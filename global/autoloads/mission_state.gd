# global/autoloads/mission_state.gd
extends Node

## Persistent mission progress singleton.
## Access anywhere: MissionState.complete("assault", 1)
##                  MissionState.is_complete("assault")
##                  MissionState.get_stars("assault")

const SAVE_PATH := "user://mission_state.cfg"

## Internal cache: { mission_id: { "completed": bool, "stars": int } }
var _data: Dictionary = {}

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

func _save() -> void:
	var cfg := ConfigFile.new()
	for mission_id: String in _data:
		var entry: Dictionary = _data[mission_id]
		cfg.set_value(mission_id, "completed", entry.get("completed", false))
		cfg.set_value(mission_id, "stars", entry.get("stars", 0))
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no save file yet — fresh start
	for mission_id: String in cfg.get_sections():
		_data[mission_id] = {
			"completed": cfg.get_value(mission_id, "completed", false),
			"stars": cfg.get_value(mission_id, "stars", 0),
		}
