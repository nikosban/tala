extends RefCounted
## Obstacle scenarios as deterministic rollouts of MovementCore guided by NavigatorCore (no scene).
## Thresholds derive from the frigate profiles and hull.

const DT := 1.0 / 60.0

var p: MovementProfile = load("res://game/ship/classes/frigate/frigate.tres")
var nav: NavigatorProfile = load("res://game/ship/classes/frigate/frigate_navigator.tres")
var spin := _frigate_spin_radius()


static func _frigate_spin_radius() -> float:
	var ship: Node = load("res://game/ship/classes/frigate/frigate.tscn").instantiate()
	var radius := 0.0
	for child in ship.get_children():
		if child is CollisionShape3D:
			radius = NavigatorModule.hull_spin_radius(child.shape)
	ship.free()
	return radius


## Rocks as real (uninflated) circles Vector3(x, y, radius).
func _inflate(rocks: Array[Vector3], by: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r in rocks:
		out.append(Vector3(r.x, r.y, r.z + by))
	return out


## Runs one order to completion, wired like MovementModule.physics_step. Returns
## {done, min_gap, limits, min_speed_near, max_stray} where min_gap is the smallest distance
## between the hull's spin circle and any rock edge, min_speed_near the lowest speed while
## within near_rock (u) of a rock centre, and max_stray the furthest the ship strayed from the
## corridor centreline while inside the corridor's reach.
func _fly(start_speed: float, destination: Vector2, rocks: Array[Vector3], limit_s: float,
		heading: float = 0.0, near_rock: float = 0.0) -> Dictionary:
	var core := MovementCore.new(p)
	core.motion.speed = start_speed
	core.motion.heading = heading
	var navigator := NavigatorCore.new(nav, spin)
	var circles := _inflate(rocks, navigator.clearance)
	var obstacles := func() -> Array[Vector3]: return circles
	core.issue_move_order(destination)
	var result := {"done": false, "min_gap": INF, "limits": {}, "routed": false,
			"min_speed_near": INF, "max_stray": 0.0}
	var time := 0.0
	while time < limit_s:
		var travel := core.travel_direction()
		var turn_radius := PathFollower.turn_radius(p, core.motion.speed)
		if core.update_orders(DT):
			result.routed = navigator.start_route(core.motion.position, destination, circles, travel, turn_radius)
		var order := core.active
		var guidance: Guidance = null
		if order != null and order.status == MoveExecution.Status.MOVING:
			guidance = navigator.update(DT, core.motion.position, obstacles, travel, turn_radius)
		core.step(DT, guidance)
		time += DT
		for r in rocks:
			var to_centre := core.motion.position.distance_to(Vector2(r.x, r.y))
			result.min_gap = minf(result.min_gap, to_centre - r.z - spin)
			if to_centre <= near_rock:
				result.min_speed_near = minf(result.min_speed_near, core.motion.speed)
		if guidance != null and order.binding_limit != &"corridor":
			result.max_stray = maxf(result.max_stray, guidance.corridor.distance_to_centreline(core.motion.position))
		if order != null:
			result.limits[order.binding_limit] = true
		if order != null and order.status == MoveExecution.Status.COMPLETED:
			result.done = true
			result.final_error = core.motion.position.distance_to(destination)
			break
	return result


func _limit(distance: float) -> float:
	return distance / (p.top_speed * 0.25) + 2.0 * (p.top_speed / p.acceleration + p.top_speed / p.braking) + 120.0


func test_rock_ahead_at_speed_routes_around(t: TestContext) -> void:
	var rocks: Array[Vector3] = [Vector3(0, -500, 30)]
	var r := _fly(p.top_speed, Vector2(0, -1000), rocks, _limit(1000.0))
	t.check(r.routed, "route planned")
	t.check(r.done, "order completes")
	t.at_least(r.min_gap, 0.0, "spin circle gap to rock (u)")
	t.check(r.limits.has(&"corner"), "bend speed limit slows the ship")
	if r.done:
		t.at_most(r.final_error, p.arrival_tolerance, "final position error (u)")


func test_rock_ahead_from_rest_routes_around(t: TestContext) -> void:
	var rocks: Array[Vector3] = [Vector3(0, -150, 25)]
	var r := _fly(0.0, Vector2(0, -300), rocks, _limit(300.0))
	t.check(r.done, "order completes")
	t.at_least(r.min_gap, 0.0, "spin circle gap to rock (u)")


func test_rock_field(t: TestContext) -> void:
	var rocks: Array[Vector3] = [Vector3(-40, -300, 15), Vector3(40, -380, 20), Vector3(-10, -470, 18),
			Vector3(60, -560, 12)]
	var r := _fly(p.top_speed * 0.5, Vector2(0, -800), rocks, _limit(800.0))
	t.check(r.done, "order completes")
	t.at_least(r.min_gap, 0.0, "spin circle gap to rocks (u)")


func test_fast_ship_facing_away_routes_around(t: TestContext) -> void:
	# Heading -90 deg faces +X (east); the destination lies north beyond a rock.
	var rocks: Array[Vector3] = [Vector3(0, -400, 30)]
	var r := _fly(p.top_speed, Vector2(0, -800), rocks, _limit(1200.0), -PI * 0.5)
	t.check(r.done, "order completes")
	t.at_least(r.min_gap, 0.0, "spin circle gap to rock (u)")


func test_wide_corridor_corners_faster_than_hugging(t: TestContext) -> void:
	var rock := Vector3(0, -500, 30)
	var rocks: Array[Vector3] = [rock]
	var clearance := spin + nav.obstacle_margin
	var hugging_speed := PathFollower.max_speed_for_radius(p, rock.z + clearance)
	var r := _fly(p.top_speed, Vector2(0, -1000), rocks, _limit(1000.0), 0.0,
			rock.z + clearance + nav.corridor_half_width)
	t.check(r.done, "order completes")
	t.at_least(r.min_speed_near, hugging_speed * 1.2, "lowest speed passing the rock (u/s)")
	t.at_least(r.min_gap, 0.0, "spin circle gap to rock (u)")


func test_stays_in_corridor(t: TestContext) -> void:
	var rocks: Array[Vector3] = [Vector3(-40, -300, 15), Vector3(40, -380, 20), Vector3(-10, -470, 18)]
	var r := _fly(p.top_speed * 0.5, Vector2(0, -700), rocks, _limit(700.0))
	t.check(r.done, "order completes")
	t.at_most(r.max_stray, nav.corridor_half_width + 2.0, "distance from the corridor centreline (u)")
