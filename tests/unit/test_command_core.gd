extends RefCounted
## CommandCore: selection, control groups and group order destinations.


func _ships(count: int) -> Array[Object]:
	var ships: Array[Object] = []
	for i in count:
		ships.append(RefCounted.new())
	return ships


func test_group_destinations_keep_layout(t: TestContext) -> void:
	var positions: Array[Vector2] = [Vector2(-80, 0), Vector2(0, 0), Vector2(80, 30)]
	var target := Vector2(500, -400)
	var slots := CommandCore.group_destinations(positions, target)
	t.check(slots.size() == 3, "one slot per ship")
	for i in positions.size():
		for j in positions.size():
			var before := positions[j] - positions[i]
			var after := slots[j] - slots[i]
			t.near(before.distance_to(after), 0.0, 0.0001, "offset %d->%d preserved" % [i, j])
	var centre := (slots[0] + slots[1] + slots[2]) / 3.0
	t.near(centre.distance_to(target), 0.0, 0.0001, "group centre lands on the target")


func test_single_ship_goes_to_target(t: TestContext) -> void:
	var slots := CommandCore.group_destinations([Vector2(13, -7)] as Array[Vector2], Vector2(100, 200))
	t.near(slots[0].distance_to(Vector2(100, 200)), 0.0, 0.0001, "single ship slot")
	t.check(CommandCore.group_destinations([] as Array[Vector2], Vector2.ZERO).is_empty(), "no ships, no slots")


func test_selection_select_add_toggle(t: TestContext) -> void:
	var core := CommandCore.new()
	var s := _ships(3)
	core.select([s[0], s[1]])
	t.check(core.selected() == [s[0], s[1]], "select replaces the selection")
	core.add(s[1])
	t.check(core.selected().size() == 2, "adding a selected ship does not duplicate it")
	core.toggle(s[2])
	core.toggle(s[0])
	t.check(core.selected() == [s[1], s[2]], "toggle adds and removes")
	core.clear()
	t.check(core.selected().is_empty(), "clear empties the selection")


func test_control_groups(t: TestContext) -> void:
	var core := CommandCore.new()
	var s := _ships(3)
	core.select([s[0], s[1]])
	core.assign_group(1)
	core.select([s[2]])
	core.add_to_group(1)
	core.assign_group(2)
	core.clear()
	core.recall_group(1)
	t.check(core.selected() == [s[0], s[1], s[2]], "group 1 holds the assigned and added ships")
	core.recall_group(2)
	t.check(core.selected() == [s[2]], "group 2 recalled")
	core.recall_group(5)
	t.check(core.selected() == [s[2]], "an empty group leaves the selection unchanged")
	core.assign_group(0)
	core.assign_group(10)
	t.check(core.group(0).is_empty() and core.group(10).is_empty(), "only groups 1-9 exist")


func test_prune_drops_freed_ships(t: TestContext) -> void:
	var core := CommandCore.new()
	var keep := Node.new()
	var gone := Node.new()
	core.select([keep, gone])
	core.assign_group(3)
	gone.free()
	core.prune()
	t.check(core.selected() == [keep], "freed ship leaves the selection")
	t.check(core.group(3) == [keep], "freed ship leaves its group")
	keep.free()
