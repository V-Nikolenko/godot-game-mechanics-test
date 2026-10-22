VERDICT: CHANGES_REQUESTED

# Review, round 1: t4 context-steering avoidance stage (`3-plan.md`)

Independent review against epic plan §2.4 / §2.2 / "For every task" (`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`
:26-82, :211-276, :310-358), research F1/F2/F10 (`2-research.md`:56-65, :142), and the code. Only the test plan
needs changes. The design, the four refinements, the mover wiring and the build sequence are sound, and I am
not sending them back to the owner. Five test defects must be fixed before implementation: three pre-written
rows are wrong (one fails on a correct build, one can never fail, one rests on a premise the design does not
give), one row has no control, and one regression gap has no test.

## What I checked in the code (the plan's claims hold)

- `global/enemy_ai/enemy_mover.gd:208-266`: `step()` runs boost/cap → slow → `_avoid(desired)` (only `if hazards_live`
  and `not boosting`, :224-229) → accel limit → drift → `constraint.filter` → write. `_avoid()` is the t2 no-op at
  :269-270. The plan's hook placement, the "never while boosting" rule and the corridor-after-stage order are all
  already here, so the only new mover code is `_avoid()` and `_avoid_prev`. `halt()` (:149-157) is where the clear goes.
- `global/hazards/hazards.gd:29-35`: `around(pos, reach)` filters on the **current** centre (`info.contains`),
  allocates, and returns `HazardInfo`s. `hazard_info.gd` has `velocity`, `avoid_weight`, `line_of_sight_blocker` and
  `is_claimed_by()` (:98-99) as the plan says. `hazard_field.gd:168-179` never sets `line_of_sight_blocker`, and
  `avoid_weight` defaults to 1.0 (:29). So "wells are never dropped" holds by construction.
- `global/enemy_ai/steering.gd:1-12`: a pure static `RefCounted`. No context or danger-map code exists anywhere
  outside the new test (grep), so nothing is being rebuilt that already exists.
- Brains: every `mover.boost()` caller is the one the plan names: `swarm_drone_brain.gd:439` (BURST),
  `razor_drone_brain.gd:437` (feint lunge), `:515` (dash), `:694` (IDLE_BOOST), `ram_corvette_brain.gd:464` (CHARGE).
  Swarm APPROACH is `Steering.corkscrew` (`swarm_drone_brain.gd:299`, `steering.gd:106-109`: lateral 120 px/s at
  0.6 Hz, about 32 px of weave). The Fighter APPROACH is the Dubins lead-in (`fighter_brain.gd:9`, :643).
- Conventions: nothing new in `global/` references `ArenaCamera`. There is no rng and no `Timer`. The mover stays
  the only writer (the stage only changes `desired`). The pass-through is bit-identical with `count() == 0`
  (stage never entered) and with an empty `around()` (return `desired` untouched).

## The four refinements: all justified, none needs to go back to the owner

1. **Inside-case danger formula** (`3-plan.md`:34-40). Justified. With the epic's `max(0, cos)`, the tangent
   slots carry about 0, and the raw-cosine ranking then picks the tangent for a ship heading through the centre.
   That gives `out · outward = 0`, which fails "inside → first step outward". The plan's formula is the outside
   formula's own limit at `d ≤ R` (skirt 1, θ = 90° + one slot), so the danger map is continuous across the edge.
   It is also *better* than the epic's formula for soft profiles. After the threshold, the epic's version leaves a
   0.8 ship free to take slightly inward headings (cos φ > 0.2 masks only φ < 78.5°). The plan's version keeps it
   at φ ≥ 90°.
2. **Hysteresis on the selection, not the output** (:52-59). Justified. It is closer to the source than the
   epic's wording: research F1 (`2-research.md`:56) says "blending in the previous frame's map", and option D
   (:142) says "the mover gains state (previous map for hysteresis)". Blending `prev_dir` into the interest is the
   cheap form of that. `test_prev_dir_keeps_the_side_it_chose` pins it.
3. **Ranking by the signed cosine** (:60-62). Justified. With `max(0, ·)`, every slot more than 90° from
   `desired` ties at 0 behind a hazard. The speed rule (:68-70) keeps the epic's `max(·, 0.35)` floor, so the
   epic's §2.4 step 6 is unchanged.
