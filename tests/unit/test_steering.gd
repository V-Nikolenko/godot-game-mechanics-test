## Unit tests for Steering (global/enemy_ai/steering.gd), the pure movement primitives.
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4 / §4's test_steering.gd row.
## Phase 2 additions (spiral, corkscrew, formation_slot, separation, alignment, cohesion,
## clamped_lead_time, turn_toward): docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.2 / §4.
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


# ── break_contact (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.2.1) ───────────────────

func test_break_contact_grows_distance_to_a_stationary_threat_every_step() -> void:
	var threat := Vector2.ZERO
	var pos := Vector2(200.0, 0.0)
	var dt := 1.0 / 60.0
	var previous := pos.distance_to(threat)
	for i in 120:
		pos += Steering.break_contact(pos, threat, Vector2.ZERO, 1.0, 300.0) * dt
		var dist := pos.distance_to(threat)
		assert_gt(dist, previous, "step %d must open the distance" % i)
		previous = dist


func test_break_contact_returns_exactly_max_speed() -> void:
	for threat_vel in [Vector2.ZERO, Vector2(-80.0, 0.0), Vector2(80.0, 30.0)]:
		var v := Steering.break_contact(Vector2(100.0, 40.0), Vector2.ZERO, threat_vel, 1.0, 275.0)
		assert_almost_eq(v.length(), 275.0, 0.01)


func test_break_contact_side_mirrors_the_lateral_component() -> void:
	var left := Steering.break_contact(Vector2(100.0, 0.0), Vector2.ZERO, Vector2.ZERO, 1.0, 100.0)
	var right := Steering.break_contact(Vector2(100.0, 0.0), Vector2.ZERO, Vector2.ZERO, -1.0, 100.0)
	assert_almost_eq(left.x, right.x, 0.001, "the away component is the same either side")
	assert_almost_eq(left.y, -right.y, 0.001, "the lateral component mirrors")
	assert_ne(signf(left.y), 0.0)


func test_break_contact_closing_threat_roughly_doubles_the_lateral_share() -> void:
	var pos := Vector2(100.0, 0.0)
	# Threat at the origin; away = +X. A velocity along +X is closing, along -X is opening.
	var closing := Steering.break_contact(pos, Vector2.ZERO, Vector2(50.0, 0.0), 1.0, 100.0)
	var opening := Steering.break_contact(pos, Vector2.ZERO, Vector2(-50.0, 0.0), 1.0, 100.0)
	# |y / x| of the heading is the lateral weight: 0.6 opening, 1.2 closing.
	assert_almost_eq(absf(opening.y / opening.x), 0.6, 0.001)
	assert_almost_eq(absf(closing.y / closing.x), 1.2, 0.001)


func test_break_contact_lateral_weight_is_a_parameter() -> void:
	var v := Steering.break_contact(Vector2(100.0, 0.0), Vector2.ZERO, Vector2.ZERO, 1.0, 100.0, 0.0)
	assert_almost_eq(v.y, 0.0, 0.001, "no lateral weight flees straight down the line")


func test_break_contact_zero_distance_is_finite_and_max_speed_long() -> void:
	var p := Vector2(10.0, 10.0)
	for threat_vel in [Vector2.ZERO, Vector2(0.0, 90.0)]:
		var v := Steering.break_contact(p, p, threat_vel, 1.0, 240.0)
		_assert_no_nan(v)
		assert_almost_eq(v.length(), 240.0, 0.01, "finite vector of max_speed length")


func test_break_contact_zero_distance_leaves_across_the_threat_velocity() -> void:
	var p := Vector2(10.0, 10.0)
	var v := Steering.break_contact(p, p, Vector2(0.0, 90.0), 1.0, 100.0)
	assert_almost_eq(v.dot(Vector2(0.0, 1.0)), 0.0, 0.01, "orthogonal to the threat's velocity")


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


# ── spiral ────────────────────────────────────────────────────────────────────

func test_spiral_combines_orbit_and_radial_term() -> void:
	var center := Vector2(500.0, 500.0)
	var radius := 130.0
	var angle := 0.3
	var pos := center + Vector2(20.0, 0.0)
	var expected := Steering.orbit(pos, center, radius, angle, 160.0) + (pos - center).normalized() * -40.0
	var v := Steering.spiral(pos, center, radius, angle, -40.0, 160.0)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_spiral_holds_radius_when_rate_zero() -> void:
	var center := Vector2(500.0, 500.0)
	var radius := 130.0
	var angle := 0.4
	var pos := center + Vector2.RIGHT.rotated(angle) * radius
	var v := Steering.spiral(pos, center, radius, angle, 0.0, 160.0)
	assert_eq(v, Vector2.ZERO)


