# t4 — Segment hazards: enemies steer round the ends of a laser wall

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t4. Builds epic plan §2.6 (approved); this task plan only fixes the details
§2.6 leaves open and the test geometry. Context: `1-context.md`. **Revision 2**, answering round 1 of `4-review.md` (B1, M1–M3, m1–m4; the
answer to each is listed at the end).

## Problem

Phase 8 adds laser walls: a twin-drone beam and a laser fence are long, thin lines that kill on contact. The hazard registry and the
avoidance stage only know circles. Registered as a circle round its midpoint, a 420 px wall is either a 38 px dot that enemies happily
fly through 150 px from the middle, or a 250 px disc that walls off everything near it, including ships flying alongside. Enemies
should see the wall as a line: steer round its ends when it is across their way, ignore it when it is beside them, read where a
moving wall will be, and never avoid their own pair's wall. Every existing hazard (wells, anomalies, wrecks, debris, mines) must
behave exactly as today, bit for bit.

## Design

### `HazardInfo` (`global/hazards/hazard_info.gd`)
- `var segment_half: Vector2 = Vector2.ZERO`: half the segment, from `position` to one end. ZERO = a circle (every existing hazard).
- `var exempt_group: StringName = &""`: an actor in this Godot group drops the info in its avoidance stage.
- `func closest_point(pos: Vector2) -> Vector2`: `position` for a circle; `Geometry2D.get_closest_point_to_segment(pos, position -
  segment_half, position + segment_half)` for a segment.
- `contains(pos, margin)` and `penalty_at(pos)`: a leading `if segment_half != Vector2.ZERO:` branch measures to `closest_point(pos)`;
  the existing circle line follows it unchanged, so every circle result is the same expression as today.
- `falloff` / `accel_at` unchanged. A segment info has no pull (`pull_force` 0, `core_radius` 0 → `falloff` is 0 → `accel_at` returns
  `Vector2.ZERO` exactly); a row pins it.
- `Hazards` (`hazards.gd`): no code change — `around()` goes through `contains`, so it finds a wall by its closest point. Its doc comment
  (line 29, which spells the circle formula) becomes "within `radius + reach` of the info's `closest_point()`" (comment only).

### `Steering.context_avoid` segment branch (`global/enemy_ai/steering.gd`)
Inside the per-info loop, after the existing `null` / `avoid_weight <= 0` skip, one new branch:
```gdscript
if info.segment_half != Vector2.ZERO:  # a wall (Phase 8 §2.6)
	var wall := _segment_danger(pos, want, info, margin, lookahead, skirt_reach, slot)
	for i in CONTEXT_SLOTS:
		danger[i] = maxf(danger[i], wall[i])
	continue
```
The circle code below it is not edited, and everything after the loop (threshold, clear way, masked pick, hysteresis, refinement, speed
floor) is shared and unchanged. A new private static `_segment_danger()` returns a fresh 16-slot `PackedFloat64Array`:
1. **Lead** both ends: `lead = position + velocity · lookahead − pos`, `a = lead − segment_half`, `b = lead + segment_half` (relative to
   `pos`), as the circle centre is led.
2. `c` = closest point of `a`–`b` to the origin, `d = |c|`. Skirt exactly as a circle (`outside = max(0, d − radius)`; 0 beyond
   `skirt_reach`). If the skirt is 0 the whole info writes nothing (every end is at least as far as `c`).
3. **Three cones**, each the circle formula as written in the loop — its own distance `d_i`, its own skirt, half-width
   `asin(min(1, (radius + margin) / d_i)) + slot`, weight `avoid_weight · skirt_i · (1 − off / half_width)` — at `c`, `a` and `b`.
   A point closer than 0.001 px (the ship exactly on the line, or on an end) has no bearing and is skipped, as the circle loop skips its centre.
