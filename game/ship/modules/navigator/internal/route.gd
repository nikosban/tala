class_name Route
extends RefCounted
## A planned route and progress along it. points[0] is where the route started; the last
## point is the goal. For each point: radii[i] is its keep-out circle's radius and circle_ids[i]
## that circle's index in `circles` (INF / -1 where the point is not on a circle).

## Largest half-turn (rad) used for a bend group; keeps the radius formula finite.
const MAX_HALF_TURN := deg_to_rad(80.0)

var points: PackedVector2Array
var radii: PackedFloat32Array
var circle_ids: PackedInt32Array
## Keep-out circles the route was planned around.
var circles: Array[Vector3] = []
## Index of the current steer point.
var index := 1


func _init(p: PackedVector2Array, r: PackedFloat32Array, ids: PackedInt32Array,
		keep_out: Array[Vector3]) -> void:
	assert(p.size() >= 2 and p.size() == r.size() and p.size() == ids.size(),
			"Route needs a start, a goal and one radius and circle id per point")
	points = p
	radii = r
	circle_ids = ids
	circles = keep_out


func goal() -> Vector2:
	return points[points.size() - 1]


func is_final() -> bool:
	return index >= points.size() - 1


## Moves the steer point on once the ship is within lookahead of it or has passed it.
func advance(position: Vector2, lookahead: float) -> void:
	while not is_final():
		var point := points[index]
		var leg := point - points[index - 1]
		if position.distance_to(point) <= lookahead or (position - point).dot(leg) >= 0.0:
			index += 1
		else:
			break


## The leg being flown and everything after it.
func remaining_points() -> PackedVector2Array:
	return points.slice(index - 1)


## Guidance for the helm. current_circles: keep-out circles now (for the corridor).
func guidance(current_circles: Array[Vector3], half_width: float) -> Guidance:
	var g := Guidance.new()
	g.candidates = points.slice(index)
	var along := 0.0
	g.along.append(0.0)
	for i in range(index + 1, points.size()):
		along += points[i - 1].distance_to(points[i])
		g.along.append(along)
	g.remaining_after = along
	g.corridor = Corridor.new(remaining_points(), current_circles, half_width)
	g.bends = _bend_groups(half_width)
	return g


## One bend per run of consecutive points on the same circle that has not been fully passed:
## Vector2(distance from points[index] to where the turn starts, available radius).
## Available radius R = r + w / (1 - cos(turn / 2)): the widest arc that stays outside the
## circle when the ship may swing out by w (the free outer width) before and after it.
func _bend_groups(half_width: float) -> PackedVector2Array:
	var bends := PackedVector2Array()
	var i := 1
	while i < points.size() - 1:
		var id := circle_ids[i]
		if id < 0:
			i += 1
			continue
		var first := i
		var turn := 0.0
		var outer := half_width
		while i < points.size() - 1 and circle_ids[i] == id:
			turn += absf(angle_difference((points[i] - points[i - 1]).angle(), (points[i + 1] - points[i]).angle()))
			outer = minf(outer, _outer_width(i, half_width))
			i += 1
		if i - 1 < index:
			continue
		var r := radii[first]
		var half_turn := minf(turn * 0.5, MAX_HALF_TURN)
		var available := r
		if half_turn > 1e-4:
			available = r + outer / (1.0 - cos(half_turn))
		var lead := (available - r) * tan(half_turn)
		bends.append(Vector2(_route_distance(index, first) - lead, available))
	return bends


## Free distance (u) outward from point i (away from its circle) to the next keep-out circle,
## capped at half_width.
func _outer_width(i: int, half_width: float) -> float:
	var own := circles[circle_ids[i]]
	var origin := points[i]
	var direction := (origin - CircleGeometry.center(own)).normalized()
	var free := half_width
	for k in circles.size():
		if k == circle_ids[i]:
			continue
		var hit := _ray_hit(origin, direction, circles[k])
		free = minf(free, hit)
	return maxf(free, 0.0)


## Distance along a ray to a circle's boundary (0 if starting inside, INF if missed).
static func _ray_hit(origin: Vector2, direction: Vector2, circle: Vector3) -> float:
	var to_centre := CircleGeometry.center(circle) - origin
	if to_centre.length() <= circle.z:
		return 0.0
	var t := to_centre.dot(direction)
	if t < 0.0:
		return INF
	var miss_sq := to_centre.length_squared() - t * t
	if miss_sq > circle.z * circle.z:
		return INF
	return t - sqrt(circle.z * circle.z - miss_sq)


## Signed route length from point a to point b (negative when b is behind a).
func _route_distance(a: int, b: int) -> float:
	var total := 0.0
	for i in range(mini(a, b) + 1, maxi(a, b) + 1):
		total += points[i - 1].distance_to(points[i])
	return total if b >= a else -total
