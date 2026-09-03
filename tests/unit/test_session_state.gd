## Characterization tests for SessionState — the cross-session store for
## *temporary* buffs (temp shield charges, temp HP pool, timed damage boost).
## The `apply_to(player)` path is covered by tests/integration/test_player_damage_chain.gd.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const SessionStateScript := preload("res://global/autoloads/session_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func _fresh() -> Node:
	return SessionStateScript.new()


func test_starts_with_no_buffs() -> void:
	var s := _fresh()
	assert_eq(s._temp_shield_count, 0)
	assert_eq(s._temp_hp_current, 0)
	assert_eq(s._temp_hp_stack, 0)
	assert_eq(s._dmg_bonus, 0.0)
	assert_eq(s._dmg_expiry_time, 0.0)
	s.free()


func test_save_and_clear_temp_damage_buff() -> void:
	var s := _fresh()
	s.save_temp_damage_buff(0.5, 1_700_000_000.0)
	assert_eq(s._dmg_bonus, 0.5)
	assert_eq(s._dmg_expiry_time, 1_700_000_000.0)
	s.clear_temp_damage_buff()
	assert_eq(s._dmg_bonus, 0.0)
	assert_eq(s._dmg_expiry_time, 0.0)
	s.free()


func test_shield_snapshot_records_only_the_temporary_count() -> void:
	var s := _fresh()
	## Permanent charges live in ShipProgressionState; SessionState deliberately
	## keeps only `temp_count` from the shield snapshot.
	s._on_shield_state_changed({"perm_active": 2, "perm_max": 3, "temp_count": 4, "hacked": false})
	assert_eq(s._temp_shield_count, 4)
	s.free()


func test_shield_snapshot_missing_key_falls_back_to_zero() -> void:
	var s := _fresh()
	s._on_shield_state_changed({"perm_active": 1})
	assert_eq(s._temp_shield_count, 0)
	s.free()


## The four tests below are INTENT, not characterization: the saved stack size is
## read straight off the TempHealth component instead of being re-derived from the
## emitted `maximum`. The old `maximum / TempHealth.MAX_STACKS` inverted an invariant
## (`max_temp == MAX_STACKS * stack_hp`) that TempHealth is under no obligation to
## keep, and truncated toward zero when it did not hold.
func test_temp_health_stack_size_is_read_from_the_component() -> void:
	var s := _fresh()
	var th := TempHealth.new()
	th.add_stack(21)                       ## stack_hp = 21 / 2 = 10
	s._on_temp_health_changed(th.current_temp, th.max_temp, th)
	assert_eq(s._temp_hp_current, 10)
	assert_eq(s._temp_hp_stack, 10)
	th.free()
	s.free()


func test_temp_health_stack_size_ignores_the_emitted_maximum() -> void:
	var s := _fresh()
	var th := TempHealth.new()
	th.add_stack(20)                       ## stack_hp = 10, max_temp = 50
	## A maximum that does not divide cleanly by MAX_STACKS used to truncate the
	## recovered stack size (12 / 5 -> 2), shrinking the pool the player gets back.
	## The component is now the source of truth, so a bogus maximum cannot do that.
	s._on_temp_health_changed(9, 12, th)
	assert_eq(s._temp_hp_current, 9)
	assert_eq(s._temp_hp_stack, 10, "stack_hp comes from the component, not 12 / 5")
	th.free()
	s.free()


func test_temp_health_stack_size_is_zero_before_any_stack() -> void:
	var s := _fresh()
	var th := TempHealth.new()
	s._on_temp_health_changed(0, 0, th)
	assert_eq(s._temp_hp_current, 0)
	assert_eq(s._temp_hp_stack, 0)
	th.free()
	s.free()


func test_temp_health_stack_size_survives_odd_base_health() -> void:
	## Through the real signal, for base healths whose half is not a round number:
	## the cap the player gets back must equal the cap they earned.
	for base_health: int in [1, 3, 7, 21, 33, 99, 101]:
		var s := _fresh()
		var th := TempHealth.new()
		th.amount_changed.connect(s._on_temp_health_changed.bind(th))
		th.add_stack(base_health)
		assert_eq(s._temp_hp_stack, th.stack_hp,
			"base_health %d: saved stack size must match the component" % base_health)
		assert_eq(TempHealth.MAX_STACKS * s._temp_hp_stack, th.max_temp,
			"base_health %d: the restored cap must match the earned cap" % base_health)
		th.free()
		s.free()


func test_buffs_survive_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer._on_shield_state_changed({"temp_count": 3})
	var th := TempHealth.new()
	th.add_stack(20)                       ## stack_hp = 10
	writer._on_temp_health_changed(20, th.max_temp, th)
	th.free()
	writer.save_temp_damage_buff(0.25, 1_900_000_000.0)
	writer.free()

	var reader := _fresh()
	reader._load()
	assert_eq(reader._temp_shield_count, 3)
	assert_eq(reader._temp_hp_current, 20)
	assert_eq(reader._temp_hp_stack, 10)
	assert_almost_eq(reader._dmg_bonus, 0.25, 0.0001)
	assert_almost_eq(reader._dmg_expiry_time, 1_900_000_000.0, 1.0)
	reader.free()
