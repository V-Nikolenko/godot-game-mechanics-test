class_name FighterApproachState
extends State

@export var actor: LightAssaultShip
@export var speed: float = 80.0
@export var hold_y_offset: float = 80.0
@export var fire_interval: float = 1.2
@export var strafe_state: State

@onready var enemy_bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _fire_timer: float = 0.0
var _hold_y: float = 0.0

func enter() -> void:
	_fire_timer = fire_interval * 0.5
	var viewport_size := actor.get_viewport().get_visible_rect().size
	var cam := actor.get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset

func process_physics(delta: float) -> void:
	if actor.global_position.y < _hold_y:
		actor.velocity = Vector2(0, speed)
		actor.move_and_slide()
	else:
		state_transition.emit(strafe_state)
		return

	_fire_timer += delta
	if _fire_timer >= fire_interval:
		_fire_timer = 0.0
		_fire()

func _fire() -> void:
	var bullet: EnemyBullet = enemy_bullet_scene.instantiate()
	bullet.global_position = actor.global_position
	actor.get_parent().add_child(bullet)
