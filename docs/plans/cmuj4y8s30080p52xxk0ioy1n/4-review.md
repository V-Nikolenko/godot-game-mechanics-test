VERDICT: CHANGES_REQUESTED

The director edit, the squad grouping, the updated pin and the C3 design follow epic §2.10 step 2, §2.6 and §5 C3.
The 119 `b.drone()` lines all carry `.move(`, and exactly two carry `.free_after(5.0)` (level_1_director.gd:836,
:854). Those counts match the plan. Two changes are needed before implementation, one of them blocking.

## Blocking

1. **The exit integration test cannot fail on the build it exists to replace.** (3-plan.md "Test plan", exit test;
   build step 1 "Tests first (red)".)
   - Today cloud_descent's last wave (level_1_director.gd:984-990) spawns five rail drones: `sine(200, …)` from
     design y -400.
   - `WaveManager._spawn_ship` attaches an `EnemyPathMover` whenever `movement` is a `MovementResource`
     (wave_manager.gd:213-225). With the default `FREE_ON_SCREEN_EXIT`, that mover frees each drone once it leaves the
     screen (enemy_path_mover.gd:12, :109-122). That is about 1200 px at 200 px/s, so roughly 6-7 s after the
     trigger, which is under the 10 s `enemies_cleared_timeout` (level_section.gd:35).
   - So "container holds no SwarmDrone before the timeout" is already green before the director is touched. The plan's
     claim that the test starts red is false, and the test proves nothing about `EngagementBudget`/DISENGAGE, which is
     what epic §2.6's "integration case (t15)" is for.
   - Required: the test must also assert how each drone left, and the plan must name that assertion. Either:
     - (a) assert every spawned drone has no `EnemyPathMover` child (check on `enemy_spawned`), **and**
     - (b) record that each drone's exit happened under AI control. Connect each drone's `tree_exiting` and check
       that the brain's `phase == Phase.DISENGAGE`, or that its position is outside
       `EnemyWorld.projectile_world_rect()` (swarm_drone_brain.gd:537-542).
   - Add a boundary case too: the same wave with `.move()` restored must fail.

## Required

2. **Reuse `tests/helpers/enemy_ai_harness.gd` instead of building a new world.** `HARNESS.assault()` already
   provides a `CharacterBody2D` player in group `player` and an `ArenaCamera` at (640, 360) (enemy_ai_harness.gd:39-56).
   The plan builds all of this again by hand. Use the harness, set `harness.player.global_position` to the bottom-centre
   spot, and call `make_current()` on the harness camera. That call is needed because `_spawn_ship` returns silently
   when `get_viewport().get_camera_2d()` is null (wave_manager.gd:162-164), and test_spawn_camera_pan.gd:43 makes the
   same call for the same reason.

3. **Say exactly how "elapsed game time" is measured, and bound the loop.**
   - Measure it by summing the `delta` the tree actually advances (`get_physics_process_delta_time()` per awaited
     `physics_frame`). Do not use `Time.get_ticks_msec()`. A loaded CI box would otherwise stretch wall time against
     the game time that `WaveManager`'s clock and the `SceneTreeTimer`s run on, which makes the test flaky.
   - The loop should exit as soon as the container is empty (after all 5 have spawned). It should fail once the
     accumulated time passes `enemies_cleared_timeout`. It must never return before the 0.8 s delay timers
     (wave_manager.gd:153-157) have fired. The plan's 1 s sanity poll does satisfy that last point; state that this is
     why the poll is at 1 s.

## Non-blocking (fix if cheap)

4. **Put `worst_exit` in the shared helper.** C3's `worst_exit` is the same expression as
   `test_engagement_deadline.gd`'s deadline arithmetic. Add it to `tests/helpers/level1_drone_concurrency.gd` and call
   it from the new C3 cases, rather than writing it a third time.

