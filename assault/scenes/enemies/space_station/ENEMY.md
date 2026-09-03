# Space Station — Level 1 mini-boss (turret + laser phases, with a staged death)

**Role:** Two-phase cores-and-turrets mini-boss. Four turrets on a 256×256 hull, each on its own
HP bar; the core refuses **all** damage until the last turret dies. Every live turret fires an
aimed 3-bullet fan, so the armour is also the threat and each gun you kill visibly quietens the
station. Killing the last one flips the fight: the hull starts rotating, firing telegraphed
sweeping beams and precessing bullet rings from the exposed core.
**Fantasy / threat:** A fortress, not a ship. Shooting the hull sparks and does nothing, which
teaches the rule without any UI: kill the guns first, then the core. Stripping the armour is not a
reward — it wakes the superweapon up, and the second half is fought on the move.

> **Status: EPIC sub-items 1–3, 4a and 4b done.** The entity exists and is destructible (1), gates
> Level 1 as the `station_assault` section (2), has the rotating laser phase (3), **shoots back**
> with aimed turret fans and precessing core rings (4a), and now **calls for reinforcements** —
> squads of existing enemy ships crossing in from all four screen edges during phase 1 (4b). Still
> outstanding: no bespoke death sequence or handoff into `planet_approach` (sub-item 5). Plans and
> reviews:
> [`docs/plans/station-mini-boss-destructible/`](../../../../docs/plans/station-mini-boss-destructible/),
> [`docs/plans/station-assault-section/`](../../../../docs/plans/station-assault-section/),
> [`docs/plans/station-laser-phase/`](../../../../docs/plans/station-laser-phase/),
> [`docs/plans/station-bullet-hell/`](../../../../docs/plans/station-bullet-hell/),
> [`docs/plans/station-reinforcements/`](../../../../docs/plans/station-reinforcements/).

---

## Stats

| Property | Value |
|---|---|
| Core HP | 600 (`max_health`) |
| Turret HP | 120 each × 4 (`turret_health`) |
| Damage | 40 contact (`collision_damage`), 12/turret bullet, 10/core-ring bullet |
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

**Turret orientation is a *spawn* orientation only.** All four turrets are authored at
`rotation = 0`, and the sprite's barrels point along local **−Y** (screen top, i.e. *away* from the
player). Since sub-item 4a, `StationGunnery.fire_turret_volley()` writes each firing turret's
`global_rotation` to `aim.angle() + PI/2` immediately before it fires, so the barrel points at the
player — `global_rotation`, not `rotation`, so it stays correct while the hull spins. Nothing sets
the rotation *between* volleys, and during the laser phase the whole station rotates, so the turret
**wrecks** spin with it.

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
  `StationGunnery` hangs off the same signal, as intended, rather than fanning out over the turrets
  a second time.
- **Death.** Core death is station death: `BaseEnemy._on_health_changed` explodes and
  `queue_free()`s.

---

## Gunnery (`Gunnery` → `station_gunnery.gd`)

`StationGunnery` is a second `Node2D` child of `space_station.tscn`, modelled on its sibling
`StationLaserPhase` and for the same reason: `space_station.gd` holds **no gun logic at all** and
gained only the `turrets()` data accessor. It drives one `RadialAttackPattern` per phase on its own
`Timer`s, rather than through `AttackController` (which assumes one pattern on one ship).

- **Phase 1 — aimed turret fans.** Every **live** turret fires a `turret_burst_count`-bullet fan of
  angular width `turret_burst_arc`, centred on the player, all on one shared `turret_fire_interval`
  cadence. One legible chunk beats four independently drifting cadences, and it makes "one fewer
  gun" instantly readable: `_live_turrets()` re-reads `SpaceStation.turrets()` per volley, so a
  destroyed gun drops out for free with no bookkeeping. **The armour is therefore also the threat.**
- **The first volley lands one full interval after spawn**, never on spawn — the player's grace
  period to register the boss. No config field needed; it falls out of `Timer.start()`.
- **Phase 2 — precessing core rings.** `armor_broken` stops the turret cadence and starts
  `core_ring_interval` full rings of `core_ring_count` bullets from the hull rim, each advanced by
  `core_ring_step` radians from the last. The first ring lands one interval *after* the handover,
  because `StationLaserPhase` already fires a beam volley on that same frame.
