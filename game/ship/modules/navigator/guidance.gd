class_name Guidance
extends RefCounted
## What the Navigator tells the helm (Movement) each tick. Plane coordinates.
## The helm chooses which candidate to steer at; candidates[0] is the next route point.

## Route points ahead, nearest first; the last one is the goal.
var candidates := PackedVector2Array()
## Route length (u) from candidates[0] to each candidate.
var along := PackedFloat32Array()
## Route length (u) from candidates[0] to the goal.
var remaining_after := 0.0
## Upcoming bends: Vector2(distance along the route from candidates[0] to where the turn starts
## (u, negative once started), available radius (u)). The helm must fit its turn inside the radius.
var bends := PackedVector2Array()
## Safe space around the route; null in open space (any line is fine).
var corridor: Corridor


## Guidance straight to a point (open space).
static func direct(destination: Vector2) -> Guidance:
	var g := Guidance.new()
	g.candidates = PackedVector2Array([destination])
	g.along = PackedFloat32Array([0.0])
	return g


## The next route point.
func steer_point() -> Vector2:
	return candidates[0]


## Route length (u) from candidate k to the goal.
func remaining_after_candidate(k: int) -> float:
	return remaining_after - along[k]


## True when candidate k is the goal.
func is_goal(k: int) -> bool:
	return k == candidates.size() - 1
