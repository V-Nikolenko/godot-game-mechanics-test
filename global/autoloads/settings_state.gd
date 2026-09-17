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

## Camera automatic-motion lives in its own section, not "controls" — it is an
## accessibility scale on the camera, not a steering choice.
const SECTION_CAMERA := "camera"
const KEY_CAMERA_MOTION := "camera_motion"

const SCHEMES: Array[StringName] = [&"mouse", &"keys"]
const DEFAULT_SCHEME: StringName = &"mouse"

## full = 1.0x lead/zoom, reduced = 0.5x, off = 0.0x. See OpenSpaceCameraRig._motion_scale.
const CAMERA_MOTION_VALUES: Array[StringName] = [&"full", &"reduced", &"off"]
const DEFAULT_CAMERA_MOTION: StringName = &"full"

signal open_space_scheme_changed(scheme: StringName)
signal camera_motion_changed(value: StringName)

var _open_space_scheme: StringName = DEFAULT_SCHEME
var _camera_motion: StringName = DEFAULT_CAMERA_MOTION

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

func get_camera_motion() -> StringName:
	return _camera_motion

## Validates against CAMERA_MOTION_VALUES, saves, and emits — same redundant-set guard as
## set_open_space_scheme, so a live OpenSpaceCameraRig is not re-seeded for nothing.
func set_camera_motion(value: StringName) -> void:
	if value not in CAMERA_MOTION_VALUES:
		push_warning("SettingsState: unknown camera_motion '%s'" % value)
		return
	if value == _camera_motion:
		return
	_camera_motion = value
	_save()
	camera_motion_changed.emit(_camera_motion)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_OPEN_SPACE_SCHEME, String(_open_space_scheme))
	cfg.set_value(SECTION_CAMERA, KEY_CAMERA_MOTION, String(_camera_motion))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("SettingsState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		_open_space_scheme = DEFAULT_SCHEME
		_camera_motion = DEFAULT_CAMERA_MOTION
		return

	var raw_scheme: String = cfg.get_value(SECTION, KEY_OPEN_SPACE_SCHEME, String(DEFAULT_SCHEME))
	var scheme := StringName(raw_scheme)
	if scheme in SCHEMES:
		_open_space_scheme = scheme
	else:
		push_warning("SettingsState: unknown open_space_scheme '%s' on disk, using default" % raw_scheme)
		_open_space_scheme = DEFAULT_SCHEME

	var raw_motion: String = cfg.get_value(SECTION_CAMERA, KEY_CAMERA_MOTION, String(DEFAULT_CAMERA_MOTION))
	var motion := StringName(raw_motion)
	if motion in CAMERA_MOTION_VALUES:
		_camera_motion = motion
	else:
		push_warning("SettingsState: unknown camera_motion '%s' on disk, using default" % raw_motion)
		_camera_motion = DEFAULT_CAMERA_MOTION
