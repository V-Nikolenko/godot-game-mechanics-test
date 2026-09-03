# Context — EPIC sub-item 5: station destruction hands off to the planet approach

## What the player sees today

The `station_assault` section is a real fight (turrets → armour break → laser phase + core
bullet-hell + reinforcements). Then the core's HP reaches 0 and the 256×256 mini-boss
**vanishes in a single frame** behind one 22-particle `ExplosionEffect` burst — the exact same
death as a 40 px interceptor. 0.2 s later the background starts tweening to `planet_approach`.
Four sessions of build-up end with a poof.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd:65-73` | `_on_health_changed`: at `current == 0` sets `was_killed`, emits `died`, calls `_explosion_effect.explode()` then `queue_free()` **in the same frame** | This is the thing that makes death instantaneous. Any death sequence must override it. |
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation extends BaseEnemy`; armour rule, `armor_broken`, config application | Owner of the override. Already overrides `_on_received_damage`, so overriding `_on_health_changed` is the same shipped pattern. |
| `assault/scenes/enemies/space_station/space_station.tscn` | Hull + 4 turrets + `LaserPhase` / `BulletPool` / `Gunnery` / `Reinforcements` sibling nodes | A death sequence belongs here as a **fifth sibling node**, matching the composition rule the last three sub-items followed. |
| `assault/scenes/enemies/space_station/station_laser_phase.gd:109,172` | `_station.died.connect(_stop)`; frees live beams | Already correct: shuts down on `died`, so beams stop the moment death starts, not when the wreck is freed. |
| `assault/scenes/enemies/space_station/station_gunnery.gd:134,230` | `_station.died.connect(_stop)` | Same. Guns go quiet at the true moment of death. |
| `assault/scenes/enemies/space_station/station_reinforcements.gd` | `_stop()` on `armor_broken` and on `died` | Already correct; nothing is left alive to hold the section open. |
| `assault/scenes/systems/level_director/level_director.gd:104-147` | `_wait_enemies_cleared()` polls `wave_manager.enemy_container.get_child_count()` every 1.0 s, then a 0.2 s settle, then `_advance()` | **The handoff mechanism.** Because it polls the container, a station that stays parented for its death sequence *automatically* holds the section open — no director change needed. |
| `assault/scenes/levels/edelia/1/level_1_director.gd:199-241` | `_build_sections()` → `deep_space, asteroid_belt, station_assault, planet_approach, cloud_descent` | The sequence the end-to-end test must walk. Already refactored to be callable on a bare instance without booting the level. |
| `global/components/explosion_effect.gd` | One-shot `CPUParticles2D` spawned into `actor.get_parent()` so it outlives the actor | Reusable as-is for the chained blasts — but note it always spawns at `actor.global_position`, dead centre, and only into the *parent* container. |
| `global/systems/camera_shake.gd` | `CameraShake.add(1.0)` documented as "boss death / big impact" | The shake channel already exists and is already used by `player_fighter.gd:177`. |
| `global/components/health_component.gd:39-41` | `set_health()` emits `amount_changed` **unconditionally**, so a 0 → 0 hit re-emits | Without a latch, a bullet landing during the death sequence re-runs the whole death path. |
| `assault/scenes/systems/score_tracker/score_tracker.gd:147-165,198-211` | Kill path on `died`; escape path on `tree_exited` guarded by `enemy.was_killed` | So `was_killed = true` and `died.emit()` must still happen at the *moment* HP hits 0, not when the wreck is finally freed. Delaying them would score the boss as an escape and apply the 0.75× combo penalty. |
| `tests/integration/test_station_assault_section.gd` | The `ENEMIES_CLEARED` gate, section order, station wave | The end-to-end test's nearest neighbour; its `before_each` harness (bare `Node2D` container + `WaveManager` + `LevelDirector`) is directly reusable. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/components/explosion_effect.gd` | Configurable one-shot burst that survives its owner. `amount`, `lifetime`, `color`, velocity and scale ranges are all `@export`. |
| `global/systems/camera_shake.gd` | `CameraShake.add(trauma)` — additive, decaying, already read by `arena_camera.gd:90`. |
| `SpaceStation.died` | Already the shutdown signal for the laser phase, the gunnery and the reinforcements. Nothing new needs wiring. |
| `LevelDirector._wait_enemies_cleared()` | Already the handoff. A lingering wreck holds the section; freeing it advances. |
| `Level1Director._build_sections()` | Returns fresh `LevelSection.new()` objects per call, so a test may mutate their `duration` without touching shipped state. |
| `SpaceStationConfig` | The established home for the boss's *stats*. Scene/level geometry stays on the node (`StationLaserPhase.emitter_radius`, the gunnery `spawn_radius`, `StationReinforcements.reinforcement_lifetime`). |
| `tests/integration/test_station_assault_section.gd` harness | Director + wave manager + container built by hand; `_spawn_ship()` returns early with no camera, so nothing spawns and the gate is driven by hand. |

## Conventions that constrain this

- **Composition over inheritance** — new behaviour goes in a sibling node on `space_station.tscn`,
  not in more methods on `space_station.gd`. Three precedents in this same scene.
- **Config-driven `.tres` stats** — tunable numbers go on `SpaceStationConfig` and are **copied**
  into the node in `_ready()`, never read live: the `.tres` is a single process-wide cached
  instance shared by every test (`space_station.gd:36` uses `load()`).
- **`BulletPool` must stay a direct child of `SpaceStation`** (`bullet_pool.gd:47` hardcodes
  `get_parent().get_parent()`).
- **Nothing may be parented under the station that should not rotate with it** — the laser phase
  writes `_station.rotation`.
- Waves/positions authored in 640×360 design units × `ArenaCamera.WORLD_SCALE` (2.0). A death
  sequence placing blasts across the hull is working in *local* sprite space, so the hull's own
  256 px extent is the right frame of reference, not design units.
- Zero-arg signals stay zero-arg (`Health.amount_changed` trap, `tests/README.md`).
- GUT fails a test on **any** unexpected engine error, including inside a signal callback.
- A test that returns while `_wait_enemies_cleared()` is suspended leaks a `SceneTreeTimer` and
  **the gate stays green** — so an end-to-end director test must drive the director all the way
  to `level_complete` before returning.

## Open questions for research

1. How long does a shmup mini-boss death sequence run, and how many secondary explosions? A
   number pulled from nowhere here is the difference between "satisfying" and "the game hung".
2. During the death sequence, should enemy bullets already in flight be cleared, or left to kill
   the player after the boss is dead? (Genre convention exists for this; it is not a coin flip.)
3. Is there a hitstop/freeze convention on boss death, and how long before it reads as a bug?
4. Should the player keep control during it, and does the boss stay collidable?
