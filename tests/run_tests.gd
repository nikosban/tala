extends SceneTree
## Headless test runner. Usage (from the project folder):
##   godot --headless --fixed-fps 60 --path . -s tests/run_tests.gd
## Runs every method starting with "test_" in the suites below. Methods may await.
## Exits with code 1 if any check fails. A test also fails if it logs a script or engine
## error (it crashed) or makes no checks; a suite that fails to load fails too.

const SUITES := [
	"res://tests/unit/test_path_follower.gd",
	"res://tests/scenarios/test_movement_scenarios.gd",
	"res://tests/scenarios/test_ship_scene.gd",
	"res://tests/unit/test_route_planner.gd",
	"res://tests/unit/test_corridor.gd",
	"res://tests/scenarios/test_obstacle_scenarios.gd",
	"res://tests/scenarios/test_obstacle_scene.gd",
	"res://tests/unit/test_command_core.gd",
	"res://tests/unit/test_order_delays.gd",
	"res://tests/unit/test_right_of_way.gd",
	"res://tests/scenarios/test_fleet_scene.gd",
	"res://tests/scenarios/test_debug_tools.gd",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ctx := TestContext.new()
	ctx.tree = self
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var tests := 0
	for path in SUITES:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			ctx.current = path.get_file().get_basename()
			ctx.check(false, "suite failed to load or compile")
			print("FAIL %s" % ctx.current)
			continue
		var suite: Object = script.new()
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			ctx.current = "%s::%s" % [path.get_file().get_basename(), name]
			var before := ctx.failures.size()
			var checks_before := ctx.checks
			var errors_before := errors.count()
			await suite.call(name, ctx)
			tests += 1
			# A test that hit a script error stops early; it must not pass silently.
			var made_checks := ctx.checks - checks_before
			var new_errors := errors.count() - errors_before
			ctx.check(new_errors == 0, "%d script/engine errors" % new_errors)
			ctx.check(made_checks > 0, "made no checks")
			print("%s %s" % ["PASS" if ctx.failures.size() == before else "FAIL", ctx.current])
	print("")
	for failure in ctx.failures:
		print("  - " + failure)
	print("%d tests, %d checks, %d failures" % [tests, ctx.checks, ctx.failures.size()])
	quit(1 if ctx.failures.size() > 0 else 0)
