# Context — station bullet-hell fire (EPIC sub-item 4)

## Scope decision made at stage 1: the backlog item is split

`BACKLOG.md`'s sub-item 4 bundles **two independent subsystems**:

1. turrets and the core firing bullet-hell patterns, and
2. reinforcement ships flying in from at least three screen edges.

They share no code: (1) is a weapon composed from the existing `AttackPatternResource` /
`BulletPool` pair and lives entirely inside `space_station.tscn`; (2) is a *spawner* that has to
negotiate with `WaveManager` and `LevelSection.ENEMIES_CLEARED` and lives in the level. Each of
sub-items 1, 2 and 3 was one full session; this is bigger than any of them.

**This cycle does (1) only, as sub-item 4a**, and `BACKLOG.md` is split into 4a / 4b. The reasoning
that puts fire before reinforcements: today the *entire first phase of the boss is passive*. Four
turrets sit there and do nothing while the player shoots them — the fight has no threat at all
until the armour breaks. Reinforcements would decorate a fight whose core loop is still inert.
Adding fire also makes the turret kill *mean* something: every turret destroyed removes one gun.

The known 4b design hazard is recorded here so the next cycle does not rediscover it:
`_wait_enemies_cleared` is connected to `waves_complete` (`level_director.gd:77`), and
`waves_complete` fires when the **last wave triggers** (`wave_manager.gd:55`). Reinforcements
authored as extra timed waves in `_build_station_assault()` would therefore keep spawning after the
station is already dead, and the section could not end until the player mopped them up. 4b almost
certainly has to spawn reinforcements from a station-owned node into `enemy_container` (the
station's own parent), not from the wave list.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_station/space_station.tscn` | The boss scene: hull, core HurtBox/Health, 4 `StationTurret`s under `Turrets`, `LaserPhase` | Gains one `Gunnery` child node |
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation extends BaseEnemy`; armour rule, `armor_broken`, config application | Provides `armor_broken`, `died`, `live_turret_count()`. **Gains no gun code** |
| `assault/scenes/enemies/space_station/station_turret.gd` | `StationTurret extends Node2D`; own HP/HurtBox, `is_alive()`, `destroyed(turret)` | The phase-1 emitters. `is_alive()` is the fire gate |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` | Phase 2: rotates the hull, fires `LaserRay` volleys off `armor_broken` | The template to copy for a phase node, and the thing core fire must interleave with |
| `assault/scenes/enemies/space_station/space_station_config.gd` / `.tres` | `SpaceStationConfig extends ShipConfig` | Gains the gunnery stats; **shared process-wide instance, see below** |
| `global/components/bullet_pool.gd` | Pre-allocates + recycles bullets; reparents actives to `get_parent().get_parent()` | Mandated by the backlog item ("projectiles route through `bullet_pool`") |
| `global/resources/attack/*.gd` | `AttackPatternResource` (data) + `AimedAttackPattern` / `GatlingAttackPattern` / `ForwardAttackPattern` | `fire(ship, pool)` is exactly the seam a multi-emitter boss needs |
| `global/components/attack_controller.gd` (`AttackController`) | Node that ticks one pattern for one ship | Reference cadence code; see "not reused" below |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` | `EnemyBullet`, HitBox layer 256 / mask **128** | Player-only mask, so station bullets cannot self-damage |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/components/bullet_pool.gd` | Pre-allocation, recycling on `expired`, and `_exit_tree()` freeing in-flight bullets when the owner dies — the last one is what stops dead-boss bullets blocking `ENEMIES_CLEARED` |
| `global/resources/attack/aimed_attack_pattern.gd` | Turret fire, complete: acquires from the pool, sets `HitBox.damage`, `speed`, aims at group `player`, falls back to `Vector2.DOWN`. **Takes the firing `ship` as an argument**, so one instance can drive four turrets |
| `global/resources/attack/attack_pattern_resource.gd` | The `fire(ship, pool)` contract to subclass for the core's ring |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` | The phase-node pattern to copy verbatim: `get_parent() as SpaceStation` with a `push_warning` bail, config copied into own fields in `_ready()`, connect `armor_broken` + `died`, teardown on death, a `live_*()` accessor for tests |
| `assault/scenes/enemies/space_station/station_turret.gd` | `is_alive()` and `destroyed(turret)` — the fire gate and the "one fewer gun" event |
| `tests/integration/test_station_laser_phase.gd` | The container-`Node2D` fixture that stops `ExplosionEffect` leaking particles, and the "override the phase node's fields, never `config`" discipline |

### Deliberately *not* reused: `AttackController`

`AttackController` (`attack_controller.gd`) drives **one** pattern for **one** ship: `_ship` is
`get_parent() as Node2D`, and its timer is private. A boss needs the opposite shape — one cadence
driving N emitters, with dead emitters skipped and a per-volley angular offset shared across the
whole ring. Using it would mean a controller node parented onto each *turret* by a node that does
not own it, no way to make four guns fire as one legible volley, and no way to skip a
dead emitter without freeing someone else's child. (**Corrected in review round 1:** an earlier
draft also claimed four controllers would "independently drift". They would not —
`attack_controller.gd:24-30` is a float accumulator that does `_timer -= pattern.fire_interval`
precisely to preserve overshoot. That claim is withdrawn; the rejection stands on the ownership
and volley-legibility arguments alone.) The gunnery node keeps one `Timer` and calls
`pattern.fire(turret, pool)` directly — the same public seam `AttackController` calls.