func test_spiral_shrinks_inward_when_rate_negative() -> void:
	var center := Vector2(500.0, 500.0)
	var radius := 130.0
	var angle := 0.4
	var pos := center + Vector2.RIGHT.rotated(angle) * radius
	var v := Steering.spiral(pos, center, radius, angle, -50.0, 160.0)
	var expected := (center - pos).normalized() * 50.0
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)
	assert_true(v.length() > 0.0)
	_assert_no_nan(v)


# ── corkscrew ─────────────────────────────────────────────────────────────────

func test_corkscrew_adds_perpendicular_sinusoid() -> void:
	var forward := Vector2(1.0, 0.0)
	var v := Steering.corkscrew(Vector2.ZERO, forward, 100.0, 30.0, PI / 2.0)
	assert_almost_eq(v.x, 100.0, 0.01)
	assert_almost_eq(v.y, 30.0, 0.01)


func test_corkscrew_mean_heading_matches_forward_over_one_period() -> void:
	var forward := Vector2(1.0, 0.0)
	var speed := 100.0
	var amplitude := 30.0
	var samples := 8
	var total := Vector2.ZERO
	for i in samples:
		var phase := (float(i) / float(samples)) * TAU
		total += Steering.corkscrew(Vector2.ZERO, forward, speed, amplitude, phase)
	var mean := total / float(samples)
	assert_almost_eq(mean.x, speed, 0.01)
	assert_almost_eq(mean.y, 0.0, 0.01)


func test_corkscrew_zero_forward_is_zero_no_nan() -> void:
	var v := Steering.corkscrew(Vector2.ZERO, Vector2.ZERO, 100.0, 30.0, 1.0)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── formation_slot ────────────────────────────────────────────────────────────

func test_formation_slot_offset_rotates_with_heading() -> void:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var anchor := Vector2.ZERO
	var heading := Vector2(0.0, 1.0)
	var slot_offset := Vector2(50.0, 0.0)
	var v := Steering.formation_slot(pos, vel, anchor, heading, slot_offset, 200.0, 50.0)
	var expected_target := anchor + slot_offset.rotated(heading.angle())
	var expected := Steering.arrive(pos, vel, expected_target, 200.0, 50.0)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_formation_slot_zero_offset_is_arrive_at_anchor() -> void:
	var pos := Vector2(505.0, 5.0)
	var vel := Vector2.ZERO
	var anchor := Vector2(500.0, 0.0)
	var heading := Vector2(1.0, 0.0)
	var v := Steering.formation_slot(pos, vel, anchor, heading, Vector2.ZERO, 200.0, 50.0)
	var expected := Steering.arrive(pos, vel, anchor, 200.0, 50.0)
	assert_almost_eq(v.x, expected.x, 0.01)
	assert_almost_eq(v.y, expected.y, 0.01)


func test_formation_slot_stops_at_slot() -> void:
	var anchor := Vector2(500.0, 0.0)
	var heading := Vector2(1.0, 0.0)
	var slot_offset := Vector2(50.0, 0.0)
	var pos := anchor + slot_offset.rotated(heading.angle())
	var v := Steering.formation_slot(pos, Vector2.ZERO, anchor, heading, slot_offset, 200.0, 50.0)
	assert_eq(v, Vector2.ZERO)


# ── separation ────────────────────────────────────────────────────────────────

func test_separation_pushes_away_from_close_neighbour() -> void:
	var pos := Vector2.ZERO
	var neighbours: Array[Vector2] = [Vector2(10.0, 0.0)]
	var v := Steering.separation(pos, neighbours, 50.0)
	assert_true(v.x < 0.0)
	assert_almost_eq(v.y, 0.0, 0.01)


func test_separation_ignores_neighbour_outside_radius() -> void:
	var pos := Vector2.ZERO
	var neighbours: Array[Vector2] = [Vector2(1000.0, 0.0)]
	var v := Steering.separation(pos, neighbours, 50.0)
	assert_eq(v, Vector2.ZERO)


func test_separation_zero_with_no_neighbours() -> void:
	var neighbours: Array[Vector2] = []
	var v := Steering.separation(Vector2.ZERO, neighbours, 50.0)
	assert_eq(v, Vector2.ZERO)


func test_separation_finite_with_coincident_neighbour() -> void:
	var pos := Vector2(10.0, 10.0)
	var neighbours: Array[Vector2] = [Vector2(10.0, 10.0)]
	var v := Steering.separation(pos, neighbours, 50.0)
	_assert_no_nan(v)
	assert_true(v.length() > 0.0)


# ── alignment ─────────────────────────────────────────────────────────────────

