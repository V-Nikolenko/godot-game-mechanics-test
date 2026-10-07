# Level 1 cloud_descent: fighters off rails, deadline proven per entry and by a real run (t17)

Epic plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.9.3 (Revision 2, approved), with binding review note
**N5** (boundary rows derived from config). Precedent: t16, `docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md`
(Revision 2), whose as-built DECISIONS note says t17 reuses its helpers and its measured gate (owner option A).
This plan adds nothing the epic did not already approve; it pins down the details and reports prototype measurements.

**Revision 2 (after review round 1, `4-review.md`):** B1 — the fighter deadline uses a curved-exit bound (5.37 s) gated
on the real scene, not the task's Razor-shaped 2.84 s; recorded in DECISIONS. B2 — one `_deadline_rows()` check that
the main test and every boundary row go through. N1 effective triggers; N2 31 ships; N3 Gatling row asserted by name.
Also: the exit test judges "waves_complete fires on the last trigger" on `WaveManager`'s own clock (`_time_elapsed`,
idle delta) — a run measured 9.88 s of physics time at that moment because the first idle frame's delta covers set-up
time no physics step does; every interval after it is measured on the physics clock at both ends.

## Problem
In level 1's last section, cloud_descent, all 27 fighter lines still fly fixed rails: straight sweeps, arcs and the
59 s / 72 s formations dive down and shoot on a timer, then vanish at a set time. After this task they arrive at the
same moments and places, then fight as squads inside the corridor (pincer plus frontal pass) and leave by themselves
when their engagement budget runs out. cloud_descent is the one section that ends when the screen is **clear**
(ENEMIES_CLEARED), with a 10 s safety net that starts when its last wave (the 76.0 s drone swarm) triggers. If an AI
fighter outlives that net, the level stalls and then force-frees the ship as an "escape". So the section must still
clear in time, and the level must not become busier or noisier than it was.

## Design

### 1. Level edit — `_build_section_3()` in `level_1_director.gd` (prototyped in the working tree)
- Every `b.fighter()` line loses `.move()`, `.free_after()` and `shoot_*()`, and keeps `.at()`, `.formation()` and
  `.delay()` — the same edit t16 made to the first two sections.
- Loose fighter lines that share a wave with another loose fighter line get `.squad(&"w<n>f")`, where `n` is the wave's
  index in `raw_waves`, matching the section's existing drone tags (`w1 w7 w14 …`): `w2f` (5.0 s ×3), `w5f` (14.0 ×3),
  `w8f` (26.0 ×2), `w12f` (38.0 ×2), `w13f` (42.0 ×6: 3 attackers + 3 REARs, which in Assault are reserves), `w15f`
  (50.0 ×3), `w20f` (66.0 ×2), `w22f` (72.0 ×4; the 72.0 s V3 is its own formation squad). The 59.0 s wedge is a
  formation squad. There are no lone loose fighters in this section.
- The now-unused `L` / `R` arc-direction locals are removed (an unused local is a warning, which
  `test_project_load_integrity.gd` rejects). Wave comments describing a rail ("sweep left-to-right", "arc") are
  reworded to say where the ships arrive.
- Triggers, offsets, delays, formations, drones, rams, snipers, gunships and allies are untouched.

### 2. The pin — `tests/integration/test_level1_fighter_spawns.gd`
- The 27 cloud_descent rows become AI rows: `aim_mode ""`, `free_after 0.0`, `movement false`; section, trigger, offset,
  delay, formation and count unchanged (regenerated from `_actual_fighter_spawns()`, never hand-typed).
- **Retire the live==constant check for cloud_descent:** `_RAIL_SECTIONS` becomes empty, with a comment naming t17.
  `test_legacy_peak_fighters_and_shots_per_s_match_frozen_constants` stays (it re-arms automatically if a section is
  ever put back on rails) and gains one assertion so it is never vacuous: every key of `_LEGACY_PEAK_FIGHTERS` /
  `_LEGACY_PEAK_SHOTS_PER_S` is either in `_RAIL_SECTIONS` or in `MIGRATED_SECTIONS` — every frozen constant is
  either live-checked or divided by a gate. **The constants themselves are not edited** (cloud_descent stays 8 /
  15.0).
