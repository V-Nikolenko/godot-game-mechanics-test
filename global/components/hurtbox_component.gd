class_name HurtBox
extends Area2D

signal received_damage(damage: int)

func _ready() -> void:
	connect("area_entered", _on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is HitBox:
		received_damage.emit((area as HitBox).damage)
