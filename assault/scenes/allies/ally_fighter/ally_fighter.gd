class_name AllyFighter
extends CharacterBody2D

@export var config: AllyFighterConfig = load("res://assault/scenes/allies/ally_fighter/ally_config.tres")

@export var speed: float = 100.0

@onready var _health: Health = $Health
@onready var _hurt_box: Area2D = $HurtBox
@onready var _contact_hit_box: HitBox = get_node_or_null("ContactHitBox") as HitBox

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

var bullet_pool: BulletPool
var _explosion_effect: ExplosionEffect

## Same two hooks, and the same reasoning, as `BaseEnemy._init()`/`_enter_tree()` — see the doc
## comment there. `AllyFighter` extends `CharacterBody2D` directly rather than `BaseEnemy`, so it
## is the one entity that would otherwise keep sharing its `ally_config.tres` with every other ally
## in the process.
func _init() -> void:
	ShipConfig.privatise(self)


func _enter_tree() -> void:
	ShipConfig.privatise(self)


func _ready() -> void:
	add_to_group("allies")
	_health.amount_changed.connect(_on_health_changed)

	# Bullet pool
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 8
	add_child(bullet_pool)

	# Attack pattern from config
	var pattern := ForwardAttackPattern.new()
	pattern.fire_interval = config.fire_interval if config else 0.75
	pattern.bullet_damage = config.bullet_damage if config else 10
	pattern.spawn_offset = Vector2(0.0, -10.0)

	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = bullet_pool
	add_child(controller)

	_explosion_effect = ExplosionEffect.new()
	add_child(_explosion_effect)

	if config:
		_health.max_health = config.max_health
		_health.current_health = config.max_health
		if _contact_hit_box:
			_contact_hit_box.damage = config.collision_damage

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
			_trace("[Ally] %s DESPAWNED (off-screen) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
			queue_free()

func _on_hurt_box_received_damage(damage: int) -> void:
	_health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current == 0:
		_trace("[Ally] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		_explosion_effect.explode()
		queue_free()


## Off unless Godot was started with `--verbose`.
func _trace(message: String) -> void:
	if OS.is_stdout_verbose():
		print(message)
