VERDICT: APPROVED

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

## Round 3

Reviewed revision 3 of `3-plan.md` against the code at `8df0d59`: `laser_ray.gd` (`start()` :182-189, `_on_animation_finished` :203-225, `_begin_dissolve` :248-256,
`is_lethal_now` :296-297), `laser_ray.tscn:119-227` (init 1 × 1.0 / 5 = 0.2 s, increase 7 × 0.4 / 5 = 0.56 s, dissolve 7 × 0.6 / 5 = 0.84 s), `laser_wall.tscn`,
`level_1.tscn:46-50`, `level_1_director.gd` (schedule :80-104, `_process` :140-155, `_spawn_laser_columns` :218-231, deep_space :310-350), `wave_manager.gd` (`_process`
:56-63, spawn position :189-197), `arena_camera.gd:122-146`, `enemy_ai_harness.gd:53-56`, `level1_slice_replay.gd`, `level1_column_replay_worker.gd`, `ph10_exit_keys.gd`,
`heavy_gunship_brain.gd:268-280`, `heavy_gunship_config.tres`, `engagement_budget.gd:50`, `turret_mount.gd:40-42`, `test_heavy_gunship.gd:36-41`,
`test_level1_specialist_exit.gd:183-188, 265-270`, `tests/README.md:435-449`.

Because rounds 1 and 2 both reasoned about idle frames without measuring them, this round **measured** the plan's replay. A throwaway SceneTree script outside the repo
(`/tmp/t11_review/`, nothing in the tree touched) builds exactly the world §2 specifies: `HARNESS.assault()`, the stub at +(0, 250), brains seeded `5171 + index`, a real
`WaveManager` loaded at the third `process_frame` resume, `laser_wall.tscn` at (0, −380) added in that same resume, the director's real `_spawn_laser_columns()` on a
`set_script` spawner fired by an idle clock seeded with the load frame's delta, the clock scaled as `_scale_clock()` does (time_scale, ticks and max steps × 16). Per ray it
records first / last lethal physics tick and the largest idle delta from creation to last lethal frame, i.e. the plan's `d`. Results (this dev container; `user` ≈ `real`,
so CPU-bound where noted):

| Run (16× unless stated) | Idle deltas (game s) | Edges | Heavy |
|---|---|---|---|
| deep_space from 0, shipped offset | 0.11 at first, then 0.2 → 0.5 → 1.25 → **2.13 (the 128-tick cap) from ≈ 7–10 s section**; 39–48 frames for 23 s | wall onset +0.09 (d 1.04, span 3.92); 6.0 s columns onset **+2.29** (11.85 vs 9.56), span **2.12** (d 2.13); 14.0 s columns +2.8 | spawns at **(640, −420)**, dies at section **3.65 / 3.67** under the wall's 588 / 644 rays (2 of 2) |
| same, lasers off | same spiral, max 2.15 | — | — |
| deep_space from 2.5 (wall warn 0.5), heavy `.at(160, -500)` | max 2.15 | wall +0.14 (d 1.22); 6.0 s columns +3.14, span 2.12 | survived |
| deep_space from 0, `.at(160, -500)`, **8×** | max **1.075** (its 64-tick cap), p90 0.77 | — | survived |
| cloud_descent 49.0 → 72.85, rails stripped, lasers off | max 0.25, median 0.11 (tick-paced) | — | three spawn, none dies; 3.25 s real |
| deep_space from 0, `.at(160, -500)`, **max steps capped at 16** (×7) | **≤ 0.283** | wall +0.17 … +0.29, columns +0.31 … +0.42, spans −0.02 … −0.28; every edge inside the plan's bounds; guard 0.60 < 1.25 on every ray | **3 of 7 die**: the 640 column at 9.87 / 9.85 s, the wall's 644 ray at 7.00 s |
| same, uncapped (×4) | max 2.13–2.15 | — | **2 of 4 die**: wall 644 at 7.25 s, 640 column at 12.28 s |

Real time for 23 game s + 3 s settle + engine start: 4.3–4.6 s uncapped, 4.65–4.75 s capped at 16.

### Round-2 findings: status
- **R2-1 — resolved on paper, not in practice; see R3-1.** (a) The bounds are right: my own derivation from the engine order (physics steps, then `process_frame`,
  `_process`, then `process_timers()` over every timer created earlier in that iteration) gives onset ∈ [expected − d_k − d_L, expected + d_m + d_m′ − d_L + 2·TICK] and span ∈
  [active − d − 2·TICK, active + d), inside the plan's [expected − 2d − TICK, expected + 2d + 2TICK] / [active − d − 2TICK, active + d + TICK]; the "two idle frames early"
  reasoning is correct (the creation frame's credit plus the load frame's head start of the idle clock over `t`). Every edge reached in the five probe runs whose edges were printed fell inside them.
  (b) Wall seeded with the load frame's delta: yes (but see R3-5). (c) The guard is tied to N4's shift as asked — and fails on **every** deep_space ray at the plan's clock.
  (d) The idle-clock firing matches `Level1Director._process`: both fire before that frame's `process_timers()`, so a new ray's timer is credited the same frame delta.
