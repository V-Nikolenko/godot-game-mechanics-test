extends CharacterBody2D

const PlayerInputFrame = preload("res://infiltration_mission/scripts/player/runtime/player_input_frame.gd")
const PlayerLocomotion = preload("res://infiltration_mission/scripts/player/runtime/player_locomotion.gd")
const PlayerDashState = preload("res://infiltration_mission/scripts/player/runtime/player_dash_state.gd")
const PlayerJumpState = preload("res://infiltration_mission/scripts/player/runtime/player_jump_state.gd")
const PlayerVisualController = preload("res://infiltration_mission/scripts/player/runtime/player_visual_controller.gd")
const PlayerMovementSettings = preload("res://infiltration_mission/scripts/player/config/player_movement_settings.gd")
const PlayerDashSettings = preload("res://infiltration_mission/scripts/player/config/player_dash_settings.gd")
const PlayerJumpSettings = preload("res://infiltration_mission/scripts/player/config/player_jump_settings.gd")
const PlayerUpgrade = preload("res://infiltration_mission/scripts/player/upgrades/player_upgrade.gd")
const PlayerUpgradeLoadout = preload("res://infiltration_mission/scripts/player/upgrades/player_upgrade_loadout.gd")

@export var movement_settings: PlayerMovementSettings = PlayerMovementSettings.new()
@export var dash_settings: PlayerDashSettings = PlayerDashSettings.new()
@export var jump_settings: PlayerJumpSettings = PlayerJumpSettings.new()
@export var upgrade_loadout: PlayerUpgradeLoadout = PlayerUpgradeLoadout.new()

# --- MOVEMENT MEMORY ---
var last_move_dir: Vector2 = Vector2.RIGHT
var environment_height: float = 0.0
var elevation_sources: Dictionary = {}

# --- REFERENCES ---
@onready var player_sprite = $Player
@onready var shadow = $player_shadow
@onready var dash_particles: GPUParticles2D = $DashParticles

var locomotion: PlayerLocomotion
var dash_state: PlayerDashState
var jump_state: PlayerJumpState
var visuals: PlayerVisualController


func _ready() -> void:
	refresh_modules()


func refresh_modules() -> void:
	if upgrade_loadout == null:
		upgrade_loadout = PlayerUpgradeLoadout.new()

	locomotion = PlayerLocomotion.new(movement_settings)
	dash_state = PlayerDashState.new(dash_settings)
	jump_state = PlayerJumpState.new(_build_jump_settings())
	visuals = PlayerVisualController.new(player_sprite, shadow, dash_particles)


func _physics_process(delta: float) -> void:
	var input := _read_input()
	_update_move_memory(input)

	dash_state.update(delta)
	if input.dash_pressed:
		dash_state.try_start(last_move_dir)

	jump_state.handle_input(input.jump_pressed)
	jump_state.update(delta, input.jump_held)

	if dash_state.is_active():
		velocity = locomotion.get_dash_velocity(dash_state.dash_direction, dash_settings.dash_speed)
	else:
		velocity = locomotion.get_move_velocity(input.move_vector)

	visuals.update_dash_particles(
		dash_state.is_active(),
		dash_state.dash_direction,
		jump_state.z_position
	)

	move_and_slide()
	visuals.apply_height(environment_height, jump_state.z_position)


func _read_input() -> PlayerInputFrame:
	var input := PlayerInputFrame.new()
	input.move_vector = Input.get_vector(
		"move_left", "move_right",
		"move_up", "move_down"
	)
	input.jump_pressed = Input.is_action_just_pressed("jump")
	input.jump_held = Input.is_action_pressed("jump")
	input.dash_pressed = Input.is_action_just_pressed("dash")
	return input


func _update_move_memory(input: PlayerInputFrame) -> void:
	if input.has_move_input():
		last_move_dir = input.move_vector


func apply_upgrade(upgrade: PlayerUpgrade) -> void:
	if upgrade == null:
		return

	if upgrade_loadout == null:
		upgrade_loadout = PlayerUpgradeLoadout.new()

	upgrade_loadout.equip_upgrade(upgrade)
	refresh_modules()


func clear_jump_upgrade() -> void:
	if upgrade_loadout == null:
		upgrade_loadout = PlayerUpgradeLoadout.new()

	upgrade_loadout.clear_jump_upgrade()
	refresh_modules()


func _build_jump_settings() -> PlayerJumpSettings:
	var resolved_settings := jump_settings.duplicate(true) as PlayerJumpSettings
	if upgrade_loadout == null:
		return resolved_settings

	var jump_upgrade = upgrade_loadout.get_jump_upgrade()
	if jump_upgrade != null:
		jump_upgrade.apply_to_jump_settings(resolved_settings)
	return resolved_settings


func set_environment_elevation(source: Node, height: float) -> void:
	if source == null:
		return

	elevation_sources[source.get_instance_id()] = maxf(height, 0.0)
	_recalculate_environment_height()


func clear_environment_elevation(source: Node) -> void:
	if source == null:
		return

	elevation_sources.erase(source.get_instance_id())
	_recalculate_environment_height()


func _recalculate_environment_height() -> void:
	environment_height = 0.0
	for height in elevation_sources.values():
		environment_height = maxf(environment_height, height)
