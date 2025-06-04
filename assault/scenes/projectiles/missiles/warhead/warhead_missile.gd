class_name WarheadMissile
extends Area2D

@export var speed: float = 250.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	animated_sprite.play("default")


func _physics_process(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

func _on_hit_box_area_entered(area: Area2D) -> void:
	queue_free()
