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


# ── Segments: a laser wall (Phase 8, docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.6) ─────────────────────
# Task plan docs/plans/cmvqw0vn4017jqs2xzwshmrwt/3-plan.md, which records how the span between the ends is widened.

## The twin beam's numbers (epic plan §2.1 / §2.4), read from `twin_beam.tscn` through `EnemyBeamScenes.export_of` (never typed).
var twin_hit_half_width: float = _twin(&"hit_half_width")
var twin_draw_half_width: float = _twin(&"draw_half_width")
var twin_hazard_pad: float = _twin(&"hazard_pad")
var twin_avoid_weight: float = _twin(&"avoid_weight")


## `twin_beam.tscn`'s authored [param property]; NAN when the scene does not author it (every comparison then fails loudly).
static func _twin(property: StringName) -> float:
	return float(EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, property, NAN))


## The fixture victim's 14 px hurtbox: a ship whose centre stays `twin_hit_half_width + SHIP_RADIUS` from the hit segment
## keeps its hull out of the hit band.
const SHIP_RADIUS := 14.0
## A 420 px wall.
const WALL_HALF := 210.0
const RUN_SPEED := 200.0
## The integrated runs' accel limit: the Swarm Drone's and the Gatling's. Not the roster's lowest (Mine Layer 420, Sniper
## 520, Bomber 260): `test_roster_profiles_meet_a_twin_wall` flies every profile at its own numbers.
const RUN_ACCEL := 600.0
## The tightest margin in the roster (the Swarm Drone's) and this file's default (the Fighter's).
const WALL_MARGINS := [12.0, 60.0]


## The twin wall's footprint (§2.4: `draw_half_width + hazard_pad`, `avoid_weight`) from `at - half` to `at + half`.
func _wall(at: Vector2, half: Vector2, velocity: Vector2 = Vector2.ZERO) -> HazardInfo:
	var i := _info(at, twin_draw_half_width + twin_hazard_pad, twin_avoid_weight, velocity)
	i.segment_half = half
	return i


## The §2.6 approach geometry: the path runs +x from the origin and meets a 420 px wall 200 px ahead, `phi` being the
## angle between the path and the wall's normal. At 0° and 45° the path crosses the wall's midpoint; at 90° the wall lies
## on the path from 200 to 620 px (end-on).
func _approach_wall(phi: float) -> HazardInfo:
	if phi == 90.0:
		return _wall(Vector2(200.0 + WALL_HALF, 0.0), Vector2(WALL_HALF, 0.0))
	return _wall(Vector2(200.0, 0.0), Vector2(0.0, WALL_HALF).rotated(deg_to_rad(phi)))


## Distance from `p` to the wall's hit segment (the twin beam's `tip_grace_px` is 0: the drawn segment itself).
func _to_wall(p: Vector2, wall: HazardInfo) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, wall.position - wall.segment_half,
			wall.position + wall.segment_half))


## True when a ray from `pos` along `out` (a non-zero heading) never meets the wall's hit segment.
func _misses(pos: Vector2, out: Vector2, wall: HazardInfo) -> bool:
	return out != Vector2.ZERO and Geometry2D.segment_intersects_segment(pos, pos + out.normalized() * 4000.0,
			wall.position - wall.segment_half, wall.position + wall.segment_half) == null


## Seeks `target` at `speed` from `start`, already flying at full speed toward it, through an accel-limited mover: the
## velocity moves toward each step's output at `accel`, and the output's direction is the next step's `prev_dir` (as
## `EnemyMover._avoid` keeps it). Returns the closest approach to the hit segment, whether a step crossed it, how far off
## the line the first bent output was and whether its heading pointed past an end, and the arrival time (-1 if none).
func _run_at_wall(start: Vector2, target: Vector2, wall: HazardInfo, avoidance: float, margin: float,
		speed: float = RUN_SPEED, accel: float = RUN_ACCEL, seconds: float = 12.0) -> Dictionary:
	var a := wall.position - wall.segment_half
	var b := wall.position + wall.segment_half
	var pos := start
	var vel := (target - start).normalized() * speed
	var prev := Vector2.ZERO
	var run := {"closest": INF, "crossed": false, "bent_at": -1.0, "past_an_end": false, "arrived": -1.0}
	for step in int(seconds / DT):
		if pos.distance_to(target) < 6.0:
			run.arrived = step * DT
			break
		var desired := (target - pos).normalized() * speed
		var out := _avoid(pos, desired, [wall], avoidance, margin, prev)
		if run.bent_at < 0.0 and var_to_bytes(out) != var_to_bytes(desired):
			run.bent_at = _to_wall(pos, wall)
			run.past_an_end = _misses(pos, out, wall)
		prev = out.normalized()
		vel = vel.move_toward(out, accel * DT)
		var next := pos + vel * DT
		if Geometry2D.segment_intersects_segment(pos, next, a, b) != null:
			run.crossed = true
		pos = next
		run.closest = minf(run.closest, _to_wall(pos, wall))
	return run


