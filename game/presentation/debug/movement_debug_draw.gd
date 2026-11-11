extends MeshInstance3D
## Debug overlay for one ship: heading (blue), velocity (green), chosen steer arc (yellow),
## route (cyan) with its corridor width limit (faint cyan), stop point (red), turning circle
## (grey), the point it steps aside to while giving way (magenta) and a label with speed, state and binding limit. With draw_clearance, also each
## obstacle's keep-out circle (orange), which bounds the corridor near obstacles.
## Reads only ShipBase.get_debug_info() (the debug contract), never module internals.

var ship: ShipBase
## Draw obstacle clearance circles (enable on one overlay only).
var draw_clearance := false

var _mesh := ImmediateMesh.new()
var _label := Label3D.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material_override = material
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.05
	_label.font_size = 64
	_label.outline_size = 12
	add_child(_label)


func _process(_delta: float) -> void:
	if not is_instance_valid(ship):
		return
	global_transform = Transform3D.IDENTITY
	var debug := ship.get_debug_info()
	var info: Dictionary = debug.movement
	var nav: Dictionary = debug.navigator
	var origin := ship.global_position + Vector3.UP * 3.0
	var heading: float = info.heading
	var forward := Vector3(-sin(heading), 0.0, -cos(heading))
	var velocity: Vector3 = info.velocity

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_line(origin, origin + forward * 30.0, Color(0.3, 0.5, 1.0))
	_line(origin, origin + velocity * 5.0, Color(0.3, 1.0, 0.3))
	var arc: Array = info.steer_arc
	var previous := origin
	for point in arc:
		var p := (point as Vector3) + Vector3.UP * 3.0
		_line(previous, p, Color(1.0, 0.9, 0.2, 0.8))
		previous = p
	var route: Array = nav.route
	var half_width: float = nav.corridor_half_width
	for i in range(1, route.size()):
		var a := (route[i - 1] as Vector3) + Vector3.UP * 2.0
		var b := (route[i] as Vector3) + Vector3.UP * 2.0
		_line(a, b, Color(0.2, 0.9, 1.0, 0.8))
		# Corridor width limit (the keep-out circles bound it near obstacles).
		var side := (b - a).cross(Vector3.UP).normalized() * half_width
		_line(a + side, b + side, Color(0.2, 0.9, 1.0, 0.25))
		_line(a - side, b - side, Color(0.2, 0.9, 1.0, 0.25))
	if draw_clearance:
		for circle: Vector3 in nav.keep_out:
			_circle(Vector3(circle.x, 2.0, circle.y), circle.z, Color(1.0, 0.6, 0.2, 0.6))
	if info.give_way_point != null:
		_line(origin, (info.give_way_point as Vector3) + Vector3.UP * 3.0, Color(1.0, 0.3, 1.0))
	var stop: Vector3 = info.stop_point + Vector3.UP * 3.0
	_line(stop + Vector3(-2, 0, -2), stop + Vector3(2, 0, 2), Color(1, 0.2, 0.2))
	_line(stop + Vector3(-2, 0, 2), stop + Vector3(2, 0, -2), Color(1, 0.2, 0.2))
	var radius: float = info.turn_radius
	if radius > 0.5 and radius < 5000.0:
		var right := Vector3(cos(heading), 0.0, -sin(heading))
		for side in [-1.0, 1.0]:
			_circle(origin + right * radius * side, radius, Color(0.6, 0.6, 0.6, 0.5))
	_mesh.surface_end()

	_label.global_position = ship.global_position + Vector3.UP * 14.0
	_label.text = "%s\n%.1f u/s  rcs %.1f\nlimit: %s" % [
		String(info.state).to_lower(), info.speed, info.rcs, info.limit]


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)


func _circle(center: Vector3, radius: float, color: Color) -> void:
	var segments := 48
	for i in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		_line(center + Vector3(cos(a), 0, sin(a)) * radius, center + Vector3(cos(b), 0, sin(b)) * radius, color)
