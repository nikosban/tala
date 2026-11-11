class_name NavigatorProfile
extends Resource
## Navigation tuning for one ship class. All navigation tuning lives here; code holds no tuning numbers.
## Units: world units (u), seconds (s).

## Gap (u) kept between obstacles and the ship's spin circle (the circle its hull sweeps when
## rotating in place). Total clearance from an obstacle's edge = hull spin radius + this margin.
@export var obstacle_margin: float = 5.0
## Furthest (u) a blocked destination may be moved to the nearest free spot before the order is rejected.
@export var max_destination_displacement: float = 30.0
## Interval (s) between checks that the remaining route is still clear.
@export var route_check_interval: float = 0.5
## How far (u) the ship's centre may stray from the shortest route (the corridor's half width).
## Wider lets the helm take wider, faster lines around bends.
@export var corridor_half_width: float = 40.0
## The next route point becomes the steer point once the ship is within this distance (u) of
## the current one.
@export var steer_lookahead: float = 8.0