## §2.6: a 420 px wall across the path, 200 px ahead, is avoided from approach bearings 0°, 45° and 90° at avoidance
## 1.0 / 0.8 / 0.6 and margins 12 / 60. Every run bends, its first bent heading points past an end, no step crosses the
## line and every run arrives at the target 820 px down the path. At 1.0 and 0.8 a 14 px hull never touches the 10 px hit
## band (24 px); 0.6 has no bound (§2.6), and its figures are printed with the rest. At 45° (closest point 141 px) and at
## margin 60 (skirt reach 38 + 180 = 218 px) the run starts inside the skirt, so its "first bend" is the start itself.
func test_a_wall_across_the_path_is_avoided_round_an_end() -> void:
	var bound := twin_hit_half_width + SHIP_RADIUS
	for phi in [0.0, 45.0, 90.0]:
		var wall := _approach_wall(phi)
		for avoidance in [1.0, 0.8, 0.6]:
			for margin in WALL_MARGINS:
				var run := _run_at_wall(Vector2.ZERO, Vector2(820.0, 0.0), wall, avoidance, margin)
				var label := "%d°, avoidance %.1f, margin %d" % [phi, avoidance, margin]
				gut.p("segment avoidance %s: closest %.1f px, first bend %.1f px off the line, arrived %.2f s"
						% [label, run.closest, run.bent_at, run.arrived])
				assert_gt(run.bent_at, 0.0, "%s: the stage bends the run" % label)
				assert_true(run.past_an_end, "%s: its first bent heading points past an end" % label)
				assert_false(run.crossed, "%s: never crosses the line" % label)
				assert_gt(run.arrived, 0.0, "%s: arrives round the end" % label)
				if avoidance >= 0.8:
					assert_gte(run.closest, bound, "%s: the hull stays out of the hit band (%.1f px)" % [label, run.closest])


## Review B1 / R2-2, from a standing start with no `prev_dir`: the first output's ray misses the hit segment. A span with
## no widening returns 56.25° against an end bearing of 62.4° here, and hits. The offset wall's near end is past 195 px, so
## its footprint tangent is under half a slot: a span widened by the tangent alone returns -56.25° and hits it at y -246.9.
func test_a_first_bend_points_past_an_end_from_a_static_start() -> void:
	for radius in [38.0, 62.0]:
		for avoidance in [1.0, 0.8]:
			for dir in [1.0, -1.0]:
				var wall := _wall(Vector2(110.0 * dir, 0.0), Vector2(0.0, WALL_HALF))
				wall.radius = radius
				var out := _avoid(Vector2.ZERO, Vector2(200.0 * dir, 0.0), [wall], avoidance, 12.0)
				assert_true(_misses(Vector2.ZERO, out, wall), "ends (%d, ±210), radius %d, avoidance %.1f: past an end (%.2f°)"
						% [110.0 * dir, radius, avoidance, rad_to_deg(out.angle())])
	var offset := _wall(Vector2(165.0, -60.0), Vector2(0.0, WALL_HALF))  # ends (165, -270) and (165, 150)
	var out := _avoid(Vector2.ZERO, Vector2(200.0, 0.0), [offset], 1.0, 12.0)
	assert_true(_misses(Vector2.ZERO, out, offset), "the offset wall: past an end (%.2f°)" % rad_to_deg(out.angle()))


## Review R2-3: the half slot also applies when the request blended with `prev_dir` (the tail's own aim) lies on the wall,
## not only the request. A ship asking to pass under the far end of a long, slanted wall (its request misses the wall but
## is inside the end's margin) after a heading up into it: the blend pulls the refined pick half a slot back toward the
## wall, so without the widening the output is -11.25°, whose ray hits the wall. With it, the output clears it.
func test_a_previous_heading_into_the_wall_cannot_pull_the_output_onto_it() -> void:
	var wall := _wall(Vector2(240.0, -140.0), Vector2(400.0, 30.0))  # (-160, -170) .. (640, -110)
	var desired := Vector2.from_angle(deg_to_rad(-2.0)) * RUN_SPEED
	var prev := Vector2.from_angle(deg_to_rad(-56.0))
	assert_true(_misses(Vector2.ZERO, desired, wall), "sanity: the request itself passes the wall")
	assert_false(_misses(Vector2.ZERO, prev, wall), "sanity: the last heading points into it")
	var out := _avoid(Vector2.ZERO, desired, [wall], 1.0, 60.0, prev)
	assert_ne(var_to_bytes(out), var_to_bytes(desired), "sanity: the stage acts (the far end's margin)")
	assert_true(_misses(Vector2.ZERO, out, wall), "the output clears the wall (%.2f°)" % rad_to_deg(out.angle()))


