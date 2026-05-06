# global/components/shield_component.gd
class_name Shield
extends Node

## Shield absorbs damage before Health.
## Usage:
##   var overflow := shield.absorb(damage)   # returns leftover damage to Health
##   shield.increase(amount)                 # recharge
##   shield.set_shield(value)               # hard set

signal shield_changed(current: int, maximum: int)
signal shield_depleted
signal shield_restored   ## emitted when shield goes from 0 → any positive value

@export_category("Shield")
@export var max_shield: int = 100
@export var current_shield: int = 100

func _ready() -> void:
	current_shield = clampi(current_shield, 0, max_shield)

## Absorb `damage` points. Returns leftover damage that bypasses shield.
func absorb(damage: int) -> int:
	if damage <= 0:
		return 0
	if current_shield <= 0:
		return damage
	var absorbed: int = mini(damage, current_shield)
	var overflow: int = damage - absorbed
	current_shield -= absorbed
	shield_changed.emit(current_shield, max_shield)
	if current_shield == 0:
		shield_depleted.emit()
	return overflow

## Restore `amount` shield points, clamped to max_shield.
func increase(amount: int) -> void:
	if amount <= 0:
		return
	var was_empty := current_shield == 0
	current_shield = clampi(current_shield + amount, 0, max_shield)
	shield_changed.emit(current_shield, max_shield)
	if was_empty and current_shield > 0:
		shield_restored.emit()

## Hard-set shield to `value`.
func set_shield(value: int) -> void:
	var was_empty := current_shield == 0
	current_shield = clampi(value, 0, max_shield)
	shield_changed.emit(current_shield, max_shield)
	if was_empty and current_shield > 0:
		shield_restored.emit()
	elif current_shield == 0 and not was_empty:
		shield_depleted.emit()

func is_empty() -> bool:
	return current_shield <= 0
