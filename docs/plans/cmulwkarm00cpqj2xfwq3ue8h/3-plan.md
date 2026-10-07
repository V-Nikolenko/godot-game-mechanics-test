# Level 1 deep_space / planet_approach: fighters and the Gatling pair off rails (t16), owner option A

Epic plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.9.1–2.9.2 (Revision 2, approved). This plan changes
**only** the shots/s density gate, as the owner decided on 2026-10-06 ("Apply option A" in `5-escalation.md`).
Everything else follows §2.9.2 as approved.

## Problem
In level 1's first two DURATION sections, every fighter flies a fixed rail and fires on a timer, and the two
interceptors fly through on a player-focus line. After this task, they arrive at the same moments and places as
before, then fight as squads inside the Assault corridor (fighters: pincer plus frontal pass; the Gatling pair:
convergence windows) and leave by themselves when their engagement budget runs out. The level must not become much
busier or noisier than before.

## Design

### 1. Level edit (done in the working tree, from `prototype/level1_duration_rails_off.patch`)
`assault/scenes/levels/edelia/1/level_1_director.gd`, `_build_section_1()` (deep_space) and `_build_section_2()`
(planet_approach) only:
- every `b.fighter()` line loses `.move()`, `.free_after()` and `shoot_*()`, and keeps `.at()`, `.formation()` and
  `.delay()`;
- the deep_space pair becomes `b.gatling_interceptor().at(±200, -420)[.delay(0.4)].squad(&"w0g")`;
- loose fighter lines that share a wave with another loose fighter line get `.squad(&"w<n>f")`, where `n` is the wave's
  index in `raw_waves` (the Ph2 convention). A lone loose fighter stays untagged: `WaveManager` keys it as a squad of
  one either way, exactly as the Ph2 lone drones;
- wave comments that describe a rail ("straight down", "U-sweep right") are updated to say where the ships arrive.

cloud_descent (t17) is not touched.

### 2. The pin (`tests/integration/test_level1_fighter_spawns.gd`), updated in place
- The 37 deep_space / planet_approach rows: `aim_mode` → `""`, `free_after` → `0.0`, `movement` → `false`. Section,
  trigger, offset, delay, formation and count unchanged. cloud_descent's 27 rows unchanged.
- `test_legacy_peak_fighters_and_shots_per_s_match_frozen_constants` only checks sections whose rails still exist
  (`_RAIL_SECTIONS := [&"cloud_descent"]`), with a comment naming t16. The frozen constants are **not** edited.
- New: `test_migrated_sections_have_no_rail_left` — every fighter / Gatling entry in deep_space and planet_approach has
  `movement == null`, no `FREE_ON_DURATION` exit and no `aim_mode` prop.
- New: `test_loose_pairs_are_tagged_with_their_wave_index` — every loose fighter (Gatling) line in those sections with
  a loose sibling of the same kind in its wave carries `squad_id == "w<wave index>f"` (`"...g"`).
- New boundary: `test_a_fighter_line_given_move_again_fails_the_pin` — on a fresh `_build_sections()`, set `movement`
  on one deep_space fighter entry; the pin must not match.

### 3. Structural density gates, analytic (unchanged from §2.9.2)
In the same file, per migrated section, dividing by the **frozen** `_LEGACY_PEAK_FIGHTERS`:
- all-alive peak ≤ 2.0×;
- attack-capable peak (first 3 per fighter squad by spawn order, first 2 per Gatling squad) ≤ 1.5×.

Lifetimes come from the shipped configs (`fighter_config.tres`, `gatling_interceptor_config.tres`), never typed:
- fighter: `engage_seconds + burst_telegraph + max(aimed_max × aimed_gap, forward_max × forward_gap)` + the
  Razor-shaped worst exit (`(max_speed + exit_speed) / min(acceleration, braking) + (exit_distance + max_speed² /
  (2 × braking)) / exit_speed`, `exit_distance` = half the short side of the live `projectile_world_rect()`), as §2.9.3;
- Gatling: `engage_seconds + spin_up_seconds + sync_wait_max + stream_rounds_max × stream_interval` + the same exit.

