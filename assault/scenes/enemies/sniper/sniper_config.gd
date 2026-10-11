## SniperConfig - tuning resource for the Sniper (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5, §2.8).
## Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number or bool, so the
## shallow `ShipConfig.privatise()` copy is complete. HP 60, contact 20 and score 50 are the legacy values
## (the old Sniper hardcoded the score in `_ready()`); the rest are [judgement] starting defaults, tunable
## in the `.tres`. Most of the cycle fields are read by the t13 cycle; t12 ships the shell that applies
## them.
class_name SniperConfig
extends ShipConfig

@export_group("Movement")
## The mover's cap and limits (px/s, px/s², px/s², rad/s).
@export var max_speed: float = 320.0
@export var acceleration: float = 520.0
@export var braking: float = 700.0
@export var max_turn_rate: float = 4.0
## ENTER and RELOCATE travel speed (px/s).
@export var relocate_speed: float = 260.0
## BREAK_CONTACT speed (px/s).
@export var break_speed: float = 320.0
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 320.0

@export_group("Firing point")
## Distance from the player a firing point is chosen at, and its jitter (px). Open Space values; Assault
## uses the `assault_*` pair, because the corridor is narrower than the open field.
@export var preferred_range: float = 900.0
@export var range_jitter: float = 100.0
@export var assault_preferred_range: float = 680.0
@export var assault_range_jitter: float = 80.0
## Assault: a firing point lies this far inside the corridor's `inner_rect()` (px).
@export var fire_margin: float = 96.0
## No firing point inside this half-angle of a fast player's heading (deg), while it moves >= 200 px/s.
@export var forward_cone: float = 30.0
## Every new firing point differs from the last by at least this bearing (deg), if any candidate allows it.
@export var min_bearing_change: float = 45.0
@export var w_sep: float = 1.0
@export var w_travel: float = 0.4
## BREAK_CONTACT lasts until `preferred_range * 0.9` away, or this long (s).
@export var break_cap: float = 2.0
## RELOCATE re-picks its point after this long (s).
@export var relocate_cap: float = 4.0
## SETTLE ends when the speed is under this (px/s).
@export var settle_epsilon: float = 2.0
## ENTER counts as arrived within this of its point (px).
@export var arrive_radius: float = 12.0

@export_group("Shot")
## AIM tracks the player for this long, at most `aim_track_rate` rad/s (s, rad/s).
@export var aim_seconds: float = 1.3
@export var aim_track_rate: float = 2.0
## LOCK freezes the aim point for this long: the player's dodge window (s).
@export var lock_seconds: float = 0.5
@export var rail_speed: float = 2200.0
@export var rail_damage: int = 28
## How long a fired round's trail fades (s).
@export var trail_fade: float = 0.4

@export_group("Engagement")
## Assault: seconds in the fight before DISENGAGE (a shot in AIM / LOCK is fired first).
@export var engage_seconds: float = 9.0

@export_group("Decoy")
## The difficulty flag (IDEAS §5.6): a fake orange aim line before the real one. Off in the shipped game.
@export var decoy_telegraph: bool = false
@export var decoy_seconds: float = 0.6
## The decoy line's bearing offset from the player, uniform in this range, either side (deg).
@export var decoy_offset_min: float = 25.0
@export var decoy_offset_max: float = 35.0

@export_group("Rail")
## While a rail owns the sniper (§2.8): `rail_shot_count` shots, each tracking for `rail_aim_seconds` at
## `rail_track_rate` rad/s, then `rail_lock_seconds` frozen, fired at `rail_fallback_speed` for
## `rail_fallback_damage`. These are today's numbers.
@export var rail_shot_count: int = 5
@export var rail_aim_seconds: float = 2.0
@export var rail_lock_seconds: float = 0.5
@export var rail_track_rate: float = 4.0
@export var rail_fallback_speed: float = 1400.0
@export var rail_fallback_damage: int = 25
