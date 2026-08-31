class_name Overheat
extends Node

signal overheat(overheat_percentage: float)

@export_category("Overheat Configuration")
@export var heat_limit: float = 20.0
@export var cooldown_time: float = 10.0

var heat: float = 0.0

## Seconds remaining in the shoot-grace window.
## Reset to _SHOOT_GRACE on every increase_heat() call.
## While > 0 the player is still in an active shooting window and heat must not dissipate.
## Must exceed the longest weapon fire_interval in the game (long_range = 0.45 s).
var _no_shoot_timer: float = 0.0
const _SHOOT_GRACE: float = 0.5

func increase_heat(heat_amount: float) -> void:
	heat = min(heat + heat_amount, heat_limit)
	_no_shoot_timer = _SHOOT_GRACE
	_emit_heat()

func _physics_process(delta: float) -> void:
	if _no_shoot_timer > 0.0:
		_no_shoot_timer = max(_no_shoot_timer - delta, 0.0)
		return
	if heat > 0.0:
		var dissipation_rate: float = heat_limit / cooldown_time
		heat = max(heat - dissipation_rate * delta, 0.0)
		_emit_heat()

func _emit_heat() -> void:
	var overheat_percentage: float = heat / heat_limit * 100.0
	overheat.emit(overheat_percentage)
