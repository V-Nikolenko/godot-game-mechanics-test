## MissileCorvetteConfig - tuning resource for the Missile Corvette
## (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.9; research `2-research.md` §3.2). Extends ShipConfig
## (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. The values are [judgement] starting defaults, tunable in the `.tres`.
##
## `max_speed` and `acceleration` are what the rocket scenes' launcher inequalities are checked against
## (`test_enemy_rockets.gd`: every rocket's `cruise_speed >= 1.1 x max_speed`, `launch_speed > acceleration x
## boost_seconds`). The salvo counts and `salvo_period_min` size the four rocket pools with
## `EnemyRocketScenes.pool_size_for()`. The rocket numbers themselves live in the rocket scenes, not here.
class_name MissileCorvetteConfig
extends ShipConfig

@export_group("Movement")
## Transit speed (px/s): APPROACH, and the mover's cap.
@export var max_speed: float = 210.0
@export var acceleration: float = 240.0
## Heading change cap (rad/s).
@export var max_turn_rate: float = 1.2

@export_group("Range")
## Open Space: the distance it holds from the player (px).
@export var preferred_range: float = 620.0
## Assault: the distance it holds (px); the corridor is narrower.
@export var assault_preferred_range: float = 460.0
## Closer than this it backs off (px).
@export var min_range: float = 380.0
## The held range drifts by up to this much (px) so it does not sit on one ring.
@export var range_drift: float = 80.0
## Slack around the held range inside which it does not correct (px).
@export var range_tolerance: float = 120.0

@export_group("Arc")
## The broad arc it circles the player on (rad/s).
@export var orbit_angular_speed: float = 0.22
## It reverses the arc after a random time in this range (s).
@export var reversal_min: float = 4.0
@export var reversal_max: float = 7.0

@export_group("Salvo")
## It launches only at a player inside this half-cone round its nose (degrees).
@export var launch_cone_deg: float = 45.0
## The telegraph before a salvo (s).
@export var salvo_telegraph: float = 0.7
## Rockets in a Dumb / Pursuit / Cluster salvo, and warheads in a Warhead salvo.
@export var salvo_count: int = 3
@export var warhead_salvo_count: int = 2
## The gap between rockets of one salvo (s).
@export var salvo_gap: float = 0.22
## Shortest and longest time between two salvos (s). `salvo_period_min` sizes the pools.
@export var salvo_period_min: float = 4.0
@export var salvo_period_max: float = 5.0
## Each rocket of a salvo leads the player by this much more (s), so the salvo covers where it is heading.
@export var salvo_lead_step: float = 0.25
## A warhead is aimed this far to either side of the player (px) and is chosen inside `warhead_range`.
@export var warhead_offset: float = 90.0
@export var warhead_range: float = 420.0
## A Cluster rocket is chosen only beyond this range (px).
@export var cluster_min_range: float = 700.0
## A Pursuit rocket is chosen only when the player is faster than this (px/s).
@export var pursuit_flee_speed: float = 300.0

@export_group("Engagement")
## Assault: seconds before the corvette disengages.
@export var engage_seconds: float = 7.0
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 280.0

@export_group("Rail")
## While a rail owns the corvette: a Dumb rocket DOWN every this many seconds.
@export var rail_rocket_interval: float = 2.5
