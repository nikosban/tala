class_name NavigatorCore
extends RefCounted
## Scene-free navigation for one ship: destination checks, the route and its upkeep.
## NavigatorModule wraps this with the scene (Lookout, hull size).

var profile: NavigatorProfile
## Distance (u) kept between an obstacle's edge and the ship's centre: spin radius + margin.
var clearance := 0.0
var route: Route

var _check_left := 0.0
## Keep-out circles from the latest plan or check.
var _circles: Array[Vector3] = []


func _init(p: NavigatorProfile, hull_spin_radius: float) -> void:
	assert(p != null, "NavigatorCore needs a NavigatorProfile")
	profile = p
	clearance = hull_spin_radius + p.obstacle_margin


## The goal, or the nearest free spot within the allowed displacement, if a route to it exists
## from `from`; otherwise null. circles are already inflated by clearance.
func resolve_destination(from: Vector2, goal: Vector2, circles: Array[Vector3]) -> Variant:
	var resolved: Variant = RoutePlanner.resolve_destination(goal, circles, profile.max_destination_displacement)
	if resolved == null or RoutePlanner.plan(from, resolved, circles) == null:
		return null
	return resolved


## Plans a new route. False when no route exists.
## travel_direction / turn_radius: the ship's motion now (see RoutePlanner.plan).
func start_route(from: Vector2, goal: Vector2, circles: Array[Vector3],
		travel_direction: Vector2 = Vector2.ZERO, turn_radius: float = 0.0) -> bool:
	route = RoutePlanner.plan(from, goal, circles, travel_direction, turn_radius)
	_circles = circles
	_check_left = profile.route_check_interval
	return route != null


## Advances along the route, re-checks it every route_check_interval (re-planning from the
## current position when it is blocked or the ship has strayed outside the corridor) and
## returns guidance, or null when no route remains.
## obstacles: Callable returning the current inflated circles (Array[Vector3]).
func update(dt: float, position: Vector2, obstacles: Callable,
		travel_direction: Vector2 = Vector2.ZERO, turn_radius: float = 0.0) -> Guidance:
	if route == null:
		return null
	route.advance(position, profile.steer_lookahead)
	_check_left -= dt
	if _check_left <= 0.0:
		_check_left = profile.route_check_interval
		var circles: Array[Vector3] = obstacles.call()
		_circles = circles
		var ahead := route.remaining_points()
		# A leg that starts inside a circle (leading out after a contact) is not re-checked.
		if not CircleGeometry.point_free(ahead[0], circles):
			ahead = ahead.slice(1)
		# A ship that swung outside the corridor (e.g. carried wide by its momentum) gets a
		# route from where it is now.
		var strayed := CircleGeometry.point_free(position, circles) \
				and Corridor.new(route.remaining_points(), circles, profile.corridor_half_width) \
						.distance_to_centreline(position) > profile.corridor_half_width
		if strayed or not CircleGeometry.polyline_clear(ahead, circles):
			route = RoutePlanner.plan(position, route.goal(), circles, travel_direction, turn_radius)
			if route == null:
				return null
			route.advance(position, profile.steer_lookahead)
	return route.guidance(_circles, profile.corridor_half_width)


func clear() -> void:
	route = null
