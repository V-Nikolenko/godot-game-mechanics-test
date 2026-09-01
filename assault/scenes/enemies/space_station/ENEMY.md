# Space Station — Level 1 mini-boss (turret phase)

**Role:** Stationary cores-and-turrets mini-boss. Four turrets on a 256×256 hull, each on its own
HP bar. The core refuses **all** damage until the last turret dies.
**Fantasy / threat:** A fortress, not a ship. Shooting the hull sparks and does nothing, which
teaches the rule without any UI: kill the guns first, then the core.

> **Status: EPIC sub-item 1 only — the entity exists and is destructible.** It does **not** shoot,
> has no laser phase, and is not yet placed in a level. Sub-items 2–5 add level integration, the
> rotating laser phase, bullet-hell + reinforcements, and the death handoff. Plan and review:
> [`docs/plans/station-mini-boss-destructible/`](../../../../docs/plans/station-mini-boss-destructible/).

---

## Stats

| Property | Value |
|---|---|
| Core HP | 600 (`max_health`) |
| Turret HP | 120 each × 4 (`turret_health`) |
| Damage | 40 contact (`collision_damage`) |
| Score | 1000 (core only — turrets award nothing, see below) |
| Sprites | `station_core.png` (256×256), `station_turret.png` / `station_turret_destroyed.png` (64×64) |
| Scene | `space_station.tscn` (turret: `station_turret.tscn`) |
| Config | `space_station_config.tres` |

Sprites are authored at **final on-screen pixel size** and placed at `scale = 1`. They are **not**
multiplied by `ArenaCamera.WORLD_SCALE` — that constant applies only to authored spawn offsets
(`wave_manager.gd:172`) and `EnemyPathMover` paths (`enemy_path_mover.gd:77`). 256×256 is 4× the
64×64 player fighter; turrets are player-sized. Turret positions inside the scene (`±76, ±76`) are
sprite-local screen pixels, not design units. The station's *spawn* position, when sub-item 2
places it, **is** an authored offset and will be scaled.

---

## Behaviour

- **Armour rule.** `is_armored()` is `live_turret_count() > 0`, read live from `$Turrets` on every
  call — no cached array, no counter, so it cannot desync. While armoured, the core's
  `_on_received_damage` override emits `armor_deflected(damage)`, plays the hit flash, and
  **returns without touching `Health`**. When the last turret dies the override falls through to
  `BaseEnemy`, and the core takes damage normally.
- **Turrets** are plain `Node2D`s (they never move and never score). On death a turret swaps to the
  destroyed sprite, closes its hurtbox, explodes, emits `destroyed`, and **stays in the tree as
  wreckage** — so the station reads as damaged, and the live count stays a deterministic read
  rather than a `queue_free()` frame-timing race.
- **Death.** Core death is station death: `BaseEnemy._on_health_changed` explodes and
  `queue_free()`s.

---

## Why the core is *armoured*, not *unhittable*

The HurtBox stays fully live and damage is refused inside `_on_received_damage`. Disabling the
hurtbox would have been simpler and is **wrong**, because two shipped systems drive damage straight
into the signal with no physics involved:

- `plasma_nova_module.gd:39-41` — `n.get_node_or_null("HurtBox").received_damage.emit(_DAMAGE)`
- `beam_behavior.gd:75-76, 99-102` — the mining laser, same pattern over group `"enemies"`

Both collect group `"enemies"` and bypass collision entirely, so a disabled hurtbox would have
leaked both. Keeping it live also means the hit still registers visually, which is the whole
teaching signal. Do not "simplify" this into a disabled hurtbox.

---

## Collision layers — read this before changing the scene

| Node | Layer | Mask | Why |
|---|---|---|---|
| `SpaceStation` (root) | **0** | **0** | Deliberate; see below. |
| `HurtBox` (core) | 512 | 1121 (`97 \| 1024`) | Layer authored **in the scene** — `BaseEnemy._ready()` sets the *mask* only (`base_enemy.gd:25`) and never touches the layer. |
| `StationTurret/HurtBox` | 512 | 1121 | Set in `station_turret.gd::_ready()`; a plain `Node2D` has nothing setting it. |

Mask `97 | 1024` = bullets (64) + rockets (32) + layer 1 + asteroids (1024). Copying the gunship
scene's raw `collision_mask = 65` would omit bit 6 and **the player's homing and warhead missiles
would pass straight through** — the gunship only gets away with 65 because `BaseEnemy` overwrites
it.

