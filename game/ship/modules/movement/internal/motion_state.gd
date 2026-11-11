class_name MotionState
extends RefCounted
## Ship motion on the tactical plane. Vector2 maps x -> world X, y -> world Z.
## Heading is the rotation around world Y; heading 0 faces -Z (Godot forward).

var position := Vector2.ZERO
var heading := 0.0
## Forward speed along the bow (u/s), never negative.
var speed := 0.0
## Velocity from RCS translation (u/s), world frame. Added to the main-engine velocity.
var rcs_velocity := Vector2.ZERO


static func forward_of(h: float) -> Vector2:
	return Vector2(-sin(h), -cos(h))


static func right_of(h: float) -> Vector2:
	return Vector2(cos(h), -sin(h))


static func heading_of(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)


func forward() -> Vector2:
	return forward_of(heading)


func right() -> Vector2:
	return right_of(heading)


func velocity() -> Vector2:
	return forward() * speed + rcs_velocity


func copy() -> MotionState:
	var c := MotionState.new()
	c.position = position
	c.heading = heading
	c.speed = speed
	c.rcs_velocity = rcs_velocity
	return c
