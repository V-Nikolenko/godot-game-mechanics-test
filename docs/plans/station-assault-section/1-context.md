# Context — `station_assault` LevelSection (EPIC sub-item 2)

Sub-item 1 built the entity (`docs/plans/station-mini-boss-destructible/`). This sub-item puts it
in Level 1 and makes the level refuse to continue until it is dead. Nothing about the entity
itself changes.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Builds the four Level 1 `LevelSection`s in `_ready()` (`:38-45`) and owns the section-relative event schedules (`:51-77`) | The new section is added here, between `_build_section_asteroid()` and `_build_section_2()` |
| `assault/scenes/levels/edelia/1/phases/*.tres` | Four `BackgroundPhase` resources, one per section | A fifth, `phase_station_assault.tres`, is needed |
| `assault/scenes/systems/level_director/level_director.gd` | Sequences sections; `_advance()` (`:44`), `_wait_enemies_cleared()` (`:104`) | Holds the **10 s hard cap** that breaks `ENEMIES_CLEARED` for a boss (see below) |
| `global/resources/levels/level_section.gd` | `LevelSection` resource + `EndCondition` enum | Where a per-section timeout export belongs |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Triggers waves, spawns into `enemy_container` (`_spawn_ship`, `:150`) | The station must be a **child of `enemy_container`**, so it must be spawned through here |
| `assault/scenes/systems/wave_builder.gd` | Fluent wave DSL; scene-path constants at `:229-242`, ship constructors at `:78-91` | Needs a `space_station()` constructor + path constant |
| `assault/scenes/enemies/space_station/` | The mini-boss entity from sub-item 1 | The thing being spawned |
| `assault/scenes/systems/arena_camera.gd` | `WORLD_SCALE = 2.0`; camera `global_position` is **pinned** at the level origin, all panning goes through `Camera2D.offset` (`:5-13`) | A stationary enemy at a fixed world position stays put on screen — no scroll compensation needed |
| `tests/integration/test_space_station.gd` | Sub-item 1's nine tests | Records the coverage gap this sub-item can start to close |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `LevelSection.EndCondition.ENEMIES_CLEARED` | "Do not advance until `enemy_container` is empty" — already used by `cloud_descent` (`level_1_director.gd:763`) |
| `LevelDirector._wait_enemies_cleared()` | The wait loop, the `child_exiting_tree`/timeout poll, and the 0.2 s settle before `_advance()` |
| `WaveBuilder.wave()` / `SpawnConfig.at()` | Section-relative wave with a camera-relative, design-space offset |
| `WaveManager._spawn_ship()` | Instances the scene, applies `offset * ArenaCamera.WORLD_SCALE`, adds to `enemy_container`, emits `enemy_spawned` for `ScoreTracker` |
| `SpaceStation` + `StationTurret` | Armour rule, turret HP, death → `queue_free()` (so `child_exiting_tree` fires) |
| `BackgroundPhase` (`phase_deep_space.tres`) | A ready-made "we are in open space" alpha set to copy for the station phase |
| `tests/helpers/`, `tests/integration/test_space_station.gd` | Test idioms: instance the real scene, drive damage through `HurtBox.received_damage` |

## Conventions that constrain this

- **Design-unit coordinates.** Spawn offsets are authored in 640×360 space and multiplied by
  `ArenaCamera.WORLD_SCALE` (2.0) inside `wave_manager.gd:172`. The station's *spawn offset* is
  therefore design units — unlike everything **inside** `space_station.tscn`, which is authored at
  final on-screen pixels with `scale = 1` (`ENEMY.md`, "Stats").
- **Composition, and no new inheritance.** This sub-item adds no new node types.
- **Config-driven stats** already live in `space_station_config.tres`; nothing here duplicates them.
- **Characterization suite.** New behaviour gets intent-asserting tests (like
  `test_space_station.gd`); existing behaviour must not change silently — so any edit to
  `LevelDirector` has to leave `cloud_descent` behaving exactly as it does today.
- **Never commit to `main`**; work stays on `agent/auto-dev`.

## The blocking discovery: `ENEMIES_CLEARED` currently gives up after 10 seconds

`level_director.gd:106-107`:

```gdscript
var deadline_ms: int = start_ms + 10_000
while container.get_child_count() > 0:
    if Time.get_ticks_msec() >= deadline_ms:
        push_warning("[LevelDirector] enemy cleanup timed out with %d remaining" % ...)
        break
```

That cap is sized for *"wait for the last few stragglers to fly off screen"*, which is what
`cloud_descent` uses it for. For a boss it is fatal, and worse than it first looks:

- The clock starts on `WaveManager.waves_complete`, which fires when the **last wave triggers**,
  not when the fight ends (`wave_manager.gd:52-56`). A section whose only wave is the station at
  t=0 therefore starts its 10 s countdown on frame one.
- After 10 s the director advances to `planet_approach` **with the station still alive and still
  parented to `enemy_container`**. It has no `EnemyPathMover`, so nothing will ever free it: the
  boss hangs on screen for the rest of the level.

So "the encounter blocks level progress" cannot be satisfied by configuration alone — the timeout
has to become a per-section value. This is the one non-obvious piece of the sub-item.

## Second discovery: `waves_complete` can fire before a delayed spawn exists

`wave_manager.gd:_spawn_with_delay` awaits a `SceneTreeTimer` when `delay > 0`, but `_trigger_wave`
does not await it (`:126-131`), and `_process` emits `waves_complete` immediately after the last
wave triggers (`:52-56`). With a delayed spawn, `_wait_enemies_cleared` can therefore observe an
**empty** container and advance instantly. The station's spawn entry must use `delay == 0`, and the
plan must say why.

## Open questions for research

1. How do shipped autoscrolling shmups gate level progress on a boss — is a hard timeout ever the
   right default, and what do they do when the player cannot kill it?
2. Where on screen does a stationary mini-boss sit so the player still has room to dodge?
3. Is there a standard "boss arrives" beat (siren/warning/approach) worth reserving a hook for,
   given sub-items 3–5 will add the laser phase, reinforcements and the death handoff?
