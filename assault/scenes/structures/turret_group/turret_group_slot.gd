## TurretGroupSlot - where a `TurretGroup` places one member (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.1; Phase 8 t9).
##
## The group instantiates `member_scene` at this marker's position when it spawns its members. `variant` (>= 0) is copied onto a member that has a
## `variant` property (a `DefenseTurret`: its first mount's weapon); `rest_bearing_deg`, when not NAN, onto one that has `rest_bearing_override` (the
## first mount's scan centre and droop target, degrees, 0 = +X, 90 = down). The defaults keep whatever the member scene authors.
class_name TurretGroupSlot
extends Marker2D

@export var member_scene: PackedScene
## >= 0: the member's `variant` (a `TurretMount.Variant` for a turret); -1 keeps the member scene's own.
@export var variant: int = -1
## Not NAN: the member's `rest_bearing_override`, degrees; NAN keeps the member scene's own.
@export var rest_bearing_deg: float = NAN
