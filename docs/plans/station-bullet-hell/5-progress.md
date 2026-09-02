# Progress — station bullet-hell fire (EPIC sub-item 4a)

Review verdict: **round 2 APPROVED** (`4-review.md`). Implementation started 2026-09-02.

Baseline before any change: `bash /agent/verify.sh` = **GATE PASS**, GUT `Scripts 21 / 188 passing`.
That script count is the C4 detector — a test file GUT cannot load is silently dropped and the
count stays flat while GUT still prints "All tests passed" and exits 0.

- [x] **Step 1 — `RadialAttackPattern`** — `global/resources/attack/radial_attack_pattern.gd` +
      `tests/integration/test_radial_attack_pattern.gd` (10 tests, all green).
      Watched it fail first, and the C4 trap reproduced exactly as `BACKLOG.md` describes:
      with the test file present but the class missing, GUT printed `---- All tests passed! ----`,
      reported `Scripts 21` (not 22) and exited 0, while stderr carried
      `Parse Error: Could not find type "RadialAttackPattern"`. The red was read off stderr and
      the script count, never off GUT's verdict.
      A new `class_name` is not visible to the suite until `godot --headless --import` has run.
- [x] **Step 2 — `SpaceStation.turrets()` accessor** — `space_station.gd`. A data accessor only;
      `live_turret_count()` left untouched because `test_space_station.gd` pins it.
- [x] **Step 3 — config exports** — ten gunnery fields on `space_station_config.gd`, values in
      `space_station_config.tres`. `core_ring_step = 0.24` (the golden-angle value from B2), not
      the refuted 0.21.
- [x] **Step 4 — scene edit** — `BulletPool` (pool_size 48) and `Gunnery` added to
      `space_station.tscn`. The pool is a DIRECT child of `SpaceStation` (B1); the gunnery node
      carries `node_paths=PackedStringArray("bullet_pool")` (non-blocking item 2), without which
      the export is silently left null.
- [x] **Step 5 — `StationGunnery`** — `assault/scenes/enemies/space_station/station_gunnery.gd`.
      Drives the authored pool, never creates one.
- [x] **Step 6 — `tests/integration/test_station_gunnery.gd`** — 16 tests, all green.
- [x] **Step 7 — `test_space_station.gd` container fix** — the station is now parented to a
      container `Node2D` (C3), so `bullet_pool.gd:47`'s grandparent resolution and
      `ExplosionEffect`'s `actor.get_parent()` both land inside something the test owns.
- [x] **Step 8 — gate, docs, backlog** — `bash /agent/verify.sh` **GATE PASS**,
      GUT `Scripts 23 / Tests 214 / 214 passing / 767 asserts`. Script count 21 → 23 and test
      count 188 → 214 (+26 = 10 + 16), which is the C4 detector confirming both new files were
      actually loaded rather than silently dropped.

**Resume at:** complete.

## Deviations from plan

None to the design. Test-local corrections during step 1:
- `test_spawn_radius_places_each_bullet_on_its_own_angle` first failed on an angle-wrap artifact
  in the *test* (+PI vs -PI for the same direction). Now compares with `angle_to`, which is
  wrap-safe. The implementation was correct.
- `test_the_pattern_ignores_ship_rotation` originally freed the first volley to count the second;
  a `queue_free()`d node also removed from its parent is a GUT orphan for the rest of the test
  (24 reported). It now compares the two volleys as batches and frees nothing.
- Added a 10th case beyond the plan's list of 9: `test_a_zero_bullet_count_fires_nothing`, pinning
  that `bullet_count <= 0` fires nothing rather than falling back to one bullet. Cheap, and it
  fixes the one ambiguity the plan left in the resource contract.

One correction during step 8, in `test_station_gunnery.gd` only:
- `test_destroying_turrets_removes_their_guns` failed with
  `Invalid call. Nonexistent function 'is_alive' in base 'Nil'`. Cause: `StationTurret._destroy()`
  runs `ExplosionEffect.explode()`, which parents its `CPUParticles2D` to `actor.get_parent()` —
  for a turret that is the station's `Turrets` node. The test's `_turrets()` helper returned a raw
  `get_children()`, so from the first kill onward it also handed back particle nodes and
  `child as StationTurret` returned null. The helper now filters to `StationTurret`, matching what
  `SpaceStation._turrets()` already does (which is why the gunnery's own `_live_turrets()` was
  never affected). Test-only; no production behaviour changed.

## Non-blocking review items

All eight handled. 1 — stale "23 tests" count corrected in `3-plan.md`. 2 — `node_paths=` written
as prescribed. 3 — the design-lock test reads `core_ring_step`/`core_ring_count` off the gunnery
node, never literals. 4 — the deliberate `0.25 * spacing` bound is explained in the test comment.
5 — the script was written before the scene referenced it and `--import` minted the UID;
`test_resource_uid_integrity.gd` is green. 6 — the refuted "gunnery creates the pool" paragraph in
`1-context.md` is rewritten and marked superseded. 7 — `b1check.gd` + `.uid` deleted. 8 — line
citations corrected in the new files' headers.
