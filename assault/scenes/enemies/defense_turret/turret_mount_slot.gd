## TurretMountSlot - where a host places one `TurretMount` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7; Phase 8 t6).
##
## Mounts are built at runtime (`DefenseTurret._build_mounts()`), so the slot is the only authored place a host can choose and retune one:
## `variant` picks the mount scene (`TurretMountScenes.scene_for`), `rest_bearing_deg` becomes the mount's scan centre and droop target, and a
## `turn_rate_override` >= 0 replaces the mount scene's own `turn_rate` before `setup()` (negative keeps it). A later host (the heavy emplacement,
## Ph10 ships) authors the same marker.
class_name TurretMountSlot
extends Marker2D

@export var variant: TurretMount.Variant = TurretMount.Variant.BURST_CANNON
## Degrees, local to this slot's parent (0 = +X, 90 = down).
@export var rest_bearing_deg: float = 90.0
## >= 0: copied onto the mount's `turn_rate`; negative keeps the mount scene's value.
@export var turn_rate_override: float = -1.0
