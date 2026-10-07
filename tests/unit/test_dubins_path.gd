## Unit tests for DubinsPath (global/enemy_ai/dubins_path.gd).
## docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md §3 (task t8b-fighter-run).
extends GutTest

const R := 300.0 / 1.8


## The heading at the end of the last segment, recomputed from the segment geometry rather than
## read back from `end_heading()`.
func _geometric_end_heading(path: DubinsPath) -> float:
	var last: Dictionary = path.segments[-1]
	if last.type == "line":
		return (last.to - last.from).angle()
	return last.start_heading + last.sign * last.angle


func _polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


func test_goal_straight_ahead_is_a_straight_line() -> void:
	var paths := DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(500, 0), 0.0, R)
	assert_false(paths.is_empty())
	assert_almost_eq(paths[0].length, 500.0, 1e-3)
	assert_almost_eq(paths[0].first_arc_angle(), 0.0, 1e-4)


## Boundary: start and goal on one circle — the path is that arc and nothing else.
func test_a_quarter_turn_is_a_single_arc() -> void:
	var paths := DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(R, R), PI / 2.0, R)
	assert_eq(paths[0].kind, "R", "a single clockwise (heading-increasing) arc")
	assert_eq(paths[0].segments.size(), 1)
	assert_almost_eq(paths[0].length, R * PI / 2.0, 1e-3)


func test_candidates_are_sorted_by_length() -> void:
	var paths := DubinsPath.candidates(Vector2(10, 20), 1.0, Vector2(-300, 400), -2.0, R)
	for i in range(1, paths.size()):
		assert_true(paths[i - 1].length <= paths[i].length)


## Every candidate for a spread of seeded pose pairs really ends at the goal pose, and its length
## is the length of the curve it describes.
func test_every_candidate_reaches_the_goal_pose_and_measures_its_own_length() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var checked := 0
	for _pair in 12:
		var p0 := Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var p1 := Vector2(rng.randf_range(-600, 600), rng.randf_range(-600, 600))
		var h0 := rng.randf_range(-PI, PI)
		var h1 := rng.randf_range(-PI, PI)
		for path in DubinsPath.candidates(p0, h0, p1, h1, R):
			var pts := path.sample(1.0)
			assert_lt(pts[-1].distance_to(p1), 1e-3, "%s ends at the goal" % path.kind)
			assert_lt(pts[0].distance_to(p0), 1e-3, "%s starts at the start" % path.kind)
			assert_lt(absf(angle_difference(path.end_heading(), h1)), 1e-4)
			assert_lt(absf(angle_difference(_geometric_end_heading(path), h1)), 1e-4,
				"%s's last segment really ends on the goal heading" % path.kind)
			assert_almost_eq(_polyline_length(pts), path.length, path.length * 0.005 + 0.01,
				"%s's length is its curve's length" % path.kind)
			checked += 1
	assert_gt(checked, 12 * 4, "several candidates per pair were checked")


## The solo fighter's reversal (review N8): the next start is 30 px ahead, facing back.
func test_the_solo_reversal_is_a_short_ccc() -> void:
	var paths := DubinsPath.candidates(Vector2(450, -160), 0.0, Vector2(480, -160), PI, R)
	assert_eq(paths[0].kind.length(), 3)
	assert_false(paths[0].kind.contains("S"), "CCC")
	assert_lte(paths[0].length, 1250.0)


## Boundary: the circle-distance limits of the inner-tangent CSC (≥ 2r) and CCC (≤ 4r) shapes.
func test_shape_availability_follows_the_circle_distance() -> void:
	# Goal 3r ahead on the same heading: the same-side circle centres are 3r apart (≤ 4r).
	var near := _kinds(DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(3.0 * R, 0), 0.0, R))
	assert_true(near.has("RLR") and near.has("LRL"), "CCC exists with centres 3r apart")
	# 5r ahead: same-side centres 5r apart, beyond 4r — no CCC.
	var far := _kinds(DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(5.0 * R, 0), 0.0, R))
	assert_false(far.has("RLR") or far.has("LRL"), "no CCC with centres > 4r apart")
	# Goal 1r ahead, facing back: the opposite-side circles are r apart — no inner-tangent CSC.
	var tight := _kinds(DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(R, 0), PI, R))
	assert_false(tight.has("RSL") or tight.has("LSR"), "no inner tangent with centres < 2r apart")


func test_first_arc_samples_cover_the_first_arc() -> void:
	var path := DubinsPath.candidates(Vector2.ZERO, 0.0, Vector2(R, R), PI / 2.0, R)[0]
	assert_eq(path.first_arc_samples(8.0), int(ceil(R * PI / 2.0 / 8.0)))


func _kinds(paths: Array[DubinsPath]) -> Array[String]:
	var out: Array[String] = []
	for p in paths:
		out.append(p.kind)
	return out
