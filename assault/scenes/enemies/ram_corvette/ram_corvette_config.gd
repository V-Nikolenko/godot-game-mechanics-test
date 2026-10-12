## RamCorvetteConfig - tuning resource for the Ram Corvette (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md
## §2.6; tasks t16 (armour) and t17 (the charge)). Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. The charge fields (LINE_UP / WIND_UP / CHARGE / WIDE_TURN /
## STAGGER) and the exposed ones are read by `RamCorvetteBrain`.
class_name RamCorvetteConfig
extends ShipConfig

@export_group("Armour")
## HP of each of the three `ArmorPlate`s: one rocket of either kind breaks one, two Sniper Shots (40) do.
@export var plate_health: int = 50
## Contact damage once every plate is gone (`collision_damage`, 50, is the armoured value).
@export var exposed_collision_damage: int = 60
## The ARMOR contact profile's shove (px/s) while armoured; 0 once exposed (the armour is what staggers).
@export var armor_shove_speed: float = 260.0

@export_group("Movement")
## APPROACH / WIDE_TURN cruise speed (px/s) and the mover's caps.
@export var cruise_speed: float = 280.0
@export var acceleration: float = 500.0
@export var max_turn_rate: float = 2.2

@export_group("Engagement")
## Assault: seconds before the Corvette disengages.
@export var engage_seconds: float = 4.5
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 500.0

@export_group("Charge")
## APPROACH hands over to LINE_UP within this of the player (px).
@export var engage_range: float = 420.0
## Assault: APPROACH aims this far beside and above/below the player (px, each axis), so the charge is diagonal.
@export var assault_side_offset: float = 240.0
## LINE_UP lasts at most this long (s); the attack gate also asks for this much budget.
@export var line_up_cap: float = 0.5
## LINE_UP ends early once the nose is within this of the aim (deg) and the speed is down to `crawl_speed`.
@export var line_up_tolerance_deg: float = 8.0
## The aim point's lead, `Steering.clamped_lead_time(d, charge speed, lead_min, lead_max)` (s).
@export var lead_min: float = 0.15
@export var lead_max: float = 0.6
## The mover's braking (px/s²) while it stops to aim (LINE_UP, WIND_UP, STAGGER) - only then.
@export var braking: float = 1600.0
## WIND_UP creeps along the aim at this speed (px/s).
@export var crawl_speed: float = 20.0
@export var wind_up_seconds: float = 0.65
## The aim tracks the player for this share of the wind-up, then freezes.
@export var windup_track_fraction: float = 0.6
## ... turning at most this fast while it tracks (rad/s).
@export var windup_track_rate: float = 0.8
@export var charge_speed: float = 620.0
## The charge runs this far past the aim point (px) ...
@export var overshoot: float = 220.0
## ... but its boost never lasts longer than this (s): it bounds the Assault deferral.
@export var charge_max_time: float = 1.45
## WIDE_TURN's heading turns toward the player at this rate (rad/s) ...
@export var wide_turn_rate: float = 1.4
## ... until it is within this of the player (deg).
@export var wide_turn_exit_angle_deg: float = 30.0
## The plates' glow fades out over this long after a charge (s).
@export var glow_fade_seconds: float = 0.3
## A plate broken in LINE_UP / WIND_UP stops the Corvette for this long (s).
@export var stagger_seconds: float = 0.4

@export_group("Exposed")
## Once every plate is gone (px/s).
@export var exposed_cruise_speed: float = 340.0
@export var exposed_charge_speed: float = 700.0
## Exposed, it strafes out of the player's aim when the player's nose is within this of it (deg) ...
@export var evade_cone_deg: float = 20.0
## ... and it is closer than this (px) ...
@export var evade_range: float = 600.0
## ... at this lateral speed (px/s).
@export var evade_speed: float = 180.0
