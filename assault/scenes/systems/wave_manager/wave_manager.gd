class_name WaveManager
extends Node

signal wave_triggered(wave_index: int)

@export var scroll_controller: ScrollController
@export var enemy_container: Node2D

# Waves registered via register_wave(). Each wave dict:
# {
#   "trigger": float,                          — scroll distance that fires this wave
#   "scroll_speed": float (optional),          — overrides scroll speed when wave triggers
#   "spawns": Array of spawn dicts
# }
#
# Each spawn dict:
# {
#   "scene": PackedScene,
#   "offset": Vector2  (meaning varies by spawn_edge),
#   "delay": float     (seconds after wave trigger),
#   "spawn_edge": String  "top" | "left" | "right"  (default: "top"),
#   "on_spawned": Callable  (optional, receives the instantiated node)
# }
#
# For "top":   offset.x = horiz offset from screen centre, offset.y = extra y push (0 = just above screen)
# For "left":  offset.y = vert offset from screen centre   (spawns beyond left edge)
# For "right": offset.y = vert offset from screen centre   (spawns beyond right edge)

var _waves: Array[Dictionary] = []
var _next_wave_index: int = 0

func _ready() -> void:
	if scroll_controller:
		scroll_controller.distance_changed.connect(_on_distance_changed)

func register_wave(trigger_distance: float, spawns: Array, override_scroll_speed: float = -1.0) -> void:
	var wave := {"trigger": trigger_distance, "spawns": spawns}
	if override_scroll_speed >= 0.0:
		wave["scroll_speed"] = override_scroll_speed
	_waves.append(wave)

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
	if wave.has("scroll_speed") and scroll_controller:
		scroll_controller.set_speed(wave.scroll_speed)
	for spawn in wave.spawns:
		_spawn_with_delay(spawn)

func _spawn_with_delay(spawn: Dictionary) -> void:
	var delay: float = spawn.get("delay", 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_enemy(spawn)

func _spawn_enemy(spawn: Dictionary) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var offset: Vector2 = spawn.get("offset", Vector2.ZERO)
	var edge: String = spawn.get("spawn_edge", "top")
	var spawn_pos: Vector2

	match edge:
		"left":
			spawn_pos = Vector2(
				cam.global_position.x - viewport_size.x * 0.5 - 50.0,
				cam.global_position.y + offset.y
			)
		"right":
			spawn_pos = Vector2(
				cam.global_position.x + viewport_size.x * 0.5 + 50.0,
				cam.global_position.y + offset.y
			)
		_: # "top"
			spawn_pos = Vector2(
				cam.global_position.x + offset.x,
				cam.global_position.y - viewport_size.y * 0.5 - 40.0 + offset.y
			)

	var enemy := spawn.scene.instantiate()
	enemy.global_position = spawn_pos
	enemy_container.add_child(enemy)

	if spawn.has("on_spawned"):
		spawn.on_spawned.call(enemy)
