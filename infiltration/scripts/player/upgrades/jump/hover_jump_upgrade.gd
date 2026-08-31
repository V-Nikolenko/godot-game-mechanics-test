extends PlayerJumpUpgrade
class_name HoverJumpUpgrade

@export var hover_duration: float = 0.8
@export var hover_jump_force: float = 80.0
@export var hover_max_height_gain: float = 48.0
@export_range(0.05, 1.0, 0.05) var hover_gravity_scale: float = 0.15


func apply_to_jump_settings(settings: PlayerJumpSettings) -> void:
	settings.max_jumps = 1
	settings.hover_enabled = true
	settings.hover_duration = hover_duration
	settings.hover_jump_force = hover_jump_force
	settings.hover_max_height_gain = hover_max_height_gain
	settings.hover_gravity_scale = hover_gravity_scale
