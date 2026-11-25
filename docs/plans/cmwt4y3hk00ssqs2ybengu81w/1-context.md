# Context — t6 Space Fortress movement (task cmwt4y3hk00ssqs2ybengu81w)

The design is the epic's approved plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.6 (with §2.5.5 for the §25 row and §2.16 for the numbers).
This file records what the code gives the task, read @ `2f10b38`.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_fortress/fortress_brain.gd` | t5 shell: `Phase` enum, `bind()`, `tick()` (ticks `BossReinforcements` with `is_engaged()`), `on_boss_phase()`, `on_emp_started()`, `movement_snapshot()` `[]` stub, `is_engaged()` false stub | t6 fills `tick`, `is_engaged`, `on_boss_phase`, `movement_snapshot`; adds facing, spins, OS zone, Assault hold/bob |
| `assault/scenes/enemies/space_fortress/space_fortress.gd` | Root: `_on_phase_entered` sets `Thrusters.visible = true` at `core_exposed` then calls `brain.on_boss_phase(id)` (also for `batteries`, synchronously from `driver.bind` in `_ready`); `phase_snapshot()` reads `brain.movement_snapshot()` and the live `Thrusters.visible` | the movement key; thrusters must not make the snapshot depend on travel state |
| `assault/scenes/enemies/space_fortress/space_fortress.tscn` | `EnemyMover` authors only `constraint_mode = 1` (NONE); `Thrusters`, `CriticalOverlay` empty `Node2D`s | author `turn_lerp = 0.0` explicitly (row 6 reads it) |
| `assault/scenes/enemies/space_fortress/space_fortress_config.gd/.tres` | Flat config | append a `Movement` group |
| `global/enemy_ai/enemy_mover.gd` | `request_velocity`, `face_toward`, `arrive`, `hold_position`, `halt`; `step()` facing: lerp by `turn_lerp` (0 = snap) **then** the `max_turn_rate` cap (`:268-274`); no face request → faces the velocity heading | every motion request; the brain must request a face point every tick or travel would yaw the hull |
| `global/enemy_ai/anchor_idle.gd` | `AnchorIdle(anchor, perceive, lose, notice_time, home_radius)`; distances measured **actor → target**; RETURNING → IDLE inside `home_radius` of the anchor | the OS hub idle and the leash |
| `global/enemy_ai/steering.gd` | `arrive` with accel 0 = full speed to the point; `hold_position` zero inside `tolerance` | HOLD / REPOSITION / RETURNING |
| `assault/scenes/enemies/base_enemy.gd:126-139, 178-189` | One AI tick (brain then mover); EMP window: `mover.halt()`, `brain.on_emp_started()`, brain not ticked, mover still steps with no request (v 0, no face point → no rotation) | row 7 is the base rule; nothing to add |
| `assault/scenes/enemies/carrier/carrier_brain.gd` | Ph10 precedent: `patrol_anchor` INF → spawn, `start_engaged` skips `AnchorIdle` (none built), `_start()` on first tick, mode read there, limit writes on the mover (`max_turn_rate`, `max_speed`) | same shape |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)`, `predicted_position(t)` | the reposition pick's "player 1 s ahead" |
| `open_space/scenes/entities/player/player_ship.gd` (`max_speed` 420, `cruise_speed()`), `assault/scenes/player/player_fighter.gd` (`cruise_speed()` = `MoveState.move_speed` 360) | Player speeds | the circling-wins row reads them from the instantiated scenes |
| `tests/integration/test_space_fortress.gd` | t5's 11 rows; `_spawn` hand-driven (physics off); §25 row with `T5_KEYS` | the movement block and the extended §25 row go here |
| `tests/integration/test_carrier.gd:118-121` | `_tick(c, dt)`: `_physics_process(dt)` then `position = before + velocity * dt` (outside a physics frame `move_and_slide` moves by the idle delta) | the hand-tick helper to copy |
| `tests/integration/test_enemy_mover_single_writer.gd` | Sweeps `*_brain.gd` for `actor.velocity/rotation` writes, `look_at`, `rotate(`, `move_and_slide(` | the brain only requests |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `AnchorIdle` | IDLE / NOTICING / COMBAT / RETURNING with hysteresis, home radius |
| `EnemyMover.face_toward` + `max_turn_rate` (`turn_lerp` 0) | exact rate-limited turns: facing rule, spins, idle spin |
| `EnemyMover.sprite_forward_angle_of(actor)` | the facing formula's `sprite_forward_angle` |
| `Steering.arrive` / `hold_position` via the mover wrappers | travel and hold |
| `ModularHull.module(id)` / `EnemyModule.is_destroyed()` | sector strengths |

## Conventions that constrain this
Single writer (requests and mover-limit field writes only). No `Timer` in brains (clocks are `x -= delta`, over at `<= 1e-6`). Flat config, never write a loaded
resource. §25 keys from phase-driven state only. Both harnesses for every row; hand-ticked. GUT allotment +2.0 s.
