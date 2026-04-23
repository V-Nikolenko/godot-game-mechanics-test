## AllyFighterConfig — configuration for AllyFighter.
class_name AllyFighterConfig
extends ShipConfig

@export var fire_interval: float = 0.75
@export var bullet_damage: int = 10
## "FORWARD" = shoot straight up, "AUTO_AIM" = aim at nearest enemy
@export var aim_mode: String = "FORWARD"
