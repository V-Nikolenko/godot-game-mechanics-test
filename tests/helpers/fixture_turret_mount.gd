## A `TurretMount` subclass for `test_defense_turret.gd`'s hook row (task plan docs/plans/cmvqw0vnb017rqs2xsyursu5d/3-plan.md row 16): it
## counts `_weapon_tick` calls by the phase in force, answers `_telegraph_done()` from a flag the row sets, and reports FIRE done after
## `fire_ticks` calls. No weapon, no pools.
##
## No `class_name`: test-only. Preload it:
##     const FIXTURE_MOUNT := preload("res://tests/helpers/fixture_turret_mount.gd")
extends TurretMount

## `_weapon_tick` calls, keyed by the phase in force at the call.
var weapon_ticks: Dictionary = {}
var telegraph_ready: bool = false
var fire_ticks: int = 3


func _telegraph_seconds() -> float:
	return 0.05


func _telegraph_done() -> bool:
	return telegraph_ready


func _fire_tick(_delta: float, _can_fire: bool) -> bool:
	fire_ticks -= 1
	return fire_ticks <= 0


func _weapon_tick(_delta: float) -> void:
	weapon_ticks[_phase] = int(weapon_ticks.get(_phase, 0)) + 1
