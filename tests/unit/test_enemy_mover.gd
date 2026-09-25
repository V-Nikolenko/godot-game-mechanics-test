## INTENT tests for `EnemyMover` (`global/enemy_ai/enemy_mover.gd`) — new code, so these assert
## the contract in docs/plans/cmug33ldn00d3m52wfe1j6fct/3-plan.md, not today's behaviour.
##
## Harness: a plain `CharacterBody2D` actor (floating motion mode) in the tree, with the mover as
## its child; `mover.step(dt)` is called directly, never through engine frames, so every case is
## exact. `dt = 1/64` wherever a duration is summed over steps — 1/64 is exact in binary floating
## point, so an accumulated clock lands on its boundary exactly (1/60 does not: the plan review's
## R3 / the epic review's N7).
extends GutTest

const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")

const DT := 1.0 / 60.0
const DT_EXACT := 1.0 / 64.0
const EPS := 0.0001


func _script(source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	return s


## A plain actor + mover. `configure` runs on the mover before it enters the tree.
func _rig(configure: Callable = Callable()) -> EnemyMover:
	var actor := CharacterBody2D.new()
	actor.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var mover := EnemyMover.new()
	if configure.is_valid():
		configure.call(mover)
	actor.add_child(mover)
	add_child_autofree(actor)
	return mover


# ── Pass-through and limits ────────────────────────────────────────────────────

func test_unconfigured_mover_is_a_pass_through_and_moves_the_actor() -> void:
	var mover := _rig()
	var start := mover.actor.global_position
	mover.request_velocity(Vector2(120, -30))
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2(120, -30))
	assert_ne(mover.actor.global_position, start, "step() must call move_and_slide()")


func test_acceleration_caps_the_velocity_change_per_step() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.acceleration = 600.0)
	mover.request_velocity(Vector2(300, 0))
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 10.0, EPS)
	for _i in 29:
		mover.request_velocity(Vector2(300, 0))
		mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 300.0, EPS, "reaches the target after 30 steps, no overshoot")
	mover.request_velocity(Vector2(300, 0))
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 300.0, EPS)


func test_braking_caps_a_slow_down_separately_from_acceleration() -> void:
	var mover := _rig(func(m: EnemyMover) -> void:
		m.acceleration = 600.0
		m.braking = 1200.0)
	mover.actor.velocity = Vector2(300, 0)
	mover.request_velocity(Vector2.ZERO)
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 280.0, EPS, "slow-down uses braking (1200/60 = 20)")


## Boundary: braking = 0 means "same as acceleration".
func test_zero_braking_falls_back_to_acceleration() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.acceleration = 600.0)
	mover.actor.velocity = Vector2(300, 0)
	mover.request_velocity(Vector2.ZERO)
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 290.0, EPS)


func test_zero_acceleration_is_instant() -> void:
	var mover := _rig()
	mover.actor.velocity = Vector2(-500, 0)
	mover.request_velocity(Vector2(400, 100))
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2(400, 100))


func test_max_speed_truncates_the_request() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.max_speed = 100.0)
	mover.request_velocity(Vector2(300, 0))
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.length(), 100.0, EPS)


func test_nudge_sums_with_the_primary_and_a_second_request_replaces_the_first() -> void:
	var mover := _rig()
	mover.request_velocity(Vector2(999, 999))
	mover.request_velocity(Vector2(100, 0))
	mover.add_nudge(Vector2(0, 20))
	mover.add_nudge(Vector2(0, 5))
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2(100, 25))


func test_requests_clear_after_each_step() -> void:
	var mover := _rig()
	mover.request_velocity(Vector2(100, 0))
	mover.add_nudge(Vector2(0, 50))
	mover.step(DT)
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2.ZERO, "no request next step → instant stop (no accel limit)")


func test_requests_clear_after_each_step_and_decay_at_braking() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.braking = 600.0)
	mover.actor.velocity = Vector2(100, 0)
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, 90.0, EPS)


