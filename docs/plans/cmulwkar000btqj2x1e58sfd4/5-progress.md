# Progress
- [x] Step 1 — `global/enemy_ai/dubins_path.gd` + `tests/unit/test_dubins_path.gd` (7 tests green)
- [x] Step 2 — brain: pass geometry/latching, RUN_IN, APPROACH/EXTEND/TURN/REPOSITION/caps/passes
  (`assault/scenes/enemies/fighter/fighter_brain.gd`, applying I1–I8)
- [x] Step 3 — Assault rules + specs (`tests/integration/test_fighter.gd`)
- [x] Step 4 — weapons + specs; the two t8a-only cases rewritten
- [x] Step 5 — gate green (1195/1195), `scripts/check-test-leaks.sh` clean; docs and DECISIONS

**Resume at:** done.
**Deviations from plan:**
- The lead-in re-plans when S leaves the track the plan predicted for it (`S_plan + v_P × age`), not when
  it moves 24 px from S at plan time. Against a moving player the literal rule re-plans every ≈ 0.12 s
  (review I5's measurement). The arrival prediction `T = length(S + v_P·T) / max_speed` is refined
  3 times (capped at the plan's `GOAL_PREDICT_MAX` 3 s) instead of once.
- The tick RUN_IN is entered on already steers along the pass line (`_steer_run_in`), so `seek_target`
  is a lookahead ahead on every RUN_IN tick, the entry tick included.
- The cruising-player (I6) natural spawn is ahead-and-beside the player's course, `MID + (600, −600)`:
  from straight abeam or behind, the first pass comes from APPROACH's deadline at 5–11 s and the second
  falls just past 20 s. The steady state is a breach-shaped pass about every 15 s (REPOSITION runs to its
  deadline), recorded in DECISIONS and `ENEMY.md`.
