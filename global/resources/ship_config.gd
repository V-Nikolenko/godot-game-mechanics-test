## ShipConfig — base resource for all ship configurations.
## Contains only properties shared by every ship type (health and contact damage).
## Each ship type has its own subclass with the properties it actually uses.
class_name ShipConfig
extends Resource

@export var max_health: int = 100
@export var collision_damage: int = 20
## Points awarded to the player for destroying this ship.
## Read by ScoreTracker via the enemy's config resource.
@export var score_value: int = 0
## If false, this ship doesn't count toward wave-clear bonuses (e.g. bonus drones).
@export var counts_toward_wave_clear: bool = true
