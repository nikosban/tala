class_name CommandController
extends Node
## Fleet command: the Command layer's public API, used by the Player layer (and later AI).
## Owns the selection and control groups (CommandCore) and the order delay (OrderDelays).
## Orders wait out the order delay here before the ship receives them; meanwhile the ship
## keeps executing its previous order. Talks to ships only through ShipBase's public API
## (check_order, receive_order, order signals), never to their modules.
## News goes up: ship order problems are relayed as Command signals, so the layers above
## never listen to ships directly. No input handling and no drawing.

signal selection_changed(ships: Array[Object])
## A ship refused an order: no free spot near the destination or no route to it.
signal order_rejected(ship: ShipBase, destination: Vector3)
## A ship's active order ended because its route became blocked and no new route exists.
signal order_failed(ship: ShipBase, destination: Vector3)

@export var profile: CommandProfile = preload("res://game/command/orders/default_command.tres")

var core := CommandCore.new()
var delays := OrderDelays.new()

var _ships: Array[ShipBase] = []


## Makes a ship commandable.
func register_ship(ship: ShipBase) -> void:
	if _ships.has(ship):
		return
	_ships.append(ship)
	ship.order_rejected.connect(func(d: Vector3) -> void: order_rejected.emit(ship, d))
	ship.order_failed.connect(func(d: Vector3) -> void: order_failed.emit(ship, d))


## Registered ships that still exist (a copy; changing it does not register or drop ships).
func get_ships() -> Array[ShipBase]:
	_ships.assign(_ships.filter(func(s: Variant) -> bool: return is_instance_valid(s)))
	return _ships.duplicate()


func selected() -> Array[Object]:
	core.prune()
	return core.selected()


func select(ships: Array) -> void:
	core.select(ships)
	_selection_changed()


func add(ship: ShipBase) -> void:
	core.add(ship)
	_selection_changed()


func toggle(ship: ShipBase) -> void:
	core.toggle(ship)
	_selection_changed()


func clear() -> void:
	core.clear()
	_selection_changed()


## Control groups 1-9.
func assign_group(n: int) -> void:
	core.assign_group(n)


func add_selection_to_group(n: int) -> void:
	core.add_to_group(n)


## Selects control group n (an empty group leaves the selection unchanged).
func recall_group(n: int) -> void:
	core.recall_group(n)
	_selection_changed()


## Orders every selected ship toward target, keeping the group's layout.
func order_selection(target: Vector3) -> void:
	var ships := selected()
	var positions: Array[Vector2] = []
	for ship in ships:
		var p: Vector3 = (ship as ShipBase).global_position
		positions.append(Vector2(p.x, p.z))
	var slots := CommandCore.group_destinations(positions, Vector2(target.x, target.z))
	for i in ships.size():
		order_ship(ships[i] as ShipBase, Vector3(slots[i].x, 0.0, slots[i].y))


## Orders one ship to destination. The ship checks it now (an unreachable order is rejected
## at once); an accepted order reaches the ship after the order delay.
func order_ship(ship: ShipBase, destination: Vector3) -> void:
	var order := MoveOrder.new(destination)
	if ship.check_order(order):
		delays.hold(ship, order, profile.order_delay)


## Where ship will go once its waiting move order arrives (the resolved destination), or null.
func get_pending_destination(ship: ShipBase) -> Variant:
	var order := delays.pending(ship) as MoveOrder
	return order.resolved_destination if order != null else null


## The ship's newest move destination: the waiting order's if any, else the one it executes,
## else null.
func get_order_destination(ship: ShipBase) -> Variant:
	var pending: Variant = get_pending_destination(ship)
	return pending if pending != null else ship.get_active_destination()


func _physics_process(delta: float) -> void:
	delays.prune()
	for due in delays.tick(delta):
		(due[0] as ShipBase).receive_order(due[1] as Order)


func _selection_changed() -> void:
	selection_changed.emit(selected())
