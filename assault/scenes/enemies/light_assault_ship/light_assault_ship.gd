class_name LightAssaultShip
extends CharacterBody2D

@onready var hurt_box: HurtBox = $HurtBox
@onready var health: Health = $Health
@onready var hit_flash_animation_player: AnimationPlayer = $HitFlashAnimationPlayer

func _on_hurt_box_received_damage(damage: int) -> void:
	print("Received damaged ")
	health.decrease(damage)


func _on_health_amount_changed(current_health:int) -> void:
	print("Current healthis " + str(current_health))
	hit_flash_animation_player.play("hit")
	if current_health == 0:
		print("died")
