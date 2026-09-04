# global/autoloads/ship_module_state.gd
extends Node

## Persists which module is equipped in each ship slot.
## Slot IDs:  &"cockpit"  |  &"armor"  |  &"weapons"  |  &"engines"
## Module IDs per slot:
##   cockpit  → &"trajectory_calc"  |  &"emp_blast"  |  &"ai_targeting"  |  &"cockpit_heal"
##   armor    → &"armor_plating"  |  &"parry"  |  &"shield_overload"  |  &"final_resort"
##   weapons  → &"overclock"  |  &"plasma_nova"  |  &"overheat_nullifier"  |  &"pierce"  |  &"shooting"
##   engines  → &"warp"  |  &"engine_boost"
## Empty string means nothing equipped.

const SAVE_PATH := "user://ship_modules.cfg"
const SECTION := "modules"

const SLOTS: Array[StringName] = [&"cockpit", &"armor", &"weapons", &"engines"]

## Maps slot → list of available module IDs (in display order).
## First entry is always &"" (None / unequip).
const SLOT_MODULES: Dictionary = {
	&"cockpit":  [&"", &"trajectory_calc", &"emp_blast", &"ai_targeting", &"cockpit_heal"],
	&"armor":    [&"", &"armor_plating", &"parry", &"shield_overload", &"final_resort"],
	&"weapons":  [&"", &"overclock", &"plasma_nova", &"overheat_nullifier", &"pierce", &"shooting"],
	&"engines":  [&"", &"warp", &"engine_boost"],
}

signal module_equipped(slot: StringName, module_id: StringName)
signal module_unequipped(slot: StringName, prev_id: StringName)
signal module_unlocked(slot: StringName, module_id: StringName)

## slot → module_id (&"" = nothing equipped)
var _equipped: Dictionary = {
	&"cockpit":  &"",
	&"armor":    &"",
	&"weapons":  &"",
	&"engines":  &"",
}

## slot → Array[StringName] of unlocked module IDs. `equip()` refuses anything not in
## here; &"" (unequip) is exempt, so a slot can always be cleared. Unlockers are the
## ShipModuleUnlockerPickup instances in the world.
var _unlocked: Dictionary = {
	&"cockpit":  [] as Array[StringName],
	&"armor":    [] as Array[StringName],
	&"weapons":  [] as Array[StringName],
	&"engines":  [] as Array[StringName],
}

func _ready() -> void:
	_load()

func get_equipped(slot: StringName) -> StringName:
	return _equipped.get(slot, &"")

## Unlock a module so it appears in the ship menu without equipping it.
## Safe to call multiple times — duplicate unlocks are ignored.
func unlock(slot: StringName, module_id: StringName) -> void:
	if slot not in SLOTS:
		push_warning("ShipModuleState: unknown slot '%s'" % slot)
		return
	var valid_ids: Array = SLOT_MODULES.get(slot, [])
	if module_id not in valid_ids:
		push_warning("ShipModuleState: module_id '%s' is not valid for slot '%s'" % [module_id, slot])
		return
	var list: Array = _unlocked.get(slot, [])
	if module_id in list:
		return  ## already unlocked
	list.append(module_id)
	_save()
	module_unlocked.emit(slot, module_id)

func is_unlocked(slot: StringName, module_id: StringName) -> bool:
	var list: Array = _unlocked.get(slot, [])
	return module_id in list

func equip(slot: StringName, module_id: StringName) -> void:
	if slot not in SLOTS:
		push_warning("ShipModuleState: unknown slot '%s'" % slot)
		return
	var valid_ids: Array = SLOT_MODULES.get(slot, [])
	if module_id != &"" and module_id not in valid_ids:
		push_warning("ShipModuleState: module_id '%s' is not valid for slot '%s'" % [module_id, slot])
		return
	## &"" means "take the module out" and is always allowed — a gate that could trap a
	## module in a slot would be a worse bug than the one this check exists to fix.
	if module_id != &"" and not is_unlocked(slot, module_id):
		push_warning("ShipModuleState: module_id '%s' is not unlocked for slot '%s'" % [module_id, slot])
		return
	var prev: StringName = _equipped.get(slot, &"")
	if prev == module_id:
		return
	if prev != &"":
		module_unequipped.emit(slot, prev)
	_equipped[slot] = module_id
	_save()
	if module_id != &"":
		module_equipped.emit(slot, module_id)

func _save() -> void:
	var cfg := ConfigFile.new()
	for slot: StringName in SLOTS:
		cfg.set_value(SECTION, String(slot), String(_equipped[slot]))
		var names: Array[String] = []
		for id: StringName in _unlocked.get(slot, []):
			names.append(String(id))
		cfg.set_value(SECTION, String(slot) + "_unlocked", names)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("ShipModuleState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for slot: StringName in SLOTS:
		var raw: String = cfg.get_value(SECTION, String(slot), "")
		var id := StringName(raw)
		var valid: Array = SLOT_MODULES.get(slot, [])
		if id in valid:
			_equipped[slot] = id
		elif id != &"":
			push_warning("ShipModuleState: unknown module_id '%s' for slot '%s', ignoring" % [raw, slot])
		var raw_list: Array = cfg.get_value(SECTION, String(slot) + "_unlocked", [])
		var list: Array[StringName] = []
		for entry in raw_list:
			var entry_id := StringName(String(entry))
			if entry_id in valid:
				list.append(entry_id)
		## Grandfather a module that is equipped but not unlocked — that is every save
		## written before equipping required an unlock. Confiscating it would strip a
		## loadout the player is currently flying with. Both guards matter: &"" is in
		## `valid` for every slot (SLOT_MODULES lists it first), and re-loading an
		## already-migrated save must not append a second copy.
		var installed: StringName = _equipped.get(slot, &"")
		if installed != &"" and installed not in list:
			list.append(installed)
		_unlocked[slot] = list
