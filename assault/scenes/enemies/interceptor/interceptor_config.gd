## InterceptorConfig — tuning resource for the Interceptor enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
class_name InterceptorConfig
extends ShipConfig

## Seconds between shots (fire rate = 1 / fire_interval).
@export var fire_interval : float = 0.09
## Damage dealt per bullet.
@export var bullet_damage : int   = 4
## Travel speed of each bullet (px/s). Lower = shorter effective range.
@export var bullet_speed  : float = 220.0
## Max random rotation scatter per shot (radians). 0.08 ≈ ±4.5°.
@export var spread_angle  : float = 0.08
