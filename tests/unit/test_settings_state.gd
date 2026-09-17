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


func test_default_camera_motion_on_empty_disk() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	assert_eq(s.get_camera_motion(), &"full", "full is the stated default")
	s.free()


func test_camera_motion_round_trips_without_clobbering_the_scheme() -> void:
	## BOUNDARY (review N3): _save() must write BOTH keys. This fails on the obvious
	## one-key-at-a-time implementation, which would clobber whichever key was written last.
	_sandbox.clear_all()
	var writer := _fresh()
	writer._load()
	writer.set_open_space_scheme(&"keys")
	writer.set_camera_motion(&"reduced")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_open_space_scheme(), &"keys", "camera_motion must not clobber the scheme")
	assert_eq(reader.get_camera_motion(), &"reduced")
	reader.free()


func test_scheme_round_trips_without_clobbering_camera_motion() -> void:
	## BOUNDARY, the other direction: setting the scheme after camera_motion must also
	## preserve both keys.
	_sandbox.clear_all()
	var writer := _fresh()
	writer._load()
	writer.set_camera_motion(&"off")
	writer.set_open_space_scheme(&"keys")
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_camera_motion(), &"off", "the scheme write must not clobber camera_motion")
	assert_eq(reader.get_open_space_scheme(), &"keys")
	reader.free()


func test_camera_motion_load_falls_back_to_default_on_an_unknown_value() -> void:
	## BOUNDARY. push_warning is expected and not asserted on, matching the scheme's own case.
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(SettingsStateScript.SECTION_CAMERA, SettingsStateScript.KEY_CAMERA_MOTION, "turbo")
	cfg.save(SettingsStateScript.SAVE_PATH)

	var reader := _fresh()
	reader._load()
	assert_eq(reader.get_camera_motion(), &"full", "an unknown value on disk falls back to full")
	reader.free()


func test_camera_motion_rejects_a_value_not_in_the_list() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	s.set_camera_motion(&"reduced")
	s.set_camera_motion(&"ludicrous")   ## push_warning, no state change
	assert_eq(s.get_camera_motion(), &"reduced", "an invalid value is refused")
	s.free()


func test_setting_the_same_camera_motion_emits_nothing() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	var seen: Array = []
	s.camera_motion_changed.connect(func(value: StringName) -> void: seen.append(value))
	s.set_camera_motion(&"full")   ## already the default: no redundant save, no re-seed
	assert_eq(seen, [], "setting the current value emits nothing")
	s.free()


func test_camera_motion_changed_signal_carries_the_new_value() -> void:
	_sandbox.clear_all()
	var s := _fresh()
	s._load()
	var seen: Array = []
	s.camera_motion_changed.connect(func(value: StringName) -> void: seen.append(value))
	s.set_camera_motion(&"off")
	assert_eq(seen, [&"off"])
	s.free()
