class_name HudMeshes
extends RefCounted
## Flat HUD shapes on a horizontal plane, appended as triangles to an ImmediateMesh surface
## (PRIMITIVE_TRIANGLES) that the caller has begun. Sizes are world units, so the shapes keep
## a fixed size in the world at every zoom. Scene-free.

## Segments per full circle; arcs use a proportional share.
const CIRCLE_SEGMENTS := 48


## A full ring centred at center: radius to the middle of the band, band width.
static func ring(mesh: ImmediateMesh, center: Vector3, radius: float, width: float) -> void:
	arc(mesh, center, radius, width, 0.0, TAU)


## Part of a ring from from_angle spanning span radians (angle 0 = +X, increasing toward +Z).
static func arc(mesh: ImmediateMesh, center: Vector3, radius: float, width: float,
		from_angle: float, span: float) -> void:
	var inner := maxf(radius - width * 0.5, 0.0)
	var outer := radius + width * 0.5
	var steps := maxi(1, ceili(CIRCLE_SEGMENTS * absf(span) / TAU))
	for i in steps:
		var a := from_angle + span * i / steps
		var b := from_angle + span * (i + 1) / steps
		var da := Vector3(cos(a), 0.0, sin(a))
		var db := Vector3(cos(b), 0.0, sin(b))
		_quad(mesh, center + da * inner, center + da * outer, center + db * outer, center + db * inner)


## A straight band of the given width from a to b (on a's plane height).
static func strip(mesh: ImmediateMesh, a: Vector3, b: Vector3, width: float) -> void:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if along.length_squared() < 1e-8:
		return
	var side := Vector3(-along.z, 0.0, along.x).normalized() * width * 0.5
	var end := Vector3(b.x, a.y, b.z)
	_quad(mesh, a - side, a + side, end + side, end - side)


static func _quad(mesh: ImmediateMesh, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	for p in [p0, p1, p2, p0, p2, p3]:
		mesh.surface_add_vertex(p)
