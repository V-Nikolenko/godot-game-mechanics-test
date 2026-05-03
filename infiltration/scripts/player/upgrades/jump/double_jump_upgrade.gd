extends PlayerJumpUpgrade
class_name DoubleJumpUpgrade

@export_range(2, 4, 1) var jump_count: int = 2
@export var extra_jump_force: float = 150.0


func apply_to_jump_settings(settings: PlayerJumpSettings) -> void:
	settings.max_jumps = max(settings.max_jumps, jump_count)
	settings.air_jump_force = extra_jump_force
	settings.hover_enabled = false
	settings.hover_duration = 0.0
