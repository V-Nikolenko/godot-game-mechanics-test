## Unit tests for EngagementBudget (global/enemy_ai/engagement_budget.gd).
## docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6.
extends GutTest

const DT := 1.0 / 60.0


## Simulates the Assault harness: an ArenaCamera joins the &"assault_arena" group in _ready().
func _with_arena() -> void:
	add_child_autofree(ArenaCamera.new())


func test_inactive_with_no_arena_provider() -> void:
	var budget := EngagementBudget.new(5.5, get_tree())
	assert_false(budget.active, "no provider in the tree -> Open Space -> inactive")


func test_active_with_an_arena_provider() -> void:
	_with_arena()
	var budget := EngagementBudget.new(5.5, get_tree())
	assert_true(budget.active)


## The Open Space harness: update() must never report expired, no matter how much time passes.
func test_update_is_a_permanent_no_op_when_inactive() -> void:
	var budget := EngagementBudget.new(1.0, get_tree())
	for _i in 600:
		assert_false(budget.update(DT), "inactive budget must never expire")


func test_update_reports_expired_once_seconds_have_elapsed() -> void:
	_with_arena()
	var budget := EngagementBudget.new(1.0, get_tree())
	var steps := int(1.0 / DT)
	for _i in steps - 1:
		assert_false(budget.update(DT), "must not expire before its seconds have elapsed")
	assert_true(budget.update(DT), "must expire once seconds have elapsed")


## Once expired, later calls keep reporting true — the brain checks this once per tick and only
## acts the first time it turns true, so a second read must not silently go back to false.
func test_expired_stays_expired() -> void:
	_with_arena()
	var budget := EngagementBudget.new(0.1, get_tree())
	assert_true(budget.update(1.0))
	assert_true(budget.update(0.0))
	assert_true(budget.update(DT))


## Counting only advances by the delta a caller feeds it — a brain that constructs the budget on
## spawn and calls update() every tick starts the clock on the spawn frame, exactly as the plan
## requires, regardless of how much real time passed before the first call.
func test_counting_only_advances_by_fed_delta() -> void:
	_with_arena()
	var budget := EngagementBudget.new(1.0, get_tree())
	assert_false(budget.update(0.0), "no delta fed yet; elapsed stays at 0")
	assert_true(budget.update(1.0))


## `remaining()` is what the Swarm Drone's WINDUP gate reads (docs/plans/cmuj4y8rh0070p52xk6vzfvbe):
## INF with no arena (never expires), counting down by fed delta, floored at 0 once expired.
func test_remaining_is_inf_without_an_arena() -> void:
	var budget := EngagementBudget.new(1.0, get_tree())
	budget.update(5.0)
	assert_eq(budget.remaining(), INF)


func test_remaining_counts_down_and_floors_at_zero() -> void:
	_with_arena()
	var budget := EngagementBudget.new(1.0, get_tree())
	assert_almost_eq(budget.remaining(), 1.0, 0.0001)
	budget.update(0.25)
	assert_almost_eq(budget.remaining(), 0.75, 0.0001)
	budget.update(3.0)
	assert_eq(budget.remaining(), 0.0)
