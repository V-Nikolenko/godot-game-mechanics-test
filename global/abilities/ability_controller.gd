# global/abilities/ability_controller.gd
class_name AbilityController
extends Node

## Owns the currently-selected ability, handles H-key input,
## tracks cooldown, and exposes modifier properties for abilities to write.

@export var actor: CharacterBody2D
@export var health: Health
@export var shield: Shield        ## may be null in contexts without a shield
@export var overheat: Overheat    ## may be null in open-space

## Written by abilities (e.g. Overdrive writes 2.0, Final Resort writes 3.0).
## Read by WeaponState and player scripts when dealing/receiving damage.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
## True while Overdrive is active — tells player to skip heat capping.
var overdrive_active: bool = false

var cooldown_left: float = 0.0
var _ability: AbilityBase = null

## Maps ability id → instance. Built lazily on first selection.
var _pool: Dictionary = {}  # { StringName: AbilityBase }

func _ready() -> void:
	_swap_ability(AbilityState.selected_id)
	AbilityState.ability_changed.connect(_swap_ability)

func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = max(0.0, cooldown_left - delta)
	if _ability != null:
		_ability.tick(self, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_ability"):
		_try_activate()
		get_viewport().set_input_as_handled()

func _try_activate() -> void:
	if _ability == null:
		return
	if cooldown_left > 0.0:
		return
	var triggered: bool = _ability.activate(self)
	if triggered:
		cooldown_left = _ability.get_cooldown()

func _swap_ability(id: StringName) -> void:
	## Deactivate old ability.
	if _ability != null:
		_ability.deactivate(self)

	## Reset all modifiers to defaults when switching.
	damage_multiplier = 1.0
	fire_rate_multiplier = 1.0
	overdrive_active = false
	if actor:
		actor.set("damage_multiplier", 1.0)
		actor.set("fire_rate_multiplier", 1.0)
		actor.set("overdrive_active", false)

	## Get-or-create ability instance.
	if not _pool.has(id):
		var inst := _create_ability(id)
		if inst != null:
			_pool[id] = inst
			add_child(inst)

	_ability = _pool.get(id, null)
	cooldown_left = 0.0

func _create_ability(id: StringName) -> AbilityBase:
	match id:
		&"shockwave":       return preload("res://global/abilities/shockwave_ability.gd").new()
		&"overdrive":       return preload("res://global/abilities/overdrive_ability.gd").new()
		&"teleport":        return preload("res://global/abilities/teleport_ability.gd").new()
		&"armor_plating":   return preload("res://global/abilities/armor_plating_ability.gd").new()
		&"overheat_nullifier": return preload("res://global/abilities/overheat_nullifier_ability.gd").new()
		&"final_resort":    return preload("res://global/abilities/final_resort_ability.gd").new()
		&"emp_blast":       return preload("res://global/abilities/emp_blast_ability.gd").new()
		&"plasma_nova":     return preload("res://global/abilities/plasma_nova_ability.gd").new()
		&"shield_overload": return preload("res://global/abilities/shield_overload_ability.gd").new()
		&"shield_recharge": return preload("res://global/abilities/shield_recharge_ability.gd").new()
		&"trajectory_calc": return preload("res://global/abilities/trajectory_calc_ability.gd").new()
		_:
			push_warning("AbilityController: no class for id '%s'" % id)
			return null

## Convenience: current ability display name (for HUD).
func get_ability_name() -> String:
	return _ability.get_display_name() if _ability else "—"

## Convenience: current ability icon (for HUD).
func get_ability_icon() -> Texture2D:
	return _ability.get_icon() if _ability else null

## Convenience: cooldown fraction 0..1 (for HUD cooldown arc).
func get_cooldown_ratio() -> float:
	if _ability == null or _ability.get_cooldown() <= 0.0:
		return 0.0
	return cooldown_left / _ability.get_cooldown()