- **R2-2 — resolved.** From `lit_from` 11.0 the 6.0 s row has elapsed 5.0 > 3.0, rest = 7.56 − 5.0 − 0.76 = 1.8 ≥ 0.25, lethal 11.76 → 13.56; the wall is not lit
  (7.56 − 11.0 − 0.76 < 0.25); the run length 13.56 − 11.0 + 1.25 + TICK = 3.83 s checks the end edge (14.81 < 14.83) and puts "no ray lethal at the stop" after the latest
  possible end (exp_end + 2d + TICK while the guard holds). Its world is empty, so its d is ≈ 0.11 s and the guard holds there.
- **R2-3 — not resolved; see R3-3.** The restated 3.8–4.5 s rested on round 2's "tick-paced" premise, which the deep_space slice breaks.
- **R2-4 — handled** ((a) `b.wave(...).entries[0]`, tweak capture; (b) exit read in `before_all()`; (c) README note). Correction to round 2: the boundary run's x 640 heavy
  is covered **from spawn** (R3-4), so its wall death comes at ≈ 3.6–4.0 s, not ≈ 5.4 s; still inside the wall's window, so the row is unaffected.
- **R2-5 — handled** (one gap, R3-6). **R2-6 — handled** (`elapsed < warn`; equality gives rest = active − 0.2).

### New findings

**R3-1. Blocking — the deep_space replays are CPU-bound at 16×, so their idle frame is the 128-tick cap (2.13 game s), not the ≈ 0.3 s the timing row and its guard
assume.** Measured above: in all four deep_space configurations (lasers on or off, from 0 or 2.5) the frames spiral to the cap from ≈ 7–10 s section and stay there (≈ 2.4 ms
of CPU per tick against the 1.04 ms a 16× tick has). Consequences, all measured: (1) `2·d + 2·TICK < 1.25` fails on every deep_space ray, the wall included (d 1.04–1.22),
so `test_the_replayed_lasers_are_lethal_when_the_level_makes_them` fails on every run; (2) the plan's fallback (Risks :216-218, "move to 8×") does not help: 8× hits its own
64-tick cap, 1.075 s; (3) with 2.13 s frames the derived tolerance is ±4.3 s, wider than N4's 2.5 s shift, and the replay's columns are lethal **2.3–3.1 s late for half their
real span** (11.85–13.97 vs 9.56–13.56), so "the lit world is the real world" (plan :174-175) does not hold for the main row either. **Required:** bound the idle frame in
every deep_space replay (the lit run and the boundary run; harmless elsewhere) by capping `Engine.max_physics_steps_per_frame` at a small fixed value instead of 16 × the
default. Measured with 16: idle ≤ 0.283 s, every edge inside the bounds with errors of +0.17 … +0.42 s, guard 0.60, and real time within ≈ 5–10 % of the uncapped run (a CPU-bound run is
paced by its CPU either way). The cap does not change the step (still 1/60 game s); Godot shortens the process step to the capped physics steps (the measured deltas never
exceeded cap + 1 ticks), so idle and physics time stay in step. It departs from README rule 1's "scaled together": mark it (D), add the reason to rule 1, and assert in the
replay that its largest idle delta is ≤ cap / 60 + 2·TICK, so a lost cap reads as that and not as a laser bug. (Any other fix that bounds d well under 0.6 s is fine.)

