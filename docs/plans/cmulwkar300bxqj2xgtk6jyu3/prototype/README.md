# t9 prototypes (not shipped)

Each patch is a complete variant of `assault/scenes/enemies/fighter/{fighter.gd, fighter_brain.gd, fighter_config.gd,
fighter_config.tres}`. Apply **one**. The measurements behind each are in `../5-escalation.md`.

| File | What it is |
|---|---|
| `revision2_variant.patch` | **Revision 2 (2026-10-05), the latest.** Applies cleanly to `f753884`. Squad roles, window, holds, REAR dry passes, crossing stagger (one-gap parallel trail), budget-bounded holds, ring-fallback clearance, plus the in-scope give-way: `_slide_aside()` (a holder steps off a moving mate's planned track) and `_slow_for_mates()` (a member on a lead-in slows along its own track), the settled-on-S rule, and the budget-pressure start rule. The current-role REAR fire gate (round-1 N3). No env switches or debug fields. Round-2 review: CHANGES_REQUESTED (second-window REAR/turn overlaps). |
| `test_fighter_squad_rev2.gd.txt` | Its `tests/integration/test_fighter_squad.gd` (15 cases, dual where the acceptance line asks; green on the patch; ≈ 40 s). Its separation case stops at the LEAD's second RUN_IN — round-2 B1 asks for the third. |
| `orca_variant.patch` | Revision 1 (2026-09-30). Applies to `6711274`. Adds the ORCA give-way, D5 and D6 (`EnemyMover.requested_velocity()`). Contains two measurement leftovers: the `NO_GW` switch and `dbg_nudge`. Ruled a scope change (round-1 B1). |
| `routing_variant.patch` | Revision 1's alternative (2026-09-30). Applies to `6711274`. Lead-ins planned clear of mates' `predicted_position(t)`. Measured worse on breaches and silence. |
| `test_fighter_squad_draft.gd.txt` | Revision 1's draft test (superseded by `test_fighter_squad_rev2.gd.txt`). |
| `test_fighter_avoidance_draft.gd.txt` | Unit cases for the ORCA variant only. |
| `sweep_harness.gd.txt` | The measurement sweep: clean harness (collision exceptions), dense / wide sets, SEP / CYC / HIT / BREACH / SILENT metrics, plus `_trace` and a flank-only debug case. Rename it to `tests/integration/test_zz_sweep.gd` to run it, and **delete it again before committing**: the load-integrity gate compiles every `.gd` outside `addons/`, and the gate would run it. |
