# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns patrol drones and wires mission configs into
## the Planet node so it knows which scenes to launch.

const PATROL_DRONE := preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")

@export var drone_count: int = 3
@export var spawn_radius: float = 600.0

@onready var enemy_container: Node2D = $EnemyContainer
@onready var planet: Planet = $Planet

func _ready() -> void:
	_spawn_initial_drones()
	_configure_planet()

func _spawn_initial_drones() -> void:
	for i: int in drone_count:
		var drone := PATROL_DRONE.instantiate()
		var angle := randf() * TAU
		var distance := randf_range(spawn_radius * 0.5, spawn_radius)
		drone.global_position = Vector2(cos(angle), sin(angle)) * distance
		drone.initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		enemy_container.add_child(drone)

func _configure_planet() -> void:
	var assault := MissionConfigResource.new()
	assault.display_name = "Assault"
	assault.scene_path = "res://assault/scenes/levels/level_1.tscn"
	assault.mission_id = "assault"
	assault.required_mission = ""  # always available

	var infiltration := MissionConfigResource.new()
	infiltration.display_name = "Infiltration"
	infiltration.scene_path = "res://infiltration_mission/scenes/levels/TestIsometricScene.tscn"
	infiltration.mission_id = "infiltration"
	infiltration.required_mission = "assault"  # locked until assault is done

	planet.missions = [assault, infiltration]
