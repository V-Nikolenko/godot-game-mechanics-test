VERDICT: APPROVED

## Round 1

Reviewed `3-plan.md` and `1-context.md` against the epic plan (`docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md`: "For every task", §2.4,
§2.6) and against the code: `global/hazards/hazard_info.gd`, `global/hazards/hazards.gd`, `global/enemy_ai/steering.gd` (`context_avoid`,
lines 236–304), `global/enemy_ai/enemy_mover.gd` (`step`, `_avoid` 280–296), `tests/unit/test_hazards.gd`, `tests/unit/test_context_avoidance.gd`,
`tests/unit/test_enemy_mover.gd` (the avoidance section from line 703), every `Hazards.around()` consumer, and the roster `*_config.tres` / `*_config.gd`.

I didn't take the geometry on trust. I re-implemented `context_avoid` (the threshold, clear-way, masked pick, parabolic refinement and speed floor,
copied from `steering.gd`) plus the plan's `_segment_danger` in a scratch Node.js script (`/tmp/segreview/`, not committed; float64, so the GDScript
figures will differ in the decimals). I ran it over the plan's 18 approach rows, the parallel-wall rows and the roster profiles. Where a finding
depends on a number, I also worked it by hand below. The hand derivations don't depend on the prototype.

**What holds up (no change needed):**
- **Bit-identity.** The new branch sits after the `null` / `avoid_weight <= 0` skip (`steering.gd:248`) and `continue`s before line 250. The circle body
  (250–267) and the shared tail (269–304) are untouched. The `contains` / `penalty_at` branches lead and the circle expression follows unchanged. The
  mover's `elif` is a `StringName` compare. No circle float operation moves.