4. **Clear-way pass-through** (:42-50). Justified, and a superset of the epic's step 4. I checked the
   containment argument. θ ≥ asin((R+margin)/d) + one slot, and any cone that wide puts danger on at least one
   of the two slots either side of a `desired` lying inside the tangent cone. So a zero-danger bracket implies
   the straight-line path clears `R + margin`. It also makes the threshold's "ignore" bit-exact, which the
   soft-profile row asserts.

## Required changes

**C1. `tests/unit/test_enemy_mover.gd:828-840` `test_boost_and_halt_clear_the_avoidance_memory` fails on a correct
build.** `boost(Vector2.UP, 300.0, 0.1)` (:833) lasts 0.1 s, which is 6.4 steps at `DT_EXACT = 1/64` (:14).
`_boost_left` is only decremented after each step (`enemy_mover.gd:263-264`), so both `_advance(mover, (300, 0))`
calls (:836-837) are still boost steps. The plan says to clear `_avoid_prev` while boosting, so it is still
`ZERO` and `assert_ne(mover._avoid_prev, Vector2.ZERO)` (:838) fails. Fix: advance until
`not mover.is_boosting()` before the two plain steps, or make the boost shorter than one step. Do not change the
design to fit the test.

**C2. The "claimed by another node is avoided" half of the dual-mode claimed-wreck row cannot fail.** The plan
(`3-plan.md`:144) specifies "never within `radius + 50 − 10`", and the row asserts exactly that
(`test_enemy_dual_mode.gd:881`). But the cover point is itself `radius + 50` from the wreck (:864), and the
fixture wreck has no body. A build with no avoidance stage at all arrives on the cover point, its closest
approach about 110 > 100, and passes. This is the only dual-mode evidence for "a wreck claimed by another node
is avoided", so it must discriminate. Assert that the ship never reaches the cover: for example
`closest > radius + 50 + 10`, or a final distance to `cover` of more than 10 px. Fix the plan text to match. With
the Sniper's 90 px margin, the stage masks every heading within 112.5° of the centre inside `R + 90`, so a
correct build stays near `R + 90` and has plenty of room.

**C3. The corridor dual-mode row uses a profile whose "steering out" the design does not guarantee**
(`test_enemy_dual_mode.gd:890-907`; the plan, :145-146, names no profile). The row puts a Fighter profile
(avoidance 0.8, :896) 80 px from the centre of a weight-1 hazard and expects the stage to push it outward past
the visible edge. Under the plan's own formula:

- At the start, the tangent slots' inside danger is `1 − 90/112.5 = 0.2`, exactly the threshold `1 − 0.8`, so
  float noise decides whether they are masked.
- After one step off the axis, the tangent slot drops below the threshold. With `want = −x`, the ship then takes
  the tangent slot (score 0, a flat triple, so no refinement).
- Once the bearing has turned 22.5°, it takes the next slot round. It slides round the centre toward −x instead
  of leaving, so `furthest` stays near −20 px and both modes' assertions fail.

This is the intended semantics of a soft profile (it never heads inward, but it is not forced out). The
acceptance criterion "inside → first step outward" is stated for full avoidance. Use an avoidance-1.0 profile
(Sniper or Swarm values) at a speed ≤ the corridor's `edge_pressure` (200), and name the profile in the plan.

**C4. The Fighter real-brain row has no control proving the well was in its path**
(`test_enemy_dual_mode.gd:931-948`). Its sanity check `closest < 120` (:948) passes on a path that runs 100 px
clear of the edge. Build step 5 says to "tune the scenario geometry by measurement", which can quietly produce
a scenario where the well is never in the way. Add a control: the same fighter with `hazard_avoidance = 0` does
enter the radius (`closest < 0`). The Swarm skim row (:912-928) probably discriminates already: the corkscrew
weaves only about 32 px either side of y = 360, straight across a radius-120 well. Give it the same one-line
control so tuning cannot erode it.

**C5. The threshold's other half (R6.8, "reacts only when heading squarely in") is untested.**
`test_half_avoidance_...` (`test_context_avoidance.gd:125`) and `test_danger_merges_by_max_not_sum` show only that
avoidance 0.5 *ignores* things. Both stay green on a build that turns avoidance off entirely below 1.0. Every
soft row also uses exactly 0.5, where subtracting `avoidance` instead of `1 − avoidance` is indistinguishable.
Add:

- a 0.5 ship heading squarely into a well's centre from inside its skirt is deflected (the Ram case);
- one soft row at a value other than 0.5 (for example 0.8 bends where 0.5 does not, or ignores where 1.0
  bends).

