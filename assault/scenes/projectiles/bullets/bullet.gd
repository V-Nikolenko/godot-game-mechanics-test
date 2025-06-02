class_name Bullet
extends Area2D

@export var speed: float = 500.0
var direction: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta


# --- Clear element from queue on screen exit --
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_hit_box_area_entered(area: Area2D) -> void:
	queue_free()
