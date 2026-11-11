class_name MovementProfile
extends Resource
## Tuning data for one ship class. All movement tuning lives here; code holds no tuning numbers.
## Units: world units (u), seconds (s), degrees for authored angles.

## Maximum forward speed (u/s).
@export var top_speed: float = 10.0
## Rate at which forward speed rises (u/s²).
@export var acceleration: float = 0.5
## Rate at which forward speed falls from the main engines (u/s²).
@export var braking: float = 0.625
## Turn rate (deg/s) sampled by speed fraction (0 = at rest, 1 = top speed).
@export var turn_rate_curve: Curve

@export_group("RCS")
## RCS effectiveness (0..1) sampled by speed fraction. Scales sideways speed and braking assist.
@export var rcs_authority_curve: Curve
## Rate at which sideways speed changes (u/s²).
@export var rcs_acceleration: float = 0.5
## Maximum sideways speed at full authority (u/s).
@export var rcs_max_speed: float = 1.5
## Extra deceleration at full authority (u/s²), added to braking.
@export var rcs_braking: float = 0.3

@export_group("Rest manoeuvre")
## A ship moving no faster than this (u/s) when an order becomes active counts as stationary.
@export var rest_max_speed: float = 0.5
## From stationary, destinations at least this far off the bow (deg) start a rest manoeuvre:
## RCS carries the ship straight toward the destination while it rotates, main engine off.
@export_range(0.0, 180.0) var rest_min_bearing_deg: float = 90.0
## The rest manoeuvre ends and the main engine takes over once the bow is within this angle (deg).
@export_range(0.0, 180.0) var rest_align_deg: float = 20.0

@export_group("Orders")
## Distance (u) from the destination that counts as arrived.
@export var arrival_tolerance: float = 1.5
## Heading error (deg) that counts as facing the final heading.
@export var heading_tolerance_deg: float = 2.0
## Fraction of forward and sideways speed lost on each contact (0..1).
@export_range(0.0, 1.0) var contact_speed_loss: float = 0.5
## Extra distance (u) checked for ships ahead, beyond the stopping distance.
@export var traffic_lookahead: float = 20.0
## Gap (u) kept from a ship in the way when stopping for it.
@export var traffic_stop_margin: float = 5.0

@export_group("Giving way")
## Extra lateral gap (u) kept from a passing ship's centreline when stepping aside, on top of
## both ships' hull spin radii.
@export var give_way_margin: float = 5.0
## Time (s) before trying again to settle right of way with a ship when neither could step aside.
@export var give_way_retry_interval: float = 1.0
