## DroneInterceptorConfig — tuning resource for the DroneInterceptor enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
class_name DroneInterceptorConfig
extends ShipConfig

## Preferred distance from the player while orbiting (px).
@export var orbit_radius         : float = 130.0
## Angular velocity of the orbit anchor (rad/s). Positive = counter-clockwise.
@export var orbit_speed          : float = 1.8
## Movement speed during ENTER phase (px/s).
@export var approach_speed       : float = 200.0
## Maximum speed when correcting orbit position (px/s).
@export var orbit_correct_speed  : float = 160.0
## Burst speed during the kamikaze dash (px/s).
@export var dash_speed           : float = 480.0
## How far ahead to predict the player position for the dash target (seconds).
@export var dash_prediction_time : float = 0.2
