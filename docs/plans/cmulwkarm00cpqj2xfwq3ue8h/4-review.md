VERDICT: CHANGES_REQUESTED

Independent review of `3-plan.md` (t16, owner option A), 2026-10-06. I treated option A as final and did not
reopen it. I checked the plan against the code, not just against its own claims. Its design is sound: the pin update,
retiring the legacy-equality check for these two sections only, analytic count gates that divide by the frozen
constants, and a measured real-`WaveManager` shots/s gate. I verified that the level patch in the working tree matches
the plan. Four things must change before implementation: one leftover file would break the gate, one part of the
owner's decision was dropped, one epic test requirement disappeared without a note, and one part of the measurement
does not match the real game. All four are cheap to fix.

## Blocking

### B1. The untracked `tests/scratch/` must be deleted, and the plan does not say so
- Checked: `git status` shows `?? tests/scratch/`, which contains `tests/scratch/test_scratch_measured.gd`
  (`extends GutTest`, three `test_*` functions).
- The gate runs `-gdir=res://tests -ginclude_subdirs`, so it picks this file up. It runs about 3 × 42 s of game time
  at 1×, 4× and **8×**. It also sets `Engine.time_scale` and `Engine.physics_ticks_per_second` with no `after_each`
  restore. If any of its runs breaks off early, the scaled clock leaks into the rest of the suite.
  `test_station_laser_phase.gd:272-275` reads `Engine.physics_ticks_per_second`, so it is exposed to that leak.
- The suite-integrity sweep would also pick the file up, and in an AI-Kanban run the harness commits whatever is left.
- **Required:** add "delete `tests/scratch/`" to the build sequence, before step 4 (the gate run).

### B2. Option A as approved says "one seeded scenario"; the plan runs unseeded, although a seed hook already exists
- Checked: `5-escalation.md:57`, option A row, cost column: "Behaviour-dependent: **one seeded scenario**".
- `3-plan.md:115` says instead: "the brains' RNG is not seeded per run".
- `global/enemy_ai/enemy_brain.gd:41-59` already provides `@export var rng_seed`: a non-zero value seeds `rng` in
  `_ready()`. The fighter's burst counts (`fighter_brain.gd:1339/1343`), the Gatling's stream length, aim error and
  reposition time (`gatling_interceptor_brain.gd:200-211`), and both patterns' `rng` (`fighter.gd:70/78`,
  `gatling_interceptor.gd:67`) all draw from it.
- The plan already listens to the container's `child_entered_tree`. That signal fires before `_ready()`, so the same
  handler can set `ship.get_node("Brain").rng_seed` from the spawn index. That makes a red run reproducible, which an
  unseeded behaviour-dependent gate is not, and it matches what the owner approved.
- **Required:** seed every brain deterministically through the existing `rng_seed`, and change the Risks paragraph
  to match. A stationary-player run then reads as "one seeded scenario". Physics may still introduce small variation,
  and the plan can say so.

### B3. One epic test requirement disappears without a note, and the new count gates have no boundary case
- Checked: epic `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md:776` (§4 row for this file): "**A 3rd Gatling
  added to deep_space's pair pushes shots/s over (verified once by hand)**".
  - Under option A that cannot hold: the measured deep_space value is about 12 against a limit of 39.06.
  - `3-plan.md` never mentions it, neither under "Rejected" nor under "Out of scope" (lines 90-123). That is a
    dropped requirement with no reason given.
- Separately, the two analytic gates the plan does assert (all-alive ≤ 2.0×, capable ≤ 1.5×; `3-plan.md:42-44`) have
  no boundary test in the Test plan (lines 105-112). Nothing shows they can fail.
  - The pin has a boundary (line 38), and the window arithmetic has one (line 74). The count gates have none.
  - planet_approach's capable peak is expected at 14 against a limit of 15. The gate can clearly fail, and one test
    should prove that.
