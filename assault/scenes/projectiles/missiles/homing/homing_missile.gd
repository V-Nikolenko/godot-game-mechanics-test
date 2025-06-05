class_name homing_missile
extends Area2D

@export var speed: float = 250.0
@export var locked_target: Node

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.play("default")


func _physics_process(delta: float) -> void:
	if locked_target and locked_target.is_inside_tree():
		_fly_to_target(delta)
	else:
		_fly_forward(delta)


func _fly_to_target(delta: float) -> void:
	var direction = (locked_target.global_position - global_position).normalized()
	rotation = direction.angle() + PI / 2
	global_position += direction * speed * delta
		
		
func _fly_forward(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta
		
		
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_hit_box_area_entered(area: Area2D) -> void:
	queue_free()
