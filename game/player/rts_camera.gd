class_name RtsCamera
extends Camera3D
## Player camera: angled top-down. WASD / arrows pan, mouse wheel zooms.

@export var focus := Vector3.ZERO
@export var distance := 400.0
@export var min_distance := 40.0
@export var max_distance := 3000.0
@export var pitch_deg := 60.0
@export var pan_speed_per_distance := 1.0


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
		focus += Vector3(pan.x, 0.0, pan.y).normalized() * distance * pan_speed_per_distance * delta
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.9)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance * 1.1)
			_apply()


func _apply() -> void:
	var pitch := deg_to_rad(pitch_deg)
	global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	look_at(focus, Vector3.UP)
