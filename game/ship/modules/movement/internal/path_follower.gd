class_name PathFollower
extends RefCounted
## Pure movement rules. No scene access; deterministic for a given input.
## step() returns a new MotionState and advances the order's progress fields
## (status, final_heading, binding_limit, waiting). Where to steer comes from Guidance.

const EPSILON := 0.0001
## Below this speed (u/s) a velocity has no meaningful direction.
const STILL_SPEED := 0.05
## A ship held by traffic at or below this speed (u/s) is reported as waiting.
const WAIT_SPEED := 0.1
## Targets up to this cosine behind abeam still count as abeam for RCS translation.
const ABEAM_SLACK := 0.05
## Integration steps for the stopping distance.
const STOP_STEPS := 24


## Turn rate (rad/s) at the given forward speed, from the profile curve.
static func turn_rate(profile: MovementProfile, speed: float) -> float:
	var fraction := clampf(speed / profile.top_speed, 0.0, 1.0)
	return deg_to_rad(maxf(profile.turn_rate_curve.sample(fraction), 0.0))


## Turning radius (u) at the given forward speed.
static func turn_radius(profile: MovementProfile, speed: float) -> float:
	return speed / maxf(turn_rate(profile, speed), EPSILON)


## Highest speed whose turning radius fits within the given radius.
static func max_speed_for_radius(profile: MovementProfile, radius: float) -> float:
	if is_inf(radius) or turn_radius(profile, profile.top_speed) <= radius:
		return profile.top_speed
	var lo := 0.0
	var hi := profile.top_speed
	for i in 24:
		var mid := (lo + hi) * 0.5
		if turn_radius(profile, mid) <= radius:
			lo = mid
		else:
			hi = mid
	return lo


## Radius (u) of the turn needed to reach a point given in the ship frame
## (x = ahead, y = to the right). Points behind are capped at half their distance,
## so near targets behind demand slow, tight maneuvers and far ones allow wide turns.
static func reach_radius(local: Vector2) -> float:
	var radius := INF
	if absf(local.y) > EPSILON:
		radius = local.length_squared() / (2.0 * absf(local.y))
	if local.x < 0.0:
		radius = minf(radius, local.length() * 0.5)
	return radius


## RCS effectiveness (0..1) at the given forward speed, from the profile curve.
static func rcs_authority(profile: MovementProfile, speed: float) -> float:
	var fraction := clampf(speed / profile.top_speed, 0.0, 1.0)
	return clampf(profile.rcs_authority_curve.sample(fraction), 0.0, 1.0)


## Deceleration (u/s²) at the given speed: main braking plus the RCS braking assist.
static func effective_braking(profile: MovementProfile, speed: float) -> float:
	return profile.braking + profile.rcs_braking * rcs_authority(profile, speed)


