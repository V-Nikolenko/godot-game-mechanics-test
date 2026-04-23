## FighterConfig — configuration for LightAssaultShip.
class_name FighterConfig
extends ShipConfig

@export var movement_speed: float = 100.0
@export var fire_interval: float = 0.8
@export var bullet_damage: int = 8
## "PLAYER" = aim at nearest player, "FORWARD" = shoot straight down
@export var aim_mode: String = "PLAYER"
