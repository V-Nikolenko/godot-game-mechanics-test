# Context — t8c Swarm Drone squad behaviour

Epic plan: `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.4, §2.7, §2.7.2, §4 row t8c (approved). As-built notes
for t4 (SquadController) and t8b (solo cycle) are in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/swarm_drone/swarm_drone_brain.gd` | Solo ram cycle: APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT, REJOIN, DISENGAGE; already calls `update_target`, `claim_side`/`release_side`, `release_lead` (≥ 2 members), `leave` on DISENGAGE/rails | The brain this task extends with FORM, roles, the window, nudges, per-role budget |
| `assault/scenes/enemies/swarm_drone/swarm_drone_config.gd` / `.tres` | Flat config, t8b rows | Gets the t8c rows |
| `assault/scenes/enemies/swarm_drone/swarm_drone.gd` | Copies config → brain/mover; `squad` slot; joins in `_ready()` | Copies the new fields |
| `global/enemy_ai/squad_controller.gd` | Role board: full recompute on join/leave/release_lead; `attack_window_open` cleared when the LEAD leaves or releases; `claim_side` int API | Read-only use plus at most one shared field (see plan) |
| `global/enemy_ai/engagement_budget.gd` | `seconds`, `update()`, `remaining()` (INF when inactive) | Per-role limit for REAR |
| `global/enemy_ai/steering.gd` | `orbit`, `formation_slot`, `separation`, `alignment`, `cohesion`, `evade` | FORM motion and the nudges |
| `global/enemy_ai/enemy_mover.gd` | `request_velocity`, `add_nudge`, `orbit`, `formation_slot`; `constraint.inner_rect()` | One primary request + one nudge per tick |
| `tests/integration/test_swarm_drone.gd` | 30 t8b cases, hand-ticked and real-physics styles | Extended with the t8c rows |
| `tests/helpers/enemy_ai_harness.gd`, `tests/helpers/contact_fixture.gd` | Dual harness; real player hurtbox + Health | Reused |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `SquadController.role_of / rear_index / members / claim_side / attack_window_open` | Everything FORM needs except a REAR count |
| `SwarmDroneBrain._heading_of`, `_sector_of`, `_side_offset` | Target heading (velocity, else facing), sector, aim offset toward the claimed side |
| `SwarmDroneBrain.can_start_attack()` | Budget gate for a flank's WINDUP too |
| `Steering.orbit` (correction `clamp(d·4, 60, max)`) | REAR ring; anchor lag ≈ tangential speed / 4 |
| `test_swarm_drone.gd` `_harness/_spawn/_tick/_phase_log/_real_player/_real_drone` | Test scaffolding |

## Conventions that constrain this
- Single writer: the brain only requests (`request_velocity` once, `add_nudge`), writes only mover fields; board writes are
  field writes. Gate: `test_enemy_mover_single_writer.gd` sweeps `*_brain.gd`.
- Signal arity gate: any new signal declares its args.
- Tunables are copied by `SwarmDrone._ready()` *after* the brain's `_ready()`; derive nothing tunable-dependent in `_ready()`.
- rng draws only from `rng`; new draws go after the existing `cork_phase`/`_spin` draws so t8b seeds reproduce.
- Config stays flat (`test_config_instance_isolation.gd`); tests write only the private `drone.config` copy.
- Dual-mode tests take a string label and build the harness in the body; run `scripts/check-test-leaks.sh`.
- Hand-ticked tests never step physics, so no overlap is ever reported (every burst misses).
