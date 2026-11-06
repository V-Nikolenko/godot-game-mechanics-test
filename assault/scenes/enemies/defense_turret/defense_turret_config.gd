## DefenseTurretConfig - the Stationary Defense Turret's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7, Phase 8 t6).
##
## Weapon tuning is NOT here: it lives in each mount scene's exports (`defense_turret/mounts/*_mount.tscn`), so a mount behaves the same on
## any host (Ph10). `counts_as_escape` is false in the `.tres`: a turret that drifts off the bottom of Assault never breaks the combo (the
## Bonus Drone precedent). No mover, so the hazard fields are 0; `wreck_chance` 0 (destroyed structures as wreckage is Ph19).
class_name DefenseTurretConfig
extends ShipConfig

@export_group("Perception")
## Open Space: the player is noticed within this distance of the turret, px.
@export var perceive_radius: float = 900.0
## Open Space: once noticed, the player is kept until beyond this distance, px.
@export var lose_radius: float = 1100.0
## Seconds of NOTICING (one `StateLight.blink_once()`) before ENGAGED.
@export var notice_time: float = 0.3

@export_group("Assault")
## Downward drift in Assault, px/s (copied onto the `AssaultDrift` child).
@export var assault_drift_speed: float = 60.0
