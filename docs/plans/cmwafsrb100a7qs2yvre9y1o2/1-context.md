# Context — Phase 10 t4: Heavy Gunship shell, movement and Assault life

The design is the epic's approved plan (`docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.4, §2.11, §2.15, §2.16; review round 2 findings
N2, N7, N8, N10). This file lists the code it lands on.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/gunship/` (`gunship.gd/.tscn`, `gunship_config.gd/.tres`, `ENEMY.md`) | Legacy self-managed gunship: own `_physics_process`, ENTER/HOLD/RETREAT, camera hold-y, x-tracking, off-the-top retreat, 200 HP, contact 30 | `git mv` to `heavy_gunship/` and rewritten |
| `assault/scenes/enemies/base_enemy.gd` | `_physics_process` ticks `brain.tick` then `mover.step`; root `DefenseProfile` applied to root hurtbox only; hazard profile copied from config onto the mover; `apply_emp`, `suspend_ai`, `accept_tow` | The heavy defines no `_physics_process` |
| `global/components/enemy_module.gd`, `modular_hull.gd` | t2 / t3 parts and coordinator; `build_mounts(host, rng, owner_group, gate, first_index)` | Six parts, four mounts |
| `assault/scenes/enemies/defense_turret/mounts/*` | `TurretMount` (`tick(delta, target, host_can_fire)`, `traverse_deg`, `telegraph_gate`, `is_committed`, `phase()`), `BurstCannonMount`, `RocketBatteryMount`, `heavy_cannon_mount.tscn`, `TurretMountSlot` (a `Marker2D`) | Mount variants and arcs authored in the slots |
| `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` | APPROACH / HOLD_ARC / DISENGAGE, `EngagementBudget`, attack gate, `AnchorIdle` hub idle, curved DISENGAGE to the nearest projectile-rect edge | The template for `HeavyGunshipBrain` |
| `global/enemy_ai/enemy_mover.gd` | single writer of velocity / rotation; `max_turn_rate`, `boost`, `release_constraint`, `face_toward` | Broadside facing = `face_toward` a point; side swap = the mover's capped turn |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Corridor velocity filter (inner rect 1480 × 1480, soft 120 / hard 450) | Assault fight |
| `assault/scenes/systems/wave_builder.gd` | `gunship()` / `GUNSHIP` | → `heavy_gunship()` / `HEAVY_GUNSHIP` |
| `assault/scenes/levels/edelia/1/level_1_director.gd:347-349, 985-1018`; `assault/scenes/levels/level_2_waves.gd:34, 74-127` | callers | Rows switch builder only; rails kept (t11 removes level 1's) |
| `tests/helpers/specialist_exit_probe.gd`, `tests/helpers/ph9_exit_keys.gd` | Memoised curved-exit probe; the "keys file" rule | New `tests/helpers/ph10_exit_keys.gd` |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` worlds | Both-harness rows |
| Roster / legacy tests: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd`, `test_enemy_dual_mode.gd`, `test_config_instance_isolation.gd`, `test_explosion_effect_placement.gd`, `test_enemy_emp.gd`, `test_emp_blast_module.gd`, `test_support_ship.gd`, `test_enemy_bullet_lifetime.gd`, `test_station_reinforcements.gd` | name the gunship | §2.4.6 moves |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `MissileCorvetteBrain` | budget / gate / deferral / DISENGAGE / hub idle structure, `_sync_orbit` + `Steering.orbit` arc with drift and reversals, the `-orbit_dir` break-contact sign |
| `DefenseTurretBrain.tick` | ticking mounts with `TargetInfo.player` and `can_fire = can_see_player() or fires_past_cover()` (LOS only on the physics step) |
| `DefenseTurret` | owner group `"<kind>_%d" % instance_id`, `launch_velocity()` / `rocket_clear_radius()`, `is_laser_blocking() == false` |
| `test_enemy_module.gd` | 8× clock helpers, `_fire(scene, target, from_dir)` real-projectile helper |
| `test_hacker_frigate.gd` | hand-ticked `_tick` / `_step` shape, `_world(mode)` that unparents an earlier world, probe in `before_all()` |

## Conventions that constrain this
- Only `EnemyMover` writes velocity / rotation (single-writer gate sweeps every `*_brain.gd` and mover-driven roots).
- Flat config (`@export_group`), `.tres` wins, contact damage re-applied in `_ready()`; hazards copied by `BaseEnemy._ready()`.
- Hull art nose-down (`sprite_forward_angle` `PI/2`): local +y is the nose, so **port (the ship's left) is local +x**, starboard −x.
- Mount `rest_bearing_deg` is local to the slot's parent (the hull frame): port 0°, starboard 180°, nose 90°, aft 270°.
- Exit probes only through a keys file with a static `prepare_probe`.
- Never hand-type a `uid://`; leave new references UID-less.
