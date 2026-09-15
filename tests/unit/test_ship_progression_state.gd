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


## ── Boost charge capacity — a second key on the same ConfigFile, mirroring the shield stat
## line for line (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/
## 3-plan.md` → Design → "Persistence and the upgrade"). Tree-less `_fresh()`, same as the
## shield cases above — this file never touches the live autoload (`tests/README.md`'s house
## rule); see `test_open_space_boost_wiring.gd` / `test_boost_bar.gd` / `test_boost_upgrade_source.gd`
## for the live-singleton discipline that applies where a scene or a pickup is involved instead.
func test_defaults_to_min_boost_charges() -> void:
	var p := _fresh()
	assert_eq(p.boost_charge_count, ProgressionScript.MIN_BOOST_CHARGES)
	assert_eq(ProgressionScript.MIN_BOOST_CHARGES, 2)
	assert_eq(ProgressionScript.MAX_BOOST_CHARGES, 5)
	p.free()


func test_add_boost_charge_increments_and_emits() -> void:
	var p := _fresh()
	var seen: Array[int] = []
	p.boost_charge_count_changed.connect(func(n: int) -> void: seen.append(n))
	assert_true(p.add_boost_charge(), "2 -> 3 succeeds")
	assert_eq(p.boost_charge_count, 3)
	assert_eq(seen, [3] as Array[int])
	p.free()


## Boundary: the cap refuses and announces nothing.
func test_add_boost_charge_refuses_at_the_cap() -> void:
	var p := _fresh()
	assert_true(p.add_boost_charge())  ## 2 -> 3
	assert_true(p.add_boost_charge())  ## 3 -> 4
	assert_true(p.add_boost_charge())  ## 4 -> 5 == MAX_BOOST_CHARGES
	assert_eq(p.boost_charge_count, 5)
	var seen: Array[int] = []
	p.boost_charge_count_changed.connect(func(n: int) -> void: seen.append(n))
	assert_false(p.add_boost_charge(), "at the cap it reports failure")
	assert_eq(p.boost_charge_count, 5, "unchanged at the cap")
	assert_eq(seen.size(), 0, "no signal when nothing changed")
	p.free()


## Boundary: a corrupt saved value clamps on load, like the shield key.
func test_load_clamps_a_corrupt_saved_boost_value() -> void:
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(ProgressionScript.SECTION, ProgressionScript.KEY_BOOST, 99)
	cfg.save(ProgressionScript.SAVE_PATH)

	var reader := _fresh()
	reader._load()                       ## also emits a push_warning, by design
	assert_eq(reader.boost_charge_count, 5, "an out-of-range save is clamped, not trusted")
	reader.free()


## Boundary: the two stats share one ConfigFile but clamp and store independently.
func test_boost_and_shield_keys_are_independent_on_the_shared_config() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.set_permanent_shield_count(4)
	writer.add_boost_charge()            ## 2 -> 3
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader.boost_charge_count, 3, "the boost key survives a round trip")
	assert_eq(reader.permanent_shield_count, 4,
			"raising the boost count must not disturb the shield count on the shared file")
	reader.free()
