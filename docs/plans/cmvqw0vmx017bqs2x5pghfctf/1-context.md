# Context — t2: the `EnemyBeam` core (epic cmug23ona0015m52w4t1m73bc, plan §2.1–§2.3)

The design is the epic's approved plan (`docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.1 / §2.2 / §2.3 and "For every task").
This file records only what the code says about it; nothing here re-decides the design.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/hazards/laser_ray/laser_ray.gd` | Level 1 / race / station laser: 9999 one-hit, sprite-driven phases, `Timer` re-damage | Stays byte-identical (acceptance); the new beam sits beside it, never edits it |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` (+ tests) | Station boss beam | Untouched (acceptance) |
| `global/hazards/hazards.gd` | `Hazards.hurt_box_of(ship)` (property `hurt_box`, else child `HurtBox`), `pulse_damage` (a direct-emit precedent) | Delivery goes through `hurt_box_of` |
| `global/components/hurtbox_component.gd` | `HurtBox.received_damage(damage: int)`; absorber hook only on `area_entered` | A direct `received_damage.emit` bypasses `EnemyShield` (absorber) — the documented "direct emitter" path |
| `global/entities/player_base.gd` | `invincibility_sec` export 0.5 (script default; neither player scene overrides it), one-shot idle `Timer` started in `_start_invincibility()`; shield charge consumed first | Rehit 0.55 > 0.5 row; cadence row on real frames |
| `assault/scenes/player/player_fighter.tscn` | HurtBox: `CircleShape2D` r 5, node scale 2.7, position (0, 1); `MoveState.move_speed` script default 360 | `r_p` and `v_c` of the fairness rows (read from the scene instance, never typed) |
| `open_space/scenes/entities/player/player_ship.tscn` | Health 50, HurtBox → `_on_received_damage` → `_apply_damage` | Open Space cadence / victim rows |
| `assault/scenes/allies/ally_fighter/ally_fighter.tscn` | Joins `allies` in `_ready()`, child `HurtBox` (HurtBox script) | Victim row (Assault harness) |
| `assault/scenes/hazards/big_asteroid/big_asteroid.tscn` | `AsteroidBase` joins `asteroids`, `hurt_box` property | Victim row |
| `assault/scenes/enemies/ram_corvette/ram_corvette.gd:128` | `_on_received_damage` refuses every hit while `is_armored()` | Plated-Ram row: delivered, 0 health damage |
| `assault/scenes/enemies/base_enemy.gd:234` | `_on_health_changed` sets `was_killed` on 0 | Scoring row |
| `global/components/enemy_shield.gd` | Sustained bubble via `attach()` + `sustain_mode` | Shield-bypass row |
| `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`, `enemy_rockets/enemy_rocket.gd` | Neither joins `player`/`allies`/`enemies`/`asteroids` | Ordnance row: never a candidate |
| `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine_scenes.gd` | `scene_for` / `export_of` through `PackedScene.get_state()` | The `EnemyBeamScenes` shape |
| `assault/scenes/enemies/mine_layer/mine_wake.gd` (`MineWake`) | Code-built `Line2D`, owner-stepped clock, no Timer | Drawing / clock precedent |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a fake player | Both-harness rows |
| `tests/helpers/fixture_enemy.tscn` | `BaseEnemy` fixture, HurtBox with no shape, Health 10 | Victim fixture (14 px circle added at runtime, `enemies` group at runtime) |
| `tests/integration/test_enemy_mines.gd`, `test_enemy_rockets.gd` | `_scale_clock()` / `_restore_clock()` (8×), `_Ticker`, real-player rows (`shield_component.set_all_zero()`) | Patterns reused verbatim |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `Shape2D.collide(xform, shape, shape_xform)` (engine) | Exact shape test without a physics step. Checked in a scratch run: circle vs band exact at ±0.5 px, a 2.7-scaled circle exact at ±1 px, a 96 × 44 rectangle rotated 90° at 40 px hits a ±12 px band and unrotated misses, a `ConvexPolygonShape2D` triangle hits |
| `Hazards.hurt_box_of` | Hurtbox lookup for every victim kind |
| `EnemyMineScenes.export_of` | The `get_state()` reading shape for `EnemyBeamScenes.export_of` |
| `StateLight` | Not used by the beam (the host sets it, §2.3) — nothing to build |

## Conventions that constrain this
- Owner-driven clock: `tick(delta)` is the only clock; no `Timer`, `create_timer` or `_process` clock (`self_tick` export calls `tick` from `_physics_process` for props only).
- Weapon numbers only in scene exports; gates read them via `EnemyBeamScenes.export_of`; no typed copies in the suite.
- Signals declared with arity (`test_signal_emit_arity.gd` sweeps self-emits).
- Per-frame prints behind `OS.is_stdout_verbose()`.
- No `uid://` typed by hand: new `.tscn` files reference scripts by path only.
- `test_project_load_integrity.gd` loads/instantiates every new `.tscn`/`.gd` — no warnings allowed (unused params prefixed `_`, typed code).
- Tests: GUT, both harnesses parameterised on a label string; per-tick drivers are `_Ticker` children; 8× clock for real-frame rows.
- Gate time allotment for this task: +2.0 s GUT (baseline measured 200.30 s → ceiling 202.3 s for this task).
