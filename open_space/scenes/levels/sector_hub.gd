# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns patrol drones.
## Planet mission data is fully configured in the PlanetConfigResource .tres file
## assigned to the Planet node in the Inspector — no code changes needed per planet.

const PATROL_DRONE := preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")

@export var drone_count: int    = 3
@export var spawn_radius: float = 600.0

@onready var enemy_container: Node2D        = $EnemyContainer
@onready var planet:          MissionTrigger = $Planet

func _ready() -> void:
	_spawn_initial_drones()

func _spawn_initial_drones() -> void:
	for i: int in drone_count:
		var drone := PATROL_DRONE.instantiate()
		var angle    := randf() * TAU
		var distance := randf_range(spawn_radius * 0.5, spawn_radius)
		drone.global_position = Vector2(cos(angle), sin(angle)) * distance
		drone.initial_direction = Vector2(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		enemy_container.add_child(drone)
