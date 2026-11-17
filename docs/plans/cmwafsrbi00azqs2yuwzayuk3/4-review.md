VERDICT: CHANGES_REQUESTED

## Round 1

Reviewed `3-plan.md` and `1-context.md` against the code at `7225e63` (the director, `level_1.tscn`, `laser_ray.gd` / `.tscn`, `laser_wall.tscn`,
`level1_slice_replay.gd`, `level1_column_replay_worker.gd`, `ph10_exit_keys.gd`, the heavy's brain / scene / config, `rocket_battery_mount.gd`,
`turret_mount_scenes.gd`, `wave_manager.gd`, `level_director.gd`, `test_engagement_deadline.gd`, `test_level1_specialist_spawns.gd`,
`test_level1_specialist_exit.gd`, `test_level1_ph8_attacks.gd`, `test_heavy_gunship.gd`, `level1_drone_concurrency.gd`, `tests/README.md`, DECISIONS Phase 10),
the epic plan §2.4.3 / §2.5 / §2.12 / §2.15 / §2.16 and the epic review's N4 / N5.

The plan covers every requirement of §2.12 and the task statement, keeps the approved design, marks its real departures (D), and its arithmetic is right where it
matters (deadline tail 19.58 s, worst row 6.38 s, boundary (a) limit 66.42 s between the 66.0 / 68.0 waves, legacy peaks 1 / 3, spill-over 22.58 s < 30 s, cloud_descent
columns dark at 42.4 s). Two things must change before hours of unattended work start: a sanity row whose fixed tolerance is tighter than the 16× clock it runs on
(finding 1), and a warm-start spec that can build a laser that never switches off (finding 2). The rest are minor.

### Checked and confirmed (no action)
- Director rows: deep_space 3.5 s `b.heavy_gunship().at(0, -500)` with no rail (`level_1_director.gd:348-350`); cloud_descent 50.0 s `.move(b.straight(42))` (:987),
  62.0 s `.move(b.straight(36))` ×2, the second `.delay(0.8)` (:1017-1018); `_spawn_laser_columns(columns, warn = 3.0, active = 4.0)` (:218). Hoisting the defaults is
  behaviour-identical; `test_level1_laser_columns.gd:187` passes explicit 0.0 / 0.0 and is unaffected.
- `LaserWallWave` = `laser_wall.tscn` at (0, −380) (`level_1.tscn:46-47`); 12 rays at x 28…644, `warn_duration = 3.0`, `registers_hazard`, default `auto_start` /
  `active_duration` 4.0 (`laser_wall.tscn`, `laser_ray.gd:31-38`). Rays start in `_ready()` (`laser_ray.gd:141-142`), so setting `warn_duration` before `add_child` works.
  The level's wall and deep_space section time both start in the same `_ready` pass (`LevelDirector.start()` → `_advance()` → `load_section`), so N4's "wall at
  section 0" premise holds and the plan's warn shift (3.0 − 2.5 = 0.5 s) restores lethality to 3.56–7.56 s section time (increase 7 × 0.4 / 5 = 0.56 s,
  dissolve 7 × 0.6 / 5 = 0.84 s, `laser_ray.tscn` SpriteFrames).
- N5: the pod closes at budget expiry, not at DISENGAGE (`heavy_gunship_brain.gd:302-311` `missile_gate_open`, :657-667 `_missiles_open` on `_expiry_seen`;
  `_enter_disengage` :695-701 `scan(0.0)`), so the rocket term `engage + rocket max_time` is sound; boundary (b) is derived from config + the measured exit.
  `RocketBatteryMount.pool_specs()` (:42-54) gives DUMB / PURSUIT scenes; `EnemyRocketScenes.max_time_of()` reads `max_time`.
- §2.12's boundary (a) wording really is a negative delay (10 − 19.58); the fighter's config-derived row (`test_engagement_deadline.gd:352-395`) is the right
  precedent. Note its helper `_with_fighter_wave_before_last` asserts the trigger lies between the last two waves (72 / 76), so 66.42 s needs a generalised
  insert-in-list-order helper (the plan says so).