**R3-2. Blocking (small) — the no-death row is a probability, not a fact, and the plan accepts it on one green run.** The same seeded replay flips between runs (idle frame
boundaries move run to run, and with them every spawn and laser time): with the lever-2 offset, 3 of 7 capped runs and 2 of 4 uncapped runs lost the heavy (the 640 column
twice at 9.85–9.87 s and once at 12.28 s, the wall's 644 ray at 7.00 / 7.25 s). Every column death was a side-on hull (−1.49, 1.80, −1.26 rad); side-on, its x half-extent is 72–91 px
(half-diagonal 91.2) against a `hazard_margin` of 90 derived from the unrotated half-width 56 (epic §2.16 row). An unattended run that applies the levers "only if a row
fails" (plan :160) can see one green run, commit, and leave a gate that fails the harness about one time in two. **Required:** (a) the lit rows count as green only after
**N consecutive green runs** of the file on the final tree (say 10, at build step 4 and again at step 6), and a death in **any** run is "a death shows" for the lever
ladder; (b) the lit run records and prints the minimum clearance between each heavy hurtbox and every lethal strip (and every warning strip), so a marginal pass is visible;
asserting a positive clearance margin is a good way to make (a) cheap. Say in Risks that the measured death rate with lever 2 alone is ≈ 40–50 %, so ESCALATE is a live outcome.

**R3-3. Blocking (small) — the gate-time estimate is about half the measured cost, and the plan commits to ESCALATE at the line it will cross.** Measured: the deep_space lit run
≈ 3.0–3.5 s real to the heavy's exit (CPU-bound, ≈ 4.3–4.7 s for 23 game s with start-up), the cloud run ≈ 2.5–2.8 s (tick-paced, 23.85 game s), the boundary run ≈ 1 s, the
carried-over run ≈ 0.3 s: **≈ 6.5–7.5 s**, against the 3.0 s allotment and the 4.5 s line at which Risks :210-211 says `Result: ESCALATE`. Built as written, the task ends in
ESCALATE after the whole implementation. Before building, either cut (for example: stop the cloud run at each heavy's first battery FIRE plus a stated density window, a (D)
on §2.12's density record) or pre-declare the overrun as a (D) with the figures and the headroom argument (suite 205.6 s → ≈ 213 s, phase end ≈ 215.5 s against 234.5 /
237; the t4 precedent, "over, logged, absorbed by t1's surplus") and move the stop to a line the measured cost does not already cross. The choice is the planner's; leaving
"≈ 3.8–4.5 s, ESCALATE past 4.5 s" is not.

**R3-4. Minor — the shipped deep_space offset is a certain wall death, so lever 1 cannot be the first answer to it.** `wave_manager.gd:194` spawns at `cam.global_position
+ cam.offset + offset × 2`, and `arena_camera.gd:122-146` pans the camera toward the player: the stub at (640, 610) gives offset (0, 220) (measured), so `.at(0, -500)` spawns at
(640, **−420**), and the 144 px hull already reaches y −348, 32 px into the wall's strip (y ≥ −380), 0.06 s before it turns lethal. Measured deaths at section 3.65 / 3.67 / 3.98.
This holds in the level whenever the player is below y ≈ 578 (offset > 188 px); the level starts it at y 542 (`level_1.tscn:50`). A wider `hazard_margin` cannot move a hull
that is already inside; lever (2) is the fix for the wall, and record why lever (1) was passed over for it (it stays the first answer to the 640-column deaths, R3-2). Fix the
Risks text (":204-206 may die") and the boundary run's "≈ section 5.4 s" (plan :116) to "from spawn, ≈ 3.6–4.0 s".

**R3-5. Minor — seed every ray's `d` with the load frame's delta, not only the wall's** (plan :56-58, :121). A column's early side is d_k + d_L (its own creation credit plus the idle
clock's head start over `t`), so a column whose own frames are smaller than d_L can read earlier than `expected − 2d − TICK`. Use `max(d_own, d_L)` for every ray (rays relit at
the load moment in the carried-over run are load-moment rays too).

**R3-6. Minor — "the 6.0 s row is among the checked edges" can fail without a bug.** Its end edge is checked only if the run lasts past 13.56 + 1.25 = 14.81 s; the from-0 run stops
when the heavy leaves (measured 15.4–18.1 s in the survivors, earlier if it dies or exits fast). Run on to max(heavy gone, 14.81 + TICK), or require only the onsets to be among the
checked edges.

Re-checked and fine: the warm-start rule and its sweep (no lit result with `active < 0.25`, `warn < 0`); `elapsed == warn` → middle branch, rest = active − 0.2; the static
"which heavies meet lasers" row (34.0 s set dark at 42.4 s < 50.0 s); spill-over 22.58 s < 30 s; deadline tail 19.58 s, worst row 6.38 s, boundary (a) 66.42 s, (b) 9.95 / 15.95 s;
`EngagementBudget.remaining()`, `TurretMount.phase_changed` / `round_fired` exist; `test_heavy_gunship.gd:40` `CLOUD_DESCENT_WINDOW` 23.2 is the constant the live read replaces;
the cloud slice is not CPU-bound at 16× (max idle 0.25 s), so its attack-in-budget rows are sound as planned.

### Verdict
**CHANGES_REQUESTED.** Revision 3's reasoning about timer semantics is correct, and R2-2, R2-4, R2-5 and R2-6 are done. But measuring the replay it specifies shows its premise
is wrong for deep_space: the slice is CPU-bound at 16×, so the idle frame is 2.13 game s. At that frame size the timing row fails every time, the lasers are seconds off, the
no-death row passes or fails at random (≈ 40–50 % deaths even after lever 2), and the file costs about twice the estimate, past the line where the plan stops. Each fix is
small and none changes the design: cap the physics steps per frame in the deep_space replays (R3-1), accept the lit rows only on repeated green runs with a printed
clearance (R3-2), and restate the cost with a decision taken before building (R3-3). With those three in the plan, R3-4 to R3-6 can be handled during implementation without
another review round.

## Round 4

Reviewed revision 4 of `3-plan.md` (§2 :75-87, §3 :111-164, §5 :184-190, §5a :192-240, build steps :258-276, Risks :286-307, Q1 / Q2 :361-365) against the code at `8df0d59`:
`heavy_gunship.tscn:82` (root `CharacterBody2D`, no `collision_layer` / `collision_mask` / `motion_mode` line, so layer 1 / mask 1 / GROUNDED), `defense_turret.tscn:53` (the same),
`assault_drift.gd:16-34` (a turret's only motion is `(0, speed)`), `carrier.tscn:85-87` (layer 0 / mask 0), `space_station.tscn:65`, the epic plan :303 (heavy "mask ENVIRONMENT") and
:449 (carrier "mask 0 (ploughs through, the station's rule)"), `enemy_mover.gd:216-258` (`step`, `move_and_slide()` :258) and `_avoid()` :282-300, `steering.gd:238-311`
(`context_avoid`; `margin` enters only the skirt reach :245 and the cone half-width :269 / :352) and `_segment_danger()` :333-388 (the span's tangents use `info.radius` only,
:364-365), `global/hazards/hazards.gd:31-38` (`around()`), `global/hazards/hazard_info.gd:95-106` (`contains`, `closest_point`), `laser_ray.gd:76, 87-88, 340-350` (footprint
28 + 24 = 52 px), `base_enemy.gd:106-113` (the three hazard fields copied onto the mover), `global/resources/ship_config.gd:22-28`, `heavy_gunship_config.tres` (margin 90,
`max_speed` 140, `range_tolerance` 100), `heavy_gunship_brain.gd:492-506` (`_tick_approach`: BROADSIDE only once `|distance − held_range()| ≤ range_tolerance`),
`ph10_exit_keys.gd:46-74` (the probe frees the body shape), `test_enemy_dual_mode.gd:632-648, 686-695` (`HAZARD_PROFILES`), `test_heavy_gunship.gd:1007-1031`, the workers in
`/tmp/t11_meas/` (read: the world matches §2; it carries `float`, `nomask` and `body=` switches; its `gone` check `if heavy != null` never fires once the heavy is freed, because a
freed object compares equal to null, so it never recorded exits) and `/tmp/t11_review/`.

**Measured** with my own worker (`/tmp/t11_r4/`, nothing in the tree touched; `git diff` shows only the two plan files): the §2 world exactly (`HARNESS.assault()`, stub at
+(0, 250), brains seeded `5171 + index`, a real `WaveManager`, the real wall and the director's real columns on an idle clock, 16× with
`max_physics_steps_per_frame` 16), plus per heavy the first **battery FIRE** (mount `phase_changed`, connected through `ship.ready`) with `budget.remaining()`, DISENGAGE, exit,
the minimum lethal clearance (the plan's definition) and part deaths. Option A's hull term is a scratch `EnemyMover` subclass swapped onto the heavy before `_ready()`, implemented as
§5a (ii) specifies (segment infos' radius + 92, the `around()` reach + 92); it reproduces the plan's clearance figures (min 121-130 px), so it is the same build.

| Deep_space from 0, lever 2 (`.at(160, -500)`) plus | Runs | Laser deaths | Battery FIRE inside the budget | Min lethal clearance (survivors) | Exit |
|---|---|---|---|---|---|
| nothing (GROUNDED, mask 1) | 12 | **8** (wall 644 at 6.68-7.65 s ×6, 640 column at 9.75 / 9.93 s ×2) | 4 / 4 survivors | 6.3 px | 16.0-17.4 s |
| `motion_mode` FLOATING | 12 | 0 | 9 / 12 | **1.5 and 9.6 px** in 2 runs (< 24) | 16.0-17.1 s |
| FLOATING + lever 1 (margin 110) | 12 | 2 (1152 at 13.90 s, 896 at 17.98 s in DISENGAGE) | 5 / 12 | 17.1 px | 15.9-16.8 s |
| **option A** (FLOATING + hull term 92) | **25** | 0 | **0 / 25** | 86.7-130 px | 14.3-16.9 s |
| option A + lever 1 | 12 | 0 | **0 / 12** | 64.0-129.7 px | 14.9-17.3 s |
| **`collision_mask = 0` (the Carrier's rule)** | **30** | **0** | **30 / 30** (9.15-9.42 s, 3.33-3.35 s left, BROADSIDE) | **34.5-66.4 px** | 15.8-16.2 s |

Max idle delta 0.276-0.283 s in all 102 runs (R3-1's bound 16/60 + 2·TICK = 0.30 holds). Real time of one lit run (engine start, run, 3 s settle): 3.9-4.1 s. The cloud
run (49.0 → 72.85, rails stripped, lasers off, uncapped, ×7): all three heavies fire a battery inside the budget every time (54.2 / 66.5 / 67.4 s, 4.3-4.8 s left), none dies, 3.25 s real.
Per-tick traces of four lever-2 runs (GROUNDED): every floor contact was a **Sniper** or a **Fighter** (normal within 45° of up, `is_on_floor()` true, `get_platform_velocity()` =
the collider's velocity: (−33, −143), (−228, 183), (−102, 88); wall contacts (−261, 147)), never a `DefenseTurret`.

### Round-3 findings: status
- **R3-1 — resolved.** Every lit replay caps the steps at 16 (§2 :75-82), the helper returns `max_idle` and the row asserts ≤ 16/60 + 2·TICK before any edge (§3 :148); measured
  0.283 s at most, so the guard reads ≈ 0.6 s as stated. The (D) and the README rule-1 note are in place.
- **R3-2 — resolved in the text** (10 consecutive green runs at steps 4 and 6; the 24 px floor read from `LaserRay._HAZARD_PAD`; clearance printed). The floor earns its keep: the
  FLOATING row above survives 12 / 12 yet fails it twice. See R4-1 for what the measurements behind §5a left out.
- **R3-3 — resolved as an owner decision (Q2).** The restated cost (≈ 6.5-7.5 s) matches what I measured; the accounting of the probe's move and the 9.0 s / 237 s stop are stated.
- **R3-4, R3-5, R3-6 — resolved** (lever 2 first with the reason; `d = max(own, d_L)` for every ray; the from-0 run lasts to max(heavy gone, 14.83 s), and every exit I measured is past 14.83 s).

### New findings

**R4-1. Blocking — option A, the recommended answer to Q1, keeps the deep_space heavy alive by keeping it out of the fight.** In 37 of 37 runs (25 at margin 90, 12 at 110) the
heavy never fires a battery: it stays in APPROACH for its whole budget, above the view (y −40 … −210 while the view starts at y 220), and enters DISENGAGE at ≈ 12.6 s. Why: with the
hull term a column's footprint is 144 px plus the skirt on each side, so the 512 px lane between the 6.0 s row's 640 and 1152 columns (registered 6.0-13.56 s, the heavy's whole
budget) is a channel ≈ 784-1008 px wide at rest; its APPROACH point (`target + away · held_range()`, `heavy_gunship_brain.gd:505`) is ≈ (765, 209), inside the 640 footprint, and BROADSIDE
starts only within `range_tolerance` 100 of 420 px (:496), which the heavy never reaches; the near-tie between the up and down slots then goes to the previous heading
(`CONTEXT_PREV_BLEND`), so it climbs. This fails the plan's own `test_every_placed_heavy_fires_a_battery_inside_its_budget` (§3 :159) and §5's rule that a lever is legal only
while every attack-in-budget row stays green (:184), and it contradicts the task's "really fight". §5a's table (:198-208) has no fire column, so Q1 (:362) is asked on evidence that
cannot show this; option B's description (:237) omits it too (5 / 12 without a FIRE in my runs). Built as written, option A ends in the same ESCALATE the round was meant to avoid,
after steps 3a-4. **Required:** re-measure every Q1 candidate with "battery FIRE inside the budget" (and "entered the view") as columns, and drop option A or state it as failing.
Also make the no-death row's non-vacuity self-contained (:133-134): "not killed, left after DISENGAGE" is satisfied by a heavy that never entered the view; require that it reached
BROADSIDE (or fired) too.

**R4-2. Blocking — a plainly simpler fix is missing from Q1: `collision_mask = 0` on the heavy root.** It is the approved rule of the other Phase 10 heavy (epic plan :449,
"mask 0 (ploughs through, the station's rule)"; `carrier.tscn:86-87`; `space_station.tscn:65`) and the measurement worker the plan used already had the switch (`nomask`). With lever 2
it survives 30 / 30, fires 30 / 30 with 3.33-3.35 s of budget left, keeps 34.5-66.4 px of lethal clearance (all above the 24 px floor) and leaves by 16.2 s, before the 14.0 s row's
896 column is lethal (17.56 s). It is one property in one scene: no `ShipConfig` field, no `EnemyMover` / `Steering` change, no `HAZARD_PROFILES` edit, nothing for any other enemy.
The trade-offs to put in front of the owner: a departure from §2.4.1's "mask ENVIRONMENT" (D); the heavy's body no longer stops on other ships, asteroids or wrecks (wrecks are layer
1 / mask 0, `wreck_large.tscn:13-15`), while it still steers round wrecks and lasers through `Hazards` and its contact damage is the `ContactHitBox` area, unchanged; other ships
(mask 1) still bump into it. Its build needs only: a failing row in `test_heavy_gunship.gd` (the root's mask is 0 and its `move_and_slide()` passes through a layer-1 body), lever 2,
and the lit rows. With mask 0 the heavy has no body contacts at all, so `motion_mode` is moot for this bug; FLOATING stays a reasonable project-wide follow-up (Out of scope :311).
The measurements also suggest §5a's "second cause" (the 52 px segment footprint) is mostly the same body contacts: without them the shipped footprint keeps ≥ 34.5 px.

**R4-3. Blocking (small) — §5a names the wrong body.** The plan says the heavy lands on a deep_space turret-group member (:211-214). A `DefenseTurret` moves only by `AssaultDrift`,
`(0, speed)` (`assault_drift.gd:27-34`), so it cannot hand over (−251, 152); that is a Fighter's velocity. Every floor contact in my traces was a Sniper or a Fighter. The mechanism is
right (GROUNDED, a floor-angle contact sets the platform, `platform_on_leave` adds its velocity on leaving; a FLOATING body never takes a platform from a `CharacterBody2D`, which
is why FLOATING removes the 6.7-7.6 s wall deaths), but the text goes to DECISIONS and to the owner as the reason for a scene change: correct it, and the (−251, 152) attribution.

**R4-4. Minor — option C is not buildable as written.** "Re-point §3's deep_space rows as §5a says" (:265-266) leaves open: `test_heavy_gunship.gd:1010-1012` asserts exactly one
deep_space heavy and goes red; the spill-over boundary (`engage_seconds` 20 flags the deep_space heavy, :106-107) and the deep_space count boundary lose their subject; the pin's
relation to `_LEGACY_ROWS` (4 rows vs 3); which run now carries the wall's end edge and the 6.0 s row's edges (the boundary run reaches 3.56 / 7.56 / 9.56; the carried-over run 11.76 /
13.56); and the lit acceptance criterion becomes vacuous (no heavy meets a laser), which the owner should be told. If C stays an option, list its rows. Option D has no build at all
(what the lit rows assert once deaths are accepted): drop it or specify it.

**R4-5. Minor — Q2's alternative needs its replacement named.** "Drop the Cloud Descent in-traffic attack replay … its three heavies' attack-in-budget would then rest on
hand-ticked rows only" (:364-365): no such rows exist for the cloud spawns (the one hand-ticked row, `test_heavy_gunship.gd:1010`, is deep_space's). Name them (the :1010 shape per
cloud spawn) so that answer is buildable too. The measured cloud figures above (fires at 4.3-4.8 s of budget left, 3.25 s real) support keeping the replay.

Re-checked and fine: option A's code claims as such (opt-in, default 0 bit-identical: `context_avoid` gains a trailing default argument, its three callers are
`enemy_mover.gd:297`, `test_context_avoidance.gd`, `test_enemy_mines.gd:699`; `margin` really does not widen the span), but see R4-1 for its outcome; the cloud run's
attack-in-budget premise (measured above); the step cap's idle bound; the lit-run stop and cost; `HazardInfo` lives in `global/hazards/`, not `global/components/`.

### Verdict
**CHANGES_REQUESTED.** Revision 4 resolves round 3 (R3-1 to R3-6), and the cloud half of the plan, the deadline rows, the helper and the timing rows are ready to build. What is not
ready is the answer the plan recommends to Q1: measured with the column §5a left out, option A stops the deep_space heavy from ever fighting (0 of 37 runs fire), which fails the
plan's own attack-in-budget row and the task's premise, and the cause it rests on names the wrong body. A one-property alternative the plan's own worker could measure, the Carrier's
mask 0 with lever 2, survives and fires in 30 of 30 runs with clearance above the floor. Revise §5a / Q1 with fire and in-view columns, offer mask 0 (recommended on these figures),
correct the cause, and list option C's rows (R4-1 to R4-4; R4-5 is a sentence). After that, the only things between this plan and implementation are the owner's answers to Q1 and
Q2, and the next round need check only those points.

## Round 5

Checked only the revision-5 changes the coordinator listed: the header (:11-14), §1's deep_space bullet (:29-30), §3's no-death row (:140-145), §5's closing paragraph (:198-200),
§5a (:202-275), build steps 3a / 4 / 6 (:299-309), the Test plan's option M / C sentences (:319-322), Risks (:325-348), Out of scope (:356-360), the round-4 response (:409-419)
and the owner questions (:421-426). Against the code: `level_1_director.gd:310-370` (deep_space's list order), `wave_manager.gd:56-67` (waves trigger strictly in list order) and
:125-144 (an empty wave triggers cleanly), `test_level1_fighter_fire_density.gd:325-372`, `test_level1_drone_spawns.gd:58-60`, `test_level1_specialist_spawns.gd:1018-1019`,
`carrier.tscn:85-87`, `space_station.tscn:63-65` (root layer 0 / mask 0), and the files §5a lists for option M. No new measurement was needed: the coordinator's 6 extra mask-0 runs
fit mine (33.1 px is inside the scatter I saw), and the table reproduces my figures correctly.

### Round-4 findings: status
- **R4-1 — resolved.** Option A is withdrawn with the fire column and the reason (§5a :216-217, :229-234). The no-death row now has a self-contained non-vacuity clause
  ("entered the view and reached BROADSIDE or fired a battery before DISENGAGE", :141-142), and step 4 stops on any run without a FIRE (:304).
- **R4-2 — resolved.** Option M is specified completely: the one property, lever 2, levers 1 / 3 / 4 not used (:236-240), the trade-offs (:241-245), its failing rows
  (the scene's mask is 0; on real physics a mask-0 heavy passes a layer-1 box while a mask-1 control is stopped, so the row can fail; :246-248, :299-300) and the files to keep
  green (:248-251). Its stop rule (any death, sub-floor clearance or run without a FIRE in the 10 runs → ESCALATE, :198-200, :303-305) is right. Nit, no change needed: the list
  called "every file that names the heavy" (:248, :330) omits `test_explosion_effect_placement.gd`, `test_ph10_sprites.gd` and `test_entity_sprite_transparency.gd`. None of them
  reads the body mask, and step 9 runs the whole gate.
- **R4-3 — resolved.** §5a :220-227 names Snipers and Fighters, keeps the mechanism, and withdraws the turret / (−251, 152) attribution. DECISIONS will carry the corrected text (:416).
- **R4-4 — mostly resolved; see R5-1 and R5-2.** Option C's rows are now listed (:254-272) and the vacuous lit criterion is stated. Option D is dropped (:274-275).
  Two of C's rows are not right as written.
- **R4-5 — resolved in substance; see R5-3.** The replacing hand-ticked rows are named (:339-343).

### New findings

**R5-1. Blocking for option C — removing the 3.5 s wave moves two other waves, and the plan says it moves none.** §1 :30 and §5a :257-258: "the 3.5 s wave … is removed. Every
other wave's effective trigger is unchanged: the existing specialist / fighter / drone pins and the fire-density wave-order schedule row must stay green unedited". In
`_build_section_1()` the 3.5 s wave is listed **before** the 2.0 s V5 and the 3.0 s wave, the drone trio plus the `assault_pair` turret group (`level_1_director.gd:345-370`).
`WaveManager._process` triggers strictly in list order (`wave_manager.gd:56-67`), so today both of those waves trigger at 3.5 s: that is the Ph3 wave-order quirk, and Ph8's turret
group "spawns at 3.0 s (3.5 s in game)". Remove the wave and they trigger at 2.0 s and 3.0 s, and every later deep_space wave index shifts by one.
`test_level1_fighter_fire_density.gd:365-372` asserts outright that "deep_space's 2.0 s V5 triggers behind the 3.5 s wave in the shipped game" (3.5 ± tolerance), so it goes red
on every run. Every gate that reads effective triggers (the density peaks, the Ph8 group's column timing) is computed on the 3.5 s figure. Built as written, option C fails at step
3a with an instruction ("green unedited") it cannot meet. **Fix:** option C keeps the wave in place with no entries, `b.wave(3.5, [])`, with a comment saying it is kept for
list order. An empty wave triggers cleanly (`wave_manager.gd:125-144`), `placed()` / `spawn_count()` / `slice_waves()` handle it, and nothing else moves. Say so in §1 :30,
§5a :257 and step 3a :301. The boundary run can then append its two held heavies to the slice's copy of that wave, as under option M, instead of a one-wave list of its own (:268-269).

**R5-2. Minor (option C) — the boundary run does not reach the 6.0 s row's scheduled onset as a checked edge.** §5a :269-270 says the boundary run checks "the 6.0 s row's onset
(9.56)". That run stops when both held heavies have a covered death (§3 :136-137), and the x 1152 heavy dies when that column turns lethal, at ≈ 9.6-9.9 s. Under §3 :156's
rule an edge is checked only if expected + 1.25 s (10.81 s) precedes the stop, so the edge is never checked, and the "asserted among the checked edges" assertion goes red. The
carried-over run checks only the relit onset (11.76), not a cold-start column onset, which is the N4 bug's case. **Fix (option C only):** the boundary run stops at max(both covered
deaths, 9.56 + 1.25 + TICK). That is ≈ +1 game s, ≈ +0.1 s real. Under option M the from-0 run already checks both edges, so nothing changes there.

**R5-3. Minor — one owner answer has no stop line.** Q2's alternative (:339-343, :425-426) leaves the task at ≈ 4.8-5.3 s. That is still over §2.15's 4.5 s line, the only
stop that applies when the owner does not accept the overrun, so built as written the run ends in ESCALATE at step 7. State the stop for that answer as well (for example the same
"own files over 9.0 s or suite mean past 237 s", or a tighter one), and say it is still a logged (D).

Re-checked and fine: option M's pin / lever-2 offset handling (:97-100); the clearance floor and its margin (33.1 px against 24, :326-328); Out of scope (FLOATING project-wide
is the owner's follow-up); option C's count boundary (two inserted heavies against the frozen deep_space 1); its spill-over boundary (an inserted heavy at 3.5 s with
`engage_seconds` 20 ends at 3.5 + 20 + 10.08 = 33.58 > 30.0, flagged); the re-pointed `test_heavy_gunship.gd` row; the cost under C (≈ 3.8-4.1 s, so Q2 does not arise).

### Verdict
**CHANGES_REQUESTED.** R4-1 to R4-3 and R4-5 are resolved. For the recommended answers (Q1 = option M, Q2 = accept the overrun) the plan is correct and buildable as written.
Option C is not: removing the 3.5 s wave breaks the wave-order quirk that `test_level1_fighter_fire_density.gd:365-372` pins, against the plan's own "green unedited" (R5-1).
Q2's alternative also has no stop line (R5-3). The fixes are three sentences: keep `b.wave(3.5, [])` under C; extend C's boundary-run stop to 10.83 s; name the stop for Q2's
alternative. With those in, every owner answer is buildable as written, the owner's answers to Q1 and Q2 are the only open items, and the next check need only confirm those three
sentences.

## Round 6

Checked only the three round-5 fixes and their echoes: the header (:14-15), §1's option C bullet (:31), §5a's option C "Director" row (:258-262) and "Replays" row (:271-276),
step 3a's option C sentence (:306-307), the gate-time Risks bullet (:344-349), Q2 (:430-432) and "Response to review round 5" (:434-440). Against the code: `wave_builder.gd:272-282`
(`wave()` accepts an empty list), `wave_manager.gd:56-67, 84-93, 125-144` (an empty wave registers, triggers in list order and spawns nothing), `level1_slice_replay.gd`
`slice_waves()` (copies entries into a fresh array, so appending to the empty wave's copy writes nothing shipped), `test_level1_fighter_fire_density.gd:365-372`.

### Round-5 findings: status
- **R5-1 — resolved.** Under C the heavy entry goes and the wave stays as `b.wave(3.5, [])`, with the reason (§1 :31, §5a :258-262, step 3a :306-307). The wave
  still gates the 2.0 s and 3.0 s waves, every later wave index is unchanged, and the V5 row at `test_level1_fighter_fire_density.gd:372` keeps reading 3.5 s. Nothing else iterates
  waves in a way an empty one breaks: the `entries.size() > 1` asserts in `test_level1_specialist_spawns.gd` look only at waves holding their own lines.
- **R5-2 — resolved.** Under C the boundary run appends its two held heavies to the empty wave's slice copy (the §3 technique) and stops at max(both covered deaths, 10.83 s), cap 14.06
  (§5a :271-276). So the wall's onset and end and the 6.0 s row's cold onset are checked edges there, and the carried-over run keeps the relit onset and the real end.
  Nit, no change needed: Risks' mitigation line (:350) still says the boundary run "stops on its two covered deaths"; §5a's explicit option C rule governs.
- **R5-3 — resolved.** Q2's alternative is a logged (D) with its own stop, the task's files over 6.0 s or the two-run suite mean past 237 s (Risks :348-349, Q2 :431-432).
  Its ≈ 4.8-5.3 s estimate sits under that stop, so the answer is buildable.

No new findings.

### Verdict
**APPROVED.** For every answer the owner can give, the plan is correct and buildable as written:
- **Q1 = M:** option M with lever 2 and the root's `collision_mask` 0.
- **Q1 = C:** option C with the empty 3.5 s wave.
- **Q2:** accept the overrun with the stop at 9.0 s / 237 s, or the hand-ticked alternative with the stop at 6.0 s / 237 s (Q2 arises only under M).

The only open items are the owner's answers to Q1 and Q2. Step 3a starts only after the Q1 answer, and step 4's 10-consecutive-runs rule with its ESCALATE stop stays in force under M.
