## ShieldGeneratorConfig - the shield generator's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.5, Phase 8 t9s).
##
## The `shield_*` fields are the bubble it projects on every member of its turret group (the Support Ship's projected-shield fields, but a 360 degree bubble,
## so no arc or turn rate). `counts_as_escape` is false in the `.tres`: a generator that drifts off the bottom of Assault never breaks the combo (the Bonus
## Drone / turret precedent). No mover, so the hazard fields are 0; `wreck_chance` 0 (destroyed structures as wreckage is Ph19).
class_name ShieldGeneratorConfig
extends ShipConfig

@export_group("Shield")
## Points of each member's bubble.
@export var shield_capacity: int = 50
## Seconds after the last absorbed hit before a bubble refills.
@export var shield_regen_delay: float = 3.0
## Empty -> full refill time.
@export var shield_regen_seconds: float = 2.0
## After a break a bubble absorbs nothing for this long.
@export var shield_reboot_seconds: float = 5.0
## A bubble's radius is the member's body radius plus this, px.
@export var shield_radius_margin: float = 8.0

@export_group("Assault")
## Downward drift in Assault, px/s (copied onto the `AssaultDrift` child).
@export var assault_drift_speed: float = 60.0
