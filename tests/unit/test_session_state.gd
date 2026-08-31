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


func test_temp_health_stack_size_is_recovered_from_the_maximum() -> void:
	var s := _fresh()
	## maximum = TempHealth.MAX_STACKS * stack_hp, so stack_hp = maximum / 5.
	s._on_temp_health_changed(30, 50)
	assert_eq(s._temp_hp_current, 30)
	assert_eq(s._temp_hp_stack, 10)
	s.free()


func test_temp_health_stack_size_uses_integer_division() -> void:
	var s := _fresh()
	## CHARACTERIZED: `maximum / TempHealth.MAX_STACKS` is integer division, so a
	## maximum that is not a multiple of 5 rounds the stack size DOWN and the
	## reloaded pool is smaller than the one that was saved.
	s._on_temp_health_changed(9, 12)
	assert_eq(s._temp_hp_stack, 2, "12 / 5 truncates to 2, not 2.4")
	s.free()


func test_temp_health_zero_maximum_clears_the_stack_size() -> void:
	var s := _fresh()
	s._on_temp_health_changed(30, 50)
	s._on_temp_health_changed(0, 0)
	assert_eq(s._temp_hp_current, 0)
	assert_eq(s._temp_hp_stack, 0)
	s.free()


func test_buffs_survive_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer._on_shield_state_changed({"temp_count": 3})
	writer._on_temp_health_changed(20, 50)
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
