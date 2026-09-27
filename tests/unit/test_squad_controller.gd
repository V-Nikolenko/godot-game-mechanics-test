## INTENT tests for `SquadController` (`global/enemy_ai/squad_controller.gd`) — new code, so these
## assert the contract in docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.4, not today's
## behaviour.
##
## Harness: plain `Node2D` fixtures, added as children of the test itself (`add_child_autofree`) so
## `tree_exiting` actually fires on `.free()`. `SquadController.new()` is never a scene child, so
## every test builds the board directly and drives it through its API, never through frames.
extends GutTest

const Role := SquadController.Role


func _member(pos: Vector2) -> Node2D:
	var m := Node2D.new()
	m.global_position = pos
	add_child_autofree(m)
	return m


# ── Assignment (§2.4, "Assignment") ─────────────────────────────────────────────

func test_one_member_is_lead() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	board.join(a)
	assert_eq(board.role_of(a), Role.LEAD)


func test_two_members_lead_and_flank_left() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var a := _member(Vector2(0, -20))     # closest to the hint → LEAD
	var b := _member(Vector2(-100, -80))  # x < 0 → left of heading UP → FLANK_LEFT
	board.join(a)
	board.join(b)
	assert_eq(board.role_of(a), Role.LEAD)
	assert_eq(board.role_of(b), Role.FLANK_LEFT)


func test_three_members_lead_and_both_flanks() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var a := _member(Vector2(0, -20))
	var b := _member(Vector2(-100, -80))
	var c := _member(Vector2(100, -90))
	board.join(a)
	board.join(b)
	board.join(c)
	assert_eq(board.role_of(a), Role.LEAD)
	assert_eq(board.role_of(b), Role.FLANK_LEFT)
	assert_eq(board.role_of(c), Role.FLANK_RIGHT)


func test_six_members_rest_are_rear_in_join_order() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var a := _member(Vector2(0, -20))
	var b := _member(Vector2(-100, -80))
	var c := _member(Vector2(100, -90))
	var d := _member(Vector2(50, -500))
	var e := _member(Vector2(-50, -600))
	var f := _member(Vector2(0, -700))
	for m in [a, b, c, d, e, f]:
		board.join(m)
	assert_eq(board.role_of(a), Role.LEAD)
	assert_eq(board.role_of(b), Role.FLANK_LEFT)
	assert_eq(board.role_of(c), Role.FLANK_RIGHT)
	assert_eq(board.role_of(d), Role.REAR)
	assert_eq(board.role_of(e), Role.REAR)
	assert_eq(board.role_of(f), Role.REAR)
	assert_eq(board.rear_index(d), 0)
	assert_eq(board.rear_index(e), 1)
	assert_eq(board.rear_index(f), 2)


func test_seven_members_a_fourth_rear_gets_index_three() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var a := _member(Vector2(0, -20))
	var b := _member(Vector2(-100, -80))
	var c := _member(Vector2(100, -90))
	var d := _member(Vector2(50, -500))
	var e := _member(Vector2(-50, -600))
	var f := _member(Vector2(0, -700))
	var g := _member(Vector2(10, -800))
	for m in [a, b, c, d, e, f, g]:
		board.join(m)
	assert_eq(board.role_of(g), Role.REAR)
	assert_eq(board.rear_index(g), 3)


func test_lead_is_the_closest_member_regardless_of_join_order() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var far := _member(Vector2(0, -500))
	var near := _member(Vector2(0, -10))  # joins last, but is closest → steals LEAD
	board.join(far)
	board.join(near)
	assert_eq(board.role_of(near), Role.LEAD)
	assert_ne(board.role_of(far), Role.LEAD, "the earlier joiner is demoted once a closer member joins")


func test_lead_tie_is_broken_by_join_order() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var first := _member(Vector2(-50, 0))
	var second := _member(Vector2(50, 0))  # exactly as far from the hint as `first`
	board.join(first)
	board.join(second)
	assert_eq(board.role_of(first), Role.LEAD)
	assert_eq(board.role_of(second), Role.FLANK_RIGHT)


# ── Reassignment (§2.4, "Reassignment") ─────────────────────────────────────────

func _rig_four() -> Dictionary:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.UP)
	var a := _member(Vector2(0, -10))    # LEAD
	var b := _member(Vector2(-30, -20))  # FLANK_LEFT, 2nd closest
	var c := _member(Vector2(40, -25))   # FLANK_RIGHT, 3rd closest
	var d := _member(Vector2(-15, -60))  # REAR, 4th closest
	for m in [a, b, c, d]:
		board.join(m)
	return {"board": board, "a": a, "b": b, "c": c, "d": d}


