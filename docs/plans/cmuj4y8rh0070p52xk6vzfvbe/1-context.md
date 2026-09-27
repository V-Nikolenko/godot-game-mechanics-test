# Context — t8b Swarm Drone solo cycle

The epic plan (`docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.2, §2.3, §2.6, §2.7, §2.7.1, §4 row
`test_swarm_drone.gd (t8b)`) is the approved design. This file lists only what the code offers today.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`: resolves `ContactProfile`, brain/mover tick in `_physics_process`, `suspend_ai()` arms the profile, death → `was_killed`, `queue_free` | `SwarmDrone extends BaseEnemy`; must NOT override `_physics_process` |
| `assault/scenes/enemies/drone_interceptor/*` | Phase-1 ported brain enemy: scene layout, config copy in `_ready()`, brain enum phases | Template for the scene/script/config layout |
| `assault/scenes/enemies/kamikaze_drone/*` | Legacy drone: `drones.png` (126×84, 3×2 cells of 42×28), config 30 HP / 30 dmg / 10 score | Placeholder art cell; parity stats |
| `global/enemy_ai/enemy_brain.gd` | `EnemyBrain`: `actor`, `mover`, `rng` (seeded in `_ready`) | Base of `SwarmDroneBrain` |
| `global/enemy_ai/enemy_mover.gd` | request/nudge/boost/face; `step()` = `move_toward` with accel/braking, constraint filter, facing; `release_constraint()` | The only motion writer; `max_turn_rate` turns the sprite only (D7) |
| `global/enemy_ai/steering.gd` | `corkscrew`, `spiral`, `clamped_lead_time`, `turn_toward`, `hold_position`, `seek` | All primitives this brain needs already exist and are unit-tested |
| `global/enemy_ai/engagement_budget.gd` | `EngagementBudget(seconds, tree)`, `active` only with an arena provider | Assault DISENGAGE clock |
| `global/enemy_ai/enemy_world.gd` | `arena()`, `projectile_world_rect()` | DISENGAGE exit target and free rule |
| `global/enemy_ai/squad_controller.gd` | `join/leave/claim_side/release_side/release_lead/update_target` | Called when `squad != null`; roles are t8c's |
| `global/enemy_ai/target_info.gd` | `player(tree)`, `predicted_position(t)`, `velocity`, `facing` | Perception and prediction |
| `global/components/contact_profile.gd` | EXPLOSIVE: armed-only hitbox, `detonate()` on contact or death-while-armed, `contact_made` | Scene-authored child, EXPLOSIVE, blast 48 / 15 |
| `global/components/state_light.gd` | `set_state(OFF/ARMED/CHARGING/COMMIT)`, code-built texture | CHARGING in WINDUP, ARMED in BURST |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis velocity filter, entry latch, hard band 450 | Assault harness behaviour |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` dual harness (fake player CharacterBody2D, optional `ArenaCamera`) |
| `tests/integration/test_enemy_dual_mode.gd` `_tick()` | Manual tick with exact `delta·velocity` integration (move_and_slide delta drift) |
| `tests/helpers/contact_fixture.gd` `build_player()` | Real player `HurtBox` (layer 128, mask 1281) → `Health.decrease` |
| `tests/integration/test_contact_blast_damage.gd` | Pattern for a real-physics blast test (`wait_physics_frames`) |
| `tests/integration/test_engagement_deadline.gd` | t6 deadline test, constants to repoint at `swarm_drone_config.tres` |
| Gate rosters: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` | Hand rosters + completeness guards that will fail until `swarm_drone` is added |

## Conventions that constrain this
- Single writer: the brain requests only (`test_enemy_mover_single_writer.gd` sweeps `*_brain.gd` and mover-driven roots).
- Brain clock = accumulated `delta`; randomness from `rng` only; no `Timer`/`create_timer`.
- Config: flat `@export_group`s on a `ShipConfig` subclass; the `.tres` is shared — never written; `BaseEnemy` privatises.
- Signals declared with their emitted arity.
- Contact hitbox + hurtbox share the body `SubResource` shape id and scale (geometry gates).
- UIDs: no hand-typed `uid://`; leave new references UID-less.
- Open-question resolved from review round 2 (B5, never folded into the epic plan): with `braking` 500 the overshoot turns only ~44°; the plan must pick values that reach ≥ 60°.