- **The per-cone skirt reading is justified.** In the prototype, the literal reading (the closest point's skirt on all three cones) bends the
  parallel-wall midpoint heading in 8 of the row's combinations (margin 60 and 90 at avoidance 1.0, both sides, both directions). The plan's reading
  bends none, and over a 184,080-case sweep (100–200 px beside, 200/420/800 px walls, margins 12–90, every avoidance level) it adds nothing that
  circles at both ends and at the closest point don't add. The "adds nothing its ends do not" restatement plus a literal midpoint row is a sound
  reading of §2.6's parallel row.
- **The shorter-arc rule is correct.** A segment that doesn't contain `pos` subtends less than 180°, so the shorter arc is exactly the arc the wall
  covers. End-on (α = β) gives a zero-width arc that the inclusive test keeps. ±π wrap is handled by `angle_difference`. The 180° case is exactly
  `d < 0.001`, which the plan skips.
- **The lead matches the circle:** the same `position + velocity · lookahead − pos`, applied to both ends.
- **Placing the exempt row in `test_enemy_mover.gd` is justified.** `context_avoid` is pure and takes no actor, and the drop belongs to `_avoid`
  (`enemy_mover.gd:286–289`).

### B1 (blocking): the span has no slot widening, so the shared refinement turns the output back into the wall, and the plan's own row (§2.6's "the output heading points past an end") fails

- **Where:** `3-plan.md:46–48` (span = exactly the arc between the end bearings), `3-plan.md:109` (assertion), epic `3-plan.md:330, 339`.
- **The mechanism:**
  - The circle cone carries `+ slot` (`steering.gd:262`) for a stated reason (`steering.gd:234`: "at most half a slot; the one-slot widening keeps
    that outside the tangent").
  - The refinement at `steering.gd:302` moves the picked slot up to half a slot toward the aim. When the wall is across the path, the aim points into
    the span.
  - The span has no widening. Its guard would have to come from the end cones, and under the plan's own per-cone skirt reading those are silent
    whenever the end is beyond its own reach, which is the usual case at first contact. At 0.8 and 0.6 they are also often under the threshold.
  - Result: the refined heading can sit up to 11.25° inside the end's bearing, aimed at the wall.
- **By hand, the plan's row φ 0°, margin 12, avoidance 0.8, radius 38:**
  - The span and the closest-point cone peak cross the 0.2 threshold together, at skirt 0.4, so d = 38 + 0.6 · 132 = 117.2 px.
  - End bearing β = atan(210 / 117.2) = 60.8°. The end cones are 240 px away (outside 202 > 132), so they write nothing.
  - The closest-point cone's half-width is 47.8°, which masks ±45° but not 67.5°.
  - Best free slot is 67.5°. The refinement uses the 45° and 90° neighbours (scores 0.707 and 0) and gives shift −0.5, so the output is 56.25°.
    That is 4.5° inside β.
  - The ray from (82.8, 0) at 56.25° reaches x = 200 at y = 175 < 210, so it hits the wall. The prototype agrees.
- **The lever doesn't fix it.** At radius 62 the threshold distance is 141.2 px, β ≈ 56.1°, and the 56.25° output is a coin flip against discretisation.
  The prototype has it hitting.
- **The φ 0°, margin 60, 0.8 row passes by about 1°** (ray clearance 2.5 px).
- **How often it happens:** over 20,000 random walls across a desired heading, with the ship outside the footprint, margins 12–90 and 200–320 px/s,
  26% of the deflected outputs at 1.0 and 41% at 0.8 still point into the wall.
- **Fix (verified in the prototype):**
  - When the desired heading's bearing lies on the span arc, extend the span by **half a slot** past each end's bearing, flat, at the span weight.
    `_segment_danger` then needs `want`.
  - The first free slot is then more than half a slot outside β, so the refined heading is strictly past β.
  - Results:
    - 0 into-the-wall deflections over the same 20,000 walls, tried with four `prev_dir` values.
    - 0 parallel false positives over the 184,080-case sweep. The parallel heading isn't on the span arc, so nothing is added.
    - All 18 rows' first outputs miss the wall.
  - Record this as a deviation from §2.6's literal arc in DECISIONS, with the reason (the same one as `steering.gd:234`).
- **Variants I rejected:**
  - An *unconditional* flat half-slot widening also clears every into-the-wall case, but it bends a ship flying parallel 100 px beside a wall whose
    far end lies within half a slot of its heading (5,120 / 184,080 false positives).
  - A full-slot widening fails the plan's own 150 px sweep row.
- **Add a static, lever-independent row that fails without the fix:**
  - Setup: a 420 px wall with ends at (110, ±210), ship at the origin, `desired` (200, 0), margin 12, avoidance 1.0 and 0.8, radius 38 and 62.
  - Assert the output ray misses the hit segment.
  - The plan's design returns 56.25° against an end bearing of 62.4°, so it hits. The fix returns 90°.

### M1 (should fix): predicted figures, so the lever decision isn't a surprise

- **Prototype figures (plan design, 200 px/s, 600 px/s², radius 38):**
  - The closest approach is under 24 px only at **φ 90°, margin 12, 0.8, ≈ 19.7 px**: rounding the far end with a target on the wall's own line,
    where the end acts as a 38 px circle at weight 0.5 and the 0.2 threshold.
  - With the B1 fix it stays ≈ 19.7; with the lever (radius 62) it is ≈ 27.6.
  - Every other 1.0 / 0.8 row is 26–108 px.
- **Expect to use the pre-approved lever (`TWIN_HAZARD_PAD` 48).** Record it as the plan says (`3-plan.md:74–75, 136–137`); no bound moves.
- **Not lenient against the roster.** Margin 12 at 0.8 is not a roster pairing (the 0.8 ships use 60 / 60 / 24), and real profiles at their own
  speeds come out wider, because speed widens the skirt reach:
  - Fighter 300 / 700 / 60: φ 90° ≈ 35.
  - Gatling 260 / 600 / 60: ≈ 32.
  - Mine Layer 240 / 420 / 24: ≈ 26.5.
  - Swarm 220 / 600 / 12 at 1.0: ≥ 53.
- **But the justification at `3-plan.md:102` is wrong.** 600 is not "the lowest of the small 0.8–1.0 ships": the Mine Layer is 0.8 with accel 420
  (`mine_layer_config.gd:15–16`, max 240), and the Sniper is 1.0 with 520 (`sniper_config.gd:14–15`).
- **Fix:** correct the comment, and add one *printed* (not gated) roster row per profile (Swarm, Fighter, Gatling, Mine Layer at their own
  max_speed / accel / margin) so DECISIONS records figures for real ships. That's about 12 extra runs, well inside the 1.5 s allotment.

### M2 (should fix): the exempt row can't catch an over-broad drop

- **Where:** `3-plan.md:125–129`. An `_avoid` that returns `desired` (or clears `infos`) whenever any exempt info is present would pass the row
  as written.
- **Fix:** add the case the own-claim row already has (`test_enemy_mover.gd:771–797`, "and nothing else is"). The exempt actor, with its pair's
  wall plus a circle `_obstacle` in its way, is still steered, bit-identically to the same actor with the circle alone.

### M3 (should fix): no steering row covers the degenerate cases the plan specifies

- **Where:** `3-plan.md:45`. On the line, on an end, and a hair off the line are pinned only for `closest_point` (test_hazards). The steering
  branch's skips are untested, so a NaN or a wrong bearing from `Vector2.ZERO.angle()` would go unseen.
- **Fix:** add a row in the shape of `test_inside_the_first_step_points_outward` (`test_context_avoidance.gd:100–117`):
  - Positions inside the footprint, beside the middle, beside an end and 0.5 px off the line, over the 16 slot headings: the output steps outward
    (positive dot with `pos − closest_point`) and keeps at least 35% speed.
  - Exactly on the line and exactly on an end: the output is finite and at least 35% speed.
- In the prototype every off-line inside position steps outward.
- Record in DECISIONS that exactly on the line, with the ends out of reach, the wall writes nothing. This mirrors the circle's centre skip
  (`steering.gd:252–253`); it is measure-zero and accepted.

### m1: no row pins the MAX merge between a segment and a circle

- **Where:** `3-plan.md:31–35`. An overwrite (`danger = seg`) instead of `maxf` passes every single-info row.
- **Fix:** one row: `[circle, wall]` and `[wall, circle]` return identical bytes, and differ from either alone, in a geometry where both write.

### m2: `1-context.md:32–34` and `3-plan.md:148–149` misstate the `around()` consumers

- **What's wrong:** these say a laser wall is skipped by every consumer except Fighter `_inside_other_hazard()`. Two Sniper paths also see it:
  - Sniper `_candidate` (`sniper_brain.gd:554–557`) sets `hazard_ok = false` for any non-line-of-sight-blocker in reach.
  - Sniper `_inside_other_hazard` (`sniper_brain.gd:633–637`) rejects any other info.
- **Impact:** both become segment-aware through `contains`. That's the intended reading, and there's no behaviour change in t4 (no producer yet).
- **Fix:** correct the list and record it in DECISIONS for t5.
- **Related:** `hazards.gd:29`'s doc comment still states the circle formula. Make a comment-only edit ("within `radius + reach` of the info's
  closest point").

### m3: the 0.6 "never crosses the hit segment" assertion is fragile

- **Where:** `3-plan.md:110`. At avoid_weight 0.5 and threshold 0.4, the prototype has the 0.6 runs at 2.0–5.3 px from the line at 200 / 600, and
  ≈ 0.1 px for a Bomber profile (240 / 260 / 70, φ 0°).
- **Context:** the plan's escalate-on-failure path is legitimate. But §2.6 asks only for "avoided … the output heading points past an end" at 0.6,
  with the bound limited to 1.0 / 0.8.
- **Fix:** gate 0.6 on the deflection and the first output past an end, and print its closest approach. Record in DECISIONS that a 0.6 ship skims
  a weight-0.5 wall, as input for the fence's weight 1.0 in t10.

### m4: wording and arithmetic

- **`3-plan.md:53`:** the danger is `0.5 · 0.378 · 0.207 = 0.039`, not 0.078 (`avoid_weight` was dropped). The conclusion stands.
- **`3-plan.md:121`:** "both ends are led, not just the midpoint" isn't something the row can distinguish, because the ends are the midpoint ±
  `segment_half`. Say "led along the wall's own axis, not only across it".
- **`3-plan.md:106–108`:** at φ 45° the near end is 157 px from the start and the closest point is 141 px, so the run starts inside the skirt. The
  same holds for margin 60 at φ 0° (200 < 218). The recorded "first deflection distance" is then the start. Note it, or add one start further
  back, so the figure means something.

### Note (no change in t4): the registry query is unled

- **What:** `EnemyMover._avoid` finds infos with `Hazards.around(pos, …)` at the wall's *current* closest point (`enemy_mover.gd:285`), while
  `context_avoid` leads by `velocity · 0.6`.
- **Effect:** a wall closing at 240 px/s is found no earlier than a static one, even though the pure-function row shows the lead working 144 px
  sooner.
- This is pre-existing for circles and outside §2.6's "registry unchanged". Record it in DECISIONS so t5 / t12 test moving walls through a real
  mover.

### To approve

Revise for B1, M1 (lever expectation and the corrected accel justification, plus the printed roster rows), M2 and M3. Fold in m1–m4.

## Round 2

Reviewed revision 2 of `3-plan.md` and `1-context.md` against the same code: `global/enemy_ai/steering.gd` (`context_avoid` 236–304, the `+ slot`
rationale at 234), `global/hazards/hazard_info.gd`, `global/hazards/hazards.gd:29`, `global/enemy_ai/enemy_mover.gd::_avoid` (280–296), the three
test files and the roster configs. Round 1's prototype was still in `/tmp/segreview/`. I rebuilt the stage from revision 2's *text*, in a new
float64 Node.js copy (`/tmp/segreview2/sim3.js`, not committed). It reproduces the plan's figures exactly: 1.0 ≥ 57.9, 0.8 ≥ 38.8, 0.6 ≥ 11.4 px,
Swarm 59.1, Fighter 47.8, Gatling 43.8, Mine Layer 39.3, the Bomber's φ 0° crossing (0.1 px) and its weight-1.0 46.2 / 55.1 / 55.2. So the plan's
text is precise enough to build from.

### Round 1 findings: status

| Finding | Status |
|---|---|
| B1 | **Resolved.** The static row: the literal arc returns ±56.25° (or ±123.75° mirrored), which hits; revision 2 returns ±90°, which misses, at radius 38 and 62. All 18 approach rows' first bends miss the line, none crosses, and 0.8 keeps 14.8 px over the bound, so no lever is needed. |
| M1 | Resolved. The accel comment is corrected (`3-plan.md:126`). The printed roster row is added; its figures match mine (see R2-9). |
| M2 | Resolved (`3-plan.md:173–174`). |
| M3 | Resolved. Add the levels to the row (R2-5). |
| m1–m4, note | Resolved. The merge row catches an overwrite and a sum; the Sniper consumers and the `hazards.gd:29` comment are listed; 0.6 is gated on the bend and the first heading. |

### What holds up

- **The guarantee, for a request on the span.**
  - Say `want` lies on the tangent-widened arc. The span then covers that arc plus half a slot each side. Two adjacent slots that bracket `want`
    can't both fall outside an inclusive interval of length ≥ one slot that contains `want`. So the clear-way test fails, whatever `want`'s
    alignment.
  - The span writes `avoid_weight · skirt_c`, which is the closest-point cone's peak. So the span is above the threshold whenever anything the
    wall writes is.
  - The picked slot is therefore more than half a slot outside the tangent arc. The refinement moves at most half a slot. The heading ends
    outside the tangent arc, which contains the literal arc, so **its ray misses the hit segment**.
  - Two exceptions, below: the arc is not the full capsule extent near end-on views (R2-1), and the span can cover all 16 slots (R2-7).
- **Measured, with `want` through the wall:**
  - 20,000 random walls, at any orientation (not only slot-aligned), with 9 `prev_dir` each: 0 into-the-wall outputs at 1.0 / 0.8 / 0.6.
  - Closed loop: 3,800 runs at accel 420–900 and margins 12–90, with a target sliding behind the wall. 0 crossings at 1.0 / 0.8, and at least
    21.1 px at 0.8. The literal arc crosses 13 times in 600 runs.
- **Slot-aligned parallel passes are untouched.**
  - The far end's tangent edge reaches the heading only when the lateral offset is ≤ `radius`, because the tangent is exact for that disc.
  - 0 changes out of 75,600 requests (beside offsets 39–200 px, which includes ships inside the margin band; walls 200 / 420 / 800 px) beyond
    what the cones alone make.
  - The plan's midpoint row and its sweep pass, and both controls bend (but see R2-8).
- **Bit-identity is unchanged.** `want`, `slot` and `skirt_reach` are locals already computed before the loop (`steering.gd:242–245`). The new
  branch leads and `continue`s, and no float operation on the circle path moves. The `HazardInfo` and `_avoid` additions only lead or `elif`.
- **The 0.6 handling meets §2.6's text.** The epic asks for "avoided … the output heading points past an end" at 0.6 and bounds only 1.0 / 0.8.
  The plan gates exactly that.

### Findings (none blocking; fold in during implementation, R2-1 and R2-2 strongly recommended)

**R2-1: the per-end tangent widening isn't the capsule's angular extent near end-on views** (`3-plan.md:51–52`)
- **The mechanism:**
  - The construction widens `a`'s side by `ta` only, and `b`'s side by `tb` only.
  - When one end's disc overhangs the other end's bearing (Δ < |ta − tb|), the true extent is wider on the far end's side.
  - At Δ = 0 (end-on), the near end's 90° tangent is applied to one side only.
- **Example, at avoidance 0.8, with the wall from (−210, 0) to (210, 0) and the ship 20 px beyond an end at (230, 0), inside the footprint:**
  - The span is [175°, 270°] only.
  - A request at 95.7° comes back as 95.68° and steps 0.05 px *closer*. The mirrored −95.7° is turned to −78.75° and steps away.
  - At (225, −15), at 0.6, an output steps 1.65 px closer per tick (outward share −0.56).
  - This is no worse than a weight-0.5 circle there, which lets 36–45 % of inside headings step inward at 0.8 / 0.6. But it contradicts the
    plan's "angular extent of the capsule".
- **Fix:** relative to `a`'s bearing, with `D = angle_difference(a.angle(), b.angle())`:
  - `lower = minf(-ta, D - tb)` and `upper = maxf(ta, D + tb)`.
  - `start = a.angle() + lower` and `length = upper - lower`.
  - This is identical to the plan's formula except in the overhang case.
- **Verified:**
  - The 1.0 / 0.8 rows are unchanged (57.9 / 38.8).
  - The six **0.6 rows go from 11.4 to 30.0 px** (φ 90°: 31.1 / 38.9).
  - The static row, the parallel sweeps, the into-the-wall rates, the Bomber rows and the closed loop are unchanged.
  - Every inside position, including two end-cap positions, now steps outward at 1.0 / 0.8 / 0.6.
- **Also:** add one end-cap position (beyond an end, inside the footprint) to the inside row.

**R2-2: no row fails a build without the half slot** (`3-plan.md:141–143`)
- **The gap:** a tangent-only build passes all 18 approach rows (0.8 ≥ 37.3 px), the static row (it returns ±90°, because the end at 237 px has a
  9.2° tangent that already masks 67.5°) and the listed inside positions.
- **Why it matters:** the plan's own measurement has that build at 10.8 / 11.7 / 9.0 % into the wall, so the design choice isn't pinned.
- **Fix:** add one static geometry where the near end is past 195 px, so its tangent is under half a slot:
  - Wall centre (165, −60), half (0, 210), so the ends are (165, −270) and (165, 150).
  - Ship at the origin, `desired` (200, 0), margin 12, avoidance 1.0.
  - Tangent-only returns −56.25°, whose ray meets x = 165 at y = −246.9, on the wall. The plan's design returns 56.25°, which misses.
  - About 2° of angular slack either way. It also passes with R2-1 and R2-3 applied.

**R2-3: the guarantee is conditional on `want`, and the blended aim can still pull the output into the wall** (`3-plan.md:53–55, 69–72`)
- **When it happens:** `want` points past one end, outside the tangent arc, so there is no half slot. Meanwhile the `prev_dir` blend puts the aim
  across the wall.
- **Example, at 1.0 with margin 84:**
  - `want` −154.9° sits 3.4° past end `a`'s tangent edge. `prev` points past end `b`, which is 681 px away with a 3.2° tangent.
  - The best slot is −22.5°, and the half-slot refinement toward the mid-wall aim gives −33.75°. That is inside `b`'s bearing of −30.0°, so the
    ray hits.
- **How often:** 0.12 % / 0.30 % of deflections at 1.0 / 0.8, over 40,000 walls (off-centre, any orientation, 9 `prev_dir`). It's 0 when `want`
  is on the line, and 0 crossings in closed loop. So the plan's "0 / 0 / 0" holds only for its distribution.
- **Fix, either of:**
  - Record it in DECISIONS with the figure and the mechanism.
  - Or (cheap, verified) also widen when the blended aim is on the arc. The aim is `want · (1 − CONTEXT_PREV_BLEND) +
    prev_dir.normalized() · CONTEXT_PREV_BLEND`, the tail's own expression. Pass `prev_dir` into `_segment_danger` and recompute the aim there, so
    the shared tail is untouched. Results:
    - 0 / 0 / 0 over the same 40,000 walls.
    - The approach rows, static row, parallel sweep, inside row and closed loop are unchanged.
- **Either way:** reword the "0 / 0 / 0" sentence to name its distribution.

**R2-4: "never touch a heading along the wall" is true only for slot-aligned requests** (`3-plan.md:71–73, 152`)
- **The mechanism:** with an off-slot request, the bracketing slot on the wall's side is up to 22.5° toward the wall. The span masks it whenever
  its ray meets the footprint anywhere along the wall, and the refinement can then reach only half a slot from the free neighbour.
- **Max heading change**, always away from the wall, speed ≥ 0.98 (this plan vs the literal arc):

  | Beside offset | Wall length | This plan | Literal arc |
  |---|---|---|---|
  | 150 px | 420 px | 0.06° (bit-level only) | 0.06° |
  | 150 px | 800 px | 3.25° | 0.75° |
  | 120 px | 420 px | 3.0° | 0.06° |
  | 100 px | 420 px | 5.25° | 1.75° |
  | 60 px | 420 px | 9.0° | 5.5° |

- **Judgement:** benign, and the epic row (150 px beside 420 px) still holds to within 0.06°. But the sentence overstates it, and t10 / t17 walls
  may be longer.
- **Fix:**
  - Correct the sentence and record these figures in DECISIONS.
  - Add one off-slot case to the parallel row, in the shape of `test_a_heading_between_two_slots_is_not_quantised`: the wall rotated with a
    `desired` at 8° and at 15°, 150 px beside, over the same sweep. Assert the heading stays within 0.5° of the request and the speed is ≥ 99 %.
  - This pins "beside = ignored" against a later widening.

**R2-5: the inside row needs its avoidance levels and margins named** (`3-plan.md:144–148`)
- **Why:** at 1.0 the literal arc and a span-less build pass too. The row's teeth are at 0.8 / 0.6, where they fail 28–50 of 64 requests per
  position.
- **Specify:** 1.0 / 0.8 / 0.6 and margins 12 / 60.
- **Measured with revision 2 at the listed positions:** worst outward share 0.20 and minimum gain 0.228 px per tick. So the circle row's stronger
  assertion (outward share > 0.1, `test_context_avoidance.gd:115–117`) holds too, and the "dot 0 level with an end" allowance isn't needed. Prefer
  the stronger assertion. The end-cap position needs R2-1.

**R2-6: gate "no step crosses" at 0.6 too, and widen the 0.6 note** (`3-plan.md:136, 184–185`)
- **Gate it:** with revision 2 the six 0.6 rows keep ≥ 11.4 px (30.0 with R2-1), so "no step crosses the hit segment" is no longer fragile, and
  it's a closer reading of "avoided". Keep the closest-approach figure printed.
- **Record it:** in the closed loop, 0.6 crosses a weight-0.5 wall in 3.5–5 % of moving-target runs (28–41 / 800), not only the head-on Bomber.
  Add that to DECISIONS for t5 / t10.

**R2-7 (note): a wall shorter than 2 · `radius` can blind the span**
- **What happens:** with the ship inside both end discs, `ta = tb = 90°`, so the widened span can cover all 16 slots. Every slot then carries
  equal danger and the clear way returns `desired`.
- **Example:** a 60 px wall gives 102 of 1,152 inside requests that don't step outward.
- **Reachability:** none in Phase 8. The twin beam is 420 ± 16 px and collapses outside that, and the fence is ≈ 300 px.
- **Why not a guard:** a guard that skips the span when `length ≥ TAU − slot` doesn't fix it.
- **Fix:** one line in the `segment_half` doc comment and in DECISIONS: a segment info is for walls longer than `2 · radius`.

**R2-8 (wording): the "turned wall" control** (`3-plan.md:154`)
- **The problem:** turning the parallel wall about its own midpoint (0, 150) puts the ship *on* the line. The span and the closest-point cone are
  then skipped, and the control bends only at 1.0, through the 60 px end.
- **Fix:** name the placement (for example midpoint (150, 0), half (0, 210)) and the control's avoidance and margin.

**R2-9 (note): expected figures**
- My copy gives Sniper 89.4 (the plan says ≥ 90) and Bomber φ 90° 11.4 (the plan says 11.8). Everything else matches to 0.1 px.
- These are printed only. Record whatever the GDScript run prints.

### Verdict

**APPROVED.** B1 is fixed and the fix is sound, and every round-1 item is answered. Fold in R2-1 and R2-2 (two small changes, both verified),
plus R2-4, R2-5, R2-6 and R2-8, and either fix or record R2-3. Record R2-7 and R2-9 in DECISIONS.
