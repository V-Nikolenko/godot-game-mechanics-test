## SaveSandbox — protects the real `user://` save files from the test suite.
##
## Every persistent autoload (MissionState, UpgradeState, ShipProgressionState,
## ShipModuleState, SessionState) writes to a fixed `user://*.cfg` path, and the
## live autoload instances read those files at boot. A test that exercises a save
## path would therefore leak into the next run of the game AND into the next run
## of the suite.
##
## Usage in a GutTest:
##     const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
##     var _sandbox := SaveSandbox.new()
##     func before_all() -> void: _sandbox.capture()
##     func after_all() -> void:  _sandbox.restore()
extends RefCounted

const PATHS: Array[String] = [
	"user://mission_state.cfg",
	"user://upgrades.cfg",
	"user://ship_progression.cfg",
	"user://ship_modules.cfg",
	"user://session.cfg",
]

## path -> file contents, or `null` if the file did not exist when captured.
var _backup: Dictionary = {}

func capture() -> void:
	_backup.clear()
	for path in PATHS:
		if FileAccess.file_exists(path):
			_backup[path] = FileAccess.get_file_as_string(path)
		else:
			_backup[path] = null

func restore() -> void:
	for path: String in _backup:
		var content: Variant = _backup[path]
		if content == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(content)
			f.close()

## Delete every sandboxed save file, so an autoload instance that calls _load()
## starts from a known-empty disk.
func clear_all() -> void:
	for path in PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
