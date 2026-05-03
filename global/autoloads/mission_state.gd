# global/autoloads/mission_state.gd
extends Node

## Persistent mission progress singleton.
## Access anywhere: MissionState.complete("assault", 1)
##                  MissionState.is_complete("assault")
##                  MissionState.get_stars("assault")

const SAVE_PATH := "user://mission_state.cfg"

## Reserved ConfigFile section name for cutscene flags. The double-underscore
## prefix is namespaced to never collide with a mission id.
const _CUTSCENE_SECTION := "__cutscenes__"

## Internal cache: { mission_id: { "completed": bool, "stars": int } }
var _data: Dictionary = {}

## Internal cache of cutscene flags: { cutscene_id: bool }
var _cutscenes: Dictionary = {}

func _ready() -> void:
	_load()

## Mark a mission as complete and record its star count (1–3).
## If the mission was already complete with MORE stars, keeps the higher count.
func complete(mission_id: String, stars: int = 1) -> void:
	var entry: Dictionary = _data.get(mission_id, {})
	entry["completed"] = true
	entry["stars"] = max(entry.get("stars", 0), clampi(stars, 1, 3))
	_data[mission_id] = entry
	_save()

## Returns true if the mission has been beaten at least once.
func is_complete(mission_id: String) -> bool:
	return _data.get(mission_id, {}).get("completed", false)

## Returns 0 if the mission has never been completed.
func get_stars(mission_id: String) -> int:
	return _data.get(mission_id, {}).get("stars", 0)

## Mark a cutscene as having been viewed at least once. Persists to disk.
func mark_cutscene_seen(cutscene_id: String) -> void:
	_cutscenes[cutscene_id] = true
	_save()

## True if `mark_cutscene_seen(cutscene_id)` was ever called (in this run or
## any previous run).
func has_cutscene_been_seen(cutscene_id: String) -> bool:
	return _cutscenes.get(cutscene_id, false)

func _save() -> void:
	var cfg := ConfigFile.new()
	for mission_id: String in _data:
		var entry: Dictionary = _data[mission_id]
		cfg.set_value(mission_id, "completed", entry.get("completed", false))
		cfg.set_value(mission_id, "stars", entry.get("stars", 0))
	for cutscene_id: String in _cutscenes:
		cfg.set_value(_CUTSCENE_SECTION, cutscene_id, _cutscenes[cutscene_id])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("MissionState: failed to save '%s' (error %d)" % [SAVE_PATH, err])

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no save file yet — fresh start
	for section: String in cfg.get_sections():
		if section == _CUTSCENE_SECTION:
			for key: String in cfg.get_section_keys(section):
				_cutscenes[key] = cfg.get_value(section, key, false)
		else:
			_data[section] = {
				"completed": cfg.get_value(section, "completed", false),
				"stars": cfg.get_value(section, "stars", 0),
			}
