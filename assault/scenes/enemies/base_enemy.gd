class_name BaseEnemy
extends CharacterBody2D

signal died

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var hit_flash_player: AnimationPlayer = $HitFlashAnimationPlayer

var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect

func _ready() -> void:
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)
	hurt_box.collision_mask = 97 | 1024  # bullets (64) + rockets (32) + layer 1 + asteroid contact (1024)
	_rotate_sprite()
	_add_contact_hitbox()

	_hit_effect = HitEffect.new()
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	add_child(_explosion_effect)

func _rotate_sprite() -> void:
	var sprite := get_node_or_null("AnimatedSprite2D") as Node2D
	if sprite:
		sprite.rotation_degrees = 180.0

func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	var hb := HitBox.new()
	hb.collision_layer = 256
	hb.collision_mask = 0
	hb.damage = 20
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	add_child(hb)

func _on_received_damage(damage: int) -> void:
	health.decrease(damage)

func _on_health_changed(current: int) -> void:
	hit_flash_player.play("hit")
	_hit_effect.burst()
	if current == 0:
		print("[Enemy] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		died.emit()
		_explosion_effect.explode()
		queue_free()
