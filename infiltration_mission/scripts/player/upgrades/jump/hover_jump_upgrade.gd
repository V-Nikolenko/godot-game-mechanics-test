extends PlayerJumpUpgrade
class_name HoverJumpUpgrade

@export var hover_duration: float = 0.8
@export_range(0.05, 1.0, 0.05) var hover_gravity_scale: float = 0.15


func apply_to_jump_settings(settings: PlayerJumpSettings) -> void:
	settings.max_jumps = 1
	settings.hover_enabled = true
	settings.hover_duration = hover_duration
	settings.hover_gravity_scale = hover_gravity_scale
