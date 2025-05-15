class_name IdleState
extends State

const IDLE_ANIMATION_NAME : String = "idle"

@export_category("State Dependencies")
@export var animated_sprite: AnimatedSprite2D

# --- Main State Logic ---
func enter():
	animated_sprite.play(IDLE_ANIMATION_NAME)