5. **The "first three by spawn time" rule for attack-capable is the epic's own model, so keep it.** Roles are actually
   reassigned by distance, and `release_lead()` rotates them (squad_controller.gd:189-218). While `rear_engage_seconds`
   equals `engage_seconds` (both 5.5 in swarm_drone_config.tres), `min(alive_in_squad, 3)` per squad per sample is the
   more conservative count, and it costs one line. Consider asserting that instead, or record both values with `gut.p`.

6. **Keep the edit script's diff inside the section builders.** Its regex anchors on `b.drone()`, so it cannot match
   `b.bonus_drone()` or `_section_schedules` (level_1_director.gd:52-72), and nothing pins that schedule. State in the
   plan that the reviewed diff must touch no lines outside the `_build_section_*` bodies. That is the acceptance
   evidence for "Bonus Drone schedule unchanged".

7. **Optionally assert `exit_mode`.** The pin's `EXPECTED` does not include `exit_mode`/`exit_time`
   (test_level1_drone_spawns.gd:209-218), so a leftover `.free_after()` would go unnoticed. That is harmless without a
   mover, but you could add `exit_mode == FREE_ON_SCREEN_EXIT` to the new no-movement case, or accept this and say so.

## Checked and fine
- **Squad key:** it is `"<wave index>:<id>"` (wave_manager.gd:127-129), so any id that is unique within a wave is
  correct. The rejection of automatic per-wave tagging is sound.
- **Loose-wave sizes:** the largest loose wave has 7 drones (deep_space 28.0 s, level_1_director.gd:459-467), so the
  "no loose wave > 7" boundary holds.
- **Station BOTTOM squad:** still pinned by test_level1_drone_spawns.gd:320-352. `station_reinforcements.gd` is
  untouched.
- **Timers:** ContactBlast deliberately creates no timers (contact_blast.gd:14). The only `SceneTreeTimer` the exit
  test creates is `WaveManager`'s, which the plan already covers.
- **Pin boundary case:** mutating a fresh `_build_sections()` entry and comparing it against `EXPECTED` does fail.

---

# Round 2

VERDICT: APPROVED

I re-checked the revised 3-plan.md (the exit-test section, the N4–N7 paragraph and "Response to review round 1")
against my round-1 findings and the code.

- **B1, resolved.** The exit test now records, on each drone's `tree_exiting`, the brain's `phase` and whether the
  drone has an `EnemyPathMover` child, then asserts `Phase.DISENGAGE` with no mover.
  - The brain can be reached as `$Brain` (swarm_drone.tscn:111, swarm_drone.gd:26).
  - `_tick_disengage()` calls `queue_free()` while the brain is still in DISENGAGE (swarm_drone_brain.gd:537-542), so
    the recorded phase is the right one.
  - A rail drone gets an `EnemyPathMover` from wave_manager.gd:213-225 and is freed by that mover's screen cull, not by
    DISENGAGE, so today's build fails this assertion.
  - The boundary case duplicates the entries instead of mutating the shared resource, which is correct.
- **R2, resolved.** The test now builds its world with `HARNESS.assault()` and calls `make_current()` on its camera.
- **R3, resolved.** Time is accumulated game time. The loop is bounded by `enemies_cleared_timeout`, and it runs for at
  least 1.0 s, which is longer than the largest spawn delay (0.8 s), so every delayed-spawn timer has fired.
  - Nothing in `global/enemy_ai/` or in `EnemyPathMover` calls `create_timer`, so the boundary case, which ends at
    about 1 s, leaves no other timers behind.
- **N4–N7, resolved as stated.** The worst-exit formula becomes one helper function. The `min(alive, 3)` count is
  printed but not asserted. The diff is limited to `b.drone()` lines. The no-movement case now also asserts
  `exit_mode == FREE_ON_SCREEN_EXIT`. Leaving `test_engagement_deadline.gd` alone is acceptable.

Remaining notes (not blocking):
- `tree_exiting` hooks also fire when autofree frees whatever is left at teardown, including the boundary case's rail
  drones. Take every assertion before teardown, and keep the recorder on the test object (not a node that is being
  freed), so a late callback cannot write into freed state or add a spurious failure.
- Run `scripts/check-test-leaks.sh` after the exit test lands. Build step 4 already says this.
