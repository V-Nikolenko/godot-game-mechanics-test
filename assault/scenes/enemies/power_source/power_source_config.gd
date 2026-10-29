## PowerSourceConfig - the turret group's power source's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.2, Phase 8 t9).
##
## `counts_as_escape` is false in the `.tres`: a source that drifts off the bottom of Assault never breaks the combo (the Bonus Drone / turret precedent).
## No brain and no mover, so the hazard fields are 0; `wreck_chance` 0 (destroyed structures as wreckage is Ph19).
class_name PowerSourceConfig
extends ShipConfig

@export_group("Assault")
## Downward drift in Assault, px/s (copied onto the `AssaultDrift` child).
@export var assault_drift_speed: float = 60.0