## Review M3 / R2-5, in the shape of `test_inside_the_first_step_points_outward`: from inside the footprint every request —
## every slot heading, 0.1 rad off each, and straight at the wall — steps outward and keeps moving. Beside the middle, beside
## an end, 0.5 px off the line and on the wall's axis past an end, never near-tangent (outward share > 0.1). Diagonally
## round an end cap at 0.8 / 0.6 the wall acts as its end's 38 px circle, whose cone tail past 90° is under the threshold, so
## a request a few degrees past tangent goes through: still outward, its share printed (a weight-0.5 circle there steps
## inward). Exactly on the line and exactly on an end there is no outward: the output is finite and keeps moving.
func test_a_ship_inside_the_footprint_steps_outward() -> void:
	var wall := _wall(Vector2.ZERO, Vector2(WALL_HALF, 0.0))  # (-210, 0) .. (210, 0)
	var worst := INF
	for pos in [Vector2(0.0, 20.0), Vector2(-40.0, -30.0), Vector2(190.0, 30.0), Vector2(-195.0, -12.0),
			Vector2(60.0, 0.5), Vector2(230.0, 0.0), Vector2(-240.0, 0.0), Vector2(225.0, -15.0)]:
		worst = minf(worst, _worst_outward_share(wall, pos))
	var worst_cap := INF
	for pos in [Vector2(-236.0, 20.0), Vector2(215.0, 30.0)]:
		worst_cap = minf(worst_cap, _worst_outward_share(wall, pos))
	gut.p("segment inside: worst outward share %.3f, diagonally round an end cap %.3f" % [worst, worst_cap])
	assert_gt(worst, 0.1, "never a near-tangent step: worst outward share %.3f" % worst)
	for pos in [Vector2(50.0, 0.0), Vector2(210.0, 0.0), Vector2(-210.0, 0.0)]:
		for avoidance in [1.0, 0.8, 0.6]:
			for k in Steering.CONTEXT_SLOTS:
				var out := _avoid(pos, Vector2.from_angle(k * SLOT) * RUN_SPEED, [wall], avoidance, 12.0)
				assert_true(out.is_finite(), "on the wall at %s: a finite output (%s)" % [pos, out])
				assert_gte(out.length(), RUN_SPEED * Steering.CONTEXT_MIN_SPEED_RATIO - 0.0001, "and keeps moving")


## Every request from `pos` (inside the wall's footprint) at 1.0 / 0.8 / 0.6 and both margins steps outward and keeps
## moving; returns the least outward share.
func _worst_outward_share(wall: HazardInfo, pos: Vector2) -> float:
	var away := (pos - wall.closest_point(pos)).normalized()
	var headings: Array = [-away]
	for k in Steering.CONTEXT_SLOTS:
		headings.append(Vector2.from_angle(k * SLOT + 0.1))
		headings.append(Vector2.from_angle(k * SLOT))
	var worst := INF
	for avoidance in [1.0, 0.8, 0.6]:
		for margin in WALL_MARGINS:
			for h in headings:
				var out := _avoid(pos, (h as Vector2) * RUN_SPEED, [wall], avoidance, margin)
				var outward := out.normalized().dot(away)
				worst = minf(worst, outward)
				assert_gt(outward, 0.0, "inside at %s, avoidance %.1f, margin %d, heading %s: steps outward (got %s)"
						% [pos, avoidance, margin, h, out])
				assert_gte(out.length(), RUN_SPEED * Steering.CONTEXT_MIN_SPEED_RATIO - 0.0001, "and keeps moving")
	return worst


