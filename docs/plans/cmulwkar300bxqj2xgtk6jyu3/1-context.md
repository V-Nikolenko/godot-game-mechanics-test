# Context — t9-fighter-squad

Builds epic plan `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` (Revision 2) §2.5 on top of t8b
(`docs/plans/cmulwkar000btqj2x1e58sfd4/`, as built in DECISIONS "Phase 3, built in t8b"). The epic's research
(`2-research.md` finding 1: three-attacker cap) is not repeated.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/fighter/fighter_brain.gd` | t8b attack run: `_derive_pass` (re-derived every tick until RUN_IN, latched RUN_IN → EXTEND end), `_kind_for` (forced seam / solo alternation), Dubins lead-ins, TURN turn-in + break-away, REPOSITION with the Open Space regroup loiter (`_loiter_time`), weapons layer (`_try_open_burst`) | Every t9 change lands here: role → kind, the window, the hold at S, dry REAR passes |
| `assault/scenes/enemies/fighter/fighter.gd` | Root; copies config; no `squad` property yet | Needs the duck-typed `squad` slot and the `_ready()` join (Swarm precedent) |
| `assault/scenes/enemies/fighter/fighter_config.gd/.tres` | Already has `rear_standoff_radius` 560 and `flank_wait_max` 2.0 (t8a) | `flank_stagger` would be new, only if separation fails |
| `global/enemy_ai/squad_controller.gd` | Role board: `_reassign()` full recompute by distance on join/leave/prune; closes `attack_window_open` on any LEAD change; `rear_index/rear_count/member_count` | Used as is (epic X6: nothing new for fighters) |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Stamps `squad_key`, resolves one board per formation, writes `entity.squad` before `add_child`; stagger delays `await create_timer` | The real spawn path the test must use; delays > 0 would leak timers (tests/README) — use stagger 0 |
| `assault/scenes/systems/wave_builder.gd` | `fighter()`, `v_formation()`, `w_formation()` | V3 / W5 layouts |
| `assault/scenes/enemies/swarm_drone/swarm_drone_brain.gd` | The Ph2 squad precedent: `_answered_window` reset on reading the window closed; LEAD opens only while it leads; `_pass_role`; leave on DISENGAGE / suspension | Pattern to copy |
| `tests/integration/test_fighter.gd` | Hand-tick harness, `_simulate`, shot recording | Helpers to mirror in the new test file |
| `tests/integration/test_wave_squads.gd` | Real `WaveManager` + camera fixture | How to drive a real WaveManager without timers |
| `tests/helpers/enemy_ai_harness.gd` | Open Space / Assault worlds | Dual harness; Open Space needs its own `Camera2D` for `_spawn_ship()` |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `SquadController.role_of/members/rear_index/rear_count/attack_window_open` | Roles, REAR spacing, the window flag with its LEAD-change auto-close |
| `FighterBrain._derive_pass`, `_clamp_run`, lane flip rules | Pass geometry for every role, corridor rules included |
| `FighterBrain._tick_loiter` | Hold at S: `v_P + capped correction`, nose along `u` |
| `FighterBrain._fly_to_start` / `_best_path` | REPOSITION routing clear of `reposition_min_radius` |
| `FighterBrain.forced_pass_kind` | Existing role-shaped lane seam (FLANK_RIGHT outer lane) |
| `SwarmDrone._ready()` | `update_target` then `join` |

## Conventions that constrain this

- Single writer: brain only requests through `EnemyMover` (`test_enemy_mover_single_writer.gd`).
- Signal arity: any new signal declares its args.
- Config flat; shipped `.tres` never written by tests (private copy only).
- Roles are read every tick, never cached (Ph2 t4).
- A formation is one squad; loose entries are squads of one (so a solo fighter's `role_of` is LEAD with
  `member_count() == 1`, and must keep t8b's solo alternation).
- WaveManager delays use `SceneTreeTimer`: tests use stagger 0 (tests/README leak trap).
