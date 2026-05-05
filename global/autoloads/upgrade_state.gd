# global/autoloads/upgrade_state.gd
extends Node

## Persistent unlock store for ship upgrades.
## Access anywhere: UpgradeState.unlock(&"piercing")
##                  UpgradeState.is_unlocked(&"reflect")
##                  UpgradeState.unlocked_ids()

const SAVE_PATH := "user://upgrades.cfg"
const SECTION := "upgrades"

const ALL_IDS: Array[StringName] = [
	&"default", &"long_range", &"piercing", &"spread", &"auto_aim", &"reflect"
]

signal unlocked_changed(id: StringName)

var _unlocked: Dictionary = {}  # { StringName: bool }

func _ready() -> void:
	_load()
	if _unlocked.is_empty():
		_unlocked[&"default"] = true
		_save()

func is_unlocked(id: StringName) -> bool:
	return _unlocked.get(id, false)

func unlock(id: StringName) -> void:
	if _unlocked.get(id, false):
		return
	_unlocked[id] = true
	_save()
	unlocked_changed.emit(id)

func unlocked_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ALL_IDS:
		if _unlocked.get(id, false):
			out.append(id)
	return out

func unlock_all() -> void:
	for id in ALL_IDS:
		unlock(id)

func _save() -> void:
	var cfg := ConfigFile.new()
	for id: StringName in _unlocked.keys():
		cfg.set_value(SECTION, String(id), _unlocked[id])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("UpgradeState: failed to save '%s' (error %d)" % [SAVE_PATH, err])

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section(SECTION):
		return
	for key: String in cfg.get_section_keys(SECTION):
		_unlocked[StringName(key)] = cfg.get_value(SECTION, key, false)
