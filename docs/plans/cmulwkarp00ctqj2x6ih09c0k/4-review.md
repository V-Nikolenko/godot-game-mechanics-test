# Review — round 1

VERDICT: CHANGES_REQUESTED

Reviewed `3-plan.md` and `1-context.md` against the code and the working-tree prototype: the level edit, the
`test_level1_fighter_spawns.gd` / `test_level1_fighter_fire_density.gd` / `test_engagement_deadline.gd` diffs, and the
untracked `test_level1_fighter_exit.gd`. Most of the plan is right and the prototype follows it closely. Two problems
block it. One is in the deadline formula's exit term: it is not a bound on the code it claims to bound. The other is a
boundary row that cannot fail.

## Blocking

### B1. `worst_exit` does not bound a fighter's DISENGAGE. The real worst case is ≈ 4.9 s, not 2.84 s.

Checked: `assault/scenes/enemies/fighter/fighter_brain.gd:1407-1441` (`_enter_disengage`, `_tick_disengage`),
`global/enemy_ai/steering.gd:170-179` (`turn_toward`), `global/enemy_ai/enemy_mover.gd:176-198` (`step`), and
`tests/helpers/level1_drone_concurrency.gd:220-223` (`worst_exit_after_speed`).

- **What the formula assumes.** `worst_exit_after_speed()` treats the exit as a straight line: brake from `max_speed`
  away from the edge, accelerate back, then cover `exit_distance`. That gives (300+520)/700 + (804+64.3)/520 = **2.84 s**.
- **What the fighter actually does.** It never reverses along a line.
  - `_tick_disengage` takes its heading from the **velocity** (`_heading()`). It rotates that heading toward the exit
    point at `rate = min(turn_rate, acceleration / exit_speed)` = min(1.8, 700/520) = **1.346 rad/s**.
  - It then requests `dir * exit_speed`. The result is a curved turn-around of about π/1.346 ≈ 2.3 s on a radius of
    about 386 px, followed by a long diagonal run.
- **Measured with the real `fighter.tscn`.** I ran it headless, hand-ticked exactly like `test_fighter.gd::_tick` with
  the `enemy_ai_harness` Assault world, from `enter_phase(DISENGAGE)` until it was queued for deletion:

  | Start (relative to the camera centre), 300 px/s | Freed after |
  |---|---|
  | (0, 0), heading right (away from its tie-broken left exit) | **4.87 s** |
  | (0, +200), heading up (away from its bottom exit) | **4.57 s** |
  | (+100, 0), heading right (towards its right exit) | 1.45 s |
  | Formula | 2.84 s |

  A kinematic sweep of the same code gives the same result. Over positions × headings inside the visible 1280×720
  box, 11.5 % of start states exceed 2.84 s, and the maximum is 4.85 s. So this is not a corner case.
- **Consequences.**
  - The per-entry margin the plan reports, **3.06 s, is really ≈ 1.0 s**: (72.8−76.0) + 6.0 + 0.8 + 4.87 + 0.5 ≈ 8.97.
  - The invariant would also pass a level that stalls. A fighter entry 1.2 s before the last trigger computes 8.94 by
    the formula, but needs ≈ 10.97 s in reality.
  - The acceptance criterion "the computed per-entry margin … reported" would then report a wrong number. That is
    exactly what this gate family exists to prevent.
- **Required.**
  1. The fighter rows must use an exit term that bounds the curved exit.
  2. `test_engagement_deadline.gd` (or `test_fighter.gd`) must gain a real-fighter probe proving that bound: a fighter at
     the world-rect centre, at `max_speed`, heading directly away from its chosen exit edge, plus the off-centre
     (0, +200) case. Each must be freed within the term the rows use. This also makes the term falsifiable if the
     DISENGAGE steering changes.
  3. A candidate closed form: with ω = min(turn_rate, acceleration/exit_speed), use
     π/ω + (exit_distance + 2·exit_speed/ω)/exit_speed = 2.33 + 3.03 = **5.37 s**, which is ≥ the 4.87 s measured. The
     implementer may choose a different term, but the probe must gate it. With 5.37:
     - worst entry: −3.2 + 6.0 + 0.8 + 5.37 + 0.5 = **9.47 < 10** (margin 0.53 s), so no lever is needed;
     - literal boundary: 0.8 + … = 13.47;
     - the N5 row is unaffected.
