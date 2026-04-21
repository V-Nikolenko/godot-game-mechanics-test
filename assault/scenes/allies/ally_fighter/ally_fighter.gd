class_name AllyFighter
extends CharacterBody2D

enum AimMode { FORWARD, AUTO_AIM }

@export var speed: float = 100.0
@export var bullet_damage: int = 10
@export var aim_mode: AimMode = AimMode.FORWARD

## Setter keeps the fire Timer in sync when wave_manager applies ship stats after _ready().
@export var fire_interval: float = 0.75:
	set(value):
		fire_interval = value
		if is_instance_valid(_fire_timer_node):
			_fire_timer_node.wait_time = value

@onready var _health: Health = $Health
@onready var _hurt_box: Area2D = $HurtBox

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

var _fire_timer_node: Timer
var _explosion_effect: ExplosionEffect

func _ready() -> void:
	add_to_group("allies")
	_health.amount_changed.connect(_on_health_changed)
	_add_contact_hitbox()

	# Use a child Timer so shooting continues even when EnemyPathMover disables
	# this node's physics_process to take control of movement.
	_fire_timer_node = Timer.new()
	_fire_timer_node.wait_time = fire_interval
	_fire_timer_node.autostart = true
	_fire_timer_node.timeout.connect(_fire)
	add_child(_fire_timer_node)

	_explosion_effect = ExplosionEffect.new()
	add_child(_explosion_effect)

func _physics_process(_delta: float) -> void:
	# Movement when no EnemyPathMover is attached (standalone ally).
	# EnemyPathMover disables this via set_physics_process(false) and owns the position.
	velocity = Vector2(0.0, -speed)
	move_and_slide()

	# Cull when scrolled off the top — EnemyPathMover has its own off-screen check.
	var cam := get_viewport().get_camera_2d()
	if cam:
		var vp := get_viewport().get_visible_rect().size
		if global_position.y < cam.global_position.y - vp.y * 0.5 - 80.0:
			print("[Ally] %s DESPAWNED (off-screen) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
			queue_free()

func _fire() -> void:
	var bullet: Bullet = _BULLET_SCENE.instantiate() as Bullet
	bullet.global_position = global_position + Vector2(0.0, -10.0)
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage

	if aim_mode == AimMode.FORWARD:
		# Shoot straight forward (up)
		bullet.rotation = 0.0
	else:  # AUTO_AIM
		# Aim at nearest enemy; clamp to upper hemisphere so the ally never shoots backward.
		var enemies := get_tree().get_nodes_in_group("enemies")
		var nearest: Node2D = null
		var nearest_dist: float = INF
		for e: Node in enemies:
			var d: float = (e as Node2D).global_position.distance_squared_to(global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = e as Node2D

		if nearest != null:
			var dir := (nearest.global_position - global_position).normalized()
			bullet.rotation = atan2(dir.x, -dir.y) if dir.y < 0.4 else 0.0
		else:
			bullet.rotation = 0.0

	get_parent().add_child(bullet)

func _on_hurt_box_received_damage(damage: int) -> void:
	_health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current == 0:
		print("[Ally] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		_explosion_effect.explode()
		queue_free()

func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	# Layer 64 = player_hitbox — enemy HurtBoxes (mask 97) detect this and take damage.
	var hb := HitBox.new()
	hb.collision_layer = 64
	hb.collision_mask = 0
	hb.damage = 25
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	add_child(hb)
