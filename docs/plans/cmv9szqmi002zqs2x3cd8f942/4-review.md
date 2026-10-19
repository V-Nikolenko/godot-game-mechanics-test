VERDICT: APPROVED

# Review — t17 plan (Level 1 placement of the Missile Corvette and the Support Ship)

## Round 1

Independent review of `3-plan.md` / `1-context.md` against the code. The task acceptance criteria and the epic's §2.18,
§4.1 and §4.3 were the reference. I checked every claim below against the code, and re-ran two things myself (read-only):
`test_level1_specialist_spawns.gd` (the current peaks) and the draft `tests/zz_scratch_t17/test_zz_measure.gd` (the
slice-replay measurements).

### Verified claims

1. **Placements match the task.** `git diff assault/scenes/levels/edelia/1/level_1_director.gd`: there are five new
   lines, each inside an existing wave. A corvette sits at 11.0 + 1.0 = 12.0 s (deep_space). A support sits at
   (-255, -460) in the 26.0 s ram wave, the deep_space ram line nearest 26 s. In planet_approach, a support sits at
   (0, -460) in the 28.0 s ram triple, and corvettes sit at 39.0 + 1.0 = 40.0 s and 84.0 + 1.0 = 85.0 s. No line has
   `.move()`, `.free_after()` or `.shoot_*()`. No existing line or config changed. planet_approach's triggers are
   monotonic (director lines 583-798). deep_space has the known 3.5 / 2.0 / 3.0 quirk, but no new line sits in an
   affected wave. Adding an entry to an existing wave changes no other wave's index or effective trigger
   (`wave_manager.gd::_process` triggers in list order).
2. **The "65.7 s peak" deviation holds.** A run of `test_level1_specialist_spawns.gd` on the working tree prints
   `planet_approach: peak alive specialists 6 at 75.50 s (limit 7.5 ...)` and lives sniper 16.23 / bomber 18.38 /
   ram 10.19. I recomputed planet_approach by hand with the plan's lives (corvette 16.89, support 13.58):
   - At 75.5 s: 6 alive. The 40 s corvette ended at 56.89.
   - At 98.0 s: 7 alive (bomber 98, snipers 92 x2, rams 88 / 88.4 / 88.8, which end at 98.19 / 98.59 / 98.99, and the
     85 s corvette, which ends at 101.89).
   - At 28.4 s: 5. At 44.2 s: 4.

   So 7 <= 7.5 holds, as the plan says. The task's literal boundary cannot work. An extra corvette at 65.7 s (alive to
   82.59) gives only 4-5 at 65.7 s and 7 at 75.5 s, which still passes the gate. So "an extra corvette at the 65.7 s
   peak fails" is false on today's data. The likely cause is that the 65.7 s figure was measured before t22's ram levers
   shortened the ram's life. Using the measured `_peak()["at"]`, the existing ram-triple boundary's shape, is the right
   reading. Asserting `before["count"] == 7` makes the boundary non-vacuous: 7 + 1 = 8 > 7.5. Recording it in DECISIONS
   is required, and the plan does so. deep_space after placement: 7 at 15.5 s, 26.5 s and 29 s, against a limit of
   12.5. cloud_descent is unchanged.
3. **Lifetime terms are right.**
   - Corvette:
     - `missile_corvette_brain.gd:214`: `attack_window()` = 0.7 + 2 x 0.22 = 1.14.
     - `:238-243`: expiry is deferred only during TELEGRAPH / SALVO.
     - `:301`: the attack gate is `attack_window() + 0.05`.
     - `engage_seconds` 7.0 (`missile_corvette_config.tres`).
   - Support (`support_ship_brain.gd:146-152`): DISENGAGE starts on expiry, with no deferral. This confirms
     "engage 9.0 + exit". The escort tow (`:734`) moves the ward, not either budget.
4. **The probe `prepare` hook is sound.** Diff of `specialist_exit_probe.gd:82-112`: the hook is called after
   instantiate and before `add_child`. The four pools are direct scene children with authored `pool_size`
   (`missile_corvette.tscn:130-151`), and `BulletPool._prewarm()` runs in `_ready()`. So setting `pool_size = 0` on the
   instance changes only that instance. Nothing in `MissileCorvette._ready()` reads the pools, and DISENGAGE never
   fires. The default `Callable()` leaves the existing callers identical.
