class_name Gunship
extends BaseEnemy

@export var config: GunshipConfig = load("res://assault/scenes/enemies/gunship/gunship_config.tres")

enum Phase { ENTER, HOLD, RETREAT }

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
const _TEXTURE_FULL    := preload("res://assault/assets/sprites/enemies/heave_gunship.png")
const _TEXTURE_DAMAGED := preload("res://assault/assets/sprites/enemies/heavy_gunship_non_shielded.png")

var _phase: Phase = Phase.ENTER
var _hold_y: float = 0.0
var _burst_interval: float = 1.0
var _burst_gap: float = 0.12
var _bullet_damage: int = 15
var _bullet_speed: float = 260.0
var _entry_speed: float = 60.0
var _track_speed: float = 70.0
var _track_player: bool = true
var _retreat_hp_ratio: float = 0.3

var _bullet_pool: BulletPool
var _burst_timer: Timer
var _sprite: Sprite2D
var _firing: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	_sprite = $Sprite2D as Sprite2D

	if config:
		health.max_health      = config.max_health
		health.current_health  = config.max_health
		_burst_interval        = config.burst_interval
		_burst_gap             = config.burst_gap
		_bullet_damage         = config.bullet_damage
		_bullet_speed          = config.bullet_speed
		_entry_speed           = config.entry_speed
		_track_speed           = config.track_speed
		_track_player          = config.track_player
		_retreat_hp_ratio      = config.retreat_hp_ratio
		## BaseEnemy._add_contact_hitbox() hardcodes damage = 20 and never reads the config
		## (base_enemy.gd:56), so it has to be re-applied here — same as bomber.gd:23-26,
		## light_assault_ship.gd:20-23, ram_ship.gd:20-23 and space_station.gd:119-122.
		## Pinned for the whole roster by tests/integration/test_enemy_contact_damage.gd.
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + (config.hold_y_offset if config else 55.0)

	_bullet_pool              = BulletPool.new()
	_bullet_pool.bullet_scene = _BULLET_SCENE
	_bullet_pool.pool_size    = 15
	add_child(_bullet_pool)

	_burst_timer             = Timer.new()
	_burst_timer.wait_time   = _burst_interval
	_burst_timer.autostart   = false
	_burst_timer.one_shot    = false
	_burst_timer.timeout.connect(_fire_burst)
	add_child(_burst_timer)

	# Separate signal connection so we don't interfere with BaseEnemy's hit flash.
	health.amount_changed.connect(_on_health_changed_gunship)


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.ENTER:
			_phase_enter()
		Phase.HOLD:
			_phase_hold(delta)
		Phase.RETREAT:
			_phase_retreat()


func _phase_enter() -> void:
	if global_position.y < _hold_y:
		velocity = Vector2(0.0, _entry_speed)
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		_phase = Phase.HOLD
		_burst_timer.start()


func _phase_hold(_delta: float) -> void:
	velocity.y = 0.0

	if _track_player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var diff := (players[0] as Node2D).global_position.x - global_position.x
			velocity.x = sign(diff) * minf(absf(diff) * 2.0, _track_speed)
		else:
			velocity.x = 0.0
	else:
		velocity.x = 0.0

	move_and_slide()

	if health.current_health <= int(health.max_health * _retreat_hp_ratio):
		_burst_timer.stop()
		_phase = Phase.RETREAT


func _phase_retreat() -> void:
	velocity = Vector2(0.0, -_entry_speed * 1.5)
	move_and_slide()
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam and global_position.y < cam.global_position.y - viewport_size.y * 0.5 - 50.0:
		queue_free()


func _fire_burst() -> void:
	if _phase != Phase.HOLD or _firing:
		return
	_firing = true
	_shoot_from_barrel(Vector2(-12.0, 8.0))
	await get_tree().create_timer(_burst_gap).timeout
	if not is_instance_valid(self):
		return
	_firing = false
	if _phase != Phase.HOLD:
		return
	_shoot_from_barrel(Vector2(12.0, 8.0))


func _shoot_from_barrel(barrel_offset: Vector2) -> void:
	var barrel_world := global_position + barrel_offset
	var direction := Vector2.DOWN
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		direction = ((players[0] as Node2D).global_position - barrel_world).normalized()

	var bullet := _bullet_pool.acquire(barrel_world) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = _bullet_damage
	bullet.speed = _bullet_speed
	bullet.set_direction(direction)


func _on_health_changed_gunship(current: int) -> void:
	if _sprite and current <= health.max_health / 2:
		_sprite.texture = _TEXTURE_DAMAGED
