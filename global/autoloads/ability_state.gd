# global/autoloads/ability_state.gd
extends Node

## Persists which ability is currently equipped.
## Set via: AbilityState.set_selected(&"shockwave")
## Read via: AbilityState.selected_id

const SAVE_PATH := "user://ability_state.cfg"
const SECTION := "ability"
const KEY := "selected"

## All valid ability IDs in display order.
## Note: "parry" is intentionally absent — it exists only as a ship module.
const ALL_IDS: Array[StringName] = [
	&"shockwave", &"overdrive", &"teleport",
	&"armor_plating", &"overheat_nullifier", &"final_resort",
	&"emp_blast", &"plasma_nova", &"shield_overload",
	&"shield_recharge", &"trajectory_calc",
]

signal ability_changed(id: StringName)

var selected_id: StringName = &"shockwave"

func _ready() -> void:
	_load()

func set_selected(id: StringName) -> void:
	if id not in ALL_IDS:
		push_warning("AbilityState: unknown id '%s'" % id)
		return
	selected_id = id
	_save()
	ability_changed.emit(id)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY, String(selected_id))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("AbilityState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err == ERR_FILE_NOT_FOUND:
		return
	if err != OK:
		push_warning("AbilityState: failed to load (%s)" % error_string(err))
		return
	var raw: String = cfg.get_value(SECTION, KEY, "shockwave")
	var id := StringName(raw)
	if id in ALL_IDS:
		selected_id = id
		ability_changed.emit(selected_id)
