class_name RocketState
extends State

signal weapon_changed(icon: Texture2D)

@export var actor: CharacterBody2D
@export var movement_controller: MovementController
@export var homing_count: int = 3  # upgradeable up to 8

var warhead_icon: Texture2D = preload("res://assault/assets/gui/weaponselector/icon_warhead_missiles.png")
var homing_icon: Texture2D  = preload("res://assault/assets/gui/weaponselector/icon_homing_missiles.png")

@onready var cooldown_timer: Timer = $CooldownTimer
@onready var warhead_scene: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
@onready var homing_scene:  PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")

var _type: int = 0  # 0 = warhead, 1 = homing

func _ready() -> void:
	movement_controller.action_single_press.connect(_on_action)

func get_current_icon() -> Texture2D:
	return warhead_icon if _type == 0 else homing_icon

## Public: return the current sub-weapon type (0=warhead, 1=homing).
func get_type() -> int:
	return _type

## Public: switch to sub-weapon type (0=warhead, 1=homing). Emits weapon_changed.
func select_sub_weapon(type: int) -> void:
	var clamped: int = clampi(type, 0, 1)
	if clamped == _type:
		return
	_type = clamped
	weapon_changed.emit(get_current_icon())

func _on_action(key_name: String) -> void:
	if key_name == "switch_weapon":
		_type = (_type + 1) % 2
		weapon_changed.emit(get_current_icon())
	elif key_name == "special_weapon" and cooldown_timer.is_stopped():
		_launch()
		cooldown_timer.start()

func _launch() -> void:
	if _type == 0:
		_launch_warhead()
	else:
		_launch_homing()

func _launch_warhead() -> void:
	for offset in [Vector2(-16, 26), Vector2(0, 36), Vector2(16, 26)]:
		var rocket: WarheadMissile = warhead_scene.instantiate()
		rocket.global_position = actor.global_position + offset.rotated(actor.rotation)
		rocket.rotation = actor.rotation
		add_child(rocket)

func _launch_homing() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	# Sort enemies by distance so closer ones get priority targets
	enemies.sort_custom(func(a: Node, b: Node) -> bool:
		return (a as Node2D).global_position.distance_to(actor.global_position) \
			 < (b as Node2D).global_position.distance_to(actor.global_position)
	)
	for i in homing_count:
		var rocket := homing_scene.instantiate() as homing_missile
		# Spread rockets sideways so they don't stack
		var spread: float = (i - (homing_count - 1) * 0.5) * 7.0
		rocket.global_position = actor.global_position + Vector2(spread, -15).rotated(actor.rotation)
		rocket.rotation = actor.rotation
		# Round-robin: if more rockets than enemies, revisit enemies from the start
		if enemies.size() > 0:
			rocket.locked_target = enemies[i % enemies.size()]
		add_child(rocket)

func _on_cooldown_timer_timeout() -> void:
	pass