## Minor (fix while implementing; no re-review needed)

- **M1. List the helper files the plan relies on.** The build sequence and file list omit
  `tests/helpers/fixture_wreck.gd` (new, untracked, already written) and the `arrive_point` / `arrive_speed`
  extension of `tests/helpers/fixture_brain.gd` (already in the working tree). Add both.
  `fixture_wreck.gd` has no `.uid` yet: let `--import` mint it, never hand-type one.
- **M2. One existing row does reach the stage.** `3-plan.md`:154 says "no hazard is registered in any of them",
  but t2's `test_a_ram_corvettes_line_up_inside_a_well...` (`test_enemy_dual_mode.gd:731`) runs a real Ram
  (avoidance 0.5) inside a well, so the stage now runs there. It is harmless: LINE_UP requests `Vector2.ZERO`
  (`ram_corvette_brain.gd:390`), so `_avoid()` returns early. Say so instead of claiming no existing row reaches
  the stage.
- **M3. The blend can collapse to zero.** `aim = 0.5·want + 0.5·prev` (:53) is near zero when a brain reverses its
  request (want ≈ −prev), and the ranking is then decided by noise or slot index. Use `want` when `|aim|` is below
  a small ε.
- **M4. `_avoid_prev` can go stale.** It is cleared only inside `_avoid()`. When the last hazard leaves the
  registry, the `hazards_live` early-out (`enemy_mover.gd:215`) skips the stage, and the old direction biases the
  first selection whenever a hazard reappears. Clear it on the skip path too. It is a field write, so the
  bit-identical rows are unaffected.
- **M5. Record the deviations and the known limitations.** The epic's rule (`3-plan.md`:80-81) puts any deviation
  later phases depend on into DECISIONS.md Phase 6. Record the four refinements there, plus two items:
  - the Razor IDLE_BOOST bypass, which t17 needs;
  - the "led only once within `around()` reach" limitation, which matters for t15's debris (200 px/s gives a
    120 px lead at 0.6 s, `3-plan.md`:633). Either note it for t15, or pad the reach by a lead allowance. That
    is safe, because `context_avoid` already skips any info whose skirt is 0.

## Verdict

CHANGES_REQUESTED: fix C1–C5 in the test plan and the already-written rows. The design itself, including all four
refinements, is approved as written.

VERDICT: CHANGES_REQUESTED

# Review, round 2: the revised test plan (`3-plan.md`) and its written rows

**Result.** C1, C2, C4 and C5 are resolved, and so are M1–M5. C3 is not resolved: the revised corridor row fails on a
correct build. I also found three new defects in the rows already written. All four problems are in tests. The design,
the mover wiring and the build sequence stay approved, and nothing goes back to the owner.

**How I checked.** I did not take the arithmetic on trust. I built the plan's implementation in a scratch copy of the
project (`/tmp/rv4`; nothing in the repo was touched). That build is `/tmp/t4/steering_add.gd` plus the two changes the
plan adds to it (the on-slot bracket at `3-plan.md`:45-48 and the M3 collapse fallback at :57), and `_avoid()` /
`_avoid_prev` as `3-plan.md`:77-87 specifies. I ran the three test files under GUT on it, then the whole suite. I also
ran three mutants, to check that the rows can fail:

- **no stage**: `_avoid()` returns `desired`;
- **threshold = `avoidance`**: the threshold subtracts `avoidance` instead of `1 − avoidance`;
- **off below 1.0**: the stage does nothing below 1.0.

The full suite on the plan build has the :992 parse fix (R2) applied. It ran 1954 tests and 1950 passed. The 4 failures
are R1, R3, R4 and the Fighter geometry (C4, below). No existing row regressed. That includes M2's Ram row, which passes.
GUT reported 199.9 s against the 199.0 s baseline in `/tmp/t4/gate-before.txt`, well inside +3.5 s. That timing is
indicative only.

## Round 1 findings

- **C1, resolved.** `tests/unit/test_enemy_mover.gd`:836 now loops `while mover.is_boosting()`.
  - The 0.1 s boost ends after 7 steps at 1/64 s (0.1 − 7/64 < 0).
  - The two plain steps then start at about (3, −33), about 200 px from the obstacle. That is inside the reach
    100 + 60 + 300·0.6 = 340.
  - `desired` = +x sits exactly on slot 0. The bearing to the obstacle is about 10° off it, so the slot has danger
    above `lo` = 0, the stage selects a heading, and `_avoid_prev ≠ 0`.
  - Measured: the plan build passes all 62 rows in the file. The no-stage mutant fails this row at :831.
