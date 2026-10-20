## INTENT tests for `Steering.context_avoid()` (`global/enemy_ai/steering.gd`): the pure context-steering stage
## `EnemyMover` runs between the slow and the accel limit (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md §2.4;
## task plan docs/plans/cmvg30aa90073qs2xrw74hcvg/3-plan.md, which records the four refinements).
##
## No node, no registry: every case builds `HazardInfo`s by hand and, where a path matters, integrates the
## returned velocity at a fixed `DT` the way the mover would — feeding each step's direction back as `prev_dir`.
extends GutTest

const DT := 1.0 / 60.0
const SLOT := TAU / Steering.CONTEXT_SLOTS


func _info(at: Vector2, radius: float, weight: float = 1.0, velocity: Vector2 = Vector2.ZERO) -> HazardInfo:
	var i := HazardInfo.new()
	i.position = at
	i.radius = radius
	i.avoid_weight = weight
	i.velocity = velocity
	return i


func _avoid(pos: Vector2, desired: Vector2, infos: Array, avoidance: float = 1.0, margin: float = 60.0,
		prev_dir: Vector2 = Vector2.ZERO) -> Vector2:
	return Steering.context_avoid(pos, desired, infos, avoidance, margin, Steering.CONTEXT_LOOKAHEAD, prev_dir)


## Seeks `target` at `speed` for `seconds`, avoiding through `infos`. Returns the run's log: the closest
## approach to any hazard's edge, the lowest speed ratio, whether every step returned `desired` bit-identical,
## the step `target` was reached on (-1 if never), and every output velocity.
func _fly(start: Vector2, target: Vector2, speed: float, infos: Array, avoidance: float, margin: float,
		seconds: float) -> Dictionary:
	var pos := start
	var prev := Vector2.ZERO
	var log := {"min_edge": INF, "min_ratio": INF, "untouched": true, "reached": -1, "outs": [], "at": []}
	for step in int(seconds / DT):
		if pos.distance_to(target) < 6.0:
			log.reached = step
			break
		var desired := (target - pos).normalized() * speed
		var out := _avoid(pos, desired, infos, avoidance, margin, prev)
		if var_to_bytes(out) != var_to_bytes(desired):
			log.untouched = false
		log.min_ratio = minf(log.min_ratio, out.length() / speed)
		log.outs.append(out)
		log.at.append(pos)
		prev = out.normalized()
		pos += out * DT
		for info in infos:
			log.min_edge = minf(log.min_edge, pos.distance_to(info.position) - info.radius)
	return log


# ── Pass-through ───────────────────────────────────────────────────────────────

func test_no_info_returns_desired_unchanged() -> void:
	for desired in [Vector2(120.0, -40.0), -Vector2(200.0, 0.0), Vector2.ZERO]:
		for prev in [Vector2.ZERO, Vector2.UP]:
			var out := _avoid(Vector2(10.0, 20.0), desired, [], 1.0, 60.0, prev)
			assert_eq(var_to_bytes(out), var_to_bytes(desired), "%s (prev %s): bit-identical, -0.0 included" % [desired, prev])


