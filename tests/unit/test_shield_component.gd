## Characterization tests for the Shield component (discrete-charge shield).
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

var _sandbox := SaveSandbox.new()
var _saved_permanent_count: int


func before_all() -> void:
	_sandbox.capture()
	_saved_permanent_count = ShipProgressionState.permanent_shield_count


func after_all() -> void:
	ShipProgressionState.set_permanent_shield_count(_saved_permanent_count)
	_sandbox.restore()


## Shield needs to be in the tree: _ready() builds the regen Timer and seeds the
## permanent charges.
func _make(permanent: int, max_temp: int = 5) -> Shield:
	var s := Shield.new()
	s.bind_progression = false
	s.permanent_charges = permanent
	s.max_temporary = max_temp
	add_child_autofree(s)
	return s


func test_ready_fills_the_permanent_charges() -> void:
	var s := _make(3)
	assert_eq(s.permanent_max, 3)
	assert_eq(s.permanent_active, 3, "a ship spawns with a full permanent shield")
	assert_eq(s.temporary_count, 0)
	assert_false(s.is_hacked)


func test_ready_emits_the_opening_snapshot() -> void:
	var s := Shield.new()
	s.bind_progression = false
	s.permanent_charges = 2
	var snaps: Array = []
	s.shield_state_changed.connect(func(snap: Dictionary) -> void: snaps.append(snap))
	add_child_autofree(s)
	assert_eq(snaps.size(), 1, "the UI gets a snapshot as soon as the shield is ready")
	assert_eq(snaps[0], {"perm_active": 2, "perm_max": 2, "temp_count": 0, "hacked": false})


func test_each_charge_absorbs_exactly_one_hit() -> void:
	var s := _make(2)
	assert_true(s.consume_one())
	assert_eq(s.permanent_active, 1)
	assert_true(s.consume_one())
	assert_eq(s.permanent_active, 0)
	assert_false(s.consume_one(), "an empty shield absorbs nothing")


func test_temporary_charges_are_spent_before_permanent_ones() -> void:
	var s := _make(2)
	assert_true(s.add_temporary())
	assert_true(s.add_temporary())
	assert_eq(s.temporary_count, 2)

	s.consume_one()
	assert_eq(s.temporary_count, 1)
	assert_eq(s.permanent_active, 2, "permanent charges are untouched while temps remain")
	s.consume_one()
	assert_eq(s.temporary_count, 0)
	assert_eq(s.permanent_active, 2)
	s.consume_one()
	assert_eq(s.permanent_active, 1, "only now does a permanent charge go")


func test_temporary_stack_is_capped() -> void:
	var s := _make(1, 2)
	var pickups: Array[bool] = []
	s.shield_pickup_collected.connect(func() -> void: pickups.append(true))
	assert_true(s.add_temporary())
	assert_true(s.add_temporary())
	assert_false(s.add_temporary(), "the third exceeds max_temporary")
	assert_eq(s.temporary_count, 2)
	assert_eq(pickups.size(), 1, "a wasted pickup still notifies the visuals")


func test_restore_all_permanent_refills_and_signals_when_already_full() -> void:
	var s := _make(3)
	s.consume_one()
	s.consume_one()
	assert_eq(s.permanent_active, 1)
	s.restore_all_permanent()
	assert_eq(s.permanent_active, 3)

	var pickups: Array[bool] = []
	s.shield_pickup_collected.connect(func() -> void: pickups.append(true))
	s.restore_all_permanent()
	assert_eq(s.permanent_active, 3)
	assert_eq(pickups.size(), 1, "a redundant refill still notifies the visuals")


func test_restore_all_permanent_does_not_touch_temporary_charges() -> void:
	var s := _make(2)
	s.add_temporary()
	s.consume_one()                      ## eats the temp charge
	s.consume_one()                      ## eats a permanent charge
	assert_eq(s.temporary_count, 0)
	assert_eq(s.permanent_active, 1)
	s.restore_all_permanent()
	assert_eq(s.permanent_active, 2)
	assert_eq(s.temporary_count, 0, "temporary charges are never refilled")


