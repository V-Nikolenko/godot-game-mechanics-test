class_name MoveState
extends State

const TILT_RIGHT_ANIMATION_NAME : String = "tilt_to_the_right"
const TILT_LEFT_ANIMATION_NAME : String = "tilt_to_the_left"

@export var actor: CharacterBody2D
@export var animated_sprite: AnimatedSprite2D

@export_category("Move State")
@export var move_speed: float = 150.0
@export var max_move_speed: float = 200.0

@export_category("Action Transitions")
@export var idle_state: State

func enter():
	pass

func process_physics(delta: float):
	pass
	#var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down").normalized()
	#
	#if (input_direction.x == 0):
		#state_transition.emit(self, idle_state)
		#
	#move(input_direction, delta)
	
func exit() -> void:
	pass

func move(direction: Vector2, delta: float) -> void:
	if direction.x != 0:
		if (direction.x > 0):
			animated_sprite.play(TILT_RIGHT_ANIMATION_NAME)
		else:
			animated_sprite.play(TILT_LEFT_ANIMATION_NAME)
	
	actor.velocity = direction * move_speed
	actor.move_and_slide()
	
