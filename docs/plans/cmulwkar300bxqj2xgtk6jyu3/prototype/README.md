# t9 prototypes (not shipped)

Both patches apply cleanly to HEAD `6711274` (`git apply --check`, 2026-09-30). Each is a complete variant of
`assault/scenes/enemies/fighter/{fighter.gd, fighter_brain.gd, fighter_config.gd, fighter_config.tres}`; the ORCA one
also touches `global/enemy_ai/enemy_mover.gd`. Apply **one**, not both. The measurements behind each are in
`../5-escalation.md`.

| File | What it is |
|---|---|
| `orca_variant.patch` | Squad roles, window, holds, REAR dry passes, crossing stagger, budget-bounded holds, ring-fallback clearance. Adds the ORCA give-way (`avoidance()`, `_share()`, `give_way_rank()`, along-track-only for the run and turn-in, nothing toward the player). Adds D5: `_heading()` returns the brain's last primary request, and a velocity jump bigger than the mover's acceleration drops it. Adds D6: `EnemyMover.requested_velocity()`. **Contains two measurement leftovers to remove before shipping:** the `OS.get_environment("NO_GW")` switch round `_give_way()`, and the `dbg_nudge` field. |
| `routing_variant.patch` | The same squad code without D4–D6. Instead, each lead-in is planned clear of mates' `predicted_position(t)` (priority LEAD < FLANK_LEFT < FLANK_RIGHT < REARs; holding mates and mates on a run, turn or exit are always avoided), and re-checked every 0.2 s. |
| `test_fighter_squad_draft.gd.txt` | The draft `tests/integration/test_fighter_squad.gd` (15 cases, green on the ORCA variant before the harness fix). **It must gain `add_collision_exception_with()` between the spawned fighters** (review B5), plus the review's B2, B4 and B6 changes, before it is committed. |
| `test_fighter_avoidance_draft.gd.txt` | Unit cases for the ORCA variant's `avoidance()` / `_share()` (10/10 green against it). |
| `sweep_harness.gd.txt` | The measurement sweep: a clean harness (collision exceptions), with shipped and wide sets and the SEP / HIT / BREACH / SILENT metrics. It runs against either variant, and against HEAD. Rename it to `tests/integration/test_zz_sweep.gd` to run it, and **delete it again before committing**: the load-integrity gate compiles every `.gd` outside `addons/`. |
