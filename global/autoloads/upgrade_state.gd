# global/autoloads/upgrade_state.gd
extends Node

## Persistent unlock store for ship upgrades.
## Access anywhere: UpgradeState.unlock(&"gatling")
##                  UpgradeState.is_unlocked(&"reflect")
##                  UpgradeState.unlocked_ids()
##
## Ids are validated on the way in and on load — see ALL_IDS / ABILITY_IDS below.

const SAVE_PATH := "user://upgrades.cfg"
const SECTION := "upgrades"

## Weapon modes. Each id must have a matching `assault/scenes/player/weapons/modes/<id>.tres`;
## `unlocked_ids()` walks this list in order, and that is what drives the weapon cycle and the
## player menu's main-weapon column.
const ALL_IDS: Array[StringName] = [
	&"default", &"sniper_shot", &"spread", &"gatling", &"mining_laser"
]

## Non-weapon abilities that share this unlock store. They are deliberately absent from
## ALL_IDS — an ability listed by `unlocked_ids()` would appear in the weapon cycle as an
## unusable entry with no `modes/<id>.tres` behind it.
## &"reflect" is read by `assault/scenes/player/states/reflect_state.gd`. That script is
## currently orphaned — the `reflect` input action was replaced by `use_ability` and no scene
## instances it — but the id stays accepted here so reviving it needs no change to this file.
const ABILITY_IDS: Array[StringName] = [&"reflect"]

signal unlocked_changed(id: StringName)

var _unlocked: Dictionary = {}  # { StringName: bool }

func _ready() -> void:
	_load()
	if _unlocked.is_empty():
		_unlocked[&"default"] = true
		_save()

func is_unlocked(id: StringName) -> bool:
	return _unlocked.get(id, false)

## Every id `unlock()` accepts: a weapon mode or a standalone ability.
static func is_known_id(id: StringName) -> bool:
	return id in ALL_IDS or id in ABILITY_IDS

func unlock(id: StringName) -> void:
	if not is_known_id(id):
		push_warning("UpgradeState: unknown upgrade id '%s', ignoring" % id)
		return
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
		var id := StringName(key)
		if not is_known_id(id):
			## A renamed or removed upgrade left behind in an older profile. Dropping it here
			## keeps the store to ids the rest of the game can actually act on.
			push_warning("UpgradeState: unknown upgrade id '%s' in save file, ignoring" % key)
			continue
		_unlocked[id] = cfg.get_value(SECTION, key, false)
