extends RefCounted
## Navigator rules: route planning around circles, destination resolution, route progress and
## guidance, plus the helm's corner speed helper. Circles are Vector3(x, y, inflated radius).

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")
var nav: NavigatorProfile = load("res://game/ship/classes/frigate/frigate_navigator.tres")


func _circles(list: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.assign(list)
	return out


func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func test_clear_line_is_direct(t: TestContext) -> void:
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -200), _circles([Vector3(100, -100, 30)]))
	t.check(route != null, "route found")
	t.check(route.points.size() == 2, "direct route has start and goal only")


func test_route_goes_around_circle(t: TestContext) -> void:
	var circles := _circles([Vector3(5, -100, 30)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -200), circles)
	t.check(route != null, "route found")
	if route == null:
		return
	t.check(CircleGeometry.polyline_clear(route.points, circles), "route never enters the circle")
	t.at_most(_length(route.points), 200.0 + PI * 30.0, "route length (u)")
	for i in range(1, route.points.size() - 1):
		t.check(route.points[i].x < 5.0, "shorter side (away from the offset centre) is used")
		t.near(route.radii[i], 30.0, 0.001, "bend radius is the circle radius")


func test_closed_gap_is_not_used(t: TestContext) -> void:
	# Overlapping inflated circles: the gap between the rocks is narrower than the clearance.
	var circles := _circles([Vector3(-25, -100, 30), Vector3(25, -100, 30)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -200), circles)
	t.check(route != null, "route found")
	if route == null:
		return
	t.check(CircleGeometry.polyline_clear(route.points, circles), "route never enters a circle")
	var widest := 0.0
	for point in route.points:
		widest = maxf(widest, absf(point.x))
	t.at_least(widest, 55.0, "route goes around the pair (u)")


func test_open_gap_is_used(t: TestContext) -> void:
	var circles := _circles([Vector3(-50, -100, 30), Vector3(50, -100, 30)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -200), circles)
	t.check(route != null and route.points.size() == 2, "straight through the gap")


func test_enclosed_goal_has_no_route(t: TestContext) -> void:
	var ring: Array[Vector3] = []
	for k in 12:
		var at := Vector2(0, -300) + Vector2.from_angle(TAU * k / 12.0) * 60.0
		ring.append(Vector3(at.x, at.y, 20))
	t.check(RoutePlanner.plan(Vector2.ZERO, Vector2(0, -300), ring) == null, "no route into a closed ring")


func test_start_inside_circle_leads_out(t: TestContext) -> void:
	var circles := _circles([Vector3(0, -20, 30)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, 200), circles)
	t.check(route != null, "route found")
	if route != null:
		t.check(CircleGeometry.point_free(route.points[1], circles), "first point leads out of the circle")
		t.check(CircleGeometry.polyline_clear(route.points.slice(1), circles), "rest of the route is clear")


func test_destination_resolution(t: TestContext) -> void:
	var circles := _circles([Vector3(0, -100, 30)])
	var free := Vector2(100, 0)
	t.check(RoutePlanner.resolve_destination(free, circles, nav.max_destination_displacement) == free,
			"free goal is kept")
	var inside := Vector2(0, -80)
	var resolved: Variant = RoutePlanner.resolve_destination(inside, circles, nav.max_destination_displacement)
	t.check(resolved != null, "goal near the edge is moved")
	if resolved != null:
		t.check(CircleGeometry.point_free(resolved, circles), "moved goal is free")
		t.near(inside.distance_to(resolved), 10.0, 0.05, "moved to the nearest free spot (u)")
	var deep := _circles([Vector3(0, -100, nav.max_destination_displacement + 20.0)])
	t.check(RoutePlanner.resolve_destination(Vector2(0, -100), deep, nav.max_destination_displacement) == null,
			"goal too deep inside is rejected")


func test_destination_between_overlapping_circles(t: TestContext) -> void:
	var circles := _circles([Vector3(-20, 0, 30), Vector3(20, 0, 30)])
	var resolved: Variant = RoutePlanner.resolve_destination(Vector2.ZERO, circles, 100.0)
	t.check(resolved != null and CircleGeometry.point_free(resolved, circles), "resolves to a point free of both")
	if resolved != null:
		t.near(Vector2.ZERO.distance_to(resolved), sqrt(30.0 * 30.0 - 20.0 * 20.0), 0.05, "nearest crossing point (u)")


func test_route_progress_and_guidance(t: TestContext) -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(0, -100), Vector2(50, -150), Vector2(50, -300)])
	var radii := PackedFloat32Array([INF, 40.0, 40.0, INF])
	var ids := PackedInt32Array([-1, 0, 0, -1])
	var circles := _circles([Vector3(60, -90, 40)])
	var route := Route.new(points, radii, ids, circles)
	route.advance(Vector2(0, -50), nav.steer_lookahead)
	var g := route.guidance(circles, nav.corridor_half_width)
	t.check(g.steer_point() == points[1] and g.candidates.size() == 3, "steers at the first bend; all points ahead are candidates")
	t.near(g.remaining_after, points[1].distance_to(points[2]) + 150.0, 0.001, "remaining after steer point")
	t.near(g.remaining_after_candidate(2), 0.0, 0.001, "nothing remains after the goal")
	t.check(g.is_goal(2) and not g.is_goal(0), "last candidate is the goal")
	t.check(g.bends.size() == 1, "consecutive points on one circle form one bend")
	t.check(g.corridor != null, "guidance carries the corridor")
	route.advance(Vector2(0, -100 + nav.steer_lookahead * 0.5), nav.steer_lookahead)
	t.check(route.guidance(circles, nav.corridor_half_width).steer_point() == points[2], "within lookahead: next point")
	route.advance(Vector2(60, -151), nav.steer_lookahead)
	t.check(route.is_final(), "passed point: steers at the goal")


func test_max_speed_to_reach(t: TestContext) -> void:
	t.near(PathFollower.max_speed_to_reach(p, 10.0, p.top_speed), p.top_speed, 1e-6, "no slowing needed")
	var end := p.top_speed * 0.25
	t.near(PathFollower.max_speed_to_reach(p, 0.0, end), end, 0.01, "at the bend: bend speed")
	var distance := 100.0
	var v := PathFollower.max_speed_to_reach(p, distance, end)
	t.near(PathFollower.stopping_distance(p, v) - PathFollower.stopping_distance(p, end), distance, 0.5,
			"braking from the cap to the bend speed uses the distance (u)")
