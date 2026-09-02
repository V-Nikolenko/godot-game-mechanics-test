# Space Station — Level 1 mini-boss (turret + laser phases)

**Role:** Two-phase cores-and-turrets mini-boss. Four turrets on a 256×256 hull, each on its own
HP bar; the core refuses **all** damage until the last turret dies. Killing the last turret flips
the fight: the hull starts rotating and firing telegraphed sweeping beams.
**Fantasy / threat:** A fortress, not a ship. Shooting the hull sparks and does nothing, which
teaches the rule without any UI: kill the guns first, then the core. Stripping the armour is not a
reward — it wakes the superweapon up, and the second half is fought on the move.

> **Status: EPIC sub-items 1–3 done.** The entity exists and is destructible (1), gates Level 1
> as the `station_assault` section (2), and has the rotating laser phase (3). It still has **no
> turret fire, no bullet-hell patterns and no reinforcements** (sub-item 4), and no bespoke death
> sequence or handoff into `planet_approach` (sub-item 5). Plans and reviews:
> [`docs/plans/station-mini-boss-destructible/`](../../../../docs/plans/station-mini-boss-destructible/),
> [`docs/plans/station-assault-section/`](../../../../docs/plans/station-assault-section/),
> [`docs/plans/station-laser-phase/`](../../../../docs/plans/station-laser-phase/).

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
sprite-local screen pixels, not design units. The station's *spawn* position — `at(0, -90)` in
`_build_station_assault()` — **is** an authored offset and *is* scaled.

### Sprite provenance — reproduce these exact parameters

Both turret sprites shipped first as **3/4 views** (visible barrel side faces, base in
perspective) and were regenerated on **2026-09-01**. The root cause was the *tool*, not the
prompt. They were made with `create_image_pixflux`, whose `view` parameter **defaults to `null`
and is documented as "weakly guiding"** — so an unset camera is unconstrained, and even setting it
is only a soft hint. `create_map_object` defaults `view` to `"high top-down"` and treats it as a
real control. Regenerate only with the parameters below — the `pixel-art-generation` skill
mandates them.

| Sprite | Tool | Parameters |
|---|---|---|
| `station_turret.png` | `create_map_object` | `view: "high top-down"`, `outline: "lineless"`, `detail: "medium detail"`, `shading: "medium shading"`, 64×64 |
| `station_turret_destroyed.png` | `create_object_state` off the intact turret | inherits the source's view; keeps the footprint and palette aligned |
| `station_core.png` | `create_image_pixflux` (original) | **has an opaque background** — see *Discovered* in `BACKLOG.md` |

The prompt that worked names the 2D shapes seen from above — "the base reads as a flat **circle**,
the barrels as two short flat **rectangles** lying across it" — plus the skill's negative list.
Describing the object rather than saying "top-down" is the part that actually constrains the model.

**Turret orientation is not wired up.** All four turrets are placed at `rotation = 0`, so the
barrels point toward −Y (screen top, i.e. *away* from the player). Harmless today because turrets
do not fire; EPIC sub-item 4 should set per-turret `rotation` when it adds firing. Note that during
the laser phase the whole station rotates, so the turret **wrecks** spin with it — the authored
`rotation = 0` is a *spawn* orientation, not a permanent one.

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
- **Phase transition.** When `live_turret_count()` reaches 0, `SpaceStation` emits the zero-argument
  **`armor_broken`** signal, latched by `_armor_broken` so it fires exactly once. That is the only
  laser-related thing on `space_station.gd` — all the behaviour lives on the `LaserPhase` child.
  Sub-item 4's escalating fire should hang off the same signal rather than a second fan-out over
  the turrets.
- **Death.** Core death is station death: `BaseEnemy._on_health_changed` explodes and
  `queue_free()`s.

---

## Laser phase (`LaserPhase` → `station_laser_phase.gd`)

`StationLaserPhase` is a `Node2D` child of `space_station.tscn` that owns the entire second phase:
the trigger, the rotation, the volley cycle and the beams. Composition, per `CLAUDE.md` — the
station is already assembled from components, and this is one more child.

- **Trigger.** Connects to `SpaceStation.armor_broken`; does nothing at all before it. `is_active()`
  is the observable.
- **Rotation.** `_physics_process` does `_station.rotation += rotation_speed * delta` while active.
  Constant angular velocity, no easing — a predictable sweep is what makes it dodgeable. Beams are
  children of this node, which is a child of the station, so rotating the station sweeps every live
  beam for free; there is no per-beam rotation code.
