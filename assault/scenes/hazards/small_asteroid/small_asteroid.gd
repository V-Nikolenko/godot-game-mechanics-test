class_name SmallAsteroid
extends AsteroidBase

const _OFF_SCREEN_MARGIN: float = 80.0

## Direction & speed assigned by BigAsteroid when this shard was spawned from
## a split. When non-zero, this drives movement directly (no move_and_slide).
## Wave-spawned small asteroids leave this at zero and let EnemyPathMover
## drive their position.
var drift_velocity: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	super(delta)
	if drift_velocity.length_squared() > 0.01:
		# Direct position update bypasses move_and_slide entirely so split
		# shards reliably keep moving regardless of physics layer quirks.
		global_position += drift_velocity * delta
	else:
		# Legacy / fallback — still useful if something sets velocity instead.
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
