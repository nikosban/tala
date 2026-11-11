class_name MoveOrder
extends Order
## Move to a point on the tactical plane (y = 0).

## Point that was asked for.
var destination := Vector3.ZERO
## Where the ship will actually go (the destination, or the nearest free spot to it); set by
## ShipBase.check_order, null until checked or when rejected.
var resolved_destination: Variant = null


func _init(to: Vector3) -> void:
	destination = to
