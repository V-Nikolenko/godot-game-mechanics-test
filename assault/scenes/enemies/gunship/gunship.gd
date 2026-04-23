class_name Gunship
extends BaseEnemy

@export var config: GunshipConfig = load("res://assault/scenes/enemies/gunship/gunship_config.tres")

@export var hold_y_offset: float = 55.0
@export var entry_speed: float = 60.0
@export var track_speed: float = 70.0
@export var fire_interval: float = 0.6
@export var retreat_hp_ratio: float = 0.3

var _hold_y: float = 0.0
var _entered: bool = false
var _retreating: bool = false
var _gun_side: int = 0
var _fire_timer_node: Timer

@export var bullet_pool: BulletPool
const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		fire_interval = config.fire_interval
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset

	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 12
	add_child(bullet_pool)

	_fire_timer_node = Timer.new()
	_fire_timer_node.wait_time = fire_interval
	_fire_timer_node.autostart = true
	_fire_timer_node.timeout.connect(_fire)
	add_child(_fire_timer_node)

func _physics_process(delta: float) -> void:
	if _retreating:
		_retreat(delta)
		return

	if not _entered:
		_enter(delta)
		return

	if float(health.current_health) / float(health.max_health) <= retreat_hp_ratio:
		_retreating = true
		return

	_hold_and_fire(delta)

func _enter(delta: float) -> void:
	if global_position.y < _hold_y:
		velocity = Vector2(0, entry_speed)
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		_entered = true

func _hold_and_fire(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var diff := (players[0] as Node2D).global_position.x - global_position.x
		var move_x: float = sign(diff) * min(abs(diff) * 2.0, track_speed) * delta
		velocity = Vector2(move_x, 0)
		move_and_slide()
	# Firing is handled by _fire_timer_node (child Timer).

func _fire() -> void:
	_gun_side = (_gun_side + 1) % 2
	var offset := Vector2(-10.0 if _gun_side == 0 else 10.0, 8.0)
	var bullet := bullet_pool.acquire(global_position + offset) as EnemyBullet
	if not bullet:
		return
	# Default direction (Vector2.DOWN) is fine — shoots straight down.

func _retreat(delta: float) -> void:
	velocity = Vector2(0, -entry_speed)
	move_and_slide()
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam and global_position.y < cam.global_position.y - viewport_size.y * 0.5 - 50.0:
		queue_free()