# ── Constraint ─────────────────────────────────────────────────────────────────

const DOUBLING_CONSTRAINT_SRC := """extends MovementConstraint
func filter(_position: Vector2, desired: Vector2) -> Vector2:
	return desired * 2.0
"""

const PROVIDER_SRC := """extends Node
var constraint_script: GDScript
var made: Array = []
func enemy_movement_constraint():
	var c = constraint_script.new()
	made.append(c)
	return c
"""


func _spawn_provider() -> Node:
	var provider: Node = _script(PROVIDER_SRC).new()
	provider.constraint_script = _script(DOUBLING_CONSTRAINT_SRC)
	provider.add_to_group(EnemyWorld.ARENA_GROUP)
	add_child_autofree(provider)
	return provider


func test_injected_constraint_filters_the_velocity() -> void:
	var doubling: MovementConstraint = _script(DOUBLING_CONSTRAINT_SRC).new()
	var mover := _rig(func(m: EnemyMover) -> void: m.constraint = doubling)
	mover.request_velocity(Vector2(50, 10))
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2(100, 20))


func test_auto_without_a_provider_resolves_no_constraint() -> void:
	var mover := _rig()
	assert_null(mover.constraint, "Open Space: no provider, no constraint")


func test_auto_resolves_the_providers_constraint() -> void:
	var provider := _spawn_provider()
	var mover := _rig()
	assert_eq(provider.made.size(), 1)
	assert_same(mover.constraint, provider.made[0])


func test_constraint_mode_none_never_resolves_one_even_with_a_provider() -> void:
	var provider := _spawn_provider()
	var mover := _rig(func(m: EnemyMover) -> void: m.constraint_mode = EnemyMover.ConstraintMode.NONE)
	assert_null(mover.constraint)
	assert_eq(provider.made.size(), 0, "NONE must not even ask the provider")


func test_injected_constraint_wins_over_auto() -> void:
	var provider := _spawn_provider()
	var injected := MovementConstraint.new()
	var mover := _rig(func(m: EnemyMover) -> void: m.constraint = injected)
	assert_same(mover.constraint, injected)
	assert_eq(provider.made.size(), 0)


# ── Facing ─────────────────────────────────────────────────────────────────────

func test_actor_without_sprite_forward_angle_faces_with_pi_over_2() -> void:
	var mover := _rig()
	assert_null(mover.actor.get(&"sprite_forward_angle"), "sanity: a plain body has no such property")
	mover.request_velocity(Vector2.RIGHT * 100.0)
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, -PI / 2.0, EPS, "RIGHT.angle() (0) - PI/2")


func test_nose_down_actor_heading_down_has_rotation_zero() -> void:
	var mover := _rig()
	mover.request_velocity(Vector2.DOWN * 100.0)
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, 0.0, EPS)


func test_sprite_forward_angle_is_read_from_the_actor() -> void:
	var enemy := FIXTURE_ENEMY.instantiate()
	enemy.sprite_forward_angle = -PI / 2.0  # nose-up art
	var brain := enemy.get_node("Brain")
	enemy.remove_child(brain)  # this case drives the mover by hand
	brain.free()
	add_child_autofree(enemy)
	var mover: EnemyMover = enemy.get_node("EnemyMover")
	mover.request_velocity(Vector2.UP * 100.0)
	mover.step(DT)
	assert_almost_eq(enemy.rotation, 0.0, EPS, "UP.angle() (-PI/2) - (-PI/2)")


func test_face_toward_beats_the_velocity_heading() -> void:
	var mover := _rig()
	mover.request_velocity(Vector2.RIGHT * 100.0)
	mover.face_toward(mover.actor.global_position + Vector2.RIGHT * 100.0 + Vector2(0, 500))
	mover.step(DT)
	# After move_and_slide the actor sits ~(1.67, 0) further right; the point is recomputed from the
	# post-move position, so compute the expectation the same way.
	var heading: Vector2 = (Vector2.RIGHT * 100.0 + Vector2(0, 500)) - (mover.actor.global_position)
	assert_almost_eq(mover.actor.rotation, heading.angle() - PI / 2.0, EPS)


