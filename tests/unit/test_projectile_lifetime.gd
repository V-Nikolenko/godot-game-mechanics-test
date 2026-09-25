## Unit tests for ProjectileLifetime (global/components/projectile_lifetime.gd) — the world-space
## lifetime rules for a projectile: max_time, max_distance from the origin, and (optionally) the
## Assault mode's world rect. Every case in
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.9's test_projectile_lifetime.gd row.
##
## Kept IN the tree (add_child_autofree) because EnemyWorld.projectile_world_rect() needs
## get_tree(), but every _physics_process call is made BY HAND with an explicit delta, exactly
## like tests/unit/test_overheat_component.gd — none of these tests await a frame, so the engine
## never ticks physics on its own mid-test.
extends GutTest


## A minimal stand-in for a projectile host: Node2D + the `expired` signal the component looks up
## duck-typed via has_signal(). Deliberately NOT an EnemyBullet, so these tests exercise only the
## component's own contract.
class Host extends Node2D:
	signal expired


## A stand-in for the &"assault_arena" provider (ArenaCamera in real code) — answers
## projectile_world_rect() and nothing else, proving the lookup is duck-typed.
class RectProvider extends Node:
	var rect: Rect2 = Rect2()
	func projectile_world_rect() -> Rect2:
		return rect


var _host: Host


func before_each() -> void:
	_host = Host.new()
	add_child_autofree(_host)


func _lifetime(max_time: float = 0.0, max_distance: float = 0.0,
		use_world_rect: bool = false) -> ProjectileLifetime:
	var lt := ProjectileLifetime.new()
	lt.max_time = max_time
	lt.max_distance = max_distance
	lt.use_world_rect = use_world_rect
	_host.add_child(lt)
	return lt


# ---------------------------------------------------------------------------------------------
# Lazy arming (F1 / N-boundary): never in _ready(), on reset() or the first tick, whichever first.
# ---------------------------------------------------------------------------------------------

## The component must NOT record the origin in _ready(). If it did, moving the host before the
## first physics tick (exactly what happens to the unpooled sniper shot, positioned only after
## add_child()) would make the very first tick see the full jump as travel and expire immediately.
func test_lazy_arm_never_reset_records_origin_at_first_tick_not_at_ready() -> void:
	_host.global_position = Vector2.ZERO
	var lt := _lifetime(0.0, 50.0, false)  # max_distance = 50
	# Host moves 1000px BEFORE the component's first physics tick — as the sniper shot does.
	_host.global_position = Vector2(1000.0, 0.0)

	watch_signals(_host)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 0,
			"arming at _ready() would have recorded origin (0,0) and expired on this very tick")

	# Now move only 60px past the (lazily armed) origin — this SHOULD trip max_distance = 50.
	_host.global_position += Vector2(60.0, 0.0)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 1,
			"the lazily-armed origin must be the position at the first tick, not at _ready()")


func test_reset_arms_immediately_with_the_position_at_reset_time() -> void:
	_host.global_position = Vector2(500.0, 0.0)
	var lt := _lifetime(0.0, 50.0, false)
	lt.reset()  # origin = (500, 0)
	_host.global_position = Vector2(560.0, 0.0)  # 60px from the reset-time origin

	watch_signals(_host)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 1, "reset() must arm immediately, not lazily")


# ---------------------------------------------------------------------------------------------
# The three rules, each in isolation.
# ---------------------------------------------------------------------------------------------

func test_max_time_rule_trips_once_the_clock_reaches_it() -> void:
	var lt := _lifetime(1.0, 0.0, false)
	watch_signals(_host)
	lt._physics_process(0.5)
	assert_signal_emit_count(_host, "expired", 0, "0.5s of 1.0s should not expire yet")
	lt._physics_process(0.6)
	assert_signal_emit_count(_host, "expired", 1, "1.1s total should have tripped max_time")