- **C2, resolved.** `test_enemy_dual_mode.gd`:881-883 now asserts closest > `radius + 60` and final distance > 10 px.
  The plan text matches (`3-plan.md`:163-167).

  | Build | Closest to the wreck | Final distance to the cover | Result |
  |---|---|---|---|
  | Plan, both modes | 163.1 px | 253.3 px | passes |
  | No stage | 97.1 px | 0.35 px | fails both assertions |

  The "self" half passes.
- **C3, NOT resolved.** See R1.
- **C4, resolved in design.**
  - **Swarm skim** (:934-945): passes in both modes on the plan build, and its control enters the well. The no-stage
    mutant fails "never inside" (closest −95.9 px in Open Space, −86.5 px in Assault).
  - **Fighter** (:967-976): the new control does its job. It **rejects the current geometry**: unavoiding, the approach
    stays 131.3 px (Open Space) and 72.9 px (Assault) clear of the well at (320, 190). With no well at all:
    - the Open Space approach loops out to about x = −406 and reaches RUN_IN at tick 326;
    - the Assault one never reaches RUN_IN: its budget runs out, it goes to DISENGAGE and parks at (−347, −60), so
      `run.reached` fails in Assault whatever the stage does.

    This is the step-5 geometry tuning the plan allows, not a blocker. To keep the budget out of the row, use
    `fighter.config.engage_seconds = 1000.0` (a private copy, as the t2 Ram row does at :737).
- **C5, resolved.**
  - **The squarely-in row** (`test_context_avoidance.gd`:142-152): at (−200, 0) heading +x, d = 200, M = 240, skirt
    0.667, θ = asin(0.9) + 22.5° = 86.7°.
    - Slot 0 has 0.667 − 0.5 = 0.167, so it is masked.
    - Slot 1 has 0.667·(1 − 22.5/86.7) − 0.5 < 0, so it is free.
    - The parabola over (1, 0.924, 0.707) clamps to half a slot, so the heading is 11.25° and |y| = 0.195 > 0.1.
  - **The 0.8 row** (:158-171):
    - On y = −170, slot 0's danger peaks at about 0.26 (x ≈ −50: skirt 0.76 · (1 − 73.6°/112.5°)). That is above 0.8's
      threshold of 0.2 and below 0.5's.
    - On y = −190 it peaks at about 0.14, below 0.2.
  - **Mutants**: the threshold = `avoidance` mutant fails :163, along with eight other rows. The off-below-1.0 mutant
    fails :147, :151 and :163-164.
- **M1–M5, all reflected.**
  - M1: `3-plan.md`:107-111.
  - M2: :180-183, measured green.
  - M3: :57, pinned by the test at :235-238.
  - M4: :85-87, pinned at `test_enemy_mover.gd`:845-848.
  - M5: :93-100.

  Note on M3 and the on-slot rule: the unpatched `/tmp/t4/steering_add.gd` fails three rows: :131 (the soft pass is not
  bit-exact), :168 and :237. So those rows discriminate the plan's two changes. Implement from the plan, not from that
  draft.

## Required changes (round 2)

**R1. (C3) The corridor row fails on a correct build, and it cannot discriminate either way**
(`test_enemy_dual_mode.gd`:892-910; plan :168-171).

- **Measured.** `furthest` is −12.4 px in both modes, starting from −20. The no-stage mutant gives −20.1. Both modes'
  assertions fail on both builds.
- **The cause is the design, which is working as intended.** A want straight through the centre makes the stage take
  the free slot nearest to −x, about 112.5° from the bearing:
  - step 0's output is (26.8, 64.7): slot 3 at the 0.35 speed floor;
  - the ship slides round inside the hazard and leaves through its bottom (y ≈ 545), then flies −x;
  - it never crosses the right edge.

  "Inside → steps outward" is radial, not "back out the way it came".
