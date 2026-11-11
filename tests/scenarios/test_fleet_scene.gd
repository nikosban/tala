extends RefCounted
## Scene tests with real frigates: right of way (the ship giving way steps aside, then resumes)
## and group orders through CommandController. Thresholds derive from the profiles.

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")
const OBSTACLE := preload("res://game/world/obstacles/obstacle.tscn")

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")


## Waits a frame first so worlds queued for deletion by earlier tests are gone.
func _world(t: TestContext) -> Node3D:
	await t.tree.process_frame
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
	return distance / (p.top_speed * 0.25) + 2.0 * (p.top_speed / p.acceleration + p.top_speed / p.braking) + 120.0


func _idle(ship: ShipBase) -> bool:
	return ship.movement.get_state() == MovementCore.State.IDLE


func _yielding(ship: ShipBase) -> bool:
	return ship.movement.get_state() == MovementCore.State.YIELDING


## Lateral offset a ship giving way must reach from a frigate's line of travel.
func _required(ship: ShipBase) -> float:
	var spin := NavigatorModule.hull_spin_radius(ship.get_node("CollisionShape3D").shape)
	return 2.0 * spin + p.give_way_margin


func test_parked_ship_steps_aside(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var mover := _spawn(world, Vector3.ZERO, 0.0)
	var parked := _spawn(world, Vector3(0, 0, -200), 0.0)
	var destination := Vector3(0, 0, -400)
	_order_now(mover, destination)
	var yielded := [false]
	var done: bool = await _wait_until(t, func() -> bool:
		yielded[0] = yielded[0] or _yielding(parked)
		return _idle(mover) and _idle(parked), _limit(400.0))
	t.check(yielded[0], "the parked ship gives way")
	t.check(done, "the mover completes its order and the parked ship settles")
	t.at_most(mover.global_position.distance_to(destination), p.arrival_tolerance, "mover final position error")
	t.check(mover.movement.contact_count == 0 and parked.movement.contact_count == 0, "no contact")
	t.at_least(absf(parked.global_position.x), _required(parked) - p.arrival_tolerance,
			"parked ship ends clear of the mover's line")
	world.queue_free()


func test_head_on_resolves(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var a := _spawn(world, Vector3.ZERO, 0.0)
	var b := _spawn(world, Vector3(0, 0, -300), PI)
	var a_goal := Vector3(0, 0, -500)
	var b_goal := Vector3(0, 0, 200)
	_order_now(a, a_goal)
	_order_now(b, b_goal)
	var yielders := {}
	var done: bool = await _wait_until(t, func() -> bool:
		if _yielding(a):
			yielders[a] = true
		if _yielding(b):
			yielders[b] = true
		return _idle(a) and _idle(b), _limit(1000.0))
	t.check(yielders.size() == 1, "exactly one ship gives way (%d did)" % yielders.size())
	t.check(done, "both orders complete")
	t.at_most(a.global_position.distance_to(a_goal), p.arrival_tolerance, "a final position error")
	t.at_most(b.global_position.distance_to(b_goal), p.arrival_tolerance, "b final position error")
	t.check(a.movement.contact_count == 0 and b.movement.contact_count == 0, "no contact")
	world.queue_free()


func test_head_on_slower_ship_gives_way(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var fast := _spawn(world, Vector3.ZERO, 0.0, p.top_speed * 0.6)
	var slow := _spawn(world, Vector3(0, 0, -900), PI, p.top_speed * 0.2)
	_order_now(fast, Vector3(0, 0, -1200))
	_order_now(slow, Vector3(0, 0, 300))
	var fast_yielded := [false]
	var slow_yielded: bool = await _wait_until(t, func() -> bool:
		fast_yielded[0] = fast_yielded[0] or _yielding(fast)
		return _yielding(slow), _limit(900.0))
	t.check(slow_yielded, "the slower ship gives way")
	t.check(not fast_yielded[0], "the faster ship keeps right of way")
	var done: bool = await _wait_until(t, func() -> bool:
		return _idle(fast) and _idle(slow), _limit(1500.0))
	t.check(done, "both orders complete")
	t.check(fast.movement.contact_count == 0 and slow.movement.contact_count == 0, "no contact")
	world.queue_free()


func test_steps_aside_away_from_obstacle(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var rock: Obstacle = OBSTACLE.instantiate()
	rock.radius = 15.0
	rock.position = Vector3(40, 0, -200)
	world.add_child(rock)
	var mover := _spawn(world, Vector3.ZERO, 0.0)
	var parked := _spawn(world, Vector3(0, 0, -200), 0.0)
	_order_now(mover, Vector3(0, 0, -400))
	var done: bool = await _wait_until(t, func() -> bool:
		return _idle(mover) and _idle(parked), _limit(400.0))
	t.check(done, "the mover completes and the parked ship settles")
	t.check(parked.global_position.x < 0.0, "the parked ship steps to the side without the rock")
	t.check(mover.movement.contact_count == 0 and parked.movement.contact_count == 0, "no contact")
	world.queue_free()


func test_order_delay_keeps_previous_order(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var command := CommandController.new()
	world.add_child(command)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	command.register_ship(ship)
	var first := Vector3(0, 0, -2000)
	_order_now(ship, first)
	for i in 30:
		await t.tree.physics_frame
	var second := Vector3(800, 0, -600)
	var activated := [false]
	ship.movement.order_activated.connect(func(_d: Vector3) -> void: activated[0] = true)
	command.order_ship(ship, second)
	t.check(command.get_pending_destination(ship) == second, "the new order waits in Command")
	var previous_ok := [true]
	var time := [0.0]
	var done: bool = await _wait_until(t, func() -> bool:
		if activated[0]:
			return true
		time[0] += 1.0 / Engine.physics_ticks_per_second
		previous_ok[0] = previous_ok[0] and ship.movement.get_active_destination() == first
		return false, command.profile.order_delay + 1.0)
	t.check(done, "the new order reaches the ship")
	t.check(previous_ok[0], "the previous order runs during the delay")
	t.near(time[0], command.profile.order_delay, 2.0 / Engine.physics_ticks_per_second + 1e-6,
			"order delay (s)")
	t.check(ship.movement.get_active_destination() == second, "the new order is active")
	t.check(command.get_pending_destination(ship) == null, "nothing waits in Command")
	world.queue_free()


func test_group_order_keeps_layout(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var command := CommandController.new()
	world.add_child(command)
	var starts := [Vector3(-80, 0, 0), Vector3(0, 0, 0), Vector3(80, 0, 0)]
	var ships: Array[ShipBase] = []
	for start in starts:
		var ship := _spawn(world, start, 0.0)
		command.register_ship(ship)
		ships.append(ship)
	command.select(ships)
	var target := Vector3(100, 0, -500)
	command.order_selection(target)
	# Orders wait out the order delay in Command first; the ships are idle meanwhile.
	var done: bool = await _wait_until(t, func() -> bool:
		return ships.all(func(s: ShipBase) -> bool:
			return _idle(s) and command.get_pending_destination(s) == null), _limit(520.0))
	t.check(done, "every ship completes its order")
	for i in ships.size():
		var slot: Vector3 = target + (starts[i] as Vector3)
		t.at_most(ships[i].global_position.distance_to(slot), p.arrival_tolerance,
				"ship %d final position error" % i)
		t.check(ships[i].movement.contact_count == 0, "ship %d no contact" % i)
	world.queue_free()


func test_command_relays_rejected_order(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var rock: Obstacle = OBSTACLE.instantiate()
	rock.radius = 60.0
	rock.position = Vector3(0, 0, -300)
	world.add_child(rock)
	var command := CommandController.new()
	world.add_child(command)
	var ship := _spawn(world, Vector3.ZERO, 0.0)
	command.register_ship(ship)
	await t.tree.physics_frame
	var rejected := []
	command.order_rejected.connect(func(s: ShipBase, d: Vector3) -> void: rejected.append([s, d]))
	var destination := Vector3(0, 0, -300)
	command.order_ship(ship, destination)
	t.check(rejected.size() == 1, "Command relays order_rejected once")
	t.check(rejected.size() == 1 and rejected[0][0] == ship and rejected[0][1] == destination,
			"with the ship and the destination")
	t.check(command.get_pending_destination(ship) == null, "nothing waits in Command")
	world.queue_free()


func test_command_selection_signals(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var command := CommandController.new()
	world.add_child(command)
	var a := _spawn(world, Vector3(-50, 0, 0), 0.0)
	var b := _spawn(world, Vector3(50, 0, 0), 0.0)
	command.register_ship(a)
	command.register_ship(b)
	var seen := []
	command.selection_changed.connect(func(ships: Array[Object]) -> void: seen.append(ships))
	command.select([a, b])
	command.assign_group(2)
	command.clear()
	command.recall_group(2)
	t.check(seen.size() == 3, "select, clear and recall each report the selection (%d)" % seen.size())
	t.check(seen.size() == 3 and seen[2] == [a, b], "recall reports the group")
	t.check(command.get_ships() == [a, b], "registered ships")
	world.queue_free()
