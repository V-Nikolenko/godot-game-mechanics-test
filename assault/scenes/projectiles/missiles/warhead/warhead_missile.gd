class_name WarheadMissile
extends Area2D

@export var speed: float = 640.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.play("default")
	add_child(RocketTrail.new())


func _physics_process(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta


func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()


func _on_hit_box_area_entered(area: Area2D) -> void:
	if _hit_is_deflected(area):
		return
	queue_free()


## True when the hurtbox we just overlapped refused to apply damage (e.g. the space-station core
## while any turret still lives). Duck-typed against `is_armored()`, same idiom as
## `bullet.gd::_hit_is_deflected` — a rocket gets the same exemption a bullet already has, so it
## survives crossing the boss's armoured core instead of detonating on it before reaching a turret.
func _hit_is_deflected(area: Area2D) -> bool:
	var target := area.get_parent()
	return target != null and target.has_method("is_armored") and target.is_armored()