- **Required:**
  1. List the 3rd-Gatling boundary as superseded by option A, with the reason (the measured gate replaced the
     analytic shots/s figure it was written for), and name its replacement: the synthetic `peak_window_rate` boundary.
  2. Add a pure-data boundary for the count gates. On a fresh `_build_sections()`, add one extra 3-fighter formation
     (or a second Gatling pair) inside planet_approach's peak window. Assert that the attack-capable peak then exceeds
     `1.5 × _LEGACY_PEAK_FIGHTERS`, and assert the computed value, as the Ph2 boundaries do. This costs milliseconds.

### B4. The measured run must keep the section's wave order, or it does not match the real game for deep_space's V5
- Checked: `level_1_director.gd`. In `_build_section_1()`, the `b.wave(3.5, …)` gunship wave at about line 302 comes
  before the `b.wave(2.0, …)` V5-fighter wave at about line 307 in `raw_waves`. This is the only out-of-order pair in
  any section.
- `wave_manager.gd` `_process()` triggers waves strictly in index order (`else: break`). In the shipped game the
  "2.0 s" V5 therefore triggers at **3.5 s**, the same tick as the gunship wave.
- `3-plan.md:61` feeds the `WaveManager` "only the fighter and Gatling entries … at their own trigger times". The
  prototype it is based on (`prototype/scratch_sim.gd.txt`, `if not es.is_empty(): waves.append(nw)`) **drops waves
  with no such entries**. The 3.5 s wave has no fighters, so it is dropped, and the V5 then fires at 2.0 s. The
  measured run would then differ from the level it claims to measure.
  - The V5 sits in deep_space's ≈ 8 s peak, so the 1.5 s shift is not irrelevant. With a 3× margin it will not flip
    the gate, but the plan says it measures the real level, so this should be fixed.
- **Required:** keep every wave of the section, in order, with its non-fighter entries filtered out. An empty
  `WaveResource` triggers harmlessly. The run then reproduces the shipped trigger timing exactly.
  - Dropping waves does not change squad grouping; I checked this. Every `squad_id` is unique within its wave, and a
    formation is keyed by entry. Keeping the waves also keeps the wave indices identical to the level's.
- Not for this task (triggers are pinned and must not change): note the out-of-order wave in DECISIONS, and ideally in
  `docs/discovered-bugs.md`. The analytic count gates, the frozen constants and the Ph2 drone pin all model the V5 at
  2.0 s, while the game spawns it at 3.5 s. For the count gates this is consistent with their denominator, so it is
  fine there.

## Non-blocking (for the implementer)

- **N1. Time acceleration: also scale `Engine.max_physics_steps_per_frame`, and restore the captured originals.**
  `3-plan.md:77-80`.
  - Godot's own documentation for `max_physics_steps_per_frame` says to raise it when `physics_ticks_per_second` is
    raised well above the default. At 240 ticks/s, the default cap of 8 steps per frame slows the simulation whenever
    the headless loop drops below 30 fps. On a slower NAS that can let idle-driven `WaveManager` triggers and spawn
    timers drift away from physics-driven brain lifetimes.
  - The drift would make the measured density *higher* (a possible false red, not a false pass), but it is easy to
    avoid. Scale the cap ×4 as well.
  - Capture all three values (`time_scale`, `physics_ticks_per_second`, `max_physics_steps_per_frame`) before
    changing them, and restore those captured values rather than the literals `1.0` and `60`.
  - Optionally record the physics time at each `wave_triggered` and assert it is within about 0.1 s of the expected
    trigger time. That proves the 4× run is the same schedule.
  - I checked the code the measurement depends on, and none of it reads wall-clock time: brains, `EngagementBudget`
    and `BurstClock` all accumulate physics `delta` (`enemy_brain.gd:8`, `engagement_budget.gd`). The only wall-clock
    users are `level_director.gd` and `dialog_player.gd`, and neither is in this run.
