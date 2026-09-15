# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/autoloads/upgrade_state.gd` | Persistent unlock store for weapon modes. `ALL_IDS` is a **hand-written** array of ids, each expected to have a matching `.tres`. `_load()` drops unknown ids with `push_warning`. | Closest sibling in shape (persistent id-set store), but its catalogue is hardcoded — explicitly the anti-pattern this task's "derived, not typed" requirement forbids. Still the reference for save/load/validate structure. |
| `global/autoloads/ship_module_state.gd` | Persistent unlock + equip store per slot. `_load()` validates every id against `SLOT_MODULES` and drops/grandfathers unknowns. | Reference for the validate-on-load behaviour the task explicitly says to copy. |
| `global/autoloads/mission_state.gd` | Persistent per-mission progress. `ConfigFile` at `user://mission_state.cfg`, `ready()` calls `_load()`. | Reference for `_save()`/`_load()` shape and `SAVE_PATH`/`SECTION` constants. |
| `open_space/scenes/mission_data/mission_config_resource.gd` | Per-mission `Resource` subtype (`class_name`, `@export` fields), one `.tres` per mission on disk, loaded by path. | The named pattern to follow for `LogEntryResource`. |
| `tests/integration/test_weapon_mode_catalogue.gd` | Invariant: sweeps `assault/scenes/player/weapons/modes/*.tres` with `DirAccess` and cross-checks against `UpgradeState.ALL_IDS` in both directions. | Precedent for a `DirAccess.get_files()` sweep over a resource-catalogue directory — the exact mechanism `LogState` needs to derive its total from disk instead of a hardcoded list. |
| `tests/helpers/save_sandbox.gd` | Captures/restores every persistent autoload's `user://*.cfg` before/after a test run so tests never leak into the real save or into each other. `PATHS` is a **hardcoded list** of the sandboxed files. | `LogState`'s new save path must be added to `PATHS`, or its tests (and any other test that happens to trigger a `LogState.collect_next()`) will leak into the player's real save file. |
| `tests/unit/test_upgrade_state.gd` | Shows the project's test idiom for a Node autoload: construct a tree-less instance (`_ready()` never fires), call `_load()`/other methods directly, `add_child_autofree()` only when `_ready()` behaviour itself is under test. | This is the shape `test_log_state.gd` follows. |
| `project.godot` `[autoload]` section | Registers eight autoloads today (`MissionState`, `DialogPlayer`, `UpgradeState`, `EventBus`, `ShipModuleState`, `ShipProgressionState`, `SessionState`, `CameraShake`). | `LogState` needs a ninth entry. |
| `tests/integration/test_project_load_integrity.gd` | Loads every `.tscn`/`.tres`/`.gd` under `res://` except `addons/`/`.godot/`/`.git/`/`.import/` and asserts no engine error/warning. This **includes `tests/`**. | Any fixture `.tres` this task adds under `tests/` must be a genuinely valid `Resource` with a compiling script, or this gate fails. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `tests/helpers/save_sandbox.gd` | `SaveSandbox.capture()`/`restore()`/`clear_all()` — must extend `PATHS` with the new save file. |
| `global/resources/ship_config.gd` (pattern only) | Shows the project's `Resource` subclass idiom (`class_name`, typed `@export`), not reused directly. |

## Conventions that constrain this

- **Config-driven `.tres`, one file per entry** — matches `mission_config_resource.gd` /
  weapon-mode `.tres` pattern already in the codebase.
- **Persist via `ConfigFile` to `user://*.cfg`**, load in `_ready()`, exposed as a public API on a
  `Node`-based autoload registered in `project.godot`.
- **Validate-on-load**: an unknown id in the save file is `push_warning`ed and dropped, never
  trusted (`ShipModuleState._load()`, `UpgradeState._load()`).
- **Test sandbox**: any test that exercises a real save path must use `SaveSandbox`
  (`tests/README.md` line ~426), and the new `user://log_state.cfg` path must be added to
  `SaveSandbox.PATHS` or every other test in the suite is at risk of reading a leaked file.
- **Derive, never hardcode, a catalogue-wide total.** `UpgradeState.ALL_IDS` is the explicit
  counter-example named in the task body — a hand list is exactly what "adding a log requires no
  bookkeeping" rules out. The catalogue must come from a `DirAccess` sweep of `.tres` files on
  disk, read at runtime, the same primitive `test_weapon_mode_catalogue.gd` already uses to
  cross-check (there it's a test assertion; here it has to be production code).

## Open design question (from the task body)

The task flags an explicit design fork and asks the plan to pick one:

- **Anonymous pickup (chosen)** — a lore-log collectible carries no id. Collecting one grants the
  next still-locked entry in catalogue order (`LogEntryResource.sequence`). The story always reads
  in order regardless of where in the game world the player found the collectible.
- **Named pickup (rejected)** — each collectible names its target entry; the menu can show gaps.

Reasoning for picking anonymous, expanded in the plan: it is the reading that matches "place the
collectible on the map and everything else happens automatically" — a level designer drops a
generic pickup with zero configuration, and reordering the story later means reordering
`sequence` values on the `.tres` catalogue, not moving collectibles between levels. The named
variant makes placement order narratively load-bearing, which is a bigger commitment for later
tasks in this epic (specifically the assault/infiltration placement task) to carry.
