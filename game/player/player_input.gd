class_name PlayerInput
extends Node
## Player input for fleet command: turns mouse and keys into Command calls. Holds no game state.
##   LMB click: select a ship (empty space clears). LMB drag: box select.
##   Shift + click / drag: add to the selection (click toggles).
##   RMB: order the selection; each ship keeps its offset from the group centre.
##   1-9: select control group. Ctrl + 1-9: assign. Shift + 1-9: add the selection to it.
## Camera panning, zoom, rotation and follow belong to RtsCamera.

## The drag box changed (screen rect); the HUD draws it.
signal box_changed(rect: Rect2, visible: bool)

const HELP := "LMB select / drag box (Shift adds)   RMB move   " \
		+ "1-9 group (Ctrl assign, Shift add)   WASD pan   wheel zoom   " \
		+ "Q/E or MMB rotate   F follow   F4 debug"

@export var command: CommandController
## Camera used to pick ships and points on the plane.
@export var camera: Camera3D
## Mouse travel (px) beyond which a left drag is a box selection rather than a click.
@export var drag_threshold_px := 6.0
## Physics layers a click picks ships on (layer 1 "ships"), so obstacles never block a pick.
@export_flags_3d_physics var pick_mask := 1

var _drag_start := Vector2.ZERO
var _dragging := false


func _unhandled_input(event: InputEvent) -> void:
	if command == null or camera == null:
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_update_box(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = event.position
			_dragging = true
			_update_box(event.position)
			return
		if not _dragging:
			return
		_dragging = false
		box_changed.emit(Rect2(), false)
		if event.position.distance_to(_drag_start) > drag_threshold_px:
			_box_select(Rect2(_drag_start, event.position - _drag_start).abs(), event.shift_pressed)
		else:
			_click_select(event.position, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var point: Variant = _mouse_on_plane(event.position)
		if point != null:
			command.order_selection(point)


func _key(event: InputEventKey) -> void:
	var n := event.keycode - KEY_0
	if n < 1 or n > CommandCore.GROUP_COUNT:
		return
	if event.ctrl_pressed:
		command.assign_group(n)
	elif event.shift_pressed:
		command.add_selection_to_group(n)
	else:
		command.recall_group(n)


func _click_select(screen: Vector2, additive: bool) -> void:
	var hit := _ship_at(screen)
	if additive:
		if hit != null:
			command.toggle(hit)
	else:
		command.select([hit] if hit != null else [])


func _box_select(rect: Rect2, additive: bool) -> void:
	var result: Array = command.selected().duplicate() if additive else []
	for ship in command.get_ships():
		if camera.is_position_behind(ship.global_position):
			continue
		if rect.has_point(camera.unproject_position(ship.global_position)) and not result.has(ship):
			result.append(ship)
	command.select(result)


func _update_box(current: Vector2) -> void:
	var rect := Rect2(_drag_start, current - _drag_start).abs()
	box_changed.emit(rect, rect.size.length() > drag_threshold_px)


func _mouse_on_plane(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, camera.project_ray_normal(screen))


func _ship_at(screen: Vector2) -> ShipBase:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin,
			origin + camera.project_ray_normal(screen) * camera.far, pick_mask)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as ShipBase if not hit.is_empty() else null
