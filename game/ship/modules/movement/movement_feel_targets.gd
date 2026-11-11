class_name MovementFeelTargets
extends Resource
## Provisional feel targets for a ship class, checked by the feel-target test against its profile.
## Adjust these when the intended feel changes; the profile is then retuned to meet them.

## Hull length (u) used to express distances in hull lengths.
@export var hull_length: float = 20.0
## Time (s) to go from rest to top speed.
@export var rest_to_top_speed_s: float = 20.0
## Stopping distance from top speed, in hull lengths.
@export var stop_distance_hull_lengths: float = 4.0
## Time (s) to rotate 90 degrees while at rest.
@export var quarter_turn_at_rest_s: float = 12.0
## Accepted relative deviation from each target (0.15 = ±15%).
@export var tolerance_fraction: float = 0.15
