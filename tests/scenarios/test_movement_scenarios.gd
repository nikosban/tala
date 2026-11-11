extends RefCounted
## Movement scenarios (design doc section 9) as deterministic rollouts of MovementCore.
## Feel targets come from frigate_feel_targets.tres; every other threshold derives from
## the frigate profile, so retuning never requires editing these tests.
## Ship frame at heading 0: forward = (0, -1), right = (1, 0).

const DT := 1.0 / 60.0

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")
var targets: MovementFeelTargets = load("res://game/ship/classes/frigate/frigate_feel_targets.tres")
var hull: float = targets.hull_length
## Speed at which RCS authority reaches zero: the edge of the low-speed regime.
var fade: float = preload("res://tests/unit/test_path_follower.gd").rcs_fade_speed(p)


# --- helpers ------------------------------------------------------------------

func _core(speed: float = 0.0) -> MovementCore:
	var core := MovementCore.new(p)
	core.motion.speed = speed
	return core


## Issues an order that activates on the next tick.
func _start(core: MovementCore, destination: Vector2) -> MoveExecution:
	core.issue_move_order(destination)
	return core.incoming


## Generous time limit for a trip of the given length, derived from the profile.
func _time_limit(distance: float) -> float:
	var rest_rate := p.turn_rate_curve.sample(0.0)
	return distance / (p.top_speed * 0.5) + 2.0 * (p.top_speed / p.acceleration + p.top_speed / p.braking) \
			+ 720.0 / rest_rate + 10.0


func _top_turn_radius() -> float:
	return PathFollower.turn_radius(p, p.top_speed)


## Ticks the core until the order completes or time runs out. on_tick(core, time) runs after each tick.
func _run(core: MovementCore, order: MoveExecution, limit: float, on_tick: Callable = Callable()) -> bool:
	var time := 0.0
	while time < limit:
		core.tick(DT)
		time += DT
		if on_tick.is_valid():
			on_tick.call(core, time)
		if order.status == MoveExecution.Status.COMPLETED:
			return true
	return false


func _local(core: MovementCore, point: Vector2) -> Vector2:
	var d := point - core.motion.position
	return Vector2(d.dot(core.motion.forward()), d.dot(core.motion.right()))


# --- feel targets ---------------------------------------------------------------

func test_feel_rest_to_top_speed(t: TestContext) -> void:
	var core := _core()
	_start(core, Vector2(0, -1000000))
	var time := 0.0
	while core.motion.speed < p.top_speed - 1e-6 and time < 600.0:
		core.tick(DT)
		time += DT
	var target := targets.rest_to_top_speed_s
	t.near(time, target, target * targets.tolerance_fraction, "rest to top speed (s)")


