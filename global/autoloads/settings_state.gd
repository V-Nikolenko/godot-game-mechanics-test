# global/autoloads/settings_state.gd
extends Node

## Persists player-chosen game settings. First key: which open-space steering scheme
## the player flies with (&"mouse" or &"keys").
##
## Deliberately NOT the ShipModuleState/UpgradeState "STARTING_IDS on an empty store"
## idiom — this is a per-boot guarantee (every boot must resolve to a valid scheme),
## not a fresh-profile declaration that only ever needs to fire once.
##
## Named SettingsState, not ControlsState, so a future setting (e.g. mouse
## sensitivity) lands as another key in this same store rather than a second autoload.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "controls"
const KEY_OPEN_SPACE_SCHEME := "open_space_scheme"

const SCHEMES: Array[StringName] = [&"mouse", &"keys"]
const DEFAULT_SCHEME: StringName = &"mouse"

signal open_space_scheme_changed(scheme: StringName)

var _open_space_scheme: StringName = DEFAULT_SCHEME

func _ready() -> void:
	_load()

func get_open_space_scheme() -> StringName:
	return _open_space_scheme

## Validates against SCHEMES, saves, and emits — but only on an actual change, so a
## redundant set neither writes to disk nor re-seeds a live ShipTurnController mid-flight.
func set_open_space_scheme(scheme: StringName) -> void:
	if scheme not in SCHEMES:
		push_warning("SettingsState: unknown open_space_scheme '%s'" % scheme)
		return
	if scheme == _open_space_scheme:
		return
	_open_space_scheme = scheme
	_save()
	open_space_scheme_changed.emit(_open_space_scheme)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_OPEN_SPACE_SCHEME, String(_open_space_scheme))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("SettingsState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		_open_space_scheme = DEFAULT_SCHEME
		return
	var raw: String = cfg.get_value(SECTION, KEY_OPEN_SPACE_SCHEME, String(DEFAULT_SCHEME))
	var scheme := StringName(raw)
	if scheme in SCHEMES:
		_open_space_scheme = scheme
	else:
		push_warning("SettingsState: unknown open_space_scheme '%s' on disk, using default" % raw)
		_open_space_scheme = DEFAULT_SCHEME