## §2.6: a wall alongside the path is not in the way. Level with its midpoint, 150 px beside it, every profile's request
## along it comes back bit-identical. Along a whole pass, from 360 px before the midpoint to 360 px past it, the wall leaves
## a request alone wherever two footprint circles at its ends alone would: its closest-point cone and its span never reach a
## heading along it. (An end is avoided exactly as a 38 px circle there: a 1.0 ship with a wide margin bends a little passing
## one, as past any hazard.) Review R2-4: a request between two slots is nudged off the wall by a fraction of a slot at most,
## so the same pass along the wall turned to 8° and 15° keeps its heading within 0.5° and its speed within 1 %.
func test_a_wall_beside_the_path_adds_nothing_its_ends_do_not() -> void:
	var wall := _wall(Vector2(0.0, 150.0), Vector2(WALL_HALF, 0.0))
	var ends := [_info(wall.position - wall.segment_half, wall.radius, wall.avoid_weight),
			_info(wall.position + wall.segment_half, wall.radius, wall.avoid_weight)]
	var checked := 0
	var bent: Array = []
	for avoidance in [1.0, 0.8, 0.6]:
		for margin in [12.0, 60.0, 90.0]:
			for dir in [1.0, -1.0]:
				var desired := Vector2(RUN_SPEED * dir, 0.0)
				assert_eq(var_to_bytes(_avoid(Vector2.ZERO, desired, [wall], avoidance, margin)), var_to_bytes(desired),
						"level with the midpoint, avoidance %.1f, margin %d, %s: bit-identical" % [avoidance, margin, desired])
				for x in range(-360, 361, 10):
					var pos := Vector2(x, 0.0)
					if var_to_bytes(_avoid(pos, desired, ends, avoidance, margin)) != var_to_bytes(desired):
						continue
					checked += 1
					if var_to_bytes(_avoid(pos, desired, [wall], avoidance, margin)) != var_to_bytes(desired):
						bent.append("x %d, avoidance %.1f, margin %d, %s" % [x, avoidance, margin, desired])
	assert_eq(bent, [], "the wall bends nothing its ends leave alone")
	assert_gt(checked, 1000, "sanity: the sweep compared %d requests" % checked)

	var worst_turn := 0.0
	var worst_speed := INF
	var off_slot := 0
	for turn in [deg_to_rad(8.0), deg_to_rad(15.0)]:
		var tilted := _wall(wall.position.rotated(turn), wall.segment_half.rotated(turn))
		var tilted_ends := [_info(tilted.position - tilted.segment_half, tilted.radius, tilted.avoid_weight),
				_info(tilted.position + tilted.segment_half, tilted.radius, tilted.avoid_weight)]
		for avoidance in [1.0, 0.8, 0.6]:
			for margin in [12.0, 60.0, 90.0]:
				for dir in [1.0, -1.0]:
					var desired := Vector2(RUN_SPEED * dir, 0.0).rotated(turn)
					for x in range(-360, 361, 10):
						var pos := Vector2(x, 0.0).rotated(turn)
						if var_to_bytes(_avoid(pos, desired, tilted_ends, avoidance, margin)) != var_to_bytes(desired):
							continue
						off_slot += 1
						var out := _avoid(pos, desired, [tilted], avoidance, margin)
						worst_turn = maxf(worst_turn, absf(angle_difference(desired.angle(), out.angle())))
						worst_speed = minf(worst_speed, out.length() / RUN_SPEED)
	gut.p("segment beside, off-slot: %d requests, worst turn %.3f°, worst speed %.4f" % [off_slot, rad_to_deg(worst_turn),
			worst_speed])
	assert_gt(off_slot, 1000, "sanity: the off-slot sweep compared %d requests" % off_slot)
	assert_lt(rad_to_deg(worst_turn), 0.5, "off-slot along the wall: within 0.5° of the request")
	assert_gte(worst_speed, 0.99, "and within 1 % of its speed")

	# Controls, so the rows above can fail: a circle holding the whole wall walls the path off, and so does the wall turned
	# across the path (review R2-8: midpoint (150, 0), so the ship is not on its line).
	var desired := Vector2(RUN_SPEED, 0.0)
	var disc := _info(wall.position, WALL_HALF + wall.radius, wall.avoid_weight)
	assert_ne(var_to_bytes(_avoid(Vector2.ZERO, desired, [disc])), var_to_bytes(desired), "control: a circle round the wall")
	var across := _wall(Vector2(150.0, 0.0), Vector2(0.0, WALL_HALF))
	assert_ne(var_to_bytes(_avoid(Vector2.ZERO, desired, [across], 1.0, 60.0)), var_to_bytes(desired),
			"control: the wall turned across the path")