- `run()`'s default path (`level1_slice_replay.gd:142-190`) can stay byte-for-byte unchanged behind `if light_lasers`; every existing caller (ph8 / ph9 attacks,
  mine layer, corvette, support, heavy gunship statics) uses the default. No other test replays the 50.0 / 62.0 s cloud_descent waves with heavies.
- Exit probe only through `ph10_exit_keys.gd::heavy_gunship_exit()` (memo; t4 9.03 s). The spawner `set_script` technique exists (`level1_column_replay_worker.gd:114-116`);
  `_wall_wave_row()` already reads the wall's scene and position from `level_1.tscn` state (`test_level1_specialist_spawns.gd:1289-1314`).

### Findings

1. **Blocking — the N4 sanity row's fixed ±0.4 s cannot hold at 16× and contradicts `tests/README.md` rule 1.** Plan lines 84-86 (and Risks line 143) assert the wall
   rays first lethal at 3.56 s and dark at 7.56 s, and each column first lethal at `row.time + lethal_offset()`, "each within ±0.4 s". Every one of those edges is
   reached through **idle-time** steps: the warn `SceneTreeTimer` (`laser_ray.gd:188-189`), the `laser_increase` animation (AnimatedSprite2D, idle) ending in
   `_on_animation_finished` (:211-225), and for the end also the `active_duration` timer (:224-225). Each step lands on an idle frame, and at 16× an idle frame is
   ≈ 0.26–0.3 game s (`tests/README.md:438-439, 446-447`; `level1_slice_replay.gd:18-21`; the plan's own context says 0.1–0.3). The onset spans two such steps (up to
   ≈ 0.6 s off) and the end three (up to ≈ 0.8–0.9 s), so a symmetric ±0.4 s around the fixed 7.56 s will fail a large share of runs. README rule 1 is explicit: a
   fixed tolerance tighter than the idle frame either stays at a lower multiplier or **derives its tolerance from the largest idle delta seen**
   (`test_level1_specialist_exit.gd:185-187, 267-270`: `_max_idle_delta + _TICK`, one-sided `assert_gte` / `assert_lt`). Required change: record the max idle delta
   during the lit run (`process_frame` hook, as there); assert onset ∈ [expected − 1 tick, expected + 2·max_idle + 1 tick] and (end − observed onset) ∈
   [active − 1 tick, active + max_idle + 1 tick] (or the end against the fixed figure with 3·max_idle); and add a guard that the derived tolerance stays well below the
   2.5 s shift N4 describes, so the row still catches that bug. Also read the wall's onset from **the wall rays' own** scene `warn_duration` + increase, not
   `lethal_offset()` (which the plan defines from `COLUMN_WARN_SECONDS`, line 48) — the wall's end already uses the rays' own `active_duration`, the onset should match.

2. **Blocking — the warm-start spec can build a ray that is lethal forever, and nothing tests the branch.** Plan lines 34-36 (columns) and 37-39 (wall): a row with
   `row.time + lit_seconds() > lit_from` is lit at slice start with warn floored at 0 and "the active time shortened by the overshoot". `lit_seconds()` includes the
   0.84 s dissolve, so a row whose lethal phase has already ended (lit_from inside the dissolve) gets `active ≤ 0`; `laser_ray.gd:33-35` and :224 make
   `active_duration <= 0` mean **never dissolve** — the replay would then hold a permanent kill strip. The same applies to the wall ("lit_from < wall dark time",
   "the same approximation"). Fix the spec: light a carried-over row (or the wall) only while `elapsed < warn + increase + active` (its lethal end), and floor the
   remaining active at a positive value. §2.12 requires this branch and t12 is meant to rely on the helper, yet no t11 row runs it (the plan says so, line 35-36):
   add one cheap row (≈ 0.5–1 game s, e.g. `lit_from` 7.0 for deep_space: the 6.0 s row's three rays appear at slice start and turn lethal near section 9.56 within
   finding 1's derived tolerance; and a `lit_from` inside a row's dissolve lights nothing for it).