- **N2. Reuse rather than copy the squad keying.** `level1_drone_concurrency.gd::squad_intervals()` (lines 64-100)
  already reproduces `WaveManager._trigger_wave()`'s key. Factor that keying into one private static function that
  both `squad_intervals()` and the new `shooter_squad_intervals()` call, so there is a single copy of it.
  - Likewise, the Razor-shaped worst exit is currently inline in `test_engagement_deadline.gd:91-95`. Put it in the
    helper as a static function taking (speed, exit_speed, acceleration, braking, exit_distance). t17 needs it for
    the fighter and Gatling deadline rows.
- **N3. Attack-capable model.** The plan uses "first 3 by spawn order" (epic wording). `1-context.md` argues that
  `peak_min_alive_three()`'s per-squad `min(alive, cap)` is the more accurate model for fighters, because REARs get
  promoted. The escalation found both give the same peak here. Print both numbers. If they diverge later, nobody
  needs to rediscover this.
- **N4. Strengthen the sanity checks on the measured run.**
  - "At least one shot" (`3-plan.md:72`) does not show that both kinds are counted. In deep_space, assert that shots
    from Fighter rounds (Pulse/Scatter) **and** from Gatling Stream rounds are both above 0. All three round scenes
    inherit `enemy_bullet.tscn` (`class_name EnemyBullet`), so the `is EnemyBullet` filter is correct today; this
    check keeps it honest if that changes.
  - Also assert that every ship leaves in DISENGAGE, as `test_level1_drone_exit.gd` does.
- **N5. Handler arity and leaks.**
  - `child_entered_tree(node)` and `enemy_spawned(enemy, wave_index)` need handlers with exactly 1 and 2 parameters
    (tests/README.md, signal-arity trap).
  - Keep the `_recording` flag pattern from `test_level1_drone_exit.gd`, so late callbacks during teardown write
    nowhere.
  - Waiting until every expected ship has spawned is what keeps `WaveManager`'s delay timers from leaking. Keep it,
    and run `scripts/check-test-leaks.sh` as the plan says.
- **N6. Records for t18.**
  - The epic's t18 CLAUDE.md gate paragraph lists "the fighter pin/density" but does not know about
    `test_level1_fighter_fire_density.gd`, a new intent test with a real-run gate. Have the DECISIONS entry name the
    file explicitly for t18.
  - The pin file's header (lines 5-10) and the `EXPECTED` doc comment (lines 73-79, "falls back to its config
    default, 'PLAYER'") should also say that the deep_space and planet_approach rows are now AI rows.
- **N7. Loose-line tagging.** `3-plan.md:21-22` leaves lone loose fighters untagged, while the task text says "tag
  loose lines". I checked that this behaves identically: `wave_manager.gd:117-118` gives an untagged lone line the
  key `"<w>:<i>"`, which is a squad of one either way. This includes planet_approach's 20.0 s wave, where a lone
  loose line sits next to a V3 formation. It also matches the Ph2 lone-drone convention. Acceptable as written; the
  DECISIONS note can say it was deliberate.
- **N8. Other tests affected by the level edit.** I checked whether anything besides the pin reads these sections'
  fighters. `test_level_1_sequence.gd` has no `Camera2D`, so `WaveManager._spawn_ship()` returns early and nothing
  spawns. The drone pin and the deadline test read drones and cloud_descent only. Only the pin should go red, which
  matches the plan.
- **N9. Measured gate file location.** Epic §2.9.2 put all the density gates in `test_level1_fighter_spawns.gd`. A
  separate file for the real-run gate is the right call, because it has the `test_level1_drone_exit.gd` shape. Reading
  `_LEGACY_PEAK_SHOTS_PER_S` through a preloaded script constant meets "never copied". The plan could state this
  deviation from the epic in a single sentence.

## What I checked and found correct
- The level diff matches `prototype/level1_duration_rails_off.patch`. No `.move()`, `.free_after()` or `shoot_*()`
  is left on a fighter or Gatling line in either section. cloud_descent is untouched.