## Every way the danger map can come out all-zero: out of the skirt, `avoid_weight` 0, `avoidance` 0, and a
## soft profile's threshold wiping a glancing danger. Plus the clear-way rule (refinement 4): a hazard behind
## the ship puts danger on other slots only, and the heading is left exactly as the brain asked.
func test_zero_danger_returns_desired_unchanged() -> void:
	var pos := Vector2.ZERO
	var desired := Vector2(300.0, 0.0)  # skirt reach M = 60 + 300 * 0.6 = 240 px beyond the edge
	var cases := {
		"beyond the skirt": [[_info(Vector2(500.0, 0.0), 100.0)], 1.0],
		"avoid_weight 0": [[_info(Vector2(150.0, 0.0), 100.0, 0.0)], 1.0],
		"avoidance 0": [[_info(Vector2(150.0, 0.0), 100.0)], 0.0],
		"under a soft threshold": [[_info(Vector2(0.0, 200.0), 100.0)], 0.5],
		"behind the ship": [[_info(Vector2(-200.0, 0.0), 100.0)], 1.0],
	}
	for label in cases:
		var out := _avoid(pos, desired, cases[label][0], cases[label][1])
		assert_eq(var_to_bytes(out), var_to_bytes(desired), "%s: bit-identical" % label)
	var neg := -Vector2(200.0, 0.0)
	var out_neg := _avoid(pos, neg, [_info(Vector2(200.0, 0.0), 100.0)], 1.0)
	assert_eq(var_to_bytes(out_neg), var_to_bytes(neg), "-0.0 survives a hazard behind the ship")
	# On a slot other than 0 (review m1): `angle()` of an exact +y request is a hair off slot 4, and a hazard at 150°
	# puts danger on slot 5 (and beyond) but none on slot 4. Slot 4 alone brackets it: a clear way, bit for bit.
	var down := Vector2(0.0, 300.0)
	var beside := _info(Vector2.from_angle(deg_to_rad(150.0)) * 250.0, 60.0)
	assert_ne(var_to_bytes(_avoid(pos, Vector2.from_angle(deg_to_rad(112.5)) * 300.0, [beside])),
		var_to_bytes(Vector2.from_angle(deg_to_rad(112.5)) * 300.0), "sanity: the 112.5° slot is dangerous")
	assert_eq(var_to_bytes(_avoid(pos, down, [beside])), var_to_bytes(down), "+y, on slot 4: bit-identical")


# ── Going round ────────────────────────────────────────────────────────────────

## Failure mode 2 (research): context steering that sticks when the target is straight behind an obstacle.
func test_a_target_straight_behind_a_well_is_reached_round_the_edge() -> void:
	var log := _fly(Vector2(-300.0, 0.0), Vector2(300.0, 0.0), 300.0, [_info(Vector2.ZERO, 120.0)], 1.0, 60.0, 4.0)
	assert_gt(log.min_edge, 0.0, "never inside the radius")
	assert_gte(log.min_ratio, Steering.CONTEXT_MIN_SPEED_RATIO - 0.0001, "never below 35 % of the desired speed")
	assert_gt(log.reached, 0, "reached the target on the far side within 4 s")


func test_inside_the_first_step_points_outward() -> void:
	var centre := Vector2(40.0, -30.0)
	var radius := 120.0
	var infos := [_info(centre, radius)]
	var worst := INF
	for offset in [Vector2(50.0, 10.0), Vector2(0.0, -100.0), Vector2(-80.0, 60.0), Vector2(115.0, 0.0), Vector2(3.0, 2.0)]:
		var pos: Vector2 = centre + offset
		var headings: Array = [centre - pos]  # straight through the centre
		for k in Steering.CONTEXT_SLOTS:
			headings.append(Vector2.from_angle(k * SLOT + 0.1))
			headings.append(Vector2.from_angle(k * SLOT))
		for h in headings:
			var out := _avoid(pos, (h as Vector2).normalized() * 200.0, infos)
			var outward := out.normalized().dot((pos - centre).normalized())
			worst = minf(worst, outward)
			assert_gt(outward, 0.0, "inside at %s heading %s: steps outward (got %s)" % [offset, h, out])
			assert_gte(out.length(), 200.0 * Steering.CONTEXT_MIN_SPEED_RATIO - 0.0001, "and keeps moving")
	assert_gt(worst, 0.1, "never a near-tangent step: worst outward share %.3f" % worst)


