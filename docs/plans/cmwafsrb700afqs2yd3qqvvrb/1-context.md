# Context — Phase 10 t6, the Carrier shell

Task plan for epic `cmug23oo90029m52wae4clve0` (Phase 10), task key t6. The design is the epic plan's §2.6 (with §2.1, §2.2, §2.9, §2.11, §2.16);
this stage read the code those sections rely on. t5 (Gunship phases) is BLOCKED and landed only its plan files, so the Heavy Gunship code is t4's.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`: root HurtBox / Health / ContactHitBox, profiles, `_physics_process` brain-then-mover tick, EMP window (`_emp_left`, `apply_emp` halts the mover then calls `brain.on_emp_started()`), `_on_received_damage` / `_on_health_changed` hooks, death | Carrier extends it; t6 adds the read-only `emp_seconds_left()` here |
| `assault/scenes/enemies/heavy_gunship/` | t4's modular heavy: `HeavyGunship` (root: `_apply_config`, `build_mounts`, `homing_point`, `launch_velocity`, `rocket_clear_radius`, `is_laser_blocking`), `HeavyGunshipBrain` (AnchorIdle hub idle, `start_engaged` seam, side choice, `_tick_weapons`), flat config, scene layout | the template the Carrier copies (scene node names, root API, brain seams) |
| `global/components/enemy_module.gd` | `EnemyModule`: Role, `starts_vulnerable`, `set_vulnerable`, `deflects_hit`, `destroy()` (wreck stays, hurtbox off deferred, Sprite -> `wreck_texture`, `Light` CanvasItem hidden), signals `destroyed` / `deflected` / `vulnerability_changed` | the seven Carrier parts; a locked part pings for bullets, beam and nova alike |
| `global/components/modular_hull.gd` | `ModularHull`: collects `Modules/*`, `module(id)`, `live(role)`, `destroyed_count(roles)`, `module_destroyed`, `build_mounts()` | core exposure counts `destroyed_count([ENGINE, WEAPON, HANGAR])`; engine factor reads `live(ENGINE)` |
| `global/enemy_ai/enemy_mover.gd` | the single motion writer: `request_velocity`, `arrive`, `face_toward`, `boost`, `halt`, `max_speed` / `acceleration` / `braking` / `max_turn_rate`, hazard slow `1 - p·(1 - resistance)`, `constraint_mode` NONE | CROSS writes accel / braking 0 and avoidance 0; the turn cap is `max_turn_rate`; resistance 1.0 makes the slow factor exactly 1 |
| `global/enemy_ai/enemy_world.gd`, `engagement_budget.gd` | `arena(tree)` (Assault iff an arena provider), `view_rect`, `projectile_world_rect` | mode detection and the free-below rule |
| `assault/scenes/enemies/jamming_structure/jamming_structure.gd:45` | the world-anchored-x rule: `global_position.x -= view_rect.center.x - projectile_world_rect.center.x` once in `_ready()` | the Carrier copies it |
| `global/enemy_ai/anchor_idle.gd` | `AnchorIdle(anchor, perceive, lose, notice, home)` and `update()` -> IDLE / NOTICING / COMBAT / RETURNING | the Open Space CRUISE idle |
| `assault/scenes/enemies/support_ship/support_ship_brain.gd:290` | `is_candidate(e)`: the ward filter | gains the duck-typed `accepts_ward() == false` skip |
| `global/components/contact_profile.gd` | ARMOR: armed at setup, `contact_made`, `_shove` -> duck-typed `apply_knockback` | the Carrier's contact (Ram precedent: mode 4, ContactHitBox layer 256 mask 128) |
| `assault/scenes/enemies/ram_corvette/ram_corvette.gd:128` | armoured-hull refusal: `armor_deflected.emit(damage)` + `hit_flash_player.play("hit")` | the Carrier's `_on_received_damage` |
| `assault/scenes/systems/wave_builder.gd` | `heavy_gunship()` / `HEAVY_GUNSHIP` | add `carrier()` / `CARRIER` |
| `tests/integration/test_enemy_module.gd` | `BeamDriver` (real `BeamBehavior` on a node), `_lit_ray`, nova via `PlasmaNovaModule.new().try_activate(player)` + freeing its flash layer, `_fire` real bullets, 8x clock pair | the direct-emitter and projectile rows of `test_carrier.gd` reuse these shapes |
| `tests/integration/test_heavy_gunship.gd` | `_world(mode)` (removes the previous harness root from the tree), `_spawn`, hand `_tick`, `_until_spent` | the harness pattern |
| `tests/integration/test_ram_corvette.gd:547`, `test_jamming_structure.gd:117` | ARMOR contact row; a real player (`player_ship.tscn` / `player_fighter.tscn`) with physics off | the contact row |
| Roster gates: `test_enemy_contact_damage.gd` (ROSTER + per-enemy row), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd` (`_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`, `_MIN_ROSTER_SIZE`, every-phase refusers), `test_enemy_dual_mode.gd` (`HAZARD_PROFILES`, one spawn row), `test_support_ship.gd` (ward rows), `test_engagement_deadline.gd` (ENEMIES_CLEARED guards) | each enemy directory must appear in them |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EnemyModule` / `ModularHull` | every part rule (lock, ping, wreck that stays, mounts powered down) — the Carrier adds none of its own |
| `HeavyGunship` root | `homing_point(from)` (nearest live vulnerable part), `launch_velocity`, `rocket_clear_radius`, `body_size`, `is_laser_blocking` — copied shape |
| `AnchorIdle` | the hub idle state machine |
| `ContactProfile` ARMOR | the shove |
| `StateLight` | the hull light node (OFF in t6; t7 drives it) |
| `EnemyMover.boost()` | the EMP crossing: a committed velocity the mover keeps applying while the brain is frozen |
| `ShipConfig` hazard fields | copied onto the mover by `BaseEnemy._ready()` |
| `tests/helpers/enemy_ai_harness.gd` | both harnesses |

## Conventions that constrain this

- Single writer: the brain only requests; it may write mover limits (`max_speed`, `max_turn_rate`, `acceleration`, `braking`, `hazard_avoidance`).
- Nose-down art: nose local +y, port local +x, stern local −y; `sprite_forward_angle` PI/2.
- Flat `@export_group` config; never write the shared `.tres` (tests write the private `config` copy).
- Signals with arity; per-frame prints behind `OS.is_stdout_verbose()`; no `Timer` / `_process` clocks in the brain (it ticks on physics).
- Never hand-type a `uid://`: new `ext_resource` lines are UID-less.
- Tests: both harnesses label-parameterised, hand-ticked at 1/60; projectile / beam rows on real physics at the 8x clock.
- Gate budget: t6 allotment 2.0 s of new GUT time (escalation at 1.5x = 3.0 s for its own files).
