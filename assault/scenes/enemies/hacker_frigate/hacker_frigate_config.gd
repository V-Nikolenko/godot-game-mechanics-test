## HackerFrigateConfig - tuning resource for the Hacker Frigate (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10, §2.19; task t8,
## task plan docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md). Extends ShipConfig (max_health, collision_damage, score_value, the hazard
## profile, the wreck roll).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is
## complete. The values are [judgement] starting defaults (§2.19), tunable in the `.tres`. The brain reads the cone fields every tick, so a
## test may switch a cone on after a warm-up. The pulse fields arrive with TELEGRAPH / PULSE (t9).
class_name HackerFrigateConfig
extends ShipConfig

@export_group("Movement")
## The mover's cap (px/s): the orbit's correction speed and the Assault break-off.
@export var max_speed: float = 230.0
## px/s². The Support Ship's value: a wrong-way orbit at 216 px/s stops in 0.31 s, so "the nearer edge" is always the faster cone exit
## (at 260 it takes 0.83 s; plan §2.10 "Why acceleration is 700").
@export var acceleration: float = 700.0
## Heading change cap (rad/s).
@export var max_turn_rate: float = 1.4

@export_group("Range")
## Open Space: the distance it holds from the player (px).
@export var preferred_range: float = 720.0
## Assault: the distance it holds (px); the corridor is narrower.
@export var assault_preferred_range: float = 520.0
## The held range drifts by up to this much (px) so it does not sit on one ring.
@export var range_drift: float = 90.0
## Closer than this it breaks off (px).
@export var min_range: float = 420.0

@export_group("Arc")
## The lopsided arc round the player (rad/s): `orbit_dir` +1 (clockwise on screen) at `orbit_speed_cw`, -1 at `orbit_speed_ccw`.
@export var orbit_speed_cw: float = 0.18
@export var orbit_speed_ccw: float = 0.30
## It reverses the arc after a random time in this range (s); the clock is held while it is inside a cone.
@export var reversal_min: float = 3.0
@export var reversal_max: float = 6.0

@export_group("Cones")
## The player's nose cone: ± this many degrees round its facing. 0 = off.
@export var nose_cone_deg: float = 30.0
## The player's route cone: ± this many degrees round its velocity, live only above `route_min_speed`. 0 = off.
@export var route_cone_deg: float = 25.0
@export var route_min_speed: float = 80.0
## Inside a cone the arc runs toward the nearer edge at this speed, either direction (rad/s).
@export var cone_escape_speed: float = 0.30

@export_group("Break-off")
## Open Space: the committed burst (`mover.boost`, ignores `max_speed`) and its sideways share against `Steering.break_contact`
## (doubled against a closing threat: radial 360 / sqrt(1.25) ≈ 322 px/s, above a 300 px/s rusher, below the player's 420 cruise).
@export var break_speed: float = 360.0
@export var break_lateral_weight: float = 0.25
## One burst's length (s); re-issued at its end while still inside `min_range + break_exit_margin`.
@export var break_burst_seconds: float = 0.8
## BREAK_OFF ends once the player is further than `min_range + break_exit_margin` (px; 540) ...
@export var break_exit_margin: float = 120.0
## ... or after this long (s), and the next one waits `break_rearm_seconds`.
@export var break_max_seconds: float = 3.0
@export var break_rearm_seconds: float = 1.0

@export_group("Assault")
## Every target point is clamped into `EnemyWorld.view_rect().grow(-view_margin)` (px), so the Hacker stays on screen.
@export var view_margin: float = 60.0
## Seconds before it disengages.
@export var engage_seconds: float = 9.0
## DISENGAGE speed (px/s).
@export var exit_speed: float = 300.0

@export_group("Idle")
## Open Space hub only: a slow ring round `patrol_anchor` until the player is within `perceive_radius`; home again beyond `lose_radius`
## (px). `lose_radius` sits above the furthest distance its own fight opens (`preferred_range + range_drift` + a break-off's 540).
@export var perceive_radius: float = 760.0
@export var lose_radius: float = 1600.0
## The beat between perceiving the player and fighting (s).
@export var notice_time: float = 0.35
## The patrol ring's radius (px) and angular speed (rad/s; the cw arc runs at `idle_speed · orbit_speed_cw / orbit_speed_ccw`).
@export var idle_radius: float = 160.0
@export var idle_speed: float = 0.45