- **A forced volley in the wrong phase fires nothing** — `fire_turret_volley()` early-returns once
  `is_core_firing()`, `fire_core_ring()` before it. Both are public so tests can drive a volley
  without awaiting a real interval.
- **Deliberately no `randf()`**, same rule as the laser phase: `test_volleys_are_deterministic`
  fails the moment someone reaches for RNG.
- **Teardown.** Connected to `BaseEnemy.died`: stops both timers. In-flight bullets are freed by
  `BulletPool._exit_tree()` when the pool leaves the tree with the station — which matters because
  `LevelSection.ENEMIES_CLEARED` polls the container's child count, so a bullet outliving the boss
  would hold the section open.
- **No self-damage, in either direction.** `enemy_bullet.tscn`'s `HitBox` is layer 256 / **mask 128**
  (the player hurtbox only), and the core `HurtBox` mask `97 | 1024` excludes 256. So the
  `hit_mask_override` dance the beams need has **no analogue here**.

### ⚠️ The `BulletPool` must stay a *direct* child of `SpaceStation`

`bullet_pool.gd:47` hardcodes its container as `get_parent().get_parent()`, with no override. Only
`pool → station → enemy_container` puts in-flight bullets in unrotated world space like every other
enemy's. Placed under `Gunnery` or a turret, the grandparent is the **station itself** — and
`StationLaserPhase` rotates the hull, so the entire bullet field would swing around with it.

It is therefore **authored in the scene**, and the gunnery node only *drives* it. That is not a
style preference: a child cannot `add_child()` onto its own parent from `_ready()`, because
`Node::_propagate_ready()` sets `data.blocked` on the parent before readying its children and the
call fails hard. Authoring it in `space_station.tscn` makes the placement a structural property of
the scene file rather than a comment someone can violate later.
`test_station_gunnery.gd::test_the_pool_is_a_direct_child_of_the_station` is the regression test.

`pool_size` is **48**. Phase 1 peaks at 4 × 3 / 1.8 s = 6.7 bullets/s and a bullet needs ~4.1 s to
clear the arena, so ~27 in flight; phase 2 adds ~23. The phases **overlap** at the handover, so the
real peak is ~27 leftovers + 10 ≈ 37, not `max(27, 23)`.

⚠️ **The `Gunnery` node tag needs `node_paths=PackedStringArray("bullet_pool")`.** The text scene
format only resolves an exported `Node` reference when the node tag declares it; without it the
export is left `null`, **no error is printed and the gate stays green** — only the script's
`get_node_or_null` fallback would save it.

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

## Reinforcements (`Reinforcements` → `station_reinforcements.gd`)

Sub-item 4b. **Phase 1 only.** While the turrets are still up, the station calls in squads of
existing enemy ships that cross the arena. Before this the fight was a duel in a vacuum: the
player picked a comfortable spot below the hull and streamed into one turret at a time. Now the
safe spot for dodging turret fans is not the safe spot when an interceptor is strafing through it.

The third sibling behaviour node, on the same pattern as `LaserPhase` and `Gunnery`. This one is
the purest version of the split — **`space_station.gd` gained nothing at all**, not even an
accessor.

### The squad table

Fixed, cycling, **never `randf()`** — the same rule the beam angle list follows, and for the same
reason. Order is `LEFT → RIGHT → BOTTOM → TOP`, so consecutive squads arrive from opposite sides
and pull the player across the screen rather than nudging them.

| # | Edge | Ships | Offsets (design units) | Movement |
|---|---|---|---|---|
| 0 | Left | 2 × `interceptor` | (-440, 20), (-440, 80) | `straight(200, PI/2)` — rightward |
| 1 | Right | 2 × `interceptor` | (440, 20), (440, 80) | `straight(200, -PI/2)` — leftward |
| 2 | Bottom | 2 × `kamikaze_drone` | (-100, 290), (100, 290) | `straight(170, PI)` — upward |
| 3 | Top | 2 × `fighter` + `.shoot_forward()` | (-250, -290), (250, -290) | `straight(170, ±0.5)` — down-and-inward |

Every entry also gets `.free_after(reinforcement_lifetime)` (7.0 s).

