# Progress

- [x] Steps 1–7 of the build sequence (component changes 0–3, `race_ship.gd` and
  `station_turret.gd` call-site fixes, `test_damage_reaction.gd`'s container fix, both new test
  files) — already implemented and committed by a prior cycle (`4126376`, mislabeled
  `agent: cycle 2026-09-08-0038-i1` rather than a descriptive subject — the harness auto-committed
  uncommitted work from that window). Verified by reading the diff and the current file contents;
  matches `3-plan.md` round 2 exactly.
- [x] Step 8 — `tests/integration/test_explosion_effect_placement.gd` present and passing (6/6),
  same prior commit.
- [x] Step 9 — Gate: `bash /agent/verify.sh` → GATE PASS (41 scripts / 355 tests / 1837 asserts).
  **`scripts/check-test-leaks.sh` initially FAILED**: a leaked `SceneTreeTimer`, traced to
  `test_a_race_wall_under_the_real_track_offset_explodes_at_the_wall` — `race_wall.gd:49` awaits a
  0.7s `SceneTreeTimer` before its own `queue_free()`, and the test returned (letting
  `add_child_autofree` free the wall) while that coroutine was still suspended. This is the same
  class of trap `tests/README.md` documents for `LevelDirector`, just on `RaceWall`'s own death
  cleanup, and the plan's test plan didn't anticipate it. Fixed by adding
  `await wait_seconds(0.75)` after the test's assertions, so the wall's own cleanup completes
  before the container is freed. Both `verify.sh` and `check-test-leaks.sh` are green after.
- [x] Step 10 — Docs updated (`updating-project-docs` skill): `docs/architecture/modules/global.md`
  (the `ExplosionEffect` wiring recipe — was still describing the deleted two-hop rule and the
  now-false "must be a child of the entity" constraint), `station_death_sequence.gd`,
  `space_station.tscn`, `tests/README.md` (both flagged bullets, including correcting the
  `$Turrets` claim which the turret fix makes false), and `test_station_gunnery.gd`'s `_turrets()`
  comment. The other seven header comments the plan flagged (`test_space_station.gd`,
  `test_station_laser_phase.gd`, `test_station_reinforcements.gd`, `test_station_gunnery.gd:20`,
  `test_station_death_sequence.gd`, `test_config_instance_isolation.gd`,
  `test_enemy_contact_damage.gd`) were checked against the new behaviour and found to still be
  accurate — they describe the *default* container rule (`actor.get_parent()`), which is
  unchanged; left as-is rather than rewritten for no substantive reason.

**Resume at:** done — proceeding to `set-state done`.
**Deviations from plan:** one test fix not anticipated by the plan (the `RaceWall` coroutine leak
above); everything else matched the plan exactly.
