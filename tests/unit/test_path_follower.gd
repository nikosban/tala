extends RefCounted
## Rule-level checks of PathFollower. Thresholds derive from the frigate profile.

const DT := 1.0 / 60.0

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")


func _state(speed: float = 0.0, heading: float = 0.0) -> MotionState:
	var m := MotionState.new()
	m.speed = speed
	m.heading = heading
	return m


func test_turn_rate_follows_curve(t: TestContext) -> void:
	t.near(rad_to_deg(PathFollower.turn_rate(p, 0.0)), p.turn_rate_curve.sample(0.0), 0.001, "rest turn rate")
	t.near(rad_to_deg(PathFollower.turn_rate(p, p.top_speed)), p.turn_rate_curve.sample(1.0), 0.001, "top turn rate")
	t.check(PathFollower.turn_rate(p, p.top_speed) <= PathFollower.turn_rate(p, 0.0), "turn rate does not rise with speed")


func test_max_speed_for_radius_fits_radius(t: TestContext) -> void:
	var top_radius := PathFollower.turn_radius(p, p.top_speed)
	t.near(PathFollower.max_speed_for_radius(p, top_radius * 2.0), p.top_speed, 0.0001, "speed for wide radius")
	var previous := 0.0
	for fraction in [0.05, 0.2, 0.5, 0.9]:
		var radius: float = top_radius * fraction
		var v := PathFollower.max_speed_for_radius(p, radius)
		t.at_most(PathFollower.turn_radius(p, v), radius + 0.01, "turn radius at capped speed")
		t.check(v >= previous, "cap grows with radius")
		previous = v


func test_reach_radius(t: TestContext) -> void:
	t.check(is_inf(PathFollower.reach_radius(Vector2(100, 0))), "straight ahead needs no turn")
	t.near(PathFollower.reach_radius(Vector2(0, 50)), 25.0, 0.001, "beside: half the distance")
	t.near(PathFollower.reach_radius(Vector2(-80, 0)), 40.0, 0.001, "directly behind: half the distance")
	t.check(PathFollower.reach_radius(Vector2(-10, 0)) < PathFollower.reach_radius(Vector2(-1000, 0)),
			"near targets behind need tighter turns than far ones")


func test_speed_respects_acceleration_and_braking(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(0, -100000))
	var n := PathFollower.step(_state(), p, order, DT)
	t.near(n.speed, p.acceleration * DT, 0.000001, "speed gain in one tick")
	order = MoveExecution.new(Vector2(0, -1))
	n = PathFollower.step(_state(p.top_speed), p, order, DT)
	t.near(n.speed, p.top_speed - PathFollower.effective_braking(p, p.top_speed) * DT, 0.000001, "speed loss in one tick")


func test_heading_change_limited_by_turn_rate(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(1000, 0))
	var m := _state(p.top_speed)
	var n := PathFollower.step(m, p, order, DT)
	t.at_most(absf(angle_difference(m.heading, n.heading)), PathFollower.turn_rate(p, p.top_speed) * DT + 1e-6, "heading change")


## Lowest speed at which RCS authority reaches zero (top speed if it never does).
static func rcs_fade_speed(profile: MovementProfile) -> float:
	for i in 1001:
		var speed := profile.top_speed * i / 1000.0
		if PathFollower.rcs_authority(profile, speed) <= 1e-6:
			return speed
	return profile.top_speed


func test_no_lateral_without_authority(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(500, -500))
	var speed := minf(rcs_fade_speed(p) * 1.5, p.top_speed)
	var n := PathFollower.step(_state(speed), p, order, DT)
	t.near(n.rcs_velocity.length(), 0.0, 1e-9, "RCS speed where RCS authority is zero")


func test_lateral_toward_side_target_at_rest(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(50, 0))  # to the right of a ship facing -Z
	var m := PathFollower.step(_state(), p, order, DT)
	t.near(m.rcs_velocity.length(), p.rcs_acceleration * DT, 1e-9, "RCS speed gain in one tick (rcs_acceleration)")
	var peak := m.rcs_velocity.length()
	var within_authority := true
	for i in 120:
		var limit := PathFollower.rcs_authority(p, m.speed) * p.rcs_max_speed
		m = PathFollower.step(m, p, order, DT)
		peak = maxf(peak, m.rcs_velocity.length())
		# Sideways speed may only exceed the current authority while it decays toward it.
		within_authority = within_authority and (m.rcs_velocity.length() <= limit + 1e-6 \
				or m.rcs_velocity.length() < peak)
	t.check(peak > 0.0 and m.rcs_velocity.x >= 0.0, "slides toward the right")
	t.check(within_authority, "sideways speed never grows beyond authority × rcs_max_speed")


func test_braking_assist_scales_with_authority(t: TestContext) -> void:
	var expected := p.rcs_braking * (PathFollower.rcs_authority(p, 0.0) - PathFollower.rcs_authority(p, p.top_speed))
	t.near(PathFollower.effective_braking(p, 0.0) - PathFollower.effective_braking(p, p.top_speed),
			expected, 1e-6, "braking difference rest vs top speed")


func test_stopping_distance_matches_simulated_stop(t: TestContext) -> void:
	for speed: float in [p.top_speed, rcs_fade_speed(p), rcs_fade_speed(p) * 0.5]:
		var m := _state(speed)
		var travelled := 0.0
		while m.speed > 0.0:
			var before := m.position
			m = PathFollower.coast(m, p, DT)
			travelled += before.distance_to(m.position)
		var predicted := PathFollower.stopping_distance(p, speed)
		t.near(travelled, predicted, predicted * 0.02 + speed * DT, "stop from %.1f u/s (u)" % speed)


func test_no_settle_when_passing_through_fast(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(0, -0.5))
	PathFollower.step(_state(p.top_speed), p, order, DT)
	t.check(order.status == MoveExecution.Status.MOVING, "still moving while too fast to stop inside tolerance")


func test_settles_when_slow_inside_tolerance(t: TestContext) -> void:
	var order := MoveExecution.new(Vector2(0, -0.5))
	PathFollower.step(_state(0.2), p, order, DT)
	t.check(order.status == MoveExecution.Status.SETTLING, "settles when it can stop inside tolerance")
	t.near(order.final_heading, 0.0, 0.001, "final heading is the travel direction")
