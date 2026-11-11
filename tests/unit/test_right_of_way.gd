extends RefCounted
## RightOfWay rules and the give-way step. Thresholds derive from the frigate profile.

const DT := 1.0 / 60.0

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")


func _snap(position: Vector2, direction: Vector2, speed: float, moving: bool) -> Dictionary:
	return {
		"position": position,
		"velocity": direction * speed,
		"travel_direction": direction,
		"speed": speed,
		"spin_radius": 10.0,
		"has_moving_order": moving,
	}


func test_moving_order_beats_none(t: TestContext) -> void:
	var mover := _snap(Vector2.ZERO, Vector2.UP, 0.0, true)
	var idle := _snap(Vector2(0, -50), Vector2.UP, 0.0, false)
	t.check(RightOfWay.has_priority(mover, idle, 2, 1), "a ship with a moving order beats an idle one")
	t.check(not RightOfWay.has_priority(idle, mover, 1, 2), "the idle ship agrees")


func test_faster_ship_wins_then_id(t: TestContext) -> void:
	var fast := _snap(Vector2.ZERO, Vector2.UP, 10.0, true)
	var slow := _snap(Vector2(0, -50), Vector2.DOWN, 3.0, true)
	t.check(RightOfWay.has_priority(fast, slow, 9, 1), "the faster ship wins")
	t.check(not RightOfWay.has_priority(slow, fast, 1, 9), "the slower ship agrees")
	var a := _snap(Vector2.ZERO, Vector2.UP, 5.0, true)
	var b := _snap(Vector2(0, -50), Vector2.DOWN, 5.0, true)
	t.check(RightOfWay.has_priority(a, b, 1, 2) and not RightOfWay.has_priority(b, a, 2, 1),
			"equal speeds: the lower id wins, both agree")


func test_following_needs_no_negotiation(t: TestContext) -> void:
	# Both travel toward -Z (Vector2.UP); `ahead` is ahead of `me` and still moving away.
	var me := _snap(Vector2.ZERO, Vector2.UP, 8.0, true)
	var ahead := _snap(Vector2(0, -60), Vector2.UP, 4.0, true)
	t.check(not RightOfWay.needs_negotiation(me, ahead), "a ship moving away ahead is followed")
	var oncoming := _snap(Vector2(0, -60), Vector2.DOWN, 4.0, true)
	t.check(RightOfWay.needs_negotiation(me, oncoming), "an oncoming ship needs right of way")
	var idle := _snap(Vector2(0, -60), Vector2.UP, 0.0, false)
	t.check(RightOfWay.needs_negotiation(me, idle), "an idle ship in the way needs right of way")


func test_release_after_passing(t: TestContext) -> void:
	var required := 25.0
	var yielder := _snap(Vector2(30, 0), Vector2.UP, 0.0, false)
	var coming := _snap(Vector2(0, 100), Vector2.UP, 8.0, true)
	t.check(not RightOfWay.can_release(yielder, coming, required), "not released while it approaches")
	var past := _snap(Vector2(0, -40), Vector2.UP, 8.0, true)
	t.check(RightOfWay.can_release(yielder, past, required), "released once it has gone past")
	var stopped := _snap(Vector2(0, 10), Vector2.UP, 0.0, false)
	t.check(RightOfWay.can_release(yielder, stopped, required), "released when it no longer moves on an order")


func test_step_options_prefer_own_side(t: TestContext) -> void:
	var options := RightOfWay.step_options(4.0, 25.0)
	t.near(options[0], 21.0, 0.0001, "preferred step reaches the required offset on its side")
	t.near(options[1], -29.0, 0.0001, "fallback step crosses to the other side")
	t.near(RightOfWay.step_options(-30.0, 25.0)[0], 0.0, 0.0001, "already clear: no step")
	t.near(RightOfWay.step_options(0.0, 25.0)[0], 25.0, 0.0001, "on the line: a fixed side")


func test_give_way_step_holds_heading_and_translates(t: TestContext) -> void:
	var m := MotionState.new()
	m.heading = 0.3
	var point := Vector2(25, 0)
	for i in int(60.0 / DT):
		m = PathFollower.give_way_step(m, p, point, DT)
	t.near(m.heading, 0.3, 0.0001, "heading held")
	t.at_most(m.position.distance_to(point), p.arrival_tolerance, "reaches the step-aside point")
	t.at_most(m.rcs_velocity.length(), 0.05, "comes to rest there")


func test_give_way_step_brakes_before_sliding_at_speed(t: TestContext) -> void:
	var m := MotionState.new()
	m.speed = p.top_speed
	var point := m.position + m.right() * 25.0
	m = PathFollower.give_way_step(m, p, point, DT)
	t.check(m.speed < p.top_speed, "main engine brakes")
	t.at_most(m.rcs_velocity.length(),
			PathFollower.rcs_authority(p, p.top_speed) * p.rcs_max_speed + 0.0001,
			"sideways speed limited by RCS authority at speed")