## The margin is the skim knob (plan §2.4): a Swarm Drone's 12 px runs along the edge, a Sniper's 90 px keeps clear.
func test_a_narrow_margin_skims_closer_than_a_wide_one() -> void:
	var well := [_info(Vector2.ZERO, 120.0)]
	var narrow := _fly(Vector2(-300.0, 0.0), Vector2(300.0, 0.0), 300.0, well, 1.0, 12.0, 4.0)
	var wide := _fly(Vector2(-300.0, 0.0), Vector2(300.0, 0.0), 300.0, well, 1.0, 90.0, 4.0)
	assert_gt(narrow.min_edge, 0.0, "the skimmer still never enters")
	assert_lt(narrow.min_edge, 60.0, "margin 12 passes within 60 px of the edge (%.1f)" % narrow.min_edge)
	assert_gt(wide.min_edge, narrow.min_edge + 40.0,
		"margin 90 keeps well clear (%.1f vs %.1f)" % [wide.min_edge, narrow.min_edge])


## R6.8: a 0.5-avoidance ship ignores glancing danger and reacts only when heading squarely in. The line runs
## exactly along slot 0 with danger on slot 1 for part of it, so this also pins the clear-way rule's on-slot case
## (a heading exactly on a slot needs only that slot clear; checking the next one too bent it by float noise).
func test_half_avoidance_ignores_a_tangential_pass_that_full_avoidance_bends_round() -> void:
	var well := [_info(Vector2.ZERO, 120.0)]
	var soft := _fly(Vector2(-400.0, -150.0), Vector2(400.0, -150.0), 300.0, well, 0.5, 60.0, 4.0)
	var full := _fly(Vector2(-400.0, -150.0), Vector2(400.0, -150.0), 300.0, well, 1.0, 60.0, 4.0)
	assert_true(soft.untouched, "avoidance 0.5: every step is the brain's own velocity, bit for bit")
	assert_almost_eq(soft.min_edge, 30.0, 0.5, "so it passes 30 px off the edge, on its line")
	assert_false(full.untouched, "avoidance 1.0 bends")
	assert_gt(full.min_edge, soft.min_edge + 30.0, "round, wider (%.1f vs %.1f)" % [full.min_edge, soft.min_edge])
	assert_gt(soft.reached, 0, "both still arrive")
	assert_gt(full.reached, 0)


## R6.8's other half: a soft profile still reacts when it is heading squarely in. From inside a well's skirt,
## straight at its centre, a 0.5 ship is deflected on the first step and its run never comes within half a radius
## of the centre, where an unavoiding ship flies straight through it.
func test_soft_avoidance_still_turns_off_a_run_aimed_squarely_at_the_centre() -> void:
	var radius := 120.0
	var well := [_info(Vector2.ZERO, radius)]
	var desired := Vector2(300.0, 0.0)
	var first := _avoid(Vector2(-200.0, 0.0), desired, well, 0.5)
	assert_gt(absf(first.normalized().y), 0.1, "0.5: the first step already turns off the centre line (%s)" % first)
	var soft := _fly(Vector2(-400.0, 0.0), Vector2(400.0, 0.0), 300.0, well, 0.5, 60.0, 5.0)
	var none := _fly(Vector2(-400.0, 0.0), Vector2(400.0, 0.0), 300.0, well, 0.0, 60.0, 5.0)
	assert_almost_eq(none.min_edge, -radius, 0.001, "control: avoidance 0 flies through the centre")
	assert_gt(soft.min_edge, -0.5 * radius, "0.5 stays more than half a radius off the centre (%.1f)" % soft.min_edge)
	assert_gt(soft.reached, 0, "and still arrives")


