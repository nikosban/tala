extends RefCounted
## Scene tests for the Player camera and HUD: the camera orbits the screen-centre focus at 45°,
## follow tracks the selection and stops on panning or an empty selection; the HUD draws marks
## for the selection and shows the newest order's destination (waiting first, then active).

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")


func _world(t: TestContext) -> Node3D:
	await t.tree.process_frame
	var world := Node3D.new()
	t.tree.root.add_child(world)
	return world


func _setup(world: Node3D, at: Vector3 = Vector3.ZERO) -> Array:
	var command := CommandController.new()
	world.add_child(command)
	var ship: ShipBase = FRIGATE.instantiate()
	world.add_child(ship)
	ship.movement.reset_motion(at, 0.0, 0.0)
	ship.global_position = at
	command.register_ship(ship)
	var camera := RtsCamera.new()
	camera.command = command
	world.add_child(camera)
	return [command, ship, camera]


func test_camera_orbits_focus_at_45(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var camera: RtsCamera = _setup(world)[2]
	camera.focus = Vector3(50, 0, -30)
	for angle in [0.0, 0.7, -2.0]:
		camera.rotate_by(angle)
		var forward := -camera.global_transform.basis.z
		t.near(rad_to_deg(asin(-forward.y)), 45.0, 0.01, "pitch")
		var to_focus := (camera.focus - camera.global_position).normalized()
		t.check(forward.dot(to_focus) > 0.9999, "focus stays at the screen centre")
		t.near(camera.global_position.distance_to(camera.focus), camera.distance, 0.01, "orbit distance")
	world.queue_free()


func test_pan_is_view_relative(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var camera: RtsCamera = _setup(world)[2]
	camera.rotate_by(PI * 0.5)
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	var before := camera.focus
	camera.pan_by(Vector2(0, -1), 0.1)
	var moved := (camera.focus - before).normalized()
	t.check(moved.dot(forward.normalized()) > 0.999, "W pans toward where the camera looks")
	world.queue_free()


func test_follow_tracks_selection_and_stops(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var parts := _setup(world, Vector3(120, 0, -80))
	var command: CommandController = parts[0]
	var ship: ShipBase = parts[1]
	var camera: RtsCamera = parts[2]
	camera.set_follow(true)
	t.check(not camera.is_following(), "follow needs a selection")
	command.select([ship])
	camera.set_follow(true)
	t.check(camera.is_following(), "F with a selection follows")
	for i in 120:
		await t.tree.process_frame
	t.check(camera.focus.distance_to(Vector3(120, 0, -80)) < 1.0, "focus reaches the selected ship")
	camera.pan_by(Vector2(1, 0), 0.016)
	t.check(not camera.is_following(), "panning stops follow")
	camera.set_follow(true)
	command.clear()
	await t.tree.process_frame
	t.check(not camera.is_following(), "empty selection stops follow")
	world.queue_free()


func test_hull_length(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var ship: ShipBase = _setup(world)[1]
	t.near(ship.get_hull_length(), 20.0, 0.01, "frigate hull length")
	world.queue_free()


func test_hud_marks_newest_order(t: TestContext) -> void:
	var world: Node3D = await _world(t)
	var parts := _setup(world)
	var command: CommandController = parts[0]
	var ship: ShipBase = parts[1]
	var hud := Hud.new()
	hud.command = command
	world.add_child(hud)
	await t.tree.process_frame
	t.check(hud.get_marks_mesh().get_surface_count() == 0, "nothing drawn without a selection")
	command.select([ship])
	await t.tree.process_frame
	var ring_only: int = _vertex_count(hud)
	t.check(ring_only > 0, "selection ring drawn")
	var hull_bottom := ship.global_position.y + ship.get_hull_bounds().position.y
	var vertices := hud.get_marks_mesh().surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	t.check(Array(vertices).all(func(v: Vector3) -> bool: return v.y < hull_bottom),
			"HUD marks lie below the hull, not through it")
	var target := Vector3(0, 0, -200)
	command.order_ship(ship, target)
	t.check(command.get_pending_destination(ship) != null, "order waits out the delay")
	t.check((command.get_order_destination(ship) as Vector3).distance_to(target) < 0.01,
			"newest destination is the waiting order")
	await t.tree.process_frame
	t.check(_vertex_count(hud) > ring_only,
			"trajectory and destination mark drawn for the waiting order")
	for i in ceili(command.profile.order_delay * 60.0) + 10:
		await t.tree.physics_frame
	t.check(command.get_pending_destination(ship) == null, "order delivered")
	var active: Variant = command.get_order_destination(ship)
	t.check(active != null and (active as Vector3).distance_to(target) < 0.01,
			"newest destination is the active order after the delay")
	world.queue_free()


func _vertex_count(hud: Hud) -> int:
	var mesh := hud.get_marks_mesh()
	if mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