- **Volleys.** The first fires immediately on `armor_broken` (waiting a full interval reads as the
  boss having *stopped*), then every `laser_volley_interval`. Volley `k` spawns
  `laser_beam_count` beams at local angles `_VOLLEY_ANGLES[k % 4] + i * TAU / beam_count`, where
  `_VOLLEY_ANGLES` is `[0, PI/2, PI/4, 3PI/4]`.
- **Deliberately no `randf()`.** Random attack ordering is the documented boss-design mistake: it
  cannot be balanced and it cannot be tested. The station is rotating underneath anyway, so every
  volley's *world* angle differs; the fixed list adds a second, controlled axis of variation with a
  known value range. `test_volley_angles_are_deterministic` fails the moment someone reaches for
  RNG.
- **Beams** are plain `laser_ray.tscn` instances — `LaserRay` already has the telegraph, charge-up,
  active window, auto-dissolve, the 0.1 s re-hit tick, `is_lethal_now()` and `dissolve()`. Spawned
  with `auto_start = false`, then positioned and `start()`ed, because `auto_start` defaults to
  **true** and an early `add_child()` telegraphs a frame at the origin with rotation 0.
- **Teardown.** Connected to `BaseEnemy.died`: cancels the volley timer, clears `_active`, and
  `dissolve()`s or `queue_free()`s every live beam. `BaseEnemy` frees the station in the same call,
  so the beams would go with the subtree anyway — but a beam lethal on *that* frame would still get
  one kill out of a corpse, and `LevelSection.ENEMIES_CLEARED` polls the container's child count,
  so nothing this node creates may outlive the station.

### ⚠️ The station's beams must not use the default hit mask

`LaserRay._HIT_MASK` is `128 | 256 | 512`, and the station's own core `HurtBox` is on **layer 512**
— deliberately kept live (see below). A beam fired from inside the hull on the default mask takes
the station **600 → 0 HP in one frame**, i.e. the boss kills itself the instant its laser phase
starts. Reproduced, not theorised.

`_spawn_beam()` therefore sets `laser.hit_mask_override = 128` (player hurtbox only) **before**
`add_child()`, because that is when `LaserRay._ready()` reads it. `hit_mask_override` was added to
`laser_ray.gd` for this; `0` means "use the default", so every other caller is unchanged.

The overlap is **angle-dependent**, which matters for the test: at `emitter_radius = 140` an
axis-aligned beam starts 20 px clear of the 240×240 core hurtbox and never touches it, but the
half-diagonal is ~170 px, so a diagonal emitter sits ~30 px *inside* the hull. Only volleys 2 and 3
self-kill. `test_beam_does_not_damage_the_station_that_fires_it` forces volley index 2 for exactly
that reason — on volley 0 it would pass with the fix reverted. **If the emitter is ever moved
outside the hull on all angles, that test's health assertion goes vacuous and only its
collision-mask assertion still bites.**

### Rotation side-effects — all intended

- The hull spins, and so do the four turret **wrecks**.
- The 240×240 core `HurtBox` and the contact `HitBox` spin with it, so at 45° the corners reach
  ~34 px beyond the axis-aligned footprint. The collision table below reads as if static; it is
  static only during the turret phase.
- Nothing else writes `_station.rotation`: the station's wave entry has no `.move()`, so
  `WaveManager` attaches no `EnemyPathMover` and never sets rotation itself.

If the sweep reads badly in play, `laser_rotation_speed` is the single knob.

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

⚠️ **Known coverage gap — still open.** `tests/integration/test_space_station.gd` drives damage by
emitting `received_damage` directly, so it does **not** prove any of these layer values. A core no
bullet could ever hit passes all nine tests. Sub-item 2 placed the station in a live level but did
**not** close this: `tests/integration/test_station_assault_section.gd` asserts the section's
gating and wave data, not a projectile overlap. Closing it needs a test that instances
`assault/scenes/projectiles/bullets/bullet.tscn` and steps physics.

For the record, because it was got wrong twice during sub-item 2's review: a player bullet is
**not** consumed by the first HurtBox it overlaps. `BulletPool` is used only by four enemies and
the ally fighter — `straight_behavior.gd:22` just does `state.add_child(bullet)` — so
`Bullet.expired` has no listener on the player path, and `default.tres` sets `range_px = 0.0` so
`bullet.gd:49` never frees it either. A bullet crosses the armoured core (deflected) and goes on
to hit the turrets behind it.

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
| `laser_warn_duration` | `1.4` | Seconds the beam holds its warning line. Time-to-lethal is `warn + ~0.56 s` (the `laser_increase` charge-up), so ~**1.9–2.0 s** of tell, measured across runs at process-frame granularity. ~6× the 0.3 s human reaction floor. Deliberately shorter than the 3.0 s Level 1's static laser columns use, which would not fit twice inside a volley cycle. |
| `laser_active_duration` | `2.0` | Seconds the beam stays lethal once armed. |
| `laser_volley_interval` | `6.5` | Volley start to volley start. Must exceed the full beam lifetime (`warn + 0.56 + active + 0.84` dissolve ≈ **4.8 s**), leaving ~1.7 s of clear screen. |
| `laser_rotation_speed` | `0.5` | Radians/second the whole station rotates while the phase is active (~29°/s). At the ~400 px the player sits from the station the beam edge moves ~200 px/s — half the player's 400 px/s top speed (`move_state.gd:21`). One 2.0 s active window sweeps ~57°. |
| `laser_beam_count` | `2` | Beams per volley, spread evenly. Two opposed beams sweep the plane while always leaving two large clear quadrants. |

