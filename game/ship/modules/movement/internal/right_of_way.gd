class_name RightOfWay
extends RefCounted
## Pure right-of-way rules between two ships that meet. The ship already moving has priority;
## the other gives way. Snapshots come from MovementModule.get_traffic_snapshot().


## True when ship a has right of way over ship b.
## 1. A ship executing a moving order beats one that is not (idle, settling, already
##    giving way).
## 2. Between two moving ships, the faster one wins.
## 3. Equal speeds: the lower id wins, so both ships always reach the same answer.
static func has_priority(a: Dictionary, b: Dictionary, a_id: int, b_id: int) -> bool:
	if a.has_moving_order != b.has_moving_order:
		return a.has_moving_order
	if absf(a.speed - b.speed) > PathFollower.WAIT_SPEED:
		return a.speed > b.speed
	return a_id < b_id


## True when ship `me` and ship `other` must settle right of way: `other` is not simply
## travelling away ahead of `me` (that is ordinary following, handled by the traffic limit).
## It is when `other` has no moving order, is stopped, or is heading toward `me`'s side.
static func needs_negotiation(me: Dictionary, other: Dictionary) -> bool:
	if not other.has_moving_order or other.speed <= PathFollower.WAIT_SPEED:
		return true
	var to_me: Vector2 = me.position - other.position
	return to_me.dot(other.travel_direction) > 0.0


## True when the ship giving way may resume: the priority ship no longer has a moving order,
## or it has gone past (the yielder is behind its beam and further than `required`).
static func can_release(me: Dictionary, priority: Dictionary, required: float) -> bool:
	if not priority.has_moving_order:
		return true
	var to_me: Vector2 = me.position - priority.position
	return to_me.dot(priority.travel_direction) < 0.0 and to_me.length() > required


## Lateral step (u) along the priority ship's normal for each side to try, preferred side
## first. `lateral` is the yielder's current signed offset from the priority ship's line;
## `required` is the offset it needs. A side already clear needs no step.
static func step_options(lateral: float, required: float) -> PackedFloat64Array:
	var side := signf(lateral) if absf(lateral) > PathFollower.EPSILON else 1.0
	var preferred := 0.0 if absf(lateral) >= required else side * required - lateral
	return PackedFloat64Array([preferred, -side * required - lateral])