5. **Attack-in-budget measurements are reproduced.** I ran the scratch measurement. Each value is shown as time after
   spawn, then budget left.

   | Ship | Event | Time after spawn | Budget left |
   |---|---|---|---|
   | Corvette, deep_space 12.0 s | TELEGRAPH | 4.07 s | 2.93 s |
   | Corvette, deep_space 12.0 s | Salvo done | 5.00 s | 2.00 s |
   | Corvette, planet_approach 40.0 s | TELEGRAPH | 4.60 s | 2.40 s |
   | Corvette, planet_approach 40.0 s | Salvo done | 5.75 s | 1.25 s |
   | Corvette, planet_approach 85.0 s | TELEGRAPH | 4.48 s | 2.52 s |
   | Corvette, planet_approach 85.0 s | Salvo done | 5.42 s | 1.58 s |
   | Support, deep_space 26.0 s | Supporting | 3.50 s | 5.50 s |
   | Support, planet_approach 28.0 s | Supporting | 3.02 s | 5.98 s |

   In both support runs the ward was the RamCorvette it spawned with. Exactly one target is in each slice.

   Both boundaries trip with margin:
   - Corvette with `engage_seconds` 4.0: the gate needs TELEGRAPH by 2.81 s, but the initial `salvo_cooldown` alone is
     4-5 s (`:225`). The margin is >= 1.26 s.
   - Support with `engage_seconds` 2.5: the earliest support is at 3.02 s, a margin of 0.52 s. Spawn jitter does not eat
     into it, because the budget counts from the ship's own first tick and the ram spawns in the same idle frame.

   The tweak goes through `child_entered_tree`, which fires after `_enter_tree()` and its `privatise()`
   (`base_enemy.gd:72`) and before `_ready()`. So it edits the private copy, never the shared `.tres`. That follows the
   CLAUDE.md config-ownership rule.
6. **Leak rule.** `_spawn_with_delay()` (`wave_manager.gd`) awaits a `SceneTreeTimer`. The plan's "switch the
   WaveManager off and keep stepping until every already-triggered wave's spawn timers have fired" handles this
   correctly before the world is freed. Freeing the world under a pending timer would resume a coroutine on a freed
   instance. The new enemy code holds no timers, tweens or awaits (grep over `support_ship/`, `missile_corvette/`,
   `enemy_rockets/`, `enemy_shield.gd` and `global/enemy_ai/`). `check-test-leaks.sh` is in step 5.
7. **8x clock.** Both target files already own a save/scale/restore pair that keeps the step at 1/60 and restores it in
   `after_each`:
   - `test_missile_corvette.gd:273-291` (`_scale_clock`/`_restore_clock`)
   - `test_support_ship.gd:829-846` (`_fast_clock` plus `after_each`)

   The helper waits three idle frames before `load_section()`, as `tests/README.md` requires. No row compares wall-clock
   time against a tolerance tighter than one idle frame. `remaining()` is the brain's own summed physics delta.
8. **Deadline rows.**
   - `_deadline_rows`, `_add_to_last_wave` and `_section_has_scene` already exist (`test_engagement_deadline.gd:99,
     236, 278`), and so does the bomber "no-exit-term" boundary shape (`:728-761`). The plan reuses them rather than
     reinventing them.
   - The corvette boundary computes 0 + 7.0 + 1.14 + 7.0 + 0.5 = 15.64 > 10. Its rocket term comes from
     `EnemyRocketScenes.max_time_of()` (`enemy_rocket_scenes.gd:42`; Warhead 7.0). This matches the acceptance wording
     "from the rocket term alone".
9. **Unaffected gates.** The fighter and drone level-1 gates filter by scene path:
   - `test_level1_fighter_fire_density.gd:144`
   - `test_level1_drone_exit.gd:157`
   - `test_level1_fighter_exit.gd:141`

   `test_level1_specialist_exit.gd` replays cloud_descent only. `test_level_1_sequence.gd` zeroes delays and has no
   camera.
