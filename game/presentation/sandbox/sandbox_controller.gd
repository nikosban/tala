extends Node3D
## Movement sandbox (project main scene). Composition only: builds the world (obstacles, grid),
## the ships, Command (CommandController), the Player layer (PlayerInput, RtsCamera, Hud) and
## DebugTools (all debug visuals, toggled with F4).

const FRIGATE := preload("res://game/ship/classes/frigate/frigate.tscn")
const OBSTACLE := preload("res://game/world/obstacles/obstacle.tscn")

@export var spawn_points: Array[Vector3] = [
	Vector3(-80, 0, 0), Vector3(0, 0, 0), Vector3(80, 0, 0),
	Vector3(-40, 0, 60), Vector3(40, 0, 60),
]
## Obstacles as Vector3(x, z, radius): a single rock, a pair too narrow to pass between,
## a pair wide enough to pass between, and a small field.
@export var obstacles: Array[Vector3] = [
	Vector3(0, -260, 30),
	Vector3(-250, -200, 25), Vector3(-180, -200, 25),
	Vector3(220, -220, 20), Vector3(320, -220, 20),
	Vector3(-60, -560, 15), Vector3(30, -620, 20), Vector3(110, -540, 12), Vector3(-10, -720, 18),
]

@onready var _camera: RtsCamera = $Camera

var _ships: Array[ShipBase] = []
var _command := CommandController.new()
var _input := PlayerInput.new()
var _hud := Hud.new()
var _debug := DebugTools.new()


func _ready() -> void:
	for spec in obstacles:
		var obstacle: Obstacle = OBSTACLE.instantiate()
		obstacle.radius = spec.z
		obstacle.position = Vector3(spec.x, 0.0, spec.y)
		add_child(obstacle)
	add_child(_command)
	_input.command = _command
	_input.camera = _camera
	add_child(_input)
	_debug.command = _command
	add_child(_debug)
	for point in spawn_points:
		var ship: ShipBase = FRIGATE.instantiate()
		ship.position = point
		add_child(ship)
		_ships.append(ship)
		_command.register_ship(ship)
		_debug.track_ship(ship)
	_hud.command = _command
	_hud.input = _input
	add_child(_hud)
	_command.select([_ships[0]])
	_draw_grid()


func _draw_grid() -> void:
	var grid := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.3, 0.4)
	grid.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var extent := 3000.0
	var step := 100.0
	var x := -extent
	while x <= extent:
		grid.surface_add_vertex(Vector3(x, -1, -extent))
		grid.surface_add_vertex(Vector3(x, -1, extent))
		grid.surface_add_vertex(Vector3(-extent, -1, x))
		grid.surface_add_vertex(Vector3(extent, -1, x))
		x += step
	grid.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = grid
	add_child(instance)
