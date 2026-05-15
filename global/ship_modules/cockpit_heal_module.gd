# global/ship_modules/cockpit_heal_module.gd
class_name CockpitHealModule
extends ShipModuleBase

## HP restored by the active (H) ability.
const _INSTANT_HEAL: int = 25
## After using H, passive regen is locked for this many seconds.
const _PASSIVE_LOCKOUT: float = 40.0
## Passive regen rate in HP per second (applied while stationary).
const _REGEN_RATE: float = 5.0
## Player must be below this speed (px/s) to count as "stationary".
const _VELOCITY_THRESHOLD: float = 15.0
## How long the player must remain still before regen starts ticking.
const _STILL_DELAY: float = 1.5

var _passive_lockout: float = 0.0   ## > 0 means passive is disabled.
var _still_timer: float = 0.0       ## How long the player has been stationary.
var _regen_accum: float = 0.0       ## Fractional HP accumulator.

func get_display_name() -> String: return "Repair System"
func get_description() -> String:
	return "Passive: while stationary for 1.5 seconds, hull regenerates 5 HP/sec. Active (H): instantly restores 25 HP, but disables passive regen for 40 seconds."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_heal.png")
func get_slot() -> StringName: return &"cockpit"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	_passive_lockout = 0.0
	_still_timer = 0.0
	_regen_accum = 0.0

func try_activate(player: Node) -> bool:
	var health: Health = player.get("health_component") as Health
	if health == null:
		return false
	_passive_lockout = _PASSIVE_LOCKOUT
	_still_timer = 0.0
	_regen_accum = 0.0
	health.increase(_INSTANT_HEAL)
	return true

func tick(player: Node, delta: float) -> void:
	## Count down the lockout started by H.
	if _passive_lockout > 0.0:
		_passive_lockout -= delta
		_still_timer = 0.0
		_regen_accum = 0.0
		return

	## Check if the player is stationary.
	var vel: Variant = player.get("velocity")
	var speed: float = (vel as Vector2).length() if vel is Vector2 else 0.0

	if speed < _VELOCITY_THRESHOLD:
		_still_timer += delta
	else:
		_still_timer = 0.0
		_regen_accum = 0.0
		return

	## Only regen after the delay.
	if _still_timer < _STILL_DELAY:
		return

	var health: Health = player.get("health_component") as Health
	if health == null or health.current_health >= health.max_health:
		_regen_accum = 0.0
		return

	_regen_accum += _REGEN_RATE * delta
	if _regen_accum >= 1.0:
		var heal: int = int(_regen_accum)
		_regen_accum -= heal
		health.increase(heal)
