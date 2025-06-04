class_name DashState
extends State

const ROLL_RIGHT_ANIMATION_NAME : String = "roll_to_the_right"
const ROLL_LEFT_ANIMATION_NAME : String = "roll_to_the_left"

const STATE_KEY_BINDINGS: Array = [
	"move_left", 
	"move_right"
]

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var animated_sprite: AnimatedSprite2D
@export var movement_controller: MovementController

@export_category("State Configuration")
@export var dash_speed: float = 350.0
@export var move_speed: float = 180.0
@export var dash_cooldown_enabled: bool = true
@export var dash_cooldown_in_sec: float = 0.6

@export_category("Transition State")
@export var transition_state: State

@onready var cooldown_timer: Timer = $CooldownTimer
@onready var dashing_timer: Timer = $DashingTimer


# --- State Activation ---
func _ready() -> void:
        movement_controller.action_double_press.connect(start_state_transition)

var dashing_direction: Vector2
func start_state_transition(key_name: String) -> void:
        if !dashing_timer.is_stopped():
                return
        if dash_cooldown_enabled && !cooldown_timer.is_stopped():
		print("Dash in cooldown. Time to refresh: " + str(cooldown_timer.time_left) + "sec.")
		state_transition.emit(transition_state)
		return
	
	if STATE_KEY_BINDINGS.has(key_name):
		dashing_direction = get_dash_direction(key_name)
		state_transition.emit(self)

func get_dash_direction(key_name: String) -> Vector2:
	return Vector2.LEFT if key_name == "move_left" else Vector2.RIGHT


# --- Main State Logic ---
func enter() -> void:
        dashing_timer.start()
	
	if dashing_direction == Vector2.LEFT:
		animated_sprite.play(ROLL_LEFT_ANIMATION_NAME)
	elif dashing_direction == Vector2.RIGHT:
		animated_sprite.play(ROLL_RIGHT_ANIMATION_NAME)

func process_physics(delta: float):
        if !dashing_timer.is_stopped():
                var vertical_input := Input.get_axis("move_up", "move_down")
                var velocity := dashing_direction * dash_speed
                velocity.y = vertical_input * move_speed
                actor.velocity = velocity
                actor.move_and_slide()
	
	
# --- Timers Callback ---
func _on_dash_timer_timeout() -> void:
	state_transition.emit(transition_state)
	if (dash_cooldown_enabled):
		cooldown_timer.start(dash_cooldown_in_sec)
		print("Dash ended. Starting cooldown timer for " + str(cooldown_timer.wait_time) + " sec.")

func _on_cooldown_timer_timeout() -> void:
	print("Dash cooldown ended. Dash can be used again!")
