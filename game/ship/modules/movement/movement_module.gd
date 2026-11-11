class_name MovementModule
extends Node
## The single movement module every ship inherits. Public entry point for all ship movement.
## Must be a direct child of a CharacterBody3D with sibling Navigator (NavigatorModule) and
## Lookout (LookoutModule) nodes. Movement is the helm: it follows the Navigator's guidance and
## the Lookout's traffic report with its own speed, turn and RCS rules.
## The owning ship calls physics_step() each physics tick and applies the result.
## Other modules use only this script's public API, never the internal/ scripts.
## Ships settle right of way with each other through this public API only
## (get_traffic_snapshot, request_give_way, is_giving_way_to).

signal order_activated(destination: Vector3)
signal order_completed(destination: Vector3)
## The order was refused: no free spot near the destination or no route to it.
signal order_rejected(destination: Vector3)
## An active order ended because its route became blocked and no new route exists.
signal order_failed(destination: Vector3)

const State := MovementCore.State

@export var profile: MovementProfile

## Contacts registered since spawn (debug and tests).
var contact_count := 0

var _core: MovementCore
var _body: CharacterBody3D
var _navigator: NavigatorModule
var _lookout: LookoutModule
var _guidance: Guidance
## Radius (u) the hull sweeps when rotating in place.
var _spin_radius := 0.0
## Ship this one is stepping aside for, or null.
var _giving_way_to: MovementModule
## Other ship's instance id -> seconds before trying to settle right of way with it again.
var _retry_left := {}


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	assert(_body != null, "MovementModule must be a child of a CharacterBody3D")
	_navigator = _body.get_node_or_null("Navigator") as NavigatorModule
	_lookout = _body.get_node_or_null("Lookout") as LookoutModule
	assert(_navigator != null and _lookout != null,
			"MovementModule needs sibling Navigator and Lookout modules")
	_core = MovementCore.new(profile)
	_core.order_activated.connect(func(d: Vector2) -> void: order_activated.emit(_to3(d)))
	_core.order_completed.connect(func(d: Vector2) -> void:
		_navigator.clear_route()
		order_completed.emit(_to3(d)))
	_core.order_failed.connect(func(d: Vector2) -> void:
		_navigator.clear_route()
		order_failed.emit(_to3(d)))
	for child in _body.get_children():
		if child is CollisionShape3D and child.shape != null:
			_spin_radius = NavigatorModule.hull_spin_radius(child.shape)
			break
	reset_motion(_body.global_position, _body.global_rotation.y)


# --- Orders -------------------------------------------------------------------

## Checks a move order without issuing it. Returns where the ship would go: the destination,
## or the nearest free spot when it lies inside an obstacle's clearance. Null when there is
## none or no route; then order_rejected is emitted.
func resolve_move_order(destination: Vector3) -> Variant:
	var resolved: Variant = _navigator.resolve_destination(_core.motion.position, _to2(destination))
	if resolved == null:
		order_rejected.emit(destination)
		return null
	return _to3(resolved)


## Issues a move order, resolved as resolve_move_order does (a rejected order leaves the
## current order running). It replaces the active order on the next physics tick, starting
## from the ship's actual motion. Any order delay is applied by Command before this call.
func issue_move_order(destination: Vector3) -> void:
	var resolved: Variant = resolve_move_order(destination)
	if resolved != null:
		_core.issue_move_order(_to2(resolved), _to2(destination))


## Destination of the order being executed (including one received this tick), or null.
func get_active_destination() -> Variant:
	var order := _core.incoming if _core.incoming != null else _core.active
	return _to3(order.destination) if order != null else null


## IDLE, MOVING, WAITING
## (stopped for a ship in the way), SETTLING (arrived, finishing rotation) or YIELDING
## (stepping aside for a ship with right of way; any active order resumes afterwards).
func get_state() -> MovementCore.State:
	return _core.get_state()