## The threshold is graded, `1 − avoidance`, not a switch: on the same tangential line a 0.8 ship bends where a
## 0.5 ship does not, and a little further out it ignores what a 1.0 ship still bends round. (Subtracting
## `avoidance` itself, or turning avoidance off below 1.0, fails one of the two.)
func test_a_0_8_profile_sits_between_0_5_and_1_0() -> void:
	var well := [_info(Vector2.ZERO, 120.0)]
	var near_soft := _fly(Vector2(-400.0, -170.0), Vector2(400.0, -170.0), 300.0, well, 0.5, 60.0, 4.0)
	var near_mid := _fly(Vector2(-400.0, -170.0), Vector2(400.0, -170.0), 300.0, well, 0.8, 60.0, 4.0)
	assert_true(near_soft.untouched, "50 px off the edge: 0.5 ignores it")
	assert_false(near_mid.untouched, "50 px off the edge: 0.8 bends")
	assert_gt(near_mid.min_edge, near_soft.min_edge + 5.0,
		"and passes wider (%.1f vs %.1f)" % [near_mid.min_edge, near_soft.min_edge])
	var far_mid := _fly(Vector2(-400.0, -190.0), Vector2(400.0, -190.0), 300.0, well, 0.8, 60.0, 4.0)
	var far_full := _fly(Vector2(-400.0, -190.0), Vector2(400.0, -190.0), 300.0, well, 1.0, 60.0, 4.0)
	assert_true(far_mid.untouched, "70 px off the edge: 0.8 ignores it")
	assert_false(far_full.untouched, "70 px off the edge: 1.0 bends")
	assert_gt(far_full.min_edge, far_mid.min_edge + 5.0,
		"and passes wider (%.1f vs %.1f)" % [far_full.min_edge, far_mid.min_edge])


## A brain wanting 8° with the 22.5° slot masked but 0° clear: the heading is refined between the slots, not
## snapped to 0°. The hazard (R 60, bearing 70°, 260 px out) puts danger on 22.5° and none on 0°.
func test_a_heading_between_two_slots_is_not_quantised() -> void:
	var want := Vector2.from_angle(deg_to_rad(8.0)) * 300.0
	var hazard := _info(Vector2.from_angle(deg_to_rad(70.0)) * 260.0, 60.0)
	var out := _avoid(Vector2.ZERO, want, [hazard])
	var deg := rad_to_deg(out.angle())
	assert_gt(deg, 0.5, "strictly past slot 0 (%.3f°)" % deg)
	assert_lt(deg, 22.0, "and short of slot 1")
	assert_almost_eq(deg, 8.0, 1.0, "on the brain's own heading")
	var to_slot := fposmod(deg, 22.5)
	assert_true(to_slot > 0.5 and to_slot < 22.0, "not a multiple of 22.5° (%.3f°)" % deg)
	# Control: the same hazard really does mask slot 1 — a brain wanting exactly 22.5° is turned off it.
	var on_slot := _avoid(Vector2.ZERO, Vector2.from_angle(deg_to_rad(22.5)) * 300.0, [hazard])
	assert_lt(rad_to_deg(on_slot.angle()), 22.5 - 0.5, "control: 22.5° is masked")


func test_a_drifting_hazard_is_led() -> void:
	var desired := Vector2(300.0, 0.0)
	var at := Vector2(200.0, -300.0)  # 300 px off the edge: beyond the 240 px skirt while static
	var still := _avoid(Vector2.ZERO, desired, [_info(at, 60.0)])
	var closing := _avoid(Vector2.ZERO, desired, [_info(at, 60.0, 1.0, Vector2(0.0, 500.0))])
	var leaving := _avoid(Vector2.ZERO, desired, [_info(at, 60.0, 1.0, Vector2(0.0, -500.0))])
	assert_eq(var_to_bytes(still), var_to_bytes(desired), "static and off the path: untouched")
	assert_eq(var_to_bytes(leaving), var_to_bytes(desired), "drifting away: untouched")
	assert_gt(absf(rad_to_deg(closing.angle())), 10.0, "drifting into the path 0.6 s ahead: avoided (%s)" % closing)


