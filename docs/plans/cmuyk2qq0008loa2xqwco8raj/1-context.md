# Context — t13 Sniper cycle (task `cmuyk2qq0008loa2xqwco8raj`)

Epic `cmufs7ele0015nm2xvag3vrwc` (Enemy rework phase 4). The epic's approved plan is
`docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2); this task builds its §2.5 cycle and the sniper row of
§2.9.4, and the t13 row of §4. This file records only what the code says today; it does not repeat the epic plan.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/sniper/sniper_brain.gd` | `SniperBrain` (t12 shell): `Phase` enum with all nine phases, ENTER (seek `nearest_firing_point()` with an arrival latch), `EngagementBudget`, DISENGAGE (nearest world-rect edge), `on_suspended()` → telegraph rail cycle | The file this task fills in. `_request_disengage()` already carries the "t13: defer in AIM/LOCK" comment. |
| `assault/scenes/enemies/sniper/sniper_telegraph.gd` | `SniperTelegraph`: `show_line(point, locked)`, `hide_line()`, `line_points()`, the rail fallback (`_process`) | The AI cycle draws through `show_line`. No decoy colour yet (t14). |
| `assault/scenes/enemies/sniper/sniper.gd` | Root script; `_apply_config()` wires config, telegraph, muzzle and pool | Must also hand the brain the muzzle, pool and barrel. |
| `assault/scenes/enemies/sniper/sniper.tscn` | `Brain`, `EnemyMover` (AUTO), `StateLight`, `RailPool` (rail round, size 2), `Telegraph`, `Barrel` (placeholder gradient, at (0, −14)), `Muzzle` (0, −20); art points up (`sprite_forward_angle = −PI/2`) | Barrel starts unfolded today; the cycle needs it folded at rest. |
| `assault/scenes/enemies/sniper/sniper_config.gd/.tres` | Flat `SniperConfig`; every §2.5 field already exists (ranges, filters, weights, caps, aim/lock, rail speed/damage, `trail_fade`) | New fields this task needs: `break_min`, `velocity_smoothing`, `barrel_unfold_seconds`, `barrel_fold_seconds`, `candidate_count`, `max_los_rays`, `seed_jitter_deg`. |
| `assault/scenes/projectiles/enemy_bullet/rounds/rail_round.tscn` | 2200 px/s, damage 28, `ProjectileLifetime` 4 s / 2400 px, `expired` signal from `EnemyBullet` | The FIRE round; `RailTrail` follows it. |
| `global/components/bullet_pool.gd` | `acquire()`, `_recycle()` (deferred, reparents to the pool, never frees), `cancel_active()` on `_exit_tree` (frees without `expired`) | Why the trail needs both the one-shot `expired` connection and a weakref. |
| `global/enemy_ai/steering.gd` | `Steering.break_contact(pos, threat_pos, threat_vel, side, max_speed, lateral_weight)` (t2), `turn_toward`, `arrive` | BREAK_CONTACT and the AIM tracking rate. |
| `global/enemy_ai/line_of_sight.gd` | `LineOfSight.clear(space, from, to, exclude)` (t2): opt-in blockers (`asteroids` group or `blocks_line_of_sight()`), up to 4 recasts | Candidate filter, SETTLE re-check, LOCK→FIRE re-check. |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)`, `.intercept(from, speed)` (full intercept), `.facing` (= `UP.rotated(rotation)`), `.line_of_sight(from, space, exclude)` | Player frame, lock point, LOS. |
| `global/enemy_ai/enemy_mover.gd` | `request_velocity`, `arrive`, `face_toward`, `release_constraint`, `constraint.inner_rect()` | Brain requests only (single-writer gate). |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis velocity filter against the visible rect (1480 × 1480 at (−100, −380)); inward pressure past it | The Assault BREAK_CONTACT must stop short of the edge or the pressure can push it toward the player. |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Spawns at `cam.global_position + cam.offset + offset × WORLD_SCALE`; `.move()` attaches `EnemyPathMover` | The attack-in-budget row spawns through it, rails stripped. |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | 26 sniper rows, all on rails today (t21/t22 migrate them) | Source of the spawn classes (review N3: derived from the live rows, not a hand list). |
| `tests/integration/test_sniper.gd` | 18 t12 cases; the ENTER case asserts "ENTER is the only phase t12 plays" | Changes: that assertion is replaced; new t13 cases appended. |
| `tests/integration/test_enemy_dual_mode.gd` | Two sniper dual cases (ENTER comes to rest; DISENGAGE in Assault only) | The ENTER case's "holds still 8 s in" stops being true once the cycle runs (it relocates after a shot); it is updated. |
| `tests/integration/test_enemy_bullet_lifetime.gd`, `test_enemy_mover_single_writer.gd`, `test_signal_emit_arity.gd`, `test_config_instance_isolation.gd`, `test_entity_sprite_transparency.gd` | Invariant gates touching the sniper | Must stay green; RailTrail is code-built (no texture), new config fields are flat. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `Steering.break_contact` / `EnemyMover.break_contact` | The BREAK_CONTACT velocity (t2). |
| `LineOfSight.clear` | Every LOS check. Physics-step only; the brain tick is the physics step, and hand-ticked tests run outside the space's locked flush. |
| `TargetInfo.intercept` | The full-intercept lock point. |
| `Steering.turn_toward` | AIM's capped tracking rate (never overshoots, converges exactly). |
| `EngagementBudget.update/remaining` | Budget, deferral and the attack-in-budget measurement. |
| `SniperTelegraph.show_line/hide_line` | Dim tracking / bright locked line, already sized to reach past the player. |
| `tests/helpers/enemy_ai_harness.gd` | The dual harness (`open_space()` / `assault()`). |
| `test_level1_fighter_exit.gd` | The WaveManager + ArenaCamera + container harness shape for the attack-in-budget row. |
| `test_fighter.gd::_simulate` | The per-tick log pattern for the cycle specs. |

## Conventions that constrain this

- Brains request only; `EnemyMover` is the single writer of velocity/rotation (`test_enemy_mover_single_writer.gd`, empty
  allowlist). The barrel's `scale`/`position` are not motion and are not swept, but no sniper script may write a
  `rotation` (`test_no_sniper_script_writes_rotation`).
- Brain clock only: no `Timer`, no `create_timer`. Randomness only from `rng`.
- Signals declare their arity. Per-frame prints are behind `OS.is_stdout_verbose()`.
- Every projectile has one owner: the rail round is pooled (the pool owns it); the trail owns itself and frees itself.
- Config is flat and private per instance; never write to the `load()`ed object.
- Mode-neutral specs run in both harnesses (`use_parameters(["open_space", "assault"])`).
- Design units: spawn offsets are 640×360 units × `WORLD_SCALE`; never pre-multiplied in data.
