# Context — t12 Twin-Laser Drones, the `TwinLaserPair` rig, Attack A

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t12. Builds epic plan §2.12 with §2.1, §2.3, §2.4 and §2.19 (approved). Code read on
`agent/auto-dev` @ `4772ffc` (t11 landed).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`: health/hurtbox wiring, `_physics_process` = `brain.tick(delta)` then `mover.step(delta)`, `suspend_ai()`, `accept_tow()`, `died` emitted before `queue_free()`, `_maybe_leave_wreck()` (brain rng, only with `wreck_chance > 0`) | The drone is a `BaseEnemy` with brain + mover; the rig listens to `died` / `tree_exiting` |
| `global/enemy_ai/enemy_brain.gd` | `EnemyBrain`: `actor`, `mover`, `rng` (`rng_seed`), `tick`, `on_suspended`, `accepts_tow`, `can_see_player` | Base of `TwinLaserDroneBrain` |
| `global/enemy_ai/enemy_mover.gd` | Single writer of velocity/rotation: `request_velocity`, `arrive`, `add_nudge`, `face_toward`, `boost(dir, speed, duration)` (skips avoidance and accel, keeps drift + constraint), `own_velocity()`, `release_constraint()`, `constraint.inner_rect()`; `_avoid` drops a hazard whose `exempt_group` the actor is in | ADVANCE is `boost()`; the corridor constraint and well drift still apply during it (the counterplay) |
| `global/enemy_ai/engagement_budget.gd` | Assault-only budget (`update`, `remaining`, `active`) | One attack per Assault life, deferral |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Velocity filter; identity inside `inner_rect()` = 1480 × 1480 visible rect (camera pan range), soft band pressure outside | Assault frames must keep both slots and the advance inside `inner_rect()` (with an inset so a drone within `slot_tolerance` of its slot is still inside) |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)` snapshot (position, velocity) | The rig's only player read |
| `global/enemy_ai/squad_controller.gd` | RefCounted board held by members' properties; signal connections do not keep it alive | Precedent for `TwinLaserPair`'s lifetime |
| `assault/scenes/projectiles/enemy_beams/enemy_beam.gd`, `twin_beam.tscn` | `EnemyBeam` TWIN: `setup(host, owner_group)`, `start()` (ignored in TELEGRAPH/ACTIVE), `tick()`, `cancel()` (TELEGRAPH→OFF, ACTIVE→FADE), `set_endpoints`, `set_strained`, `is_lethal`, `hazard_info` (registered TELEGRAPH..FADE start, `exempt_group` = owner group, unregisters in `_exit_tree`); cover casts only on the physics step, excluding the host body; telegraph 0.8, held ACTIVE, ignite 0.1, fade 0.15, hhw 10, damage 12, rehit 0.55 | The pair's beam (child of drone A) |
| `assault/scenes/projectiles/enemy_beams/enemy_beam_scenes.gd` | `scene_for(TWIN)`, `export_of(kind, prop, fallback)`, `export_of_scene` | Beam instance + gate reads |
| `assault/scenes/structures/laser_fence/laser_fence.gd` | The other endpoint-beam user: endpoints frozen at a dead post's last position, `died` + `tree_exiting` one-shot collapse, beam ticked through FADE after the collapse | The pattern the rig follows for "kill one drone" |
| `assault/scenes/structures/turret_group/turret_group.gd` | Coordinator: deferred `spawn_members()` (public, idempotent), siblings in the parent, `EventBus.enemy_spawned_orphan`, `counts_toward_wave_clear` / `counts_as_escape` false | `TwinLaserPairSpawn` copies the spawn shape (then frees itself) |
| `assault/scenes/enemies/mine_layer/mine_layer.gd`, `mine_layer_brain.gd`, `.tscn`, `_config.gd/.tres` | Newest mover enemy: `_apply_config`, `enter_phase()` test seam, `budget`, `_request_disengage()` deferral, DISENGAGE (`release_constraint`, `max_speed = exit_speed`, free outside `projectile_world_rect` with strict compares), `_set_light`, `start_engaged` | Template for shell, brain skeleton and DISENGAGE |
| `assault/scenes/enemies/defense_turret/defense_turret.tscn` | Code-drawn placeholder; hit flash animates `.:self_modulate` | Placeholder art until t16 |
| `global/components/state_light.gd` | `StateLight` OFF/ARMED/CHARGING/COMMIT, `blink_once()` | The lens light |
| `global/hazards/hazards.gd`, `HazardField` | Registry, `accel_at`, `penalty_at`, `hurt_box_of`; `HazardField` gravity well (`radius`, `core_radius`, `pull_force`) | Well strain row |
| `assault/scenes/hazards/wreck/wreck.gd`, `wreck_large.tscn` | Layer-1 body every ship stops on, LOS blocker, contact box unreachable by a ship whose hurtbox ≤ body; `assault_drift` | Wreck strain row ("bait into terrain") |
| `assault/scenes/systems/wave_builder.gd` | Spawn constructors + path constants | `TWIN_LASER_PAIR`, `twin_laser_pair()` |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | `_spawn_ship()`: camera-relative position, props before `add_child`, `enemy_spawned` | Real spawn path for the WaveBuilder row |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds with a bare player body | Every row in both harnesses |
| `tests/helpers/specialist_exit_probe.gd` | t14 measures DISENGAGE from `enter_phase(DISENGAGE)` on a lone ship with a set velocity | DISENGAGE must work on a lone drone (exit along the heading) |
| `tests/integration/test_enemy_beams.gd` | Fairness rows with `_player_terms()` (`r_p` 20.09, `v_c` 360), `_synthetic` boundary copies | The twin / moving-wall row lands here |
| `tests/integration/test_base_enemy.gd` | `_MIN_ROSTER_SIZE` 18, `_AUTHORED_CONTACT_MODES`, `_REFUSING_PHASES` tow table (sets `Brain.start_engaged`, calls `enter_phase`, falls back to `APPROACH` / `ENTER` for its "unlisted" phase) | The drone has neither APPROACH nor ENTER: the unlisted-phase fallback gains FORM |
| `tests/integration/test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`, `test_wreck.gd` | Hand rosters + completeness sweeps | The drone joins all four |
| `tests/integration/test_enemy_dual_mode.gd` | Dual-mode cases; `HAZARD_PROFILES` | One dual-mode case; the drone's hazard profile row |
| `tests/integration/test_engagement_deadline.gd` | `ENEMIES_CLEARED` guard rows for groups / fences | A twin-pair guard row |
| `tests/integration/test_enemy_mover_single_writer.gd` | Sweeps `*_brain.gd` (receiver writes) and mover-driven roots (bare writes) | The drone root and brain write no motion; the rig is a `RefCounted` that only computes frames |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EnemyMover.arrive` / `boost` / `face_toward` / `add_nudge` / `release_constraint` | All drone motion (FORM / hold / ADVANCE / DISENGAGE) |
| `EngagementBudget` | Assault life; `active` false in Open Space |
| `EnemyBeam` TWIN + `EnemyBeamScenes.scene_for(TWIN)` | The beam, its telegraph, strain flicker, laser-wall hazard with `exempt_group` |
| `TargetInfo.player()` | Player position and velocity for the frame and the feed-forward |
| `StateLight` | Lens light: CHARGING in TELEGRAPH, ARMED in ACTIVE |
| `TurretGroup.spawn_members()` shape | Deferred sibling spawn + orphan announcement |
| `LaserFence._on_post_gone` shape | One-shot `died` + `tree_exiting` collapse, frozen endpoint |
| `MineLayerBrain` DISENGAGE + `enter_phase` seam | Exit and the probe-compatible entry |
| `test_laser_fence.gd` / `test_mine_layer.gd` helpers | `_scale_clock`, `_victim` (fixture enemy + 14 px hurtbox), hand tick with `before + velocity * DT` |
| `test_enemy_dual_mode.gd::_fixture_well` | A `HazardField` gravity well |

## Conventions that constrain this

- Brain ticks on physics through `BaseEnemy._physics_process`; only `EnemyMover` writes velocity/rotation (gated). Randomness only from `brain.rng`.
- `accepts_tow()` false in TELEGRAPH, ADVANCE and LAUNCHED; the tow table needs `start_engaged` on the brain and `enter_phase()` working on a lone drone.
- Flat config `TwinLaserDroneConfig extends ShipConfig`, one `*config*.tres` in the dir, `.tres` wins in `_ready()`; joins `enemies` in `_ready()`.
- Body, hurtbox and contact box share one `CircleShape2D` r 13 (COLLISION idiom: contact box layer 256, mask 0, damage = `collision_damage` 8).
- Hull art nose-down (`sprite_forward_angle` PI/2); placeholder is code-drawn until t16.
- Signals declared with their arity; per-frame prints behind `OS.is_stdout_verbose()`; never hand-type a `uid://`.
- Cover rays only on the physics step: hand-ticked rows never cast; the wreck row runs on real physics at 8×.
- Numbers in gates come from scenes / the `.tres`, never typed copies.
- Self-reference trap: `enemy_mine.gd` leaked by naming its own class; `TargetInfo` (RefCounted) names itself without leaking. `TwinLaserPair` follows the `TargetInfo` precedent and `check-test-leaks.sh` verifies it.
- Gate time allotment 2.5 s; real-physics rows ≈ 0.25–0.4 s each at 8×; hand-ticked dual-mode cases ≈ 0.02–0.06 s.
