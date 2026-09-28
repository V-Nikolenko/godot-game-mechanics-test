# Context — Razor Drone combat (t10)

Epic plan: `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.8.2–§2.8.3 (approved), §4 row
`test_razor_drone.gd` (t10), D5. DECISIONS.md Phase 2 sections t3, t4, t8b, t8c, t8d are the as-built record
this task builds on.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/razor_drone/razor_drone.gd` | `RazorDrone` root: copies config onto the brain; `contact_hit_box.area_entered` → `health.set_health(0)` (self-kill) | Self-kill is removed; config copy grows; pattern built here |
| `.../razor_drone_brain.gd` | `RazorDroneBrain`: ENTER/ORBIT/DASH, `_begin_dash()`, `_check_dash_end()` (cull rect / `dash_max_distance` free) | Rewritten to the §2.8.2 state machine |
| `.../razor_drone_config.gd/.tres` | Flat `ShipConfig` subclass | §2.8.3 fields added, `dash_max_distance` removed, mover fields added |
| `.../razor_drone.tscn` | Root, sprite, hurtbox, contact hitbox (r 3.08 scale, shared shape), `EnemyMover` (`turn_lerp` 7, `constraint_mode` 1 = NONE, accel 0), Brain | Gets `ContactProfile` (RAMMING), `StateLight`, `BulletPool`, `AttackController`; mover re-pinned |
| `.../ENEMY.md` | Per-entity doc | Rewritten for the new behaviour |
| `tests/integration/test_razor_drone.gd` | Phase-1 1:1 pins (ENTER speed, orbit clamp, 1–2 s dash onset, dash dir, contact kill, facing, cull rect) | Rewritten as Razor pins + §4 t10 cases |
| `tests/integration/test_enemy_dual_mode.gd` | Three Razor cases: identical orbit in both modes, identical dash dir, OS dash frees past `dash_max_distance` | Re-pinned "identical relative to the constraint"; the free case becomes "survives" |
| `tests/integration/test_base_enemy.gd` | `_AUTHORED_CONTACT_MODES` map | + `razor_drone → RAMMING` |
| `tests/integration/test_engagement_deadline.gd` | §2.6 formula, swarm config for every drone/razor | Razor spawns should use the Razor config (plan §2.6 claim) |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `swarm_drone_brain.gd` | The whole pattern: `phase_changed` + `enter_phase()` seam, lazy `_start()` (config copied after brain `_ready`), `EngagementBudget` DISENGAGE with nearest-edge exit and strict world-rect free, `_ring_centre()` inner-rect clamp, `turn_toward` overshoot from the actor's current velocity, `_set_light` / `_set_armed` duck-typed helpers, WINDUP `_hold_at` stopping point |
| `global/components/contact_profile.gd` | RAMMING: hitbox on only while armed (deferred), `contact_made` only while armed |
| `global/components/state_light.gd` | OFF / ARMED / CHARGING / COMMIT, `get_state()` |
| `global/components/attack_controller.gd` | `driven_by_brain`, `enabled`, `fire_now()` (ignores enabled) |
| `global/resources/attack/aimed_attack_pattern.gd` | `bullet_damage`, `bullet_speed`, `accuracy`, `spawn_offset` (world-space) |
| `global/components/bullet_pool.gd` | container = grandparent; idle bullets are its children (acquired ones reparent out) |
| `global/enemy_ai/steering.gd` | `orbit` (velocity toward the anchor point, clamp(4·d, 60, max)), `turn_toward` |
| `global/enemy_ai/enemy_mover.gd` | `boost`, `is_boosting`, `hold_position`, `arrive`, `release_constraint`, `constraint.inner_rect()` |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` |
| `tests/integration/test_swarm_drone.gd` | `_tick()` exact integration, overshoot-curve assertion shape, exit-rect assertion, `_phase_log` |
| `tests/helpers/contact_fixture.gd` | real player (`build_player`) for a real-physics contact case |

## Conventions that constrain this
- Brain requests only; mover is the single writer (gate). Field writes (`max_speed`, `release_constraint`) are allowed.
- No `Timer`s; accumulate delta. `rng` only. `super._ready()` first.
- Config flat; never write the preloaded `.tres` in tests (write `drone.config`, the private copy, before `add_child`).
- Root `_ready()` runs after the brain's `_ready()` → derive tunables lazily on the first tick.
- Signals declared with their arity. Per-frame prints behind `OS.is_stdout_verbose()`.
- Cross-script nested enums: pass as `int`.
- Hand-ticked tests have no physics step: contact must be simulated (`contact_hit_box.area_entered.emit` while armed) or run in a real-physics world.