## Boundary: no velocity and no face request → rotation untouched (atan2 of zero is not a heading).
func test_zero_heading_leaves_rotation_unchanged() -> void:
	var mover := _rig()
	mover.actor.rotation = 1.234
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, 1.234, EPS)


func test_turn_lerp_eases_toward_the_target() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.turn_lerp = 7.0)
	mover.request_velocity(Vector2.LEFT * 100.0)  # target = PI - PI/2 = PI/2
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, lerp_angle(0.0, PI / 2.0, DT * 7.0), EPS)


func test_max_turn_rate_caps_the_rotation_change_per_step() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.max_turn_rate = PI)
	mover.request_velocity(Vector2.LEFT * 100.0)  # target PI/2, far more than PI/60 away
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, PI / 60.0, EPS)


func test_max_turn_rate_takes_the_short_way_round() -> void:
	var mover := _rig(func(m: EnemyMover) -> void: m.max_turn_rate = PI)
	mover.actor.rotation = 3.0
	mover.request_velocity(Vector2.from_angle(-3.0 + PI / 2.0) * 100.0)  # target -3.0: 0.28 rad the short way
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, 3.0 + PI / 60.0, EPS)


## Boundary: max_turn_rate = 0 is uncapped (snaps with turn_lerp 0).
func test_zero_max_turn_rate_is_uncapped() -> void:
	var mover := _rig()
	mover.request_velocity(Vector2.LEFT * 100.0)
	mover.step(DT)
	assert_almost_eq(mover.actor.rotation, PI / 2.0, EPS)


# ── Boost and halt ─────────────────────────────────────────────────────────────

func test_boost_overrides_for_its_duration_then_ends() -> void:
	var mover := _rig(func(m: EnemyMover) -> void:
		m.max_speed = 100.0
		m.acceleration = 10.0)
	mover.boost(Vector2.RIGHT * 3.0, 480.0, 0.125)
	for i in 8:
		assert_true(mover.is_boosting(), "boosting on step %d" % (i + 1))
		mover.request_velocity(Vector2(0, 50))
		mover.add_nudge(Vector2(0, 50))
		mover.step(DT_EXACT)
		assert_eq(mover.actor.velocity, Vector2(480, 0), "step %d ignores request, nudge, max_speed, accel" % (i + 1))
	assert_false(mover.is_boosting(), "0.125 s = exactly 8 steps of 1/64")
	mover.request_velocity(Vector2(0, 50))
	mover.step(DT_EXACT)
	assert_ne(mover.actor.velocity, Vector2(480, 0), "step 9 is back under the request and limits")


func test_halt_zeroes_velocity_and_cancels_a_boost() -> void:
	var mover := _rig()
	mover.boost(Vector2.RIGHT, 480.0, 1.0)
	mover.step(DT)
	mover.halt()
	assert_eq(mover.actor.velocity, Vector2.ZERO)
	assert_false(mover.is_boosting())
	mover.step(DT)
	assert_eq(mover.actor.velocity, Vector2.ZERO)


# ── Steering wrappers (review R2): each is Steering.<same> at the actor ────────

func _wrapper_rig() -> EnemyMover:
	var mover := _rig()
	mover.actor.global_position = Vector2(100, 200)
	return mover


