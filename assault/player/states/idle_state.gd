class_name IdleState
extends State

const IDLE_ANIMATION_NAME : String = "idle"

@export var animated_sprite: AnimatedSprite2D

@export_category("Action Transitions")
@export var move_state: State

func enter():
	animated_sprite.play(IDLE_ANIMATION_NAME)
	pass

func process_physics(delta: float):
	var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	if (input_direction != Vector2.ZERO):
		state_transition.emit(self, move_state)
		
func exit() -> void:
	pass
