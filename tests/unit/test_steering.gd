## Unit tests for Steering (global/enemy_ai/steering.gd), the pure movement primitives.
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4 / §4's test_steering.gd row.
extends GutTest


func _target(position: Vector2, velocity: Vector2) -> TargetInfo:
	var body := CharacterBody2D.new()
	add_child_autofree(body)
	body.global_position = position
	body.velocity = velocity
	return TargetInfo.of(body)


func _assert_no_nan(v: Vector2, text: String = "") -> void:
	assert_false(is_nan(v.x) or is_nan(v.y), text)


# ── seek ──────────────────────────────────────────────────────────────────────

func test_seek_returns_full_speed_toward_target() -> void:
	var v := Steering.seek(Vector2.ZERO, Vector2(100.0, 0.0), 200.0)
	assert_eq(v, Vector2(200.0, 0.0))


func test_seek_at_target_is_zero_no_nan() -> void:
	var v := Steering.seek(Vector2(10.0, 10.0), Vector2(10.0, 10.0), 200.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── arrive ────────────────────────────────────────────────────────────────────

func test_arrive_is_zero_at_target() -> void:
	var v := Steering.arrive(Vector2(5.0, 5.0), Vector2(150.0, 0.0), Vector2(5.0, 5.0), 200.0, 50.0)
	assert_eq(v, Vector2.ZERO)


func test_arrive_full_speed_outside_derived_radius() -> void:
	# radius = |vel|^2 / (2*accel) = 150^2 / 100 = 225. 300 > 225.
	var vel := Vector2(150.0, 0.0)
	var accel := 50.0
	var v := Steering.arrive(Vector2.ZERO, vel, Vector2(300.0, 0.0), 200.0, accel)
	assert_almost_eq(v.x, 200.0, 0.01)
	assert_almost_eq(v.y, 0.0, 0.01)


func test_arrive_slows_inside_derived_radius() -> void:
	# radius = 225, distance = 100 < radius -> speed scales linearly with distance/radius.
	var vel := Vector2(150.0, 0.0)
	var accel := 50.0
	var max_speed := 200.0
	var v := Steering.arrive(Vector2.ZERO, vel, Vector2(100.0, 0.0), max_speed, accel)
	var expected_speed := max_speed * (100.0 / 225.0)
	assert_almost_eq(v.x, expected_speed, 0.01)
	assert_almost_eq(v.y, 0.0, 0.01)


func test_arrive_zero_accel_never_slows() -> void:
	var v := Steering.arrive(Vector2.ZERO, Vector2(150.0, 0.0), Vector2(1.0, 0.0), 200.0, 0.0)
	assert_almost_eq(v.x, 200.0, 0.01)


# ── orbit ─────────────────────────────────────────────────────────────────────

func test_orbit_matches_interceptor_formula() -> void:
	var center := Vector2(500.0, 500.0)
	var radius := 130.0
	var angle := 0.3
	var max_correct_speed := 160.0
	var pos := Vector2(500.0, 500.0)

	var anchor := center + Vector2.RIGHT.rotated(angle) * radius
	var to_anchor := anchor - pos
	var expected_speed := clampf(to_anchor.length() * 4.0, 60.0, max_correct_speed)
	var expected := to_anchor.normalized() * expected_speed

	var v := Steering.orbit(pos, center, radius, angle, max_correct_speed)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_orbit_speed_clamped_to_minimum() -> void:
	var center := Vector2.ZERO
	var radius := 130.0
	var angle := 0.0
	var anchor := center + Vector2.RIGHT.rotated(angle) * radius  # (130, 0)
	var pos := anchor - Vector2(5.0, 0.0)  # distance 5 -> dist*4 = 20 < 60
	var v := Steering.orbit(pos, center, radius, angle, 160.0)
	assert_almost_eq(v.length(), 60.0, 0.01)


func test_orbit_speed_clamped_to_maximum() -> void:
	var center := Vector2.ZERO
	var v := Steering.orbit(center, center, 130.0, 0.0, 160.0)
	# pos == center, so dist to anchor == radius (130) -> dist*4 = 520, clamped to 160.
	assert_almost_eq(v.length(), 160.0, 0.01)


func test_orbit_coincident_with_anchor_is_zero_no_nan() -> void:
	var center := Vector2.ZERO
	var anchor := center + Vector2.RIGHT.rotated(0.0) * 130.0
	var v := Steering.orbit(anchor, center, 130.0, 0.0, 160.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── intercept ─────────────────────────────────────────────────────────────────

func test_intercept_seeks_predicted_position() -> void:
	var target := _target(Vector2(100.0, 0.0), Vector2(0.0, 50.0))
	var v := Steering.intercept(Vector2.ZERO, target, 200.0, 1.0)
	var expected := Steering.seek(Vector2.ZERO, Vector2(100.0, 50.0), 200.0)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_intercept_no_target_is_zero_no_nan() -> void:
	var v := Steering.intercept(Vector2.ZERO, TargetInfo.new(), 200.0, 1.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── evade / retreat_from ────────────────────────────────────────────────────

func test_retreat_from_flees_threat_directly() -> void:
	var v := Steering.retreat_from(Vector2.ZERO, Vector2(50.0, 0.0), 100.0)
	assert_almost_eq(v.x, -100.0, 0.01)
	assert_almost_eq(v.y, 0.0, 0.01)


func test_evade_flees_predicted_threat_position() -> void:
	var v := Steering.evade(Vector2.ZERO, Vector2(100.0, 0.0), Vector2(50.0, 0.0), 200.0, 1.0)
	# predicted threat position = (150, 0) -> flee directly away.
	assert_almost_eq(v.x, -200.0, 0.01)
	assert_almost_eq(v.y, 0.0, 0.01)


func test_retreat_from_coincident_is_zero_no_nan() -> void:
	var v := Steering.retreat_from(Vector2(10.0, 10.0), Vector2(10.0, 10.0), 100.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── strafe ────────────────────────────────────────────────────────────────────

func test_strafe_is_perpendicular_side_positive() -> void:
	var v := Steering.strafe(Vector2.ZERO, Vector2(100.0, 0.0), 1.0, 50.0)
	assert_almost_eq(v.dot(Vector2(1.0, 0.0)), 0.0, 0.001)
	assert_almost_eq(v.length(), 50.0, 0.01)


func test_strafe_side_values_are_opposite() -> void:
	var positive := Steering.strafe(Vector2.ZERO, Vector2(100.0, 0.0), 1.0, 50.0)
	var negative := Steering.strafe(Vector2.ZERO, Vector2(100.0, 0.0), -1.0, 50.0)
	assert_almost_eq(positive.x, -negative.x, 0.001)
	assert_almost_eq(positive.y, -negative.y, 0.001)


func test_strafe_coincident_is_zero_no_nan() -> void:
	var v := Steering.strafe(Vector2(10.0, 10.0), Vector2(10.0, 10.0), 1.0, 50.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── hold_position ─────────────────────────────────────────────────────────────

func test_hold_position_is_zero_inside_tolerance() -> void:
	var v := Steering.hold_position(Vector2(5.0, 0.0), Vector2.ZERO, Vector2.ZERO, 10.0, 100.0, 50.0)
	assert_eq(v, Vector2.ZERO)


func test_hold_position_arrives_outside_tolerance() -> void:
	var v := Steering.hold_position(Vector2(50.0, 0.0), Vector2.ZERO, Vector2.ZERO, 10.0, 100.0, 50.0)
	var expected := Steering.arrive(Vector2(50.0, 0.0), Vector2.ZERO, Vector2.ZERO, 100.0, 50.0)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_hold_position_at_exact_tolerance_boundary_is_zero() -> void:
	var v := Steering.hold_position(Vector2(10.0, 0.0), Vector2.ZERO, Vector2.ZERO, 10.0, 100.0, 50.0)
	assert_eq(v, Vector2.ZERO)


# ── drift ─────────────────────────────────────────────────────────────────────

func test_drift_is_constant_velocity() -> void:
	var v := Steering.drift(Vector2(3.0, 4.0), 50.0)
	assert_almost_eq(v.x, 30.0, 0.01)
	assert_almost_eq(v.y, 40.0, 0.01)


func test_drift_zero_direction_is_zero_no_nan() -> void:
	var v := Steering.drift(Vector2.ZERO, 50.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)