10. **Gate time is plausible.** The scratch runs cost 0.126-0.127 s of wall time per game second at 8x. Stopping each
    run at its condition gives about 6.0-6.8 s game time per corvette and about 3.0-4.5 s per support. That is about
    3.5 s, plus settling, against the plan's 3.8 s. Stopping the two boundary runs at expiry (5.0 s and 3.5 s game time)
    gives about 1.1 s. With the measured probes (about 7.2 s), the total is about 12.4 s, inside the 15.0 s allotment.
    GUT would be about 198 s, well under 240 s.

### Findings to apply during implementation (none block the plan)

- **N1 (required): delete `tests/zz_scratch_t17/` before the gate.** The build sequence does not mention it.
  - GUT runs it with `-ginclude_subdirs`, and `test_suite_integrity.gd` only checks that it compiles.
  - It costs 7.8 s of GUT time (measured just now), which is more than half the allotment.
  - It is a no-assert "Risky" test.
  - It also hard-codes `physics_ticks_per_second = 480` rather than scaling the saved value, which goes against README
    rule 1.

  Add the deletion to step 6, before `scripts/gate-time.sh`. Commit the generated `level1_slice_replay.gd.uid` with the
  helper. Every other helper ships one.
- **N2: keep the new probe results out of the existing `_exits` dictionary** (`test_level1_specialist_spawns.gd:379-395`).
  Alternatively, state the change to `test_measured_exits_are_real`. Its loop (`:468-474`) asserts
  `runs == starts().size() * 3` for every key. A corridor x 2-speed result (2166 runs) in the same dictionary would fail
  that existing assertion or force an edit to it. Do not edit the existing assertion. Put the corvette and support in
  their own memo, with their own sanity row: `runs == corridor_starts().size() * 2`, no run capped, and the exit at
  least the straight distance from the centre to the edge. Also, `_ai_intervals()` indexes `_KIND_NAMES[path]` (`:440`),
  so it must be able to name the new paths.
- **N3: make the attack rows unable to pass vacuously.**
  - `EngagementBudget.remaining()` returns `INF` when `active` is false (`engagement_budget.gd:50-53`), and `INF > 0`.
    Assert `brain.budget.active` in each attack row and in each boundary row.
  - In each boundary, also assert that the target spawned exactly once and that its budget actually expired inside
    the run (DISENGAGE was reached, or `remaining() == 0` was observed). Otherwise a run that ends early, or a missing
    ship, proves "never".
  - The boundary must use the same predicate as the main row: TELEGRAPH with budget left for the corvette, and the full
    supporting condition for the support. That proves the main row can fail.
- **N4: state the spill-over row's scope and read its rocket term live.**
  - The row covers planet_approach's specialists, both new kinds included. The acceptance text says "nothing from
    planet_approach". Say in the test comment that drones, fighters and Gatlings are bounded by their own gates and are
    not touched by this task. The margin is about 70 s: the latest end is the bomber at 116.4 s, against 186 s.
  - Use the same live `max_time_of()` maximum as the deadline boundary for the "+ 7.0" term, not a typed 7.0.
  - 186 s ignores cloud_descent's 2.0 s `transition_in_duration`, which only makes the bound conservative. Say so in
    the comment.
  - Optional and cheap: apply the same predicate to deep_space against station_assault's start (ENEMIES_CLEARED). The
    support at 26 s lives to about 39.6 s, and the corvette's rockets end by about 35.9 s.
- **N5 (note): "120 px behind the ram".** The plan reads this as 120 world px, which is 60 design units, giving y -460.
  The convention allows that reading, and the plan states it. The support then spawns at world y -920. That is outside
  the 1608 px projectile world rect (±804) by 116 px. The measured run shows this is harmless: the support reaches its
  ward in 3.0-3.5 s, and nothing frees an AI enemy for being outside that rect except DISENGAGE. Say it in the
  DECISIONS line next to the 65.7 s deviation, so a later reader does not "fix" it.

No existing row, frozen constant or enemy config changes. Every new gate has a boundary that the code shows can trip.
The one deviation from the task text is necessary and correctly reasoned.