Squads are authored with **`WaveBuilder`'s own fluent API** and stored as
`Array[SpawnEntryResource]` via `b.wave(0.0, […]).entries`, so they read in exactly the vocabulary
of [`docs/enemy-roster.md`](../../../../docs/enemy-roster.md) instead of a second one invented
here. Offsets are **640×360 design units** multiplied by `ArenaCamera.WORLD_SCALE` once at spawn;
speeds are left **unscaled**, because `EnemyPathMover` applies the scale itself — pre-multiplying
either would double it.

Why these numbers:

- **±440 / ±290 design.** The margin has to exceed half the largest sprite plus the camera's pan.
  The largest reinforcement is the interceptor at **64×74** (its `Sprite2D` carries no `scale` —
  the `1.8` in `interceptor.tscn` is on the sibling `CollisionShape2D`), so half-extent **37**.
  Horizontal budget `640 + H_LIMIT 100 + 37 = 777` world px; vertical `360 + 37 = 397`, with
  `V_LIMIT` deliberately excluded because every spawn in the game resolves against the camera's
  *fixed* centre and not the panned view. ±440 gives 880 and ±290 gives 580.
- **Side lanes at design y = 20 / 80**, the vertical middle — not hugging a border, which creates
  traps the player cannot escape.
- **Top squad enters at x = ±250 angled inward**, clearing the hull by 41.8 design units against a
  16-unit sprite half-extent.

### ⚠️ Reinforcements are *siblings* of the station, never children

`_container()` is `_station.get_parent()` — `WaveManager.enemy_container` in the level, the same
place waves land. Parenting one under the station would drag it around the arena, because
`StationLaserPhase` writes `_station.rotation`; and an `interceptor` or `fighter` builds its **own**
`BulletPool`, whose container is the hardcoded `get_parent().get_parent()`, so its bullet field
would swing with the hull too. Same trap as the station's own pool, one level out.

### ⚠️ `FREE_ON_DURATION`, never `FREE_ON_SCREEN_EXIT`

`FREE_ON_SCREEN_EXIT` only culls a ship **after** it has been on screen at least once. A ship
spawned off screen that never quite arrives would live forever — and `LevelSection.ENEMIES_CLEARED`
polls the container's child count, so it would hold the section open behind a 180 s timeout. Every
entry therefore carries an explicit `exit_time`.

### Scoring, and the combo cost

Each ship is announced on **`EventBus.enemy_spawned_orphan`**, the channel `big_asteroid.gd`
already uses for its shards. `ScoreTracker` routes it to `_on_enemy_spawned(enemy, -1)`, so a
reinforcement kill pays out and the `-1` keeps it out of every wave-clear tally.

That also opts these ships into the game's **universal escape penalty**: `_on_enemy_freed`
multiplies the combo by `escape_combo_multiplier` (0.75) *outside* its `if counts_in_wave:` block,
so `wave_index == -1` does not exempt it. A squad the player ignores costs 0.75 **twice**, i.e.
0.5625. This is a **deliberate balance decision**, pinned by a test with real numbers — the
alternative (not announcing) means killing a reinforcement awards nothing at all, which reads as a
bug. Raised in `BACKLOG.md` under *Discovered* for the user to overrule.

### The cap

`reinforcement_max_alive` (4) **skips a whole squad** rather than spawning part of one, so the
ceiling is exactly 4 — an "already at the cap?" check would let a 2-ship squad through at 3 alive
and peak at 5. The live list is pruned with `is_instance_valid` on every squad; without the prune
the cap jams permanently once four ships have been culled. When a squad is skipped the **cycle
still advances**, so a capped fight does not freeze the rotation on one edge.

### Lifecycle

| Event | Effect |
|---|---|
| `_ready()` | Copy config, build the squad table, `_timer.start(reinforcement_first_delay)` |
| `_timer.timeout` → `_on_timer_timeout()` | `spawn_next_squad()`, **then** `_timer.start(reinforcement_interval)` |
| `armor_broken` | `_stop()` — phase 2 is the station's own show |
| `died` | `_stop()` — the backstop |

The `Timer` is `one_shot` and is restarted **only** from `_on_timer_timeout()`. `spawn_next_squad()`
touches no timer at all, which is what lets a test force squads without re-arming the timer it just
asserted stopped.

Ships already in flight when `_stop()` runs are left alone: they are on a `FREE_ON_DURATION` mover
and cull themselves within 7 s, well before the boss can die.
---

## Death sequence (`DeathSequence` → `station_death_sequence.gd`)

