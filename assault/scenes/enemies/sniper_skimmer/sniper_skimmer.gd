class_name SniperSkimmer
extends BaseEnemy

# direction: 1 = enters from left, travels right; -1 = enters from right, travels left
@export var speed: float = 150.0
@export var direction: float = 1.0

var _has_fired: bool = false
var _midpoint_x: float = 0.0

@onready var enemy_bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var cam := get_viewport().get_camera_2d()
	if cam:
		_midpoint_x = cam.global_position.x

func _physics_process(delta: float) -> void:
	velocity = Vector2(direction * speed, 0)
	move_and_slide()

	if not _has_fired and _passed_midpoint():
		_has_fired = true
		_fire()

	_check_off_screen()

func _passed_midpoint() -> bool:
	if direction > 0:
		return global_position.x >= _midpoint_x
	return global_position.x <= _midpoint_x

func _fire() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	var bullet: EnemyBullet = enemy_bullet_scene.instantiate()
	bullet.global_position = global_position
	var aim_dir := (players[0].global_position - global_position).normalized()
	bullet.set_direction(aim_dir)
	bullet.speed = 400.0
	get_parent().add_child(bullet)

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var half_w := viewport_size.x * 0.5 + 60.0
	if abs(global_position.x - cam.global_position.x) > half_w:
		queue_free()
