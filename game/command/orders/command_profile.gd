class_name CommandProfile
extends Resource
## Tuning for fleet command.

@export_group("Orders")
## Delay (s) between issuing an order and the ship receiving it. Meanwhile the ship keeps
## executing its previous order. A newer order replaces the waiting one and restarts the delay.
@export var order_delay: float = 1.0