Squads are keyed like `WaveManager._trigger_wave()`. That logic is added to `tests/helpers/level1_drone_concurrency.gd`
as `shooter_squad_intervals(section, kinds)`, where `kinds` maps a scene path to `{life, capable_per_squad, rate}`.
Each interval is `{start, end, capable, squad, rate}` (rate 0 when not capable), so the existing `peak_intervals()` and
`peak_interval_rate()` compute the peaks. The plan's **analytic** shots/s figure (fighter `max over modes of n_max /
(gap × n_max + min_burst_period)`, Gatling `stream_rounds_max / min_window_period()` read from the brain) is
**printed, not asserted** (option A). Expected from the escalation: all-alive 17 / 16 ≤ 20, capable 13 / 14 ≤ 15.

### 4. Shots/s density gate, measured (owner option A)
New file `tests/integration/test_level1_fighter_fire_density.gd`, the `test_level1_drone_exit.gd` shape:
- A real `WaveManager` fed **only the fighter and Gatling entries** of the section's waves, at their own trigger times.
  That is the same population the frozen constant counts. A real `ArenaCamera` (corridor and world rect), and a
  stationary, hurtbox-less player stub at the lower centre of the view.
- A shot is an `EnemyBullet` entering the enemy container (`child_entered_tree`). `BulletPool.acquire()` reparents
  every fired round there, so each fired round is counted exactly once. Its time is summed physics delta (game time).
- The run lasts until every expected ship has spawned and none is left, capped at last spawn + the analytic lifetime
  (§3) + 5 s.
- **Gate:** the peak shots in any 2 s window (windows anchored at each shot), ÷ 2, must be ≤ 1.25 ×
  `_LEGACY_PEAK_SHOTS_PER_S[section]`. The value is printed. The 2 s window is the one the escalation validated: on
  the old rails it measured 31.0 / 35.0 shots/s against the frozen 31.25 / 33.33. The constants are read from
  `test_level1_fighter_spawns.gd` (preloaded script constant), never copied.
- Sanity assertions: every expected ship spawned; at least one shot was fired, so a silent build cannot pass trivially;
  every ship left within the cap, with no `EnemyPathMover`.
- The window arithmetic is a pure static `peak_window_rate(times, window)` in the concurrency helper. A boundary test
  feeds it synthetic timestamps: 80 shots inside 2 s gives 40.0/s and is rejected against deep_space's 39.06 limit;
  the same 80 shots spread over 4 s give 20.0/s and pass. A second boundary checks that an empty list gives 0.
- **Time acceleration:** `Engine.time_scale = 4` and `Engine.physics_ticks_per_second × 4` for the run, so the physics
  step stays 1/60 game-second. That is the same simulation step as normal play at a quarter of the wall time (prototype:
  42 s of game time in 10.5 s). Both are restored in `after_each` as well as at the end of the run, so a failing run
  cannot leak a 4× clock into the rest of the suite. Expected cost ≈ 10 s + 30 s of wall time.

### 5. Levers
If a gate fails, only the pre-approved levers may be used (engage 6.0 → 4.5, a new `assault_passes` 2 → 1, split a 5+
formation). Expected: none needed (measured 11–14 / 6.5 shots/s against 39.06 / 41.67).

### 6. Records
Append "Phase 3, t16 — as built" to `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`: option A, the measured and
analytic figures, no lever used, and that t17 should reuse the measured gate for cloud_descent (legacy 15.0).

### Rejected
- Options B–E (see `5-escalation.md`): the owner chose A.
- Running the whole level through `Level1Director`: it brings every other enemy into the run, which the legacy
  constant does not count.
- Wall-clock runs at 1×: about 160 s added to the gate, for the same step size.

## Build sequence
1. Tests first: pin row update, the three new pin tests, the analytic gates, and the measured gate file. Run them
   against the edited level (the pin's new rows go red on HEAD's level and green on the edit).
2. Concurrency helper additions (`shooter_squad_intervals`, `peak_window_rate`).
3. Level comment touch-ups.
4. `bash /agent/verify.sh`, then `scripts/check-test-leaks.sh` (the new file awaits and uses timers).
5. DECISIONS, STATUS, and progress.

## Test plan
- `test_level1_fighter_spawns.gd`: the updated pin; `test_the_pin_itself_is_internally_consistent` (unchanged counts);
  the legacy-equality check for cloud_descent only; `test_migrated_sections_have_no_rail_left`;
  `test_loose_pairs_are_tagged_with_their_wave_index`; `test_a_fighter_line_given_move_again_fails_the_pin`
  (boundary); `test_migrated_sections_all_alive_peak_within_2x` and `test_migrated_sections_attack_capable_peak_within_1_5x`
  (printing the values and the analytic shots/s).
- `test_level1_fighter_fire_density.gd`: `test_deep_space_measured_shots_per_s_within_1_25x`,
  `test_planet_approach_measured_shots_per_s_within_1_25x`, `test_peak_window_rate_rejects_a_dense_burst` (boundary),
  `test_peak_window_rate_of_no_shots_is_zero`.

## Risks
- **Behaviour-dependent gate.** One scenario (stationary player); the brains' RNG is not seeded per run, and repeated
  prototype runs gave 11–14 shots/s. The margin to the limit is about 3×, so noise cannot flip it. A moving player is
  not measured (stated in DECISIONS as a known gap).
- **Time scaling.** `_process`-driven code (`WaveManager`, idle timers) sees up to 4× larger idle deltas. Triggers can
  land up to a few physics steps late, which is negligible against a 2 s window. The physics step itself is unchanged.
- **Gate time** grows by ≈ 40 s.

## Out of scope
cloud_descent (t17); docs, roster and dossier (t18); any lever not listed; a moving-player scenario.

---

## Revision 2 (answers review round 1, `4-review.md`)

Where this section and the text above disagree, this section wins.

- **B1. Scratch file.** `tests/scratch/` has been deleted (done before this revision). Build step 4 is preceded by
  a `git status` check confirming that no untracked test file is left.
- **B2. Seeded run.** The container's `child_entered_tree(node: Node)` handler sets
  `node.get_node("Brain").rng_seed = _SEED_BASE + spawn_index` on every `BaseEnemy` that enters. This happens before
  `_ready()`, so `EnemyBrain._ready()` seeds `rng` from it. The fighter's patterns share that `rng` (`fighter.gd:70/78`).
  The run is then **one seeded scenario**, as option A says. Physics ordering may still give small run-to-run
  differences, and the Risks paragraph now says exactly that instead of "unseeded".
- **B3. Superseded boundary, and a count-gate boundary.**
  - Epic §4's "a 3rd Gatling added to deep_space's pair pushes shots/s over (verified once by hand)" was written for
    the analytic shots/s figure that option A removed. A third Gatling cannot move the measured value (≈ 12) past
    39.06. It is **superseded**. Its job, proving that the shots/s gate can reject, moves to
    `test_peak_window_rate_rejects_a_dense_burst`. This is recorded in DECISIONS.
  - New pure-data boundary `test_extra_formations_at_the_peak_break_the_count_gates`, in
    `test_level1_fighter_spawns.gd`. On a fresh `_build_sections()`, find planet_approach's analytic capable-peak
    moment `t*` from the computed intervals. Add a wave at `t*` holding one `v_formation(3)` fighter entry and
    recompute. Assert that the capable peak is now **> 1.5 ×** the frozen constant: 14 + 3 = 17 > 15, with the
    computed value asserted. Add two more `v_formation(5)` entries and assert that the all-alive peak is > 2.0 ×.
- **B4. Wave order.** The measured run keeps **every** wave of the section, in its `raw_waves` order, with only the
  non-fighter / non-Gatling entries filtered out. An empty wave triggers harmlessly. The run then reproduces the
  shipped trigger timing, including deep_space's out-of-order 2.0 s V5, which really triggers at 3.5 s behind the 3.5 s
  gunship wave. The run records the game time of each `wave_triggered(wave_index: int)` and asserts it is within 0.1 s
  of `max(trigger, previous wave's actual trigger)`, which shows that the 4× run follows the real schedule. The quirk
  itself predates this task: triggers are pinned. It is recorded in DECISIONS and listed as a follow-up, not fixed.
- **N1.** `Engine.max_physics_steps_per_frame` is scaled ×4 as well. All three originals are captured before the run
  and restored from the captured values: at the end of the run and in `after_each`.
- **N2.** `level1_drone_concurrency.gd` gains `static func squad_key(wave_index, entry_index, entry) -> String`, used
  by both `squad_intervals()` and the new `shooter_squad_intervals()`, and `static func worst_exit_after_speed(speed,
  exit_speed, acceleration, braking, exit_distance) -> float` (the Razor-shaped exit), which `_razor_deadline()` in
  `test_engagement_deadline.gd` now calls. Its behaviour is unchanged, and t17 reuses it.
- **N3.** Print both capable models (first-N by spawn order, and per-squad `min(alive, cap)`). Assert the first-N
  model, as the epic does.
- **N4.** deep_space asserts that both Fighter rounds and Gatling rounds were counted (> 0 each). Rounds are told
  apart by scene: on `enemy_spawned`, every `BulletPool` child of the ship maps its `bullet_scene.resource_path` to the
  ship's kind, and a counted shot looks up its own `scene_file_path` in that map. Every ship must leave in DISENGAGE
  (its brain's `phase` equals that brain class's `Phase.DISENGAGE` at `tree_exiting`), with no `EnemyPathMover`.
- **N5.** Handlers match the signal arity (`child_entered_tree(node)`, `enemy_spawned(enemy, wave_index)`,
  `wave_triggered(wave_index)`). The `_recording` flag pattern guards late callbacks. Every expected ship must have
  spawned before a test returns. `scripts/check-test-leaks.sh` is run.
- **N6.** The DECISIONS entry names `test_level1_fighter_fire_density.gd` for t18's CLAUDE.md paragraph. The pin
  file's header and `EXPECTED` comment say that the deep_space / planet_approach rows are AI rows now.
- **N7.** Lone loose lines stay untagged on purpose (a squad of one either way, the Ph2 convention). Noted in DECISIONS.
- **N9.** Deviation from epic §2.9.2: the measured gate lives in its own file, because it has the real-run shape. It
  reads `_LEGACY_PEAK_SHOTS_PER_S` through the pin script's preloaded constant.

Updated test plan additions: `test_extra_formations_at_the_peak_break_the_count_gates` (boundary, pin file);
the measured tests also assert the trigger schedule, the DISENGAGE exits and the per-kind shot counts.
