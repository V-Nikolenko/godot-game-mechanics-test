extends RefCounted
class_name PlayerDashState

var settings: PlayerDashSettings
var dash_timer: float = 0.0
var cooldown_timer: float = 0.0
var effect_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT


func _init(dash_settings: PlayerDashSettings) -> void:
	settings = dash_settings


func update(delta: float) -> void:
	dash_timer = maxf(dash_timer - delta, 0.0)
	cooldown_timer = maxf(cooldown_timer - delta, 0.0)
	effect_timer = maxf(effect_timer - delta, 0.0)


func can_start() -> bool:
	return settings.enabled and cooldown_timer <= 0.0


func try_start(intent_dir: Vector2) -> bool:
	if not can_start():
		return false

	dash_direction = intent_dir.normalized()
	dash_timer = settings.dash_duration
	cooldown_timer = settings.dash_cooldown
	effect_timer = 0.0
	return true


func is_active() -> bool:
	return dash_timer > 0.0


func should_emit_dash_effect() -> bool:
	if not is_active():
		return false

	if effect_timer > 0.0:
		return false

	effect_timer = settings.afterimage_interval
	return true