func test_freeing_the_lead_reassigns_in_the_same_call() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	rig.a.free()
	assert_eq(board.role_of(rig.b), Role.LEAD, "closest remaining member becomes LEAD")
	assert_eq(board.role_of(rig.c), Role.FLANK_RIGHT, "untouched flank keeps its role")
	assert_eq(board.role_of(rig.d), Role.FLANK_LEFT, "closest REAR fills the vacated flank")


func test_explicit_leave_matches_a_free_and_is_idempotent() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.leave(rig.a)
	assert_eq(board.role_of(rig.b), Role.LEAD)
	assert_eq(board.role_of(rig.c), Role.FLANK_RIGHT)
	assert_eq(board.role_of(rig.d), Role.FLANK_LEFT)
	assert_eq(board.role_of(rig.a), Role.NONE, "a is no longer a member")
	assert_false(board.members().has(rig.a))

	board.leave(rig.a)  # idempotent: already gone
	assert_eq(board.role_of(rig.b), Role.LEAD, "second leave() changes nothing")


func test_release_lead_rotates_to_the_closest_remaining_member() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.release_lead(rig.a)
	assert_eq(board.role_of(rig.a), Role.REAR, "the finishing lead drops to REAR, not re-elected")
	assert_eq(board.role_of(rig.b), Role.LEAD)


func test_release_lead_on_a_non_lead_member_is_a_noop() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.release_lead(rig.b)
	assert_eq(board.role_of(rig.a), Role.LEAD)
	assert_eq(board.role_of(rig.b), Role.FLANK_LEFT)


func test_attack_window_clears_when_the_lead_that_opened_it_leaves() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.attack_window_open = true
	rig.a.free()
	assert_false(board.attack_window_open)


func test_release_lead_clears_the_attack_window() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.attack_window_open = true
	board.release_lead(rig.a)
	assert_false(board.attack_window_open)


## t8c (task plan docs/plans/cmuj4y8rj0074p52xqmin24gu, review round 1 B4): the recompute is by
## distance, so a NON-lead leaving can move LEAD when members have moved since the last recompute.
## The window belongs to the lead that opened it, so any change of lead closes it.
func test_a_non_lead_leave_that_moves_the_lead_clears_the_window() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	rig.b.global_position = Vector2(0, -2)  # now closer than a; no recompute yet
	board.attack_window_open = true
	rig.c.free()
	assert_eq(board.role_of(rig.b), Role.LEAD, "sanity: the recompute moved LEAD to b")
	assert_false(board.attack_window_open, "a new lead never inherits the old lead's window")


func test_a_non_lead_leave_that_keeps_the_lead_keeps_the_window() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.attack_window_open = true
	rig.d.free()
	assert_eq(board.role_of(rig.a), Role.LEAD, "sanity: a still leads")
	assert_true(board.attack_window_open, "boundary: the same lead keeps its window open")


func test_a_join_that_takes_the_lead_clears_the_window() -> void:
	var rig := _rig_four()
	var board: SquadController = rig.board
	board.attack_window_open = true
	var e := _member(Vector2(0, -1))
	board.join(e)
	assert_eq(board.role_of(e), Role.LEAD, "sanity: the newcomer is closest")
	assert_false(board.attack_window_open)


# ── REAR ring (t8c) ─────────────────────────────────────────────────────────────

func test_rear_count_counts_valid_rear_members() -> void:
	var board := SquadController.new()
	assert_eq(board.rear_count(), 0, "empty board")
	board.update_target(Vector2.ZERO, Vector2.UP)
	var ms: Array[Node2D] = []
	for i in 5:
		var m := _member(Vector2(0, -10 - 10 * i))
		ms.append(m)
		board.join(m)
		assert_eq(board.rear_count(), maxi(0, i + 1 - 3), "%d members" % (i + 1))
	ms[4].free()
	assert_eq(board.rear_count(), 1, "a freed REAR is not counted")


func test_rear_ring_angle_starts_unset() -> void:
	assert_true(is_nan(SquadController.new().rear_ring_angle), "NAN until a REAR initialises it")


# ── Left/right from the heading hint (§2.4, "Assignment") ──────────────────────

func test_side_follows_the_heading_hint_sign() -> void:
	var board := SquadController.new()
	board.update_target(Vector2.ZERO, Vector2.RIGHT)  # heading rotated 90° from the earlier tests
	var a := _member(Vector2(0, -10))
	var b := _member(Vector2(0, -100))   # "left" of RIGHT is toward -y
	var c := _member(Vector2(0, 100))    # "right" of RIGHT is toward +y
	board.join(a)
	board.join(b)
	board.join(c)
	assert_eq(board.role_of(b), Role.FLANK_LEFT)
	assert_eq(board.role_of(c), Role.FLANK_RIGHT)