Before EPIC sub-item 5 the 256×256 mini-boss vanished **between one frame and the next** behind a
single 22-particle burst — the identical death a 40 px interceptor gets — because
`base_enemy.gd:65-73` emits `died` and calls `queue_free()` in the same call. Four sessions of
build-up ended with a poof.

The split is deliberate and is the fifth instance of the same composition pattern:

| Owner | Responsibility |
|---|---|
| `space_station.gd` | **Lifetime only.** Latch the death, emit `died` + set `was_killed` at the true moment HP hits 0, disarm the corpse, hold the wreck for `death_duration`, then free it. |
| `station_death_sequence.gd` | **Spectacle only.** The blast chain, the shake, the drift and the darkening. |
| `station_gunnery.gd` | Additionally calls `bullet_pool.cancel_active()` on `died`. |

### ⚠️ The station owns `queue_free()`, not the sequence node

If the *visual* node called `queue_free()`, a station whose `DeathSequence` was renamed or removed
would never leave the enemy container, and `station_assault` would hang for its full **180 s**
timeout with no error at all — then take the 0.75× escape-combo penalty. The station owns the
timer and the free; the sequence node only draws. Deleting it costs the explosions and nothing
else.

### ⚠️ The `ExplosionEffect` is a child of the *station*, never of the sequence node

`explosion_effect.gd:28` reads `actor = get_parent()` and `:31` reads
`container = actor.get_parent()`. Parented to `DeathSequence` — itself a child of the station —
that chain is **one hop short**: the particles become children of the *hull*, where they are
freed with the wreck, never enter the container `LevelDirector._wait_enemies_cleared()` polls, and
rotate with the dying hull's spin. Same hazard the `BulletPool` and `Reinforcements` notes above
describe, for the same reason.

It is therefore added to `_station` lazily, in the `death_started` handler — **not** in
`_ready()`, because `_propagate_ready()` blocks the parent while it readies its children, exactly
as the `BulletPool` note explains.

`tests/integration/test_station_death_sequence.gd::test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre`
is the regression test. **If it fails, the node placement is wrong — do not weaken the test.**

### The chain

Seven blasts roll across the hull over 1.8 s at **deterministic** hull-local offsets — a fixed
table of eight unit vectors cycled by blast index, never `randf()`, for the same reason the beam
angles and the squad order are fixed lists: random ordering cannot be balanced or asserted. The
offsets are exposed as `blast_offset(i)`, a pure function of the index with no transform, time or
RNG in it, which is what makes determinism testable. Consecutive blasts land on *opposite* sides
of the hull, so the chain reads as a disintegration rather than a spinner.

Then one final central blast at `_finish()`, and the station frees itself on its own timer.

- **Cadence is derived from `_station.death_duration`, not from a second copy of the config.**
  The station owns the timer that frees the wreck, so two independent copies could desync and
  leave the chain firing into a freed station. Reading a sibling's per-instance var is not a
  shared-`.tres` read; `station_gunnery.gd:153` reads live station state the same way.
- **The hull drifts and darkens** — `death_spin` (1.2 rad/s) decaying linearly to 0, and
  `modulate` lerped toward `burnt_tint`. The hull is *already* rotating in phase 2, so a hard stop
  at death would be the more jarring option. The darkening works only because `hit_flash_vs.tres`
  passes the incoming vertex colour through when `enabled` is false.
- **Shake:** `blast_shake` (0.25) per blast and `final_shake` (1.0) on the finale. Note the chain
  shake is **deliberately near-invisible**: `CameraShake` decays at 1.5/s and the blasts are
  ~0.26 s apart, so it never accumulates past ~0.25 trauma ≈ a 0.5 px offset. Do not "fix" that by
  raising the value — nothing an enemy does shakes this game's screen at all, and the finale is
  where the budget is meant to be spent.

### The corpse is harmless

From the instant HP hits 0:

- `hurt_box.monitoring` → `false` (deferred).
- The contact `HitBox`'s `collision_layer` → `0` (deferred). The player's HurtBox is the side that
  *monitors* (mask 1281), so zeroing the layer is what stops a dead hull ramming the player.
- `bullet_pool.cancel_active()` — **new, and required by this change.** Previously
  `BulletPool._exit_tree()` freed in-flight bullets at the moment of death because the station was
  freed in the same frame. The wreck now lingers ~1.8 s, so without the explicit call the corpse
  would keep a full ring of live bullets in the air and could kill the player while visibly
  exploding. Those bullets also live in the enemy container, so they would hold `ENEMIES_CLEARED`
  open.

