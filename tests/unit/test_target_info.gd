## Unit tests for TargetInfo (global/enemy_ai/target_info.gd), the one snapshot of a target's
## position/velocity/facing plus its intercept math. Every case in
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §4's test_target_info.gd row.
extends GutTest


func test_no_target_reports_false_and_aims_down() -> void:
	var info := TargetInfo.new()
	assert_false(info.has_target)
	assert_eq(info.aim_direction(Vector2.ZERO, 250.0, 1.0), Vector2.DOWN)


func test_predicted_position_at_zero_is_position() -> void:
	var info := TargetInfo.of(_make_body(Vector2(100.0, 50.0), Vector2(30.0, -10.0)))
	assert_eq(info.predicted_position(0.0), info.position)


func test_stationary_target_intercept_ok_time_is_distance_over_speed() -> void:
	var info := TargetInfo.of(_make_body(Vector2(300.0, 0.0), Vector2.ZERO))
	var result := info.intercept(Vector2.ZERO, 150.0)
	assert_true(result.ok)
	assert_almost_eq(result.time, 300.0 / 150.0, 0.0001)
	assert_eq(result.point, Vector2(300.0, 0.0))


func test_target_outrunning_shot_has_no_intercept() -> void:
	## Moving directly away faster than the shot: no t >= 0 solves the closed-form quadratic.
	var info := TargetInfo.of(_make_body(Vector2(300.0, 0.0), Vector2(400.0, 0.0)))
	var result := info.intercept(Vector2.ZERO, 150.0)
	assert_false(result.ok)
	assert_eq(result.point, info.position)


func test_zero_shot_speed_is_never_ok() -> void:
	var info := TargetInfo.of(_make_body(Vector2(300.0, 0.0), Vector2.ZERO))
	var result := info.intercept(Vector2.ZERO, 0.0)
	assert_false(result.ok)


func test_target_at_shooter_position_intercepts_at_time_zero_with_no_nan() -> void:
	var info := TargetInfo.of(_make_body(Vector2(50.0, 50.0), Vector2(20.0, 0.0)))
	var result: Dictionary = info.intercept(Vector2(50.0, 50.0), 150.0)
	assert_true(result.ok)
	assert_almost_eq(result.time, 0.0, 0.0001)
	assert_false(is_nan(result.point.x) or is_nan(result.point.y))


func test_accuracy_blends_direct_and_intercept_aim() -> void:
	# A target crossing directly in front of the shooter has a real, distinct intercept point,
	# so direct/midpoint/intercept aim are three different directions.
	var info := TargetInfo.of(_make_body(Vector2(0.0, -200.0), Vector2(200.0, 0.0)))
	var from := Vector2.ZERO
	var shot_speed := 250.0
	var result := info.intercept(from, shot_speed)
	assert_true(result.ok, "precondition: this setup must have a real intercept solution")

	var direct := info.aim_direction(from, shot_speed, 0.0)
	var full_intercept := info.aim_direction(from, shot_speed, 1.0)
	var midpoint := info.aim_direction(from, shot_speed, 0.5)

	assert_eq(direct, (info.position - from).normalized())
	assert_eq(full_intercept, (result.point - from).normalized())
	var expected_midpoint: Vector2 = info.position.lerp(result.point, 0.5) - from
	assert_eq(midpoint, expected_midpoint.normalized())
	assert_ne(direct, full_intercept, "the setup must make direct and intercept aim differ")


func test_failed_intercept_falls_back_to_direct_aim_at_every_accuracy() -> void:
	var info := TargetInfo.of(_make_body(Vector2(300.0, 0.0), Vector2(400.0, 0.0)))
	var from := Vector2.ZERO
	var direct := (info.position - from).normalized()
	assert_eq(info.aim_direction(from, 150.0, 0.0), direct)
	assert_eq(info.aim_direction(from, 150.0, 0.5), direct)
	assert_eq(info.aim_direction(from, 150.0, 1.0), direct)


func test_target_freed_after_snapshot_is_safe_to_read() -> void:
	var body := _make_body(Vector2(10.0, 20.0), Vector2(5.0, 0.0))
	var info := TargetInfo.of(body)
	body.queue_free()
	await get_tree().process_frame
	assert_true(info.has_target)
	assert_eq(info.position, Vector2(10.0, 20.0))
	assert_eq(info.aim_direction(Vector2.ZERO, 250.0, 0.0), Vector2(10.0, 20.0).normalized())


func test_of_null_or_freed_node_reports_no_target() -> void:
	assert_false(TargetInfo.of(null).has_target)


func test_player_resolver_finds_no_target_with_no_player_in_tree() -> void:
	var info := TargetInfo.player(get_tree())
	assert_false(info.has_target)


func test_player_resolver_snapshots_the_grouped_player_node() -> void:
	var body := _make_body(Vector2(40.0, -10.0), Vector2(0.0, 60.0))
	body.add_to_group(&"player")
	var info := TargetInfo.player(get_tree())
	assert_true(info.has_target)
	assert_eq(info.position, Vector2(40.0, -10.0))
	assert_eq(info.velocity, Vector2(0.0, 60.0))


func test_of_reads_velocity_only_from_character_body_2d() -> void:
	var node := Node2D.new()
	add_child_autofree(node)
	node.global_position = Vector2(5.0, 5.0)
	var info := TargetInfo.of(node)
	assert_true(info.has_target)
	assert_eq(info.velocity, Vector2.ZERO)


func test_facing_matches_the_project_up_is_forward_convention() -> void:
	var body := _make_body(Vector2.ZERO, Vector2.ZERO)
	body.rotation = PI / 2.0
	var info := TargetInfo.of(body)
	assert_almost_eq(info.facing.x, Vector2.UP.rotated(PI / 2.0).x, 0.0001)
	assert_almost_eq(info.facing.y, Vector2.UP.rotated(PI / 2.0).y, 0.0001)


func test_distance_from_and_relative_angle_from() -> void:
	var info := TargetInfo.of(_make_body(Vector2(100.0, 0.0), Vector2.ZERO))
	assert_almost_eq(info.distance_from(Vector2.ZERO), 100.0, 0.0001)
	# Target is straight along +X from the origin; facing +X means zero relative angle.
	assert_almost_eq(info.relative_angle_from(Vector2.ZERO, Vector2.RIGHT), 0.0, 0.0001)


func test_line_of_sight_stub_agrees_with_has_target() -> void:
	assert_false(TargetInfo.new().line_of_sight(Vector2.ZERO))
	var info := TargetInfo.of(_make_body(Vector2.ONE, Vector2.ZERO))
	assert_true(info.line_of_sight(Vector2.ZERO))


func _make_body(pos: Vector2, vel: Vector2) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	add_child_autofree(body)
	body.global_position = pos
	body.velocity = vel
	return body
