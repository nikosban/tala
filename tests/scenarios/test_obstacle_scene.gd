extends RefCounted
## Scene tests with real frigates and obstacles: routing, re-planning, unavoidable contact,
## destination resolution and rejection. Thresholds derive from the profiles.

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")
const OBSTACLE := preload("res://game/world/obstacles/obstacle.tscn")

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")
var nav: NavigatorProfile = load("res://game/ship/classes/frigate/frigate_navigator.tres")


## Waits a frame first so worlds queued for deletion by earlier tests are gone.
func _world(t: TestContext) -> Node3D:
	await t.tree.process_frame
	var world := Node3D.new()
	t.tree.root.add_child(world)
	return world


func _spawn(world: Node3D, position: Vector3, heading: float, speed: float = 0.0) -> ShipBase:
	var ship: ShipBase = FRIGATE.instantiate()
	world.add_child(ship)
	ship.movement.reset_motion(position, heading, speed)
	return ship


func _rock(world: Node3D, position: Vector3, radius: float) -> Obstacle:
	var rock: Obstacle = OBSTACLE.instantiate()
	rock.radius = radius
	rock.position = position
	world.add_child(rock)
	return rock


func _order_now(ship: ShipBase, destination: Vector3) -> void:
	ship.movement.issue_move_order(destination)


func _wait_until(t: TestContext, condition: Callable, limit_s: float) -> bool:
	var frames := int(limit_s * Engine.physics_ticks_per_second)
	for i in frames:
		await t.tree.physics_frame
		if condition.call():
			return true
	return false


func _limit(distance: float) -> float:
	return distance / (p.top_speed * 0.25) + 2.0 * (p.top_speed / p.acceleration + p.top_speed / p.braking) + 60.0


func test_routes_around_rock_without_waiting(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	_rock(world, Vector3(0, 0, -200), 30.0)
	var destination := Vector3(0, 0, -400)
	_order_now(ship, destination)
	var waited := [false]
	var arrived: bool = await _wait_until(t, func() -> bool:
		if ship.movement.get_state() == MovementCore.State.WAITING:
			waited[0] = true
		return ship.movement.get_state() == MovementCore.State.IDLE, _limit(400.0))
	t.check(arrived, "ship arrives")
	t.check(not waited[0], "a rock never counts as a ship in the way")
	t.check(ship.movement.contact_count == 0, "no contact")
	t.at_most(ship.global_position.distance_to(destination), p.arrival_tolerance, "final position error (u)")
	world.queue_free()


func test_replans_when_rock_appears_on_route(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	var destination := Vector3(0, 0, -700)
	_order_now(ship, destination)
	await _wait_until(t, func() -> bool: return ship.global_position.z < -100.0, _limit(100.0))
	_rock(world, Vector3(0, 0, -450), 25.0)
	var arrived: bool = await _wait_until(t, func() -> bool:
		return ship.movement.get_state() == MovementCore.State.IDLE, _limit(700.0))
	t.check(arrived, "ship re-plans and arrives")
	t.check(ship.movement.contact_count == 0, "no contact")
	t.at_most(ship.global_position.distance_to(destination), p.arrival_tolerance, "final position error (u)")
	world.queue_free()


func test_unavoidable_rock_contact_keeps_order(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship := _spawn(world, Vector3.ZERO, 0.0, p.top_speed)
	# Rock edge 2 u ahead of the bow at top speed: contact cannot be avoided.
	_rock(world, Vector3(0, 0, -(10.0 + 2.0 + 10.0)), 10.0)
	_order_now(ship, Vector3(0, 0, -1000))
	var touched: bool = await _wait_until(t, func() -> bool: return ship.movement.contact_count > 0, 5.0)
	t.check(touched, "contact happens")
	await _wait_until(t, func() -> bool: return false, 1.0)
	t.check(ship.movement.get_active_destination() != null, "order stays active after contact")
	world.queue_free()


func test_blocked_destination_moves_to_nearest_free_spot(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	_rock(world, Vector3(0, 0, -300), 30.0)
	await t.tree.physics_frame
	var edge := 30.0 + ship.navigator.get_clearance()
	var shift := nav.max_destination_displacement * 0.5
	var requested := Vector3(0, 0, -300 + edge - shift)
	var resolved: Variant = ship.movement.resolve_move_order(requested)
	t.check(resolved != null, "order accepted")
	if resolved != null:
		t.near((resolved as Vector3).distance_to(requested), shift, 0.05, "moved to the clearance edge (u)")
	world.queue_free()


func test_unreachable_destination_is_rejected(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	_rock(world, Vector3(0, 0, -300), 60.0)
	await t.tree.physics_frame
	var first := Vector3(200, 0, 0)
	_order_now(ship, first)
	await t.tree.physics_frame
	var rejected: Array[Vector3] = []
	ship.movement.order_rejected.connect(func(d: Vector3) -> void: rejected.append(d))
	ship.movement.issue_move_order(Vector3(0, 0, -300))
	t.check(rejected.size() == 1, "order_rejected emitted")
	t.check(ship.movement.get_active_destination() == first, "previous order keeps running")
	world.queue_free()