Note `cancel_active()` permanently **shrinks** the pool — `_recycle()` is the only path back into
`_idle` and this frees the bullets instead. That is fine for a dying boss and is pinned by a test.

### ⚠️ `died` and `was_killed` fire at HP 0, not when the wreck is freed

`ScoreTracker` connects its kill path to `died` (`score_tracker.gd:151-164`) and its escape path
to `tree_exited`, discriminating on `was_killed` (`:201`). Deferring either to `_finish_death()`
would score the boss as an **escape** and multiply the combo by 0.75 (`:211`) — a silent scoring
regression no test of the *visuals* would catch. Only `queue_free()` moved.

The `_dying` latch is what stops a stray bullet re-running the whole path: `Health.set_health()`
emits `amount_changed` unconditionally, so a hit on a 0-HP station re-enters `_on_health_changed`.

### The handoff needs no director change

`LevelDirector._wait_enemies_cleared()` polls the enemy container's child count
(`level_director.gd:116`), so a station that stays parented while it dies holds `station_assault`
open **for free**, and the section advances the moment the wreck and its last particles leave.
The blast particles live in the container deliberately: the level does not transition
mid-explosion. `tests/integration/test_level_1_sequence.gd` walks the real five-section sequence
with a real station killed in the middle and asserts it reaches `level_complete`.

### Boundary: `death_duration = 0.0`

The script default is `0.0` and that is the honest fallback, not an oversight — at zero the
station is freed in the same frame, exactly as every other enemy, so a station with **no** config
behaves precisely as `BaseEnemy` always has. The shipped `.tres` carries 1.8. Pinned by
`test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour`.

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

- `Health.amount_changed` is declared and emitted with one argument (`health_component.gd:10`
  and `:53`) — handlers here take one argument, or the engine errors.
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
| `turret_fire_interval` | `1.8` | Seconds between turret volleys. All live turrets fire on the same tick: 4 × 3 / 1.8 s = **6.7 bullets/s** at full strength, decaying to 1.7 with one gun left. |
| `turret_burst_count` | `3` | Bullets in each turret's fan. Three is the smallest chunk that reads as a line rather than a stray shot. |
| `turret_burst_arc` | `0.35` | Fan width in radians (~20°). Wide enough that strafing does not dodge all three, narrow enough to still read as one fan. |
| `turret_bullet_damage` | `12` | Between the interceptor's 4 and the gunship's 15 — four turrets firing at once must not out-damage the station's own 40-damage contact hit. |
| `turret_bullet_speed` | `240.0` | 60 % of the player's 400 px/s top speed (`move_state.gd:21`), inside the shipped 220–260 band. |
| `core_ring_interval` | `2.0` | Seconds between core rings once the armour is broken. 5 bullets/s alongside the 6.5 s laser cycle, so phase 2 changes every ~2 s. |
| `core_ring_count` | `10` | Bullets per ring. Spacing `TAU/10` = 36°; at 300 px from the hull that is a ~188 px gap, dodgeable at 400 px/s. |
| `core_ring_step` | `0.24` | Radians the ring's base angle advances between rings. **Do not "tidy" this to a round fraction of `TAU`** — see below. |
| `core_bullet_damage` | `10` | Lower than the turret fan: ring bullets cannot be avoided by position alone, so they hit softer. |
| `core_bullet_speed` | `210.0` | 52 % of player speed — the slowest of the three, because phase 2 already has sweeping beams to dodge. |
| `reinforcement_first_delay` | `8.0` | Seconds to the first squad. The opening belongs to the boss alone — adds arriving during a boss's introduction are the main way a boss ends up overshadowed by its own minions. Roughly two turret volleys plus the time to read the hull. |
| `reinforcement_interval` | `10.0` | Seconds between squads after the first. The top of the 5–10 s attack-switch band, so a squad lands as an *event* punctuating the 1.8 s turret cadence rather than blurring into it. Over a ~25–35 s phase 1 that is 2–3 squads. |
| `reinforcement_max_alive` | `4` | Hard ceiling on live reinforcements, i.e. two squads. A squad is skipped **whole** when it would breach this, so the ceiling is exactly 4. Readability valve for a stalled fight; at a 10 s interval against a ~4 s transit it should not bind in normal play. |
| `death_sequence_duration` | `1.8` (script `0.0`) | Seconds the wreck stays in the tree after HP hits 0, before it is freed. The script default `0.0` is the honest fallback — a station with no config is freed in the same frame, exactly as `BaseEnemy` always did. Copied into `SpaceStation.death_duration` in `_ready()`; tests override **that**, never the shared `.tres`. |
| `death_blast_count` | `7` (script `3`) | Explosions in the chain that rolls across the hull before the final central blast. Seven reads as a chain; three reads as a hiccup. |

