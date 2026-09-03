# Context — Station reinforcements (EPIC sub-item 4b)

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_station/space_station.tscn` | The mini-boss scene. Children: `Turrets`, `LaserPhase`, `BulletPool`, `Gunnery` | A reinforcement node would be the 4th sibling behaviour node |
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation extends BaseEnemy`. Signals `armor_deflected(int)`, `armor_broken` (0-arg), inherits `died` (0-arg) | Lifecycle hooks: start on spawn, escalate on `armor_broken`, stop on `died` |
| `assault/scenes/enemies/space_station/station_gunnery.gd` | Sibling node driving bullet patterns; copies config in `_ready()`; `Timer` children; `_stop()` on `died` | **The template to copy.** Same shape, same discipline |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` | Other sibling node, phase-2 beams | Second example of the pattern |
| `assault/scenes/enemies/space_station/space_station_config.gd` + `.tres` | `SpaceStationConfig extends ShipConfig`, all tuning | Reinforcement tuning fields go here |
| `assault/scenes/levels/edelia/1/level_1_director.gd:228-243` | `_build_station_assault()` — one zero-delay wave holding only `b.space_station().at(0, -90)` | The "no `.delay()` / no `.move()`" constraint the backlog quotes |
| `assault/scenes/levels/edelia/1/level_1_director.gd:104-140` | `_spawn_bonus_drone()` — section-side ad-hoc spawn into `wave_manager.enemy_container` | **Working precedent for spawning outside the wave registry**, incl. hand-attaching an `EnemyPathMover` |
| `assault/scenes/systems/wave_manager/wave_manager.gd:157-205` | `_spawn_ship()` — camera-relative offset × `WORLD_SCALE`, `add_child`, `enemy_spawned`, mover attach | The behaviour an ad-hoc spawner must reproduce |
| `assault/scenes/systems/level_director/level_director.gd:104-147` | `_wait_enemies_cleared()` polls `enemy_container.get_child_count()`, with `enemies_cleared_timeout` (180 s for this section) then frees everything left | A live reinforcement holds the section open after the boss dies |
| `assault/scenes/enemies/enemy_path_mover.gd` | Movement driver. `FREE_ON_SCREEN_EXIT` only frees **after** the ship has been on screen once; `FREE_ON_DURATION` uses `exit_time` | Exit mode choice decides whether a reinforcement can strand the section |
| `assault/scenes/systems/score_tracker/score_tracker.gd:70-80, 84-86` | Connects `EventBus.enemy_spawned_orphan`, routing to `_on_enemy_spawned(enemy, -1)` | Lets a station-owned spawner register kills for score **without** a `WaveManager` reference |
| `global/systems/event_bus.gd:69` | `signal enemy_spawned_orphan(enemy: Node)` | The registration channel |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EventBus.enemy_spawned_orphan` | Score registration for ad-hoc spawns; already used by `big_asteroid.gd:77` for shards. `wave_index = -1`, so reinforcements never disturb wave-clear tallies |
| `EnemyPathMover` + `StraightMovement` / `ArcMovement` / `SineMovement` | All flight paths; `ExitMode.FREE_ON_DURATION` + `exit_time` gives a hard lifetime |
| `WaveBuilder` scene-path constants (`WaveBuilder.INTERCEPTOR`, `.DRONE`, `.RAM`, `.FIGHTER` …) | Enemy scenes by path, no new consts needed |
| `ArenaCamera.WORLD_SCALE = 2.0`, `SCREEN_W = 1280`, `SCREEN_H = 720` | Design-space → world conversion |
| `station_gunnery.gd` structure | Config-copy-in-`_ready()`, `Timer` children, `armor_broken` / `died` wiring, public `fire_*()` methods so tests drive volleys without waiting real seconds |
| Existing enemies (`interceptor`, `kamikaze_drone`, `ram_ship`, `light_assault_ship`, `bomber`) | The reinforcements themselves — the EPIC forbids new enemy types |

## Conventions that constrain this

- **Composition:** new behaviour is a **child node** of `space_station.tscn`, not methods on `space_station.gd` (`CLAUDE.md`; `StationGunnery` / `StationLaserPhase` both do this).
- **Config-driven `.tres`:** tuning goes on `SpaceStationConfig`, read **once** in `_ready()` and copied into node fields — the `.tres` is a single process-wide instance (`space_station.gd:36` `load()`s it, `ResourceLoader` caches), so runtime reads through it are reads of mutable global state.
- **Design-unit coordinates:** offsets authored in 640×360 space, multiplied by `ArenaCamera.WORLD_SCALE` at spawn. Never pre-multiplied. `EnemyPathMover` already scales movement, so **speeds are authored unscaled too**.
- **Zero-arg signal trap** (`tests/README.md`): `died` and `armor_broken` are genuinely 0-arg; `Health.amount_changed` is not. Handlers must match.
- **Scene wiring:** a `node_paths=PackedStringArray(...)` tag is required for any exported node reference or it is silently null with the gate green (learned in 4a).
- **`BulletPool` must stay a direct child of `SpaceStation`** (`bullet_pool.gd:47` hardcodes `get_parent().get_parent()`). Reinforcements must not be parented anywhere that breaks this.
- Enemy movement rules from `docs/enemy-roster.md`: `gunship` and `drone_interceptor` are **self-managed AI — never attach a mover**; everything else needs `.move()` or it sits still.

## Open questions for research

1. In shmups, do boss fights spawn **timed** reinforcement waves or **phase-gated** ones, and how much add pressure is fair on top of a bullet-hell pattern?
2. Typical add cadence / population cap for a boss with adds, so the screen does not become unreadable next to a 48-bullet pool.
3. Off-screen spawn conventions: how far outside the camera bound, and how to avoid a reinforcement appearing on top of the player.
4. Does spawning from the **bottom** edge (behind the player) read as unfair in a top-down autoscroller, and what mitigations exist (telegraph, slower speed, no shooting until on screen)?