func test_alignment_is_mean_neighbour_velocity() -> void:
	var neighbour_vels: Array[Vector2] = [Vector2(100.0, 0.0), Vector2(0.0, 100.0)]
	var v := Steering.alignment(Vector2.ZERO, neighbour_vels)
	assert_almost_eq(v.x, 50.0, 0.01)
	assert_almost_eq(v.y, 50.0, 0.01)


func test_alignment_zero_with_no_neighbours_no_nan() -> void:
	var neighbour_vels: Array[Vector2] = []
	var v := Steering.alignment(Vector2(10.0, 0.0), neighbour_vels)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── cohesion ──────────────────────────────────────────────────────────────────

func test_cohesion_toward_centroid() -> void:
	var pos := Vector2.ZERO
	var neighbours: Array[Vector2] = [Vector2(100.0, 0.0), Vector2(0.0, 100.0)]
	var v := Steering.cohesion(pos, neighbours)
	assert_almost_eq(v.x, 50.0, 0.01)
	assert_almost_eq(v.y, 50.0, 0.01)


func test_cohesion_zero_with_no_neighbours_no_nan() -> void:
	var neighbours: Array[Vector2] = []
	var v := Steering.cohesion(Vector2(10.0, 10.0), neighbours)
	assert_eq(v, Vector2.ZERO)
	_assert_no_nan(v)


# ── clamped_lead_time ─────────────────────────────────────────────────────────

func test_clamped_lead_time_normal_case() -> void:
	var t := Steering.clamped_lead_time(300.0, 500.0, 0.4, 0.8)
	assert_almost_eq(t, 0.6, 0.001)


func test_clamped_lead_time_clamps_at_lower_bound() -> void:
	var t := Steering.clamped_lead_time(10.0, 1000.0, 0.4, 0.8)
	assert_almost_eq(t, 0.4, 0.001)


func test_clamped_lead_time_clamps_at_upper_bound() -> void:
	var t := Steering.clamped_lead_time(10000.0, 100.0, 0.4, 0.8)
	assert_almost_eq(t, 0.8, 0.001)


func test_clamped_lead_time_zero_speed_is_t_min() -> void:
	var t := Steering.clamped_lead_time(100.0, 0.0, 0.4, 0.8)
	assert_almost_eq(t, 0.4, 0.001)


func test_clamped_lead_time_negative_speed_is_t_min() -> void:
	var t := Steering.clamped_lead_time(100.0, -5.0, 0.4, 0.8)
	assert_almost_eq(t, 0.4, 0.001)


# ── turn_toward ───────────────────────────────────────────────────────────────

func test_turn_toward_turns_by_exactly_max_rate_delta_when_far() -> void:
	var current := Vector2(1.0, 0.0)
	var desired := Vector2(0.0, 1.0)
	var max_rate := 1.0
	var delta := 0.1
	var v := Steering.turn_toward(current, desired, max_rate, delta)
	var angle_turned: float = current.angle_to(v)
	assert_almost_eq(angle_turned, max_rate * delta, 0.0001)
	assert_almost_eq(v.length(), 1.0, 0.0001)


func test_turn_toward_lands_exactly_on_target_within_one_step() -> void:
	var current := Vector2(1.0, 0.0)
	var desired := Vector2(0.0, 1.0)
	var v := Steering.turn_toward(current, desired, 100.0, 1.0)
	assert_almost_eq(v.x, desired.x, 0.0001)
	assert_almost_eq(v.y, desired.y, 0.0001)


func test_turn_toward_takes_short_way_across_pi() -> void:
	var current := Vector2(-1.0, -0.01).normalized()
	var desired := Vector2(-1.0, 0.01).normalized()
	var v := Steering.turn_toward(current, desired, 10.0, 0.1)
	var turned: float = current.angle_to(v)
	assert_true(absf(turned) < 0.1)


func test_turn_toward_zero_current_returns_desired() -> void:
	var v := Steering.turn_toward(Vector2.ZERO, Vector2(3.0, 4.0), 1.0, 0.1)
	assert_almost_eq(v.x, 0.6, 0.0001)
	assert_almost_eq(v.y, 0.8, 0.0001)


func test_turn_toward_zero_desired_returns_current() -> void:
	var current := Vector2(0.6, 0.8)
	var v := Steering.turn_toward(current, Vector2.ZERO, 1.0, 0.1)
	assert_almost_eq(v.x, 0.6, 0.0001)
	assert_almost_eq(v.y, 0.8, 0.0001)


func test_turn_toward_always_unit_length() -> void:
	var current := Vector2(2.0, 0.0)
	var v := Steering.turn_toward(current, Vector2(0.0, 5.0), 0.5, 0.1)
	assert_almost_eq(v.length(), 1.0, 0.0001)
