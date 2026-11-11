class_name NavigatorModule
extends Node
## The ship's navigator: checks destinations, plans the route around obstacles and tells the
## helm where to steer. Makes no speed or turn decisions. Reads obstacles from the sibling
## Lookout. Must be a direct child of a CharacterBody3D that has a CollisionShape3D child.
## Plane coordinates: Vector2 x -> world X, y -> world Z.

@export var profile: NavigatorProfile

var _core: NavigatorCore
var _lookout: LookoutModule


func _ready() -> void:
	var body := get_parent() as CharacterBody3D
	assert(body != null, "NavigatorModule must be a child of a CharacterBody3D")
	_lookout = body.get_node_or_null("Lookout") as LookoutModule
	assert(_lookout != null, "NavigatorModule needs a sibling LookoutModule named Lookout")
	var spin_radius := 0.0
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null:
			spin_radius = hull_spin_radius(child.shape)
			break
	_core = NavigatorCore.new(profile, spin_radius)


## Radius (u) of the circle the hull sweeps when rotating about its origin on the plane.
static func hull_spin_radius(shape: Shape3D) -> float:
	var box := shape.get_debug_mesh().get_aabb()
	return Vector2(maxf(absf(box.position.x), absf(box.end.x)),
			maxf(absf(box.position.z), absf(box.end.z))).length()


## The goal, the nearest free spot within the allowed displacement, or null when the order
## cannot be completed (no free spot, or no route from `from`).
func resolve_destination(from: Vector2, goal: Vector2) -> Variant:
	return _core.resolve_destination(from, goal, _obstacles())


## Plans the route to goal. False when no route exists. travel_direction and turn_radius
## (the ship's turning radius at its current speed) let the plan favour the side the ship's
## momentum already points to.
func start_route(from: Vector2, goal: Vector2, travel_direction: Vector2 = Vector2.ZERO,
		turn_radius: float = 0.0) -> bool:
	return _core.start_route(from, goal, _obstacles(), travel_direction, turn_radius)


## Advances the route for this tick. Returns guidance (with the corridor), or null when the
## route became blocked and no new route exists (the caller fails its order).
func update(dt: float, position: Vector2, travel_direction: Vector2 = Vector2.ZERO,
		turn_radius: float = 0.0) -> Guidance:
	return _core.update(dt, position, _obstacles, travel_direction, turn_radius)


func clear_route() -> void:
	_core.clear()


## Clearance (u) kept from obstacle edges: hull spin radius + margin.
func get_clearance() -> float:
	return _core.clearance


## Snapshot for debug drawing (world coordinates). Not part of the gameplay contract.
## route: remaining route points; corridor_half_width: how far the ship's centre may stray from
## the route; clearance; keep_out: obstacle circles Vector3(x, z, radius + clearance).
func get_debug_info() -> Dictionary:
	var route: Array = []
	if _core.route != null:
		for p in _core.route.remaining_points():
			route.append(Vector3(p.x, 0.0, p.y))
	return {
		"route": route,
		"corridor_half_width": profile.corridor_half_width,
		"clearance": _core.clearance,
		"keep_out": _obstacles(),
	}


func _obstacles() -> Array[Vector3]:
	return _lookout.get_obstacles(_core.clearance)
