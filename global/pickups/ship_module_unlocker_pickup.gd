# global/pickups/ship_module_unlocker_pickup.gd
class_name ShipModuleUnlockerPickup
extends PickupBase

## Inspector-selectable enums — no raw string typing required.
enum Slot { COCKPIT, ARMOR, WEAPONS, ENGINES }
enum Module {
	## cockpit
	TRAJECTORY_CALC, EMP_BLAST, AI_TARGETING, COCKPIT_HEAL,
	## armor
	ARMOR_PLATING, PARRY, SHIELD_OVERLOAD, FINAL_RESORT,
	## weapons
	OVERCLOCK, PLASMA_NOVA, OVERHEAT_NULLIFIER, PIERCE, SHOOTING,
	## engines
	WARP, ENGINE_BOOST,
}

@export var module_slot: Slot = Slot.COCKPIT
@export var module_id: Module = Module.TRAJECTORY_CALC


func _collect(_player: PlayerBase) -> void:
	ShipModuleState.unlock(_slot_name(), _module_name())


func _get_dialog_text() -> String:
	var id := _module_name()
	var module := ShipModuleBase.create(id)
	if module == null:
		return "Module acquired!"
	return "%s module acquired!" % module.get_display_name()


func _slot_name() -> StringName:
	match module_slot:
		Slot.COCKPIT:  return &"cockpit"
		Slot.ARMOR:    return &"armor"
		Slot.WEAPONS:  return &"weapons"
		Slot.ENGINES:  return &"engines"
	return &""


func _module_name() -> StringName:
	match module_id:
		Module.TRAJECTORY_CALC:    return &"trajectory_calc"
		Module.EMP_BLAST:          return &"emp_blast"
		Module.AI_TARGETING:       return &"ai_targeting"
		Module.COCKPIT_HEAL:       return &"cockpit_heal"
		Module.ARMOR_PLATING:      return &"armor_plating"
		Module.PARRY:              return &"parry"
		Module.SHIELD_OVERLOAD:    return &"shield_overload"
		Module.FINAL_RESORT:       return &"final_resort"
		Module.OVERCLOCK:          return &"overclock"
		Module.PLASMA_NOVA:        return &"plasma_nova"
		Module.OVERHEAT_NULLIFIER: return &"overheat_nullifier"
		Module.PIERCE:             return &"pierce"
		Module.SHOOTING:           return &"shooting"
		Module.WARP:               return &"warp"
		Module.ENGINE_BOOST:       return &"engine_boost"
	return &""
