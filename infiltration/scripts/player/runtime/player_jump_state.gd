extends RefCounted
class_name PlayerJumpState

var settings: PlayerJumpSettings
var z_position: float = 0.0
var z_velocity: float = 0.0
var jumps_used: int = 0
var hover_timer: float = 0.0
var hover_active: bool = false
var hover_used: bool = false
var hover_start_height: float = 0.0


func _init(jump_settings: PlayerJumpSettings) -> void:
	settings = jump_settings


func handle_input(jump_pressed: bool) -> bool:
	if not settings.enabled:
		return false

	if not jump_pressed:
		return false

	if is_grounded():
		jumps_used = 1
		z_velocity = settings.jump_force
		hover_timer = 0.0
		hover_active = false
		hover_used = false
		hover_start_height = 0.0
		return true

	if settings.hover_enabled and not hover_used:
		_start_hover()
		return true

	if jumps_used >= settings.max_jumps:
		return false

	jumps_used += 1
	z_velocity = settings.air_jump_force
	hover_active = false
	hover_timer = 0.0
	hover_start_height = 0.0
	return true


func update(delta: float, jump_held: bool) -> void:
	if is_grounded():
		return

	var gravity_scale := 1.0
	if _is_hovering():
		if not jump_held:
			hover_active = false
		elif _has_reached_hover_height_limit():
			hover_active = false
			z_position = hover_start_height + settings.hover_max_height_gain
			z_velocity = minf(z_velocity, 0.0)

	if _is_hovering():
		gravity_scale = settings.hover_gravity_scale
		hover_timer = maxf(hover_timer - delta, 0.0)
		if hover_timer <= 0.0:
			hover_active = false

	z_velocity -= settings.gravity * gravity_scale * delta
	z_position += z_velocity * delta

	if hover_used and z_position > hover_start_height + settings.hover_max_height_gain:
		z_position = hover_start_height + settings.hover_max_height_gain
		z_velocity = minf(z_velocity, 0.0)
		hover_active = false

	if z_position <= 0.0:
		land()


func is_airborne() -> bool:
	return not is_grounded()


func is_grounded() -> bool:
	return z_position <= 0.0 and z_velocity <= 0.0


func land() -> void:
	z_position = 0.0
	z_velocity = 0.0
	jumps_used = 0
	hover_timer = 0.0
	hover_active = false
	hover_used = false
	hover_start_height = 0.0


func _is_hovering() -> bool:
	return settings.hover_enabled and hover_active and hover_timer > 0.0


func _start_hover() -> void:
	hover_used = true
	hover_active = true
	hover_timer = settings.hover_duration
	hover_start_height = z_position
	z_velocity = settings.hover_jump_force


func _has_reached_hover_height_limit() -> bool:
	return z_position >= hover_start_height + settings.hover_max_height_gain
