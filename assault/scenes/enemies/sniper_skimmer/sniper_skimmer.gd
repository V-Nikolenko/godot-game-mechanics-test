class_name SniperSkimmer
extends BaseEnemy

@export var config: SniperConfig = load("res://assault/scenes/enemies/sniper_skimmer/sniper_config.tres")

# direction: 1 = enters from left, travels right; -1 = enters from right, travels left
@export var speed: float = 130.0
@export var direction: float = 1.0

var _has_fired: bool = false
var _midpoint_x: float = 0.0

@export var bullet_pool: BulletPool
const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		speed = config.movement_speed
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	var cam := get_viewport().get_camera_2d()
	if cam:
		_midpoint_x = cam.global_position.x

	# Sniper fires once — a small pool is enough.
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 3
	add_child(bullet_pool)

func _process(_delta: float) -> void:
	# EnemyPathMover disables physics_process but NOT process, so midpoint
	# detection works whether the ship is path-driven or self-driven.
	if not _has_fired and _passed_midpoint():
		_has_fired = true
		_fire()

func _physics_process(delta: float) -> void:
	velocity = Vector2(direction * speed, 0)
	move_and_slide()
	_check_off_screen()

func _passed_midpoint() -> bool:
	if direction > 0:
		return global_position.x >= _midpoint_x
	return global_position.x <= _midpoint_x

func _fire() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	var bullet := bullet_pool.acquire(global_position) as EnemyBullet
	if not bullet:
		return
	var aim_dir := ((players[0] as Node2D).global_position - global_position).normalized()
	bullet.set_direction(aim_dir)
	bullet.speed = 400.0

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var half_w := viewport_size.x * 0.5 + 60.0
	if abs(global_position.x - cam.global_position.x) > half_w:
		queue_free()
