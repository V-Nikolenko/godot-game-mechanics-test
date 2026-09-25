# Context — t10-brain-mover

Epic plan: `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.2 (tick), §2.3 (EnemyBrain), §2.4 (Steering +
EnemyMover + single-writer gate), §2.10 (suspend_ai), P-9, P-10; epic review round 2 N2 (sweep shape) and N7.
Checked on `agent/auto-dev` @ `4bb244a`.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | Base of every assault enemy; `_ready()` wires Health/HurtBox/DefenseProfile; no `_physics_process` today | Gains the brain→mover physics tick, `suspend_ai()`, by-type resolution of `EnemyBrain`/`EnemyMover` |
| `assault/scenes/enemies/enemy_path_mover.gd` | Rail driver; `_ready()` does `set_physics_process(false)` + `"AIStateMachine"` name lookup (lines 60-65) | Gains an **additional, unconditional** `_actor.suspend_ai()` call when present |
| subclasses with their own `_physics_process`: bomber, gunship, kamikaze_drone, ram_ship, sniper_enemy, drone_interceptor | GDScript 4 does not chain virtual callbacks, so an override fully replaces `BaseEnemy._physics_process` | Must stay byte-identical; pinned by t1/t3 tests |
| subclasses without one: light_assault_ship, interceptor, bonus_drone, space_station | Will now inherit `BaseEnemy._physics_process` | Must be inert (no brain → early return) |
| `light_assault_ship.tscn` `AIStateMachine` | `StateMachine` ticks states from `_process`; states write `actor.velocity` + `move_and_slide()` | Why the name lookup must stay unconditional (F3) |
| `global/enemy_ai/enemy_world.gd` | Only lookup of the `&"assault_arena"` provider; `movement_constraint(tree) -> Object` (null until t11) | `EnemyMover` AUTO mode resolves through it |
| `global/enemy_ai/steering.gd` | Pure primitives returning desired velocity | Mover wrappers call these; no duplication |
| `global/enemy_ai/target_info.gd` | Target snapshot; has `info.velocity = ...` | Must NOT trip the single-writer sweep (N2: receiver-scoped regex) |
| `global/components/attack_controller.gd` | Pattern+pool timer; `driven_by_brain` + `tick()` + `fire_now()` (t8) | Brain resolves it by type; nothing to add |
| `tests/integration/test_enemy_path_mover.gd` | t2 pins incl. real `light_assault_ship.tscn` | Must stay green **unchanged** |
| `tests/integration/test_ship_rotation_single_writer.gd` | Precedent source sweep | Style for the new mover single-writer gate |
| `tests/integration/test_project_load_integrity.gd` | Loads every .tscn/.tres/.gd under res:// (incl. `tests/`), zero engine errors/warnings | New scripts and the fixture `.tscn` must load clean; UID-less ext_resources are legal |
| `tests/helpers/path_mover_actor.gd` | Bare CharacterBody2D fixture, no `class_name`, preload-only | Pattern for the new fixture files |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `Steering.*` | seek/arrive/orbit/intercept/evade/retreat_from/strafe/hold_position/drift — mover wrappers are one-liners over these |
| `EnemyWorld.movement_constraint(tree)` | AUTO resolution; returns null today (t4b provider lacks the method until t11) |
| `AttackController.driven_by_brain/tick()` | Brain-clocked fire, already built |
| `ShipTurnController` precedent | by-type child resolution, "only writer of rotation" |
| `test_ship_rotation_single_writer.gd` | regex + roster-non-empty boundary shape |
| drone_interceptor.tscn | template for a hand-written BaseEnemy scene (Health, HurtBox, HitFlashAnimationPlayer with a `hit` animation) |

## Conventions that constrain this
- Composition: brain and mover are child `Node`s resolved by type, not inheritance.
- Physics-tick with accumulated delta, seeded `RandomNumberGenerator`, no `Timer` (P-9; GUT `simulate()` doesn't fire Timers).
- `global/` must not name Assault classes: `EnemyBrain.actor: CharacterBody2D`, `sprite_forward_angle` duck-typed (F11).
- Signals declared with emitted args (none planned here). Verbose-gated per-frame logging.
- Never hand-type a `uid://`: fixture `.tscn` ext_resources are UID-less.
- `test_project_load_integrity`: bare load must log no warning; the mover's bad-parent warning happens in `_ready()` only, never at load.