- **Scope.**
  - The task text says "Razor-shaped". Record this deviation, and the reason for it, in DECISIONS.
  - **Do not change the shared `DroneConcurrency.ai_shooter_kinds()` lifetime in this task.** Re-running the t16 count
    gates with a corrected fighter life gives:

    | Fighter life | deep_space all-alive / capable (limits 20 / 15) |
    |---|---|
    | Measured, 11.67 s | 18 / 14 |
    | Bound, 12.17 s | **21** / 15 — breaks t16's all-alive gate |

    cloud_descent stays at 9 / 8 for every lifetime I tried, so its new gates are unaffected. Record the helper's
    underestimate in DECISIONS as an owner item. It is t16's gate, not something to fix silently here.
  - The plan's "Why 66 s" (life 9.64 s → gone by 75.6 s) also uses the low figure. The conclusion still holds with
    ≈ 12.2 s: the latest pre-66 s fighters are the 59 s wedge (slot stagger ≤ 0.2 s), gone by ≈ 71.4 s, before 76 s.
    The text should be corrected.

### B2. The config-derived (N5) boundary row is a tautology and cannot fail.

Checked: `tests/integration/test_engagement_deadline.gd` (working tree),
`test_a_fighter_just_past_the_config_derived_limit_misses_the_timeout`, against
`docs/plans/cmufs7ekv000lnm2x7nbswijy/4-review.md:313-319`.

- **What the row does.**
  - It computes `rel = timeout − tail + 0.25`, then `computed = rel + tail`, then asserts `computed > timeout`. That is
    the identity `timeout + 0.25 > timeout`.
  - Its "control", `rel − 0.5 + tail < timeout`, is the identity `timeout − 0.25 < timeout`.
  - Neither line touches the code under test. Both stay green whatever the level, `_entry_rows()` or the configs do.
- **What N5 asked for, and why there is nothing to call.** N5 asked to place the synthetic entry and "assert that the
  **function** rejects it". There is no such function: the main test inlines `float(row["rel"]) + tail`.
- **Required.**
  1. Factor the per-entry check into one helper that the main test also uses. It should build the rows (trigger, delay,
     formation slots) and return each row's computed value, or the rows over the timeout.
  2. Drive the N5 row through it: append a synthetic fighter `SpawnEntryResource` to a **freshly built** cloud_descent,
     in a wave at the last trigger, at delay `timeout − tail + 0.25`, with a sanity assertion that this delay is ≥ 0.
     Assert that the helper reports that entry, and that its computed value is > the timeout.
  3. Run the shipped section through the same helper as the control, and assert that nothing in it is over.
- **Recommended (not required): route the literal delay-0.8 row the same way.** Today it is arithmetic only — the
  Razor-row precedent at `:146-163` is too, so this is acceptable. A row that goes through `_entry_rows()` would also
  catch a broken slot-delay or relative-time computation.

## Non-blocking

- **N1 — use the effective trigger time.**
  - Checked: `assault/scenes/systems/wave_manager/wave_manager.gd:56-64`. `WaveManager` triggers strictly in list
    order. t16's DECISIONS note found deep_space waves triggering 1.5 s late because of this.
  - A wave's real trigger is therefore the running maximum of `trigger_time` over the list. `_entry_rows()` uses the
    raw `trigger_time`, so an out-of-order wave inserted into cloud_descent later would be understated.
  - `_last_wave()` (the maximum) is correct for the clock start. cloud_descent is monotonic today, so nothing changes
    now.
  - Fix: use the running max, or assert that ENEMIES_CLEARED sections have non-decreasing triggers.
- **N2 — wrong ship count.**
  - Checked: `level_1_director.gd:809-1004`. §4's "cloud_descent's 27 lines → 29 ships" should be **31**: 25 loose
    lines, plus the wedge's 3, plus the V's 3. The plan's own prototype table says 31.
  - The prototype only asserts `checked > 0`, so nothing is wrong in code. Fix the text, or assert 31.
- **N3 — the Gatling row's filter.**
  - Checked: `gatling_interceptor_config.tres`. 0 + 7.0 + 2.08 + 2.918 + 0.5 = 12.50 ✓.
  - The plan's filter, "evaluated on every section whose timeout is below the computed value", is circular: the
    assertion inside it is vacuous, and only the cloud_descent sanity check carries the row.
  - The prototype instead uses an unexplained `timeout >= 60.0` cut-off.
  - Simpler: assert on cloud_descent by name, and print station_assault.
  - Also note in the comment that the Gatling's own exit is probably longer than its formula too (≈ 5.4 s in a
    kinematic model of the same steering shape). That is harmless for a row that must fail: it only lowers the computed
    value.
