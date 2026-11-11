class_name ShipContact
extends RefCounted
## A ship found in the way by the Lookout: how far the hull can travel before touching it,
## and which ship it is.

## Distance (u) the hull can travel before touching the ship.
var distance := INF
## The ship in the way.
var ship: CharacterBody3D


func _init(d: float, s: CharacterBody3D) -> void:
	distance = d
	ship = s
