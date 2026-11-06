# Context — t11: Mine Layer passes (the combat AI)

Epic plan `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.12 (with "For every task", §2.1, §2.3, §2.11, §2.17) is the approved
design. This file records what the code looks like today (`c3ec47f`, `agent/auto-dev`) where §2.12 touches it.

## Modules and files involved

| Path | What it does today | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/mine_layer/mine_layer_brain.gd` | t10 shell: full `Phase` enum, `phase_changed(new_phase: int)`, `enter_phase()`, `start_engaged`, `budget`; plays APPROACH (`mover.seek(player, max_speed)`) and DISENGAGE (`release_constraint()`, `max_speed = exit_speed`, exit along the heading fixed on entry, free outside `projectile_world_rect()`); `accepts_tow()` false in LAY | The file this task fills in |
| `assault/scenes/enemies/mine_layer/mine_layer.gd` | `MineLayer extends BaseEnemy`; `_apply_config()` copies speeds onto the mover and the private config onto the brain (same object); `drop_mine(variant, rest_point) -> EnemyMine` (eject `2d / (eject_time − 1 tick)`, life by mode, PROXIMITY fallback, null when nothing left); `_process` rail clock; `dispenser` Marker2D at local (0, −38) | The brain drops every mine through `drop_mine()` |
| `assault/scenes/enemies/mine_layer/mine_layer_config.gd/.tres` | Flat `MineLayerConfig`: Movement, Mines (`max_live_mines` 18, `assault_max_live_mines` 8, `w_*`), Engagement, Rail. The `.tres` sets only `ShipConfig` fields; every other value is the script default | The passes task adds its own `@export_group("Passes")` |
| `assault/scenes/enemies/mine_layer/mine_layer.tscn` | Root pools Proximity 20 / Chain 6 / Pulse 5 / Homing 5 (`persist_after_owner_death`); `Brain` and `EnemyMover` (`constraint_mode` AUTO) | Pools are children of the layer; acquired mines are reparented to the layer's parent (`BulletPool._container`) |
| `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd` | `EnemyMine`; `retire()`, `is_fizzling()`, `trigger_radius`, `hazard_info()`; privates `_launched`, `_done`, `_fizzling` | The live-mine FIFO needs a public "is this life still live" query; none exists (`is_fizzling()` only) |
| `assault/scenes/enemies/bomber/bomber_brain.gd` | `_update_prediction()` (EMA, seeded from the first sample, `alpha = 1 − exp(−delta / velocity_smoothing)`); `_solve_arrival()` (scan `ARRIVAL_SCAN_STEP` 0.1 up to the cap, then `ARRIVAL_BISECTIONS` 5); `_tick_reposition()` (orbit with `REPOSITION_LEAD` 0.4 + `turn_toward`); `_enter_disengage()` | The shapes §2.12 reuses, re-declared in `MineLayerBrain` |
| `global/enemy_ai/enemy_mover.gd` | Single writer; `request_velocity`, `seek`, `orbit`, `break_contact`, `boost(dir, speed, duration)`, `own_velocity()`, `release_constraint()`, `constraint_released()`. Velocity direction is limited only by `acceleration` (420); `max_turn_rate` caps the sprite rotation only. Avoidance stage runs unless boosting | Every request goes through it |
| `global/enemy_ai/steering.gd` | `break_contact(pos, threat, threat_vel, side, speed)`, `orbit`, `turn_toward`, `context_avoid` | BREAK_OFF / REPOSITION |
| `global/enemy_ai/target_info.gd`, `enemy_world.gd`, `engagement_budget.gd` | `TargetInfo.player(tree)` (`.position` / `.velocity`); `EnemyWorld.view_rect(tree)` (Assault camera rect, 1280 × 720 at (0, 0) in the harness); `EngagementBudget` active only in Assault | Frame, Assault clamp, budget deferral |
| `global/hazards/hazards.gd` | `Hazards.around(pos, reach)` returns `HazardInfo`s (mines: `kind &"mine"`, `source` the mine) | No-stacking check against every live mine, not only this layer's |
| `global/components/bullet_pool.gd` | `acquire()` reparents to the container and `reset()`s; `expired` → **deferred** `_recycle()` | A hand-ticked loop that never yields never recycles: long scenarios must let a frame pass now and then |
| `tests/integration/test_mine_layer.gd` | 17 t10 rows; `_world(mode)`, `_spawn()`, `_tick()` (calls `_physics_process` and integrates `velocity`), `_player_stub()` | The §2.12 rows go here |
| `tests/integration/test_enemy_dual_mode.gd:1056-1080` | `test_mine_layer_approach_closes_on_the_player`: layer at (640, 60), player at (640, 360), asserts the gap to the **player** closes by > 60 px in 1 s | After §2.12 APPROACH seeks the run-in point R, not the player; this row's premise changes |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `BomberBrain._update_prediction()` | v̄ EMA shape (copied, not called: brains share no base beyond `EnemyBrain`) |
| `BomberBrain._solve_arrival()` | Scan + bisection shape (constants re-declared, as §2.12 says) |
| `BomberBrain._tick_reposition()` / `_enter_reposition()` | Orbit-at-standoff shape |
| `MineLayer.drop_mine()` | All mine configuration; the brain never touches a mine's numbers |
| `EnemyMine.retire()` | Live-cap retirement |
| `EnemyMover.break_contact()` / `orbit()` / `boost()` | BREAK_OFF, REPOSITION, and the pre-approved LAY lever |
| `tests/helpers/enemy_ai_harness.gd` | Both harnesses; the bare `player` body is the standing / moving stub |

## Conventions that constrain this

- Brains request, the mover writes (gated by `test_enemy_mover_single_writer.gd`: no `velocity` / `rotation` / `move_and_slide` in a `*_brain.gd`).
  Field writes `mover.max_speed` and `release_constraint()` are allowed (DISENGAGE already does them).
- Accumulated-delta clocks, no `Timer`; randomness only from `brain.rng`.
- `enemy_mine.gd` must not name its own class (t4 trap); other files may type `EnemyMine`.
- Signals declared with their arity (`test_signal_emit_arity.gd`); per-tick prints behind `OS.is_stdout_verbose()`.
- The instance's `config` is a private copy (`ShipConfig.privatise()`), so a test may write `layer.config.<field>` before the first tick;
  never write the preloaded `.tres`.
- Gate time: t11 allotment 4.5 s (§2.17); baseline measured now: **GUT 207.98 s, 2272 tests** (`scripts/gate-time.sh` on `c3ec47f`).