## Distance (u) to stop from the given speed, with braking that varies with speed.
static func stopping_distance(profile: MovementProfile, speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	var step := speed / STOP_STEPS
	var distance := 0.0
	for i in STOP_STEPS:
		var u := (i + 0.5) * step
		distance += u / effective_braking(profile, u) * step
	return distance


## Highest speed that can still slow to end_speed within the given distance.
static func max_speed_to_reach(profile: MovementProfile, distance: float, end_speed: float) -> float:
	if end_speed >= profile.top_speed:
		return profile.top_speed
	return max_speed_for_stop(profile, maxf(distance, 0.0) + stopping_distance(profile, end_speed))


## Speed cap from the bends ahead: at each bend the turning radius must fit the bend radius,
## so the ship must be able to slow to that speed by the time it gets there.
## to_steer: distance (u) to the steer point; bends measure from the steer point.
static func corner_cap(profile: MovementProfile, to_steer: float, bends: PackedVector2Array) -> float:
	var cap := INF
	var horizon := stopping_distance(profile, profile.top_speed)
	var seen := {}
	for bend in bends:
		var distance := to_steer + bend.x
		if distance > horizon:
			break
		# The nearest bend of a given radius is always the tightest of them.
		if seen.has(bend.y):
			continue
		seen[bend.y] = true
		cap = minf(cap, max_speed_to_reach(profile, distance, max_speed_for_radius(profile, bend.y)))
	return cap


## Highest speed that can still stop within the given distance.
static func max_speed_for_stop(profile: MovementProfile, distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	if stopping_distance(profile, profile.top_speed) <= distance:
		return profile.top_speed
	var lo := 0.0
	var hi := profile.top_speed
	for i in 24:
		var mid := (lo + hi) * 0.5
		if stopping_distance(profile, mid) <= distance:
			lo = mid
		else:
			hi = mid
	return lo


## Where the ship would come to rest if it stopped now.
static func stop_point(profile: MovementProfile, m: MotionState) -> Vector2:
	var rcs_stop := m.rcs_velocity * m.rcs_velocity.length() / (2.0 * profile.rcs_acceleration)
	return m.position + m.forward() * stopping_distance(profile, m.speed) + rcs_stop


## Speed cap from a ship in the way at free_distance (u) ahead. Uses half the braking
## rate so two ships closing on each other both stop in time.
static func traffic_cap(profile: MovementProfile, free_distance: float) -> float:
	if is_inf(free_distance):
		return INF
	return sqrt(profile.braking * maxf(free_distance - profile.traffic_stop_margin, 0.0))


## Length (u) to check ahead for ships in the way.
static func traffic_probe_length(profile: MovementProfile, speed: float) -> float:
	return speed * speed / profile.braking + profile.traffic_lookahead


## guidance: where to steer and the bends ahead, from the Navigator; null steers straight
## at the order's destination (open space).
static func step(m: MotionState, profile: MovementProfile, order: MoveExecution, dt: float,
		traffic_speed_cap: float = INF, guidance: Guidance = null) -> MotionState:
	if order.status == MoveExecution.Status.SETTLING:
		return _settle(m, profile, order, dt)
	if order.status == MoveExecution.Status.COMPLETED:
		return coast(m, profile, dt)
	if guidance == null:
		guidance = Guidance.direct(order.destination)

	var n := m.copy()
	# Steer choice: the farthest route point reachable on an arc that stays in the corridor.
	# Before the first tick and during a rest manoeuvre the ship can move straight anywhere.
	var straight := order.rest_manoeuvre or not order.started
	var choice := choose_candidate(n, profile, guidance, straight)
	var pick := choice.x
	var corridor_blocked := choice.y == 1
	var target := guidance.candidates[pick]
	var is_final := guidance.is_goal(pick)
	order.steer_point = target
	var to_target := target - n.position
	var distance := to_target.length()
	var local := Vector2(to_target.dot(n.forward()), to_target.dot(n.right()))
	var remaining := distance + guidance.remaining_after_candidate(pick)
	var to_next := n.position.distance_to(guidance.steer_point())

	# A stationary ship with its destination abeam or behind starts a rest manoeuvre.
	if not order.started:
		order.started = true
		order.rest_manoeuvre = distance > profile.arrival_tolerance \
				and n.velocity().length() <= profile.rest_max_speed \
				and absf(angle_difference(n.heading, MotionState.heading_of(to_target))) \
						>= deg_to_rad(profile.rest_min_bearing_deg) - EPSILON
	if order.rest_manoeuvre:
		if absf(angle_difference(n.heading, MotionState.heading_of(to_target))) \
				<= deg_to_rad(profile.rest_align_deg):
			order.rest_manoeuvre = false
		else:
			_rest_manoeuvre(n, profile, order, to_target, remaining, dt)
			return _finish_tick(n, profile, order, target, is_final, dt)

	# 1. Target speed = the tightest of the limits.
	var arrival_cap := max_speed_for_stop(profile, remaining - profile.arrival_tolerance * 0.5)
	# Sideways speed widens the path too, so it counts against the speed the turn allows.
	var path_speed_cap := max_speed_for_radius(profile, reach_radius(local))
	var turn_cap := sqrt(maxf(path_speed_cap * path_speed_cap - n.rcs_velocity.length_squared(), 0.0))
	var target_speed := profile.top_speed
	order.binding_limit = &"top"
	if arrival_cap < target_speed:
		target_speed = arrival_cap
		order.binding_limit = &"arrival"
	if turn_cap < target_speed:
		target_speed = turn_cap
		order.binding_limit = &"turn"
	var bend_cap := corner_cap(profile, to_next, guidance.bends)
	if bend_cap < target_speed:
		target_speed = bend_cap
		order.binding_limit = &"corner"
	# No arc keeps the ship in the corridor at this heading: brake and re-evaluate.
	if corridor_blocked:
		target_speed = 0.0
		order.binding_limit = &"corridor"
	if traffic_speed_cap < target_speed:
		target_speed = traffic_speed_cap
		order.binding_limit = &"traffic"
	# Only gain forward speed in proportion to how well the bow points at the target.
	if target_speed > n.speed:
		var alignment := local.x / maxf(distance, EPSILON)
		target_speed = maxf(n.speed, minf(target_speed, profile.top_speed * maxf(alignment, 0.0)))

	# 2. Speed.
	var rate := profile.acceleration if target_speed > n.speed else effective_braking(profile, n.speed)
	n.speed = move_toward(n.speed, target_speed, rate * dt)

	# 3. Heading turns toward the target, limited by the speed-dependent turn rate.
	if distance > EPSILON:
		_turn_toward(n, profile, MotionState.heading_of(to_target), dt)

	# 4. RCS sideways translation toward the target, scaled by authority at this speed.
	# Only when the target is ahead or abeam: sliding toward a target behind swings it
	# further aft and the ship orbits it.
	var authority := rcs_authority(profile, n.speed)
	if local.x < -ABEAM_SLACK * distance:
		authority = 0.0
	var offset := to_target.dot(n.right())
	var desired_lateral := signf(offset) * authority \
			* minf(profile.rcs_max_speed, sqrt(2.0 * profile.rcs_acceleration * absf(offset)))
	n.rcs_velocity = n.rcs_velocity.move_toward(n.right() * desired_lateral, profile.rcs_acceleration * dt)

	order.waiting = order.binding_limit == &"traffic" and n.speed <= WAIT_SPEED
	return _finish_tick(n, profile, order, target, is_final, dt)


## Picks the candidate to steer at: the farthest one (within the top-speed stopping distance)
## whose arc from the ship, leaving along the bow, stays inside the corridor (straight lines
## when `straight`). Returns Vector2i(index, blocked): blocked = 1 when no arc fits at speed,
## so the helm must brake. Without a corridor, or with the ship outside it (e.g. after a
## contact), the next route point is used.
static func choose_candidate(m: MotionState, profile: MovementProfile, guidance: Guidance,
		straight: bool) -> Vector2i:
	var corridor := guidance.corridor
	if corridor == null or not corridor.contains(m.position):
		return Vector2i(0, 0)
	var horizon := stopping_distance(profile, profile.top_speed)
	var to_first := m.position.distance_to(guidance.steer_point())
	for k in range(guidance.candidates.size() - 1, -1, -1):
		if k > 0 and to_first + guidance.along[k] > horizon:
			continue
		if corridor.arc_inside(m.position, m.forward(), guidance.candidates[k], straight):
			return Vector2i(k, 0)
	# Slow enough to turn almost in place: steer at the next point and let the turn limit work.
	if m.speed <= profile.rest_max_speed:
		return Vector2i(0, 0)
	return Vector2i(0, 1)


## Rest manoeuvre: main engine off, hull rotates at its rest rate, RCS carries the ship
## straight toward the target. Moving straight at the target keeps its bearing fixed, so
## the hull's rotation always closes on it (no orbiting).
static func _rest_manoeuvre(n: MotionState, profile: MovementProfile, order: MoveExecution,
		to_target: Vector2, remaining: float, dt: float) -> void:
	order.binding_limit = &"rest"
	order.waiting = false
	n.speed = move_toward(n.speed, 0.0, effective_braking(profile, n.speed) * dt)
	_turn_toward(n, profile, MotionState.heading_of(to_target), dt)
	var cap := rcs_authority(profile, n.speed) * minf(profile.rcs_max_speed,
			sqrt(2.0 * profile.rcs_acceleration * maxf(remaining - profile.arrival_tolerance * 0.5, 0.0)))
	n.rcs_velocity = n.rcs_velocity.move_toward(to_target.normalized() * cap, profile.rcs_acceleration * dt)


## Moves the ship and starts settling once it is inside the tolerance and can stop inside it.
static func _finish_tick(n: MotionState, profile: MovementProfile, order: MoveExecution,
		target: Vector2, is_final: bool, dt: float) -> MotionState:
	n.position += n.velocity() * dt
	if is_final:
		var tolerance := profile.arrival_tolerance
		if n.position.distance_to(target) <= tolerance \
				and stop_point(profile, n).distance_to(target) <= tolerance:
			order.status = MoveExecution.Status.SETTLING
			order.waiting = false
			var v := n.velocity()
			order.final_heading = MotionState.heading_of(v) if v.length() > STILL_SPEED else n.heading
	return n


## Giving way: the main engine brakes, the heading is held, and RCS carries the ship toward
## point once its speed leaves RCS any authority. free_distance (u): gap to a ship in the way
## along the step, INF if clear; the ship stops short of it.
static func give_way_step(m: MotionState, profile: MovementProfile, point: Vector2, dt: float,
		free_distance: float = INF) -> MotionState:
	var n := m.copy()
	n.speed = move_toward(n.speed, 0.0, effective_braking(profile, n.speed) * dt)
	var to_point := point - n.position
	var room := to_point.length() - profile.arrival_tolerance * 0.5
	if not is_inf(free_distance):
		room = minf(room, free_distance - profile.traffic_stop_margin)
	var cap := rcs_authority(profile, n.speed) 			* minf(profile.rcs_max_speed, sqrt(2.0 * profile.rcs_acceleration * maxf(room, 0.0)))
	var desired := to_point.normalized() * cap if to_point.length() > EPSILON else Vector2.ZERO
	n.rcs_velocity = n.rcs_velocity.move_toward(desired, profile.rcs_acceleration * dt)
	n.position += n.velocity() * dt
	return n


## No active order: bleed off speed and sideways speed.
static func coast(m: MotionState, profile: MovementProfile, dt: float) -> MotionState:
	var n := m.copy()
	n.speed = move_toward(n.speed, 0.0, effective_braking(profile, n.speed) * dt)
	n.rcs_velocity = n.rcs_velocity.move_toward(Vector2.ZERO, profile.rcs_acceleration * dt)
	n.position += n.velocity() * dt
	return n


static func _settle(m: MotionState, profile: MovementProfile, order: MoveExecution, dt: float) -> MotionState:
	var n := m.copy()
	n.speed = move_toward(n.speed, 0.0, effective_braking(profile, n.speed) * dt)
	n.rcs_velocity = n.rcs_velocity.move_toward(Vector2.ZERO, profile.rcs_acceleration * dt)
	_turn_toward(n, profile, order.final_heading, dt)
	n.position += n.velocity() * dt
	var error := absf(angle_difference(n.heading, order.final_heading))
	if n.speed == 0.0 and n.rcs_velocity == Vector2.ZERO and error <= deg_to_rad(profile.heading_tolerance_deg):
		order.status = MoveExecution.Status.COMPLETED
	return n


static func _turn_toward(n: MotionState, profile: MovementProfile, desired: float, dt: float) -> void:
	var error := angle_difference(n.heading, desired)
	var max_turn := turn_rate(profile, n.speed) * dt
	n.heading = wrapf(n.heading + clampf(error, -max_turn, max_turn), -PI, PI)
