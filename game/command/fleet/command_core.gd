class_name CommandCore
extends RefCounted
## Scene-free player command state: the current selection, control groups 1-9 and group
## order destinations. Holds ships as plain objects; freed ships are dropped by prune().

const GROUP_COUNT := 9

var _selected: Array[Object] = []
var _groups := {}  # int (1..9) -> Array[Object]


## The selected ships, in selection order.
func selected() -> Array[Object]:
	return _selected.duplicate()


func is_selected(ship: Object) -> bool:
	return _selected.has(ship)


## Replaces the selection.
func select(ships: Array) -> void:
	_selected.clear()
	for ship in ships:
		add(ship)


func add(ship: Object) -> void:
	if ship != null and not _selected.has(ship):
		_selected.append(ship)


## Adds the ship if it is not selected, otherwise removes it.
func toggle(ship: Object) -> void:
	if _selected.has(ship):
		_selected.erase(ship)
	else:
		add(ship)


func clear() -> void:
	_selected.clear()


## Stores the selection as control group n (replacing it).
func assign_group(n: int) -> void:
	if _valid_group(n):
		_groups[n] = _selected.duplicate()


## Adds the selection to control group n.
func add_to_group(n: int) -> void:
	if not _valid_group(n):
		return
	var group: Array = _groups.get(n, [])
	for ship in _selected:
		if not group.has(ship):
			group.append(ship)
	_groups[n] = group


## Selects control group n. An empty or unknown group leaves the selection unchanged.
func recall_group(n: int) -> void:
	prune()
	var group: Array = _groups.get(n, [])
	if not group.is_empty():
		select(group)


func group(n: int) -> Array[Object]:
	var result: Array[Object] = []
	result.assign(_groups.get(n, []))
	return result


## Drops freed ships from the selection and every group.
func prune() -> void:
	var alive := func(ship: Variant) -> bool: return is_instance_valid(ship)
	_selected.assign(_selected.filter(alive))
	for n in _groups:
		_groups[n] = (_groups[n] as Array).filter(alive)


## Destinations for a group order: each ship keeps its offset from the group's centre,
## moved to target. A single ship goes exactly to target.
static func group_destinations(positions: Array[Vector2], target: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if positions.is_empty():
		return result
	var centre := Vector2.ZERO
	for p in positions:
		centre += p
	centre /= positions.size()
	for p in positions:
		result.append(target + (p - centre))
	return result


static func _valid_group(n: int) -> bool:
	return n >= 1 and n <= GROUP_COUNT
