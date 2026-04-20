extends Node

@export var wave_manager: WaveManager

@onready var fighter_scene: PackedScene = preload("res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn")

func _ready() -> void:
	_register_waves()

func _register_waves() -> void:
	# Wave 1 — V formation of 5 fighters
	wave_manager.register_wave(100.0, [
		{"scene": fighter_scene, "offset": Vector2(0, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-40, 10), "delay": 0.1},
		{"scene": fighter_scene, "offset": Vector2(40, 10), "delay": 0.1},
		{"scene": fighter_scene, "offset": Vector2(-80, 20), "delay": 0.2},
		{"scene": fighter_scene, "offset": Vector2(80, 20), "delay": 0.2},
	])

	# Wave 2 — Diagonal line from left
	wave_manager.register_wave(300.0, [
		{"scene": fighter_scene, "offset": Vector2(-80, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-40, 15), "delay": 0.15},
		{"scene": fighter_scene, "offset": Vector2(0, 30), "delay": 0.3},
		{"scene": fighter_scene, "offset": Vector2(40, 45), "delay": 0.45},
	])

	# Wave 3 — Symmetric pincer (left + right flanks simultaneously)
	wave_manager.register_wave(500.0, [
		{"scene": fighter_scene, "offset": Vector2(-100, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-60, 10), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(100, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(60, 10), "delay": 0.0},
	])

	# Wave 4 — Dense frontal assault
	wave_manager.register_wave(750.0, [
		{"scene": fighter_scene, "offset": Vector2(-60, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-20, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(20, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(60, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-40, 20), "delay": 0.3},
		{"scene": fighter_scene, "offset": Vector2(0, 20), "delay": 0.3},
		{"scene": fighter_scene, "offset": Vector2(40, 20), "delay": 0.3},
	])
