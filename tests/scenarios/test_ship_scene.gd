extends RefCounted
## Scene tests with real frigate scenes and physics frames: traffic waiting and contact.
## Thresholds derive from the profile. Right of way is covered by test_fleet_scene.gd.

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")
const OBSTACLE := preload("res://game/world/obstacles/obstacle.tscn")

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")
var targets: MovementFeelTargets = load("res://game/ship/classes/frigate/frigate_feel_targets.tres")


func _world(t: TestContext) -> Node3D:
	var world := Node3D.new()
	t.tree.root.add_child(world)
	return world


func _spawn(world: Node3D, position: Vector3, heading: float, speed: float = 0.0) -> ShipBase:
	var ship: ShipBase = FRIGATE.instantiate()
	# Placed before entering the tree, so no two ships ever overlap at the origin.
	ship.position = position
	world.add_child(ship)
	ship.movement.reset_motion(position, heading, speed)
	return ship


## Issues an order that activates on the next tick.
func _order_now(ship: ShipBase, destination: Vector3) -> void:
	ship.movement.issue_move_order(destination)


func _gap(a: ShipBase, b: ShipBase) -> float:
	return a.global_position.distance_to(b.global_position) - targets.hull_length


## Awaits physics frames until condition() is true or the simulated time limit passes.
func _wait_until(t: TestContext, condition: Callable, limit_s: float) -> bool:
	var frames := int(limit_s * Engine.physics_ticks_per_second)
	for i in frames:
		await t.tree.physics_frame
		if condition.call():
			return true
	return false


func _limit() -> float:
	return 2.0 * (p.top_speed / p.acceleration + p.top_speed / p.braking) + 60.0


func test_waits_for_ship_in_the_way_then_resumes(t: TestContext) -> void:
	var world := _world(t)
	var mover := _spawn(world, Vector3.ZERO, 0.0)
	var blocker := _spawn(world, Vector3(0, 0, -200), 0.0)
	# Rocks on both sides leave the blocker no room to step aside, so the mover waits.
	for x in [-35.0, 35.0]:
		var rock: Obstacle = OBSTACLE.instantiate()
		rock.radius = 10.0
		rock.position = Vector3(x, 0, -200)
		world.add_child(rock)
	var destination := Vector3(0, 0, -400)
	_order_now(mover, destination)
	var waited: bool = await _wait_until(t, func() -> bool:
		return mover.movement.get_state() == MovementCore.State.WAITING, _limit())
	t.check(waited, "mover reaches the waiting state")
	t.check(mover.movement.contact_count == 0, "no contact while stopping for the blocker")
	t.at_least(_gap(mover, blocker), 0.0, "gap to blocker (u)")
	blocker.movement.reset_motion(Vector3(400, 0, -200), 0.0)
	var arrived: bool = await _wait_until(t, func() -> bool:
		return mover.movement.get_state() == MovementCore.State.IDLE, _limit() + 400.0 / p.top_speed * 2.0)
	t.check(arrived, "mover resumes and completes once the way is clear")
	t.at_most(mover.global_position.distance_to(destination), p.arrival_tolerance, "final position error")
	world.queue_free()


func test_contact_loses_speed_and_keeps_order(t: TestContext) -> void:
	var world := _world(t)
	var mover := _spawn(world, Vector3.ZERO, 0.0, p.top_speed)
	# Obstacle appears 1 u ahead of the bow: too close to stop, contact is unavoidable.
	var bow_gap := 1.0
	_spawn(world, Vector3(0, 0, -(targets.hull_length + bow_gap)), 0.0)
	_order_now(mover, Vector3(0, 0, -1000))
	var speeds: Array[float] = []
	var touched: bool = await _wait_until(t, func() -> bool:
		speeds.append(mover.movement._core.motion.speed)
		return mover.movement.contact_count > 0, 5.0)
	t.check(touched, "contact happens")
	if speeds.size() >= 2:
		var before := speeds[speeds.size() - 2]
		var after := speeds[speeds.size() - 1]
		t.at_most(after, before * (1.0 - p.contact_speed_loss) + 1e-4, "speed after contact")
	t.check(mover.movement.get_active_destination() != null, "order stays active after contact")
	world.queue_free()
