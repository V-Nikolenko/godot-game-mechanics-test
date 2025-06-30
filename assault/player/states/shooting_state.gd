class_name ShootingState
extends State

const STATE_KEY_BINDINGS: Array = [
	"shoot"
]

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var weapon_muzzles: Array[Marker2D]
@export var movement_controller: MovementController

@export_category("State Configuration")
@export var shooting_speed: float = 150.0

# --- State Activation ---
func _ready() -> void:
	movement_controller.action_single_press.connect(start_state_transition)

func start_state_transition(key_name: String) -> void:
	if STATE_KEY_BINDINGS.has(key_name):
		shootWithGuns()

var gun_fired:int = 0
func shootWithGuns():
	gun_fired = (gun_fired + 1) % weapon_muzzles.size()
	var muzzle: Marker2D = weapon_muzzles[gun_fired]
	
	var start_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	var target_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
	shoot(start_position, Vector2.ZERO)
	

@onready var bullet_scene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

func shoot(start_position: Vector2, target_position: Vector2) -> void:
	var bullet:Area2D = bullet_scene.instantiate()
	bullet.global_position = start_position
	bullet.rotation = actor.rotation
	add_child(bullet)