- **N4 — the real-run margin is the drones'.** The prototype's container margin (0.93 s) is set by the Ph2 Swarm
  drones, and the plan already says so. The Swarm deadline formula is also a straight-line exit. Worth one line in
  DECISIONS for whoever owns Ph2's gate. Not this task's to fix.
- **N5 — a `.uid` file my run may have created.** My headless Godot probe run (read-only scripts in `/tmp`) may have
  caused the engine to mint `tests/integration/test_level1_fighter_exit.gd.uid` (`uid://2k586ej2f88e`). It is
  engine-generated, and §Build-sequence step 3 expects it anyway. I did not touch any code or test file.

## Verified correct (no action)

- **Level edit.** Checked `level_1_director.gd` (diff).
  - All 27 fighter lines lost `.move()`, `.free_after()` and `shoot_*()`. Triggers, offsets, delays and formations are
    unchanged.
  - The tags `w2f w5f w8f w12f w13f w15f w20f w22f` match the `raw_waves` indices (0:0.0 … 23:76.0). The drone tags
    `w1 w7 w14 w17 w19 w21 w23` confirm the convention.
  - The unused `L`/`R` locals are removed. The 76.0 s wave is drones only, with max delay 0.8.
- **Fighter deferral, ≤ 0.8 s.** Checked `fighter_brain.gd:279-280, 1288-1303, 1395-1402` and `burst_clock.gd`.
  - Budget expiry mid-burst sets `_disengage_pending`, and `_try_open_burst` refuses a new burst while it is pending.
  - The real worst case is 0.3 + (5−1)×0.1 = 0.7 s plus tick rounding, so 0.8 is conservative.
  - The budget starts in `_start()` on the first tick after spawn.
- **Clock start.** Checked `wave_manager.gd:56-64` and `level_director.gd:159-195`. `waves_complete` fires on the
  last wave's trigger tick, and the timeout is measured from it. The 86.0 s figure is correct.
- **No bullet term.** Checked `bullet_pool.gd:18-21, 47, 88-92`. In-flight rounds are reparented to the container and
  freed when their ship exits.
- **Arithmetic from the configs.** Checked `fighter_config.tres`. 6.0 + 0.8 + 2.841 + 0.5 = 10.141; worst entry 6.94;
  literal boundary 10.94 ≥ 10.9. (Only the exit term is wrong; see B1.)
- **The pin.** Checked `test_level1_fighter_spawns.gd`.
  - 64 = 18 + 19 + 27, and 43 = 18 + 25 loose. `_RAIL_SECTIONS` is empty.
  - The never-vacuous assertion is in place (`:436-440`). The frozen constants are untouched (8 / 15.0).
  - The count gates over cloud_descent reproduce at 9 ≤ 16 and 8 ≤ 12.
- **Measured shots/s case.** It reuses `_assert_measured_gate`, including the DISENGAGE / no-`EnemyPathMover` checks.
- **Exit test.** Checked `test_level1_fighter_exit.gd`.
  - Every handler's signal arity matches.
  - The `_recording` guard is in place.
  - Every spawn timer fires before return: the main run stops only once every expected ship has spawned, and the rail
    run goes to 7.5 s, past the 7.2 s ram.
  - It polls the container the same way `LevelDirector` does, and uses game time.
  - The rail boundary has the same shape as the `test_level1_drone_exit.gd:179-207` precedent.
- **No reinvention.** The prototype reuses `worst_exit_after_speed`, `ai_shooter_kinds`, `shooter_squad_intervals`
  and the harness.

# Review — round 2

VERDICT: CHANGES_REQUESTED

Re-checked Revision 2 of `3-plan.md` and the working tree. Two files: `tests/integration/test_engagement_deadline.gd`,
from the `# ── Ph3 t17` marker to the end, and `tests/integration/test_level1_fighter_exit.gd`. B2, N1, N2 and N3 are
resolved. B1 is fixed in substance: the bound used, 5.37 s, does hold on the real scene. But the new probe gating it
does not test the slowest start, so it cannot catch the regression it exists for. Fixing it is a few lines, and a
round 3 only needs to check that.

## Blocking

### B3. The exit probe only tests starts at `max_speed`, but the slowest DISENGAGE starts from just above the standing-start speed.

