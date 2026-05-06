class_name OpenSpacePlayerShip
extends CharacterBody2D

@export_category("Movement")
@export var rotation_speed_deg: float = 220.0
@export var thrust_acceleration: float = 380.0
@export var reverse_acceleration: float = 220.0
@export var max_speed: float = 420.0
@export var damping: float = 0.6

@export_category("Boost")
@export var boost_redirect_speed: float = 200.0
@export var boost_duration_sec: float = 0.3
@export var boost_speed_threshold: float = 180.0

@export_category("Combat")
@export var shoot_cooldown_sec: float = 0.18
@export var bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

@onready var muzzle_left: Marker2D = $SpriteAnchor/MuzzleLeft
@onready var muzzle_right: Marker2D = $SpriteAnchor/MuzzleRight
@onready var health_component: Health = $HealthComponent
@onready var shield_component: Shield = $ShieldComponent
@onready var hurt_box: HurtBox = $HurtBox

## Multipliers written by AbilityController / abilities.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
var overdrive_active: bool = false

var _shoot_cooldown: float = 0.0
var _gun_index: int = 0
var _boost_timer: float = 0.0

var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect
var _thruster: ThrusterEffect

func _ready() -> void:
	add_to_group("player")
	health_component.amount_changed.connect(_on_health_changed)
	_setup_effects()
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

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

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

	_boost_timer = max(_boost_timer - delta, 0.0)

	if Input.is_action_just_pressed("move_up") and _boost_timer <= 0.0:
		var backward_speed := -velocity.dot(forward)
		if backward_speed >= boost_speed_threshold:
			_trigger_flip_boost(forward)

	if thrust_input > 0.0:
		velocity += forward * thrust_acceleration * delta
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.THRUST)
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.IDLE)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

func _trigger_flip_boost(forward: Vector2) -> void:
	velocity = forward * boost_redirect_speed
	_boost_timer = boost_duration_sec

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

	_shoot_cooldown = shoot_cooldown_sec * (1.0 / maxf(fire_rate_multiplier, 0.01))

func _on_received_damage(damage: int) -> void:
	## Route through shield first; overflow goes to health.
	var overflow := shield_component.absorb(damage)
	if overflow > 0:
		health_component.decrease(overflow)
	_hit_effect.burst()

func _on_health_changed(current: int) -> void:
	if current == 0:
		_explosion_effect.explode()
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			get_tree().reload_current_scene()
