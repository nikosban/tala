class_name MovementCore
extends RefCounted
## Scene-free movement for one ship: motion state, order lifecycle and rule stepping.
## MovementModule wraps this with the scene (body, traffic probe, contacts).

signal order_activated(destination: Vector2)
signal order_completed(destination: Vector2)
signal order_failed(destination: Vector2)

enum State { IDLE, MOVING, WAITING, SETTLING, YIELDING }

var profile: MovementProfile
var motion := MotionState.new()
## Order being executed, or null.
var active: MoveExecution
## Order received this tick; replaces the active order on the next update_orders.
var incoming: MoveExecution
## Point the ship steps aside to while giving way to a ship with priority, or null.
var give_way_point: Variant = null


func _init(p: MovementProfile) -> void:
	assert(p != null and p.turn_rate_curve != null and p.rcs_authority_curve != null,
			"MovementCore needs a profile with turn_rate_curve and rcs_authority_curve")
	profile = p


## destination: where the ship will go; requested: what was asked for (defaults to destination).
## The order replaces the active order on the next update_orders.
func issue_move_order(destination: Vector2, requested: Variant = null) -> void:
	incoming = MoveExecution.new(destination, requested)


## Advances one tick: order lifecycle, then motion. Open-space convenience (tests).
func tick(dt: float, traffic_free_distance: float = INF, guidance: Guidance = null) -> void:
	update_orders(dt)
	step(dt, guidance, traffic_free_distance)


## Activates a received order. True when an order became active this tick.
func update_orders(_dt: float) -> bool:
	if incoming == null:
		return false
	active = incoming
	incoming = null
	order_activated.emit(active.destination)
	return true


## Advances motion one tick. guidance: from the Navigator (null = straight at the destination).
## traffic_free_distance: gap (u) to a ship in the way, INF if clear.
func step(dt: float, guidance: Guidance = null, traffic_free_distance: float = INF) -> void:
	var order := active
	if give_way_point != null:
		motion = PathFollower.give_way_step(motion, profile, give_way_point, dt, traffic_free_distance)
		if order != null:
			order.binding_limit = &"give_way"
			order.waiting = false
		return
	if order == null:
		motion = PathFollower.coast(motion, profile, dt)
		return
	motion = PathFollower.step(motion, profile, order, dt,
			PathFollower.traffic_cap(profile, traffic_free_distance), guidance)
	if order.status == MoveExecution.Status.COMPLETED:
		active = null
		order_completed.emit(order.destination)


## Ends the active order because it can no longer be completed; the ship coasts to a stop.
func fail_active() -> void:
	var order := active
	if order == null:
		return
	active = null
	order_failed.emit(order.destination)


## True when the ship is executing a moving order (not settling, not giving way).
func has_moving_order() -> bool:
	return give_way_point == null and active != null 			and active.status == MoveExecution.Status.MOVING


## True when the next tick uses the traffic gap ahead (an active order still moving).
func needs_traffic_probe() -> bool:
	return has_moving_order()


## Starts stepping aside to point. The active order stays active.
func start_give_way(point: Vector2) -> void:
	give_way_point = point


## Ends giving way. An active order resumes from the ship's current motion: it moves again
## (even if it had started settling) and needs a new route. True when there is such an order.
func end_give_way() -> bool:
	give_way_point = null
	var order := active
	if order == null:
		return false
	order.status = MoveExecution.Status.MOVING
	order.started = false
	order.rest_manoeuvre = false
	order.waiting = false
	return true


func traffic_probe_length() -> float:
	return PathFollower.traffic_probe_length(profile, motion.speed)


## Direction of travel, or the bow when nearly still.
func travel_direction() -> Vector2:
	var v := motion.velocity()
	return v.normalized() if v.length() > PathFollower.STILL_SPEED else motion.forward()


func apply_contact() -> void:
	var keep := 1.0 - profile.contact_speed_loss
	motion.speed *= keep
	motion.rcs_velocity *= keep


func get_state() -> State:
	if give_way_point != null:
		return State.YIELDING
	if incoming != null:
		return State.MOVING
	var order := active
	if order != null:
		if order.status == MoveExecution.Status.SETTLING:
			return State.SETTLING
		return State.WAITING if order.waiting else State.MOVING
	return State.IDLE
