# assault/scenes/gui/health_shield_bar.gd
class_name HealthShieldBar
extends Control

## Displays stacked health (red) and shield (cyan) bars.
## Call setup(health, shield) to connect to player components.
## Shield bar sits on top; health bar below.

@onready var _shield_bar: ProgressBar = $ShieldBar
@onready var _health_bar: ProgressBar = $HealthBar

func setup(health: Health, shield: Shield) -> void:
	_health_bar.max_value = health.max_health
	_health_bar.value     = health.current_health
	health.amount_changed.connect(_on_health_changed)

	_shield_bar.max_value = shield.max_shield
	_shield_bar.value     = shield.current_shield
	shield.shield_changed.connect(_on_shield_changed)

func _on_health_changed(current: int) -> void:
	_health_bar.value = current

func _on_shield_changed(current: int, _maximum: int) -> void:
	_shield_bar.value = current
