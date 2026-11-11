class_name RoutePlanner
extends RefCounted
## Pure route planning around circles that are already inflated by the ship's clearance.
## Shortest path (A*) over a visibility graph of polygon vertices circumscribed around each
## circle: polygon edges touch their circle without entering it, so every route segment keeps
## the hull's clearance. Each vertex carries its circle's radius as the bend radius there.

## Polygon sides per circle; each route bend turns at most 360 / SIDES degrees per vertex.
const SIDES := 16
## Distance (u) points are pushed outside a boundary so they count as free.
const NUDGE := 0.01


## The goal if it is free, else the nearest free point within max_shift, else null.
## The nearest free point lies on the boundary of the circles' union: either the goal pushed
## out radially from one circle or a point where two circles cross.
static func resolve_destination(goal: Vector2, circles: Array[Vector3], max_shift: float) -> Variant:
	if CircleGeometry.point_free(goal, circles):
		return goal
	var candidates := PackedVector2Array()
	for c in circles:
		var center := CircleGeometry.center(c)
		var outward := goal - center
		if outward.length() < CircleGeometry.EPSILON:
			outward = Vector2.RIGHT
		candidates.append(center + outward.normalized() * (c.z + NUDGE))
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			for point in CircleGeometry.intersections(circles[i], circles[j]):
				var away := (point - CircleGeometry.center(circles[i])).normalized() \
						+ (point - CircleGeometry.center(circles[j])).normalized()
				if away.length() > CircleGeometry.EPSILON:
					point += away.normalized() * NUDGE
				candidates.append(point)
	var best: Variant = null
	var best_distance := INF
	for point in candidates:
		var d := goal.distance_to(point)
		if d <= max_shift and d < best_distance and CircleGeometry.point_free(point, circles):
			best = point
			best_distance = d
	return best


## Shortest clear route from start to goal, or null when none exists. A start inside a circle
## (e.g. pushed there by a collision) first leads straight out to the nearest free point.
## travel_direction / turn_radius: the ship's current motion. Leaving the start along a
## direction costs the arc length needed to swing onto it (turn_radius x angle), so a moving
## ship prefers the side its momentum already favours. Zero turn_radius = shortest route.
static func plan(start: Vector2, goal: Vector2, circles: Array[Vector3],
		travel_direction: Vector2 = Vector2.ZERO, turn_radius: float = 0.0) -> Route:
	if not CircleGeometry.point_free(goal, circles):
		return null
	var points := PackedVector2Array([start])
	var radii := PackedFloat32Array([INF])
	var ids := PackedInt32Array([-1])
	var from := start
	if not CircleGeometry.point_free(start, circles):
		var exit: Variant = resolve_destination(start, circles, INF)
		if exit == null:
			return null
		from = exit
		points.append(from)
		radii.append(INF)
		ids.append(-1)
	if CircleGeometry.segment_clear(from, goal, circles):
		points.append(goal)
		radii.append(INF)
		ids.append(-1)
		return Route.new(points, radii, ids, circles)

	var nodes := PackedVector2Array([from])
	var node_radius := PackedFloat32Array([INF])
	var node_circle := PackedInt32Array([-1])
	for c_index in circles.size():
		var c := circles[c_index]
		var center := CircleGeometry.center(c)
		var vertex_distance := c.z / cos(PI / SIDES) + NUDGE
		for k in SIDES:
			var vertex := center + Vector2.from_angle(TAU * k / SIDES) * vertex_distance
			if CircleGeometry.point_free(vertex, circles):
				nodes.append(vertex)
				node_radius.append(c.z)
				node_circle.append(c_index)
	nodes.append(goal)
	node_radius.append(INF)
	node_circle.append(-1)

	var heading := travel_direction.normalized() if turn_radius > 0.0 else Vector2.ZERO
	var came_from := _a_star(nodes, circles, heading, turn_radius)
	var goal_index := nodes.size() - 1
	if came_from[goal_index] == -1:
		return null
	var chain: Array[int] = []
	var at := goal_index
	while at != 0:
		chain.push_front(at)
		at = came_from[at]
	for i in chain:
		points.append(nodes[i])
		radii.append(node_radius[i])
		ids.append(node_circle[i])
	return Route.new(points, radii, ids, circles)


## A* from node 0 to the last node; neighbours are found lazily (any node in clear sight).
## Edges leaving node 0 also cost turn_radius x the angle between heading and the edge.
## Returns the predecessor of each node (-1 = unreached).
static func _a_star(nodes: PackedVector2Array, circles: Array[Vector3], heading: Vector2,
		turn_radius: float) -> PackedInt32Array:
	var n := nodes.size()
	var goal_index := n - 1
	var goal := nodes[goal_index]
	var cost := PackedFloat64Array()
	cost.resize(n)
	cost.fill(INF)
	var came_from := PackedInt32Array()
	came_from.resize(n)
	came_from.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var open: Array[int] = [0]
	cost[0] = 0.0
	while not open.is_empty():
		var best := 0
		var best_score := INF
		for k in open.size():
			var score := cost[open[k]] + nodes[open[k]].distance_to(goal)
			if score < best_score:
				best_score = score
				best = k
		var u := open[best]
		open.remove_at(best)
		if u == goal_index:
			break
		closed[u] = 1
		for v in n:
			if closed[v] == 1 or v == u:
				continue
			var through := cost[u] + nodes[u].distance_to(nodes[v])
			if u == 0 and heading != Vector2.ZERO:
				through += turn_radius * absf(heading.angle_to(nodes[v] - nodes[u]))
			if through >= cost[v]:
				continue
			if not CircleGeometry.segment_clear(nodes[u], nodes[v], circles):
				continue
			if is_inf(cost[v]):
				open.append(v)
			cost[v] = through
			came_from[v] = u
	return came_from
