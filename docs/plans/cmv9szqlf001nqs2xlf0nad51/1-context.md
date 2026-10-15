# Context — t5 enemy rockets (Dumb + Pursuit)

Epic plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.6, §2.7, §4.1, §4.3 (approved). This task builds
exactly that; this file only records what in the code the build leans on.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd` | Ph4 bomb/mine family: `expired`, `reset()` from `_RESET_PROPS`, `_mark_done()` latch, `ContactBlast` detonation, `Pop` `ExplosionEffect`, `ProjectileLifetime` child | The shape `EnemyRocket` mirrors (sibling class, not new kinds on it) |
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance_scenes.gd` | `scene_for(kind)` / `pool_size_for(kind, cfg)` | Shape of `EnemyRocketScenes` |
| `global/components/hitbox_component.gd` / `hurtbox_component.gd` | `HitBox{damage, damage_type}`; `HurtBox` emits `received_damage` from its own `area_entered` (absorber slot from t2) | Rocket impact HitBox (ROCKET) and shoot-down HurtBox (512 / mask 96) |
| `global/components/armor_query.gd` | `ArmorQuery.deflects(area, hit_box)` | The rocket's impact handler asks it, as the player missiles do |
| `global/components/armor_plate.gd`, `assault/scenes/enemies/ram_corvette/ram_corvette.gd` | Plates `_resolve` once per HitBox, break on ROCKET; hull `deflects_hit` while armoured; `plate_broken` signal on the Ram | Ram plate rows (50 → 34, break) |
| `global/components/contact_blast.gd` | `ContactBlast.spawn(container, at, r, dmg, frames)` deferred, layer 256 | The only player/ally damage |
| `global/components/projectile_lifetime.gd` | `max_time` / `max_distance` / world rect, emits host `expired` once, `reset()` re-arms | Rocket lifetime fizzle |
| `global/components/rocket_trail.gd` | Exhaust along local +Y | Nose-up convention |
| `global/components/bullet_pool.gd` | `acquire()` (reparent to `get_parent().get_parent()`, `reset()`), `persist_after_owner_death` hand-over | Fixture launcher pool, persistence row |
| `global/enemy_ai/target_info.gd`, `steering.gd` | `TargetInfo.player(tree).intercept()/predicted_position()`, `Steering.turn_toward` | Guidance law |
| `assault/scenes/projectiles/bullets/bullet.tscn` (HitBox 64 / mask 513), `missiles/homing/homing_missile.tscn` (HitBox 32 / mask 513, frees on a non-deflecting hurtbox) | Real player projectiles | Shoot-down rows |
| `open_space/scenes/entities/player/player_ship.tscn`, `assault/scenes/player/player_fighter.tscn` | HurtBox 128 / mask 1281 → `PlayerBase._apply_damage` (shield charge first, 0.5 s i-frames) | Real-player blast rows |
| `assault/scenes/hazards/big_asteroid/big_asteroid.tscn` | HurtBox 512 / mask 32, accepts ROCKET only | Asteroid row |
| `tests/helpers/fixture_enemy.tscn` | `BaseEnemy` with HurtBox 512 / mask 97 (runtime 1121), Health | Friendly-fire target |
| `tests/helpers/enemy_ai_harness.gd` | Dual-mode world (player in group, `ArenaCamera` in Assault) | Dual-mode rows |
| `tests/integration/test_enemy_ordnance.gd` | 8× clock pattern, `_on_container_child` blast counting | Real-physics row shape |
| `tests/integration/test_enemy_bullet_lifetime.gd` | Ph4 two-speed lifetime rows | DUMB / PURSUIT lifetime rows go here |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `Steering.turn_toward` | Capped turn per tick, never overshoots |
| `TargetInfo.intercept` | Closed-form intercept {ok, point, time} |
| `ContactBlast.spawn` | Safe-from-callback blast into the container |
| `ExplosionEffect.explode(at, container)` | Pop on defuse / fizzle / detonation |
| `ProjectileLifetime` | All lifetime rules, world rect in Assault |
| `BulletPool` with `persist_after_owner_death` | Ownership hand-over |
| `CollisionLayers` constants | No magic layer numbers in code |

## Conventions that constrain this

- One owner per projectile; `expired` exactly once per life; nothing frees itself (pool recycles, or `expired → queue_free`).
- Never `add_child` an Area2D or toggle monitoring synchronously inside a physics callback (`set_deferred`, `ContactBlast.spawn`).
- Not in group `enemies`, no `ScoreTracker`.
- Signals declare their arguments; per-frame prints behind `OS.is_stdout_verbose()`.
- No hand-typed `uid://` (new scenes reference scripts by path only).
- Real physics only at the 8× clock; hand-tick otherwise. GUT allotment for this task: 6.0 s.
- Sprite transparency sweep covers `assault/scenes/projectiles`? — it sweeps enemies/player/projectiles/hazards/allies:
  the placeholder look is `_draw()` only, no texture (t9 adds sprites).
