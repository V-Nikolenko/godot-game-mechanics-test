## INTENT tests for `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) — new code, so these assert the
## contract in docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.5, not today's behaviour.
extends GutTest

const State := AnchorIdle.State
const DT := 1.0 / 60.0

const ANCHOR := Vector2(1000.0, 0.0)
const PERCEIVE := 450.0
const LOSE := 700.0
const NOTICE_TIME := 1.0


func _idle() -> AnchorIdle:
	return AnchorIdle.new(ANCHOR, PERCEIVE, LOSE, NOTICE_TIME)


func _target_at(pos: Vector2) -> TargetInfo:
	var t := TargetInfo.new()
	t.has_target = true
	t.position = pos
	return t


func _no_target() -> TargetInfo:
	return TargetInfo.new()


func test_starts_idle() -> void:
	assert_eq(_idle().update(DT, ANCHOR, _no_target()), State.IDLE)


func test_idle_to_noticing_at_perceive_radius() -> void:
	var idle := _idle()
	var target := _target_at(ANCHOR + Vector2(PERCEIVE - 1.0, 0.0))
	assert_eq(idle.update(DT, ANCHOR, target), State.NOTICING)


func test_idle_stays_idle_outside_perceive_radius() -> void:
	var idle := _idle()
	var target := _target_at(ANCHOR + Vector2(PERCEIVE + 50.0, 0.0))
	assert_eq(idle.update(DT, ANCHOR, target), State.IDLE)


func test_noticing_to_combat_after_notice_time() -> void:
	var idle := _idle()
	var target := _target_at(ANCHOR)
	idle.update(DT, ANCHOR, target)  # IDLE -> NOTICING
	var steps := int(NOTICE_TIME / DT)
	for _i in steps - 1:
		assert_eq(idle.update(DT, ANCHOR, target), State.NOTICING, "must not reach COMBAT early")
	assert_eq(idle.update(DT, ANCHOR, target), State.COMBAT)


## Hysteresis: a target whose distance oscillates around 500 px - always above perceive_radius
## (450) but always below lose_radius (700) - must never flip COMBAT back to RETURNING once
## reached, over a full 5 s.
func test_no_flip_while_oscillating_between_perceive_and_lose() -> void:
	var idle := _idle()
	var actor_pos := Vector2.ZERO
	var target_close := _target_at(actor_pos + Vector2(400.0, 0.0))
	idle.update(DT, actor_pos, target_close)  # dip inside perceive_radius -> NOTICING
	var steps := int(NOTICE_TIME / DT) + 1
	var setup_state := State.IDLE
	for _i in steps:
		setup_state = idle.update(DT, actor_pos, target_close)
	assert_eq(setup_state, State.COMBAT, "setup must reach COMBAT before the oscillation starts")

	var elapsed := 0.0
	while elapsed < 5.0:
		var dist := 500.0 + 100.0 * sin(elapsed * 3.0)  # oscillates in [400, 600], never >= 700
		var target := _target_at(actor_pos + Vector2(dist, 0.0))
		var state := idle.update(DT, actor_pos, target)
		assert_eq(state, State.COMBAT, "must not leave COMBAT while within lose_radius")
		elapsed += DT


func test_combat_to_returning_beyond_lose_radius() -> void:
	var idle := _idle()
	var actor_pos := Vector2.ZERO
	idle.force_notice()
	var far := _target_at(actor_pos + Vector2(LOSE + 1.0, 0.0))
	idle.update(0.0, actor_pos, far)  # NOTICING, elapsed 0
	idle.update(NOTICE_TIME, actor_pos, far)  # -> COMBAT
	assert_eq(idle.update(DT, actor_pos, far), State.RETURNING)


func test_returning_to_idle_at_the_anchor() -> void:
	var idle := _idle()
	idle.force_notice()
	idle.update(NOTICE_TIME, ANCHOR, _no_target())  # -> COMBAT
	assert_eq(idle.update(DT, ANCHOR, _no_target()), State.RETURNING, "no target -> leave COMBAT")
	assert_eq(idle.update(DT, ANCHOR, _no_target()), State.IDLE, "already at the anchor")


func test_returning_to_noticing_inside_perceive_radius() -> void:
	var idle := _idle()
	idle.force_notice()
	idle.update(NOTICE_TIME, ANCHOR, _no_target())  # -> COMBAT
	idle.update(DT, ANCHOR, _no_target())  # -> RETURNING
	var target := _target_at(ANCHOR + Vector2(PERCEIVE - 1.0, 0.0))
	assert_eq(idle.update(DT, ANCHOR, target), State.NOTICING)


func test_perceive_greater_or_equal_lose_is_rejected_and_clamped() -> void:
	var idle := AnchorIdle.new(ANCHOR, 500.0, 500.0, NOTICE_TIME)
	assert_push_error("perceive_radius")
	assert_almost_eq(idle.lose_radius, 625.0, 0.001, "clamps to perceive_radius * 1.25")


func test_force_notice_from_idle() -> void:
	var idle := _idle()
	idle.force_notice()
	assert_eq(idle.update(DT, ANCHOR, _no_target()), State.NOTICING)


func test_force_notice_from_returning() -> void:
	var idle := _idle()
	idle.force_notice()
	idle.update(NOTICE_TIME, ANCHOR, _no_target())  # -> COMBAT
	idle.update(DT, ANCHOR, _no_target())  # -> RETURNING
	idle.force_notice()
	assert_eq(idle.update(DT, ANCHOR, _no_target()), State.NOTICING)


func test_hold_combat_keeps_combat_beyond_lose_radius() -> void:
	var idle := _idle()
	idle.hold_combat = true
	var actor_pos := Vector2.ZERO
	idle.force_notice()
	var far := _target_at(actor_pos + Vector2(LOSE + 1.0, 0.0))
	idle.update(NOTICE_TIME, actor_pos, far)  # -> COMBAT
	assert_eq(idle.update(DT, actor_pos, far), State.COMBAT, "hold_combat overrides lose_radius")


func test_clearing_hold_combat_returns_on_next_update() -> void:
	var idle := _idle()
	idle.hold_combat = true
	var actor_pos := Vector2.ZERO
	idle.force_notice()
	var far := _target_at(actor_pos + Vector2(LOSE + 1.0, 0.0))
	idle.update(NOTICE_TIME, actor_pos, far)  # -> COMBAT
	assert_eq(idle.update(DT, actor_pos, far), State.COMBAT, "still held")
	idle.hold_combat = false
	assert_eq(idle.update(DT, actor_pos, far), State.RETURNING)