func test_set_all_zero_drains_everything() -> void:
	var s := _make(2)
	s.add_temporary()
	s.set_all_zero()
	assert_eq(s.permanent_active, 0)
	assert_eq(s.temporary_count, 0)
	assert_false(s.consume_one())


func test_set_all_zero_on_an_empty_shield_emits_nothing() -> void:
	var s := _make(1)
	s.set_all_zero()
	var snaps: Array = []
	s.shield_state_changed.connect(func(snap: Dictionary) -> void: snaps.append(snap))
	s.set_all_zero()
	assert_eq(snaps, [], "no snapshot when nothing changed")


func test_hacked_shield_loses_every_charge_to_a_single_hit() -> void:
	var s := _make(3)
	s.add_temporary()
	s.add_temporary()
	s.set_hacked(true)
	assert_true(s.consume_one(), "the hit is still absorbed")
	assert_eq(s.permanent_active, 0, "but the whole bank is drained")
	assert_eq(s.temporary_count, 0)
	assert_false(s.consume_one(), "and nothing is left for the next hit")


func test_set_hacked_is_idempotent() -> void:
	var s := _make(1)
	s.set_hacked(true)
	var snaps: Array = []
	s.shield_state_changed.connect(func(snap: Dictionary) -> void: snaps.append(snap))
	s.set_hacked(true)
	assert_eq(snaps, [], "setting the same hacked value emits nothing")
	s.set_hacked(false)
	assert_eq(snaps.size(), 1)
	assert_false(s.is_hacked)


func test_snapshot_keys_are_what_the_icon_strip_reads() -> void:
	var s := _make(2)
	var snaps: Array = []
	s.shield_state_changed.connect(func(snap: Dictionary) -> void: snaps.append(snap))
	s.add_temporary()
	assert_eq(snaps.size(), 1)
	var keys: Array = snaps[0].keys()
	keys.sort()
	assert_eq(keys, ["hacked", "perm_active", "perm_max", "temp_count"])


func test_regen_refills_one_permanent_charge_at_a_time() -> void:
	var s := _make(3)
	s.consume_one()
	s.consume_one()
	assert_eq(s.permanent_active, 1)
	s._on_regen_tick()
	assert_eq(s.permanent_active, 2, "one charge per tick, not a full refill")
	s._on_regen_tick()
	assert_eq(s.permanent_active, 3)
	s._on_regen_tick()
	assert_eq(s.permanent_active, 3, "regen stops at the maximum")


func test_regen_interval_is_five_seconds() -> void:
	assert_eq(Shield.REGEN_INTERVAL_SEC, 5.0)
	var s := _make(2)
	s.consume_one()
	assert_almost_eq(s._regen_timer.wait_time, 5.0, 0.0001)
	assert_false(s._regen_timer.is_stopped(), "taking a hit restarts the regen countdown")


func test_bind_progression_tracks_the_progression_autoload() -> void:
	ShipProgressionState.set_permanent_shield_count(2)
	var s := Shield.new()
	s.bind_progression = true
	add_child_autofree(s)
	assert_eq(s.permanent_max, 2, "the cap comes from ShipProgressionState")
	assert_eq(s.permanent_active, 2)

	## A shield_up pickup mid-mission raises the cap AND grants the new charge.
	ShipProgressionState.set_permanent_shield_count(3)
	assert_eq(s.permanent_max, 3)
	assert_eq(s.permanent_active, 3, "the newly unlocked slot is filled immediately")


func test_shrinking_the_progression_cap_keeps_the_active_count_legal() -> void:
	ShipProgressionState.set_permanent_shield_count(4)
	var s := Shield.new()
	s.bind_progression = true
	add_child_autofree(s)
	assert_eq(s.permanent_active, 4)

	ShipProgressionState.set_permanent_shield_count(2)
	assert_eq(s.permanent_max, 2)
	## Clamped to 2, then the "auto-fill a new slot" branch cannot raise it further.
	assert_eq(s.permanent_active, 2, "active never exceeds max after a shrink")