- **Proposed replacement, measured on the plan build.** Keep the same radius-300, pull-free hazard and the Sniper profile
  at 200 px/s. Start the ship at `(rect.end.x − 20, centre.y − 500)` with the brain requesting `(0, 200)` (down along the
  edge, past the hazard), and run 8 s.

  | Hazard centre | Open Space `furthest` | Assault `furthest` | No-stage `furthest` |
  |---|---|---|---|
  | `rect.end.x − 100` | 331.7 px | 13.6 px | −20.0 px |
  | `rect.end.x − 150` | 282.6 px | 13.6 px | −20.0 px |

  The no-stage figure is the same in both modes. So the row's existing assertions (Open Space > `soft_band`; Assault > 0
  and < `soft_band`) pass on the plan and fail without the stage. Rewrite the plan text to match.

**R2. `test_enemy_dual_mode.gd`:992 is a parse error, so the whole file fails to load.**

- The line is `var dir := (harness.player.global_position - start).normalized()`. `harness` is untyped, so `:=` cannot
  infer a type, and GUT reports "Cannot infer the type of "dir" variable".
- GUT drops the file with a warning and loses every existing dual-mode row with it. `test_suite_integrity.gd` fails the
  gate.
- Fix: `var dir: Vector2 = …`. Every result above was measured with that one fix applied.

**R3. The dither half of `test_prev_dir_keeps_the_side_it_chose` fails on a correct build** (`test_context_avoidance.gd`:240-254).

- Measured: there is exactly one side change in the whole run, at step 123 at (−10, −200). The heading goes from
  −11.25° to +10.81°. That is the turn down toward the target over the well's top, not a dither.
- It happens 10 px before the `x >= 0` cutoff (:245), so `flips == 1`.
- Fix: drop the cutoff and assert `flips <= 1` over the whole run (measured: 1). An output-blend zig-zag still fails
  that. The two `prev_dir` asserts at :233-234 already pin the hysteresis itself. Do not change the design to fit the
  test.

**R4. The "captured 2 s later" half of the BURST row neither passes nor tests t4** (`test_enemy_dual_mode.gd`:998-1000;
plan :177-178).

- **Measured.** The drone ends 428.8 px from the well on the plan build and 428.7 px with no stage, in both modes.
  The stage plays no part in the result.
- **The cause is the drone's own next attack.** The phases run BURST → OVERSHOOT → WINDUP → BURST
  (`second_passes = 1`), and the second 480 px/s boost outruns the pull.
  - Other geometries are erratic: Open Space 144–429 px, Assault 4–250 px.
  - Even with `second_passes = 0` the lead re-attacks through CLOSE_IN → WINDUP → BURST (101 / 139 / 144 / 17 px against
    `damage_radius` 150).

  So no geometry makes the row robust without a brain change, and the plan rules that out.
- **What stays.** The capture physics is already pinned by t2 (`test_a_swarm_config_cannot_leave_the_core_but_a_fighter_config_can`,
  :714). The `straight` half (:993-996) is the part that discriminates boost-bypass.
- **Fix.** Keep `straight`. Then either replace the 2 s capture with an assertion over the burst itself (for example,
  the drone passes within `core_radius` of the centre during the boost: "carried in, not round") or drop it. Change the
  plan text to match.

## Minor (fix while implementing; no re-review needed)

- **m1. The on-slot bracket rule only fires on slot 0.** `Vector2.angle()` returns a 32-bit float here, so
  `fposmod(angle, TAU) / slot` is never an exact integer except at +x:

  | Heading | Computed slot index |
  |---|---|
  | −x | 8.00000022 |
  | −Vector2(200, 0) | 7.99999978 |
  | +y | 4.00000011 |
  | −y | 11.9999999 |

  So `at != floor(at)` holds and both neighbours are checked, which is the float-noise case the rule exists to remove.
  No current row fails, because every bit-exact row runs along +x. Use a tolerance: bracket `roundi(at) % 16` alone when
  `absf(at − roundf(at)) < 1e-4`. Containment still holds, because the one-slot widening dwarfs ε. Correct the
  "e.g. an axis-aligned request" wording at :45-48.
- **Conventions, checked.**
  - Nothing new in `global/` references `ArenaCamera`.
  - `_avoid_prev` is a field write, and the brain sweep accepts `mover.arrive()` in `fixture_brain.gd`.
  - `tests/unit/test_context_avoidance.gd.uid` (`uid://mfphv3lwhsv7`) is unique in the tree.
  - `fixture_wreck.gd` still has no `.uid` in the repo; `--import` mints one, as M1 says.

## Verdict

