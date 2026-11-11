class_name RtsCamera
extends Camera3D
## Player camera: orbits a focus point on the plane (the ground point at the screen centre),
## looking down at pitch_deg. WASD / arrows pan (relative to the view), mouse wheel zooms,
## Q/E or middle-mouse drag rotate around the focus. F toggles follow: the focus tracks the
## centre of the selection (read from Command) until the player pans or the selection empties.

@export var focus := Vector3.ZERO
@export var distance := 400.0
@export var min_distance := 40.0
@export var max_distance := 3000.0
@export var pitch_deg := 45.0
## View rotation around the focus (radians). 0 looks toward −Z.
@export var yaw := 0.0
@export var pan_speed_per_distance := 1.0
## Q/E rotation speed (degrees per second).
@export var rotate_speed_deg := 90.0
## Middle-mouse drag rotation (degrees per pixel of horizontal mouse travel).
@export var drag_rotate_deg_per_px := 0.3
## How quickly follow catches up with the selection (1/s; higher is snappier).
@export var follow_smoothing := 8.0
## Source of the selection to follow. Optional; without it F does nothing.
@export var command: CommandController

var _following := false
var _drag_rotating := false


func _ready() -> void:
	far = 20000.0
	_apply()


func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		pan_by(pan, delta)
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		spin -= 1.0
	if Input.is_physical_key_pressed(KEY_E):
		spin += 1.0
	if spin != 0.0:
		rotate_by(spin * deg_to_rad(rotate_speed_deg) * delta)
	if _following:
		_follow_step(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_rotating = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9)
			_apply()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)
			_apply()
	elif event is InputEventMouseMotion and _drag_rotating:
		rotate_by(event.relative.x * deg_to_rad(drag_rotate_deg_per_px))
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F:
		set_follow(not _following)
		get_viewport().set_input_as_handled()


## Pans the focus along the view (x right, y back) for delta seconds. Stops following.
func pan_by(direction: Vector2, delta: float) -> void:
	_following = false
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var move := (right * direction.x + back * direction.y).normalized()
	focus += move * distance * pan_speed_per_distance * delta
	_apply()


## Rotates the view around the focus (radians; positive turns the view to the right).
func rotate_by(angle: float) -> void:
	yaw = wrapf(yaw - angle, -PI, PI)
	_apply()


## Turns follow on (only with a non-empty selection) or off.
func set_follow(on: bool) -> void:
	_following = on and command != null and not command.selected().is_empty()


func is_following() -> bool:
	return _following


func _follow_step(delta: float) -> void:
	var ships := command.selected() if command != null else []
	if ships.is_empty():
		_following = false
		return
	var centre := Vector3.ZERO
	for ship in ships:
		centre += (ship as Node3D).global_position
	centre /= ships.size()
	centre.y = 0.0
	focus = focus.lerp(centre, 1.0 - exp(-follow_smoothing * delta))
	_apply()


func _apply() -> void:
	var pitch := deg_to_rad(pitch_deg)
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	global_position = focus + (back * cos(pitch) + Vector3.UP * sin(pitch)) * distance
	look_at(focus, Vector3.UP)
