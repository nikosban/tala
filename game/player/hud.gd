class_name Hud
extends Node3D
## Player HUD: selection rings under selected ships, the drag box, the help and selection line,
## and order warnings. Reads Command (and PlayerInput's box); never changes game state.

@export var command: CommandController
@export var input: PlayerInput
## Selection ring radius (u) drawn under each selected ship.
@export var ring_radius := 16.0
@export var ring_color := Color(0.4, 1.0, 0.5)
@export var box_color := Color(0.4, 1.0, 0.5, 0.15)
@export var warning_color := Color(1.0, 0.3, 0.25)
## Seconds a warning stays on screen.
@export var warning_time := 3.0

var _rings := MeshInstance3D.new()
var _ring_mesh := ImmediateMesh.new()
var _box := ColorRect.new()
var _help := Label.new()
var _warning := Label.new()
var _warning_left := 0.0


func _ready() -> void:
	_rings.top_level = true
	_rings.mesh = _ring_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = ring_color
	_rings.material_override = material
	add_child(_rings)
	var layer := CanvasLayer.new()
	add_child(layer)
	_box.color = box_color
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	layer.add_child(_box)
	_help.position = Vector2(12, 10)
	layer.add_child(_help)
	_warning.position = Vector2(12, 40)
	_warning.add_theme_color_override(&"font_color", warning_color)
	_warning.visible = false
	layer.add_child(_warning)
	if input != null:
		input.box_changed.connect(_on_box_changed)
	if command != null:
		command.selection_changed.connect(_on_selection_changed)
		command.order_rejected.connect(_warn.bind("rejected: no free spot or route"))
		command.order_failed.connect(_warn.bind("failed: route blocked, no way through"))
		_on_selection_changed(command.selected())


func _process(delta: float) -> void:
	_warning_left -= delta
	_warning.visible = _warning_left > 0.0
	_draw_rings()


func _draw_rings() -> void:
	_rings.global_transform = Transform3D.IDENTITY
	_ring_mesh.clear_surfaces()
	if command == null:
		return
	var ships := command.selected()
	if ships.is_empty():
		return
	_ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var segments := 32
	for ship in ships:
		var c: Vector3 = (ship as Node3D).global_position + Vector3.UP * 0.5
		for i in segments:
			var a := TAU * i / segments
			var b := TAU * (i + 1) / segments
			_ring_mesh.surface_add_vertex(c + Vector3(cos(a), 0, sin(a)) * ring_radius)
			_ring_mesh.surface_add_vertex(c + Vector3(cos(b), 0, sin(b)) * ring_radius)
	_ring_mesh.surface_end()


func _on_box_changed(rect: Rect2, visible_now: bool) -> void:
	_box.position = rect.position
	_box.size = rect.size
	_box.visible = visible_now


func _on_selection_changed(ships: Array[Object]) -> void:
	var names := PackedStringArray()
	for ship in ships:
		names.append((ship as Node).name)
	var selected := ", ".join(names) if not names.is_empty() else "none"
	_help.text = "Selected: %s   |   %s" % [selected, PlayerInput.HELP]


func _warn(ship: ShipBase, _destination: Vector3, reason: String) -> void:
	_warning.text = "%s order %s" % [ship.name, reason]
	_warning_left = warning_time
