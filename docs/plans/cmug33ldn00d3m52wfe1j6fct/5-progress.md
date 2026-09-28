# Progress
- [x] Step 1 — fixture + MovementConstraint + EnemyBrain + EnemyMover skeleton
- [x] Step 2 — test_enemy_mover.gd + EnemyMover
- [x] Step 3 — test_enemy_brain_contract.gd + BaseEnemy tick/suspend_ai + EnemyPathMover
- [x] Step 4 — test_enemy_mover_single_writer.gd (+ boundary proven)
- [x] Step 5 — import + verify.sh + leak check
- [x] Step 6 — docs + DECISIONS.md

**Resume at:** done.
**Deviations from plan:** (1) the real-frames tick case compares against `Engine.get_physics_frames()` instead of a literal 3, because GUT's awaiter resumed one frame late (4 ticks for `wait_physics_frames(3)`); the "exactly one tick per frame" intent is unchanged. (2) the sweep blanks string-literal contents as well as comments. (3) tests-first was partly nominal for EnemyMover — its skeleton was written complete in step 1; the contract test was genuinely red first (2/13).
