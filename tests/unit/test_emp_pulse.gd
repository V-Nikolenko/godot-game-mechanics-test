## EmpPulse (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.8): the one EMP entry point. In Phase 7 it reaches only
## nodes in group `player`, by centre distance (<= radius), through the duck-typed `apply_emp(seconds, source)`.
## Intent tests; Phase 9 (t5) adds the trailing `targets` bitmask (enemies, seekers); the default set stays the player only.
extends GutTest


## A player stand-in: records every `apply_emp` it gets.
class FixtureTarget extends Node2D:
	var hits: Array = []
	func apply_emp(seconds: float, source: Node) -> void:
		hits.append([seconds, source])


## A group member with no `apply_emp`.
class FixtureBare extends Node2D:
	pass


func _target(at: Vector2, group: StringName = &"player") -> FixtureTarget:
	var t := FixtureTarget.new()
	t.add_to_group(group)
	add_child_autofree(t)
	t.global_position = at
	return t


func test_reaches_a_target_at_the_radius_and_not_one_pixel_beyond() -> void:
	var inside := _target(Vector2(190, 0))
	var outside := _target(Vector2(191, 0))
	var reached := EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null)
	assert_eq(inside.hits.size(), 1, "exactly at the radius is inside (centre distance, <=)")
	assert_eq(outside.hits.size(), 0, "radius + 1 is not reached")
	assert_eq(reached, 1)


func test_passes_the_seconds_and_the_source() -> void:
	var t := _target(Vector2(10, 0))
	var src := Node.new()
	add_child_autofree(src)
	EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, src)
	assert_eq(t.hits, [[2.0, src]])


func test_returns_how_many_it_reached() -> void:
	_target(Vector2(0, 50))
	_target(Vector2(60, 0))
	_target(Vector2(0, -120))
	_target(Vector2(500, 0))
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null), 3)
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 55.0, 2.0, null), 1, "a smaller radius reaches fewer")
	assert_eq(EmpPulse.emit(get_tree(), Vector2(900, 900), 190.0, 2.0, null), 0, "nothing in range: 0")


func test_ignores_a_player_node_without_apply_emp() -> void:
	var bare := FixtureBare.new()
	bare.add_to_group(&"player")
	add_child_autofree(bare)
	var t := _target(Vector2(5, 0))
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null), 1, "only the node with the method counts")
	assert_eq(t.hits.size(), 1)


func test_never_touches_group_enemies_in_phase_7() -> void:
	var foe := _target(Vector2(5, 0), &"enemies")
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null), 0)
	assert_eq(foe.hits.size(), 0, "an enemy with apply_emp is not called (Phase 9 flips this row)")


func test_a_non_positive_duration_reaches_nobody() -> void:
	var t := _target(Vector2(5, 0))
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 0.0, null), 0)
	assert_eq(t.hits.size(), 0)


# --- Phase 9 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.6): the trailing `targets` bitmask -------------------


## An enemy stand-in: answers the routing question with `answers`, records every `apply_emp`.
class FixtureEnemy extends Node2D:
	var answers: bool = true
	var hits: Array = []
	func answers_emp() -> bool:
		return answers
	func apply_emp(seconds: float, source: Node) -> void:
		hits.append([seconds, source])


## A seeker stand-in: records every `jam_guidance`.
class FixtureSeeker extends Node2D:
	var jams: Array = []
	func jam_guidance(source: Node) -> void:
		jams.append(source)


func _enemy(at: Vector2, answers: bool = true) -> FixtureEnemy:
	var e := FixtureEnemy.new()
	e.answers = answers
	e.add_to_group(&"enemies")
	add_child_autofree(e)
	e.global_position = at
	return e


func _seeker(at: Vector2, group: StringName) -> FixtureSeeker:
	var s := FixtureSeeker.new()
	s.add_to_group(group)
	add_child_autofree(s)
	s.global_position = at
	return s


