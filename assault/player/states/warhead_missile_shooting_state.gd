class_name WarheadMissileShootingState
extends State

const STATE_KEY_BINDINGS: Array = [
	"special_weapon"
]

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var movement_controller: MovementController

@onready var cooldown_timer: Timer = $CooldownTimer

# --- State Activation ---
func _ready() -> void:
	movement_controller.action_single_press.connect(start_state_transition)

func start_state_transition(key_name: String) -> void:
	if STATE_KEY_BINDINGS.has(key_name) and cooldown_timer.is_stopped():
		launch_rocket()
		cooldown_timer.start()

@onready var rocket_scene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
func launch_rocket() -> void:
	var offsets = [Vector2(-10, 16), Vector2(0, 20), Vector2(10, 16)]
	for offset in offsets:
		var rocket: Area2D = rocket_scene.instantiate()
		rocket.global_position = actor.global_position + offset.rotated(actor.rotation)
		rocket.rotation = actor.rotation
		add_child(rocket)


func _on_cooldown_timer_timeout() -> void:
	print("Warhead Missiles cooldown is ended!")
