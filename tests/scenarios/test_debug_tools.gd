extends RefCounted
## Scene tests for DebugTools: hidden at start, F4 toggles every debug visual, markers follow
## the active order, and visuals of a freed ship are removed.

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")


func _world(t: TestContext) -> Node3D:
	await t.tree.process_frame
	var world := Node3D.new()
	t.tree.root.add_child(world)
	return world


func _f4() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_F4
	event.pressed = true
	return event


func _setup(world: Node3D) -> Array:
	var command := CommandController.new()
	world.add_child(command)
	var debug := DebugTools.new()
	debug.command = command
	world.add_child(debug)
	var ship: ShipBase = FRIGATE.instantiate()
	world.add_child(ship)
	ship.movement.reset_motion(Vector3.ZERO, 0.0, 0.0)
	command.register_ship(ship)
	debug.track_ship(ship)
	return [debug, ship, command]


func test_hidden_at_start_and_f4_toggles(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var parts := _setup(world)
	var debug: DebugTools = parts[0]
	var layers: Node3D = debug.get_node("Layers")
	t.check(not debug.is_enabled(), "debug starts disabled")
	t.check(not layers.is_visible_in_tree(), "debug visuals hidden at start")
	t.check(layers.get_child_count() == 3, "overlay and two markers per ship (got %d)" % layers.get_child_count())
	debug._unhandled_input(_f4())
	t.check(debug.is_enabled() and layers.is_visible_in_tree(), "F4 shows debug visuals")
	debug._unhandled_input(_f4())
	t.check(not debug.is_enabled() and not layers.is_visible_in_tree(), "F4 again hides them")
	world.queue_free()


func test_active_marker_follows_order(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var parts := _setup(world)
	var debug: DebugTools = parts[0]
	var ship: ShipBase = parts[1]
	debug.set_enabled(true)
	var destination := Vector3(0, 0, -200)
	ship.movement.issue_move_order(destination)
	for i in 5:
		await t.tree.physics_frame
	await t.tree.process_frame
	var active: MeshInstance3D = debug.get_node("Layers").get_child(1)
	t.check(active.visible, "active marker shown while an order is active")
	t.check(active.global_position.distance_to(destination) < 0.01, "active marker at the destination")
	world.queue_free()


func test_freed_ship_visuals_removed(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var parts := _setup(world)
	var debug: DebugTools = parts[0]
	var ship: ShipBase = parts[1]
	ship.free()
	await t.tree.process_frame
	await t.tree.process_frame
	t.check(debug.get_node("Layers").get_child_count() == 0, "visuals of a freed ship are removed")
	world.queue_free()
