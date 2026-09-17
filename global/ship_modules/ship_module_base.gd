# global/ship_modules/ship_module_base.gd
class_name ShipModuleBase
extends RefCounted

## Abstract base for ship modules. Modules can be purely passive (Armor, Overclock)
## or have an H-key activation (Trajectory Calc). Warp uses double-press movement
## via DashState — it only needs apply/remove to set a flag.
##
## ADD NEW MODULES HERE when created — this is the single source of truth for
## instantiation. Player scripts and UI both call ShipModuleBase.create().
static func create(id: StringName) -> ShipModuleBase:
	match id:
		&"armor_plating":      return ArmorPlatingModule.new()
		&"parry":              return ParryModule.new()
		&"trajectory_calc":    return TrajectoryCalcModule.new()
		&"warp":               return WarpModule.new()
		&"overclock":          return OverclockModule.new()
		&"emp_blast":          return EMPBlastModule.new()
		&"shield_overload":    return ShieldOverloadModule.new()
		&"final_resort":       return FinalResortModule.new()
		&"plasma_nova":        return PlasmaNovaModule.new()
		&"overheat_nullifier": return OverheatNullifierModule.new()
		&"ai_targeting":       return AITargetingModule.new()
		&"cockpit_heal":       return CockpitHealModule.new()
		&"engine_boost":       return EngineBoostModule.new()
		&"pierce":             return PierceModule.new()
		&"shooting":           return ShootingModule.new()
	push_warning("ShipModuleBase.create: unknown module id '%s'" % id)
	return null

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
## Passive modules leave this as false — H input is consumed with no effect.
func try_activate(_player: Node) -> bool:
	return false

## Override in active modules: report whether the module is currently ready to fire
## (mirrors try_activate()'s own guard, and defaults false the same way). Callers that
## must check readiness WITHOUT spending a resource first (e.g. a boost tank) call this
## before try_activate() rather than paying for a call that would just refuse.
func can_activate() -> bool:
	return false

## Override true on a module that IS the open-space Shift boost's upgraded tier (currently
## only EngineBoostModule). OpenSpacePlayerShip._input skips such a module on H
## (use_ability) in open space, because Shift already spends the resource that pays for it
## there — leaving H wired would let the same burst fire for free. Assault has no Shift
## boost to conflict with, so its own H loop does not consult this at all.
func is_open_space_boost_verb() -> bool:
	return false

## Override in active modules: called every physics frame by player_fighter
## for the currently equipped active module. Use for cooldown tracking and
## timed effect expiry. `delta` is real-time delta (Engine.time_scale already applied).
func tick(_player: Node, _delta: float) -> void:
	pass
