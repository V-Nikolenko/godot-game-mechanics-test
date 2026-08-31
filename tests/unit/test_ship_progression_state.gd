## Characterization tests for ShipProgressionState (permanent shield slots).
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const ProgressionScript := preload("res://global/autoloads/ship_progression_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func _fresh() -> Node:
	return ProgressionScript.new()


func test_defaults_to_one_permanent_shield() -> void:
	var p := _fresh()
	assert_eq(p.permanent_shield_count, ProgressionScript.MIN_SHIELDS)
	assert_eq(ProgressionScript.MIN_SHIELDS, 1)
	assert_eq(ProgressionScript.MAX_SHIELDS, 5)
	p.free()


func test_set_count_emits_the_clamped_value() -> void:
	var p := _fresh()
	var seen: Array[int] = []
	p.permanent_shield_count_changed.connect(func(n: int) -> void: seen.append(n))
	p.set_permanent_shield_count(3)
	assert_eq(p.permanent_shield_count, 3)
	assert_eq(seen, [3] as Array[int])
	p.free()


func test_set_count_clamps_out_of_range_input() -> void:
	var p := _fresh()
	p.set_permanent_shield_count(99)
	assert_eq(p.permanent_shield_count, 5, "above the cap clamps to MAX_SHIELDS")
	p.set_permanent_shield_count(-4)
	assert_eq(p.permanent_shield_count, 1, "below the floor clamps to MIN_SHIELDS")
	p.free()


func test_setting_the_same_clamped_value_is_a_no_op() -> void:
	var p := _fresh()
	var emissions: Array[int] = []
	p.permanent_shield_count_changed.connect(func(n: int) -> void: emissions.append(n))
	## Starts at 1; 0 clamps to 1, which equals the current value.
	p.set_permanent_shield_count(0)
	assert_eq(emissions.size(), 0, "no signal when the clamped value did not change")
	p.free()


func test_add_permanent_shield_increments_until_the_cap() -> void:
	var p := _fresh()
	assert_true(p.add_permanent_shield(), "1 -> 2 succeeds")
	assert_eq(p.permanent_shield_count, 2)
	assert_true(p.add_permanent_shield())
	assert_true(p.add_permanent_shield())
	assert_true(p.add_permanent_shield())
	assert_eq(p.permanent_shield_count, 5, "reached MAX_SHIELDS")
	assert_false(p.add_permanent_shield(), "at the cap it reports failure")
	assert_eq(p.permanent_shield_count, 5)
	p.free()


func test_count_survives_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.set_permanent_shield_count(4)
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.permanent_shield_count, 4)
	reader.free()


func test_load_clamps_a_corrupt_saved_value() -> void:
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(ProgressionScript.SECTION, ProgressionScript.KEY_SHIELDS, 42)
	cfg.save(ProgressionScript.SAVE_PATH)

	var reader := _fresh()
	reader._load()                       ## also emits a push_warning, by design
	assert_eq(reader.permanent_shield_count, 5, "an out-of-range save is clamped, not trusted")
	reader.free()
