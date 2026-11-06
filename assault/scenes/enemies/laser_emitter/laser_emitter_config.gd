## LaserEmitterConfig - a laser fence post's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.11, Phase 8 t10).
##
## `counts_as_escape` is false in the `.tres`: a fence that drifts off the bottom of Assault never breaks the combo (the Bonus Drone / turret precedent).
## No brain and no mover, so the hazard fields are 0; `wreck_chance` 0 (destroyed structures as wreckage is Ph19). The post does not drift by
## itself: the fence's `AssaultDrift` carries both posts.
class_name LaserEmitterConfig
extends ShipConfig
