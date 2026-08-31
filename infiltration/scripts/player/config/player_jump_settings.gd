extends Resource
class_name PlayerJumpSettings

@export var enabled: bool = true
@export var jump_force: float = 150.0
@export var air_jump_force: float = 150.0
@export var gravity: float = 600.0
@export_range(1, 4, 1) var max_jumps: int = 1

# Hover is optional and stays disabled by default.
@export var hover_enabled: bool = false
@export var hover_duration: float = 0.0
@export var hover_jump_force: float = 80.0
@export var hover_max_height_gain: float = 48.0
@export_range(0.05, 1.0, 0.05) var hover_gravity_scale: float = 0.35
