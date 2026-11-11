class_name OrderDelays
extends RefCounted
## Scene-free order delay: holds at most one order per ship until its delay runs out.
## A newer order for the same ship replaces the waiting one and restarts the delay
## (the delay begins when the order is issued). Orders are opaque data here.

## ship -> {"order": Variant, "time_left": float}
var _waiting := {}


func hold(ship: Object, order: Variant, delay: float) -> void:
	_waiting[ship] = {"order": order, "time_left": delay}


## Advances every delay. Returns the orders that are due this tick as [[ship, order], ...].
func tick(dt: float) -> Array:
	var due := []
	for ship in _waiting.keys():
		var entry: Dictionary = _waiting[ship]
		entry.time_left -= dt
		if entry.time_left <= 0.0:
			due.append([ship, entry.order])
			_waiting.erase(ship)
	return due


## The order waiting for ship, or null.
func pending(ship: Object) -> Variant:
	return _waiting[ship].order if _waiting.has(ship) else null


## Seconds before ship's waiting order is due, or 0 when nothing waits.
func time_left(ship: Object) -> float:
	return maxf(_waiting[ship].time_left, 0.0) if _waiting.has(ship) else 0.0


## Drops orders for ships that have been freed.
func prune() -> void:
	for ship in _waiting.keys():
		if not is_instance_valid(ship):
			_waiting.erase(ship)
