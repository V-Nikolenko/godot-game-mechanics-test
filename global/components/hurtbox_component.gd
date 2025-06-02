class_name HurtBox
extends Area2D

signal received_damage(damage: int)

func _ready() -> void:
	connect("area_entered", _on_area_entered)

func _on_area_entered(hitbox: HitBox) -> void:
	if hitbox != null:
		received_damage.emit(hitbox.damage)
