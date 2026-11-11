extends RefCounted
## OrderDelays: orders wait out their delay; a newer order replaces the waiting one.

const DT := 1.0 / 60.0


func _run_until_due(delays: OrderDelays, limit_s: float) -> Array:
	var time := 0.0
	while time < limit_s:
		time += DT
		var due := delays.tick(DT)
		if not due.is_empty():
			return [time, due]
	return [time, []]


func test_order_is_due_after_its_delay(t: TestContext) -> void:
	var delays := OrderDelays.new()
	var ship := RefCounted.new()
	delays.hold(ship, "go", 1.0)
	t.check(delays.pending(ship) == "go", "order waits")
	var result := _run_until_due(delays, 2.0)
	t.near(result[0], 1.0, DT + 1e-6, "due after the delay (s)")
	t.check(result[1] == [[ship, "go"]], "the waiting order is handed over")
	t.check(delays.pending(ship) == null, "nothing waits afterwards")
	t.check(delays.tick(DT).is_empty(), "handed over once")


func test_newer_order_replaces_and_restarts(t: TestContext) -> void:
	var delays := OrderDelays.new()
	var ship := RefCounted.new()
	delays.hold(ship, "first", 1.0)
	for i in int(0.5 / DT):
		t.check(delays.tick(DT).is_empty(), "nothing due yet")
	delays.hold(ship, "second", 1.0)
	var result := _run_until_due(delays, 2.0)
	t.near(result[0], 1.0, DT + 1e-6, "delay restarts from the newer order (s)")
	t.check(result[1] == [[ship, "second"]], "only the newer order is handed over")


func test_ships_wait_independently(t: TestContext) -> void:
	var delays := OrderDelays.new()
	var a := RefCounted.new()
	var b := RefCounted.new()
	delays.hold(a, "a", 0.5)
	delays.hold(b, "b", 1.0)
	var first := _run_until_due(delays, 2.0)
	t.check(first[1] == [[a, "a"]], "shorter delay first")
	t.check(delays.pending(b) == "b", "the other ship still waits")
	t.near(delays.time_left(b), 0.5, DT + 1e-6, "time left (s)")


func test_prune_drops_freed_ships(t: TestContext) -> void:
	var delays := OrderDelays.new()
	var keep := Node.new()
	var gone := Node.new()
	delays.hold(keep, "k", 1.0)
	delays.hold(gone, "g", 1.0)
	gone.free()
	delays.prune()
	var result := _run_until_due(delays, 2.0)
	t.check(result[1] == [[keep, "k"]], "a freed ship's order is dropped")
	keep.free()
