class_name OpenSpacePlayerShip
extends CharacterBody2D

## Asteroids-arcade-style player ship for the Open Space hub.
## - Rotates 360° via move_left/move_right (A/D or arrow keys)
## - Thrusts forward via move_up (W or up arrow)
## - Reverse thrust via move_down (S or down arrow)
## - Inertia: velocity persists when no input is given (with light damping)
## - Shoots via the "shoot" action (J or LMB) — bullet flies in ship's facing direction

@export_category("Movement")
@export var rotation_speed_deg: float = 220.0   ## degrees per second
@export var thrust_acceleration: float = 380.0  ## pixels/sec^2
@export var reverse_acceleration: float = 220.0
@export var max_speed: float = 420.0
@export var damping: float = 0.6                ## velocity multiplier per second when idle (lower = more drag)

@export_category("Combat")
@export var shoot_cooldown_sec: float = 0.18
@export var bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

@onready var muzzle_left: Marker2D = $SpriteAnchor/MuzzleLeft
@onready var muzzle_right: Marker2D = $SpriteAnchor/MuzzleRight
@onready var health_component: Health = $HealthComponent
@onready var hurt_box: HurtBox = $HurtBox

var _shoot_cooldown: float = 0.0
var _gun_index: int = 0

# ── Particle effect components (reused from PlayerFighter pattern) ────────────
var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect

func _ready() -> void:
	add_to_group("player")
	hurt_box.received_damage.connect(_on_received_damage)
	health_component.amount_changed.connect(_on_health_changed)
	_setup_effects()
	# Sprite is drawn pointing UP at rotation 0 — that matches our convention:
	# "forward" is Vector2.UP rotated by self.rotation.
	rotation = 0.0

func _setup_effects() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	_handle_shoot(delta)
	move_and_slide()

func _handle_rotation(delta: float) -> void:
	var turn: float = 0.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	rotation += deg_to_rad(rotation_speed_deg) * turn * delta

func _handle_thrust(delta: float) -> void:
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	var thrust_input: float = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 1.0

	if thrust_input > 0.0:
		velocity += forward * thrust_acceleration * delta
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
	else:
		# Inertia damping when no input — exponential decay
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

func _handle_shoot(delta: float) -> void:
	_shoot_cooldown = max(_shoot_cooldown - delta, 0.0)
	if _shoot_cooldown > 0.0:
		return
	if not Input.is_action_pressed("shoot"):
		return

	var muzzles: Array[Marker2D] = [muzzle_left, muzzle_right]
	_gun_index = (_gun_index + 1) % muzzles.size()
	var muzzle: Marker2D = muzzles[_gun_index]

	var bullet: Area2D = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position + Vector2.UP.rotated(global_rotation) * 4.0
	bullet.rotation = global_rotation
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(bullet)
		bullet.expired.connect(bullet.queue_free)

	_shoot_cooldown = shoot_cooldown_sec

func _on_received_damage(damage: int) -> void:
	health_component.decrease(damage)
	_hit_effect.burst()

func _on_health_changed(current: int) -> void:
	if current == 0:
		_explosion_effect.explode()
		# MVP: just reload the hub scene on death
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			get_tree().reload_current_scene()
