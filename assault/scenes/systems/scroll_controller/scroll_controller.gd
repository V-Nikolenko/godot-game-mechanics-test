class_name ScrollController
extends Node

signal distance_changed(distance: float)

@export var camera: Camera2D
@export var scroll_speed: float = 30.0
@export var enabled: bool = true

var distance: float = 0.0

func _process(delta: float) -> void:
	if not enabled or not camera:
		return
	var step := scroll_speed * delta
	distance += step
	camera.position.y -= step
	distance_changed.emit(distance)

func set_speed(new_speed: float) -> void:
	scroll_speed = new_speed

func pause() -> void:
	enabled = false

func resume() -> void:
	enabled = true
