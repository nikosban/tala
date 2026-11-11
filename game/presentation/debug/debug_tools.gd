class_name DebugTools
extends Node3D
## Debug tooling (Presentation, reads only): owns every debug visual and toggles them all with
## one key (F4), hidden at start. Per tracked ship: the movement overlay (route, corridor,
## steer arc, stop point, turning circles, give-way point, state label; the first ship also
## draws the obstacle keep-out circles) and the active (green) and pending (yellow)
## destination markers. Reads ShipBase.get_debug_info() / get_active_destination() and
## CommandController.get_pending_destination(); changes no game state.

const MARKER := preload("res://game/presentation/debug/destination_marker.tscn")
const DEBUG_DRAW := preload("res://game/presentation/debug/movement_debug_draw.gd")

## Source of pending (delayed) orders for the yellow markers. Optional.
@export var command: CommandController
## Whether the debug visuals start visible.
@export var enabled := false
@export var toggle_key: Key = KEY_F4
@export var pending_color := Color(1.0, 0.85, 0.2)

## Holds every debug visual; hidden and not processed while disabled.
var _layers := Node3D.new()
var _tracked := {}  # ShipBase -> [overlay, active marker, pending marker]


func _ready() -> void:
	_layers.name = "Layers"
	add_child(_layers)
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
