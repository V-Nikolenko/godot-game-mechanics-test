## Unit tests for the MovementConstraint base (global/enemy_ai/movement_constraint.gd).
## docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6: inner_rect() lets a brain keep an orbit or
## hold-position centre inside the mode's fight area without naming its provider. The identity
## here means "unbounded".
extends GutTest


func test_filter_is_the_identity() -> void:
	var c := MovementConstraint.new()
	assert_eq(c.filter(Vector2(10, 20), Vector2(30, 40)), Vector2(30, 40))


func test_inner_rect_is_empty_for_the_identity() -> void:
	var c := MovementConstraint.new()
	assert_eq(c.inner_rect(), Rect2())
