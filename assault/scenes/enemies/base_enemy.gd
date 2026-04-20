class_name BaseEnemy
extends CharacterBody2D

signal died

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var hit_flash_player: AnimationPlayer = $HitFlashAnimationPlayer

func _ready() -> void:
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)

func _on_received_damage(damage: int) -> void:
	health.decrease(damage)

func _on_health_changed(current: int) -> void:
	hit_flash_player.play("hit")
	if current == 0:
		died.emit()
		queue_free()