func test_max_distance_rule_trips_once_the_origin_is_left_far_enough() -> void:
	var lt := _lifetime(0.0, 100.0, false)
	lt._physics_process(0.016)  # arms at (0, 0)
	watch_signals(_host)
	_host.global_position = Vector2(90.0, 0.0)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 0, "90px of a 100px budget should not expire yet")
	_host.global_position = Vector2(101.0, 0.0)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 1, "101px should have crossed the 100px budget")


func test_a_zero_rule_is_disabled() -> void:
	var lt := _lifetime(0.0, 0.0, false)
	lt._physics_process(0.016)
	_host.global_position = Vector2(1.0e6, 1.0e6)
	watch_signals(_host)
	for _i in 100:
		lt._physics_process(1.0)
	assert_signal_emit_count(_host, "expired", 0,
			"max_time = 0 and max_distance = 0 must both be off")


func test_use_world_rect_expires_on_leaving_the_provider_s_rect() -> void:
	var provider := RectProvider.new()
	provider.rect = Rect2(Vector2(-100.0, -100.0), Vector2(200.0, 200.0))  # -100..100 each axis
	add_child_autofree(provider)
	provider.add_to_group(EnemyWorld.ARENA_GROUP)

	var lt := _lifetime(0.0, 0.0, true)
	lt._physics_process(0.016)  # arms with the rect resolved

	watch_signals(_host)
	_host.global_position = Vector2(99.0, 0.0)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 0, "still inside the provider's rect")

	_host.global_position = Vector2(101.0, 0.0)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 1, "left the provider's rect")


## With no provider in the tree, use_world_rect must be a no-op — only time/distance apply, and
## both are disabled here, so this never expires no matter how far the host travels.
func test_use_world_rect_with_no_provider_never_expires() -> void:
	var lt := _lifetime(0.0, 0.0, true)
	lt._physics_process(0.016)
	watch_signals(_host)
	_host.global_position = Vector2(1.0e6, 1.0e6)
	lt._physics_process(0.016)
	assert_signal_emit_count(_host, "expired", 0, "no provider means the rect rule is disabled")


# ---------------------------------------------------------------------------------------------
# The latch: expired fires exactly once per life, and never queue_frees.
# ---------------------------------------------------------------------------------------------

func test_expired_fires_once_and_latches_until_reset() -> void:
	var lt := _lifetime(1.0, 0.0, false)
	watch_signals(_host)
	lt._physics_process(2.0)  # trips max_time
	assert_signal_emit_count(_host, "expired", 1)
	# Keep ticking well past every threshold — must not fire again.
	for _i in 10:
		lt._physics_process(1.0)
	assert_signal_emit_count(_host, "expired", 1, "expired must latch until the next reset()")

	lt.reset()
	lt._physics_process(2.0)
	assert_signal_emit_count(_host, "expired", 2, "reset() must clear the latch")


func test_expire_now_emits_once_through_the_same_latch() -> void:
	var lt := _lifetime(0.0, 0.0, false)
	lt._physics_process(0.016)
	watch_signals(_host)
	lt.expire_now()
	lt.expire_now()
	assert_signal_emit_count(_host, "expired", 1, "expire_now() must latch like every other rule")


func test_expiring_never_frees_the_host_or_the_component() -> void:
	var lt := _lifetime(1.0, 0.0, false)
	lt._physics_process(2.0)
	assert_true(is_instance_valid(_host), "ProjectileLifetime must never free its host")
	assert_true(is_instance_valid(lt), "ProjectileLifetime must never free itself")
	assert_false(_host.is_queued_for_deletion())
	assert_false(lt.is_queued_for_deletion())


func test_duck_typed_host_without_expired_signal_does_not_error() -> void:
	var plain := Node2D.new()
	add_child_autofree(plain)
	var lt := ProjectileLifetime.new()
	lt.max_time = 1.0
	plain.add_child(lt)
	lt._physics_process(2.0)  # must not error even though `plain` has no `expired` signal
	assert_true(is_instance_valid(plain))
