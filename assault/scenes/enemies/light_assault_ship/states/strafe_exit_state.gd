class_name FighterStrafeExitState
extends State

@export var actor: LightAssaultShip
@export var strafe_speed: float = 120.0
@export var downward_drift: float = 20.0

var _direction: float = 1.0

func enter() -> void:
	_direction = 1.0 if randf() > 0.5 else -1.0

func process_physics(delta: float) -> void:
	actor.velocity = Vector2(_direction * strafe_speed, downward_drift)
	actor.move_and_slide()

	var viewport_size := actor.get_viewport().get_visible_rect().size
	var cam := actor.get_viewport().get_camera_2d()
	if not cam:
		return
	var left_edge := cam.global_position.x - viewport_size.x * 0.5 - 60.0
	var right_edge := cam.global_position.x + viewport_size.x * 0.5 + 60.0

	if actor.global_position.x < left_edge or actor.global_position.x > right_edge:
		actor.queue_free()