## Fray: maps merge per slot by MAX, never summed — "we're not going to avoid a particular obstacle any more
## just because there's another obstacle behind it". With avoidance 0.5 (threshold 0.5), A alone puts 0.42 on
## the 0° slot and B (behind A on the same bearing) 0.18: a sum would cross the threshold, a max does not.
func test_danger_merges_by_max_not_sum() -> void:
	var desired := Vector2.from_angle(deg_to_rad(-10.0)) * 300.0
	var a := _info(Vector2.from_angle(deg_to_rad(25.0)) * 150.0, 60.0)
	var b := _info(Vector2.from_angle(deg_to_rad(25.0)) * 220.0, 60.0)
	assert_eq(var_to_bytes(_avoid(Vector2.ZERO, desired, [a], 0.5)), var_to_bytes(desired), "sanity: A alone is ignored")
	assert_eq(var_to_bytes(_avoid(Vector2.ZERO, desired, [b], 0.5)), var_to_bytes(desired), "sanity: B alone is ignored")
	assert_eq(var_to_bytes(_avoid(Vector2.ZERO, desired, [a, b], 0.5)), var_to_bytes(desired),
		"B behind A adds nothing")
	assert_ne(var_to_bytes(_avoid(Vector2.ZERO, desired, [a, b], 1.0)), var_to_bytes(desired),
		"control: with full avoidance A is avoided")


## Boundary: every slot is dangerous (inside two overlapping hazards). The least dangerous heading wins —
## across both, not into either — and the ship keeps moving.
func test_surrounded_it_takes_the_least_dangerous_heading() -> void:
	var infos := [_info(Vector2(-100.0, 0.0), 160.0), _info(Vector2(100.0, 0.0), 160.0)]
	for desired in [Vector2(250.0, 0.0), Vector2(-250.0, 0.0), Vector2(200.0, 150.0)]:
		var out := _avoid(Vector2.ZERO, desired, infos)
		assert_gt(absf(out.normalized().y), 0.9, "%s: leaves across both centres (%s)" % [desired, out])
		assert_gte(out.length(), desired.length() * Steering.CONTEXT_MIN_SPEED_RATIO - 0.0001, "and keeps moving")


# ── Hysteresis ─────────────────────────────────────────────────────────────────

func test_prev_dir_keeps_the_side_it_chose() -> void:
	var well := [_info(Vector2.ZERO, 120.0)]
	var pos := Vector2(-260.0, 0.0)
	var desired := Vector2(300.0, 0.0)  # straight at the centre: both edges are equally good
	assert_lt(_avoid(pos, desired, well, 1.0, 60.0, Vector2.UP).y, 0.0, "coming from above, it keeps going up")
	assert_gt(_avoid(pos, desired, well, 1.0, 60.0, Vector2.DOWN).y, 0.0, "coming from below, it keeps going down")
	# A brain that reverses its request cancels the blend (0.5 want + 0.5 prev = 0): the brain's own heading ranks.
	var aside := Vector2.from_angle(deg_to_rad(30.0)) * 300.0
	assert_eq(var_to_bytes(_avoid(pos, aside, well, 1.0, 60.0, -aside.normalized())),
		var_to_bytes(_avoid(pos, aside, well, 1.0, 60.0, Vector2.ZERO)), "a reversed prev_dir is no bias at all")

	# One change of side at most over the whole run: up round the near half, then down to the target once the
	# ship is over the top (clear of the radius vertically). A dither changes side step after step.
	var log := _fly(Vector2(-300.0, 0.0), Vector2(300.0, 0.0), 300.0, well, 1.0, 60.0, 4.0)
	var side := 0.0
	var flips := 0
	for i in log.outs.size():
		var out: Vector2 = log.outs[i]
		if absf(out.y) < 1.0:
			continue
		var s := signf(out.y)
		if side != 0.0 and s != side:
			flips += 1
			assert_gte(absf((log.at[i] as Vector2).y), 120.0,
				"the side changes only over the top of the well (at %s)" % log.at[i])
		side = s
	assert_gt(log.reached, 30, "sanity: a run long enough to dither in, and it arrives")
	assert_lte(flips, 1, "no step-to-step dither between the two edges")
