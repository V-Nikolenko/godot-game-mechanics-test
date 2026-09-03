# Progress

- [x] Step 1 — `BulletPool.cancel_active()` extracted from `_exit_tree()`
      (`global/components/bullet_pool.gd`). `_exit_tree()` is now a one-line call to it.
- [x] Step 1b — `ExplosionEffect.explode(at)` optional position argument
      (`global/components/explosion_effect.gd`). Typed assignment, never `at as Vector2`.
- [x] Step 2 — `SpaceStationConfig.death_sequence_duration` / `death_blast_count` + the `.tres`
      values (1.8 / 7, against script defaults 0.0 / 3).
- [x] Step 3 — `space_station.gd` lifetime: `death_started`, public `death_duration`, `_dying`
      latch, `_death_timer` (a Timer NODE), `_on_health_changed` override,
      `_make_corpse_harmless()`, `_finish_death()`. Also fixed the stale `beam_behavior.gd:99-102`
      citation in the class comment (finding O).
- [x] Step 4 — `station_gunnery.gd::_stop()` calls `bullet_pool.cancel_active()`.
- [x] Step 5 — `station_death_sequence.gd` + the `DeathSequence` node in `space_station.tscn`.
- [x] Step 6 — `tests/integration/test_station_death_sequence.gd` (15 tests),
      `tests/integration/test_level_1_sequence.gd` (1 end-to-end), 2 tests appended to
      `test_station_gunnery.gd`.
- [x] Step 7 — docs (`updating-project-docs`), `BACKLOG.md`, `tests/README.md`.

**Gate:** PASS — 26 scripts / 249 tests / 941 asserts (was 24 / 232 / 868).

## Deviations from plan

1. **`test_station_laser_phase.gd::test_beams_stop_and_do_not_outlive_the_station` needed a
   one-line change.** It asserted the station is freed two physics frames after death — true only
   because `BaseEnemy` freed it in the same frame. Its *stated* intent is that no BEAM outlives the
   station, so the fix sets `_station.death_duration = 0.0` to select the original same-frame path
   and leaves the assertion verbatim. The lingering path is covered by the new file. The plan did
   not anticipate this test.

2. **The plan's `spawn_delay` sweep (finding C) was necessary but NOT sufficient.** The end-to-end
   test still leaked. `wave_manager.gd:143` expands a formation as `base_delay + slot.delay`, and
   every formation type staggers its own slots — so `entry.formation.set(&"stagger_delay", 0.0)`
   was needed as well. Found by observing `ObjectDB instances leaked` on the first full run and
   bisecting; `3-plan.md`'s finding-C block and `tests/README.md` both now record it.

3. **A 1.1 s drain was added at the end of test 12, and its comment is deliberately honest about
   status.** It guards the `_wait_for_child_exit_or_timeout()` poll timer, which keeps ticking when
   the child exits first. Measured: the leak does **not** currently reproduce without it, because
   ~10 s of later tests happen to outlive the timer — that is ordering luck, so the guard stays,
   labelled as a guard rather than as an observed fix.

4. **The gate's `ObjectDB instances leaked` line is pre-existing and comes from step 1, the
   headless import — not from the suite.** Established by running the import against a stashed
   tree: baseline and current both emit exactly one; the GUT step emits none. Filed under
   *Discovered*. This was initially misattributed to the new test, which is why deviation 3's
   comment is worded the way it is.

**Resume at:** complete.
