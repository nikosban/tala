class_name DebugTools
extends Node3D
## Debug tooling (Presentation, reads only): owns every debug visual and toggles them all with
## one key (F4), hidden at start. World: the reference grid and the info line (selection and
## key bindings). Per tracked ship: the movement overlay (route, corridor, steer arc, stop point,
## turning circles, give-way point, state label; the first ship also draws the obstacle
## keep-out circles) and the active (green) and pending (yellow) destination markers.
## Reads ShipBase.get_debug_info() / get_active_destination() and CommandController
## (selection, get_pending_destination()); changes no game state.

const MARKER := preload("res://game/presentation/debug/destination_marker.tscn")
const DEBUG_DRAW := preload("res://game/presentation/debug/movement_debug_draw.gd")

## Source of the selection (info line) and pending (delayed) orders (yellow markers). Optional.
@export var command: CommandController
## Whether the debug visuals start visible.
@export var enabled := false
@export var toggle_key: Key = KEY_F4
@export var pending_color := Color(1.0, 0.85, 0.2)
@export var grid_color := Color(0.25, 0.3, 0.4)
## Grid half-size and line spacing (u).
@export var grid_extent := 3000.0
@export var grid_step := 100.0

## Holds every debug visual; hidden and not processed while disabled.
var _layers := Node3D.new()
## Screen-space debug text; CanvasLayer visibility does not follow _layers, so it is set too.
var _canvas := CanvasLayer.new()
var _info := Label.new()
var _tracked := {}  # ShipBase -> [overlay, active marker, pending marker]


func _ready() -> void:
	_layers.name = "Layers"
	add_child(_layers)
	_layers.add_child(_build_grid())
	_info.position = Vector2(12, 10)
	_canvas.add_child(_info)
	_layers.add_child(_canvas)
	if command != null:
		command.selection_changed.connect(_on_selection_changed)
	_on_selection_changed(command.selected() if command != null else [])
	set_enabled(enabled)


func track_ship(ship: ShipBase) -> void:
	if _tracked.has(ship):
		return
	var overlay := DEBUG_DRAW.new()
	overlay.ship = ship
	overlay.draw_clearance = _tracked.is_empty()
	var active: MeshInstance3D = MARKER.instantiate()
	var pending: MeshInstance3D = MARKER.instantiate()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = pending_color
	pending.material_override = material
	for node: Node in [overlay, active, pending]:
		_layers.add_child(node)
	_tracked[ship] = [overlay, active, pending]


func set_enabled(on: bool) -> void:
	enabled = on
	_layers.visible = on
	_canvas.visible = on
	_layers.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func is_enabled() -> bool:
	return enabled


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == toggle_key:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	for ship: Variant in _tracked.keys():
		var nodes: Array = _tracked[ship]
		if not is_instance_valid(ship):
			for node: Node in nodes:
				node.queue_free()
			_tracked.erase(ship)
			continue
		if not enabled:
			continue
		_place_marker(nodes[1], (ship as ShipBase).get_active_destination())
		_place_marker(nodes[2], command.get_pending_destination(ship) if command != null else null)


func _place_marker(marker: MeshInstance3D, destination: Variant) -> void:
	marker.visible = destination != null
	if destination != null:
		marker.global_position = destination


func _on_selection_changed(ships: Array) -> void:
	var names := PackedStringArray()
	for ship in ships:
		names.append((ship as Node).name)
	var selected := ", ".join(names) if not names.is_empty() else "none"
	_info.text = "Selected: %s   |   %s" % [selected, PlayerInput.HELP]


func _build_grid() -> MeshInstance3D:
	var grid := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = grid_color
	grid.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var x := -grid_extent
	while x <= grid_extent:
		grid.surface_add_vertex(Vector3(x, -1, -grid_extent))
		grid.surface_add_vertex(Vector3(x, -1, grid_extent))
		grid.surface_add_vertex(Vector3(-grid_extent, -1, x))
		grid.surface_add_vertex(Vector3(grid_extent, -1, x))
		x += grid_step
	grid.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "Grid"
	instance.mesh = grid
	return instance
