# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns patrol drones and assigns the planet config.
## To change this planet's missions, background, or sprite — edit edelia.tres.
## To use a different config, change the path in _configure_planet().

const PATROL_DRONE    := preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")
const _EDELIA_CONFIG  := preload("res://global/resources/planet_configs/edelia.tres")

@export var drone_count: int    = 3
@export var spawn_radius: float = 600.0

@onready var enemy_container: Node2D         = $EnemyContainer
@onready var planet:          MissionTrigger = $Planet

func _ready() -> void:
	_configure_planet()
	_spawn_initial_drones()

func _configure_planet() -> void:
	planet.config = _EDELIA_CONFIG

func _spawn_initial_drones() -> void:
	for i: int in drone_count:
		var drone := PATROL_DRONE.instantiate()
		var angle    := randf() * TAU
		var distance := randf_range(spawn_radius * 0.5, spawn_radius)
		drone.global_position = Vector2(cos(angle), sin(angle)) * distance
		drone.initial_direction = Vector2(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		enemy_container.add_child(drone)
