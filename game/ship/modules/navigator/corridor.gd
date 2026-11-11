class_name Corridor
extends RefCounted
## Safe space around the route that the ship's centre may use: outside every keep-out circle
## (obstacles inflated by the ship's clearance) and within half_width of the route centreline.
## Plane coordinates. Part of the Navigator's guidance contract.

## Spacing (u) of samples along a checked arc.
const ARC_STEP := 5.0
const MAX_SAMPLES := 48

## Remaining route, including the leg being flown.
var centreline: PackedVector2Array
var circles: Array[Vector3]
var half_width := 0.0


func _init(line: PackedVector2Array, keep_out: Array[Vector3], width: float) -> void:
	centreline = line
	circles = keep_out
	half_width = width


func contains(point: Vector2) -> bool:
	return CircleGeometry.point_free(point, circles) and distance_to_centreline(point) <= half_width


func distance_to_centreline(point: Vector2) -> float:
	if centreline.size() == 1:
		return point.distance_to(centreline[0])
	var best := INF
	for i in range(1, centreline.size()):
		best = minf(best, CircleGeometry.distance_to_segment(point, centreline[i - 1], centreline[i]))
	return best


## True when the arc leaving `from` along `forward` and passing through `to` stays inside.
## straight: check the straight line instead (a ship that can move in any direction).
func arc_inside(from: Vector2, forward: Vector2, to: Vector2, straight: bool = false) -> bool:
	for point in arc_points(from, forward, to, straight):
		if not contains(point):
			return false
	return true


## Samples (excluding `from`, including `to`) of the circular arc that leaves `from` tangent to
## `forward` and passes through `to`; a straight line when straight or when `to` is dead ahead.
## Same geometry as the helm's reach radius for targets ahead or abeam.
static func arc_points(from: Vector2, forward: Vector2, to: Vector2, straight: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	var d := to - from
	var length := d.length()
	if length < CircleGeometry.EPSILON:
		return points
	var right := Vector2(-forward.y, forward.x)
	var x := d.dot(forward)
	var y := d.dot(right)
	if straight or absf(y) < 1e-4 * length:
		var count := clampi(ceili(length / ARC_STEP), 1, MAX_SAMPLES)
		for k in range(1, count + 1):
			points.append(from + d * (float(k) / count))
		return points
	var radius := (x * x + y * y) / (2.0 * absf(y))
	var centre := from + right * signf(y) * radius
	var a0 := (from - centre).angle()
	var a1 := (to - centre).angle()
	var direction := 1.0 if Vector2(-sin(a0), cos(a0)).dot(forward) > 0.0 else -1.0
	var sweep := fposmod((a1 - a0) * direction, TAU)
	var count := clampi(ceili(sweep * radius / ARC_STEP), 2, MAX_SAMPLES)
	for k in range(1, count + 1):
		points.append(centre + Vector2.from_angle(a0 + direction * sweep * k / count) * radius)
	return points
