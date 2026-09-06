# CLAUDE.md

A space action game in **Godot 4.6 (Forward+)**. The player cycles between three gameplay
modes — **Assault** (autoscroller shmup), **Open Space** (free-flight hub + mission
select), and **Infiltration** (isometric ground combat) — connected by a boot/cutscene
shell. Mode-specific code is isolated per module; shared logic lives in `global/`.

**Full knowledge base:** [`docs/architecture/PROJECT.md`](docs/architecture/PROJECT.md)

## Modules

| Module | Path | Role | Doc |
|---|---|---|---|
| Assault Mission | `assault/` | Autoscroller shmup; hosts the race sub-mode | [assault.md](docs/architecture/modules/assault.md) |
| Open Space | `open_space/` | Persistent hub world + mission select | [open_space.md](docs/architecture/modules/open_space.md) |
| Infiltration | `infiltration/` | Isometric ground combat | [infiltration.md](docs/architecture/modules/infiltration.md) |
| Global (shared) | `global/` | Components, entities, ship modules, state machine, pickups, resources, UI, autoloads | [global.md](docs/architecture/modules/global.md) |
| Shell | `boot/`, `cutscenes/`, `dialog/` | Boot entry, cutscenes, dialog data | [shell.md](docs/architecture/modules/shell.md) |
| Tests | `tests/` (+ `addons/gut/`) | GUT suite over the autoloads and `global/` | [tests/README.md](tests/README.md) |

## Key conventions

- **Engine:** Godot 4.6, Forward+. Viewport 1280×720.
- **Composition over inheritance** — entities are built from `global/components/`
  (Health, Hurtbox/Hitbox, Shield, Overheat, DamageReaction, effects).
