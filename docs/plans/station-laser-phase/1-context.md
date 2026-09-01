# Context — Station laser phase (EPIC sub-item 3)

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation extends BaseEnemy`; owns the armour rule (`is_armored()` / `live_turret_count()`) | The phase trigger is exactly the moment `is_armored()` flips false. The class already computes it. |
| `assault/scenes/enemies/space_station/station_turret.gd` | `StationTurret extends Node2D`; emits `destroyed(turret)` **once** | The event hook. Its own header says it exists "for sub-items 3 and 4". Nothing listens to it yet. |
| `assault/scenes/enemies/space_station/space_station.tscn` | `CharacterBody2D` root, layer 0/mask 0, 240×240 core `HurtBox` on **layer 512**, `Turrets` container with 4 turrets at ±76 | The core hurtbox layer is the whole reason the naive "mount a beam on the station" implementation self-destructs — see the spike below. |
| `assault/scenes/enemies/space_station/space_station_config.gd/.tres` | `SpaceStationConfig extends ShipConfig`; `max_health 600`, `turret_health 120`, `collision_damage 40`, `score_value 1000` | Project convention: laser timings belong here, not as magic numbers in the script. |
| `assault/scenes/hazards/laser_ray/laser_ray.tscn/.gd` | `LaserRay`: segmented beam, `warn_duration` / `active_duration` / `loop` / `off_duration`, one-hit kill | The beam. Reuse verbatim; do not build a second laser. |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_station_assault()` (line ~228) and `_spawn_laser_columns()` (line ~150) | `_spawn_laser_columns` is the shipped precedent for how this project instantiates, aims and starts a `LaserRay` at runtime, including its telegraph value. |
| `tests/integration/test_space_station.gd` | 9 tests, armour rule + config | Where the phase-trigger tests belong; it already has `_kill_turret()`. |
| `tests/README.md` | Suite rules | `Health.amount_changed` zero-arg trap, the `LevelDirector` coroutine leak, `unit/` = no scene loading. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `laser_ray.tscn` | The entire beam: telegraph (`warn_duration`), charge-up, live window (`active_duration`), auto-dissolve + `queue_free()`, the 0.1 s re-hit tick that chews shield charges, and `is_lethal_now()` — a clean public observable that is true **only** during the damaging window. |
| `LaserRay.is_lethal_now()` | `_phase == IDLE`. Exactly the "damages only during the active window, not the warning window" assertion the backlog asks for, without touching privates. |
| `LaserRay.dissolve()` | External early-terminate while IDLE. Lets the station kill its beams on death. |
| `StationTurret.destroyed(turret)` signal | Already emitted once, already `_alive`-guarded against double-fire. |
| `SpaceStation.live_turret_count()` / `is_armored()` | Live read of `$Turrets`; cannot desync. The trigger condition is `live_turret_count() == 0`. |
| `SpaceStationConfig` | The config-driven `.tres` slot for every timing number. |
| `level_1_director.gd::_spawn_laser_columns()` | Shipped call sequence: `auto_start = false` → set durations → `add_child` → set `global_position` → `start()`. Its shipped telegraph is `warn = 3.0`, `active = 4.0`. |
| `BaseEnemy` hit flash / `ExplosionEffect` / `HitEffect` | Already wired into the station; the laser phase needs no new feedback components. |

## Spike results (run this session, `spike/test_spike_*.gd`, deleted afterwards)

These are measured, not assumed. Three of them change the design.

1. **Headless GUT really does drive the beam.** A `LaserRay` with `warn_duration = 0.5`
   added to a GUT test tree reports `is_lethal_now() == false` at t=0.4 s with **0** damage
   emitted, and `true` with 6 hits by t=1.6 s, against a real `Area2D` `HurtBox` on layer 128
   stepped by real physics frames. So the "damages only in the active window" test can be a
   genuine physics test, not a poke at a private method. Time to live ≈ 0.2 s (`laser_init`
   frame) + `warn_duration` + 0.56 s (`laser_increase`).
2. **A beam mounted on the station with the default hit mask instantly kills the station.**
   `LaserRay._HIT_MASK` is `128 | 256 | 512`, and the station's core `HurtBox` is **layer 512**.
   With all turrets dead (core unarmoured) a beam at local `(0, 100)` pointing down produced
   `[Health] SpaceStation took 9999 damage: 600 → 0 HP` — the boss suicides the instant its own
   laser phase starts. Setting the beam's `HitZone.collision_mask` to `128` (player hurtbox only)
   leaves the station alive. **This is the single most important constraint on the design.**
3. **Geometry alone is not a safe fix.** The same beam at radius 180 on a diagonal *did* survive,
   because the 240×240 core shape's corner is only ~170 px out. That margin is 10 px and depends
   on the hull size, the beam width and the emitter angle all staying put. The mask is the fix;
   radius is at best a second line of defence.
4. **Rotating the station moves the beams.** With a beam parented to the station,
   `st.rotation = PI/2` moved `danger_rect()` from `(572, 480) 56×768` to `(-348, 272) 768×56`
   after two physics frames. So "the station rotates and the beams sweep" needs no per-beam
   rotation code — parent the emitters and rotate the root.

## Conventions that constrain this

- **Composition over inheritance.** New behaviour should be a child node on the station scene,
  not more methods bolted onto `SpaceStation`.
- **Config-driven `.tres`.** Timings go in `SpaceStationConfig`, applied in `_ready()`, `.tres`
  wins over the scene.
- **Design-space coordinates.** `at(0, -90)` in `_build_station_assault()` is 640×360 design
  units × `ArenaCamera.WORLD_SCALE` (2.0). But per `ENEMY.md`, everything *inside*
  `space_station.tscn` (the 256×256 sprite, the ±76 turret offsets) is authored at final
  on-screen pixels at `scale = 1`. Emitter offsets are inside the scene, so they are **screen
  pixels and must not be scaled**.
- **`Health.amount_changed` is declared with 0 params and emitted with 1** — any handler takes one
  argument or GUT fails the test on the engine error.
- **The station must leave the tree on death** (`ENEMIES_CLEARED` polls `enemy_container`'s child
  count), so anything the phase creates must not outlive or block that.
- Player has **50 max HP** (`player_fighter.tscn:295`) and 0.5 s i-frames; a shield charge absorbs
  a hit of *any* size (`player_base.gd:105-119`). So the laser's 9999 is a one-hit kill unless the
  player is shielded — the same deal the shipped laser columns already offer.

## Open questions for research

1. What telegraph duration do shipped shmups use for a sweeping/rotating boss laser? The level's
   own laser columns use 3.0 s, which may be right for a static column and far too long for a
   beam that sweeps continuously.
2. How fast should a rotating boss beam sweep so it reads as dodgeable rather than random?
3. Is a one-hit-kill boss beam normal for the genre, or do boss beams usually do chip damage
   while static hazards insta-kill?
4. How many simultaneous beams before a rotating-laser phase stops being readable?
