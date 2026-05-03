class_name DashState
extends State

const ROLL_RIGHT_ANIMATION_NAME : String = "roll_to_the_right"
const ROLL_LEFT_ANIMATION_NAME : String = "roll_to_the_left"

const STATE_KEY_BINDINGS: Array = [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
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

var _scale_tween: Tween


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
	match key_name:
		"move_left":  return Vector2.LEFT
		"move_up":    return Vector2.UP
		"move_down":  return Vector2.DOWN
		_:            return Vector2.RIGHT


# --- Main State Logic ---
func enter() -> void:
	movement_controller.movement_lock.emit(dashing_timer.wait_time)
	dashing_timer.start()

	# Invincibility only for side barrel-rolls, not forward dash
	if dashing_direction.x != 0:
		var hb := actor.get_node_or_null("HurtBox") as Area2D
		if hb:
			hb.monitoring = false

	if dashing_direction == Vector2.LEFT:
		animated_sprite.play(ROLL_LEFT_ANIMATION_NAME)
	elif dashing_direction == Vector2.RIGHT:
		animated_sprite.play(ROLL_RIGHT_ANIMATION_NAME)
	# Forward / backward dash: no roll animation, keep current sprite

	# Scale pulse only for side barrel-rolls (forward/backward are subtle repositions)
	if _scale_tween:
		_scale_tween.kill()
	if dashing_direction.x != 0:
		var base: Vector2 = animated_sprite.scale
		var half: float   = dashing_timer.wait_time * 0.5
		_scale_tween = actor.create_tween()
		_scale_tween.tween_property(animated_sprite, "scale", base * 1.35, half) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_scale_tween.tween_property(animated_sprite, "scale", base, half) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func process_physics(delta: float):
	if !dashing_timer.is_stopped():
		var velocity := dashing_direction * dash_speed
		if dashing_direction.x != 0:
			# Side dash: allow vertical steering while rolling
			velocity.y = Input.get_axis("move_up", "move_down") * move_speed
		else:
			# Forward / backward dash: allow horizontal steering during the surge
			velocity.x = Input.get_axis("move_left", "move_right") * move_speed
		actor.velocity = velocity
		actor.move_and_slide()
	
	
# --- Timers Callback ---
func _on_dash_timer_timeout() -> void:
	# Restore HurtBox before transitioning so the new state is never left unprotected
	var hb := actor.get_node_or_null("HurtBox") as Area2D
	if hb:
		hb.monitoring = true

	state_transition.emit(transition_state)
	if (dash_cooldown_enabled):
		cooldown_timer.start(dash_cooldown_in_sec)

func _on_cooldown_timer_timeout() -> void:
	print("Dash cooldown ended. Dash can be used again!")