- Every tag matches its wave's index in `raw_waves`: `w0g`, `w9f`, `w20f`, `w22f`, `w27f` in deep_space; `w11f`,
  `w18f`, `w24f`, `w30f` in planet_approach.
- Pin counts: 18 + 19 = 37 rows edited, cloud_descent's 27 unchanged. The `checked == 3` sanity check at line 414
  must become 1, which the plan's `_RAIL_SECTIONS` implies.
- The analytic lifetimes recompute from the shipped configs as the plan states: fighter 6.0 + 0.8 + 2.84 = 9.64 s,
  Gatling 7.0 + 2.08 + 2.92 = 12.0 s. Every term is read from `fighter_config.tres`, `gatling_interceptor_config.tres`
  and the live `projectile_world_rect()`, never typed.
- Shot counting: `bullet_pool.gd:72` `acquire()` → `reparent(_container)`, which triggers the container's
  `child_entered_tree`. A recycled round goes back under the pool, a grandchild of the container, so it is not counted
  twice. An exhausted pool returns null and fires nothing, so it is correctly not counted.
- Every gate divides by the frozen constants. None is recomputed from deleted rail data, and only the ratios
  (2.0 / 1.5 / 1.25) are literals.

## Round 2

VERDICT: APPROVED

Independent re-review of `3-plan.md` Revision 2, 2026-10-06. Option A was not reopened. I checked each answer against
the code, not against the plan's own text.