func test_seek_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.seek(Vector2(100, 200), Vector2(400, 0), 150.0)
	mover.seek(Vector2(400, 0), 150.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_arrive_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.arrive(Vector2(100, 200), Vector2.ZERO, Vector2(400, 0), 150.0, 0.0)
	mover.arrive(Vector2(400, 0), 150.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


## The slowing radius must use the rate the mover actually slows at: braking, not acceleration.
## With limits on, the step also applies its own rate limit, so the expectation is that limit
## applied to Steering.arrive(..., braking). The numbers are chosen so the limit cannot mask a wrong
## rate: v0 = 300 gives a slowing radius of 7.5 px at braking 6000 (target 50 px away is outside it →
## full speed, velocity stays 300) but 75 px at acceleration 600 (inside → desired 200 → brakes to 200).
func test_arrive_wrapper_uses_braking_as_the_slowing_rate() -> void:
	var mover := _rig(func(m: EnemyMover) -> void:
		m.acceleration = 600.0
		m.braking = 6000.0)
	var pos := Vector2(100, 200)
	var target := Vector2(150, 200)
	var v0 := Vector2(300, 0)
	mover.actor.global_position = pos
	mover.actor.velocity = v0
	var desired_braking := Steering.arrive(pos, v0, target, 300.0, 6000.0)
	var desired_accel := Steering.arrive(pos, v0, target, 300.0, 600.0)
	assert_ne(desired_braking, desired_accel, "sanity: the two slowing rates must disagree here")
	var rate := 6000.0 if desired_braking.length() < v0.length() else 600.0
	var expected := v0.move_toward(desired_braking, rate * DT)
	mover.arrive(target, 300.0)
	mover.step(DT)
	assert_almost_eq(mover.actor.velocity.x, expected.x, EPS)
	assert_almost_eq(mover.actor.velocity.y, expected.y, EPS)
	assert_almost_eq(mover.actor.velocity.x, 300.0, EPS)


func test_orbit_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.orbit(Vector2(100, 200), Vector2(300, 300), 130.0, 0.7, 350.0)
	mover.orbit(Vector2(300, 300), 130.0, 0.7, 350.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_intercept_wrapper() -> void:
	var mover := _wrapper_rig()
	var target := TargetInfo.new()
	target.has_target = true
	target.position = Vector2(500, 500)
	target.velocity = Vector2(-40, 10)
	var expected := Steering.intercept(Vector2(100, 200), target, 200.0, 0.5)
	mover.intercept(target, 200.0, 0.5)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_retreat_from_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.retreat_from(Vector2(100, 200), Vector2(0, 0), 120.0)
	mover.retreat_from(Vector2(0, 0), 120.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_evade_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.evade(Vector2(100, 200), Vector2(0, 0), Vector2(50, 0), 120.0, 0.4)
	mover.evade(Vector2(0, 0), Vector2(50, 0), 120.0, 0.4)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_strafe_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.strafe(Vector2(100, 200), Vector2(100, 0), -1.0, 90.0)
	mover.strafe(Vector2(100, 0), -1.0, 90.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_hold_position_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.hold_position(Vector2(100, 200), Vector2.ZERO, Vector2(300, 200), 10.0, 150.0, 0.0)
	mover.hold_position(Vector2(300, 200), 10.0, 150.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


func test_drift_wrapper() -> void:
	var mover := _wrapper_rig()
	var expected := Steering.drift(Vector2(3, 4), 50.0)
	mover.drift(Vector2(3, 4), 50.0)
	mover.step(DT)
	assert_eq(mover.actor.velocity, expected)


# ── Bad parents ────────────────────────────────────────────────────────────────

## Boundary: a mover under a non-CharacterBody2D warns (never errors — load integrity and GUT's
## error tracker allow none) and stays inert.
func test_non_character_body_parent_only_warns_and_stays_inert() -> void:
	var parent := Node2D.new()
	var mover := EnemyMover.new()
	parent.add_child(mover)
	add_child_autofree(parent)
	assert_null(mover.actor)
	mover.request_velocity(Vector2(100, 0))
	mover.step(DT)
	assert_eq(parent.position, Vector2.ZERO)


func test_bare_mover_outside_the_tree_steps_without_crashing() -> void:
	var mover: EnemyMover = autofree(EnemyMover.new())
	mover.request_velocity(Vector2(1, 1))
	mover.step(DT)
	mover.halt()
	assert_null(mover.actor)
