# assault/scenes/gui/health_shield_bar.gd
class_name HealthShieldBar
extends Control

## Displays the player's health as a ProgressBar.
## Optionally shows a TempHealthBar overlay when temporary HP is present.

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _temp_bar: ProgressBar = $TempHealthBar


func setup(health: Health, temp_health: TempHealth = null) -> void:
	_health_bar.max_value = health.max_health
	_health_bar.value = health.current_health
	health.amount_changed.connect(_on_health_changed)

	if temp_health:
		_temp_bar.max_value = temp_health.max_temp if temp_health.max_temp > 0 else 1
		_temp_bar.value = temp_health.current_temp
		_temp_bar.visible = temp_health.current_temp > 0
		temp_health.amount_changed.connect(_on_temp_health_changed)


func _on_health_changed(current: int) -> void:
	_health_bar.value = current


func _on_temp_health_changed(current: int, maximum: int) -> void:
	_temp_bar.max_value = maximum if maximum > 0 else 1
	_temp_bar.value = current
	_temp_bar.visible = current > 0
