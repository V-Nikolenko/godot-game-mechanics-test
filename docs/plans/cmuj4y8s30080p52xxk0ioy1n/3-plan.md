# Level 1 drones off rails (epic task t15)

## Problem
Today every Swarm Drone in level 1 flies a scripted `.move()` rail and is culled when it leaves the screen, so the
squad AI built in t8b/t8c never runs in the level. The player should see drones arrive exactly when and where they
did before, then fight as squads inside the Assault corridor, and leave through the nearest edge in time for the
level's ENEMIES_CLEARED wait to move on.

## Design
This implements the approved epic plan §2.10 step 2 / §2.6 / §5 C3 verbatim; nothing is redesigned.

1. **Director** (`level_1_director.gd`): strip `.move(...)` from every `b.drone()` line (119 lines) and the two
   `.free_after(5.0)` on cloud_descent's side drones (only `EnemyPathMover` reads it). `.at()`, `.formation()`,
   `.delay()` unchanged. Done by a one-off balanced-paren script, then reviewed by diff.
2. **Squads:** formations are already one squad (`WaveManager` squad key). In each `b.wave()` whose *loose* drone
   lines number 2–7, append `.squad(&"w<n>")` to each of them, `<n>` = the wave's 0-based index in that section's
   `raw_waves` (any id unique per wave works; the key already contains the wave index). A wave with exactly one loose
   drone leaves it a squad of one.
3. **Station BOTTOM squad:** untouched (on rails; `station_reinforcements.gd` is not edited).
4. **Bonus Drone:** untouched.

Rejected: tagging squads in `WaveManager` automatically by wave (would change every other enemy's semantics and the
t5 contract "no id → squad of one").

## Build sequence
1. Tests first (red): update the t1 pin (`movement: false` for all 121 rows; the drone/razor movement case becomes
   "no drone or razor has a movement"); add the "re-given `.move()` fails" boundary case; add the grouping-rule case
   and the C3 ratio cases; add `test_level1_drone_exit.gd`.
2. Edit the director (step 1–2 above). Pin and grouping green.
3. C3: compute; if red, levers in the pre-approved order (rear_engage_seconds → 3.5; Swarm engage_seconds ≥ 4.5;
   split a 6–7 loose wave into `w<n>a`/`w<n>b`), else ESCALATE.
4. Exit integration green; `check-test-leaks.sh` clean; full gate.
5. Docs: DECISIONS line if a lever is pulled; level-1 doc note (updating-project-docs: this is a behaviour change of
   the level, not a structural rename, so only the relevant docs/roster lines).

## Test plan
`tests/integration/test_level1_drone_spawns.gd` (updated):
- `test_pinned_drone_and_razor_drone_spawns_match_todays_data`: 121 rows, triggers/offsets/delays/formations as
  before, `movement: false` everywhere.
- `test_no_drone_or_razor_drone_has_a_movement` (replaces the "every drone has movement" case).
- **Boundary** `test_a_drone_line_regiven_a_move_fails_the_pin`: build sections, set one drone entry's
  `movement = StraightMovement.new()`, assert `_actual_drone_spawns(...) != EXPECTED`.
- `test_loose_drone_lines_share_one_squad_per_wave`: for each wave, loose drone entries: count 2–7 → all share one
  non-empty `squad_id`; count 1 → empty id; formation entries → empty id. **Boundary:** no loose wave exceeds 7.
- C3 (`test_c3_attack_capable_peak_within_2x_legacy`, `test_c3_all_drones_peak_within_2_5x_legacy`): new helper
  `DroneConcurrency.squad_intervals(section, swarm_path, razor_path, lifetimes)` expands formations like
  `spawn_times()`, groups spawns by squad (formation entry / shared loose id / singleton; Razors are singletons),
  orders members by spawn time (ties: entry order) and marks the first three of each squad attack-capable. Lifetimes:
  Swarm attacker `engage_seconds + worst_exit`, Swarm REAR `rear_engage_seconds + worst_exit`, Razor
  `engage_seconds + max_dash_seconds + worst_exit` with `worst_exit = exit_distance/exit_speed +
  exit_speed/(2·acceleration)` from the live `ArenaCamera.projectile_world_rect()` and the shipped `.tres`.
  `peak_intervals()` = max overlap. Assert capable ≤ 2.0 × legacy and all ≤ 2.5 × legacy per section. Also record
  (gut `gut.p`) the actual ratios. **Boundary** helper case: a 5-member formation yields 3 capable + 2 rear.