func test_feel_stop_distance(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var order := _start(core, Vector2(0, -3000))
	var state := {"brake_start": null}
	var completed := _run(core, order, _time_limit(3000), func(c: MovementCore, _time: float) -> void:
		if state.brake_start == null and c.motion.speed < p.top_speed:
			state.brake_start = c.motion.position)
	t.check(completed, "order completes")
	if state.brake_start != null:
		var distance: float = (state.brake_start as Vector2).distance_to(core.motion.position)
		var target := targets.stop_distance_hull_lengths * hull
		t.near(distance, target, target * targets.tolerance_fraction, "stop distance from top speed (u)")


func test_feel_quarter_turn_at_rest(t: TestContext) -> void:
	# A target directly behind: the first 90 degrees of the turn happen with no forward speed.
	var core := _core()
	_start(core, Vector2(0, 5.0 * hull))
	var time := 0.0
	var max_speed := 0.0
	while absf(core.motion.heading) < PI * 0.5 and time < 600.0:
		core.tick(DT)
		time += DT
		max_speed = maxf(max_speed, core.motion.speed)
	t.near(max_speed, 0.0, 1e-6, "forward speed during the quarter turn")
	var target := targets.quarter_turn_at_rest_s
	t.near(time, target, target * targets.tolerance_fraction, "quarter turn at rest (s)")


# --- section 9 situations ------------------------------------------------------

func test_from_rest_sideways(t: TestContext) -> void:
	var core := _core()
	var destination := Vector2(hull, 0)
	var order := _start(core, destination)
	var state := {"moved_at": -1.0, "facing_at": -1.0}
	var completed := _run(core, order, _time_limit(hull), func(c: MovementCore, time: float) -> void:
		if state.moved_at < 0.0 and c.motion.position.length() > p.arrival_tolerance:
			state.moved_at = time
		if order.status != MoveExecution.Status.MOVING and state.facing_at < 0.0 \
				and absf(angle_difference(c.motion.heading, order.final_heading)) <= deg_to_rad(p.heading_tolerance_deg):
			state.facing_at = time)
	t.check(completed, "order completes")
	t.check(state.moved_at >= 0.0 and state.moved_at < state.facing_at, "ship moves before its rotation finishes")
	t.at_most(absf(angle_difference(core.motion.heading, order.final_heading)),
			deg_to_rad(p.heading_tolerance_deg), "heading error at completion (rad)")
	t.at_most(core.motion.position.distance_to(destination), p.arrival_tolerance, "final position error")


func test_wide_turn_keeps_momentum(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var distance := 20.0 * _top_turn_radius()
	var destination := Vector2(distance, 0)
	var order := _start(core, destination)
	var state := {"min_speed": INF}
	var completed := _run(core, order, _time_limit(distance * 2.0), func(c: MovementCore, _time: float) -> void:
		var remaining := c.motion.position.distance_to(destination)
		if remaining > 2.0 * PathFollower.stopping_distance(p, p.top_speed):
			state.min_speed = minf(state.min_speed, c.motion.speed))
	t.check(completed, "order completes")
	t.at_least(state.min_speed, 0.9 * p.top_speed, "minimum speed through the turn")


func test_nearby_sharp_turn_slows(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var r := 0.6 * _top_turn_radius()
	var destination := Vector2(r, -r)
	var order := _start(core, destination)
	var state := {"min_speed": INF, "min_ahead": INF}
	var completed := _run(core, order, _time_limit(4.0 * r), func(c: MovementCore, _time: float) -> void:
		state.min_speed = minf(state.min_speed, c.motion.speed)
		if order.status == MoveExecution.Status.MOVING:
			state.min_ahead = minf(state.min_ahead, _local(c, destination).x))
	t.check(completed, "order completes")
	t.at_most(state.min_speed, 0.95 * p.top_speed, "speed was reduced for the turn")
	t.at_least(state.min_ahead, -p.arrival_tolerance, "overshoot past the destination (target ahead distance)")


func test_distant_reversal_wide_arc(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var distance := 20.0 * _top_turn_radius()
	var destination := Vector2(0, distance)
	var order := _start(core, destination)
	var state := {"min_speed": INF, "max_side": 0.0}
	var completed := _run(core, order, _time_limit(distance * 2.0), func(c: MovementCore, _time: float) -> void:
		state.max_side = maxf(state.max_side, absf(c.motion.position.x))
		if c.motion.position.distance_to(destination) > 2.0 * PathFollower.stopping_distance(p, p.top_speed):
			state.min_speed = minf(state.min_speed, c.motion.speed))
	t.check(completed, "order completes")
	t.at_least(state.min_speed, fade, "minimum speed during the reversal")
	t.at_least(state.max_side, _top_turn_radius(), "sideways extent of the arc")


func test_close_reversal_stops_and_repositions(t: TestContext) -> void:
	var core := _core(fade)
	var destination := Vector2(0, 0.25 * hull)
	var order := _start(core, destination)
	var state := {"min_speed": INF}
	var completed := _run(core, order, _time_limit(hull), func(c: MovementCore, _time: float) -> void:
		state.min_speed = minf(state.min_speed, c.motion.speed))
	t.check(completed, "order completes")
	t.at_most(state.min_speed, 0.05 * fade, "speed drops to about zero")
	t.at_most(core.motion.position.distance_to(destination), p.arrival_tolerance, "final position error")


func test_point_beside_at_top_speed(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var destination := Vector2(hull, 0)
	var order := _start(core, destination)
	var state := {"turned": 0.0, "last": 0.0}
	var completed := _run(core, order, _time_limit(4.0 * PathFollower.stopping_distance(p, p.top_speed)),
			func(c: MovementCore, _time: float) -> void:
				state.turned += absf(angle_difference(state.last, c.motion.heading))
				state.last = c.motion.heading)
	t.check(completed, "order completes within the time limit")
	t.at_most(rad_to_deg(state.turned), 540.0, "accumulated heading change (deg)")


func test_arrival_settles_on_travel_direction(t: TestContext) -> void:
	var core := _core()
	var destination := Vector2(0, -10.0 * hull)
	var order := _start(core, destination)
	var state := {"settle_heading": null, "moved_after_settle": false}
	var completed := _run(core, order, _time_limit(10.0 * hull), func(c: MovementCore, _time: float) -> void:
		if order.status == MoveExecution.Status.SETTLING and state.settle_heading == null:
			var v := c.motion.velocity()
			state.settle_heading = MotionState.heading_of(v) if v.length() > PathFollower.STILL_SPEED else c.motion.heading
		if state.settle_heading != null and order.status == MoveExecution.Status.MOVING:
			state.moved_after_settle = true)
	t.check(completed, "order completes")
	t.at_most(core.motion.position.distance_to(destination), p.arrival_tolerance, "final position error")
	t.check(not state.moved_after_settle, "never returns to moving after settling starts")
	if state.settle_heading != null:
		t.at_most(absf(angle_difference(core.motion.heading, state.settle_heading)),
				deg_to_rad(p.heading_tolerance_deg), "final heading vs travel direction at settle (rad)")


func test_pass_through_keeps_moving(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var destination := Vector2(0, -0.5 * hull)
	var order := _start(core, destination)
	var state := {"moving_inside": false}
	var completed := _run(core, order, _time_limit(4.0 * PathFollower.stopping_distance(p, p.top_speed)),
			func(c: MovementCore, _time: float) -> void:
				if order.status == MoveExecution.Status.MOVING \
						and c.motion.position.distance_to(destination) <= p.arrival_tolerance:
					state.moving_inside = true)
	t.check(state.moving_inside, "crosses the tolerance in the moving state")
	t.check(completed, "comes back and completes")


func test_forced_overshoot_returns(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var destination := Vector2(0, -hull)
	var order := _start(core, destination)
	var state := {"min_ahead": INF}
	var completed := _run(core, order, _time_limit(4.0 * PathFollower.stopping_distance(p, p.top_speed)),
			func(c: MovementCore, _time: float) -> void:
				state.min_ahead = minf(state.min_ahead, _local(c, destination).x))
	t.check(state.min_ahead < -p.arrival_tolerance, "overshoots when it cannot stop in time")
	t.check(completed, "returns and completes within the time limit")
	t.at_most(core.motion.position.distance_to(destination), p.arrival_tolerance, "final position error")


func test_low_speed_arrival_uses_braking_assist(t: TestContext) -> void:
	var start_speed := fade * 0.8
	var core := _core(start_speed)
	var distance := PathFollower.stopping_distance(p, start_speed) + p.arrival_tolerance * 0.5
	var destination := Vector2(0, -distance)
	var order := _start(core, destination)
	var state := {"min_ahead": INF, "stopped_at": null}
	var completed := _run(core, order, _time_limit(distance), func(c: MovementCore, _time: float) -> void:
		state.min_ahead = minf(state.min_ahead, _local(c, destination).x)
		if state.stopped_at == null and c.motion.speed == 0.0:
			state.stopped_at = c.motion.position)
	t.check(completed, "order completes")
	t.at_most(core.motion.position.distance_to(destination), p.arrival_tolerance, "final position error")
	t.at_least(state.min_ahead, -p.arrival_tolerance, "overshoot past the destination (target ahead distance)")
	if state.stopped_at != null:
		var main_only := start_speed * start_speed / (2.0 * p.braking)
		t.check(absf((state.stopped_at as Vector2).y) < main_only,
				"stops shorter (%.2f u) than main braking alone (%.2f u)" % [absf((state.stopped_at as Vector2).y), main_only])


## Runs a rest manoeuvre from rest at heading 0 toward destination and records its behaviour.
func _run_rest_manoeuvre(destination: Vector2) -> Dictionary:
	var core := _core()
	var order := _start(core, destination)
	var start_distance := destination.length()
	var state := {
		"completed": false, "used": false, "max_speed_in_rest": 0.0,
		"closed_before_aligned": 0.0, "max_distance_gain": 0.0, "turned": 0.0,
		"last_heading": 0.0, "min_distance": start_distance,
	}
	state.completed = _run(core, order, _time_limit(start_distance), func(c: MovementCore, _time: float) -> void:
		var distance := c.motion.position.distance_to(destination)
		if order.rest_manoeuvre:
			state.used = true
			state.max_speed_in_rest = maxf(state.max_speed_in_rest, c.motion.speed)
			state.closed_before_aligned = start_distance - distance
		state.max_distance_gain = maxf(state.max_distance_gain, distance - state.min_distance)
		state.min_distance = minf(state.min_distance, distance)
		state.turned += absf(angle_difference(state.last_heading, c.motion.heading))
		state.last_heading = c.motion.heading)
	state.final_error = core.motion.position.distance_to(destination)
	return state


func test_rest_manoeuvre_abeam(t: TestContext) -> void:
	var s := _run_rest_manoeuvre(Vector2(5.0 * hull, 0))
	t.check(s.used, "a stationary ship with the destination abeam uses the rest manoeuvre")
	t.check(s.completed, "order completes")
	t.near(s.max_speed_in_rest, 0.0, 1e-9, "main-engine speed during the rest manoeuvre")
	t.at_least(s.closed_before_aligned, p.arrival_tolerance, "distance closed before the bow aligned (u)")
	t.at_most(s.final_error, p.arrival_tolerance, "final position error")


func test_rest_manoeuvre_behind(t: TestContext) -> void:
	var s := _run_rest_manoeuvre(Vector2(0.01 * hull, 3.0 * hull))
	t.check(s.used, "a stationary ship with the destination behind uses the rest manoeuvre")
	t.check(s.completed, "order completes")
	t.near(s.max_speed_in_rest, 0.0, 1e-9, "main-engine speed during the rest manoeuvre")
	t.at_least(s.closed_before_aligned, p.arrival_tolerance, "distance closed before the bow aligned (u)")
	t.at_most(s.max_distance_gain, p.arrival_tolerance, "distance to destination never grows (no orbit)")
	t.at_most(rad_to_deg(s.turned), 180.0 + 2.0 * p.rest_align_deg, "accumulated heading change (deg)")


func test_rest_manoeuvre_close_behind_arrives_first(t: TestContext) -> void:
	# Close enough that RCS arrives before the hull has turned; it then finishes rotating.
	var destination := Vector2(0.01 * hull, 0.5 * hull)
	var s := _run_rest_manoeuvre(destination)
	t.check(s.used, "uses the rest manoeuvre")
	t.check(s.completed, "order completes")
	t.at_most(s.final_error, p.arrival_tolerance, "final position error")


func test_moving_ship_skips_rest_manoeuvre(t: TestContext) -> void:
	var core := _core(p.rest_max_speed + fade)
	var order := _start(core, Vector2(0, 3.0 * hull))
	core.tick(DT)
	t.check(not order.rest_manoeuvre, "a moving ship with the destination behind keeps the normal rules")


func test_orders_complete_across_sweep(t: TestContext) -> void:
	# Guards against orbiting: every start speed / bearing / distance combination completes.
	var speeds := [0.0, fade * 0.5, fade, p.top_speed * 0.5, p.top_speed]
	var distances := [hull * 0.25, hull, hull * 3.0, hull * 10.0]
	var failures := 0
	var worst := ""
	for speed: float in speeds:
		for distance: float in distances:
			for i in 12:
				var angle := TAU * i / 12.0 + 0.01
				var destination := Vector2(sin(angle), -cos(angle)) * distance
				var core := _core(speed)
				var order := _start(core, destination)
				var limit := _time_limit(distance + 2.0 * PathFollower.stopping_distance(p, speed))
				if not _run(core, order, limit) \
						or core.motion.position.distance_to(destination) > p.arrival_tolerance:
					failures += 1
					worst = "speed %.1f, distance %.0f, bearing %.0f deg" % [speed, distance, rad_to_deg(angle)]
	t.check(failures == 0, "%d orders did not complete in time (e.g. %s)" % [failures, worst])


func test_new_order_swaps_in_smoothly(t: TestContext) -> void:
	var core := _core(p.top_speed)
	var first := Vector2(0, -5000)
	_start(core, first)
	for i in 120:
		core.tick(DT)
	var second := Vector2(3000, -1000)
	core.issue_move_order(second)
	t.check(core.active.destination == first, "previous order runs until the next tick")
	var previous := core.motion.copy()
	core.tick(DT)
	t.check(core.active.destination == second, "new order active on the next tick")
	t.at_most(absf(core.motion.speed - previous.speed), maxf(p.acceleration, p.braking) * DT + 1e-6, "speed step at swap")
	t.at_most(absf(angle_difference(previous.heading, core.motion.heading)),
			PathFollower.turn_rate(p, 0.0) * DT + 1e-6, "heading step at swap")
