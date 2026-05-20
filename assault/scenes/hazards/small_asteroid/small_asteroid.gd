class_name SmallAsteroid
extends AsteroidBase

const _OFF_SCREEN_MARGIN: float = 80.0

func _physics_process(delta: float) -> void:
	super(delta)
	move_and_slide()
	_check_off_screen()

func _check_off_screen() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if not cam:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if (
		global_position.y > cam.global_position.y + vp.y * 0.5 + _OFF_SCREEN_MARGIN
		or global_position.y < cam.global_position.y - vp.y * 0.5 - _OFF_SCREEN_MARGIN
		or global_position.x > cam.global_position.x + vp.x * 0.5 + _OFF_SCREEN_MARGIN
		or global_position.x < cam.global_position.x - vp.x * 0.5 - _OFF_SCREEN_MARGIN
	):
		queue_free()
