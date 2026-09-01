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
- **Design-unit coordinates** — waves/spawns authored in 640×360 space, scaled by
  `ArenaCamera.WORLD_SCALE` (2.0) at runtime; never pre-multiply.
- **Tests are GUT, in `tests/`** — run them headless with
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
  (this is step 3 of `/agent/verify.sh`). The suite is almost entirely **characterization**: it
  pins today's behaviour, bugs included. Two exceptions:
  `tests/integration/test_resource_uid_integrity.gd`, an invariant check over `[ext_resource]`
  UIDs, and `tests/integration/test_space_station.gd`, which covers new code and so asserts
  intent. **Read [`tests/README.md`](tests/README.md) before writing a
  test** — it covers the `user://` save-file sandbox and the zero-parameter-signal trap, both of
  which cause failures unrelated to the code under test.
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
