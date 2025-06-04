extends CharacterBody2D

@onready var hurt_box: HurtBox = $HurtBox
@onready var heatlh: Health = $Health

func _on_hurt_box_received_damage(damage: int) -> void:
	pass # Replace with function body.
