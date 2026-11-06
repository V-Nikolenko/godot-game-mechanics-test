## LaserTenderConfig - the Laser Tender's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.13; task plan
## docs/plans/cmvqw0vnz018nqs2xv56q6a0a/3-plan.md; Phase 8 t13). Extends ShipConfig (max_health, collision_damage, score_value, the hazard and
## wreck fields).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is complete.
## Values are the plan's [judgement] starting values (§2.21). The launched pair's own tuning (`rig_length`, `standoff`, `slot_tolerance`, the
## advance) is the drone's (`twin_laser_drone_config.tres`, read through the tender's `drone_scene`), never repeated here.
class_name LaserTenderConfig
extends ShipConfig

@export_group("Movement")
## Cap on the tender's own speed (px/s).
@export var max_speed: float = 200.0
@export var acceleration: float = 400.0

@export_group("Launch")
## Open Space: the range the tender holds from the player (px), within `range_tolerance` before it HOLDs.
@export var preferred_range: float = 650.0
@export var range_tolerance: float = 80.0
## Open Space HOLD: the broad arc's angular speed (rad/s).
@export var arc_rate: float = 0.12
## The cradle telegraph before a launch (s): the cradle light is CHARGING for this long.
@export var launch_telegraph: float = 0.6
## Each launched drone boosts toward its point at this speed (px/s) for at most `launch_max_seconds` (s).
@export var launch_speed: float = 520.0
@export var launch_max_seconds: float = 1.4
## The prediction horizon cap (s): `P + v * min(lead_time_max, |P - tender| / launch_speed)`.
@export var lead_time_max: float = 1.5
## A standing player's wall goes this far ahead of its nose (px).
@export var standing_lead: float = 120.0
## Once no pair of this tender lives, the cradles stay empty this long (s) before a docked pair is back.
@export var rearm_seconds: float = 7.0
## Assault: a strafing player's vertical wall stands this far ahead of it along x (px), when `|v.x| >= strafe_speed_min` (px/s).
@export var assault_wall_lead: float = 180.0
@export var strafe_speed_min: float = 60.0
## Assault: the hold band's depth below the view's top edge (px).
@export var assault_hold_depth: float = 140.0
## Open Space: a returning lone drone this close is taken back into its cradle (px).
@export var dock_radius: float = 72.0

@export_group("Idle")
## Open Space hub only (t14 plays these; declared here so the config is complete).
@export var perceive_radius: float = 700.0
@export var lose_radius: float = 1600.0
@export var notice_time: float = 0.35
@export var idle_radius: float = 160.0
@export var idle_speed: float = 0.5

@export_group("Assault")
## Seconds before an Assault tender disengages (one launch per life; a budget that runs out in the cradle telegraph lets that launch finish).
@export var engage_seconds: float = 10.0
## DISENGAGE speed (px/s).
@export var exit_speed: float = 380.0
