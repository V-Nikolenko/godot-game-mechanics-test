## SpaceStationConfig — tuning for the Level 1 space-station mini-boss.
##
## `max_health`, `collision_damage`, `score_value` and `counts_toward_wave_clear` come from
## ShipConfig. Applied in SpaceStation._ready(), where the .tres wins over the values authored
## on the scene's Health nodes — the project-wide config-driven rule.
##
## There is deliberately NO per-turret score field: nothing could pay it out. ScoreTracker
## registers kills via WaveManager.enemy_spawned + BaseEnemy.died (score_tracker.gd:55-75), and
## a turret is a plain Node2D that is never spawned through WaveManager and never leaves the
## tree. Per-turret scoring needs a payout path that does not exist yet.
class_name SpaceStationConfig
extends ShipConfig

## HP of each individual turret. SpaceStation._ready() writes this into every turret's Health.
@export var turret_health: int = 120