# --- Ship integration ---------------------------------------------------------

## Advances movement by one tick and returns the displacement for the body to apply.
func physics_step(delta: float) -> Vector3:
	var before := _core.motion.position
	_tick_retries(delta)
	# The Navigator weighs the ship's momentum when choosing which side to pass obstacles.
	var travel := _core.travel_direction()
	var turn_radius := PathFollower.turn_radius(profile, _core.motion.speed)
	if _core.update_orders(delta):
		if not _navigator.start_route(before, _core.active.destination, travel, turn_radius):
			_core.fail_active()
	if _giving_way_to != null:
		_update_give_way(travel, turn_radius)
	_guidance = null
	var order := _core.active
	if order != null and order.status == MoveExecution.Status.MOVING and _giving_way_to == null:
		_guidance = _navigator.update(delta, before, travel, turn_radius)
		if _guidance == null:
			_core.fail_active()
	var free_distance := INF
	if _core.needs_traffic_probe():
		var contact := _lookout.ship_in_the_way(_core.travel_direction(), _core.traffic_probe_length())
		if contact != null:
			free_distance = contact.distance
			_meet(contact.ship)
	if _giving_way_to != null:
		free_distance = _probe_give_way_step()
	_core.step(delta, _guidance, free_distance)
	return _to3(_core.motion.position - before)


# --- Right of way ---------------------------------------------------------------

## This ship's traffic state, read by other ships settling right of way with it.
func get_traffic_snapshot() -> Dictionary:
	var m := _core.motion
	return {
		"position": m.position,
		"velocity": m.velocity(),
		"travel_direction": _core.travel_direction(),
		"speed": m.velocity().length(),
		"spin_radius": _spin_radius,
		"has_moving_order": _core.has_moving_order(),
	}


## Asked by a ship with right of way: step aside out of its path. False when this ship is
## already giving way to another ship or has no room to step aside (it then keeps its orders).
func request_give_way(priority: MovementModule) -> bool:
	if _giving_way_to != null:
		return _giving_way_to == priority
	return _start_give_way(priority)


## True while this ship is stepping aside for `other`.
func is_giving_way_to(other: MovementModule) -> bool:
	return _giving_way_to != null and _giving_way_to == other


## A ship is in the way of this ship's order. Settles right of way once; the result holds
## until the ship giving way resumes.
func _meet(ship: CharacterBody3D) -> void:
	var other := ship.get_node_or_null("Movement") as MovementModule if ship != null else null
	if other == null or other.is_giving_way_to(self) or _retry_left.has(other.get_instance_id()):
		return
	var mine := get_traffic_snapshot()
	var theirs := other.get_traffic_snapshot()
	if not RightOfWay.needs_negotiation(mine, theirs):
		return
	var settled := false
	if RightOfWay.has_priority(mine, theirs, get_instance_id(), other.get_instance_id()):
		settled = other.request_give_way(self)
	elif theirs.has_moving_order and RightOfWay.needs_negotiation(theirs, mine):
		settled = _start_give_way(other)
	if not settled:
		# Neither stepped aside: keep waiting behind it and try again later.
		_retry_left[other.get_instance_id()] = profile.give_way_retry_interval


func _start_give_way(priority: MovementModule) -> bool:
	var point: Variant = _give_way_point(priority.get_traffic_snapshot())
	if point == null:
		return false
	_giving_way_to = priority
	_core.start_give_way(point)
	return true


## A free point beside the priority ship's line of travel, or null when neither side has room.
func _give_way_point(priority: Dictionary) -> Variant:
	var position := _core.motion.position
	var direction: Vector2 = priority.travel_direction
	var normal := Vector2(-direction.y, direction.x)
	var lateral := (position - (priority.position as Vector2)).dot(normal)
	var required := _give_way_required(priority)
	for shift in RightOfWay.step_options(lateral, required):
		var point := position + normal * shift
		var resolved: Variant = _navigator.resolve_destination(position, point)
		if resolved == null or (resolved as Vector2).distance_to(point) > profile.arrival_tolerance:
			continue
		if absf(shift) > PathFollower.EPSILON \
				and not is_inf(_lookout.free_distance(normal * signf(shift), absf(shift))):
			continue
		return point
	return null


