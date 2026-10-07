# t9 prototypes (not shipped)

**The shipped build is in the code** (`assault/scenes/enemies/fighter/`, Revision 3 of `../3-plan.md`) with its test
`tests/integration/test_fighter_squad.gd`. Revision 2's patch and test, which Revision 3 grew out of, are in git history
(deleted in the commit that shipped Revision 3). What is left here are the rejected alternatives and the measurement tool.

| File | What it is |
|---|---|
| `sweep_harness.gd.txt` | The measurement sweep behind `../3-plan.md` §Measurements: clean harness (collision exceptions), `test_full_cycle` (the full-cycle grid; env `SW_FORMS`, `SW_MODES`, `SW_ENGAGE` for a long Assault budget, `SW_END`, `SW_CAP`, `SW_NONE=1` to count fighters on their exit), `test_trace` (`SW_TRACE=px,py,ax,ay,t0,t1`, `SW_TMODE`, `SW_TFORM`, `SW_TENGAGE`, `SW_TKILL` to kill the LEAD at a time) and `test_kill_sweep` (`SW_KILL=role,time,after`). Rename it to `tests/integration/test_zz_sweep.gd` to run it, and **delete it again before committing**: the load-integrity gate compiles every `.gd` outside `addons/`, and the gate would run it. |
| `orca_variant.patch` | Revision 1 (2026-09-30). Applies to `6711274`. Adds the ORCA give-way, D5 and D6 (`EnemyMover.requested_velocity()`). Contains two measurement leftovers: the `NO_GW` switch and `dbg_nudge`. Ruled a scope change (round-1 B1). |
| `routing_variant.patch` | Revision 1's alternative (2026-09-30). Applies to `6711274`. Lead-ins planned clear of mates' `predicted_position(t)`. Measured worse on breaches and silence. |
| `test_fighter_squad_draft.gd.txt` | Revision 1's draft test (superseded by the shipped test). |
| `test_fighter_avoidance_draft.gd.txt` | Unit cases for the ORCA variant only. |
