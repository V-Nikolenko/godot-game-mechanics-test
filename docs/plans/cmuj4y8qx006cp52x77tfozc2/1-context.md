# Context

The design is the epic's approved plan, `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.3 (rev 2, answers
review B1), with its test rows in §4 (`test_contact_profile.gd`, `test_contact_blast_damage.gd`, `test_base_enemy.gd`).
This file records only the code facts the implementation depends on.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | Base of every assault enemy; resolves `DefenseProfile`, owns `suspend_ai()`, `_on_health_changed` frees on 0 | Gets `contact_profile` resolution + arming in `suspend_ai()` |
| `global/components/defense_profile.gd` | Scene-authored-or-default `Node` profile | The pattern `ContactProfile` mirrors |
| `global/components/hitbox_component.gd` | `HitBox` (Area2D, `damage`, `damage_type`) | `ContactBlast` extends it |
| `global/components/hurtbox_component.gd` | `HurtBox._on_area_entered` casts to `HitBox`, emits `received_damage(damage)` | How the player takes the blast |
| `global/components/explosion_effect.gd` | Re-homes particles into `actor.get_parent()`, sets `global_position` after parenting | Blast re-homing precedent |
| `global/components/health_component.gd` | `amount_changed(current_health)` on every `set_health` | Death hook for EXPLOSIVE; repeats must be harmless |
| `global/entities/player_base.gd::_apply_damage` | `HurtBox.received_damage → health.decrease` (minus shield / temp HP / i-frames) | The path the integration test reproduces |
| `assault/scenes/player/player_fighter.tscn` | Player `HurtBox` layer 128, mask 1281 (includes 256) | Blast layer 256 is detected |
| `assault/scenes/enemies/space_station/space_station.gd:233` | Sets its `ContactHitBox.collision_layer` to 0 on death | COLLISION must not touch the hitbox, or this is fought |
| `assault/scenes/race/track/race_asteroid.gd` | Toggles hitbox monitoring via `set_deferred` | Precedent for deferred area toggles |
| `assault/scenes/enemies/{kamikaze_drone,drone_interceptor}/*.gd` | Connect `contact_hit_box.area_entered` themselves | Unchanged in this task (they stay COLLISION); t8b/t9 move them onto `contact_made` |
| `assault/scenes/enemies/bonus_drone/bonus_drone.tscn` | No `ContactHitBox` | `setup()` must accept `hit_box == null` |
| `tests/helpers/fixture_enemy.tscn` | Minimal `BaseEnemy` (Health, HurtBox, HitFlashAnimationPlayer, mover, brain), no ContactHitBox | Base for a contact fixture |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `DefenseProfile` resolution loop in `BaseEnemy._resolve_defense_profile()` | Copy for `_resolve_contact_profile()` |
| `ExplosionEffect.explode()` | Container = `actor.get_parent()`, position after parenting |
| `CollisionLayers.ENEMY_HITBOX` (256) | Blast layer, by name |
| `tests/unit/test_hitbox_hurtbox.gd` last case | Real-physics overlap harness (`await wait_physics_frames`) |

## Conventions that constrain this
- Signal arity: `contact_made(area: Area2D)`, `detonated(position: Vector2)` emitted with exactly that (arity gate).
- No `create_timer` in components that can be freed mid-wait (leak trap); the blast counts physics frames.
- Single-writer gate: `base_enemy.gd` is swept as an ancestor; neither new class may write velocity/rotation.
- Per-frame prints behind `OS.is_stdout_verbose()`.
- Every legacy pin must stay green with no assertion changed.
