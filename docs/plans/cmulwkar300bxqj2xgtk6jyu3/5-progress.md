# Progress — t9-fighter-squad, Revision 3

- [x] Step 1 — Revision 2 restored from `prototype/revision2_variant.patch` into `assault/scenes/enemies/fighter/`
      (`fighter.gd`, `fighter_brain.gd`, `fighter_config.gd`, `fighter_config.tres`) by the unfinished attempt
      `cmuve39d9000lp02y0fpjmtmv`; reviewed and kept.
- [x] Step 2 — §3.4 dry-pass slot (`_rear_due`, `is_on_pass()`, `_rear_slot_free()`, `_rear_slot_taken()`), started by
      the same attempt; measured here: full-cycle grid 0 / 168.
- [x] Step 3 — §3.3 lead-in slide fallback and deadline pause (same attempt); measured load-bearing (38.0 px without).
- [x] Step 4 — Round-2 N5 (`is_braking_onto_station()`, priority-only yield; two broader variants measured and
      rejected), N6 (`_unsettled_time`, `UNSETTLED_WAIT_FACTOR`, `_own_wait_max()`).
- [x] Step 5 — `tests/integration/test_fighter_squad.gd`: 17 cases, green (≈ 67 s). Full-cycle separation with the
      end point asserted (N3), exiting fighters counted (N4), N2 and N6 cases, Assault REAR case rewritten. Mutations
      listed in `3-plan.md` §Test plan, each red.
- [x] Step 6 — Scratch `tests/integration/test_zz_sweep.gd` deleted (kept as `prototype/sweep_harness.gd.txt`, with
      kill-sweep and long-budget options added); stale `revision2_variant.patch` and its draft test removed from
      `prototype/` (in git history).
- [ ] Step 7 — round-3 review, gate, leak check, DECISIONS, docs.

**Resume at:** step 7.
**Deviations from plan:** none from Revision 3 (it was written from the build). Deviations from the epic plan are listed
in `3-plan.md` (N5–N7 of round 1, §3.4's REAR timing) and go to DECISIONS.
