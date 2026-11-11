class_name Order
extends RefCounted
## Base of every order a ship can receive (part of the Ship's public contract). Orders are data:
## Command creates, delays and delivers them without knowing what they do; the ship routes each
## kind to the module that executes it (ShipBase.receive_order).
