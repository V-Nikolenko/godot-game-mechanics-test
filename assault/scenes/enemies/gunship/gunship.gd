class_name Gunship
extends BaseEnemy

@export var hold_y_offset: float = 55.0
@export var entry_speed: float = 60.0
@export var track_speed: float = 70.0
@export var fire_interval: float = 0.8
@export var retreat_hp_ratio: float = 0.3

var _hold_y: float = 0.0
var _entered: bool = false
var _retreating: bool = false
var _fire_timer: float = 0.0
var _gun_side: int = 0

@onready var enemy_bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset

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

	_fire_timer += delta
	if _fire_timer >= fire_interval:
		_fire_timer = 0.0
		_fire()

func _fire() -> void:
	_gun_side = (_gun_side + 1) % 2
	var offset := Vector2(-10.0 if _gun_side == 0 else 10.0, 8.0)
	var bullet: EnemyBullet = enemy_bullet_scene.instantiate()
	bullet.global_position = global_position + offset
	get_parent().add_child(bullet)

func _retreat(delta: float) -> void:
	velocity = Vector2(0, -entry_speed)
	move_and_slide()
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam and global_position.y < cam.global_position.y - viewport_size.y * 0.5 - 50.0:
		queue_free()