## Conventions that constrain this

- **Composition over inheritance.** The gunnery is a child node of `space_station.tscn`, like
  `LaserPhase`. `space_station.gd` gains nothing.
- **Config-driven `.tres`.** All tuning goes on `SpaceStationConfig`, applied in `_ready()`.
- **`SpaceStationConfig` is ONE process-wide object.** `space_station.gd:24` `load()`s it and
  `ResourceLoader` caches, so every station and every `preload()`ing test share it. The gunnery
  must copy the values into its own fields in `_ready()` and never read `config` again, and tests
  must override the **node's** fields. This is written up in `tests/README.md` and it is what got
  the laser-phase test plan rejected in review round 2.
- **Coordinates.** Everything *inside* `space_station.tscn` is final on-screen pixels at
  `scale = 1`, never multiplied by `ArenaCamera.WORLD_SCALE`; only authored *spawn offsets* are
  scaled. Turret local positions are `(±76, ±76)`.
- **No `randf()` in boss attack selection.** Settled during sub-item 3 and pinned by
  `test_volley_angles_are_deterministic`: random attack ordering cannot be balanced or tested. A
  ring's angular step is a constant, not a roll. (`GatlingAttackPattern`'s ±4.5° scatter is a
  different thing — jitter on an already-chosen direction — and is not what this is about.)
- **Signals declared with zero parameters must be connected with zero-arg handlers**, and
  `Health.amount_changed` is the reverse trap (declared 0, emitted 1).

## Hard constraint discovered while reading: where the `BulletPool` node must live

`bullet_pool.gd:40` resolves its bullet container as `get_parent().get_parent()` — hardcoded, no
export. It assumes `pool → ship → enemy_container`.

Consequences for this feature, all load-bearing:

- A pool parented under the gunnery node (`pool → Gunnery → SpaceStation`) would reparent live
  bullets **into the station**, and `StationLaserPhase._physics_process` rotates the station — so
  every bullet in flight would swing around the hull. Same for a pool under a turret
  (`pool → Turret → Turrets`).
- The pool must therefore be a **direct child of `SpaceStation`**, which resolves to
  `enemy_container` — world space, unrotated, and the same container every other enemy's bullets
  already use.
- That container is what `LevelSection.ENEMIES_CLEARED` counts
  (`level_director.gd:116`, `container.get_child_count() > 0`), so in-flight bullets do briefly
  hold the section open. `BulletPool._exit_tree()` frees every active bullet when the pool leaves
  the tree, and the pool leaves the tree with the station, so a dead boss cleans up after itself.

The gunnery node therefore creates the pool and adds it to its *parent*. The alternative — a new
`container_override` export on `BulletPool` — was considered and rejected as a wider blast radius
(a shared component used by five other ships) for no gain here.

## No self-damage risk from bullets (unlike the lasers)

`enemy_bullet.tscn`'s `HitBox` is layer 256, **mask 128** — the player hurtbox and nothing else.
The station's core HurtBox is layer 512 with mask `97 | 1024`, which does not include 256. So the
`hit_mask_override = 128` dance that phase 2's beams need has **no analogue here**, in both
directions: station bullets cannot hit the station, and the station's own beams (overridden to
mask 128) cannot shoot down its own bullets. Worth stating explicitly because the laser-phase
docs make self-damage look like a property of the station rather than of `LaserRay`'s default mask.

## Open questions for research

1. Fire interval and bullet speed for a **first** mini-boss's aimed turret fire — fast enough to
   force movement, slow enough to read. Ratio to the player's 400 px/s top speed (`move_state.gd:21`).
2. Ring/radial patterns: how many bullets, and does a rotating per-volley offset actually improve
   readability or just add noise? Is a deliberate gap needed, or is a full ring fair when it is
   slow enough to outrun?
3. Aimed vs fixed: the standard danmaku distinction, and which one belongs on the turrets vs the core.
4. Does turret fire need to *escalate* as turrets die (survivors fire faster), or does the natural
   decay from 4 guns to 1 already carry the phase?
