class_name KamikazeDrone
extends BaseEnemy

@export var speed: float = 200.0

var _target_position: Vector2

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target_position = players[0].global_position
	else:
		_target_position = global_position + Vector2(0, 500)

func _physics_process(delta: float) -> void:
	var direction := (_target_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()
	_check_off_screen()

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var bottom := cam.global_position.y + viewport_size.y * 0.5 + 60.0
	if global_position.y > bottom:
		queue_free()
