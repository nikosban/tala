class_name MoveExecution
extends RefCounted
## Movement's execution of one move order: destination and progress. The route belongs to the Navigator.

enum Status { MOVING, SETTLING, COMPLETED }

## Destination the ship goes to (the requested point, or the nearest free spot to it).
var destination := Vector2.ZERO
## Point the player asked for.
var requested_destination := Vector2.ZERO
var status := Status.MOVING
## Heading to settle on; set when settling starts.
var final_heading := 0.0
## Name of the limit currently capping speed (debug): top, arrival, turn, corner, corridor,
## traffic, rest, give_way.
var binding_limit := &"top"
## Point the helm steered at on the latest tick (debug).
var steer_point := Vector2.ZERO
## True while stopped for a ship in the way.
var waiting := false
## False until the order's first tick, when the rest manoeuvre is decided.
var started := false
## True while executing a rest manoeuvre (RCS toward the destination, main engine off).
var rest_manoeuvre := false


func _init(dest: Vector2, requested: Variant = null) -> void:
	destination = dest
	requested_destination = requested if requested != null else dest
