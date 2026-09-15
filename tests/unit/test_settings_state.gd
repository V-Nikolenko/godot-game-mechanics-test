## Intent tests for SettingsState — the project's first settings autoload.
## Sandboxed (SaveSandbox), tree-less Script.new() instances per the house rule, so
## _ready()/_load() are called explicitly rather than relying on scene-tree timing.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const SettingsStateScript := preload("res://global/autoloads/settings_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func _fresh() -> Node:
	return SettingsStateScript.new()


func test_default_scheme_on_empty_disk() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	assert_eq(s.get_open_space_scheme(), &"mouse", "mouse aim is the stated default")
	s.free()


func test_set_scheme_round_trips_through_a_second_instance() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer._load()
	writer.set_open_space_scheme(&"keys")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_open_space_scheme(), &"keys")
	reader.free()


func test_load_falls_back_to_default_on_an_unknown_value() -> void:
	## BOUNDARY. push_warning is expected and not asserted on, matching
	## test_ship_module_state.gd::test_load_does_not_grandfather_an_unknown_equipped_id.
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(SettingsStateScript.SECTION, SettingsStateScript.KEY_OPEN_SPACE_SCHEME, "warp_drive")
	cfg.save(SettingsStateScript.SAVE_PATH)

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_open_space_scheme(), &"mouse", "an unknown value on disk falls back to default")
	reader.free()


func test_set_scheme_rejects_a_value_not_in_schemes() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	s.set_open_space_scheme(&"keys")
	s.set_open_space_scheme(&"gamepad")   ## push_warning, no state change
	assert_eq(s.get_open_space_scheme(), &"keys", "an invalid scheme is refused")
	s.free()


func test_setting_the_same_scheme_emits_nothing() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	var seen: Array = []
	s.open_space_scheme_changed.connect(func(scheme: StringName) -> void: seen.append(scheme))
	s.set_open_space_scheme(&"mouse")   ## already the default: no redundant save, no re-seed
	assert_eq(seen, [], "setting the current value emits nothing")
	s.free()


func test_scheme_changed_signal_carries_the_new_scheme() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	var seen: Array = []
	s.open_space_scheme_changed.connect(func(scheme: StringName) -> void: seen.append(scheme))
	s.set_open_space_scheme(&"keys")
	assert_eq(seen, [&"keys"])
	s.free()
