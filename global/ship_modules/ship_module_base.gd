# global/ship_modules/ship_module_base.gd
class_name ShipModuleBase
extends RefCounted

## Abstract base for ship modules. Modules can be purely passive (Armor, Overclock)
## or have an H-key activation (Trajectory Calc). Warp uses double-press movement
## via DashState — it only needs apply/remove to set a flag.

## Override: human-readable name shown in module detail list.
func get_display_name() -> String:
	return "Module"

## Override: one-sentence description shown in module detail list.
func get_description() -> String:
	return ""

## Override: icon texture shown in item frame and detail list.
func get_icon() -> Texture2D:
	return null

## Override: slot this module belongs to (&"cockpit" / &"armor" / &"weapons" / &"engines").
func get_slot() -> StringName:
	return &""

## Override: apply passive effect to player. Called on equip.
func apply(_player: Node) -> void:
	pass

## Override: remove passive effect from player. Called on unequip or scene change.
func remove(_player: Node) -> void:
	pass

## Override in active modules: called when player presses H (use_ability).
## Return true if the module consumed the input (starts cooldown or effect).
## Passive modules leave this as false — H falls through to AbilityController.
func try_activate(_player: Node) -> bool:
	return false

## Override in active modules: called every physics frame by player_fighter
## for the currently equipped active module. Use for cooldown tracking and
## timed effect expiry. `delta` is real-time delta (Engine.time_scale already applied).
func tick(_player: Node, _delta: float) -> void:
	pass
