# Progress

- [x] Step 1 — Added `test_writing_to_one_trackers_score_config_cannot_reach_another` to
  `tests/integration/test_config_instance_isolation.gd`. Confirmed it failed against the
  pre-fix code (4 assertion failures, shared-object symptoms).
- [x] Step 2 — Widened `ShipConfig.privatise()` (`global/resources/ship_config.gd`) to take an
  optional `property: String = "config"` parameter and check `is Resource` instead of
  `is ShipConfig`. Doc comment updated to describe the general behaviour and name
  `ScoreTracker.score_config` as the second use.
- [x] Step 3 — `ScoreTracker._ready()` now calls `ShipConfig.privatise(self, "score_config")`
  after the null-fallback re-preload, before `score_config` is first read.
- [x] Step 4 — Re-ran `test_config_instance_isolation.gd`: 7/7 passed, including the new test and
  all six existing entity-config tests (signature change is backward compatible).
- [x] Step 5 — Ran `test_score_tracker_escape_penalty.gd`: 2/2 passed, unaffected.
- [x] Step 6 — Full gate: `bash /agent/verify.sh` → `GATE PASS`, 384/384 tests, 1950 asserts.

**Resume at:** done.
**Deviations from plan:** none.
