class_name Obstacle
extends StaticBody3D
## A round obstacle (asteroid-like) on the tactical plane. Owns its body and size only;
## the Lookout module reads its position and radius. Collider and mesh are built from radius.

const GROUP := &"obstacles"
## Physics layer 2 ("obstacles"). Ships are on layer 1 and collide with both.
const LAYER_BIT := 1 << 1
## Collider height (u); only the footprint on the plane matters.
const HEIGHT := 20.0

## Radius (u) of the obstacle's footprint on the plane.
@export var radius: float = 20.0


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_BIT
	collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.4, 0.36)
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	add_child(visual)
