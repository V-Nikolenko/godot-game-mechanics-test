## SwarmDroneConfig — tuning for the Swarm Drone (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md
## §2.7 config table, t8b rows; deviations logged in docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md).
## Flat by design: `ShipConfig.privatise()` makes a shallow copy per drone, which is complete only
## while nothing here is a nested Resource/Array/Dictionary (test_config_instance_isolation.gd).
## `swarm_drone.gd` copies every field onto its nodes in `_ready()` — this `.tres` wins over any
## value authored on the scene's nodes.
class_name SwarmDroneConfig
extends ShipConfig

@export_group("Movement")
## Non-burst speed cap (px/s) — also the overshoot request speed.
@export var max_speed: float = 220.0
## Speed-up rate (px/s²).
@export var acceleration: float = 600.0
## Slow-down rate (px/s²). High so the post-burst overshoot sheds its excess speed fast enough to
## still curve >= 60° (B5: at 500 it turned only ~44°).
@export var braking: float = 900.0
## Sprite turn cap (rad/s). Fast enough that the 0.4 s wind-up can swing the nose through 180°.
@export var max_turn_rate: float = 10.0

@export_group("Approach")
## Perpendicular speed of the corkscrew (px/s) — a velocity, not a distance; the lateral swing is
## about corkscrew_amplitude / (2π · corkscrew_frequency) px.
@export var corkscrew_amplitude: float = 120.0
## Corkscrew oscillations per second (Hz).
@export var corkscrew_frequency: float = 0.6

@export_group("Attack")
## Hold-and-face telegraph before each burst (s). Yellow light.
@export var windup_seconds: float = 0.4
## Ram speed (px/s).
@export var burst_speed: float = 480.0
## Ram duration (s). Red light, contact armed.
@export var burst_seconds: float = 0.45
## The ram prediction is clamp(distance / burst_speed, lead_time_min, lead_time_max) seconds ahead.
@export var lead_time_min: float = 0.4
@export var lead_time_max: float = 0.8
## After a missed burst, the drone curves back toward the player for this long (s), never stopping.
@export var overshoot_seconds: float = 0.8
## How fast the overshoot curve bends the drone's heading (rad/s).
@export var overshoot_turn_rate: float = 2.4
## Extra passes after the first missed burst before the drone rejoins.
@export var second_passes: int = 1
## EXPLOSIVE contact profile blast (px / damage).
@export var blast_radius: float = 48.0
@export var blast_damage: int = 15

@export_group("Exit")
## Assault only: seconds in the fight before the drone leaves by the nearest edge.
@export var engage_seconds: float = 5.5
## Assault only: speed cap while leaving (px/s).
@export var exit_speed: float = 320.0

@export_group("Squad")
## REAR members circle the target on this ring (px). APPROACH hands over at this + 100 px, and
## CLOSE_IN / FORM fall back to APPROACH beyond this + 200 px.
@export var rear_orbit_radius: float = 260.0
## The REAR ring's angular speed (rad/s). Keep `rear_orbit_speed × rear_orbit_radius` well under
## `max_speed`, or a REAR falls behind its slot and cuts inside the ring (the epic's 1.4 rad/s would be
## 364 px/s against a 220 px/s cap; t8c task plan D1).
@export var rear_orbit_speed: float = 0.55
## FLANK slots sit this far from the target (px). It is also the LEAD's CLOSE_IN ring.
@export var flank_distance: float = 200.0
## FLANK slots sit this far either side of the target's heading (degrees).
@export var flank_angle_deg: float = 70.0
## Squad mates closer than this push apart (px).
@export var separation_radius: float = 30.0
## The flocking + evade nudge is capped at this fraction of `max_speed`. 0 = nudges off.
@export var flock_nudge_cap: float = 0.35
## Outside WINDUP/BURST a drone this close to the target steers away from it (px).
@export var evade_radius: float = 90.0
## Assault only: a REAR member leaves after this many seconds, attackers after `engage_seconds`. Must
## not exceed `engage_seconds` (the §2.6 deadline uses that); a pre-approved t15 lever.
@export var rear_engage_seconds: float = 5.5

@export_group("Idle")
## Open Space only (t8d): enter combat when the player is within this of the drone (px).
@export var perceive_radius: float = 380.0
## Open Space only: drop back toward patrol once the player is beyond this (px). Must exceed
## `perceive_radius` (AnchorIdle's hysteresis margin).
@export var lose_radius: float = 620.0
## Open Space only: the NOTICING beat before entering combat (s).
@export var notice_time: float = 0.35
## Open Space only: the slow patrol ring's radius around `patrol_anchor` (px).
@export var idle_radius: float = 140.0
## Open Space only: the patrol ring's angular speed (rad/s).
@export var idle_speed: float = 0.6
