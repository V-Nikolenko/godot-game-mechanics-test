## GatlingInterceptorConfig — tuning resource for the Gatling Interceptor
## (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.6, §2.8; task plan
## docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md). Extends ShipConfig (max_health, collision_damage,
## score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. All values are [judgement] starting defaults except the
## legacy ones (HP, contact, score, and the Rail group), so they can be tuned in the `.tres` without
## code changes.
class_name GatlingInterceptorConfig
extends ShipConfig

@export_group("Movement")
@export var max_speed: float = 260.0
@export var acceleration: float = 600.0
@export var braking: float = 900.0
## Heading change cap, rad/s. Pinned: `turn_rate × max_speed ≤ acceleration`, so the mover's
## acceleration limit can follow the curve.
@export var turn_rate: float = 2.0

@export_group("Geometry")
## The side-on distance a window is fired from (px).
@export var preferred_range: float = 380.0
## Assault: a flank point closer than this (horizontally) to the player is not taken — a player
## hugging a wall keeps the Gatling on the open side (px).
@export var min_flank_range: float = 220.0
## APPROACH closes to `preferred_range + approach_margin` of the player (px).
@export var approach_margin: float = 250.0
## APPROACH and REPOSITION hand over to SWING_IN once the flank point is this close, so SWING_IN can
## reach it inside `swing_in_max` (px; task plan §D2).
@export var swing_in_reach: float = 300.0
## APPROACH (once within range) and REPOSITION hand over after this long whatever the position (s).
@export var reposition_cap: float = 5.0

@export_group("Window")
## The longest SWING_IN (s). A window starts only with at least this much budget left.
@export var swing_in_max: float = 1.5
@export var spin_up_seconds: float = 0.25
## A convergence pair's longest wait for its partner once its own spin-up is over (s); a solo Gatling
## never waits.
@export var sync_wait_max: float = 0.75
@export var stream_rounds_min: int = 8
@export var stream_rounds_max: int = 12
@export var stream_interval: float = 0.09
## How fast the Gatling slides along the flank while it spins up and fires (px/s).
@export var stream_strafe_speed: float = 140.0
@export var cooldown_seconds: float = 0.4
## REPOSITION lasts at least rng(reposition_min, reposition_max) (s).
@export var reposition_min: float = 1.0
@export var reposition_max: float = 1.5

@export_group("Rounds")
## The AI stream's Gatling Stream rounds.
@export var round_speed: float = 240.0
@export var round_damage: int = 4
## Per-round jitter, half-angle in radians.
@export var stream_spread: float = 0.05
## 0 = direct aim at the player, 1 = lead the intercept (`TargetInfo.aim_direction`).
@export var accuracy: float = 0.8

@export_group("Convergence")
## A FLANK's flank point sits this many degrees of bearing from the LEAD's, toward the player's
## heading, so the pair is on one side of the player and the other side stays open.
@export var convergence_bearing_offset_deg: float = 40.0
## Each shooter's aim at the shared point is off by up to this much, drawn once per window (deg).
@export var convergence_aim_error_deg: float = 3.0
## A FLANK joins the LEAD's window only within this many `preferred_range`s of the player.
@export var convergence_join_range_factor: float = 1.5

@export_group("Tactics")
## Assault only: seconds in the fight before DISENGAGE.
@export var engage_seconds: float = 7.0
@export var exit_speed: float = 520.0

@export_group("Idle")
## Open Space only (epic §2.10). `perceive_radius` is at least `preferred_range`, or the Gatling would
## open fire before it noticed; `lose_radius` is the hysteresis margin that keeps it from flipping at the
## edge (px).
@export var perceive_radius: float = 560.0
@export var lose_radius: float = 900.0
## The beat between perceiving the player and fighting (s).
@export var notice_time: float = 0.35
## The patrol ring's radius round `patrol_anchor` (px) and its angular speed (rad/s).
@export var idle_radius: float = 150.0
@export var idle_speed: float = 0.5

@export_group("Rail")
## The rail fallback (plan §2.8): the legacy constant stream, fired while an `EnemyPathMover` owns the
## motion. Read only by `GatlingInterceptorBrain.on_suspended()`.
@export var rail_stream_interval: float = 0.09
@export var rail_stream_speed: float = 220.0
## Max random rotation per rail round (radians). 0.08 ≈ ±4.5°.
@export var rail_spread: float = 0.08
@export var rail_damage: int = 4
