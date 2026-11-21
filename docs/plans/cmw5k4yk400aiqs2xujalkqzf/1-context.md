# Context — Hacker Frigate shell and movement (Phase 9 t8)

Epic plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.10 (this task), §2.15 (roster gates), §2.18 (gate time), §2.19 (numbers).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | HOLD_ARC (`_arc_motion`: `_orbit_angle += dir·speed·dt`, `Steering.orbit`, drift `sin`, reversals from `rng`), DISENGAGE (nearest-edge curve at `exit_speed`), hub idle via `AnchorIdle`, `enter_phase()` as the one transition | The pattern HOLD_ARC / DISENGAGE / idle are copied from (copy, not inherit) |
| `assault/scenes/enemies/support_ship/support_ship_brain.gd` `_clamp_into_view()` (l. 502) | Clamps a target point into `EnemyWorld.view_rect().grow(-view_margin)` | The Assault view clamp |
| `global/enemy_ai/enemy_mover.gd` | `step()`: `current.move_toward(desired, acceleration·dt)`; `boost(dir, speed, s)` ignores `max_speed` and the accel limit; `face_toward` | The cone-exit maths and the committed break-off |
| `global/enemy_ai/steering.gd` | `orbit()` (anchor correction `clamp(4·dist, 60, max)`), `break_contact(..., lateral_weight)` (lateral doubled against a closing threat), `turn_toward()` | Motion primitives, no new maths |
| `global/enemy_ai/anchor_idle.gd`, `engagement_budget.gd`, `target_info.gd` | Hub idle meta-state; Assault budget (`active` only with an arena); player snapshot (`facing = UP.rotated(rotation)`, `velocity`) | Idle, DISENGAGE timing, the cones' axes |
| `assault/scenes/enemies/base_enemy.gd` | Shared brain → mover tick, `privatise()` of `config` in `_init` / `_enter_tree`, `accept_tow`, EMP window | The root extends it; tests write `config` fields after `instantiate()` |
| `assault/scenes/enemies/laser_tender/laser_tender.tscn` / `.gd` | The latest mover-driven ship scene: shared r 40 circle, authored `ContactProfile` mode 1 (COLLISION), `StateLight`, `_apply_config` | Scene template |
| `assault/scenes/systems/wave_builder.gd` | Scene-path constants + spawn helpers | `HACKER_FRIGATE`, `hacker_frigate()` |
| `tests/helpers/specialist_exit_probe.gd`, `tests/helpers/ph8_exit_keys.gd` | Measured DISENGAGE over `corridor_starts()`, memoised on every input incl. a static `prepare` Callable | `ph9_exit_keys.gd` copies the Ph8 file's shape |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a bare player body | Both-harness rows |
| `tests/integration/test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd` (`_MIN_ROSTER_SIZE`, `_AUTHORED_CONTACT_MODES`, `_REFUSING_PHASES`), `test_enemy_dual_mode.gd` (`HAZARD_PROFILES` + one spawn row), `test_engagement_deadline.gd` (ENEMIES_CLEARED guard rows) | Roster gates | Each gets the Hacker |
| `tests/integration/test_laser_tender.gd` l. 1146-1277 | Ph8 exit-key memo row and source sweep | Mirrored for the Ph9 keys |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `Steering.orbit` / `Steering.break_contact` / `Steering.turn_toward` | Orbit anchor correction, break-off direction with `lateral_weight` 0.25, DISENGAGE curve |
| `EnemyMover.boost` | The Open Space committed break-off at 360 px/s |
| `AnchorIdle` | IDLE / NOTICING / COMBAT / RETURNING |
| `EngagementBudget` | 9.0 s Assault life |
| `StateLight` (`global/components/state_light.gd`) | Light on the dish |
| `SpecialistExitProbe.worst_disengage` + `corridor_starts` | The measured exit |
| `test_enemy_mover_single_writer.gd`, `test_config_instance_isolation.gd`, `test_entity_sprite_transparency.gd`, `test_project_load_integrity.gd` | Automatic sweeps the new files join with no edit |

## Conventions that constrain this
- Brain ticks only from `BaseEnemy._physics_process`; only `EnemyMover` writes velocity / rotation; committed move = `mover.boost()`; randomness only `brain.rng`.
- Flat config (`@export_group`s of plain numbers), one `*config*.tres` per directory; `.tres` wins in `_ready()`.
- `enum Phase` append-only; `phase_changed(new_phase: int)` declared with its arity.
- No `uid://` typed by hand; scenes written UID-less.
- Hull art nose-down (`sprite_forward_angle` PI/2); placeholder until t12; state shows on a light / part.
- Tests hand-ticked at 1/60 (`_physics_process(dt)` then `position = before + velocity·dt`, the corvette tests' `_tick`), both harnesses label-parameterised.
- Gate time budget: t8 allotment 4.0 s.
