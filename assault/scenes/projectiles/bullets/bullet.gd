class_name Bullet
extends Area2D

signal expired

@export var speed: float = 500.0

func reset() -> void:
	rotation = 0.0

func _physics_process(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	expired.emit()

func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()
