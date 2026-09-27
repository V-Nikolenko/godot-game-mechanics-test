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