- `MIGRATED_SECTIONS` gains `cloud_descent`. Consequences:
  - `test_migrated_sections_have_no_rail_left`: sanity count 37 → **64**;
  - `test_loose_pairs_are_tagged_with_their_wave_index`: sanity count 18 → **43** (25 new loose fighter lines, all
    already correctly tagged in the prototype);
  - `test_migrated_sections_all_alive_and_attack_capable_peaks_within_their_ratios` now gates cloud_descent against
    **its frozen constant** (8): all-alive ≤ 2.0 × 8, attack-capable ≤ 1.5 × 8.
- Header comment: cloud_descent's rows are AI rows since t17; nothing in level 1 is on rails any more.

### 3. Measured shots/s — `tests/integration/test_level1_fighter_fire_density.gd`
New case `test_cloud_descent_measured_shots_per_s_within_1_25x` → the existing `_assert_measured_gate(&"cloud_descent")`
(fighter-only population, every wave kept in list order, seeded brains, 4× clock with a 1/60 s step, gate ≤ 1.25 ×
frozen 15.0 = 18.75, plus every-ship-spawned / at-least-one-shot / all-left-in-DISENGAGE / no-`EnemyPathMover`).
Header comment updated to name all three sections.

### 4. Deadline rows — `tests/integration/test_engagement_deadline.gd` (epic X8, §2.9.3) — Revision 2
New per-entry fighter rows, in the file's relative form, for **every fighter entry (formation slots expanded) of every
ENEMIES_CLEARED section**:

`(entry_time − last_wave_trigger) + engage_seconds + deferral + worst_exit + MARGIN < enemies_cleared_timeout`

- **One check function, `_deadline_rows(section, scene_path, tail)`** (review round 1 B2): builds one row per ship
  (trigger, delay, `rel`, `computed = rel + tail`, `over = computed ≥ timeout`). The main test and **every boundary row**
  go through it, so a boundary row fails if the row building, slot expansion or relative-time computation breaks.
- `entry_time` = the wave's **effective** trigger + `spawn_delay` + slot delay, where effective = the running maximum of
  `trigger_time` in list order (`WaveManager` triggers strictly in list order; review N1). `last_wave_trigger` = the
  last effective trigger: `waves_complete` fires on the tick that wave **triggers** (76.0 s), so the clock ends at 86.0 s.
- `deferral` = `burst_telegraph + max(aimed_max × aimed_gap, forward_max × forward_gap)` = 0.8 s — `FighterBrain` defers
  budget expiry only to the end of a running burst.
- **`worst_exit` is the curved-exit bound, not the Razor-shaped straight line** (review round 1 B1; deviation from the
  task wording, recorded in DECISIONS). `_tick_disengage` turns the fighter's *velocity* toward its exit point at
  ω = min(turn_rate, acceleration/exit_speed) = 1.346 rad/s while asking for `exit_speed`, so a fighter flying away from
  its exit swings round on a ≈ 386 px radius. The real scene takes **4.87 s** from the rect centre heading away; the
  straight-line term is 2.84 s. Bound used: `π/ω + (exit_distance + 2·exit_speed/ω)/exit_speed` = 2.33 + 3.03 =
  **5.37 s** (a half turn, then a run covering `exit_distance` plus at most a turn diameter; the run to the exit point
  is never longer than that while `exit_distance ≥` radius/2).
  - **Gated on the real scene:** `test_the_fighter_exit_term_bounds_a_real_fighters_disengage` hand-ticks
    `fighter.tscn` in the Assault harness (like `test_fighter.gd`) from `enter_phase(DISENGAGE)` over a 5 × 5 grid of
    the visible view × 8 headings plus the two named starts, each at `max_speed` **and** at
    `STANDING_START_FRACTION × max_speed + 1` (round 2 B3: just above the standing-start threshold the turn-round is
    slowest — 5.20 s at the centre), 404 starts, and asserts each is freed within the bound (real slack 0.17 s). Boundary: it also asserts the slowest start takes longer than the straight-line term, which is the
    proof the task's original term was not a bound.
  - **Not changed here:** `DroneConcurrency.ai_shooter_kinds()`'s fighter lifetime (the t16 count gates) still uses the
    straight-line exit. With the bound, deep_space's all-alive peak would read 21 against t16's limit of 20 (reviewer's
    measurement). That is t16's gate and the owner's call, so it goes to DECISIONS and Follow-ups, not into this task.
