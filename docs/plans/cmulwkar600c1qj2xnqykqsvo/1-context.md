# Context — t10-gatling-windows

This task builds the epic plan's §2.6 (Gatling half) and §2.8 (Gatling rail fallback):
`docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md`, Revision 2, approved with notes N1–N12. Convergence (§2.6.1) is
t11, hub idle is t12, and art is t15. All three are out of scope here.

## Modules and files involved

| Path | What it does today | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/gatling_interceptor/gatling_interceptor.gd` | A legacy rail ship. `_ready()` builds a 20-round pool of the **legacy** `enemy_bullet.tscn` and a self-timed `AttackController` running a `GatlingAttackPattern` (0.09 s, 220 px/s, 0.08 spread, aimed at accuracy 0) | Rewritten in the `fighter.gd` shape: config → mover/pattern/brain, and no per-frame code |
| `…/gatling_interceptor.tscn` | Sprite2D (`interceptor.png`, 64×74), body/HurtBox/ContactHitBox sharing `CircleShape2D_int` r 14 × 1.8, Health, HitFlash | Gains `EnemyMover`, `Brain`, `StateLight`, `StreamPool`, `Attack`. The shape, sprite and node names stay, so every geometry/flip/transparency gate is unaffected |
| `…/gatling_interceptor_config.gd/.tres` | `fire_interval`, `bullet_damage`, `bullet_speed`, `spread_angle` (the legacy weapon), plus HP 70 and score 75 | Becomes the §2.6 config; the legacy weapon fields are renamed `rail_*` |
| `assault/scenes/enemies/fighter/fighter_brain.gd` | The t8b template: lazy `_start()` that builds an `EngagementBudget`, the `enter_phase` seam with `phase_changed(new_phase: int)`, `on_suspended()` installing a rail pattern from config, `_request_disengage()` deferral, `_enter_disengage()`/`_tick_disengage()`, `_heading_ref()`, `_corridor()`, `_set_light()` | The Gatling brain copies its shape (the DISENGAGE exit, the heading reference and the rail hand-back, near verbatim) |
| `global/enemy_ai/enemy_brain.gd` | `actor`, `mover`, `attack` (the first sibling `AttackController`), and a seeded `rng` | The Gatling has one controller, so `attack` is it |
| `global/enemy_ai/burst_clock.gd` | An exact-count burst counter | The stream is a `BurstClock` of N rounds at `stream_interval` |
| `global/enemy_ai/engagement_budget.gd` | `update()` / `remaining()`; INF and never expiring outside Assault | The SWING_IN entry rule reads `remaining()` |
| `global/enemy_ai/steering.gd` | `turn_toward`, `clamped_lead_time` | The only way the brain bends a path (single-writer gate) |
| `global/enemy_ai/enemy_mover.gd` | `request_velocity`, `face_toward`, `release_constraint`, the `max_turn_rate` facing cap | The brain only requests |
| `global/resources/attack/gatling_attack_pattern.gd` | `rng`, `aim_point`, `accuracy`, always-on jitter | Built per instance with the brain's `rng` |
| `assault/scenes/projectiles/enemy_bullet/rounds/gatling_stream_round.tscn`, `enemy_rounds.gd` | Gatling Stream (240 px/s default, 8 s / 1400 px); `EnemyRounds.pool_size_for()` | `StreamPool` holds it; pool sizing uses the formula |
| `global/components/state_light.gd` | OFF / ARMED / CHARGING / COMMIT | CHARGING in SWING_IN and SPIN_UP, ARMED in STREAM |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = x −100..1380, y −380..1100 (centre x 640) | The Assault side rule and the flank-point clamp |
| `tests/integration/test_enemy_bullet_lifetime.gd` | Reads `GatlingInterceptorConfig.new().bullet_speed`; the per-round sweep checks Gatling Stream at its scene default | Switches to `round_speed` / `rail_stream_speed` (AC: no hand-typed or regex speed) |
| `tests/integration/test_level1_fighter_spawns.gd` | `_attack_stats_of()` suspends a ship only if it has `AimedAttack`, then reads the first `BulletPool` / `AttackController`; the frozen legacy constants are asserted equal to this live computation | The Gatling must be read through `suspend_ai()` too. Its live rail rate changes (pool 20 → 36, legacy round → Gatling Stream), so the deep_space equality may move. See the plan's §5 |
| `tests/integration/test_station_reinforcements.gd::test_rail_reinforcements_fire` | LEFT/RIGHT interceptors must fire within 2 s of a rail spawn; `_bullet_pool_of()` takes the first `BulletPool` child; `_interceptor_half_extent()` reads `Sprite2D` | Must stay green through the rail fallback |
| `tests/integration/test_fighter.gd`, `test_enemy_dual_mode.gd`, `tests/helpers/enemy_ai_harness.gd` | The hand-ticked dual-harness pattern (`_tick()` re-integration, label parameters, seeded brains) | `test_gatling_interceptor.gd` follows it |
| Gate rosters: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_config_instance_isolation.gd`, `test_enemy_mover_single_writer.gd`, `test_base_enemy.gd` | The Gatling is already in each roster under its t7 name | They must stay green: flat config, contact damage applied from config, no motion writes outside the mover |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `FighterBrain._enter_disengage()` / `_tick_disengage()` | The Assault exit, copied with the Gatling's own config |
| `FighterBrain._heading_ref()` | `h`: UP in the corridor, else the player's velocity (> 40 px/s) or facing |
| `FighterBrain.on_suspended()` | The rail hand-back shape |
| `Fighter._apply_config()` | The config → mover / pattern / brain wiring shape |
| `BurstClock`, `EngagementBudget`, `StateLight`, `Steering.turn_toward`, `EnemyRounds.pool_size_for` | All as built |
| `test_fighter.gd::_simulate()` | The per-tick log with shots recycled straight back into the pool |

## Conventions that constrain this

- The single writer: the brain requests only (`request_velocity`, `face_toward`, `release_constraint`, and
  `mover.max_speed` on DISENGAGE). The root script writes no velocity or rotation.
- The config is flat and private (`ShipConfig.privatise`). The shared `.tres` is never written, including by tests.
- `BulletPool` is a direct child of the root.
- No `Timer`: the brain accumulates `delta`. Randomness comes only from `rng`.
- Signals are declared with their arity: `phase_changed(new_phase: int)`.
- UIDs: new `ext_resource` lines are UID-less, as in `fighter.tscn`. No `uid://` is typed by hand.
- The Gatling stays out of ENEMIES_CLEARED sections. Level-1 migration is t16; this task leaves level 1 on rails.