`tests/integration/test_level1_drone_exit.gd` (new; rev 2 after review round 1):
- World: `HARNESS.assault()` (`tests/helpers/enemy_ai_harness.gd`), its `ArenaCamera` `make_current()`-ed, the
  player stub placed at the camera's lower-centre and left stationary (no hurtbox, so no detonation: the worst case,
  every drone must leave by itself). A `Node2D` enemy container and a real `WaveManager` under the harness root.
- Load one `WaveResource`: cloud_descent's **last** wave from `_build_sections()`, re-timed to trigger at 0 (a new
  `WaveResource` sharing the same `entries`; the shared resource is never mutated).
- Every spawned drone (counted through `enemy_spawned`) gets a `tree_exiting` hook recording its brain's `phase`
  and whether it has an `EnemyPathMover` child.
- Time is **game time**: the sum of `get_physics_process_delta_time()` over awaited `physics_frame`s from the
  `waves_complete` emission. The loop ends as soon as all 5 spawned and none remain, and fails once
  `section.enemies_cleared_timeout` of game time has passed. It never returns before 1.0 s of game time (the ≤ 0.8 s
  `delay()` timers must have fired, so no `SceneTreeTimer` outlives the test).
- Asserts: 5 drones spawned; the container held no `SwarmDrone` before the timeout; **every drone left in
  `Phase.DISENGAGE` with no `EnemyPathMover`**, so today's rail build (rail cull at about 6–7 s) fails it: the test
  is red before the director edit.
- **Boundary** `test_a_rail_driven_last_wave_is_rejected`: the same wave with each entry duplicated and given a
  `StraightMovement` → after 1.0 s of game time the drones carry an `EnemyPathMover`, so the same "left under AI
  control" predicate the main case uses reports them as rail drones. Then everything is freed. About 1 s long.

Worst-exit formula (review N4): one `static func worst_exit_seconds(exit_distance, exit_speed, acceleration)` in the
concurrency helper, used by the C3 cases; `test_engagement_deadline.gd` is not this task's file and is left alone.
Attack-capable count (review N5): the plan's metric (first three of each squad by spawn order) is asserted; the
`min(alive, 3)`-per-squad count is also computed and printed with `gut.p`, not asserted.
Bonus Drone (review N6): the diff of `level_1_director.gd` must touch only `b.drone()` lines; checked with
`git diff` before finishing. Exit mode (review N7): the no-movement case also asserts `exit_mode == FREE_ON_SCREEN_EXIT` for every drone and razor entry, so a leftover `.free_after(` fails it; a `grep` confirms none is left
on any drone line.

## Risks
- Headless physics tracks real time; the exit test takes ~9–10 s wall-clock. Acceptable (one test).
- A drone could get stuck at the corridor edge instead of leaving → that is exactly what the exit test catches.
- The script edit could mangle a line → the pin (offsets/delays/triggers vs 121 hand-pinned rows) catches it.

## Out of scope
Station BOTTOM squad, other enemies' rails (Ph15), Bonus Drone, balance tuning beyond the three levers.

## Response to review round 1
- B1: exit test now asserts every drone left in DISENGAGE with no `EnemyPathMover`, so it is red on the rail build;
  boundary case with `.move()` restored.
- R2: uses `HARNESS.assault()` + `make_current()`.
- R3: game-time accumulation, bounded loop, ≥ 1.0 s minimum so delayed-spawn timers have fired.
- N4–N7: see the test plan paragraph above.
