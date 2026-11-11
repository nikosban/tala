class_name Hud
extends Node3D
## Player HUD. World meshes (fixed world size at every zoom, drawn with HudMeshes) for each
## selected ship: a selection ring under the ship, a trajectory line toward its newest order,
## and the destination mark (inner ring and an outer arc facing back toward the ship), with a
## small gap between ring, line and mark. Screen space: the drag box and order warnings.
## The selection and key-bindings info line belongs to DebugTools (F4).
## Reads Command (selection, order destinations), each ship's position and hull length, and
## PlayerInput's box; never changes game state.

@export var command: CommandController
@export var input: PlayerInput
## Neutral, translucent colour of every HUD mesh (a palette comes later).
@export var hud_color := Color(0.85, 0.88, 0.9, 0.45)
@export var box_color := Color(0.85, 0.88, 0.9, 0.12)
@export var warning_color := Color(1.0, 0.3, 0.25)
## Seconds a warning stays on screen.
@export var warning_time := 3.0
@export_group("Selection ring")
## Ring diameter as a share of the ship's hull length.
@export var ring_hull_ratio := 0.8
@export var ring_width := 0.6
@export_group("Trajectory")
@export var line_width := 0.5
## Free space (u) between the selection ring, the line and the destination mark.
@export var gap := 2.0
@export_group("Destination mark")
@export var dest_inner_radius := 3.5
@export var dest_inner_width := 0.6
@export var dest_outer_radius := 6.0
@export var dest_outer_width := 0.6
## Span of the outer arc, centred on the direction back toward the ship.
@export var dest_outer_arc_deg := 120.0
@export_group("")
## Distance (u) of the HUD plane below the bottom of the ship's hull.
@export var plane_offset := 0.05

var _marks := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _box := ColorRect.new()
var _warning := Label.new()
var _warning_left := 0.0


func _ready() -> void:
	_marks.name = "SelectionMarks"
	_marks.top_level = true
	_marks.mesh = _mesh
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = hud_color
	_marks.material_override = material
	add_child(_marks)
	var layer := CanvasLayer.new()
	add_child(layer)
	_box.color = box_color
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	layer.add_child(_box)
	_warning.position = Vector2(12, 40)
	_warning.add_theme_color_override(&"font_color", warning_color)
	_warning.visible = false
	layer.add_child(_warning)
	if input != null:
		input.box_changed.connect(_on_box_changed)
	if command != null:
		command.order_rejected.connect(_warn.bind("rejected: no free spot or route"))
		command.order_failed.connect(_warn.bind("failed: route blocked, no way through"))


func _process(delta: float) -> void:
	_warning_left -= delta
	_warning.visible = _warning_left > 0.0
	_draw_marks()


## The HUD mesh (selection rings, trajectories, destination marks) rebuilt every frame.
func get_marks_mesh() -> ImmediateMesh:
	return _mesh


func _draw_marks() -> void:
	_marks.global_transform = Transform3D.IDENTITY
	_mesh.clear_surfaces()
	if command == null:
		return
	var ships := command.selected()
	if ships.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ship: ShipBase in ships:
		_draw_ship(ship)
	_mesh.surface_end()


func _draw_ship(ship: ShipBase) -> void:
	# Everything for this ship lies on one plane just under the hull's bottom.
	var lift := Vector3.UP * (ship.get_hull_bounds().position.y - plane_offset)
	var centre := ship.global_position + lift
	var ring_radius := ship.get_hull_length() * ring_hull_ratio * 0.5
	HudMeshes.ring(_mesh, centre, ring_radius, ring_width)
	var destination: Variant = command.get_order_destination(ship)
	if destination == null:
		return
	var mark := (destination as Vector3) + lift
	var back := Vector3(centre.x - mark.x, 0.0, centre.z - mark.z)
	var facing := atan2(back.z, back.x) if back.length_squared() > 1e-6 else 0.0
	var span := deg_to_rad(dest_outer_arc_deg)
	HudMeshes.ring(_mesh, mark, dest_inner_radius, dest_inner_width)
	HudMeshes.arc(_mesh, mark, dest_outer_radius, dest_outer_width, facing - span * 0.5, span)
	var start_off := ring_radius + ring_width * 0.5 + gap
	var end_off := dest_outer_radius + dest_outer_width * 0.5 + gap
	var length := back.length()
	if length <= start_off + end_off:
		return
	var dir := back / length  # mark -> ship
	HudMeshes.strip(_mesh, centre - dir * start_off, mark + dir * end_off, line_width)


func _on_box_changed(rect: Rect2, visible_now: bool) -> void:
	_box.position = rect.position
	_box.size = rect.size
	_box.visible = visible_now


func _warn(ship: ShipBase, _destination: Vector3, reason: String) -> void:
	_warning.text = "%s order %s" % [ship.name, reason]
	_warning_left = warning_time
