# Context: Phase 9 t5, EMP really disrupts

Epic plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.6 (with §2.1 clock rule, §2.5 seeker contract, §2.18 gate time).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/components/emp_pulse.gd` | `EmpPulse.emit(tree, at, radius, seconds, source) -> int`: calls `apply_emp` on group `player` within radius (centre distance `<=`). | Gains the trailing `targets` bitmask (player / enemies / seekers). Default must stay bit-identical. |
| `global/entities/player_base.gd` | `apply_emp()` (Ph7 stand-in: `apply_boost_disruption(1.0, s)`), `_step_emp`, `apply_ability_lock()` (t1), `_tick_clock()` (1e-6 rule), `_step_disruption()` calls `_step_ability_lock` then `_step_emp`. | `apply_emp` becomes boost disruption + timed ability lock. Signature, `is_emp_disrupted()`, `emp_changed` unchanged. |
| `assault/scenes/enemies/base_enemy.gd` | `_physics_process`: `if _ai_suspended or _brain == null: return; brain.tick; mover.step`. `suspend_ai()`, `is_ai_driven()`. | Gains `answers_emp()`, `apply_emp()`, `is_emp_disrupted()`, the EMP window clock (skips brain tick, still steps mover), the overlay, and `suspend_ai()` clearing a live window. |
| `global/enemy_ai/enemy_brain.gd` | Brain base: `tick`, `on_suspended`, `accepts_tow`. | New virtual `on_emp_started()` (no-op). |
| `global/enemy_ai/enemy_mover.gd` | `halt()` clears requests / boost / drift and zeroes `actor.velocity`; `step()` with no request moves toward zero, still applies hazard drift and the constraint. | Called on EMP start; stepped through the window. |
| `assault/scenes/enemies/twin_laser_drone/twin_laser_drone_brain.gd`, `twin_laser_pair.gd` | `on_suspended()` -> `pair.release(actor)`; `release()` breaks the pair (`_break_for_good`, beam `cancel()`) and frees the beam when drone A is suspended (nobody would tick its fade). The beam is ticked only from the leader's brain tick (`pair.tick_beam`). | `on_emp_started()` must collapse the pair; when drone A is EMP'd its brain stops ticking, so its FADE beam would freeze on screen: free it as for a suspended A. |
| `assault/scenes/enemies/laser_tender/laser_tender_brain.gd` | Phase `LAUNCH` = the cradle telegraph (`launch_telegraph`), then `_launch()`. `_leave_after_launch` set when the Assault budget expires mid-LAUNCH. `enter_phase()` is the transition seam and updates the light. | `on_emp_started()` cancels a LAUNCH in progress. |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` | Pooled; `reset()`, `launch()`, `is_guiding()`, `_steer()`, `_mark_done()`. `turn_rate > 0` only on guided kinds (Pursuit; Cluster/Warhead per scene). | Joins `enemy_seeking_ordnance` in `launch()` when it steers, leaves in `_mark_done()` / `reset()`, answers `jam_guidance()`. |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | t4's seeker contract incl. `jam_guidance(source)` (drops `locked_target`; on a hijacked rocket ends hijack guidance). | Only consumed by `EmpPulse` TARGET_SEEKERS; not edited. |
| `global/components/seeking_ordnance.gd` | `SeekingOrdnance.GROUP = &"player_seeking_ordnance"`, `eligible()`. | Gets `ENEMY_GROUP = &"enemy_seeking_ordnance"` so the name lives in one place. |
| `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd:392` | EMP branch: `EmpPulse.emit(get_tree(), global_position, emp_radius, emp_seconds, self)`. `enum Hostility { PLAYER, ALL }`. | Passes `TARGET_PLAYER | TARGET_SEEKERS` (enemy-laid) or `TARGET_ALL` (placed). Never names `EnemyMine` inside the file. |
| `global/entities/ability_lock_static.gd` | t2's player overlay: code-built jagged arcs, seeded rng, `step()`. | Shape precedent for the enemy `EmpStatic`. |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `PlayerBase._tick_clock(x, delta)` (static) | The `<= 1e-6` clock rule; BaseEnemy uses the same expression (own const, as `EnemyBeam.EPS`). |
| `TwinLaserPair.release(d)` | Breaking the pair the way a rail does; extended to also free the beam for an EMP'd drone A. |
| `tests/helpers/enemy_ai_harness.gd` | Both harnesses (`open_space()` / `assault()`). |
| `tests/integration/test_fighter.gd` `_spawn`/`_tick`/`_simulate` | Hand-ticked seeded Fighter, shot capture through `AimedPool` / `ForwardPool` `_active` and `_recycle`. |
| `tests/integration/test_twin_laser_drones.gd` `_pair`/`_step`/`_hand_ticked` | Spawning a pair via `twin_laser_pair_spawn.tscn` and hand-ticking it. |
| `tests/integration/test_enemy_shield_hits.gd` `_fire` + 8x clock | A real player `Bullet` on real physics. |
| `tests/integration/test_enemy_rockets.gd` `_hand_rocket` | Hand-ticked pooled-scene rockets (`reset()` + `launch()`). |
| `tests/integration/test_seeking_ordnance.gd` `_hand_rocket` | Hand-ticked homing missile with `locked_target`. |
| `tests/integration/test_enemy_mines.gd` `_variant_mine` / `_tick` | A real EMP mine, `chain_trigger(0.0)`, hand-ticked detonation. |
| `tests/integration/test_player_ability_lock.gd` helpers | Real players, `_tick`, `_lock_log`. |

## Conventions that constrain this
- Only `EnemyMover` writes an AI body's velocity / rotation (`test_enemy_mover_single_writer.gd` sweeps `base_enemy.gd` as an ancestor): BaseEnemy must stop via `mover.halt()`, never `velocity =`.
- Signals declared with arity (`test_signal_emit_arity.gd`); per-frame prints behind `OS.is_stdout_verbose()`.
- `enemy_mine.gd` never names `EnemyMine` (leak at exit).
- IDEAS §21: state on a light / overlay, never a recoloured hull; EMP blue-white `Color(0.7, 0.85, 1.0)`.
- Tests: hand-ticked 1/60; physics rows on real physics at 8x; behaviour rows in both harnesses via `use_parameters(["open_space", "assault"])`.
- t6 (EMPBlastModule routing) and t7 (jammer `answers_emp` override, `HazardField.suppress`, seekers in jammer fields for EnemyRocket) are out of scope.