- **Config-driven enemies** — assault enemies load stats from a `*_config.tres` applied in
  `_ready()` (the `.tres` value wins over the scene's Health node where they differ).
- **State machines** — `global/statemachine/`; one `State` node per file in a `states/`
  folder for complex entities; simpler enemies use in-script `enum` phases.
- **Signal arity & logging** — a signal is declared with exactly what it emits
  (`amount_changed(current_health: int)`, not a bare `signal amount_changed`), and anything
  that can print per-frame or per-hit sits behind `if OS.is_stdout_verbose()`. Both are
  spelled out in `docs/architecture/PROJECT.md` → Conventions.
- **Design-unit coordinates** — waves/spawns authored in 640×360 space, scaled by
  `ArenaCamera.WORLD_SCALE` (2.0) at runtime; never pre-multiply.
- **Tests are GUT, in `tests/`** — run them headless with
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
  (this is step 3 of `/agent/verify.sh`). The suite is almost entirely **characterization**: it
  pins today's behaviour, bugs included. The exceptions are
  `tests/integration/test_resource_uid_integrity.gd`, an invariant check over `[ext_resource]`
  UIDs and the UID-only references in `project.godot` / `export_presets.cfg` (read from disk, so
  it is immune to the stale aliases a warm `.godot/uid_cache.bin` keeps alive) that also asserts
  every UID we write is one the editor could have minted and detects collisions by decoding
  rather than by string match — `uid://` is base-34 text for a 64-bit int, so a hand-typed UID is
  usually an alias for one owned elsewhere, which no text comparison can see,
  `tests/integration/test_suite_integrity.gd`, which asserts every `tests/**/test_*.gd`
  compiles and extends `GutTest` (GUT otherwise drops an unloadable test script with only a
  warning and still exits 0, so the gate stays green while a test file silently vanishes),
  `tests/integration/test_gut_local_patches.gd`, which asserts the two hand-applied patches
  `addons/gut/LOCAL_PATCHES.md` documents are still in place (re-vendoring GUT drops them, and
  the resulting breakage is silent — parse errors on stderr, suite still exit 0, doubler gone),
  `tests/integration/test_project_load_integrity.gd`, which loads every `.tscn`/`.tres`/`.gd`
  outside `addons/` and asserts each one loads, instantiates and compiles with no engine error or
  warning logged (the gate's `--import` step never loads a scene and its `--quit` step boots only
  `res://boot/…`, so most of the project was previously unloaded by every gate step),
  and the space-station family — `tests/integration/test_space_station.gd`,
  `test_station_assault_section.gd`, `test_station_laser_phase.gd`, `test_laser_ray_hit_mask.gd`,
  `test_station_gunnery.gd`, `test_station_reinforcements.gd` and `test_radial_attack_pattern.gd` —
  which cover new code and so
  assert intent. `tests/integration/test_module_unlock_sources.gd` is a second invariant check
  (every module in `ShipModuleState.SLOT_MODULES` has an unlocker pickup in the sector hub, so
  the unlock gate cannot strand content), and `tests/integration/test_module_list_lock.gd`
  asserts intent for the ship menu's locked rows.
  `tests/integration/test_enemy_contact_damage.gd` is a third invariant check, over the balance
  data rather than the files: every assault enemy's contact `HitBox` must deal the damage its
  `*_config.tres` declares. `BaseEnemy._add_contact_hitbox()` hardcodes `damage = 20` and runs
  before the subclass reads its own `.tres`, so an enemy that forgets to re-apply
  `collision_damage` leaves the field dead with no visible symptom — which is exactly how the
  gunship rammed for 20 while its config said 30.
  `tests/integration/test_contact_hitbox_geometry.gd` is a fourth invariant check, over the same
  hitboxes' *geometry*: a contact `HitBox` must carry the body `CollisionShape2D`'s transform, not
  just its `Shape2D`. A `Shape2D` holds the radius but not the node scale that multiplies it, so
  copying `col.shape` alone built the gunship's ram box at 18 px against a 41.5 px hull. All four
  build sites now go through `HitBox.matching_shape()`.
  `tests/integration/test_enemy_hurtbox_geometry.gd` is a fifth, over the *other* side of that
  collision pair: every assault entity's `HurtBox` must **cover** the body `CollisionShape2D`,
  within 1 px per edge. Armour is a damage rule on a full-size hurtbox — deflect, flash, report 0 —
  never an absent hurtbox, because a shrunken one leaves visible hull that swallows shots and
  reports nothing. It carries a permanent boundary test that applies the rejected "narrow the
  station core to 88 x 240" proposal to a live instance and asserts it fails, so that decision is a
  gate rather than prose someone re-litigates.
  `tests/integration/test_level_director_polling.gd` is a sixth, over the ENEMIES_CLEARED poll: it
  asserts the poll ends on `child_exiting_tree`, honours its fallback window, and leaves nothing
  alive behind an early return. That last one is the reason it exists — the poll used to abandon a
  `SceneTreeTimer` on every early return, and a leak is reported only at *process exit*, after GUT
  has set the exit code and in words the gate's `FATAL` regex does not match, so **the gate prints
  `GATE PASS` on a leaking suite**. `scripts/check-test-leaks.sh` runs gate step 3 and additionally
  greps for the leak lines; run it after touching anything that awaits. It is a separate script
  because `/agent` is mounted read-only, so the gate itself cannot be changed from in here.
  A few characterization files also carry individually-marked intent tests
  (`test_health_component.gd`, `test_state_machine.gd`, `test_ship_module_state.gd`); each says
  so in a comment.
  **Read [`tests/README.md`](tests/README.md) before writing a
  test** — it covers the `user://` save-file sandbox, the signal-arity trap, and the
  `LevelDirector` coroutine-leak trap, all of which cause failures (or silent leaks) unrelated to
  the code under test.
- **Resource UIDs — never run the Godot MCP `update_project_uids` tool.** As the MCP calls it it
  is a silent no-op (it searches `res:///work/repo/` and reports success); pointed at `res://` by
  hand it resaves every scene and strips all UIDs and all comments. Use
  `tests/integration/test_resource_uid_integrity.gd`, which reports instead of rewriting; the
  reasoning is in [tests/README.md](tests/README.md).
- **Never hand-type a `uid://` and never copy one from a sibling file.** A copy is a duplicate
  declaration; a typed one is usually an *alias* decoding to a UID another resource owns, and both
  fail silently. Leave the reference UID-less (legal — Godot falls back to the path) or mint one
  with the headless `ResourceUID.create_id()` snippet in [tests/README.md](tests/README.md).
- **NEVER commit — the user handles all git.** Work directly on `main` unless asked
  otherwise; no worktrees/branches unless requested.
  - *Exception — autonomous NAS loop only* (`SRCW_AUTOMATION=1` in the environment): you are
    already checked out on `agent/auto-dev`, and you **may** commit and push to that branch.
    Run `bash /agent/verify.sh` and get a green gate **before** pushing — never push work you
    have not verified. The harness also commits and pushes anything you leave uncommitted, but
    only after the same gate passes.
  - **`main` stays off-limits.** Never commit to it, never push to it, never merge into it,
    never force-push or rewrite history on any branch. The user merges `agent/auto-dev` to
    `main` by hand.

## Where things live

- Shared components / autoloads / ship modules → `global/` (map: [global.md](docs/architecture/modules/global.md)).
- **How to wire a component (Health/Hurtbox/Shield/state machine/ship module) into an
  entity** → the integration recipes in [global.md](docs/architecture/modules/global.md).
- Per-entity behaviour → `RACER.md` / `ENEMY.md` / `HAZARD.md` **beside each entity**
  (`assault/scenes/race/racers/*/`, `assault/scenes/enemies/*/`, `assault/scenes/hazards/*/`).
- Spawning enemies via `WaveBuilder` → [`docs/enemy-roster.md`](docs/enemy-roster.md).
- Game loop / mode transitions → [`docs/game-structure.md`](docs/game-structure.md).
- **What a shared component actually does, edge cases included** → its test in `tests/unit/`
  (one file per component and per autoload). Faster and more precise than re-reading the source.

## MANDATORY — generating game art

Before generating **any** sprite, tile, or other asset with PixelLab, invoke the
**`pixel-art-generation`** skill. `assault/` and `open_space/` are **strict top-down
orthographic and NEVER isometric** — the skill enforces this with explicit PixelLab
parameters (`view: "high top-down"`, `isometric: false`), not just prompt wording. It also
covers tool choice per asset type, safe binary saving via `scripts/pixellab.sh` (the Write
tool corrupts PNGs), and the mandatory visual check on every generated image.

`infiltration/` is the one genuinely isometric mode and is out of scope for that skill.
A wrong-angle sprite cannot be fixed in code; it has to be regenerated from a capped
monthly allowance. Do not skip the check.

## MANDATORY — plan before building

Before implementing any **non-trivial** feature or mechanic, invoke the **`feature-workflow`**
skill. It gathers context, researches how shipped games solve the same problem, writes a plan to
`docs/plans/`, has an **independent subagent review it**, and only then implements. It has a
short Track B path for bug fixes, renames and tuning — use the skill to pick the track rather
than skipping it.

Implementation starts only on `VERDICT: APPROVED`. A rejected plan is a legitimate outcome: it
means wrong work was avoided cheaply.

## MANDATORY — keep the docs current

After **any structural change** to scenes or scripts — adding, renaming, moving, or
deleting an **entity, component, module, or mechanic** — you **MUST** invoke the
**`updating-project-docs`** skill before finishing the task. It walks you through updating
the affected module doc, `docs/architecture/PROJECT.md`, the relevant per-entity doc, and
this file. Do not skip it; the knowledge base only stays useful if it is updated alongside
the code.
