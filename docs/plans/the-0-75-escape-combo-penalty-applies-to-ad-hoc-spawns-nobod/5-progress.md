# Progress

- [x] 1. Added `counts_as_escape: bool = true` to `global/resources/ship_config.gd`.
- [x] 2. Added `var counts_as_escape: bool = true` to `assault/scenes/enemies/base_enemy.gd`,
      propagated from `config` in `_ready()` next to `counts_toward_wave_clear`.
- [x] 3. Set `counts_as_escape = false` on `assault/scenes/enemies/bonus_drone/bonus_drone_config.tres`;
      corrected `bonus_drone.gd`'s header comment to name both flags.
- [x] 4. `assault/scenes/systems/score_tracker/score_tracker.gd`: read `counts_as_escape` in
      `_on_enemy_spawned()` with the same `enemy.get(x) != null` fallback idiom as
      `counts_toward_wave_clear`; bound it into `_on_enemy_freed()`; gated the
      `escape_combo_multiplier` multiply (and its `combo_changed` emit) behind it. Wave-tally
      bookkeeping stays unconditional — that's a separate concern.
- [x] 5. New test `tests/integration/test_score_tracker_escape_penalty.gd`:
      `test_bonus_drone_escaping_does_not_cost_combo` (real `bonus_drone.tscn`, escape leaves
      combo at 4.0) and `test_enemy_with_no_escape_flag_still_pays_the_penalty` (bare `Node2D`,
      default-true boundary, combo lands at 3.0 = 4.0 * 0.75).
- [x] 6. Verified `test_station_reinforcements.gd` unchanged and still green (18/18) — reinforcements'
      double penalty is untouched, per the plan's explicit decision not to re-open that call.
- [x] 7. `bash /agent/verify.sh` → GATE PASS (361/361). `bash scripts/check-test-leaks.sh` → LEAK
      CHECK PASS.

**Resume at:** done.
**Deviations from plan:** none — implementation matches `3-plan.md` exactly. Test file placed
under `tests/integration/` (not `tests/unit/`) since it instantiates a real scene
(`bonus_drone.tscn`) and mirrors the wiring style of `test_station_reinforcements.gd`, which the
reviewer's non-blocking note anticipated ("no `tests/unit/test_score_tracker.gd` currently
exists").