CHANGES_REQUESTED. Fix R1–R4 in `3-plan.md` and the written rows. All are test-only, and each fix above is already
measured against the plan's implementation. The design stays approved as written. A round-3 check needs to look only
at those four rows and the m1 wording.

VERDICT: APPROVED

# Review, round 3: R1–R4 and m1, re-measured on the author's build

**Result.** R1–R4 and m1 are resolved, both in `3-plan.md` and in the written rows. Every one of those rows passes on
the plan build and fails on the mutant it exists to catch. The Fighter re-geometry adds one new weakness (F1): its
Open Space half passes without ever going round the well. It is test-only, and build step 5 already reserves this
tuning (`3-plan.md`:115-116), so it does not block. Fix it before committing; it needs no re-review. Three wording
nits follow. The design was out of scope this round and is unchanged.

**How I checked.**
- **Build.** `/tmp/rv5` is a copy of the author's `/tmp/t4proj`. Its `Steering.context_avoid()` and
  `EnemyMover._avoid()` / `_avoid_prev` match `3-plan.md`:22-91, including the m1 rule
  (`on_slot := absf(at - roundf(at)) < 1e-4`). Diffed against my round-2 build `/tmp/rv4`, the only change in
  behaviour is that rule.
- **Tests.** All five changed or new test files in the tree are byte-identical to the build's copies.
- **Results.** The three t4 files pass 105/105. The full suite (`-gdir=res://tests -ginclude_subdirs`) passes
  1954/1954 in 199.8 s across 135 scripts, with no leak lines at exit.
- **Leak check.** Running `test_enemy_dual_mode.gd` on its own logs ObjectDB / "73 resources still in use" at exit.
  HEAD's version of that file logs the same lines, so this is not new.

| Mutant (scratch only) | Failing tests (of 105) | Where |
|---|---|---|
| none (plan build) | 0 | |
| no stage (`_avoid()` returns `desired`) | 8 | 4 mover rows; dual-mode claimed wreck, corridor, Swarm skim, Fighter, each in both modes |
| avoid while boosting (`if hazards_live:` at the hook) | 3 | mover boost-straight and boost-clears-memory; the burst row's straight, crosses and held, in both modes |
| no on-slot tolerance (`on_slot := at == floorf(at)`) | 1 | `test_context_avoidance.gd`:87 only (the +y case) |
| no hysteresis (`aim = want`) | 3 | `prev_dir` row (29 flips, all at \|y\| < 3), soft-centre row, Open Space Swarm skim |
| output blend (selection unblended; heading blended 50/50 with `prev_dir`) | 3 | `prev_dir` row (23 flips at \|y\| < 2, plus the reversed-`prev_dir` case), soft-centre row, Swarm skim |

## Round 2 findings

- **R1, resolved.** `test_enemy_dual_mode.gd`:893-911 is the round-2 scenario exactly: a radius-300, pull-free
  hazard at `rect.end.x − 100`, a start at `(rect.end.x − 20, centre.y − 500)`, a request of `(0, 200)` and 8 s.
  - Measured `furthest`: Open Space 331.6 px (> `soft_band` 120), Assault 13.6 px (between 0 and 120).
  - With no stage it is −20.0 px in both modes, so both modes' assertions fail.
  - The plan text (:173-180) matches, including the reason the round-1 version could not work.
- **R2, resolved.** :992 is now `var dir: Vector2 = …`. The file loads (30 functions, all green), and
  `test_suite_integrity.gd` is green in the full run.
- **R3, resolved.** `test_context_avoidance.gd`:247-263 now asserts `flips <= 1` over the whole run, a side change only
  at `|y| >= 120`, and that the target is reached.
  - Measured: one flip, at step 123 at (−9.95, −200.4), and the target is reached at step 199.
  - Both hysteresis mutants fail it (table). So the plan's claim (:147-150) that "an output-blend zig-zag still
    fails this" holds.
- **R4, resolved.** The `straight` check is kept, and two assertions are added: the burst reaches inside
  `core_radius`, and the drone is held inside `damage_radius` until its next `boost()`.
  - **Measured, both modes:** closest during the burst 67.5 px (< 90). Then 1.20 s until the next boost, furthest
    136.4 px (< 150). Control with no well: furthest 164.2 px (> 150).
  - **Mutants:** avoid-while-boosting fails all three (closest 311.0, furthest 351.9). With no stage the row still
    passes (furthest 135.5). That is correct, because the hold is t2 physics.
  - **Robustness:** I swept the 310 px start offset. 290–320 pass both halves. 270 fails the hold (163.8) and 330
    fails the control (144.2). The margin is narrow but deterministic, and 310 sits in the middle of the window.
  - The deviation from "still inside 2 s later" is recorded at :195-199, with the reason measured in round 2.
