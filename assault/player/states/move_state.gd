extends State

const IDLE_ANIMATION_NAME : String = "idle"
const TILT_RIGHT_ANIMATION_NAME : String = "tilt_to_the_right"
const TILT_LEFT_ANIMATION_NAME : String = "tilt_to_the_left"

const STATE_KEY_BINDINGS: Array = [
	"move_left",
	"move_right",
	"move_up",
	"move_down"
]

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var animated_sprite: AnimatedSprite2D
@export var movement_controller: MovementController

@export_category("State Configuration")
@export var move_speed: float = 180.0
@export var max_move_speed: float = 200.0

@export_category("Transition State")
@export var transition_state: State


# --- State Activation ---
func _ready() -> void:
	movement_controller.action_single_press.connect(start_state_transition)

func start_state_transition(key_name: String) -> void:
	if STATE_KEY_BINDINGS.has(key_name):
		state_transition.emit(self)


# --- Main State Logic ---
func physics_process(delta: float) -> void:
	var input_direction:Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down").normalized()

	if check_transition_state():
		state_transition.emit(transition_state)

	move(input_direction)

func check_transition_state() -> bool:
	for movement_key in STATE_KEY_BINDINGS:
		if Input.is_action_pressed(movement_key):
			return false
	return true

func move(direction: Vector2) -> void:
	if direction.x == 0:
		animated_sprite.play(IDLE_ANIMATION_NAME)
	elif (direction.x > 0):
		animated_sprite.play(TILT_RIGHT_ANIMATION_NAME)
	else:
		animated_sprite.play(TILT_LEFT_ANIMATION_NAME)

	actor.velocity = direction * move_speed
	actor.move_and_slide()
