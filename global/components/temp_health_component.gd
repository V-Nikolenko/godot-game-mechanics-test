# global/components/temp_health_component.gd
class_name TempHealth
extends Node

## Temporary HP pool. Sits between shield and regular health in the damage chain.
## Each "stack" adds base_health/2 HP, capped at MAX_STACKS stacks.
## Drains before regular health. Not regenerated.

const MAX_STACKS: int = 5

signal amount_changed(current: int, maximum: int)

var current_temp: int = 0
var _stack_hp: int = 0        ## value of one stack; set on first add_stack call

## Computed cap for external readers (HUD).
var max_temp: int:
	get: return MAX_STACKS * _stack_hp if _stack_hp > 0 else 0


## Add one temp stack of +base_health/2 HP. Returns false if already at cap.
## _stack_hp is locked to the value set on first call; subsequent calls with
## a different base_health still use the original stack size.
func add_stack(base_health: int) -> bool:
	if _stack_hp == 0:
		_stack_hp = maxi(1, base_health / 2)
	var cap: int = MAX_STACKS * _stack_hp
	if current_temp >= cap:
		return false
	current_temp = mini(current_temp + _stack_hp, cap)
	amount_changed.emit(current_temp, cap)
	return true


## Restore from saved state (called by SessionState on level/game load).
## Safe to call before add_stack — sets _stack_hp if not yet initialised.
func restore(current: int, stack_hp: int) -> void:
	if stack_hp <= 0 or current <= 0:
		return
	if _stack_hp == 0:
		_stack_hp = stack_hp
	current_temp = clampi(current, 0, MAX_STACKS * _stack_hp)
	amount_changed.emit(current_temp, max_temp)


## Drains current_temp by amount. Returns overflow (damage that passes through to health).
func take_damage(amount: int) -> int:
	if current_temp <= 0:
		return amount
	var absorbed: int = mini(amount, current_temp)
	current_temp -= absorbed
	amount_changed.emit(current_temp, max_temp)
	return amount - absorbed
