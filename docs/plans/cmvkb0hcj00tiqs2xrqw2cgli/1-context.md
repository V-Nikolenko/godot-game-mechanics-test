# Context — t2: the mine family (`EnemyMine`)

Epic plan: `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.1, §2.2, §2.3, §2.17 (approved). This task builds
exactly those sections; this file only records what the code looks like today.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd` | `EnemyOrdnance` (Area2D): gravity bomb / mine / pursuit bomb, one script, `kind` enum. `_RESET_PROPS` const, `_move()` match, `_player_in_range()` poll, `_detonate()` -> `ContactBlast.spawn` + gravity field, `_mark_done()` latch, `_draw()` circle + blink overlay. | Gains the three virtual hooks (`_move_mine`, `_trigger_seen`, `_on_detonated`) and `_reset_props()`; bomb paths must stay byte-identical. |
| `assault/scenes/projectiles/enemy_ordnance/mine.tscn` | The Bomber's mine (no UID). Root script `enemy_ordnance.gd`, `kind = 1`, `warning_time 0.5`, `mine_life 8.0`; children HurtBox (512, mask 96), Health 1, ProximityArea (mask 128), ProjectileLifetime (`max_time` 10), Pop. | Script switches to `EnemyMine`, `warning_time` 0.25. Path unchanged. |
| `assault/scenes/projectiles/enemy_ordnance/enemy_ordnance_scenes.gd` | `EnemyOrdnanceScenes.MINE` preload, pool sizing for the Bomber. | Unchanged; `EnemyMineScenes.scene_for(PROXIMITY)` must return the same `PackedScene`. |
| `assault/scenes/projectiles/enemy_rockets/enemy_rocket_scenes.gd` | `scene_for` / `pool_size_for` / `export_of` via `PackedScene.get_state()`. | The shape `EnemyMineScenes` copies. |
| `assault/scenes/enemies/bomber/bomber.gd` | `drop(kind, ...)` acquires from `MinePool`, overrides arm/eject/warning/life/blast, launches. | Unchanged; its mines now become registered hazards. |
| `global/hazards/hazards.gd`, `hazard_info.gd` | Static registry (`register`/`unregister`/`count`/`around`), `pulse_damage()` (both sides, centre distance, bypasses shields). | Mines register; ALL mines blast through `pulse_damage`. |
| `assault/scenes/hazards/wreck/wreck.gd` | Hazard precedent: one `_info` updated in place, `hazard_info()`, register in `_enter_tree()`. | Pattern to follow, except mines register on `launch()`. |
| `global/components/bullet_pool.gd` | Prewarms children with `PROCESS_MODE_DISABLED` (in tree), `acquire()` reparents to container then `reset()`, recycle reparents back. Hand-over does not reparent. | Why registration is launch-scoped; reparent fires `_exit_tree`/`_enter_tree`. |
| `global/components/projectile_lifetime.gd` | Backstop; `max_time` 0 = inert. | Placed mines set it to 0. |
| `global/enemy_ai/steering.gd::context_avoid`, `enemy_mover.gd::_avoid` | Context steering over `Hazards.around(pos, margin + speed * CONTEXT_LOOKAHEAD)`. | The §2.3 measured avoidance rows integrate this. |
| `global/components/armor_plate.gd` | Plate builds its own HurtBox (layer 512) in `_ready()`; parent of the HurtBox is the plate. | Hostility-ALL boundary row. |
| `tests/helpers/fixture_enemy.tscn` / `fixture_brain.gd` | BaseEnemy fixture; HurtBox (512) with no shape; brain requests `desired_velocity`. | ALL-trigger rows and the real-mover avoidance row (shape + group added at runtime). |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `ContactBlast.spawn()` | PLAYER-mine blast (unchanged). |
| `Hazards.pulse_damage()` | ALL-mine blast. |
| `EnemyRocketScenes.export_of()` | Scene-export reader shape. |
| `tests/integration/test_enemy_ordnance.gd` `_scale_clock()` / `_player()` / `_shot()` | 8x clock and player stand-in pattern. |
| `tests/unit/test_context_avoidance.gd::_fly()` | Integration shape for the pure-stage rows. |
| `tests/helpers/enemy_ai_harness.gd` | Dual-mode harness (Open Space / Assault). |

## Conventions that constrain this
- Exactly one owner per projectile; pooled mines never free themselves; placed mines are self-owned (`expired -> queue_free`).
- Accumulated-delta clocks, no Timers. Signals declared with arity. No typed numbers in gates: read from scene exports.
- `CollisionLayers` constants (128 PLAYER_HURTBOX, 512 ENEMY_HURTBOX).
- Tests on the 8x clock for real physics; GUT allotment for t2 is 3.0 s.
