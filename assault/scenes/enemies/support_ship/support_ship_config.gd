## SupportShipConfig - tuning resource for the Support Ship (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.11;
## research `2-research.md` §3.2). Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. The values are [judgement] starting defaults, tunable in the `.tres`.
##
## t10 reads only the Movement, Follow (`follow_distance`) and Assault (`engage_seconds`, `exit_speed`) groups; the
## Ward, Repair, Shield and Escort groups are authored now so the plan's table exists in one place, and are read by
## t11 (ward), t12 (repair and shield) and t13 (escort). `collision_damage` is 0: the contact profile is NONE.
class_name SupportShipConfig
extends ShipConfig

@export_group("Movement")
## Transit speed (px/s): the mover's cap.
@export var max_speed: float = 270.0
@export var acceleration: float = 700.0
## Heading change cap (rad/s).
@export var max_turn_rate: float = 4.0
## Sideways dodge added to the follow motion (px/s) and the period of its reversal (s).
@export var jink_strength: float = 60.0
@export var jink_period: float = 0.8

@export_group("Follow")
## The distance it holds behind its ward (px).
@export var follow_distance: float = 150.0
## Sideways offset of the soft formation anchor (px).
@export var follow_lateral: float = 40.0
## Inside this distance of the player it evades (px) at `evade_speed` (px/s).
@export var evade_radius: float = 300.0
@export var evade_speed: float = 240.0

@export_group("Ward")
## An ally is a ward candidate only with at least this `score_value`.
@export var ward_min_score: int = 20
## Candidates are searched within this radius (px); a ward is kept until it is farther than `ward_keep_radius`.
@export var ward_search_radius: float = 900.0
@export var ward_keep_radius: float = 1100.0
## A ward is kept at least this long (s) before a better one may replace it.
@export var min_ward_seconds: float = 2.0
## A challenger must score this many times the current ward to replace it.
@export var ward_switch_margin: float = 1.3
## How long it drifts without a ward before it gives up on supporting (s).
@export var no_ward_grace: float = 1.5

@export_group("Repair")
@export var beam_range: float = 380.0
## Seconds between repair pulses, each restoring `repair_fraction` of the ward's max HP.
@export var repair_period: float = 1.5
@export var repair_fraction: float = 0.06
## Total HP it may restore in one life.
@export var repair_budget: int = 150

@export_group("Shield")
## The arc of the shield it projects (degrees); Assault uses the narrower `assault_shield_arc_deg`.
@export var shield_arc_deg: float = 110.0
@export var assault_shield_arc_deg: float = 90.0
@export var shield_capacity: int = 40
@export var shield_regen_delay: float = 3.0
@export var shield_regen_seconds: float = 1.5
@export var shield_reboot_seconds: float = 4.0
## How fast the arc turns toward the player (rad/s).
@export var shield_turn_rate: float = 1.6
## The dish unfolds / folds over these many seconds.
@export var projector_unfold_seconds: float = 0.4
@export var projector_fold_seconds: float = 0.25

@export_group("Escort")
## An ally under this share of its max HP triggers the escort; it ends once the ally is over `escort_release_ratio`.
@export var escort_hp_ratio: float = 0.35
@export var escort_release_ratio: float = 0.5
## The tow's speed as a share of the ward's own `max_speed`.
@export var escort_tow_ratio: float = 1.25
## The support puts itself this far (px) between the ward and the player.
@export var interpose_distance: float = 90.0
@export var escort_max_seconds: float = 4.0
## The escort ends once the ward is this far from the player (px).
@export var escort_safe_distance: float = 700.0
@export var escort_cooldown: float = 6.0

@export_group("Assault")
## Seconds in the fight before it leaves, and its exit speed (px/s).
@export var engage_seconds: float = 9.0
@export var exit_speed: float = 300.0
## Keeps it inside the camera's view rect by this margin (px); the band it holds from the edge (px) and the band
## within which a ward counts as on-screen (px).
@export var view_margin: float = 48.0
@export var view_band: float = 24.0
@export var ward_view_band: float = 120.0

@export_group("Idle")
## Open Space hub only (epic §2.16; task t15). The support patrols a slow ring round its `patrol_anchor` until the player
## comes within `perceive_radius`, and goes home once the player is further than `lose_radius` (px). `lose_radius` sits
## above the largest distance its own cycle opens (`escort_safe_distance + follow_distance + interpose_distance` = 940),
## so the cycle itself never counts as losing the player.
@export var perceive_radius: float = 600.0
@export var lose_radius: float = 1300.0
## The beat between perceiving the player and supporting (s).
@export var notice_time: float = 0.35
## The patrol ring's radius round `patrol_anchor` (px) and its angular speed (rad/s).
@export var idle_radius: float = 150.0
@export var idle_speed: float = 0.5
