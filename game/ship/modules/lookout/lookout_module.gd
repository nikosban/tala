class_name LookoutModule
extends Node
## The ship's lookout: all sensing. Reports known obstacles, the ship in the way and free
## distances. Measures only; makes no movement decisions and holds no tuning.
## Must be a direct child of a CharacterBody3D that has a CollisionShape3D child.
## Plane coordinates: Vector2 x -> world X, y -> world Z.

## Physics layer 1 ("ships"). The ship probe ignores obstacles on layer 2.
const SHIPS_LAYER_BIT := 1 << 0
## Physics layer 2 ("obstacles").
const OBSTACLES_LAYER_BIT := 1 << 1

var _body: CharacterBody3D
var _shape: CollisionShape3D


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	assert(_body != null, "LookoutModule must be a child of a CharacterBody3D")
	for child in _body.get_children():
		if child is CollisionShape3D:
			_shape = child
			break


## Known obstacles as circles Vector3(x, z, radius + inflate) on the plane.
func get_obstacles(inflate: float) -> Array[Vector3]:
	var circles: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group(Obstacle.GROUP):
		var obstacle := node as Obstacle
		if obstacle != null:
			var p := obstacle.global_position
			circles.append(Vector3(p.x, p.z, obstacle.radius + inflate))
	return circles


## The first ship the hull would touch travelling `length` along `direction`, or null if clear.
## Obstacles never count as traffic.
func ship_in_the_way(direction: Vector2, length: float) -> ShipContact:
	var query := _hull_query(direction, length, SHIPS_LAYER_BIT)
	if query == null:
		return null
	var space := _body.get_world_3d().direct_space_state
	var result := space.cast_motion(query)
	if result.is_empty() or result[1] >= 1.0:
		return null
	# Identify the ship at the first touching position.
	query.transform.origin += query.motion * result[1]
	query.motion = Vector3.ZERO
	var info := space.get_rest_info(query)
	var ship: CharacterBody3D = null
	if not info.is_empty():
		ship = instance_from_id(info.collider_id) as CharacterBody3D
	return ShipContact.new(result[0] * length, ship)


## Distance (u) the hull can travel along direction before touching a ship or an obstacle,
## INF if clear within length.
func free_distance(direction: Vector2, length: float) -> float:
	var query := _hull_query(direction, length, SHIPS_LAYER_BIT | OBSTACLES_LAYER_BIT)
	if query == null:
		return INF
	var result := _body.get_world_3d().direct_space_state.cast_motion(query)
	if result.is_empty() or result[1] >= 1.0:
		return INF
	return result[0] * length


func _hull_query(direction: Vector2, length: float, mask: int) -> PhysicsShapeQueryParameters3D:
	if _shape == null or _shape.shape == null:
		return null
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape.shape
	query.transform = _shape.global_transform
	query.motion = Vector3(direction.x, 0.0, direction.y) * length
	query.exclude = [_body.get_rid()]
	query.collision_mask = mask
	return query