4. **Span** (only with `d`, `|a|` and `|b|` all ≥ 0.001): the arc of headings whose ray meets the wall's footprint, at `avoid_weight · skirt`
   (the closest point's skirt), flat:
   - the shorter arc from `a`'s bearing to `b`'s bearing (a segment not containing `pos` subtends < 180°, so the shorter arc is the wall);
   - **widened at each end by that end's footprint tangent `asin(min(1, radius / |end|))`** — the angular extent of the capsule (the
     segment inflated by `radius`) as seen from `pos`: a heading just past an end *point* still clips the footprint there;
   - **and, when `want`'s bearing lies on that arc** (the brain is asking to fly into the wall), widened by a further **half a slot** at each
     end — the same reason the circle cone carries `+ slot` (`steering.gd:234`): the shared parabolic refinement can move the picked slot up to
     half a slot back toward the aim, and without this it lands inside the footprint (review B1);
   - computed as a start bearing and a length (`fposmod(θ − start, TAU) <= length`), so a widened arc longer than 180° (a ship inside the band,
     next to the line) is covered whole.
   The margin and the one-slot widening near an end come from the end cones (step 3), which carry them only within their own skirt.

**Readings §2.6 leaves open, and why (all recorded in DECISIONS).**
- **Each cone uses its own skirt.** §2.6 says "same formula as a circle … weight `avoid_weight · skirt`". Read as the closest point's skirt for
  all three cones, a ship flying alongside the middle of a wall 150 px away is bent by the far end's cone: the end at (210, 150) seen from
  (0, 0) has bearing 35.5° and half-width 44.8° with margin 60, so it covers the 0° slot, at `0.5 · 0.378 · 0.207 = 0.039` > 0 at avoidance
  1.0 (the review's prototype: 8 of the parallel row's combinations bend). With its own skirt (the end is 258 px away, beyond the 218 px reach)
  it writes nothing. So an end of a wall is avoided exactly as a 38 px circle there would be; only the span uses the closest point's skirt.
