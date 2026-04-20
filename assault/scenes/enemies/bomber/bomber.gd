class_name Bomber
extends BaseEnemy

# direction: 1 = left-to-right, -1 = right-to-left
@export var speed: float = 50.0
@export var direction: float = 1.0
@export var bomb_interval: float = 1.2

var _bomb_timer: float = 0.0

@onready var bomb_scene: PackedScene = preload("res://assault/scenes/enemies/bomber/bomb.tscn")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	velocity = Vector2(direction * speed, 0)
	move_and_slide()

	_bomb_timer += delta
	if _bomb_timer >= bomb_interval:
		_bomb_timer = 0.0
		_drop_bomb()

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
