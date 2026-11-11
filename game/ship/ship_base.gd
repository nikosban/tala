class_name ShipBase
extends CharacterBody3D
## Base for every ship and the ship's public API for the layers above (Command, Presentation).
## Orders arrive here and are routed to the module that executes them; module news goes up as
## ship signals. Movement decisions belong to the Movement module child (helped by the
## Navigator and Lookout children); this body only applies them: rotation from heading,
## displacement via move_and_collide.

## The ship refused an order: no free spot near the destination or no route to it.
signal order_rejected(destination: Vector3)
## An active order ended because its route became blocked and no new route exists.
signal order_failed(destination: Vector3)

@onready var movement: MovementModule = $Movement
@onready var navigator: NavigatorModule = $Navigator


func _ready() -> void:
	movement.order_rejected.connect(order_rejected.emit)
	movement.order_failed.connect(order_failed.emit)


## Checks an order without executing it. True when the ship can take it; a MoveOrder gets its
## resolved_destination. A refused order emits order_rejected.
func check_order(order: Order) -> bool:
	if order is MoveOrder:
		var move := order as MoveOrder
		move.resolved_destination = movement.resolve_move_order(move.destination)
		return move.resolved_destination != null
	push_error("%s cannot take order %s" % [name, order])
	return false


## Executes an order now, replacing the current one of the same kind.
func receive_order(order: Order) -> void:
	if order is MoveOrder:
		movement.issue_move_order((order as MoveOrder).destination)
		return
	push_error("%s cannot take order %s" % [name, order])


## Destination of the move order being executed (resolved), or null.
func get_active_destination() -> Variant:
	return movement.get_active_destination()


## Hull length (u): the longest side of the collider's footprint on the plane. 0 without one.
func get_hull_length() -> float:
	var size := get_hull_bounds().size
	return maxf(size.x, size.z)


## The collider's bounding box in the ship's local frame (empty without a collider).
func get_hull_bounds() -> AABB:
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			var shape := child as CollisionShape3D
			return shape.transform * shape.shape.get_debug_mesh().get_aabb()
	return AABB()


## Debug snapshot per module, for Presentation. Not part of the gameplay contract.
func get_debug_info() -> Dictionary:
	return {"movement": movement.get_debug_info(), "navigator": navigator.get_debug_info()}


func _physics_process(delta: float) -> void:
	var displacement := movement.physics_step(delta)
	global_rotation = Vector3(0.0, movement.get_heading(), 0.0)
	var collision := move_and_collide(displacement)
	movement.sync_position(global_position)
	if collision != null:
		movement.notify_contact()
