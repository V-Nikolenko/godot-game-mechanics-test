extends Node

## Tracks which persistent-id pickups have ever been collected, independent of any specific
## physical node — so a pickup placed in a mission that can be restarted (assault) doesn't
## re-grant itself just because the scene reloaded and respawned the node fresh. Opt-in via
## PickupBase.persistent_id; a pickup that leaves persistent_id empty (every pickup today)
## is untouched by this and keeps respawning every scene load, which is what health/shield/
## module pickups already want.

const SAVE_PATH := "user://pickup_state.cfg"
const SECTION := "collected"

var _collected: Dictionary = {}


func _ready() -> void:
	_load()


func has_collected(id: StringName) -> bool:
	return _collected.get(id, false)


func mark_collected(id: StringName) -> void:
	if _collected.get(id, false):
		return
	_collected[id] = true
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	for id: StringName in _collected:
		cfg.set_value(SECTION, String(id), true)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("PickupState: failed to save '%s' (error %d)" % [SAVE_PATH, err])


func _load() -> void:
	_collected.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section(SECTION):
		return
	for key: String in cfg.get_section_keys(SECTION):
		_collected[StringName(key)] = true
