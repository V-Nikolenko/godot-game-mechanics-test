class_name WaveManager
extends Node

signal wave_triggered(wave_index: int)

@export var scroll_controller: ScrollController
@export var enemy_container: Node2D

# Waves registered via register_wave(). Each entry:
# { "trigger": float, "spawns": [{ "scene": PackedScene, "offset": Vector2, "delay": float }] }
var _waves: Array[Dictionary] = []
var _next_wave_index: int = 0

func _ready() -> void:
	if scroll_controller:
		scroll_controller.distance_changed.connect(_on_distance_changed)

func register_wave(trigger_distance: float, spawns: Array) -> void:
	_waves.append({"trigger": trigger_distance, "spawns": spawns})

func _on_distance_changed(distance: float) -> void:
	while _next_wave_index < _waves.size():
		var wave: Dictionary = _waves[_next_wave_index]
		if distance >= wave.trigger:
			_trigger_wave(wave, _next_wave_index)
			_next_wave_index += 1
		else:
			break

func _trigger_wave(wave: Dictionary, index: int) -> void:
	wave_triggered.emit(index)
	for spawn in wave.spawns:
		_spawn_with_delay(spawn)

func _spawn_with_delay(spawn: Dictionary) -> void:
	var delay: float = spawn.get("delay", 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_enemy(spawn.scene, spawn.get("offset", Vector2.ZERO))

func _spawn_enemy(scene: PackedScene, screen_offset: Vector2) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var spawn_pos := Vector2(
		cam.global_position.x + screen_offset.x,
		cam.global_position.y - viewport_size.y * 0.5 - 40.0 + screen_offset.y
	)
	var enemy := scene.instantiate()
	enemy.global_position = spawn_pos
	enemy_container.add_child(enemy)
