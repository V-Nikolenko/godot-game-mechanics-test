# Context — Phase 9 t4: the seeking-ordnance retarget hook and the hijacked homing rocket

Builds the epic plan's §2.5 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`, approved, revision 3) on top of t3's `ProjectileLifetime` (§2.4).
The design is fixed there; this directory only fixes the choices it leaves open, resolves one contradiction inside it, and orders the work.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` / `.tscn` | `class_name homing_missile extends Area2D`. 500 px/s; `_fly_to_target` turns instantly at `locked_target` (or its `homing_point()`), `_fly_forward` uses `Vector2.UP.rotated(rotation)`; both bend in hazards (`hazard_pull_scale()` 1.0). HitBox layer 32 / mask 513, damage 100, `ROCKET`; any non-deflected `area_entered` → `queue_free()`. t3 added `signal expired`, a `ProjectileLifetime` child (6 s / 2400 px / world rect) and `_on_expired()` = `queue_free()` | The rocket that gains the contract, the hijacked flight, the shoot-down HurtBox, the tell and `_finish()` |
| `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd` | `WarheadMissile`, 640 px/s straight; HitBox layer 32 / mask 513; any non-deflected hit → `queue_free()` | Gets the self-hit guard (`area.get_parent() is homing_missile`) |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` | `RocketState`: `_launch_homing()` adds `homing_count` (3) rockets **as its own children**, 7 px apart, `locked_target` round-robin over `enemies` sorted by distance; `_launch_warhead()` 3 warheads | The real salvo of the self-hit rows. A rocket's `get_parent()` is this `State` (a plain `Node`), so a `ContactBlast` spawned into it is top-level |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` | `EnemyRocket`: `_mark_done()` (areas closed and shapes disabled, deferred; lifetime physics off), `_end_after_overlaps()` (hidden, `expired` two ticks later — for **pool** recycling), `_on_expired()` backstop fizzle, `_detonate()` → `ContactBlast.spawn(get_parent(), …)`, the `area.get_parent() is EnemyRocket` self-guard, `Steering.turn_toward` pursuit, `Pop` `ExplosionEffect` | The pattern for one end of life, the blast, the guard and the pop |
| `global/components/contact_blast.gd` | `ContactBlast.spawn(container, at, radius, damage, frames)`: layer 256, deferred attach on the blast, own frame counter | The hijacked rocket's only damage to the player |
| `global/components/projectile_lifetime.gd` | Latched `expired` emit on the host; `expire_now()` goes through the same latch | `_finish()` emits `expired` through it, so `expired` is once per life |
| `global/components/hurtbox_component.gd` | `HurtBox`: `received_damage(damage)` on any `HitBox` that enters (type filter, absorber slot) | The shoot-down box (layer 512 / mask 64) |
| `global/components/rocket_trail.gd` | `RocketTrail`: CPUParticles2D with a yellow → orange ramp, built in `_ready()` | Needs one tint method so the trail turns amber |
| `global/enemy_ai/steering.gd` | `Steering.turn_toward(current, desired, max_rate, delta)` (clamped `angle_to`) | The hijacked turn |
| `global/hazards/hazards.gd` | `count()`, `bend_heading()`, `jammer_at(pos)` (t1) | Seekers fly straight inside a lit jammer; rockets still bend in wells |
| `global/systems/event_bus.gd` | `player_ordnance_hijacked(rocket: Node2D, source: Node)` declared in t2, never emitted | Emitted once per successful claim |
| `assault/scenes/projectiles/bullets/bullet.gd` / `bullet.tscn` | Player bullet: HitBox layer 64 / mask 513, consumed by a non-deflected hit (`ArmorQuery`) | The one thing that shoots a hijacked rocket down |
| `global/physics/collision_layers.gd` | Named bits; 32 `PLAYER_ROCKETS`, 64 `PLAYER_HITBOX`, 256 `ENEMY_HITBOX`, 512 `ENEMY_HURTBOX` | No new bit |

### Who sees a layer-512 area (checked: every `.tscn` mask with bit 512, every code-set mask)
`bullet.tscn` / `sniper_bullet.tscn` (64 / 513: shoots it down — intended), `homing_missile.tscn` / `warhead_missile.tscn` (32 / 513: **the self-hit the guard removes**),
every enemy rocket scene (HitBox mask 640: detonates on it — accepted by §2.5), `enemy_mine.gd` placed mines (need a parent in `enemies`: the rocket is not), `armor_plate.gd` /
`station_turret.gd` (their own hurtboxes' masks). Layer-64 hitboxes the HurtBox sees: player bullets, ally bullets, the ally fighter's CONTACT ram box, a reflected `EnemyBullet`.
Enemy bullets' HitBox mask is 1152 (no 512). Player beams and the warp pick targets by group (`enemies`, `asteroids`), so they never touch a rocket.

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `EnemyRocket._mark_done()` / `_detonate()` / `_pop_here()` / self-guard | `_finish()`'s shape, the blast call, the pop |
| `ProjectileLifetime.expire_now()` | `expired` exactly once per life without a second latch |
| `Steering.turn_toward` | The bounded turn |
| `ContactBlast.spawn` | The blast |
| `ExplosionEffect` (`Pop` node, the `pursuit_rocket.tscn` pattern) | The pop on a hijack's end |
| `tests/integration/test_homing_missile_lifetime.gd` | Hand-tick shape (`r._physics_process(DT)` then the lifetime's) and the "hover on a hurtbox-less static `Node2D`" setup |
| `tests/integration/test_enemy_rockets.gd` | `_scale_clock()` 8× real physics, `_watch_blasts()`, `_fly_against()` dodge shape, `_fixture_enemy()` with a shaped HurtBox, the real-player blast row (`shield_component.set_all_zero()`, `add_temporary()`) |
| `tests/integration/test_player_ability_lock.gd` | `_jammer()` (a lit `HazardField` built from props), the lockstep primary-fire row (idle context, `Input.action_press("shoot")`, two boxes far apart, logs compared) |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` with a fake player in group `player` |
| `tests/helpers/fixture_enemy.tscn` | A `BaseEnemy` with a HurtBox (layer 512 / mask 97) and `Health` |

## Conventions that constrain this
- Weapon tuning lives in the projectile scene (Ph5): every hijack number is an export set on `homing_missile.tscn`.
- No new collision bit (`test_collision_layer_names.gd`).
- Signals declared with their arity (`test_signal_emit_arity.gd` sweeps self-emits).
- Every projectile has exactly one owner: the homing rocket frees itself (`expired → _on_expired`, its own `_finish`). Never pooled.
- Clock rule: `x -= delta`, over at `x <= 1e-6`.
- IDEAS §21: a state shows on a light or part (amber = hacked), never a recoloured hull — the sprite's `self_modulate` is the existing precedent for a "light" on a 7×15 rocket with no separate part; the trail and a drawn bracket carry the tell.
- **The self-reference trap:** `enemy_mine.gd` naming its own `class_name` leaked at exit with every test green. `homing_missile.gd` therefore never names `homing_missile`; it compares `get_script()` identity instead. `warhead_missile.gd` naming `homing_missile` is a cross-reference, not a cycle.
- Tests: both harnesses, label-parameterised; blast rows on both real player scenes; real physics only at the 8× clock; gate-time allotment 2.5 s.
