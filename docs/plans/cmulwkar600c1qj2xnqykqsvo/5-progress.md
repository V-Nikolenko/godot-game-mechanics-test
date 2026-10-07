# Progress
- [x] Step 1 — `gatling_interceptor_config.gd/.tres` (the §D1 fields; legacy weapon → `rail_*`), `gatling_interceptor.tscn`
  (+EnemyMover, Brain, StateLight, StreamPool 36 as a root child, Attack), `gatling_interceptor.gd` (the `fighter.gd`
  shape), `gatling_interceptor_brain.gd`; `test_enemy_bullet_lifetime.gd` reads `round_speed` / `rail_stream_speed`;
  `test_level1_fighter_spawns.gd` suspends every `Brain` ship and reads `max_distance` from each ship's own round (A4).
- [x] Step 2 — window machine + specs (`tests/integration/test_gatling_interceptor.gd`): rhythm, light, cadence, seed sweep,
  side-on, predicted aim.
- [x] Step 3 — sides, budget rule, deferral specs; the A2 corridor-top case and its boundary.
- [x] Step 4 — `test_enemy_dual_mode.gd` Gatling cases.
- [x] Step 5 — gate green (1228/1228), `scripts/check-test-leaks.sh` clean; `ENEMY.md`, the roster entry, `global.md` line, DECISIONS.

**Resume at:** done.

**Review notes applied:**
- A1: SPIN_UP latches the strafe that continues the current velocity (> 40 px/s), else "dot h ≤ 0".
- A2: Assault routing samples the swing every 25°; if a clamped waypoint comes within `min_flank_range` it goes round the
  other way. Test seam `route_fallback`; boundary case proves the run cuts over the player without it.
- A3: APPROACH re-derives the first side every tick and latches it on exit (header comment).
- A4: no "constant + delta" branch. Measured: all three frozen sections still equal their constants with the Gatling at
  pool 36 and each ship's round read from its own pool (`_round_max_distance`).
- A5: Assault sequence/wall runs use a long private budget and assert ≥ 3 windows; the no-budget case is staged within
  `swing_in_reach` and asserts the REPOSITION hold, with the complementary "just enough budget" case; the mid-stream expiry
  is staged by a probe run and asserts the 2.08 s and the solo bound; containment counts only after entry; pool life read
  from `StreamPool.bullet_scene`.
- A6: REPOSITION tapers into F once it is within `swing_in_reach`.
- A7: recorded in DECISIONS.
- A8: noted below; the plan text is otherwise left as reviewed.

**Deviations from plan:** D2 (approved). A8 corrections: the SPIN_UP slide is ≈ 17 px, not 35; the t11 deferral bound uses
the epic's conservative `max_rounds × interval`.