| | Status | Checked |
|---|---|---|
| B1 scratch file | **Resolved** | `tests/scratch/` does not exist. `git status` shows only the level edit, STATUS, 3-plan and 4-review. `git ls-files --others` lists no test file. `prototype/` holds only `.patch` and `.gd.txt` files, so neither `-gdir=res://tests` nor `test_project_load_integrity.gd` loads them. Build step 4 is now preceded by a `git status` check (plan:131-132). |
| B2 seeded run | **Resolved** | `enemy_brain.gd:43` `@export var rng_seed`; `:55-59` seeds `rng` in `_ready()` when the value is non-zero. Both subclasses call `super._ready()` first (`fighter_brain.gd:253-254`, `gatling_interceptor_brain.gd:148-149`). The node is named `Brain` in both scenes (`fighter.tscn:119`, `gatling_interceptor.tscn:108`). `wave_manager.gd:199-209`: the ship is instantiated, props and squad are set, then `enemy_container.add_child(entity)` runs directly with no wrapper node. The container's `child_entered_tree` therefore fires during the ship's enter-tree propagation, before any child has entered the tree and before any `_ready()`. A seed set there reaches `EnemyBrain._ready()`. The fighter patterns and the Gatling stream share that `rng` (`fighter.gd:70/78`, `gatling_interceptor.gd:67`). I grepped fighter, Gatling, `global/enemy_ai`, the attack patterns and the pool: none of them draws from the global RNG. `AimedAttackPattern` falls back to the global `randf_range` only when `rng == null`, and both shooters set it. |
| B3 superseded boundary + count-gate boundary | **Resolved** | Plan:138-147. The 3rd-Gatling boundary is listed as superseded, with the reason and its replacement (`test_peak_window_rate_rejects_a_dense_burst`). The new pure-data boundary can really fail the gates: `peak_intervals()` (`level1_drone_concurrency.gd:110-123`) samples at every interval start with `start <= t < end`, so 3 attack-capable ships added at the capable-peak moment raise the capable peak to at least 14 + 3 − (baseline intervals that end during the formation's stagger) > 15. All-alive becomes ≥ 14 + 13 > 20. See I2 for exact-value detail. |
| B4 wave order | **Resolved** | `wave_manager.gd:56-67` triggers strictly in index order (`else: break`), and `_trigger_wave` with an empty `spawns` array does nothing beyond emitting `wave_triggered`, so an empty wave really is harmless. Plan:148-153 keeps every wave in order and asserts each trigger against `max(trigger, previous actual)`. That formula reproduces the real schedule generally, not only for the V5. See I3: the quirk is wider than round 1 said. |

Also checked:
- N4's per-kind shot map works as described. The pools are direct children of the ship (`AimedPool`, `ForwardPool`, `StreamPool`), and their `bullet_scene`s are three distinct files (`pulse_round`, `scatter_round`, `gatling_stream_round`). The prewarmed rounds enter the tree under the pool, a grandchild of the container, so the container's `child_entered_tree` does not count them. Only `acquire()`'s `reparent(_container)` (`bullet_pool.gd:68`) counts a round.
- N2's `worst_exit_after_speed()` is algebraically identical to the inline expression at `test_engagement_deadline.gd:91-94`, with `max_dash_seconds` kept outside it. The deadline test's behaviour does not change.
- The time-acceleration answer (N1) is sound. Capturing and restoring all three engine values in both places closes the leak to `test_station_laser_phase.gd:272-275`.

Nothing in Revision 2 introduces a blocking problem.

### Implementer notes (non-blocking)

- **I1. Seeding details.**
  - `_SEED_BASE` must be non-zero. `rng_seed == 0` means `randomize()`, so `0 + spawn_index 0` would leave the first
    ship unseeded.
  - Connect `child_entered_tree` directly, not `CONNECT_DEFERRED`. A deferred call arrives after `_ready()`.
  - Seed only nodes that are a `BaseEnemy` with a `Brain` child. Use `get_node_or_null`, because `EnemyBullet`s enter
    the same container through the same signal.
  - In Risks, name the remaining non-determinism precisely: `WaveManager` triggers and its delay timers run on idle
    frames, so spawn moments can shift by a frame between runs. That variation comes on top of physics ordering.
- **I2. The B3 boundary's exact values.**
  - `b.v_formation(3)` has a 0.1 s stagger (`wave_builder.gd:162`, `v_formation.gd:21-27`). Only the lead is alive at
    `t*`, so the new peak is sampled at `t* + 0.1`. "17" is then exact only if no baseline capable interval ends in
    that 0.1 s.
    - Fix: pass `stagger = 0.0` to the added formations, or compute the expected value from the intervals rather than
      typing 17.
  - The expected all-alive value is `all_alive(t*) + 13`. It is not `16 + 13`, because `t*` is the *capable*-peak
    moment.
  - The helper has no arg-max, so the test has to compute `t*` (the interval start with the highest capable count).
  - The boundary must build its intervals through the same function and lifetimes as the gate it is proving, not
    through a copy.
- **I3. Two waves are blocked behind deep_space's 3.5 s gunship wave, not one.** The 3.0 s drone-trio wave
  (`level_1_director.gd:314`, `squad(&"w6")`) comes after the 2.0 s V5 wave (`:307`) in `raw_waves`. Both trigger at
  3.5 s in the shipped game.
  - The measured run is unaffected, because that wave has no fighters and the `max()` formula covers it.
  - Record both waves in DECISIONS and in `docs/discovered-bugs.md`. Ph2's drone pin and concurrency figures model w6
    at 3.0 s, so the quirk reaches the drone numbers too.
  - Assert the schedule only for waves that actually triggered during the run, or at least through the last wave
    holding a fighter or Gatling. planet_approach's later non-shooter waves may not trigger before the run ends.
- **I4. `squad_key()` refactor.** `WaveManager._trigger_wave` uses a non-empty `squad_id` even on a formation entry.
  The helper's current key also requires `formation == null`, and it never groups a Razor.
  - No level-1 entry combines `.formation()` with `.squad()`, so the two agree today.
  - Keep the helper's current behaviour, including the Razor exclusion, so the Ph2 numbers cannot move. Note the
    divergence in the function's doc comment.
- **I5.** At the time of this review, the deep_space V5 comment (`level_1_director.gd:306`, "straight down") and the
  5.0 s "U-sweep right" (`:327`) and 20.0 s "dual U-sweeps" (`:410`) comments still describe rails. Build step 3 covers them.
