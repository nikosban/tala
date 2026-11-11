class_name CircleGeometry
extends RefCounted
## Pure helpers for circles on the tactical plane. A circle is Vector3(center.x, center.y, radius)
## in plane coordinates (x -> world X, y -> world Z). Shared by the Lookout and Navigator.

const EPSILON := 0.001


static func center(circle: Vector3) -> Vector2:
	return Vector2(circle.x, circle.y)


## True when the point is inside no circle.
static func point_free(point: Vector2, circles: Array[Vector3]) -> bool:
	for c in circles:
		if point.distance_to(center(c)) < c.z - EPSILON:
			return false
	return true


## True when the segment enters no circle.
static func segment_clear(a: Vector2, b: Vector2, circles: Array[Vector3]) -> bool:
	for c in circles:
		if distance_to_segment(center(c), a, b) < c.z - EPSILON:
			return false
	return true


## True when every segment of the polyline enters no circle.
static func polyline_clear(points: PackedVector2Array, circles: Array[Vector3]) -> bool:
	for i in range(1, points.size()):
		if not segment_clear(points[i - 1], points[i], circles):
			return false
	return true


static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	var t := 0.0 if length_sq < 1e-12 else clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


## Intersection points of two circle boundaries (0, 1 or 2 points).
static func intersections(a: Vector3, b: Vector3) -> PackedVector2Array:
	var ca := center(a)
	var cb := center(b)
	var d := ca.distance_to(cb)
	if d < EPSILON or d > a.z + b.z or d < absf(a.z - b.z):
		return PackedVector2Array()
	var along := (a.z * a.z - b.z * b.z + d * d) / (2.0 * d)
	var h := sqrt(maxf(a.z * a.z - along * along, 0.0))
	var axis := (cb - ca) / d
	var mid := ca + axis * along
	var normal := Vector2(-axis.y, axis.x)
	return PackedVector2Array([mid + normal * h, mid - normal * h])
