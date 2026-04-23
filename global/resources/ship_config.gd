## ShipConfig — base resource for all ship configurations.
## Contains only properties shared by every ship type (health and contact damage).
## Each ship type has its own subclass with the properties it actually uses.
class_name ShipConfig
extends Resource

@export var max_health: int = 100
@export var collision_damage: int = 20
