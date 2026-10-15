# Context — t2: HurtBox absorb hook and `EnemyShield`

Epic plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.3 (approved). This task builds exactly that section.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/components/hurtbox_component.gd` | `HurtBox`: `area_entered` → filter by `accepted_damage_types` → `received_damage.emit(hb.damage)` | Gains the one-slot absorber hook; must be behaviourally identical with no absorber |
| `global/components/armor_query.gd` | `ArmorQuery.deflects(area, hit_box)`: `deflects_hit` first, then `is_armored()` on the hurtbox's parent | A shielded host answers neither for the shield, so a bullet is consumed by an absorbed hit |
| `global/components/armor_plate.gd` | `deflects_hit` → `_resolve` damages the plate | Why the shield must never call `deflects_hit` (it has side effects) |
| `assault/scenes/projectiles/bullets/bullet.gd` | expires on the first non-deflected hurtbox | Real-bullet rows: front = consumed, hull unchanged |
| `assault/scenes/projectiles/missiles/{homing,warhead}/*.gd` | `queue_free()` on any non-deflected hurtbox; HitBox layer 32 mask 513; no blast | Real-rocket row: detonates on the shield, no hull damage |
| `assault/scenes/enemies/base_enemy.gd` | `hurt_box.received_damage → health.decrease` | Unchanged (P-15: DamageReaction not adopted); an absorbed hit never reaches it |
| `assault/scenes/enemies/ram_corvette/ram_corvette.gd` | `is_armored()` while plates live; `deflects_hit` = `is_armored()` | Armoured-host rule (shield asks hit-blind `is_armored()` only) |
| `tests/helpers/fixture_enemy.tscn` | minimal `BaseEnemy` (HurtBox layer 512 mask 97, **no shape**, Health 10) | Integration rows; the test adds a CircleShape2D at runtime (fixture scene unchanged, other suites use it) |
| `tests/unit/test_hitbox_hurtbox.gd` | characterization of the HitBox/HurtBox pair | Existing rows unchanged; new absorber rows appended |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/integration/test_armor_query.gd` | real-projectile spawn helpers (`_spawn`, `_frames`, `_is_consumed`, `_count`) |
| `tests/integration/test_enemy_ordnance.gd` | the 8× clock (`_scale_clock` / `_restore_clock`) pattern |
| `global/physics/collision_layers.gd` | `CollisionLayers.*` names for the fixture part's hurtbox |

## Conventions that constrain this
- Signals declare what they emit (arity sweep). Clocks are accumulated delta. No `uid://` hand-typed.
- The shield never writes its own or its host's `rotation` (single-writer sweeps); draws in world angles − `global_rotation`.
- Real physics only where a real collision is the point, on the 8× clock, ≤ 6 awaited cases; budget 3.0 s GUT.
- No shipped enemy carries a shield in this task (fixtures only).
