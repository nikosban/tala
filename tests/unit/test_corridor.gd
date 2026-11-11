extends RefCounted
## Corridor geometry, bend groups with available radius, and heading-aware side choice.
## Circles are Vector3(x, y, keep-out radius).

var nav: NavigatorProfile = load("res://game/ship/classes/frigate/frigate_navigator.tres")


func _circles(list: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.assign(list)
	return out


## Total turn (rad) over the route's points on circle `id`, computed like the Navigator does.
func _group_turn(route: Route, id: int) -> float:
	var turn := 0.0
	for i in range(1, route.points.size() - 1):
		if route.circle_ids[i] == id:
			turn += absf(angle_difference((route.points[i] - route.points[i - 1]).angle(),
					(route.points[i + 1] - route.points[i]).angle()))
	return turn


func test_contains(t: TestContext) -> void:
	var corridor := Corridor.new(PackedVector2Array([Vector2.ZERO, Vector2(0, -200)]),
			_circles([Vector3(0, -100, 30)]), 40.0)
	t.check(not corridor.contains(Vector2(0, -100)), "inside a keep-out circle is outside the corridor")
	t.check(corridor.contains(Vector2(35, -100)), "free and within the half width is inside")
	t.check(not corridor.contains(Vector2(60, -50)), "beyond the half width is outside")


func test_arc_inside(t: TestContext) -> void:
	var corridor := Corridor.new(PackedVector2Array([Vector2.ZERO, Vector2(45, -100), Vector2(0, -200)]),
			_circles([Vector3(0, -100, 30)]), 40.0)
	var forward := Vector2(0, -1)
	t.check(corridor.arc_inside(Vector2.ZERO, forward, Vector2(45, -100)), "arc to the route point clears the rock")
	t.check(not corridor.arc_inside(Vector2.ZERO, forward, Vector2(0, -200)), "line through the rock is rejected")
	var arc := Corridor.arc_points(Vector2.ZERO, forward, Vector2(45, -100))
	t.near(arc[arc.size() - 1].distance_to(Vector2(45, -100)), 0.0, 0.01, "arc ends at its target")
	var radius := (100.0 * 100.0 + 45.0 * 45.0) / (2.0 * 45.0)
	for point in arc:
		t.near(point.distance_to(Vector2(radius, 0)), radius, 0.01, "arc samples lie on the reach circle")


func test_available_radius(t: TestContext) -> void:
	var circles := _circles([Vector3(5, -150, 40)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -300), circles)
	t.check(route != null, "route found")
	if route == null:
		return
	var tight := route.guidance(circles, 0.0)
	t.check(tight.bends.size() == 1, "one bend around one rock")
	t.near(tight.bends[0].y, 40.0, 0.001, "no room to swing out: radius is the keep-out radius")
	var wide := route.guidance(circles, nav.corridor_half_width)
	var half_turn := minf(_group_turn(route, 0) * 0.5, Route.MAX_HALF_TURN)
	t.near(wide.bends[0].y, 40.0 + nav.corridor_half_width / (1.0 - cos(half_turn)), 0.01,
			"room to swing out widens the bend")
	t.check(wide.bends[0].x < tight.bends[0].x, "a wider line starts turning earlier")


func test_outer_width_limited_by_neighbour(t: TestContext) -> void:
	# A second rock just outside the first limits how far the ship can swing out.
	var lone := _circles([Vector3(5, -150, 40)])
	var pair := _circles([Vector3(5, -150, 40), Vector3(-75, -150, 30)])
	var route_lone := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -300), lone)
	var route_pair := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -300), pair)
	t.check(route_lone != null and route_pair != null, "routes found")
	if route_lone == null or route_pair == null:
		return
	var lone_r := route_lone.guidance(lone, nav.corridor_half_width).bends[0].y
	var pair_r := route_pair.guidance(pair, nav.corridor_half_width).bends[0].y
	t.check(pair_r < lone_r, "neighbouring rock narrows the bend")


func test_two_rocks_two_bends(t: TestContext) -> void:
	var circles := _circles([Vector3(5, -150, 30), Vector3(-5, -400, 30)])
	var route := RoutePlanner.plan(Vector2.ZERO, Vector2(0, -550), circles)
	t.check(route != null, "route found")
	if route != null:
		t.check(route.guidance(circles, nav.corridor_half_width).bends.size() == 2, "one bend per rock")


func test_heading_picks_side(t: TestContext) -> void:
	# Rock slightly right of the line: from rest the shorter (left) side wins.
	var circles := _circles([Vector3(5, -200, 40)])
	var goal := Vector2(0, -400)
	var at_rest := RoutePlanner.plan(Vector2.ZERO, goal, circles)
	t.check(at_rest != null and at_rest.points[1].x < 5.0, "at rest: shorter side")
	# Moving fast toward the right: the right side needs far less turning.
	var moving := RoutePlanner.plan(Vector2.ZERO, goal, circles, Vector2(1, -1).normalized(), 300.0)
	t.check(moving != null and moving.points[1].x > 5.0, "moving right: passes on the right")