3. **Minor — the risk analysis misses the 6.0 s column at x 640, the likelier killer.** `level_1_director.gd:93-97`: the 6.0 s set includes x 640, hazard from 6.0 s,
   lethal ≈ 9.56–13.56 s. The deep_space heavy's APPROACH target is `held_range()` 420 px from the stub on the line to it (`heavy_gunship_brain.gd:10-11`): from
   (640, −640) to the stub (640, 610) that is (640, 190), **on that column**, and its BROADSIDE arc is centred straight above the stub (±70°,
   `assault_arc_half_deg`) for most of its 9 s budget (~section 8.5–12.5). Plan Risks line 137-138 name only the wall, and lever (2) (`.at(160, -500)`) clears the wall
   but not this column. Name it, and move the lit measurement earlier in the build sequence (right after step 3) since it is the step most likely to end in
   ESCALATE. Related: the lit run's cap (line 70) uses the hazard-free probe exit; if a DISENGAGE detours round a lit 14.0 s column and the cap ends the run with the
   heavy alive, have the row report its phase / position / time so the failure is diagnosable rather than a bare "did not leave".

4. **Minor — the kill boundary departs from §2.12 without a (D) and never exercises a column kill.** §2.12: "held on x 640 … through the 6.0 s column's lit window
   reports a death under a lit ray". Plan lines 76-83: at x 640 the wall's 588 / 644 rays kill the hull at ≈ section 5.4 s and the run stops there, so the
   `source == "column"` attribution and a column-ray kill are never observed. Either mark it (D) and log it, or hold the hull at x 1152 (the 6.0 s set's column
   outside the wall, x 0–672) so the first covered death is a column's at ≈ 9.6 s and assert `source == "column"` (≈ +4 game s, ≈ +0.3 s real), keeping the wall
   case if cheap.