Checked: `fighter_brain.gd:121` (`STANDING_START_FRACTION` 0.3) and `:1438-1441`, against
`test_the_fighter_exit_term_bounds_a_real_fighters_disengage` and `_disengage_seconds`.

**How the start speed decides the exit.** In `_tick_disengage`, a fighter slower than
`0.3 × max_speed` = **90 px/s** heads straight for its exit. At 90 px/s or faster it instead turns its current velocity
round. Starting slower but still at least 90 px/s makes that turn-around longer, because more of the acceleration goes
into speeding up and less into turning.

**Measured with the real `fighter.tscn`.** I used the same Assault harness and hand-tick as the probe, starting at the
rect centre, heading away from its tie-broken left exit:

| Start speed | Freed after |
|---|---|
| 300 px/s (the probe's only speed) | 4.87 s |
| 120 px/s | 5.17 s |
| 91 px/s | **5.20 s** |
| 89 px/s (standing start) | 2.07 s |
| 91 px/s, at (0, +200) heading up | 4.92 s (the probe's 300 px/s figure for this start: 4.57 s) |

A kinematic sweep of the same steering puts the maximum at the 90 px/s threshold, centre, heading away: 5.18 s. Speeds
from 90 to 200 px/s over a 17 × 17 × 36 grid found nothing slower.

**Why this blocks.**
- The bound, 5.37 s, still holds. The real worst case is 5.20 s, so the slack is 0.17 s, not the 0.50 s the probe
  reports. The shipped level is still safe: worst entry −3.2 + 6.0 + 0.8 + 5.20 + 0.5 = 9.30 < 10.
- But the gate never runs its own worst case. The plan calls the two named starts "the two worst", and they are not.
  A change that slows the low-speed exit by about 0.2 s would push the real exit past the bound, and the probe would
  stay green. Examples: a different `STANDING_START_FRACTION`, a lower `acceleration`, or different heading logic.
- Fighters do reach DISENGAGE at that speed. Squad members slow along their track for mates, brake onto their S, or
  extend.

**Required.**
1. Add start speed as a probe axis. At minimum, run the two named starts and the grid's centre column at both
   `max_speed` and `FighterBrain.STANDING_START_FRACTION × max_speed + 1`, both read live.
2. Print the slowest start together with its speed.

That costs one to two dozen extra hand-ticked runs. The straight-line boundary assertion stays as it is.

## Non-blocking

- **The N5 row is now a delay-0 row.** The tail (12.67 s) exceeds the 10 s timeout, so it is clamped to 0, and lever 1
  would leave it clamped. It is still a valid boundary, because it goes through `_deadline_rows` with the shipped
  section as the control. But it no longer tests the edge, and it nearly duplicates the literal row.
  - Stronger option: insert a synthetic fighter wave at trigger `last_trigger + (timeout − tail) + 0.25` (≈ 73.58 s
    today), keeping list order. Assert it is flagged, and that the same entry 0.5 s earlier is not. That tests both
    sides of the threshold through the effective-trigger path.
  - Recommended. Not required.
- **The exit test's run cap is on the wrong clock.** It runs until the physics clock reaches `last_trigger + timeout`,
  while `waves_complete` is now known to fire at a physics time different from `last_trigger` (9.88 s in one run).
  - If the physics clock ever trails, the window is shorter than the timeout. The direction is safe: it can only fail
    a passing build, never pass a failing one.
  - Fix: stop at `_complete_at + timeout` once `_complete_at ≥ 0`.
- **The bound's derivation is informal.** The header calls the run "never longer while exit_distance ≥ radius/2".
  That argument is hand-waved; the probe is what makes the bound trustworthy, which is one more reason for B3.

## Verified (round 2)

- **`_deadline_rows`** is now the single check.
  - Effective trigger = running max in list order. `last_trigger` = the final running max, so N1 is resolved.
  - `over` = `computed ≥ timeout`.
  - The main test, the literal row, the N5 row and the Gatling row all use it. The literal and N5 rows use
    the shipped section as the control and add their entry to a freshly built `_cloud_descent()`, so B2 is resolved.
- **Literal row.** rel 0.8, computed 0.8 + 12.67 = 13.47 ≥ 10.9 and > 10 ✓.
- **Sanity count.** 31 cloud_descent fighter rows ✓ (N2).
- **Gatling row.** It goes through the same check and is asserted by name on cloud_descent; station_assault is printed
  (N3). It keeps the Razor-shaped term, which can only make this must-fail row fail harder.
- **`_fighter_exit_bound`.** ω = min(1.8, 700/520) = 1.346, giving π/ω + (804 + 772.6)/520 = 2.334 + 3.032 = 5.37 ✓.
  Tail 12.67 and worst entry 9.47 ✓.
- **The probe can fail both ways.** A slower exit, or one that hits the cap, fails `assert_lte`. A degenerate instant
  free fails `assert_gt(slowest, straight)`.
  - Its 5 × 5 × 8 grid at 300 px/s does contain the 300 px/s maximum (4.85 s kinematic, 4.87 s real, both at the
    centre heading right). My kinematic sweep over the whole 1608 × 1608 rect at 300 px/s found nothing slower.
  - Its only gap is the speed axis (B3).
  - Each fighter is `free()`d after its run, and the harness is autofreed.
- **Exit test.**
  - The "why 66 s" header now uses ≈ 12.2 s. The 59.0 s wedge enters by 59.1 s and is gone by ≈ 71.3 s ✓.
  - `waves_complete` is checked on `WaveManager._time_elapsed`, which is the clock that actually triggers waves.
  - Every later interval is physics-to-physics ✓.
- **Scope.** The shared `ai_shooter_kinds()` is untouched and is recorded as an owner item, as advised.

As in round 1, I edited no code or test files. My probes live in `/tmp/simrev`.

# Review — round 3

VERDICT: APPROVED

Scoped to B3 and the two round-2 notes that were taken up. Re-checked against the working tree.

- **B3 is resolved.** Checked `test_engagement_deadline.gd::test_the_fighter_exit_term_bounds_a_real_fighters_disengage`.
  - **Two speeds, both read from the code.** Every start (the 5 × 5 grid × 8 headings, plus the 2 named starts) runs at
    `FIGHTER_CONFIG.max_speed` and at `FighterBrain.STANDING_START_FRACTION × max_speed + 1.0`. `_tick_disengage`
    compares against `config.max_speed × STANDING_START_FRACTION` (`fighter_brain.gd:1440`), and the fighter's private
    config copy is value-identical to the shipped `.tres`. So 91 px/s is the lowest speed that takes the turning branch.
  - **The reported slowest matches my measurement.** 5.20 s at (0, 0), heading (1, 0), 91 px/s is exactly the real-scene
    worst case I found in round 2. My kinematic sweep over speeds from 90 to 200 px/s found nothing slower.
  - **It can fail in both directions:**
    - a slower exit, or one that hits the cap, fails `assert_lte(t, bound)`;
    - an instant free fails `assert_gt(slowest, straight)`.
  - **The slack is now visible.** The 0.17 s between 5.20 and 5.37 is printed in the gate log rather than hidden.
- **The N5 row now tests both sides of the edge.** Checked `test_a_fighter_just_past_the_config_derived_limit_misses_the_timeout`
  and `_with_fighter_wave_before_last`.
  - **Arithmetic.** limit = 76.0 + 10.0 − 12.67 = 73.33. The inserted wave at 73.58 computes 10.25 and is flagged. The
    same wave at 73.08 computes 9.75 and is not. The shipped worst case (9.47) stays below both, so "only it" holds.
  - **Path.** Both go through `_deadline_rows`, including the effective-trigger path. `assert_between` keeps list order
    monotonic.
  - **Survives lever 1.** With `engage_seconds` 4.5 the limit becomes 74.83, still between the 72 s and 76 s waves.
  - **Fresh resources.** Each call uses a freshly built section.
- **The exit test's run cap is fixed.** Checked `test_level1_fighter_exit.gd:203-209`.
  - The window is now `_t − _complete_at ≥ timeout` on the physics clock, and the early-stop check is suppressed until
    `waves_complete` has fired.
  - A run that hits the window cap fails `assert_lt(cleared_after, timeout)` and the container-empty assertion.
  - The `+ 1.0` hard cap only guards a run where `waves_complete` never fires.
  - Every spawn timer (the last fires 0.8 s after `waves_complete`) still fires before return, so there is no
    leaked timer.

What remains for the as-built record, already planned:
- DECISIONS gets the curved-exit deviation from the task's "Razor-shaped" wording.
- DECISIONS also gets the owner item for `DroneConcurrency.ai_shooter_kinds()`'s straight-line fighter lifetime. With
  the bound, deep_space's all-alive peak reads 21 against 20.
- Run `bash /agent/verify.sh` and `scripts/check-test-leaks.sh` on the full suite.

I edited no code or test files.
