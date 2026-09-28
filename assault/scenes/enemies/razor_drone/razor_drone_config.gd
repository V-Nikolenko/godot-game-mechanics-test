## RazorDroneConfig — tuning resource for the RazorDrone enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the
## shallow `ShipConfig.privatise()` copy is complete. Values and their sources:
## docs/plans/cmuj4y8rr007gp52xxs8dec5s/3-plan.md (task t10) on top of the epic plan §2.8.2.
class_name RazorDroneConfig
extends ShipConfig

@export_group("Movement")
## Preferred distance from the player while orbiting (px).
@export var orbit_radius         : float = 130.0
## Angular velocity of the orbit anchor (rad/s).
@export var orbit_speed          : float = 1.8
## Movement speed during ENTER and RETURN (px/s).
@export var approach_speed       : float = 200.0
## Maximum speed when correcting orbit position (px/s). Must be at least orbit_speed × orbit_radius
## (234), or the drone lags inside the ring by a seed-dependent amount (t10 review B3).
@export var orbit_correct_speed  : float = 260.0
## EnemyMover limits (px/s², px/s², rad/s).
@export var acceleration         : float = 900.0
@export var braking              : float = 700.0
@export var max_turn_rate        : float = 6.0

@export_group("Orbit choices")
## Chance a finished orbit window reverses the orbit instead of attacking.
@export var reverse_chance       : float = 0.35
## How long a reversal takes to swing the anchor's angular speed through zero (s).
@export var reverse_seconds      : float = 0.25
## Chance an attack is a feint rather than a real dash.
@export var fake_chance          : float = 0.35

@export_group("Feint")
## The feint's wind-up lasts windup_seconds × this.
@export var fake_windup_scale    : float = 1.5
@export var feint_lunge_speed    : float = 360.0
@export var feint_lunge_seconds  : float = 0.45
## The lunge aims this far beside the player (px), so it passes clear of the player's hull.
@export var feint_clearance_px   : float = 70.0

@export_group("Attack")
## Yellow wind-up before a real dash (s).
@export var windup_seconds       : float = 0.5
## White commit flash between the wind-up and the dash (s).
@export var commit_flash_seconds : float = 0.12
## Burst speed during the dash (px/s).
@export var dash_speed           : float = 480.0
## How far ahead to predict the player position for the dash target (seconds).
@export var dash_prediction_time : float = 0.2
## The dash runs this far past the locked point (px)...
@export var overshoot_px         : float = 120.0
## ...but never longer than this (s).
@export var max_dash_seconds     : float = 0.9

@export_group("Overshoot")
## The post-dash curve: speed (px/s) and turn rate (rad/s). turn_rate × speed ≤ acceleration.
@export var overshoot_speed      : float = 200.0
@export var overshoot_turn_rate  : float = 3.0
@export var overshoot_max_seconds: float = 1.2
## The single pulse shot fired after a missed dash.
@export var pulse_damage         : int = 10
@export var pulse_speed          : float = 250.0

@export_group("Assault")
## Assault only: seconds in the fight before DISENGAGE.
@export var engage_seconds       : float = 9.0
@export var exit_speed           : float = 320.0
## A dash starts only from a bearing this many degrees off the vertical axis (Assault only).
@export var side_lane_min_deg    : float = 30.0
@export var side_lane_max_deg    : float = 75.0

@export_group("Idle")
## Open Space only: the patrol ring's radius (px), redrawn ± this jitter at the start of every leg.
@export var idle_radius          : float = 160.0
@export var idle_radius_jitter   : float = 40.0
## Open Space only: the patrol ring's angular speed (rad/s), redrawn ± this jitter every leg.
@export var idle_speed           : float = 0.5
@export var idle_speed_jitter    : float = 0.2
## Open Space only: enter combat once the player is within this of the drone (px).
@export var perceive_radius      : float = 450.0
## Open Space only: drop back toward patrol once the player is beyond this (px). Must exceed
## perceive_radius (AnchorIdle's hysteresis margin).
@export var lose_radius          : float = 700.0
## Open Space only: the NOTICING beat before combat (s).
@export var notice_time          : float = 0.35