5. **Minor — gate-time accounting for the moved probe.** Plan line 140: the memoised probe (≈ 2.9 s, README row t4) moves from `test_heavy_gunship.gd`'s `before_all`
   (outside any testcase) into the first `test_engagement_deadline.gd` test that calls it (inside a testcase). `scripts/gate-time.sh`'s per-file sums would show
   ≈ +2.9 s on a file this task changes while the matching drop is invisible (it was outside testcases), so "own new / changed files ≤ 1.5 × 3.0 s" could read as
   ≈ 5.9 s and trigger a spurious ESCALATE. State the accounting (net of the probe's move, confirmed by the two-run suite mean) in the plan and the README row, or
   call the probe in `test_engagement_deadline.gd`'s `before_all` so it sits outside testcases as before. Also: 16× replays of ≈ 42–48 game s at the deep_space /
   cloud traffic density (Ph8 t19: five slices ≈ 2.9 s; Ph9 t14: three ≈ 2.35 s) put the estimate at ≈ 3.0–3.5 s, at the allotment's edge — fine with the 4.5 s
   escalation line, but say so.

6. **Minor — the "run from 0 s" alternative N4 offers is not examined.** N4's second option is to start the deep_space lit replay at 0.0 s. That needs no wall warn
   shift at all (the wall is then exactly the level's), adds only 2.5 game s (≈ 0.16 s real), and puts the heavy among the 0.0–1.5 s waves' ships it really meets.
   Either adopt it for the deep_space lit run (the warm-start branch then stays only for columns, finding 2) or add it to "Alternatives rejected" with the reason.

7. **Minor — define the sampled sets so no row is vacuous or undefined.** (a) Plan line 85: "each deep_space column row the run reached" — the run stops when the
   heavy leaves (≈ slice 12–20), so the 14.0 s row may or may not reach its 17.56 s onset and the 22.0 s row never does before the cap: assert onset / end only for
   edges whose expected time + tolerance precedes the stop, and assert the wall and the 6.0 s row are always among them. (b) Plan line 43: "covered = some lit ray's
   `danger_rect()`" — "lit" in DECISIONS includes the warning phase; say **`is_lethal_now()`** rays, so a death beside a telegraphing ray is never counted as covered.
   (c) Line 74 "all three heavies hooked through `tweak`": `tweak` runs before `_ready()`, and the mounts are built in the root's `_ready()` by `build_mounts()`, so
   `phase_changed` / `round_fired` must be connected through `ship.ready` (the `test_level1_ph8_attacks.gd:79-85` pattern); `died` and `Modules/*.destroyed` can be
   connected in `tweak`.

8. **Minor — arithmetic slip in boundary (b)'s note.** Plan line 106: the shipped 62.8 s row's open-pod figure "holds only while exit ≥ 7.65 s". With the window term
   it is −13.2 + 9.0 + 1.05 + 6.0 + 0.5 = 3.35, so it holds while exit ≥ **6.65 s** (N5's 7.7 s omitted the window). It is printed and goes to DECISIONS; correct it.

9. **Minor (optional) — a third copy of `_rail_lifetime`.** Plan line 58 copies it from `test_level1_specialist_spawns.gd:219-238` (itself the same arithmetic as
   `test_level1_fighter_spawns.gd`'s). Acceptable to keep existing gates untouched; if you prefer one copy, a static in `tests/helpers/level1_drone_concurrency.gd`
   taking the cull rect would serve all three. Not required.

## Round 2

Reviewed revision 2 of `3-plan.md` (and its "Response to review round 1") against the code at `7225e63`: `laser_ray.gd` / `laser_ray.tscn` / `laser_wall.tscn`,
`level_1.tscn:46-47`, `level_1_director.gd` (schedule :80-104, `_process` :140-155, `_spawn_laser_columns` :218-231, deep_space waves :292-350, cloud_descent waves),
`wave_manager.gd:56-100`, `wave_builder.gd:94, 272-281`, `level1_slice_replay.gd`, `level1_column_replay_worker.gd`, `ph10_exit_keys.gd`, the heavy's brain / config,
`rocket_battery_mount.gd:42-54`, `test_engagement_deadline.gd` (`_deadline_rows` :236-260, `_with_fighter_wave_before_last` :375-395), `test_heavy_gunship.gd:40, 73-75, 750-770`,
`test_level1_specialist_spawns.gd:215-238`, `test_level1_specialist_exit.gd:183-188, 265-270`, `test_level1_ph8_attacks.gd`, `tests/README.md` (Gate time, the three leak
traps), `addons/gut/gut.gd:994` (files sorted by name), the epic §2.12 / §2.15 / §2.16 and N4 / N5.

### Round-1 findings: status
- **1 (±0.4 s at 16×) — not resolved; see R2-1.** The upper sides are now derived from the idle delta, but the lower sides (`expected − TICK`, `active − 2·TICK`) are tighter
  than the engine's own timer semantics and fail on most runs, and the fixed 1.0 s guard is machine-dependent.
- **2 (warm start) — spec resolved, test only partly; see R2-2.** The three-branch rule (plan :37-45) can no longer build `active ≤ 0`, and the arithmetic checks out
  (wall at `lit_from` 7.0: 7.56 − 7.0 − 0.76 < 0.25, not lit; 6.0 s row at 7.0: warn 2.0, lethal at section 9.56; at 13.8: 7.56 − 7.8 − 0.76 < 0, not lit; init 1.0 / 5 = 0.2 s,
  increase 7 × 0.4 / 5 = 0.56 s, dissolve 7 × 0.6 / 5 = 0.84 s, `laser_ray.tscn:119-227`). But no row runs the middle (shortened-active) branch, the one round 1 was about.
- **3 (the x 640 column)** — resolved: named in Risks (:184-186) and §5 (:143-144), lit run is build step 4, a capped run prints phase / position / time.
- **4 (column kill never exercised)** — resolved in design (two held heavies). Checked feasible: `slice_waves()` returns fresh `WaveResource`s with a fresh `entries` array
  (`level1_slice_replay.gd:97-102`), so appending a second entry touches nothing shipped; `_on_wave_triggered` / `spawn_count` count it (:195-198); both heavies get the tweak
  (:215-218); x 1152 is a 6.0 s column (`level_1_director.gd:83`) and outside the wall (rays at local 28…644 + 28 px, world 0–672, `laser_wall.tscn`); every ray's strip is
  12 × 128 px from y −380 (`laser_ray.gd:26, 174-179`), so a heavy spawned at y −640 (hurtbox 72 px half-height) is covered once its centre passes y −452: ≈ 1.9 s at
  accel 120 / max 140 straight down to its APPROACH point (640, 190) (`heavy_gunship_brain.gd:492-506`), i.e. section ≈ 5.4 s, inside the wall's 3.56–7.56 s; the x 1152 heavy
  is far inside the strip by 9.56 s. One gap: see R2-4.
- **5 (probe accounting)** — resolved: the probe goes in `test_engagement_deadline.gd`'s `before_all()` (that file has no hooks today; GUT sorts files by name, so it runs before
  `test_heavy_gunship.gd` and `test_level1_heavy_spawns.gd`, whose calls become memo hits). The estimate itself is still off; see R2-3.
- **6 (run from 0 s)** — resolved. `slice_waves(sec, 0.0, …)` keeps every trigger unchanged, and the wall added at the same `process_frame` resume as `load_section()` starts
  its warn timer in the same idle frame as `WaveManager`'s clock (`wave_manager.gd:56-57`), so wall and section clock line up exactly as in the level. They do **not** line up
  with the replay's physics slice time `t` (`level1_slice_replay.gd:168-175`), which starts one idle frame later; that is part of R2-1.
- **7 (definitions)** — resolved (checked edges, `is_lethal_now()`, mounts through `ship.ready`).
- **8 (6.65 s)** — resolved: −13.2 + 9.0 + 1.05 + 6.0 + 0.5 = 3.35, so the open-pod figure reaches 10 only while exit ≥ 6.65 s.
- **9** — accepted as a copy. Note the copied `_rail_lifetime` returns **0.0** for `movement == null` (`test_level1_specialist_spawns.gd:225-226`); the plan's INF for the
  no-rail deep_space legacy row (:74) must be a special case in the caller, or the recomputed deep_space legacy peak is 0, not the frozen 1.

Also re-checked and fine: the deadline tail 9.0 + max(1.05 + 9.03, 6.0) + 0.5 = 19.58, worst row 6.38 s; boundary (a) limit 76 + 10 − 19.58 = 66.42 (cloud_descent's triggers are
monotonic, so the inserted wave's effective trigger is its own); boundary (b) at 66.37: 9.95 s shipped, 15.95 s open; spill-over 22.58 s < 30 s; the 34.0 s columns dark at 42.4 s;
`pool_specs()` is an instance method (instantiate the mount scene or read the live heavy's mount).

### Findings

**R2-1. Blocking — the N4 timing row's lower bounds contradict how `SceneTreeTimer`s are clocked, and its 1.0 s guard is machine-dependent.** Plan :105-111 (and :51-52, :193).
- `laser_ray.gd:189` creates the warn timer in `start()` and `:225` the active timer inside the `laser_increase` `animation_finished` callback, which `AnimatedSprite2D` emits
  from its internal **process** notification. In Godot 4 `SceneTree::process()` emits `process_frame`, runs `_process`, and only then runs `process_timers(p_time)` over every
  timer in the list, so a timer created anywhere earlier in that iteration (a physics callback, the `process_frame` resume, `_process`) is decremented by the **whole** idle
  delta of that frame, including the physics steps that ran before it existed. The same holds for the `laser_init` / `laser_increase` animations started before `_process`.
- Onset: the wall in the from-0 run is created at the load frame's `process_frame` resume and is credited that frame's whole delta before `t` starts counting; a column
  fired on physics step *j* of an iteration is credited *j − 1* ticks it never lived. So a ray can turn lethal up to one idle delta **early** in slice time. Example, a steady
  18 ticks per idle frame (≈ 0.3 s, the README's 16× figure): the wall's warn fires at tick 162, the increase ends at 198, first lethal observed at tick 199 = **3.32 s**,
  under the plan's floor 3.56 − 1/60 = 3.54 s. With 6 ticks per frame it reads 3.52 s, also under. The plan's lower bound fails on a large share of runs.
- Span: the active timer is credited the delta of the frame in which IDLE began, which holds no lethal physics, so (last − first lethal) ∈ [active − d − TICK, active − TICK)
  for steady frames: **always shorter than active**, and below the plan's `active − 2·TICK` unless active − d happens to land within a tick of a frame boundary. With 18 ticks
  per frame: 233 ticks = 3.883 s against a floor of 3.967 s. This row would fail on nearly every run.
- Guard: `2·max_idle + TICK < 1.0 s` over the whole run's largest idle delta means one frame over about 30 ms of real time fails it. At 16× `max_physics_steps_per_frame` is 128,
  so an idle frame can reach 2.13 game s; the README already puts the replays' *typical* frame at ≈ 0.3 s, and a frame that builds a heavy (six parts, four mounts, their pools),
  adds the wall's 12 × 12 `AnimatedSprite2D` segments, or meets a hiccup on the harness machine can pass 0.49 s with nothing wrong. DECISIONS Ph10 t5 (the `_fresh_idle_delta()`
  note) records exactly this kind of machine-dependent failure on the harness.
- **Required:** (a) lower sides with the same idle allowance as the upper: onset ∈ [expected − max_idle − TICK, expected + 2·max_idle + 2·TICK] (the extra tick on the late side
  is the column spawner's own step); span ∈ [active − max_idle − 2·TICK, active + max_idle + TICK]. (b) Include the load frame's own delta in `max_idle`: read
  `get_process_delta_time()` at the `load_section()` moment, because a hook connected during that `process_frame` emission is not called for it. (c) Tie the guard to what must be
  caught, not to 1.0 s: N4's shift is 2.5 s, so e.g. assert the late tolerance < 1.25 s (half the shift). Better still, take each edge's tolerance from the largest idle
  delta **between that ray's creation and the observed edge** (record `(t, delta)` per frame; rule 3 allows it, an assertion reads it), so a hiccup elsewhere cannot fail it.
  (d) Recommended for fidelity: fire the replay's columns on an idle-time accumulator started at the load frame (a `process_frame` hook, the semantics of
  `Level1Director._process`, `level_1_director.gd:140-155`), not on the physics clock (plan :34-36). As written they light up to one idle frame (≈ 0.3 s) later relative to the
  waves and the wall than the level does, which is not "the lit world is the real world".

**R2-2. Blocking (small) — round 1's finding 2 asked that the warm-start branch be tested; the shortened-active branch still is not.** Plan :112-115. The `lit_from` 7.0 case
puts the 6.0 s row at elapsed 1.0 < warn (the exact branch, plan :40), and both the wall at 7.0 and everything at 13.8 take the "not lit" branch (:44). Nothing runs
`warn < elapsed` with `rest ≥ MIN_ACTIVE` (:41-43): warn 0, the 0.2 s `laser_init` (`laser_ray.gd:203-209`), the increase, and a shortened `active`, which is the approximate branch,
the one whose earlier form built a ray that never dissolves, and the one t12 inherits. Fix at no extra cost: run the case from `lit_from` 11.0 instead of 7.0. The 6.0 s row has
elapsed 5.0 > 3.0 and rest = 7.56 − 11.0 + 6.0 − 0.76 = 1.8 ≥ 0.25, so its three rays are lit with warn 0 / active 1.8, lethal from section ≈ 11.76 and dark at **13.56 within
R2-1's tolerance** (assert both edges, and that they dissolve). The wall at 11.0 is not lit. The exact branch is still covered by the boundary run's wall (`lit_from` 2.5,
warn 0.5), whose onset the N4 row checks. Derive the run length from the expected end + the late tolerance, not "≈ 3.3 s" (see R2-5).

**R2-3. Minor — the gate-time estimate cannot reach its low end, and the plan should say up front that it overruns the 3.0 s allotment.** Plan :187-192. A 16× clock ticks at most
960 times per real second, so ≈ 55–59 game s of replay (deep_space ≈ 20, cloud ≈ 23.9 (49.0 → 72.85), boundary ≈ 7.4 when it stops on its second death (9.6–9.9 section),
carried-over ≈ 3.5, lasers-off 0.5) costs **≥ 3.45–3.7 s real before any CPU**. The deep_space slice is full traffic plus 21 rays, and the README shows a lighter replay is
already CPU-bound at 16× (`test_level1_fighter_fire_density.gd`, 0.8 of 1.04 ms per tick), so ≈ 3.8–4.5 s is the realistic figure: over the task's "gate time within 3.0 s",
close to the 1.5× escalation line (4.5 s). Restate the estimate, mark the expected overrun as a (D) for DECISIONS and the README row (the t4 precedent: over, logged, absorbed by
t1's surplus; the suite is at 205.6 s of 237), and keep the §2.15 rule as the stop: past 4.5 s, `Result: ESCALATE`. Say also where the shared scenarios run (`before_all()` or a
lazy memo in the first test), because that decides whether `gate-time.sh`'s per-file testcase sums show them.

**R2-4. Minor — boundary-run and probe wiring the implementer needs.** (a) `observe` receives only `_target`, the first heavy (`level1_slice_replay.gd:176-178`); the x 1152 heavy
is reachable only through the caller's tweak capture (the `test_level1_ph8_attacks.gd:104-110` pattern), with "first" / "second" by spawn order. The extra entry is a
`SpawnEntryResource`, which `b.heavy_gunship().at(0, -500)` is not (it returns a `SpawnConfig`, `wave_builder.gd:94`); take it from `b.wave(0.0, [ … ]).entries[0]`
(`wave_builder.gd:272-281`). (b) `ph10_exit_keys.prepare_probe` strips group `player` from **every** node in the tree (`ph10_exit_keys.gd:57-61`). Compute the exit (memo or not)
before any replay harness exists in `test_level1_heavy_spawns.gd`: run alone with `-gselect`, the memo misses, and a cap computed after `HARNESS.assault()` built the stub would
leave every heavy with no target. (c) `test_heavy_gunship.gd`'s `_probe_s` print (:73-75, :751) will read ≈ 0 s once the deadline file measures first; say so in the README row.

**R2-5. Minor — derive the short runs' lengths and the from-0 cap from what they must observe.** (a) The carried-over run is "≈ 3.3 game s" (:112): under the "checked edges"
rule (:107) a longer idle frame could push the expected edge past the stop and make the row vacuous. Use expected edge + the guard's bound + TICK. (b) The from-0 run is capped at
the hazard-free probe exit (:86). A heavy that detours round a lit column and leaves at, say, 26 s is still correct for a 30 s DURATION section (the spill-over row is the real
limit), but it fails "left after DISENGAGE" and may push a lever or an ESCALATE. Cap at the section's 30.0 s, which costs nothing when it leaves early, and print the lit exit
against the measured 9.03 s.

**R2-6. Minor — `elapsed ≤ warn` is not exact at equality.** Plan :40. At `elapsed == warn` the rule sets warn 0, and a `LaserRay` with `warn_duration <= 0` waits for the
0.2 s `laser_init` before the increase (`laser_ray.gd:188-189, 205-209`), so the onset is 0.2 s late. Use `elapsed < warn` and let equality take the middle branch. No row hits
it today, but t12 picks its own slice starts.

### Verdict
**CHANGES_REQUESTED.** R2-1 is the substantive one: as specified, the N4 timing row fails on most runs because of how the engine clocks timers, not because of a bug in the
replay. R2-2 is a one-number change. With those two fixed (and R2-3's estimate restated), the plan is ready; R2-4 to R2-6 can be handled during implementation without another
review round.