**The laser timings are read exactly once**, by `StationLaserPhase._ready()`, which copies them
into its own fields; nothing reads `config` afterwards. That is not a micro-optimisation —
`space_station.gd` `load()`s the `.tres` and `ResourceLoader` caches, so **every `SpaceStation` in
the process shares one `SpaceStationConfig`**, and it is the same object `preload()` hands a test.
Reading through it at runtime is reading mutable global state; a test writing to it to shorten the
timings would permanently rewrite the shipped values for the rest of the process. Tests override
the **phase node's** fields instead. The phase's own field defaults are a conservative fallback for
a null config (longer telegraph, shorter lethal window, no rotation, one beam) and are
intentionally different from the `.tres`, which is what stops the config test passing vacuously.

`laser_emitter_radius` is deliberately **not** in the config — it is scene geometry, not a stat, so
it is `@export var emitter_radius: float = 140.0` on `StationLaserPhase`, in final on-screen pixels
like everything else inside this scene.

There is no export for the turret count — turrets are authored as scene children under `Turrets`,
so adding or removing one is a scene edit. `live_turret_count()` reads the container live, so it
needs no matching code change.

---

## Spawn notes

**WaveBuilder method:** `b.space_station()` (`SPACE_STATION` in `wave_builder.gd`). It is spawned
by the `station_assault` section of Level 1 (`level_1_director.gd::_build_station_assault()`) as a
single wave, `b.wave(0.0, [ b.space_station().at(0, -90) ])`, and by nothing else. See
[`docs/enemy-roster.md`](../../../../docs/enemy-roster.md).

Four things that section gets right and any future placement must too:

- **No `.delay()`.** `waves_complete` fires when the last wave *triggers*, not when its spawns
  land (`wave_manager.gd:52-56` vs `:151-155`), so a delayed station lets `_wait_enemies_cleared()`
  see an empty container and advance immediately.
- **No `.move()`.** `WaveManager` attaches an `EnemyPathMover` only for a real `MovementResource`
  (`wave_manager.gd:194`); with one, the boss would be freed on screen exit mid-fight.
- **`ENEMIES_CLEARED` polls the container, not the group.** `level_director.gd` counts
  `wave_manager.enemy_container.get_child_count()` and **not** `get_nodes_in_group("enemies")`, so
  the station must be a child of `enemy_container` and must actually leave the tree on death.
- **The offset is in 640x360 design units**, scaled by `ArenaCamera.WORLD_SCALE`, unlike every
  measurement inside this scene. `at(0, -90)` puts the hull at world y 52-308.

The section sets `enemies_cleared_timeout = 180.0`. If the station is somehow still alive then, the
director frees it and advances rather than stalling the level — at the cost of one escape-combo
penalty. That is a safety net, not a balance number.

---

## Files

```
space_station/
├── ENEMY.md                    ← this file
├── space_station.tscn          SpaceStation + 4 instanced turrets + LaserPhase
├── space_station.gd            SpaceStation (extends BaseEnemy)
├── space_station_config.gd     SpaceStationConfig (extends ShipConfig)
├── space_station_config.tres
├── station_turret.tscn
├── station_turret.gd           StationTurret (Node2D)
└── station_laser_phase.gd      StationLaserPhase (Node2D) — the second phase
```

Sprites: `assault/assets/sprites/enemies/station_core.png`, `station_turret.png`,
`station_turret_destroyed.png`. The laser phase adds **no new art** — it reuses
`assault/scenes/hazards/laser_ray/laser_ray.tscn`'s existing frames.
Tests: `tests/integration/test_space_station.gd` (armour rule, turret lifecycle, config),
`tests/integration/test_station_laser_phase.gd` (trigger, telegraph window, self-damage
regression, rotation rate, volley determinism, teardown, config),
`tests/integration/test_laser_ray_hit_mask.gd` (the shared `LaserRay` export).
