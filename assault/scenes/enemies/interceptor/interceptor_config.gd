## InterceptorConfig — tuning resource for the Interceptor enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
class_name InterceptorConfig
extends ShipConfig

## Preferred distance from the player while orbiting (px).
@export var orbit_radius         : float = 200.0
## Angular velocity of the orbit anchor (rad/s). Positive = counter-clockwise.
@export var orbit_speed          : float = 1.4
## Movement speed during ENTER and REACQUIRE phases (px/s).
@export var approach_speed       : float = 220.0
## Maximum speed when correcting orbit position (px/s). Actual speed is proportional to error.
@export var orbit_correct_speed  : float = 170.0
## Burst speed during a dash intercept (px/s).
@export var dash_speed           : float = 440.0
## How long each dash lasts (seconds).
@export var dash_duration        : float = 0.35
## Time between dashes while in orbit (seconds).
@export var dash_interval        : float = 3.5
## How far ahead to predict the player position for the dash target (seconds).
@export var dash_prediction_time : float = 0.28
## Seconds between shots while orbiting.
@export var fire_interval        : float = 0.55
## Speed of each bullet (px/s).
@export var bullet_speed         : float = 290.0
## Damage dealt per bullet.
@export var bullet_damage        : int   = 10