- **m1, resolved.** The bracket uses the 1e-4 tolerance (`3-plan.md`:45-50).
  - The new case (`test_context_avoidance.gd`:81-87) is bit-identical on the plan build.
  - It is the only failure on the no-tolerance mutant, whose x comes out −1.3e-5 instead of 0.
  - The "e.g. an axis-aligned request" wording is corrected.

## New (fix while implementing, in step 5; no re-review needed)

**F1. The Fighter row's Open Space half passes through the brain's breach fallback and never goes round the well**
(`test_enemy_dual_mode.gd`:950-977; plan :184-189).

- **Measured with the well at (420, −168).**
  - The avoiding Open Space fighter swings south from tick 40. At tick 71, at (551.8, −84.0), it is 453 px from the
    player.
  - That is inside `clear − BREACH_MARGIN` = 479 − 24, so `FighterBrain._tick_approach` calls
    `_begin_breach_pass()` and the fighter enters RUN_IN there.
  - It never reaches the westward leg: min x is 549.5. The row stops at RUN_IN, so `closest` (55.9 px) covers only
    those 71 ticks.
  - The Assault half does go round: it reaches its own pass start at tick 315 with min x −76.1. That leaves 45 ticks
    of its 360-tick budget (`engage_seconds` 6.0), which is the margin round 2 suggested removing.
- **Why it matters.** The Open Space half is the hub's mode, where t17 places the well. A regression in which the
  stage and the Dubins tracker never let an Open Space fighter reach its pass start would still pass there.
- **The plan's measured description is also off.** With no well, the two modes share only the first ~110 ticks:
  - Open Space reaches RUN_IN at tick 232, with S = (160, 200);
  - Assault reaches it at tick 205, with S = (295, 200).

  So "the same curve in both modes … RUN_IN at tick 205" and "goes round … RUN_IN in both modes" do not hold for
  Open Space.
- **A breach in Open Space happens wherever the well sits on the leg's east half.** I swept the well at
  x = 340–460, y = −130 to −190 (9 positions). Every Open Space avoiding run breached at ticks 67–82.
- **Measured replacement.** Move the well 100 px west along the same leg, to (320, −168), keeping radius 100,
  core 30, pull 200. Set `fighter.config.engage_seconds = 1000.0` on both runs, a private copy as at :737.

  | Mode | Control `closest` | Control RUN_IN | Avoiding `closest` | Avoiding RUN_IN (via its pass start) | Avoiding min x |
  |---|---|---|---|---|---|
  | Open Space | −95.7 px | tick 233 | 56.4 px | tick 316 | −155.6 |
  | Assault | −98.0 px | tick 205 | 56.2 px | tick 337 | −110.5 |

  Add one assertion that the run went past the well before RUN_IN: min x < `well.x − radius`. That fails the current
  geometry's Open Space half (549.5). Then correct :186-188 to the measured figures. The no-stage build is the control
  path, so it still fails "never inside" in both modes.

## Nits (wording only)

- `3-plan.md`:49-50: "`desired` is within 2e-6 rad of it". The tolerance admits 1e-4 of a slot, which is
  3.9e-5 rad. The containment argument holds for any ε well below one slot, so only the number is wrong.
- `3-plan.md`:125-126 and the comment at `test_context_avoidance.gd`:82 say the 150° hazard puts danger on "the
  112.5° slot only" / "slot 5 only". It puts danger on slots 5–8; slots 4 and 9 sit just outside its 51.2° half-width.
  What the case needs, and gets, is danger on slot 5 and none on slot 4.
- The burst row says "crosses the core" (plan :191; message at `test_enemy_dual_mode.gd`:1019). The burst ends
  67.5 px *short* of the centre, inside the core. "Reaches the core" is accurate. The no-well burst also ends inside
  90 px (at 86.0), so this assertion discriminates the same mutant as `straight` and nothing more. That is fine;
  only the word is wrong.

## Verdict

APPROVED. R1–R4 and m1 are fixed and measured. Implement from `3-plan.md` as written. Fix F1 and the three nits in
step 5, before the commit; none needs another review.
