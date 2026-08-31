class_name Bomber
extends BaseEnemy

@export var config: BomberConfig = load("res://assault/scenes/enemies/bomber/bomber_config.tres")

# direction: 1 = left-to-right, -1 = right-to-left
@export var speed: float = 80.0
@export var direction: float = 1.0
@export var bomb_interval: float = 1.2

@onready var bomb_scene: PackedScene = preload("res://assault/scenes/enemies/bomber/bomb.tscn")
var _bomb_timer_node: Timer

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		speed = config.movement_speed
		bomb_interval = config.bomb_interval
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	# Child Timer fires independently of physics_process so bombing continues
	# even when EnemyPathMover takes control of movement.
	_bomb_timer_node = Timer.new()
	_bomb_timer_node.wait_time = bomb_interval
	_bomb_timer_node.autostart = true
	_bomb_timer_node.timeout.connect(_drop_bomb)
	add_child(_bomb_timer_node)

func _physics_process(_delta: float) -> void:
	velocity = Vector2(direction * speed, 0)
	move_and_slide()
	_check_off_screen()

func _drop_bomb() -> void:
	var bomb := bomb_scene.instantiate()
	bomb.global_position = global_position
	get_parent().add_child(bomb)

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var half_w := viewport_size.x * 0.5 + 70.0
	if abs(global_position.x - cam.global_position.x) > half_w:
		queue_free()
