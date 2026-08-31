# Project Knowledge Base

Authoritative map of the project's structure and game mechanics. This is the source of
truth that `CLAUDE.md` and the per-module docs derive from.

> A space action game built in **Godot 4.6 (Forward+)**. The player cycles between three
> distinct gameplay modes — a fast autoscroller shmup (**Assault**), a free-flight hub
> with mission select (**Open Space**), and isometric ground combat (**Infiltration**) —
> connected through a persistent hub and a boot/cutscene shell. Gameplay systems are
> isolated **per game mode**; all shared, reusable logic lives in a dedicated **global**
> module.

---

## Game loop

```
First launch:  Boot → Intro Cutscene → Assault L1 → Level-Exit Cutscene → Infiltration
Every launch:  Boot → Open Space Hub → (select mission) → play → return to Hub
```

`boot/boot.gd` routes the first frame: on first launch (checked via
`MissionState.has_cutscene_been_seen("intro_to_assault")`) it plays the intro cutscene,
otherwise it loads the Open Space hub. Full detail: [`docs/game-structure.md`](../game-structure.md).

---

## Module map

| Module | Path | Role | Doc |
|---|---|---|---|
| Assault Mission | `assault/` | Autoscroller shmup; hosts the race sub-mode | [assault.md](modules/assault.md) |
| Open Space | `open_space/` | Persistent hub world + mission select | [open_space.md](modules/open_space.md) |
| Infiltration | `infiltration/` | Isometric ground combat | [infiltration.md](modules/infiltration.md) |
| Global (shared) | `global/` | Components, entities, ship modules, state machine, pickups, resources, UI, autoloads | [global.md](modules/global.md) |
| Shell | `boot/`, `cutscenes/`, `dialog/` | Boot entry, cutscenes, dialog data | [shell.md](modules/shell.md) |
| Tests | `tests/` (+ `addons/gut/`) | GUT suite over the autoloads and `global/` | [tests/README.md](../../tests/README.md) |

The codebase is organised **by game mode**: each module holds only its mode-specific
scripts, scenes, and assets. Anything reused across modes belongs in `global/`.
`tests/` is not a gameplay module — it mirrors `global/` and is never imported by game code.

---

## Autoloads

Registered in `project.godot` `[autoload]` (load order matters). Full detail in
[global.md](modules/global.md).

| Autoload | Script | Responsibility |
|---|---|---|
| `MissionState` | `global/autoloads/mission_state.gd` | Mission completion, scores, and "cutscene seen" flags — persisted progression |
| `DialogPlayer` | `global/autoload/dialog_player.gd` | Plays `DialogScriptResource` dialogue; `is_active` gates gameplay input |
| `UpgradeState` | `global/autoloads/upgrade_state.gd` | Player upgrade selections |
| `EventBus` | `global/systems/event_bus.gd` | Global typed signals (decoupled cross-system events) |
| `ShipModuleState` | `global/autoloads/ship_module_state.gd` | Which ship modules are equipped per slot |
| `ShipProgressionState` | `global/autoloads/ship_progression_state.gd` | Ship progression / unlocks |
| `SessionState` | `global/autoloads/session_state.gd` | Per-run session data |
| `CameraShake` | `global/systems/camera_shake.gd` | Global camera-shake requests |

---

## Shared systems (`global/systems/`)

- **`EventBus`** — global signal hub; emit/connect for cross-system events without hard refs.
- **`CameraShake`** — `CameraShake.add(amount)` to shake the active camera.
- **`CameraDirector`** — camera framing/targeting helper.
- **`BackgroundController`** — parallax/scroll background driver (used by Assault & the race mode).

Detail and APIs: [global.md](modules/global.md).

---

## Conventions

- **Engine:** Godot 4.6, Forward+ renderer. Viewport 1280×720; window override 1920×1080.
- **Composition over inheritance:** entities are assembled from `global/components/`
  (Health, Hurtbox/Hitbox, Shield, Overheat, DamageReaction, effects). See the
  **integration recipes** in [global.md](modules/global.md) for how to wire them.
- **Config-driven enemies:** assault enemies read stats from a `*_config.tres`
  (`Resource`) applied in `_ready()`; the `.tres` value wins over the scene's Health node
  where they differ.
- **State machines:** `global/statemachine/state_machine.gd` + `state.gd`; entities with
  complex behaviour keep one `State` node per file in a `states/` folder (player, racers,
  light_assault_ship). Simpler enemies use in-script `enum` phases.
- **Coordinates:** waves and spawn offsets are authored in **design units** (640×360
  space) and scaled by `ArenaCamera.WORLD_SCALE` (2.0) at runtime — never pre-multiply.
- **Testing:** **GUT 9.7.1**, vendored in `addons/gut/`, enabled from the
  `[editor_plugins]` section of `project.godot`. Tests live in `tests/` and run headless:
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.
  The existing suite is **characterization**: it pins behaviour as it is today, bugs
  included, so any behaviour change shows up as a failing test rather than as silence.
  Read [`tests/README.md`](../../tests/README.md) before adding a test — it documents the
  save-file sandbox, and the signal-arity trap that will otherwise fail tests for reasons
  unrelated to the code under test.
- **Git:** **never commit — the user handles all git.** Work on `main` unless asked.

---

## Per-entity behaviour docs

Each combat entity carries a behaviour doc **beside its scene**, mirroring a common format:

- **Racers:** `assault/scenes/race/racers/<name>/RACER.md` (6 racers)
- **Assault enemies:** `assault/scenes/enemies/<name>/ENEMY.md` (9 enemies)
- **Assault hazards:** `assault/scenes/hazards/<name>/HAZARD.md` (3 hazards)
- **Race track hazards:** `assault/scenes/race/track/RACE_HAZARDS.md` (walls, asteroids, lasers + the lethal-hazard / AI-avoidance system)

There is **no discrete boss entity** — the boss/finale phase is the `ENEMIES_CLEARED`
section in `assault/scenes/levels/edelia/1/level_1_director.gd`, documented in
[assault.md](modules/assault.md).

For spawning enemies via `WaveBuilder`, see [`docs/enemy-roster.md`](../enemy-roster.md).

---

## Related docs

- [`docs/game-structure.md`](../game-structure.md) — game loop & mode transitions
- [`docs/enemy-roster.md`](../enemy-roster.md) — WaveBuilder spawn reference
- [`docs/scoring_guide.md`](../scoring_guide.md) & [`docs/assault-spawning-scoring-internals.md`](../assault-spawning-scoring-internals.md) — scoring
- [`docs/BULLET_POOL.md`](../BULLET_POOL.md) — bullet pooling
- [`tests/README.md`](../../tests/README.md) — how to run and write tests
- [`addons/gut/LOCAL_PATCHES.md`](../../addons/gut/LOCAL_PATCHES.md) — the two changes GUT
  needs to load under Godot 4.6.3; re-apply on any GUT upgrade

---

## Keeping this current

After any structural change to scenes or scripts, invoke the **`updating-project-docs`**
skill (`.claude/skills/updating-project-docs/`) to keep this hub, the per-entity docs, and
`CLAUDE.md` in sync.