func test_the_target_constants() -> void:
	assert_eq(EmpPulse.TARGET_PLAYER, 1)
	assert_eq(EmpPulse.TARGET_ENEMIES, 2)
	assert_eq(EmpPulse.TARGET_SEEKERS, 4)
	assert_eq(EmpPulse.TARGET_ALL, 7)
	assert_eq(SeekingOrdnance.ENEMY_GROUP, &"enemy_seeking_ordnance")


func test_target_enemies_reaches_an_answering_enemy_at_the_radius_and_not_one_pixel_beyond() -> void:
	var inside := _enemy(Vector2(0, 190))
	var outside := _enemy(Vector2(0, -191))
	var src := Node.new()
	add_child_autofree(src)
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, src, EmpPulse.TARGET_ENEMIES), 1)
	assert_eq(inside.hits, [[2.0, src]], "exactly at the radius is inside; seconds and source passed")
	assert_eq(outside.hits.size(), 0, "radius + 1 is not reached")


func test_target_enemies_skips_a_non_answering_a_methodless_and_a_queued_enemy() -> void:
	var deaf := _enemy(Vector2(10, 0), false)
	var bare := FixtureBare.new()
	bare.add_to_group(&"enemies")
	add_child_autofree(bare)
	var dying := _enemy(Vector2(20, 0))
	dying.queue_free()
	var live := _enemy(Vector2(30, 0))
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null, EmpPulse.TARGET_ENEMIES), 1, "only the live answering enemy")
	assert_eq(deaf.hits.size(), 0, "answers_emp() false: never called")
	assert_eq(dying.hits.size(), 0, "queued for deletion: skipped")
	assert_eq(live.hits.size(), 1)


func test_enemies_only_never_touches_the_player() -> void:
	var p := _target(Vector2(5, 0))
	var e := _enemy(Vector2(5, 0))
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null, EmpPulse.TARGET_ENEMIES), 1)
	assert_eq(p.hits.size(), 0, "TARGET_PLAYER unset: the player is not reached")
	assert_eq(e.hits.size(), 1)


func test_seekers_are_jammed_within_the_radius_and_not_counted() -> void:
	var src := Node.new()
	add_child_autofree(src)
	var mine := _seeker(Vector2(190, 0), SeekingOrdnance.GROUP)
	var theirs := _seeker(Vector2(0, 100), SeekingOrdnance.ENEMY_GROUP)
	var far := _seeker(Vector2(191, 0), SeekingOrdnance.ENEMY_GROUP)
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, src, EmpPulse.TARGET_SEEKERS), 0, "seekers are never counted")
	assert_eq(mine.jams, [src], "a player seeker at the radius is jammed, with the source")
	assert_eq(theirs.jams, [src], "an enemy seeker is jammed")
	assert_eq(far.jams.size(), 0, "radius + 1 is not")


func test_the_default_set_never_jams_a_seeker() -> void:
	var s := _seeker(Vector2(5, 0), SeekingOrdnance.GROUP)
	var e := _seeker(Vector2(5, 0), SeekingOrdnance.ENEMY_GROUP)
	EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null)
	assert_eq(s.jams.size() + e.jams.size(), 0)


func test_target_all_reaches_player_enemies_and_seekers() -> void:
	var p := _target(Vector2(5, 0))
	var e := _enemy(Vector2(0, 5))
	var s := _seeker(Vector2(-5, 0), SeekingOrdnance.ENEMY_GROUP)
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 2.0, null, EmpPulse.TARGET_ALL), 2, "player + enemy; the seeker is not counted")
	assert_eq(p.hits.size(), 1)
	assert_eq(e.hits.size(), 1)
	assert_eq(s.jams.size(), 1)


func test_a_non_positive_duration_jams_and_reaches_nothing_in_any_set() -> void:
	var e := _enemy(Vector2(5, 0))
	var s := _seeker(Vector2(5, 0), SeekingOrdnance.GROUP)
	assert_eq(EmpPulse.emit(get_tree(), Vector2.ZERO, 190.0, 0.0, null, EmpPulse.TARGET_ALL), 0)
	assert_eq(e.hits.size() + s.jams.size(), 0)
