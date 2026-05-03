extends RefCounted
class_name PlayerInputFrame

var move_vector: Vector2 = Vector2.ZERO
var jump_pressed: bool = false
var jump_held: bool = false
var dash_pressed: bool = false


func has_move_input() -> bool:
	return move_vector != Vector2.ZERO


func movement_intent(fallback: Vector2) -> Vector2:
	if has_move_input():
		return move_vector
	return fallback
