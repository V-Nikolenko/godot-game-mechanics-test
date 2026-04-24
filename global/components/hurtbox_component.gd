class_name HurtBox
extends Area2D

signal received_damage(damage: int)

## When empty, all damage types are accepted. Otherwise only listed types pass.
@export var accepted_damage_types: Array[HitBox.DamageType] = []

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	var hb := area as HitBox
	if not hb:
		return
	if not accepted_damage_types.is_empty() and hb.damage_type not in accepted_damage_types:
		return
	received_damage.emit(hb.damage)
