# Context — t7 Jamming Structure (Phase 9)

Epic plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.8, §2.9, §2.15 (given to this task in its prompt).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/hazards/hazard_field.gd` | `HazardField`: registers with `Hazards`, cycle TELEGRAPH/ACTIVE/QUIET, `_refresh_info()`; t1 added `disables_abilities` / `stabilise_seconds` (lit only while ACTIVE) | gains `suppress(seconds)` + `is_suppressed()` |
| `global/hazards/hazards.gd` | registry; `jammer_at(pos)` (t1) | the one query rockets / corvette / player use |
| `assault/scenes/enemies/base_enemy.gd` | `answers_emp()`, `apply_emp()`, `is_emp_disrupted()`, EMP clock counted ahead of the no-brain return (t5), `EmpStatic` overlay | jammer overrides `answers_emp()` true and extends `apply_emp` |
| `global/ship_modules/emp_blast_module.gd` | routes by `answers_emp()` (t6) | a jammer goes through `apply_emp`, not the process-disable path |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` | `_tick()` → `if is_guiding(): _steer(delta)` | skip `_steer` inside a lit field behind `Hazards.count() > 0` |
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | `_roll_kind()` (forced → choose_kind → 1-in-4 swap) | downgrade PURSUIT/CLUSTER → DUMB when the player stands in a field |
| `assault/scenes/systems/wave_builder.gd` | path constants and spawn helpers | `JAMMER`, `SECTOR_JAMMER`, `PULSED_JAMMER`, `jammer(variant)` |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | already flies straight in a lit field (t4, `_in_jammer()`) | no change |
| `global/entities/player_base.gd` | ability lock samples `Hazards.jammer_at()` (t1) | no change; the jammer feeds it |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `assault/scenes/enemies/power_source/` | the Ph8 static-structure template: BaseEnemy, no brain/mover, `ContactProfile` NONE, no ContactHitBox, `AssaultDrift`, `is_laser_blocking()` false, joins `enemies`, flat config with `assault_drift_speed`, hit-flash animation |
| `assault/scenes/enemies/heavy_emplacement/` | precedent for a directory with only a scene + config reusing another directory's scripts |
| `assault/scenes/hazards/emp_zone/` (t11) | composition precedent: root + child `Field` (HazardField) + code-drawn art child of `Field` |
| `assault/scenes/structures/turret_group/turret_group.gd:65-68` | the `world_anchored_x` formula, applied once in `_ready()` |
| `global/components/state_light.gd` | the intent light (OFF / ARMED / CHARGING / COMMIT) |
| `global/components/emp_static.gd` | EMP overlay, shown by `BaseEnemy.apply_emp` |
| `tests/helpers/enemy_ai_harness.gd` | both harnesses |
| `tests/integration/test_player_ability_lock.gd` | real-player helpers: `_player`, `_push_h`, `_equip_module`, `_refusal_log` |
| `tests/integration/test_enemy_dual_mode.gd::_fighter_past_a_well` | the Fighter approach used for the avoidance row |
| `tests/integration/test_enemy_rockets.gd::_hand_rocket` | a hand-ticked enemy rocket |
| `tests/integration/test_missile_corvette.gd::test_one_dumb_choice_in_four_becomes_a_pursuit_salvo` | the 200-roll kind loop the downgrade row mirrors |

## Conventions that constrain this
- Static structures (Ph8): `BaseEnemy`, no mover, no brain, `AssaultDrift`, `ContactProfile` NONE, no `ContactHitBox`, `counts_as_escape = false`, joins `enemies` in its own `_ready()`.
- One `*config*.tres` per entity directory (`test_config_instance_isolation.gd`); config flat; never write to a loaded `.tres`.
- `HurtBox` covers the body (`test_enemy_hurtbox_geometry.gd`); no texture painted opaque (placeholder `Polygon2D` has no texture).
- Clock rule `x -= delta`, over at `x <= 1e-6`.
- Hazards sampled by the body; the jammer field `avoid_weight` 0 (enemies ignore it).
- Never hand-type a `uid://`; scenes are written UID-less.
- Roster gates: contact damage (`no_hitbox`), contact geometry (`no_hitbox`), hurtbox geometry, base-enemy authored contact modes and `_MIN_ROSTER_SIZE`, dual-mode spawn row, `ENEMIES_CLEARED` guard row.