func _give_way_required(priority: Dictionary) -> float:
	return _spin_radius + priority.spin_radius + profile.give_way_margin


## Ends giving way once the priority ship has passed or stopped; an active order resumes.
func _update_give_way(travel: Vector2, turn_radius: float) -> void:
	var priority := _giving_way_to
	if is_instance_valid(priority):
		var theirs := priority.get_traffic_snapshot()
		if not RightOfWay.can_release(get_traffic_snapshot(), theirs, _give_way_required(theirs)):
			return
	_giving_way_to = null
	if _core.end_give_way():
		if not _navigator.start_route(_core.motion.position, _core.active.destination,
				travel, turn_radius):
			_core.fail_active()


## Gap to a ship in the way of the step aside. An idle ship there is asked to step aside too.
func _probe_give_way_step() -> float:
	var to_point: Vector2 = _core.give_way_point - _core.motion.position
	if to_point.length() <= profile.arrival_tolerance:
		return INF
	var contact := _lookout.ship_in_the_way(to_point.normalized(), to_point.length())
	if contact == null:
		return INF
	var other := contact.ship.get_node_or_null("Movement") as MovementModule \
			if contact.ship != null else null
	if other != null and other != _giving_way_to and not other.is_giving_way_to(self) \
			and not other.get_traffic_snapshot().has_moving_order \
			and not _retry_left.has(other.get_instance_id()):
		if not other.request_give_way(self):
			_retry_left[other.get_instance_id()] = profile.give_way_retry_interval
	return contact.distance


func _tick_retries(delta: float) -> void:
	for id in _retry_left.keys():
		_retry_left[id] -= delta
		if _retry_left[id] <= 0.0:
			_retry_left.erase(id)


## Heading (rotation around Y, radians) the body should take.
func get_heading() -> float:
	return _core.motion.heading


## Called by the body after moving, so motion follows where the body actually is.
func sync_position(world_position: Vector3) -> void:
	_core.motion.position = _to2(world_position)


## Called by the body on contact: the ship loses speed and keeps its order.
func notify_contact() -> void:
	contact_count += 1
	_core.apply_contact()


## Places the ship (spawning, tests). Does not change orders.
func reset_motion(world_position: Vector3, heading: float, speed: float = 0.0) -> void:
	_core.motion = MotionState.new()
	_core.motion.position = _to2(world_position)
	_core.motion.heading = heading
	_core.motion.speed = speed
	_body.global_position = Vector3(world_position.x, 0.0, world_position.z)
	_body.global_rotation = Vector3(0.0, heading, 0.0)


## Snapshot for debug drawing. Not part of the gameplay contract.
func get_debug_info() -> Dictionary:
	var m := _core.motion
	var order := _core.active
	var info := {
		"state": State.keys()[get_state()],
		"speed": m.speed,
		"rcs": m.rcs_velocity.length(),
		"heading": m.heading,
		"velocity": _to3(m.velocity()),
		"stop_point": _to3(PathFollower.stop_point(profile, m)),
		"turn_radius": PathFollower.turn_radius(profile, m.speed),
		"limit": order.binding_limit if order != null else &"",
		"path_point": _to3(order.steer_point) if order != null and _guidance != null else null,
		"steer_arc": Array(Corridor.arc_points(m.position, m.forward(), order.steer_point)).map(_to3) \
				if order != null and _guidance != null else [],
		"contacts": contact_count,
		"give_way_point": _to3(_core.give_way_point) if _core.give_way_point != null else null,
	}
	return info


static func _to2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _to3(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)
