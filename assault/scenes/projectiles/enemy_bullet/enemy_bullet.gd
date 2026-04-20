class_name EnemyBullet
extends Area2D

@export var speed: float = 250.0

var _direction: Vector2 = Vector2.DOWN

func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()
	rotation = _direction.angle() - PI / 2.0

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

func _on_hit_box_area_entered(_area: Area2D) -> void:
	queue_free()
