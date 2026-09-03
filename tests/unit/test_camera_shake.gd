## Characterization tests for the CameraShake autoload (trauma model).
extends GutTest

const CameraShakeScript := preload("res://global/systems/camera_shake.gd")

const MAX_OFFSET := 8.0
const DECAY := 1.5


## Tree-less instance so `_process` only advances when this test calls it.
func _fresh() -> Node:
	return CameraShakeScript.new()


func test_no_trauma_means_no_offset() -> void:
	var cs := _fresh()
	assert_eq(cs.get_offset(), Vector2.ZERO)
	cs.free()


func test_offset_is_bounded_by_the_quadratic_curve() -> void:
	var cs := _fresh()
	cs.add(0.5)
	## visible shake = trauma^2 * MAX_OFFSET, and each axis is in [-1, 1].
	var limit: float = MAX_OFFSET * 0.25
	for _i in 20:
		var off: Vector2 = cs.get_offset()
		assert_between(off.x, -limit, limit, "x stays inside the quadratic envelope")
		assert_between(off.y, -limit, limit, "y stays inside the quadratic envelope")
	cs.free()


func test_trauma_saturates_at_one() -> void:
	var cs := _fresh()
	cs.add(0.9)
	cs.add(0.9)
	assert_eq(cs._trauma, 1.0, "stacked shakes never exceed the visual cap")
	for _i in 20:
		var off: Vector2 = cs.get_offset()
		assert_between(off.x, -MAX_OFFSET, MAX_OFFSET)
		assert_between(off.y, -MAX_OFFSET, MAX_OFFSET)
	cs.free()


func test_negative_trauma_clamps_to_zero() -> void:
	var cs := _fresh()
	cs.add(0.4)
	cs.add(-10.0)
	assert_eq(cs._trauma, 0.0)
	assert_eq(cs.get_offset(), Vector2.ZERO)
	cs.free()


func test_trauma_decays_linearly() -> void:
	var cs := _fresh()
	cs.add(1.0)
	cs._process(0.2)
	assert_almost_eq(cs._trauma, 1.0 - DECAY * 0.2, 0.0001)
	cs._process(0.2)
	assert_almost_eq(cs._trauma, 1.0 - DECAY * 0.4, 0.0001)
	cs.free()


func test_full_trauma_decays_away_within_two_thirds_of_a_second() -> void:
	var cs := _fresh()
	cs.add(1.0)
	cs._process(1.0 / DECAY)
	assert_eq(cs._trauma, 0.0, "1.0 trauma at 1.5/s is gone after ~0.67 s")
	assert_eq(cs.get_offset(), Vector2.ZERO)
	cs.free()


func test_decay_never_goes_negative() -> void:
	var cs := _fresh()
	cs.add(0.1)
	cs._process(10.0)
	assert_eq(cs._trauma, 0.0)
	cs._process(10.0)
	assert_eq(cs._trauma, 0.0)
	cs.free()