## §2.6: a moving wall is led, both ends. Across the path 300 px out (its footprint 262 px off, beyond the 180 px skirt while
## still), closing at 240 px/s it is led 144 px into reach; leaving, it is not. Sliding along its own axis, an end 250 px off
## the path is led 144 px across it — led along the wall's axis, not only across it; sliding the other way it is not.
func test_a_moving_wall_is_led() -> void:
	var desired := Vector2(RUN_SPEED, 0.0)
	var across := Vector2(0.0, WALL_HALF)
	var still := _avoid(Vector2.ZERO, desired, [_wall(Vector2(300.0, 0.0), across)])
	var closing := _avoid(Vector2.ZERO, desired, [_wall(Vector2(300.0, 0.0), across, Vector2(-240.0, 0.0))])
	var leaving := _avoid(Vector2.ZERO, desired, [_wall(Vector2(300.0, 0.0), across, Vector2(240.0, 0.0))])
	assert_eq(var_to_bytes(still), var_to_bytes(desired), "still and beyond the skirt: untouched")
	assert_eq(var_to_bytes(leaving), var_to_bytes(desired), "moving away: untouched")
	assert_ne(var_to_bytes(closing), var_to_bytes(desired), "closing at 240 px/s: avoided (%s)" % closing)
	var side := Vector2(150.0, -200.0 - WALL_HALF)  # an end at (150, -200), 250 px off
	var parked := _avoid(Vector2.ZERO, desired, [_wall(side, across)])
	var sliding_in := _avoid(Vector2.ZERO, desired, [_wall(side, across, Vector2(0.0, 240.0))])
	var sliding_out := _avoid(Vector2.ZERO, desired, [_wall(side, across, Vector2(0.0, -240.0))])
	assert_eq(var_to_bytes(parked), var_to_bytes(desired), "an end beyond the skirt: untouched")
	assert_eq(var_to_bytes(sliding_out), var_to_bytes(desired), "sliding away: untouched")
	assert_ne(var_to_bytes(sliding_in), var_to_bytes(desired), "sliding its end into the path: avoided (%s)" % sliding_in)


## Review m1: a wall's danger merges with a circle's by MAX, slot by slot, like any two hazards. With both in the way, the
## order of the infos changes nothing, and the pair answers differently from either alone (an overwrite fails one of them):
## the wall alone is rounded at its upper end, where the circle sits, so the pair is rounded at the lower one.
func test_a_wall_and_a_circle_merge_by_max_in_either_order() -> void:
	var desired := Vector2(RUN_SPEED, 0.0)
	var wall := _wall(Vector2(200.0, 0.0), Vector2(0.0, WALL_HALF))
	var circle := _info(Vector2(120.0, -130.0), 50.0)
	var both := _avoid(Vector2.ZERO, desired, [circle, wall])
	assert_eq(var_to_bytes(_avoid(Vector2.ZERO, desired, [wall, circle])), var_to_bytes(both), "either order: the same bytes")
	assert_ne(var_to_bytes(both), var_to_bytes(_avoid(Vector2.ZERO, desired, [wall])), "the circle counts (%s)" % both)
	assert_ne(var_to_bytes(both), var_to_bytes(_avoid(Vector2.ZERO, desired, [circle])), "the wall counts (%s)" % both)


## Review M1, printed, not gated: the three approach runs for six real profiles at their own `max_speed`, `acceleration`,
## `hazard_margin` and `hazard_avoidance`, read from each `*_config.tres` (never written). The Bomber (0.6) also meets a
## weight-1.0 wall (the laser fence's, t10). Every run ends with finite figures; the rest is recorded in DECISIONS.
func test_roster_profiles_meet_a_twin_wall() -> void:
	for profile in ["swarm_drone", "sniper", "fighter", "gatling_interceptor", "mine_layer", "bomber"]:
		var config: Resource = load("res://assault/scenes/enemies/%s/%s_config.tres" % [profile, profile])
		var weights := [twin_avoid_weight, 1.0] if profile == "bomber" else [twin_avoid_weight]
		for weight in weights:
			for phi in [0.0, 45.0, 90.0]:
				var wall := _approach_wall(phi)
				wall.avoid_weight = weight
				var run := _run_at_wall(Vector2.ZERO, Vector2(820.0, 0.0), wall, config.hazard_avoidance,
						config.hazard_margin, config.max_speed, config.acceleration)
				gut.p("segment roster %s (%.0f px/s, %.0f px/s², margin %.0f, avoidance %.1f), wall weight %.1f, %d°: closest %.1f px, crossed %s, arrived %.2f s"
						% [profile, config.max_speed, config.acceleration, config.hazard_margin, config.hazard_avoidance,
						weight, phi, run.closest, run.crossed, run.arrived])
				assert_true(is_finite(run.closest), "%s, %d°: the run ends with a finite closest approach" % [profile, phi])