- MARGIN is the file's 0.5. **No bullet term**: rounds die with their ship (`BulletPool._exit_tree()`).
- Computed today: tail 6.0 + 0.8 + 5.37 + 0.5 = **12.67 s**; the worst entry is 72.8 s → (72.8 − 76.0) + 12.67 =
  **9.47 < 10**, margin **0.53 s**. No lever is needed. The test prints the worst entry and its margin.
- Sanity: cloud_descent produces exactly **31** fighter rows (25 loose + wedge 3 + V 3).

**Boundary rows** (each goes through `_deadline_rows`, with the shipped section as the control, and asserts the
*computed value* exceeds the timeout):
- **Literal, from the task:** a fighter added to a freshly built cloud_descent's 76.0 s wave at delay 0.8 (that wave's
  own latest delay) is the one row flagged; its `rel` is 0.8, its computed value 13.47 is `≥ 10.9` and `> timeout`. Plus
  a plain assertion that the **shipped** 76.0 s wave contains no fighter.
- **Config-derived (N5, survives lever 1):** a one-fighter wave inserted just before the last wave at `last_trigger +
  timeout − tail + 0.25` (73.58 s today) is the one row flagged; the same wave 0.25 s inside the limit (73.08 s) is not
  (round 2 note).
- **Gatling:** a Gatling added at delay 0 to each ENEMIES_CLEARED section's last wave computes `7.0 + 2.08 (spin_up 0.25
  + sync_wait_max 0.75 + 12 × 0.09) + worst_exit(260, 520, 600, 900, 804) 2.92 + 0.5` ≈ **12.50**. Asserted flagged and
  `> timeout` for cloud_descent by name; printed for station_assault (180 s boss net). It keeps the Razor-shaped term as
  the task specifies: the Gatling's real exit curves too and is longer, which only makes a must-fail row fail harder.
- **Plain:** no ENEMIES_CLEARED section's waves contain the Gatling scene (station reinforcements spawn in code, not
  section waves, and are out of scope).

The `test_level1_drone_exit.gd` shape: a real `WaveManager` fed **every** cloud_descent wave from 66.0 s onward (66 s
fighter pair, 68 s drones, 72 s fighters + V3 + rail ram, 76 s drones), re-timed by −66 s in list order; a real
`ArenaCamera`; a stationary, hurtbox-less player stub at the lower centre of the view; brains seeded from spawn index
before `_ready()`; 1× clock; game time = summed physics delta.
- `test_cloud_descents_fighters_leave_under_ai_before_the_timeout`: `waves_complete` fires on the re-timed 76 s trigger;
  every ship and every fighter spawned; **the container (rounds included — what `LevelDirector` polls) is empty within
  `enemies_cleared_timeout` of `waves_complete`**; every fighter left in DISENGAGE with no `EnemyPathMover`. Prints the
  measured margin for the container and for the last fighter.
- Boundary `test_a_rail_driven_fighter_wave_is_rejected`: the same waves with every fighter given a `StraightMovement`
  rail (duplicated entries) carry an `EnemyPathMover` — the predicate the main case rejects. Runs 7.5 s (past every
  spawn timer), then stops the `WaveManager`.
- Why 66 s: no fighter spawned before 66 s can be alive at 76 s: worst-case life after entry ≈ 12.2 s (with the curved
  exit bound); the latest earlier fighters, the 59.0 s wedge, enter by 59.1 s and are gone by ≈ 71.3 s.

### Prototype measurements (working tree, 2026-10-06)
| Check | Value | Limit |
|---|---|---|
| Exit run: container empty after `waves_complete` | **9.07 s** (margin 0.93 s) — set by the 76 s **drones** (Ph2's own run: 9.13 s) | 10.0 |
| Exit run: last fighter left after `waves_complete` | **4.35 s** (margin 5.65 s) | 10.0 |
| Exit run: 17 ships (9 fighters), all fighters DISENGAGE, no `EnemyPathMover` | ✓ | |
| Measured shots/s, cloud_descent | **8.50** (83 shots, 31 ships, all DISENGAGE) | 18.75 |
| All-alive peak, cloud_descent | **9** | 16 |
| Attack-capable peak, cloud_descent | **8** (min(alive, cap) model 8) | 12 |
| deep_space / planet_approach count gates (unchanged) | 17 / 16, 13 / 14 | 20, 15 |
| Analytic shots/s, cloud_descent (printed only) | 36.13 | — |

### Levers
None needed (all gates pass with large margins). Only the epic's pre-approved levers would be allowed.

### Rejected
- Replaying only the last wave (the drone test's shape): it contains no fighter.
- Replaying the whole section from 0 s: 86 s of wall time at 1× for no extra coverage (see "Why 66 s").
- Running the exit test at 4×: `LevelDirector` measures its timeout on the wall clock; at 1× game time and wall time
  agree, so the run is the faithful one. Cost ≈ 21 s of gate time.
- Splitting the 42 s six-ship squad: the count gates pass; splitting is lever 3, reserved for a failing gate.

## Build sequence
1. Tests: pin rows + `_RAIL_SECTIONS` retirement + the never-vacuous assertion + `MIGRATED_SECTIONS` and sanity counts;
   the cloud_descent measured case; the deadline rows and boundaries; the exit test. On HEAD's level the pin, the
   migrated-section tests and the exit test go red; on the edit, green.
2. Level edit and comment touch-ups (already in the working tree).
3. `bash /agent/verify.sh`, then `scripts/check-test-leaks.sh`. `git status` shows no stray file (only the new test
   and its `.uid`).
4. DECISIONS ("Phase 3, t17 — as built"), STATUS, progress. Docs for the roster / CLAUDE.md paragraph are t18's
   (the DECISIONS line names `test_level1_fighter_exit.gd` for it).

## Test plan
- `test_level1_fighter_spawns.gd`: the regenerated pin; `test_the_pin_itself_is_internally_consistent` (unchanged
  counts 18 / 19 / 27); `test_legacy_peak_…` (no section on rails; every frozen key is live-checked or gated);
  `test_migrated_sections_have_no_rail_left` (64); `test_loose_pairs_are_tagged_with_their_wave_index` (43);
  `test_a_fighter_line_given_move_again_fails_the_pin` (boundary, unchanged); the count gates over all three sections;
  `test_extra_formations_at_the_peak_break_the_count_gates` (boundary, unchanged).
- `test_level1_fighter_fire_density.gd`: + `test_cloud_descent_measured_shots_per_s_within_1_25x`.
- `test_engagement_deadline.gd`: + `test_every_enemies_cleared_fighter_entry_clears_the_timeout` (per-entry rows,
  prints worst entry and margin), + `test_a_fighter_in_the_last_wave_at_delay_0_8_misses_the_timeout` (literal
  boundary, and the shipped last wave has no fighter), + `test_a_fighter_just_past_the_config_derived_limit_misses_the_timeout`
  (N5 boundary), + `test_a_gatling_in_an_enemies_cleared_last_wave_misses_the_timeout` (boundary),
  + `test_no_enemies_cleared_section_spawns_a_gatling`.
- `test_level1_fighter_exit.gd`: the main run and the rail boundary (above).

## Risks
- **The section's real margin is the drones', not the fighters'.** The container empties 9.07 s after
  `waves_complete` (0.93 s margin), driven by the 76 s Swarm Drones — Ph2 measured 9.13 s for that wave alone and its
  analytic deadline is 9.58 s. The fighters finish at 4.35 s. This task does not change the drones; the run is one
  seeded scenario, so physics-order jitter of a frame or two cannot cross 0.93 s. Recorded in DECISIONS.
- **Single-file leak noise.** Running some test files alone (even a test that only names `Fighter` or
  `SwarmDroneBrain`) prints Godot's exit-leak lines; the existing `test_level1_fighter_fire_density.gd` does the same
  on HEAD. The acceptance check is the full-suite `scripts/check-test-leaks.sh`, which is what will be run and
  reported.
- **Gate time** grows by ≈ 21 s (exit run) + ≈ 21 s (cloud_descent measured run).
- **Separation** between squad mates in the shipped formations is not gated (t9's open decision); the 42 s six-ship
  squad and the 72 s squad of four are the densest. Not measured here; listed as a follow-up.

## Out of scope
Docs, roster and the epic dossier (t18); any lever; drones; station reinforcements; a moving-player scenario.
