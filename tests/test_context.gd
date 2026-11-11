class_name TestContext
extends RefCounted
## Assertion collector passed to every test method.

var tree: SceneTree
var current := ""
var failures: Array[String] = []
var checks := 0


func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append("%s: %s" % [current, message])
	return condition


func near(actual: float, expected: float, tolerance: float, what: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
			"%s = %.3f, expected %.3f ± %.3f" % [what, actual, expected, tolerance])


func at_most(actual: float, limit: float, what: String) -> bool:
	return check(actual <= limit, "%s = %.3f, expected ≤ %.3f" % [what, actual, limit])


func at_least(actual: float, limit: float, what: String) -> bool:
	return check(actual >= limit, "%s = %.3f, expected ≥ %.3f" % [what, actual, limit])