⚠️ **`core_ring_step = 0.24` is load-bearing and is pinned by a test.** It comes from the golden
angle: `spacing * 0.381966` = `(TAU/10) * 0.381966`, i.e. a spacing-to-step ratio of 2.618. The
golden ratio is the irrational least well approximated by small rationals, which is exactly the
"maximal lane coverage per ring" property wanted here. The value **0.21** that the plan originally
carried is wrong: `3 × 0.21 = 0.63` against a `0.6283` spacing, so the ring collapses onto three
radial lanes and stays there — a permanent safe lane the player can park in. Measured over 20
rings, 0.21 leaves a largest lane gap of **31.8 %** of the spacing; 0.24 leaves **9.0 %**.
`test_the_ring_step_leaves_no_permanent_safe_lane` reads the step and count off the *gunnery node*
(so it locks the shipped `.tres`, not a literal) and rejects anything above 25 % — a bound that
deliberately catches re-tread periods 2, 3 and 4 but not 5+.

The gunnery timings are read exactly once, by `StationGunnery._ready()`, for the same process-wide
`.tres` reason spelled out below. The two `spawn_radius` values are **not** in the config —
`turret_spawn_radius = 26.0` (the turret hurtbox rim) and `core_spawn_radius = 130.0` (outside the
240×240 hull) are scene geometry, so they are exports on the gunnery node, exactly as
`emitter_radius` is on the phase node.

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
like everything else inside this scene. The two gunnery `spawn_radius` values and
`StationReinforcements.reinforcement_lifetime` (7.0 s) follow the same rule, as does the whole
**squad table** — offsets, ships and movements are geometry that lives next to each other in
`station_reinforcements.gd`, not a set of tunable stats.

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
├── space_station.tscn          SpaceStation + 4 turrets + LaserPhase + BulletPool + Gunnery
│                            + Reinforcements + DeathSequence
├── space_station.gd            SpaceStation (extends BaseEnemy)
├── space_station_config.gd     SpaceStationConfig (extends ShipConfig)
├── space_station_config.tres
├── station_turret.tscn
├── station_turret.gd           StationTurret (Node2D)
├── station_laser_phase.gd      StationLaserPhase (Node2D) — the second phase
├── station_gunnery.gd          StationGunnery (Node2D) — the guns, both phases
├── station_reinforcements.gd   StationReinforcements (Node2D) — phase-1 add squads
└── station_death_sequence.gd   StationDeathSequence (Node2D) — the death spectacle
```

Shared code it depends on: `global/resources/attack/radial_attack_pattern.gd`
(`RadialAttackPattern`, added for this boss but generic) and `global/components/bullet_pool.gd`.

Sprites: `assault/assets/sprites/enemies/station_core.png`, `station_turret.png`,
`station_turret_destroyed.png`. The laser phase adds **no new art** — it reuses
`assault/scenes/hazards/laser_ray/laser_ray.tscn`'s existing frames.
Tests: `tests/integration/test_space_station.gd` (armour rule, turret lifecycle, config),
`tests/integration/test_station_laser_phase.gd` (trigger, telegraph window, self-damage
regression, rotation rate, volley determinism, teardown, config),
`tests/integration/test_laser_ray_hit_mask.gd` (the shared `LaserRay` export),
`tests/integration/test_station_gunnery.gd` (pool placement, both phases, aim, barrel rotation,
ring precession, the `core_ring_step` design lock, teardown, config),
`tests/integration/test_radial_attack_pattern.gd` (the shared pattern resource).
`tests/integration/test_station_reinforcements.gd` (config copy, four-edge coverage, the
off-screen spawn margin, deterministic cycling, sibling parenting, movement direction, the
`FREE_ON_DURATION` guarantee, orphan-spawn registration, both stop signals, the whole-squad cap,
the timer split, that every squad ship is killable by the primary weapon, and the combo cost).
