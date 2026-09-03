## Characterization tests for the TempHealth component — the temporary HP pool
## that sits between the shield and regular health in the damage chain.
extends GutTest

var _th: TempHealth
var _events: Array


func before_each() -> void:
	_th = TempHealth.new()
	_events = []
	_th.amount_changed.connect(func(cur: int, maximum: int) -> void: _events.append([cur, maximum]))


func after_each() -> void:
	_th.free()


func test_starts_empty() -> void:
	assert_eq(_th.current_temp, 0)
	assert_eq(_th.max_temp, 0, "max_temp is 0 until the first stack fixes the stack size")
	assert_eq(TempHealth.MAX_STACKS, 5)


func test_a_stack_is_half_of_base_health() -> void:
	assert_true(_th.add_stack(100))
	assert_eq(_th.current_temp, 50)
	assert_eq(_th.max_temp, 250, "MAX_STACKS * stack_hp")
	assert_eq(_events, [[50, 250]])


## INTENT: `stack_hp` is the persistence hook SessionState saves and feeds back to
## `restore()`. It must report the locked-in stack size without the caller having to
## divide `max_temp` by MAX_STACKS.
func test_stack_hp_reports_the_locked_in_stack_size() -> void:
	assert_eq(_th.stack_hp, 0, "0 until the first stack fixes the size")
	_th.add_stack(21)
	assert_eq(_th.stack_hp, 10, "maxi(1, 21 / 2)")
	assert_eq(_th.max_temp, TempHealth.MAX_STACKS * _th.stack_hp)
	_th.take_damage(3)
	assert_eq(_th.stack_hp, 10, "draining the pool does not change the stack size")


func test_stack_hp_is_set_by_restore_too() -> void:
	_th.restore(9, 7)
	assert_eq(_th.stack_hp, 7)
	assert_eq(_th.max_temp, 35)


func test_stack_size_is_locked_to_the_first_call() -> void:
	## CHARACTERIZED: _stack_hp is set once and never revisited, so picking up a
	## temp-HP crate on a ship whose base health later changes keeps the old size.
	_th.add_stack(100)
	_th.add_stack(10)
	assert_eq(_th.current_temp, 100, "the second stack is still worth 50, not 5")
	assert_eq(_th.max_temp, 250)


func test_a_stack_is_never_worth_less_than_one_hp() -> void:
	assert_true(_th.add_stack(1))
	assert_eq(_th.current_temp, 1, "maxi(1, base/2) floors the stack size at 1")
	assert_eq(_th.max_temp, 5)


func test_stacking_stops_at_the_cap() -> void:
	for _i in TempHealth.MAX_STACKS:
		assert_true(_th.add_stack(20))
	assert_eq(_th.current_temp, 50, "5 stacks of 10")
	assert_false(_th.add_stack(20), "a sixth stack is refused")
	assert_eq(_th.current_temp, 50)


func test_take_damage_drains_the_pool_and_reports_no_overflow() -> void:
	_th.add_stack(100)                   ## 50 temp HP
	var overflow: int = _th.take_damage(20)
	assert_eq(overflow, 0, "damage smaller than the pool passes nothing through")
	assert_eq(_th.current_temp, 30)


func test_take_damage_passes_the_remainder_through_to_health() -> void:
	_th.add_stack(100)                   ## 50 temp HP
	var overflow: int = _th.take_damage(80)
	assert_eq(overflow, 30, "the pool absorbs 50 and 30 reaches regular health")
	assert_eq(_th.current_temp, 0)


func test_an_empty_pool_passes_damage_straight_through() -> void:
	var overflow: int = _th.take_damage(15)
	assert_eq(overflow, 15)
	assert_eq(_events, [], "an empty pool emits nothing")


func test_restore_rebuilds_the_pool_from_saved_values() -> void:
	_th.restore(30, 10)
	assert_eq(_th.current_temp, 30)
	assert_eq(_th.max_temp, 50)
	assert_eq(_events, [[30, 50]])


func test_restore_clamps_to_the_stack_cap() -> void:
	_th.restore(9999, 10)
	assert_eq(_th.current_temp, 50, "a corrupt save cannot exceed MAX_STACKS * stack_hp")


func test_restore_ignores_meaningless_input() -> void:
	_th.restore(0, 10)
	_th.restore(30, 0)
	_th.restore(-5, -5)
	assert_eq(_th.current_temp, 0)
	assert_eq(_events, [], "nothing to restore means no signal")


func test_restore_does_not_overwrite_an_established_stack_size() -> void:
	_th.add_stack(100)                   ## locks stack_hp to 50
	_th.restore(20, 7)
	assert_eq(_th.max_temp, 250, "the saved stack size is ignored once one is set")
	assert_eq(_th.current_temp, 20)
