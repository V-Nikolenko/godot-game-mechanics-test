extends RefCounted
class_name PlayerLocomotion

var settings: PlayerMovementSettings


func _init(movement_settings: PlayerMovementSettings) -> void:
	settings = movement_settings


func get_move_velocity(input_dir: Vector2) -> Vector2:
	if input_dir == Vector2.ZERO:
		return Vector2.ZERO
	return get_isometric_direction(input_dir) * settings.move_speed


func get_dash_velocity(intent_dir: Vector2, dash_speed: float) -> Vector2:
	return get_isometric_direction(intent_dir) * dash_speed


func get_isometric_direction(dir: Vector2) -> Vector2:
	var result := dir

	if dir.x != 0.0 and dir.y != 0.0:
		result.y *= settings.iso_diagonal_y_scale

	return result.normalized()