func test_zero_heading_falls_back_to_the_centroid_to_target_direction() -> void:
	var board := SquadController.new()
	# Centroid sits at (-20, -10); the hint (-20, -1000) is directly "above" it on the same x, so
	# the fallback heading is exactly UP. a and b are equidistant from the hint, so a (joined
	# first) wins the LEAD tie-break, same rule as test_lead_tie_is_broken_by_join_order.
	board.update_target(Vector2(-20, -1000), Vector2.ZERO)
	var a := _member(Vector2(0, -10))
	var b := _member(Vector2(-40, -10))
	board.join(a)
	board.join(b)
	assert_eq(board.role_of(a), Role.LEAD)
	assert_eq(board.role_of(b), Role.FLANK_LEFT)


# ── claim_side / release_side ───────────────────────────────────────────────────

func test_claim_side_never_hands_out_the_same_free_sector_twice() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	var b := _member(Vector2.ZERO)
	var c := _member(Vector2.ZERO)
	var d := _member(Vector2.ZERO)
	assert_eq(board.claim_side(a, SquadController.Side.LEFT), SquadController.Side.LEFT)
	assert_eq(board.claim_side(b, SquadController.Side.LEFT), SquadController.Side.FRONT, "LEFT taken → nearest free is FRONT")
	assert_eq(board.claim_side(c, SquadController.Side.LEFT), SquadController.Side.BACK, "LEFT and FRONT taken → BACK")
	assert_eq(board.claim_side(d, SquadController.Side.LEFT), SquadController.Side.RIGHT, "only RIGHT left")


func test_claim_side_shares_the_preferred_sector_once_all_four_are_taken() -> void:
	var board := SquadController.new()
	var members: Array[Node2D] = []
	for i in 4:
		var m := _member(Vector2.ZERO)
		members.append(m)
		board.claim_side(m, SquadController.Side.LEFT)
	var fifth := _member(Vector2.ZERO)
	assert_eq(board.claim_side(fifth, SquadController.Side.LEFT), SquadController.Side.LEFT, "all taken → preferred, shared")


func test_release_side_frees_the_sector_for_reuse() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	var b := _member(Vector2.ZERO)
	board.claim_side(a, SquadController.Side.LEFT)
	board.release_side(a)
	assert_eq(board.claim_side(b, SquadController.Side.LEFT), SquadController.Side.LEFT)


# ── Engagement (§2.4, "Other rules") ────────────────────────────────────────────

func test_is_engaged_true_while_any_member_is_engaged() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	var b := _member(Vector2.ZERO)
	board.join(a)
	board.join(b)
	assert_false(board.is_engaged())
	board.set_engaged(a, true)
	assert_true(board.is_engaged())
	board.set_engaged(a, false)
	assert_false(board.is_engaged())


func test_is_engaged_false_once_the_only_engaged_member_is_freed() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	var b := _member(Vector2.ZERO)
	board.join(a)
	board.join(b)
	board.set_engaged(a, true)
	assert_true(board.is_engaged())
	a.free()
	assert_false(board.is_engaged())


# ── Membership lifetime ──────────────────────────────────────────────────────────

## A member holds the board through its own `squad` property (§2.4.1: `entity.set("squad", board)`)
## — the join() connection itself does not keep a RefCounted alive in Godot 4.6, only whatever the
## caller stores it in does. Building a tiny scripted fixture with that property is what actually
## exercises "members hold the only strong reference".
func test_the_board_is_released_once_its_last_member_is_freed() -> void:
	var fixture := GDScript.new()
	fixture.source_code = "extends Node2D\nvar squad"
	fixture.reload()
	var board := SquadController.new()
	var a: Node2D = fixture.new()
	var b: Node2D = fixture.new()
	add_child_autofree(a)
	add_child_autofree(b)
	board.join(a)
	board.join(b)
	a.squad = board
	b.squad = board
	var wr: WeakRef = weakref(board)
	board = null
	a.free()
	assert_ne(wr.get_ref(), null, "b still holds a strong reference through its squad property")
	b.free()
	assert_eq(wr.get_ref(), null, "no member remains → nothing keeps the board alive")


# ── Signal arity ─────────────────────────────────────────────────────────────────

func test_role_changed_reports_the_member_and_the_new_role() -> void:
	var board := SquadController.new()
	var a := _member(Vector2.ZERO)
	var seen: Array = []
	board.role_changed.connect(func(member: Node, role: int) -> void: seen.append([member, role]))
	board.join(a)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], a)
	assert_eq(seen[0][1], Role.LEAD)