- **The span is widened (footprint tangent; half a slot more when the request is on it).** §2.6's literal "slots whose bearing lies on the
  shorter arc between the two ends' bearings" has no widening, so the refinement turns the output back into the wall: φ 0°, margin 12,
  avoidance 0.8 deflects first at 117 px with an end bearing of 60.8° and outputs 56.25°, whose ray hits the wall at y = 175 of ±210 (review
  B1, worked by hand). Measured on a scratch copy of the stage (5000 random walls × 4 `prev_dir`, 80–400 px ahead, 200–800 px long, margins
  12–90, 200–320 px/s): the literal arc points into the wall in 18.8 % / 34.0 % / 37.7 % of deflections at 1.0 / 0.8 / 0.6; the half-slot
  widening alone (the review's fix) in 0 / 0.1 % / 0.2 %; the footprint tangent alone in 10.8 / 11.7 / 9.0 %; **both: 0 / 0 / 0**. None of the
  four bends a parallel pass that circles at both ends and at the closest point leave alone (0 of 44 200 requests, 100–200 px beside, 200/420/800
  px walls). Both also lift the 0.8 end-on row from 19.7 px (literal, and half-slot alone) to 40.5 px, so the pre-approved pad lever is **not**
  needed (expected figures below). The unconditional variants are rejected: a flat half slot bends parallel passes whose far end lies within half
  a slot of the heading (the review's 5 120 / 184 080), and widening by `asin((radius + margin) / |end|)` leaves a 0.6 ship dithering at the
  middle of the wall (margins 60 / 90 never arrive in 12 s), because near an end it masks 90° past it at the flat span weight.

### `EnemyMover._avoid` (`global/enemy_ai/enemy_mover.gd`)
In the existing reverse loop that drops the actor's own claimed LOS blocker, an `elif info.exempt_group != &"" and
actor.is_in_group(info.exempt_group)` drop. Nothing else changes; with no such info the stage is untouched. The class comment's step 3
names the new drop.

### Alternatives rejected
- **A circle round the midpoint** (Ph6's "walls join with no AI change"): either too small to keep ships off the line or so large it
  blocks ships flying alongside. That is the reason for §2.6.
- **A chain of circles along the wall:** the gaps between circles invite the stage through them (each cone is narrow at range), and the
  count grows with the length. The span covers the whole wall with three cones and one arc.
- **Editing the circle body to share a `_cone()` helper with the segment branch:** the duplicate formula keeps the circle's float
  operations as they are, so the circle bytes cannot move. The plan forbids editing that body.
- **The span variants above** (literal, half slot alone, tangent alone, unconditional half slot, `(radius + margin)` tangent).

## Build sequence
1. Segment rows in `tests/unit/test_hazards.gd` (fail: no `segment_half` / `closest_point`).
2. `HazardInfo` fields, `closest_point`, segment branches in `contains` / `penalty_at`; `hazards.gd:29` comment. Rows of step 1 green; every
   circle row green.
3. Segment rows in `tests/unit/test_context_avoidance.gd` and the exempt rows in `tests/unit/test_enemy_mover.gd` (fail).
4. `Steering._segment_danger` + the loop branch; `EnemyMover._avoid` exempt drop. Measure and print the figures. If 1.0 or 0.8 misses the
   24 px bound after all, use the pre-approved lever (`TWIN_HAZARD_PAD` 48, radius 62) and record it. No bound moves.
5. Nothing awaits, so `scripts/check-test-leaks.sh` is not needed. `scripts/gate-time.sh` after (before: 201.007 s, 2381 tests), then
   `bash /agent/verify.sh`.
6. `DECISIONS.md` "Phase 8, built in t4" (figures, the span and skirt readings, the exempt row's file, the consumers t5 meets, the unled
   registry query, the 0.6 skim, whether the lever was used), `tests/README.md` → Gate time row, `docs/architecture/modules/global.md` hazard
   rows (via `updating-project-docs`).

## Test plan

### `tests/unit/test_hazards.gd` (new section "segments (Phase 8 §2.6)"; every existing row untouched)
- `test_a_new_info_is_a_circle_and_exempts_no_one`: defaults `segment_half == ZERO`, `exempt_group == &""`; `closest_point` of a circle is
  `position` for any point.
- `test_segment_closest_point_beside_the_middle_beyond_an_end_and_on_the_line`: info at (100, 50), half (200, 0): (150, 120) → (150, 50);
  (400, 80) → (300, 50); (−150, 50) → (−100, 50); (120, 50) → itself.
- `test_segment_contains_measures_to_the_closest_point_and_honours_the_margin`: radius 38: beside the middle at 38 px in, 39 px out;
  margin 30: 68 in, 69 out; beyond an end, along the line: 38 in, 39 out (boundary); a point 190 px from `position` but 30 px from the
  segment is in (not a circle); a point 100 px straight off the midpoint is out.
- `test_segment_penalty_at_uses_the_closest_point`: `movement_penalty` 0.3 → 0.3 at 38 px beside an end and beyond the other, 0 at 39 px.
- `test_around_finds_a_segment_by_its_closest_point`: a registered segment fixture (the file's `FixtureHazard` with `segment_half`): found at
  `radius + reach` from the closest point, not 1 px beyond; found beyond an end along the line at exactly `radius + reach`, not 1 px beyond; a
  1000 px wall whose midpoint is out of reach but whose end is in reach is found.
- `test_a_segment_with_no_pull_has_no_accel_and_no_slow`: `accel_at` of the info at several points (beside, on the line, at the midpoint)
  is exactly `Vector2.ZERO`; `Hazards.accel_at` and `Hazards.penalty_at` with it registered are ZERO / 0.

### `tests/unit/test_context_avoidance.gd` (new section "segments (Phase 8 §2.6)"; every existing row untouched)
Named constants (t5 replaces the four `TWIN_*` with `EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, …)` once `twin_beam.tscn` exists):
`TWIN_HIT_HALF_WIDTH` 10, `TWIN_DRAW_HALF_WIDTH` 14, `TWIN_HAZARD_PAD` 24 (footprint radius 38), `TWIN_AVOID_WEIGHT` 0.5;
`SHIP_RADIUS` 14 (the fixture victim's hurtbox); bound `TWIN_HIT_HALF_WIDTH + SHIP_RADIUS` = 24 px. Wall 420 px.
Run: 200 px/s (§2.6), accel-limited at 600 px/s² — the Swarm Drone's and the Gatling's; **not** the roster's lowest (Mine Layer 420, Sniper 520,
Bomber 260), which the printed roster row covers at each ship's own speed — starting at full speed along the path, `prev_dir` = the last output's
direction (as `EnemyMover._avoid` keeps it), DT 1/60, at most 12 s. Margins 12 (the Swarm Drone's, the tightest in the roster) and 60 (the
Fighter's, the file's default).

- `test_a_wall_across_the_path_is_avoided_round_an_end` — approach bearing φ = the angle between the path and the wall's normal, 0°, 45°,
  90°. The path runs +x from (0, 0) to (820, 0) and meets the wall 200 px ahead: at its midpoint for 0° and 45°, at its near end for 90°
  (end-on: the wall lies on the path from 200 to 620). For every φ × avoidance {1.0, 0.8, 0.6} × margin {12, 60}:
  - the stage bends the run, and its first bent output points past an end (its ray misses the hit segment);
  - for 1.0 and 0.8: no step crosses the line, the closest approach to the hit segment is ≥ 24 px, and the target is reached;
  - for 0.6 (no bound, §2.6): the closest approach, crossing and arrival are printed, not gated (review m3);
  - every figure (closest approach, first-bend distance, arrival time) is printed (`gut.p`) and recorded in DECISIONS. The first-bend distance is
    where the stage first acted; at φ 45° (closest point 141 px) and at margin 60 (reach 38 + 180 = 218 px) the run starts inside the skirt, so it
    is the start's own distance (noted with the figures).
  Expected (scratch copy of the stage): 1.0 ≥ 57.9 px, 0.8 ≥ 38.8 px, 0.6 ≥ 11.4 px; every run arrives and none crosses.
- `test_a_first_bend_points_past_an_end_from_a_static_start` (review B1's lever-independent row): a 420 px wall with ends (110, ±210), the ship
  at the origin, `desired` (200, 0), margin 12, avoidance 1.0 and 0.8, radius 38 and 62: the output's ray misses the hit segment (the literal
  arc returns 56.25° against an end bearing of 62.4° and fails it). Plus the same geometry mirrored (ends (−110, ±210), `desired` (−200, 0)).
- `test_a_ship_inside_the_footprint_steps_outward` (review M3, the shape of `test_inside_the_first_step_points_outward`): positions inside the
  footprint beside the middle, beside an end and 0.5 px off the line, each over every slot heading (on the slot and 0.1 rad off it): the output
  steps outward (one DT step along it ends farther from the hit segment; level with an end a heading straight past it counts, its dot with
  `pos − closest_point` being 0) and keeps ≥ 35 % of the speed. Exactly on the line, and exactly on an end: the output is
  finite (no NaN) and keeps ≥ 35 % of the speed.
- `test_a_wall_beside_the_path_adds_nothing_its_ends_do_not` — a 420 px wall parallel to the path, 150 px beside it. For the ship level
  with the midpoint, every avoidance level and margin {12, 60, 90}, `desired` ±x is returned bit-identical (the plan's row). Over a sweep
  of the ship from 360 px before the wall's middle to 360 px past it, every request that two 38 px circles at the wall's ends (and nothing
  else) leave bit-identical, the wall leaves bit-identical too: the closest-point cone and the span never touch a heading along the wall.
  Controls: one circle large enough to hold the whole wall (radius 248 at the midpoint) bends the midpoint heading, and the same wall
  turned across the path bends it.
- `test_a_moving_wall_is_led` — a wall across the path whose static position is beyond the skirt: untouched static, untouched moving
  away, avoided closing at 240 px/s. And a wall sliding along its own axis at 240 px/s (led along its axis, not only across it) whose end is
  carried across the path: untouched static, untouched sliding away, avoided sliding in.
- `test_a_wall_and_a_circle_merge_by_max_in_either_order` (review m1): a wall and a circle that both write danger near the request:
  `[circle, wall]` and `[wall, circle]` return identical bytes, and differ from each alone.
- `test_roster_profiles_meet_a_twin_wall` (review M1, **printed, not gated**): the three φ runs for Swarm, Sniper, Fighter, Gatling, Mine Layer
  and Bomber at their own `max_speed` / `acceleration` / `hazard_margin` / `hazard_avoidance`, read from each `*_config.tres` (read-only; never
  written). Expected: Swarm ≥ 59, Sniper ≥ 90, Fighter ≥ 47, Gatling ≥ 43, Mine Layer ≥ 39 px; the Bomber (0.6, 240 px/s, 260 px/s², margin
  70) skims a weight-0.5 wall: at φ 0° it crosses the line (min 0.1 px), at 45° / 90° it keeps 24 / 11.8 px. Against a weight-1.0 wall (t10's
  fence) the same Bomber keeps 46 / 55 / 55 px. Recorded in DECISIONS as input for t10 / t12–t13, asserted only as "every run ends" (finite figures).
- The existing pass-through, circle-avoidance and hysteresis rows run unchanged.

### `tests/unit/test_enemy_mover.gd` (beside the own-claim drop row)
- `test_an_actor_in_the_exempt_group_ignores_the_wall_and_every_other_actor_avoids_it` — a registered 1000 px wall across the path whose
  midpoint is 409 px off (beyond a circle's reach) and whose `exempt_group` is `&"pair_a"`: an avoiding mover's actor in `pair_a` gets the
  request back bit-identical (`var_to_bytes`); one in another group, and one in none, are steered (found by `around()` through the closest
  point). This is §2.6's "an actor in `exempt_group` gets `desired` back bit-identical"; it lives here, not in `test_context_avoidance.gd`,
  because the drop is `EnemyMover._avoid`'s and needs the registry and an actor (that file is node-free).
- `test_the_exempt_drop_drops_only_the_exempt_wall` (review M2, the own-claim row's "and nothing else is"): the same exempt actor with its pair's
  wall **and** a circle obstacle in its way is steered, bit-identically to the same actor with the circle alone.

### Boundaries
`contains` 38 / 39 px beside and beyond an end; `around` at exactly `radius + reach` and 1 px beyond; the static first-bend row that fails on the
literal arc; on the line / on an end; the parallel controls (the big circle, the turned wall) that make the bit-identity rows able to fail; the
merge-order row against an overwrite; exempt vs non-exempt actor, and the exempt drop with a second hazard present.

## Risks
- **The 24 px bound at 1.0 / 0.8 with margin 12:** expected 57.9 / 38.8 px with the chosen span; the pre-approved lever (`TWIN_HAZARD_PAD` 48,
  radius 62) stays available and is recorded if used. No bound moves.
- **0.6 at avoid_weight 0.5** skims the wall (11.4 px end-on in the rows; a real Bomber crosses head-on). Not gated (§2.6 bounds only 1.0 / 0.8);
  printed and recorded for t10's fence weight 1.0 and the twin-pair tasks.
- **The registry query is unled** (`EnemyMover._avoid` asks `Hazards.around()` at the wall's current closest point, the stage then leads it): a
  wall closing at 240 px/s is found no earlier than a static one. Pre-existing for circles and outside §2.6's "registry unchanged"; recorded so
  t5 / t12 test moving walls through a real mover.
- **Bit-identity:** the circle body is not edited and the new branch runs only for `segment_half != ZERO`; the existing rows and every
  level-1 replay prove it.
- **Gate time:** 18 + 18 printed accel-limited runs of ≤ 720 steps plus single-call sweeps; the scratch copy ran 72 runs in 0.13 s, so < 0.6 s
  against 1.5 s.

## Out of scope
- `EnemyBeam.hazard_info()`, registration while lit, `twin_beam.tscn` and the `export_of` reads (t5).
- Fences and their avoid_weight 1.0 (t10), level-1 laser columns (t17).
- Any change to the circle path, `falloff`, `accel_at`, the registry's code, or other `Hazards.around()` consumers. Those that a laser wall
  (`kind = &"laser_wall"`, no LOS block) reaches once t5 registers one: Fighter `_inside_other_hazard()`, Sniper `_candidate` (any
  non-LOS-blocker in reach makes a cover point not `hazard_ok`, `sniper_brain.gd:554–557`) and Sniper `_inside_other_hazard` (`:633–637`). All three
  become segment-aware through `contains`, the intended reading; no behaviour changes in t4 (no producer yet). Recorded in DECISIONS for t5.

## Answers to review round 1
| Finding | Answer |
|---|---|
| B1 span refinement into the wall | Span widened by the footprint tangent, plus the review's half slot when the request is on it; measured 0 into-the-wall deflections; static row added. |
| M1 lever / accel comment / roster | No lever expected (0.8 ≥ 38.8 px). Accel comment corrected. Printed roster row added (six ships). |
| M2 exempt row too weak | `test_the_exempt_drop_drops_only_the_exempt_wall` added. |
| M3 degenerate cases | `test_a_ship_inside_the_footprint_steps_outward` added; "on the line with the ends out of reach writes nothing" recorded. |
| m1 merge order | `test_a_wall_and_a_circle_merge_by_max_in_either_order` added. |
| m2 consumers / comment | Sniper's two paths listed (Out of scope + `1-context.md`); `hazards.gd:29` comment fixed. |
| m3 0.6 gate | 0.6 gated only on the bend and the first heading past an end; the rest printed. |
| m4 wording | 0.039; "led along its axis"; first-bend distance at the start noted. |
| Note: unled registry query | Risks + DECISIONS. |

## Revision 3: round-2 fold-ins (built as below; round 2 was APPROVED)
- **R2-1** The span's bounds are the capsule's true angular extent: relative to `a`'s bearing with `D = angle_difference(α, β)` (ends swapped
  so `D ≥ 0`), `lower = min(−ta, D − tb)`, `upper = max(ta, D + tb)`; `start = α + lower`, `length = upper − lower`. Differs from revision 2 only
  where one end's disc overhangs the other end's bearing (end-on views).
- **R2-2** The static first-bend row gains the geometry that fails a tangent-only build: wall centre (165, −60), half (0, 210), margin 12, 1.0.
- **R2-3** The half-slot widening also applies when the **blended aim** (`want · (1 − CONTEXT_PREV_BLEND) + prev_dir.normalized() ·
  CONTEXT_PREV_BLEND`, the tail's own expression, recomputed inside `_segment_danger`) lies on the arc; `_segment_danger` takes `prev_dir`.
- **R2-4** "A wall beside the path is ignored" holds bit-for-bit for slot-aligned requests; off-slot requests are nudged away from the wall by
  a fraction of a slot (review figures recorded in DECISIONS). The parallel row gains an off-slot case: the wall turned to 8° and 15°, 150 px
  beside, the request along it: heading within 0.5° of the request and speed ≥ 99 % wherever two end circles alone leave it untouched.
- **R2-5** The inside row runs at 1.0 / 0.8 / 0.6 × margins 12 / 60 with the circle row's "outward share > 0.1", and includes end-cap
  positions (beyond an end, inside the footprint).
- **R2-6** "No step crosses the line" is gated at 0.6 too (closest approach still printed only).
- **R2-7** The `segment_half` doc comment and DECISIONS say a segment info is for walls longer than `2 · radius`.
- **R2-8** The "turned wall" control sits at midpoint (150, 0), half (0, 210), avoidance 1.0, margin 60.

## As built (implementation notes; the design above stands)
- **`SEGMENT_ARC_TOLERANCE` (1e-5 rad).** `Vector2.angle()` is a 32-bit atan2 (float32 π is 8.7e-8 rad past π), so at the end-cap position
  (230, 0) the span's lower edge (exactly π/2 in exact arithmetic) came out a hair past a request exactly at 90°: the request was neither
  widened nor masked and was returned tangent (outward share −4e-8). The span's start and length are widened by the tolerance before every arc
  test, so its edges are inclusive as designed. No other row moved.
- **The inside row splits its positions.** Beside the middle, beside an end, 0.5 px off the line and on the axis past an end (including (230, 0),
  (−240, 0) and (225, −15)) keep the circle row's "outward share > 0.1" (worst 0.195). Two **diagonal** end-cap positions, (−236, 20) and
  (215, 30), are gated on "steps outward" only and their worst share is printed (0.031 at 0.8 / 0.6): there the wall acts as its end's 38 px
  circle, whose cone tail past 90° is under the threshold, so a request a degree or two past tangent goes through. A weight-0.5 circle at the
  same end steps *inward* there (−0.44 at 0.8, −0.95 at 0.6), so the wall is strictly better than the precedent; the review measured "> 0.1"
  only on the listed positions.
- **R2-3 is fixed and pinned:** `test_a_previous_heading_into_the_wall_cannot_pull_the_output_onto_it` (wall (240, −140) half (400, 30), request
  −2°, `prev_dir` −56°, 1.0, margin 60) returns 11.25°; without the blended-aim check it returns −11.25°, whose ray hits the wall.
- **Mutation checks** (each reverted): no half slot → the offset static row fails; no overhang (R2-1) → the end-cap inside rows fail; no tangent
  → 0.8 end-on 19.7 px < 24 and the inside rows fail; overwrite merge → the merge row fails; no blended aim → the R2-3 row fails; no span → the
  approach rows fail; closest-point skirt on every cone → the parallel rows fail; no exempt drop → both exempt rows fail; an over-broad drop
  (clear every info) → the M2 row fails.
