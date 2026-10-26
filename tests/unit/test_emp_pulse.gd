## EmpPulse (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.8): the one EMP entry point. In Phase 7 it reaches only
## nodes in group `player`, by centre distance (<= radius), through the duck-typed `apply_emp(seconds, source)`.
## Intent tests; Phase 9 extends the target set (enemies) and flips the last row.
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