**Root is layer 0 on purpose.** At the default layer 1, `beam_behavior.gd:9` rays against bodies
with `_RAY_BLOCK_MASK = 1 | 1024`, truncates the beam at the hull edge, then skips the blocker
itself (`beam_behavior.gd:90`) and culls everything past `seg_len` (`:94`) — which would make the
station **immune to the player's mining laser** and shield everything behind it. Layer 0 also stops
the player colliding with a 256×256 body. Contact damage is unaffected: it comes from the `HitBox`
on layer 256 built by `base_enemy.gd:53-55`. If the hull should later be a solid obstacle, the
opt-out is an `is_laser_blocking()` returning `false` (`beam_behavior.gd:67-68`).

⚠️ **Known coverage gap.** `tests/integration/test_space_station.gd` drives damage by emitting
`received_damage` directly, so it does **not** prove any of these layer values. A core no bullet
could ever hit passes all nine tests. They are verified by reading this scene; they are only
*proven* once the station is in a live level (sub-item 2).

---

## Scoring

The core awards `score_value` 1000 through the normal `BaseEnemy.died` path. **Turrets award
nothing.** There is deliberately no `turret_score_value`: `ScoreTracker` registers kills via
`WaveManager.enemy_spawned` + `BaseEnemy.died` (`score_tracker.gd:55-75`), and a turret is a
`Node2D` that is never spawned through `WaveManager` and never leaves the tree, so no payout path
exists. Adding one is a deliberate future change, not an oversight.

---

## Gotchas

- `Health.amount_changed` is declared with **zero** parameters but emitted with one
  (`health_component.gd:4` vs `:42`) — handlers here take one argument, or the engine errors.
- `Health.set_health()` emits on **every** call including 0 → 0, so a dead turret hit again would
  re-enter its death handler. Both `_on_received_damage` and `_on_health_changed` carry an `_alive`
  guard; each alone is sufficient, and removing **both** makes `destroyed` fire 4× instead of 1×
  (verified by mutation test).
- `BaseEnemy._add_contact_hitbox()` hardcodes `damage = 20` and ignores the config
  (`base_enemy.gd:56`), so `space_station.gd` re-applies `collision_damage` after `super._ready()`.
  It also copies the shape resource but **not** the `CollisionShape2D`'s `scale`/`position`, which
  is why this scene authors its shape at true size with `scale = 1`.

---

## Config exports

Read from `space_station_config.gd` / `space_station_config.tres`. `SpaceStationConfig extends
ShipConfig`, so the first four are inherited.

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `600` | Core HP. Applied in `_ready()`; the `.tres` **wins** over the scene's `Health` node. |
| `collision_damage` | `40` | Contact damage. Re-applied to the `HitBox` in `_ready()` — `BaseEnemy` would otherwise leave it at its hardcoded 20. |
| `score_value` | `1000` | Awarded on core death via `BaseEnemy.died`. |
| `counts_toward_wave_clear` | `true` | Inherited; no effect until the station is spawned through `WaveManager`. |
| `turret_health` | `120` | HP of **each** turret. `SpaceStation._ready()` writes it into every turret's `Health` (children ready before parents). |

There is no export for the turret count — turrets are authored as scene children under `Turrets`,
so adding or removing one is a scene edit. `live_turret_count()` reads the container live, so it
needs no matching code change.

---

## Spawn notes

**Not spawnable yet.** There is no `WaveBuilder` method for it and it appears in no level; it is
not in [`docs/enemy-roster.md`](../../../../docs/enemy-roster.md) for that reason. Sub-item 2 of the
Level 1 mini-boss epic adds a `station_assault` `LevelSection` between `asteroid_belt` and
`planet_approach` using `EndCondition.ENEMIES_CLEARED`.

Two requirements for whoever does that: `ENEMIES_CLEARED` polls
`wave_manager.enemy_container.get_child_count()` (`level_director.gd:106`) and **not** the
`"enemies"` group — so the station must be a **child of `enemy_container`** and must actually leave
the tree on death. Its spawn offset is authored in 640×360 design units and scaled by
`ArenaCamera.WORLD_SCALE`, unlike everything inside this scene.

---

## Files

```
space_station/
├── ENEMY.md                    ← this file
├── space_station.tscn          SpaceStation + 4 instanced turrets
├── space_station.gd            SpaceStation (extends BaseEnemy)
├── space_station_config.gd     SpaceStationConfig (extends ShipConfig)
├── space_station_config.tres
├── station_turret.tscn
└── station_turret.gd           StationTurret (Node2D)
```

Sprites: `assault/assets/sprites/enemies/station_core.png`, `station_turret.png`,
`station_turret_destroyed.png`.
Tests: `tests/integration/test_space_station.gd`.
