# Context — t6 Stationary Defense Turret (shell, `TurretMount`, `AssaultDrift`)

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t6, building epic plan §2.7 and §2.19 (approved). Prerequisite t1 (gate room) is done;
t2–t4 (beam core, Pulse Ring, segment hazards) are also built, though t6 needs none of them (the burst cannon fires Pulse rounds).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`: health / hurtbox / contact profile, `_resolve_ai()` (brain + mover by type), `_physics_process` ticks the brain and then the mover (if any), `is_ai_driven()` needs a mover, `accept_tow()`, scoring fields copied from `config` | The turret is a `BaseEnemy` with a brain and **no mover**: the brain still ticks, `is_ai_driven()` is false, tows are refused |
| `global/enemy_ai/enemy_brain.gd` | `EnemyBrain`: `actor`, `mover`, `rng`, `tick()`, `accepts_tow()`, `can_see_player()` (`TargetInfo.line_of_sight`, physics-step only) | `DefenseTurretBrain` extends it; it runs its LOS ray only when `Engine.is_in_physics_frame()` |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)`, `intercept(from, speed)` | Partial-lead aim: `P.lerp(intercept.point, lead_blend)` |
| `global/enemy_ai/burst_clock.gd` | `BurstClock`: `start(count, gap)`, `advance(delta)` → shots due, first shot due on the first advance | Burst cannon cadence |
| `global/enemy_ai/enemy_world.gd` | `arena()`, `view_rect()`, `projectile_world_rect()` (Assault provider lookup, duck-typed) | Assault view gating and `AssaultDrift`; nothing in `global/` names `ArenaCamera` |
| `global/components/state_light.gd` | `StateLight` OFF / ARMED / CHARGING / COMMIT, `blink_once()` restores the previous state | The brain owns the turret's light |
| `global/components/bullet_pool.gd` | `BulletPool`: container = `get_parent().get_parent()`; `acquire()` reparents a round into the container | The pools must be **root children** of the turret so rounds land in the enemy container |
| `global/components/contact_profile.gd` | Mode NONE disables the hitbox; `setup()` copes with a null hitbox | Turret: NONE, no `ContactHitBox` |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`, `rounds/pulse_round.tscn`, `rounds/enemy_rounds.gd` | `EnemyBullet` (`speed`, `set_direction()`), the Pulse round (300 px/s, 8 dmg, `max_time` 8, `max_distance` 1400), `EnemyRounds.PULSE`, `pool_size_for()` | Burst cannon round and pool size |
| `assault/scenes/projectiles/enemy_beams/enemy_beam_scenes.gd` | `scene_for` / `export_of` / `export_of_scene` (reads a scene's authored export through `PackedScene.get_state()`) | `TurretMountScenes` follows the same shape (and reuses `export_of_scene`) |
| `assault/scenes/hazards/minefield/minefield.gd` | Its own Assault drift (60 px/s) and the "below the projectile world rect" free | The rule `AssaultDrift` generalises (the minefield keeps its own code) |
| `assault/scenes/systems/score_tracker/score_tracker.gd` | `_on_enemy_spawned` reads `counts_as_escape`; `_on_enemy_freed` applies the escape penalty `combo *= 0.75` only when it is true; orphans arrive through `EventBus.enemy_spawned_orphan` | The "a drifted-out turret is not an escape" row |
| `assault/scenes/systems/wave_builder.gd` | Scene constants, constructors, `SpawnConfig.prop()` → `initial_props` (applied before `add_child`) | `DEFENSE_TURRET` + `defense_turret()` |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd` | The player's mining beam: a ray on mask `1 \| 1024`, a body answering `is_laser_blocking() == false` does not stop it; targets in `enemies` within 12 px of the line | The "the mining beam damages the turret" row |
| `assault/scenes/enemies/bonus_drone/` | No `ContactHitBox`, `collision_damage` 0, `counts_as_escape = false` in its `.tres` | The roster precedent for `no_hitbox` and the escape flag |
| `assault/scenes/enemies/missile_corvette/` | Pools as direct root children, a soft glow texture built in code, `StateLight` child | Scene/script shape to copy |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds (fake player; Assault adds an `ArenaCamera` at (640, 360)) | Every behaviour row runs in both |
| `tests/integration/test_level1_drone_exit.gd` | `_scale_clock()` / `_restore_clock()` (8× clock) | The LOS row and the mining-beam row run on real physics at 8× |
| `assault/scenes/hazards/wreck/wreck_medium.tscn` | A real wreck body (layer 1024, `blocks_line_of_sight()`) | The LOS blocker (the fighter's cover rows use it the same way) |

## Roster gates the new scene joins (§2.19)

| File | Edit |
|---|---|
| `tests/integration/test_enemy_hurtbox_geometry.gd` | `ROSTER` entry |
| `tests/integration/test_contact_hitbox_geometry.gd` | `ROSTER` entry, `no_hitbox: true` |
| `tests/integration/test_enemy_contact_damage.gd` | `ROSTER` entry with `config`, `no_hitbox: true` |
| `tests/integration/test_wreck.gd` | `_SHIP_SCENES` ("no hurtbox larger than its body") |
| `tests/integration/test_base_enemy.gd` | `_MIN_ROSTER_SIZE` 10 → 14 (13 `BaseEnemy` dirs today + the turret), `_AUTHORED_CONTACT_MODES["defense_turret"] = NONE`, a tow row for a mover-less brain |
| `tests/integration/test_enemy_dual_mode.gd` | one dual-mode case |
| `tests/integration/test_enemy_bullet_lifetime.gd` | the mount's `round_speed` as a Pulse shooter |
| automatic sweeps | `test_config_instance_isolation.gd`, `test_entity_sprite_transparency.gd` (no scene texture: placeholder art is drawn in code), `test_enemy_mover_single_writer.gd` (the turret has no mover; its brain writes no `actor.` motion), `test_signal_emit_arity.gd`, `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd` (no hand-typed UIDs) |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `BurstClock` | exact burst counts and gaps |
| `TargetInfo.intercept()` | the closed-form lead |
| `EnemyRounds.pool_size_for()`, `EnemyRounds.PULSE` | pool sizing, the round scene |
| `EnemyBeamScenes.export_of_scene()` | reading a mount scene's authored export without instantiating it |
| `StateLight`, `ContactProfile` (NONE), `BulletPool` | as-is |
| `EnemyBrain.can_see_player()` | LOS through wrecks and asteroids |
| `EventBus.enemy_spawned_orphan` | registering a test turret with a real `ScoreTracker` |

## Conventions that constrain this

- Brains tick on physics through `BaseEnemy._physics_process`. There's no `Timer` or `create_timer`, and randomness comes only from `brain.rng`.
- The mount writes only its own `rotation`. The turret root never rotates.
- Tuning lives in the mount scene's exports and is read by gates through `TurretMountScenes.export_of`, never typed into a test.
- Physics queries run only on the physics step. Hand-ticked rows never cast, and the blocker rows run on real physics at 8×.
- Signals are declared with their arity, per-frame prints sit behind `OS.is_stdout_verbose()`, and `uid://` values are never hand-typed.
- Behaviour rows run in both harnesses, parameterised on a label string.
- Gate time: 1.5 s of new GUT time for this task.
