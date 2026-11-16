## CarrierConfig - tuning for the Carrier (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.6, §2.16; Phase 10 t6, task plan
## docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md). Extends ShipConfig (max_health = the armoured hull's bar, which only the core's death empties;
## collision_damage = the ARMOR touch; score_value; the explicit hazard profile 0.5 / 120 / 1.0: a capital ship shrugs off pull and slow).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is complete.
## Starting values [judgement] (§2.16) unless marked. The parts' HP live in the scene (each `EnemyModule.max_health`); weapons (t7) and hangars (t8)
## add their own groups.
class_name CarrierConfig
extends ShipConfig

@export_group("Movement")
## Open Space cruise cap (px/s) with both engines.
@export var max_speed: float = 70.0
@export var acceleration: float = 40.0
@export var braking: float = 40.0
## Heading change cap (rad/s) with both engines: a 90 degree turn takes about 4.5 s.
@export var max_turn_rate: float = 0.35

@export_group("Engines")
## Turn-rate factors with one / no engine left (module death changes movement).
@export var one_engine_turn: float = 0.5
@export var no_engine_turn: float = 0.15
## Open Space speed factors with one / no engine left.
@export var one_engine_speed: float = 0.8
@export var no_engine_speed: float = 0.4
## With exactly one engine lost the hull sags toward the dead side at this rate (rad/s) while it holds a heading ...
@export var list_rate: float = 0.06
## ... until it is this far off (degrees), then it turns back (the list's deadband, t6 D3).
@export var list_hold_deg: float = 10.0

@export_group("Screen")
## Open Space: the band it holds the player in (px). It closes only from beyond the band and opens only from inside it.
@export var screen_range_min: float = 600.0
@export var screen_range_max: float = 950.0
## It never strays further than this from `patrol_anchor` (px), in SCREEN and in PANIC alike.
@export var leash_radius: float = 900.0

@export_group("Core")
## The core opens (becomes vulnerable, PANIC) once this many outer parts (engines, guns, hangars) are wrecks. Owner choice 1.
@export var core_exposure_count: int = 3

@export_group("Assault")
## The constant crossing speed, straight down (px/s): engines, panic, hazards and EMP never change it.
@export var assault_cross_speed: float = 90.0
## The mover's cap in Assault (px/s): above the hypotenuse of the crossing and the sway, so it never slows the descent.
@export var assault_max_speed: float = 110.0
## The lateral sway that keeps the player in a live battery's arc (px/s), times 1 / `one_engine_sway` / `no_engine_sway` with 2 / 1 / 0 engines ...
@export var assault_sway_speed: float = 30.0
@export var one_engine_sway: float = 0.5
@export var no_engine_sway: float = 0.1
## ... leashed to this far either side of the spawn x (px): the level-1 column lanes are narrow (§2.13).
@export var assault_sway_leash: float = 30.0

@export_group("Geometry")
## Every part's hurtbox stays within this far of the hull centre in x (px). Level 1's lane maths (§2.13) depend on it; pinned by test_carrier.gd.
@export var module_x_extent: float = 100.0

@export_group("Idle")
## Open Space hub only: a slow orbit round `patrol_anchor` until the player comes within `perceive_radius`; home again beyond `lose_radius` (px).
@export var perceive_radius: float = 1100.0
@export var lose_radius: float = 1800.0
## The beat between perceiving the player and screening (s).
@export var notice_time: float = 0.6
## The idle orbit's radius (px) and angular speed (rad/s).
@export var idle_radius: float = 220.0
@export var idle_speed: float = 0.12
