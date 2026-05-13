# global/autoloads/ship_module_state.gd
extends Node

## Persists which module is equipped in each ship slot.
## Slot IDs:  &"cockpit"  |  &"armor"  |  &"weapons"  |  &"engines"
## Module IDs per slot:
##   cockpit  → &"trajectory_calc"
##   armor    → &"armor_plating"
##   weapons  → &"overclock"
##   engines  → &"warp"
## Empty string means nothing equipped.

const SAVE_PATH := "user://ship_modules.cfg"
const SECTION := "modules"

const SLOTS: Array[StringName] = [&"cockpit", &"armor", &"weapons", &"engines"]

## Maps slot → list of available module IDs (in display order).
## First entry is always &"" (None / unequip).
const SLOT_MODULES: Dictionary = {
	&"cockpit":  [&"", &"trajectory_calc"],
	&"armor":    [&"", &"armor_plating"],
	&"weapons":  [&"", &"overclock"],
	&"engines":  [&"", &"warp"],
}

signal module_equipped(slot: StringName, module_id: StringName)
signal module_unequipped(slot: StringName, prev_id: StringName)

## slot → module_id (&"" = nothing equipped)
var _equipped: Dictionary = {
	&"cockpit":  &"",
	&"armor":    &"",
	&"weapons":  &"",
	&"engines":  &"",
}

func _ready() -> void:
	_load()

func get_equipped(slot: StringName) -> StringName:
	return _equipped.get(slot, &"")

func equip(slot: StringName, module_id: StringName) -> void:
	if slot not in SLOTS:
		push_warning("ShipModuleState: unknown slot '%s'" % slot)
		return
	var prev: StringName = _equipped.get(slot, &"")
	if prev == module_id:
		return
	if prev != &"":
		module_unequipped.emit(slot, prev)
	_equipped[slot] = module_id
	_save()
	module_equipped.emit(slot, module_id)

func _save() -> void:
	var cfg := ConfigFile.new()
	for slot: StringName in SLOTS:
		cfg.set_value(SECTION, String(slot), String(_equipped[slot]))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("ShipModuleState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for slot: StringName in SLOTS:
		var raw: String = cfg.get_value(SECTION, String(slot), "")
		_equipped[slot] = StringName(raw)
