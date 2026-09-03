---
name: updating-project-docs
description: Use after any structural change to the game's scenes or scripts (adding, renaming, moving, or deleting an entity, component, module, or mechanic) to keep the docs/architecture hub, the per-entity docs, and CLAUDE.md in sync.
---

# Updating Project Docs

The project's knowledge base lives in `docs/architecture/` (hub: `PROJECT.md` + one doc per
module under `modules/`), with per-entity behaviour docs beside each entity, and a lean
root `CLAUDE.md`. These only stay useful if they are updated whenever the structure
changes. This skill is the checklist for doing that.

## When to use

Invoke this skill before finishing a task whenever you have made a **structural change**:

- Added, renamed, moved, or deleted an **entity** (a racer, an assault enemy, or a hazard).
- Added, renamed, moved, or deleted a **shared component** (`global/components/`), a
  **ship module** (`global/ship_modules/`), or an **autoload**.
- Added or removed a **module** / top-level directory, or changed a module's boundaries.
- Added, reworked, or removed a **game mechanic** (wave system, scoring, a player state,
  the race sub-mode, mission-select flow, etc.).
- Changed a **convention** documented in `PROJECT.md` / `CLAUDE.md` (coordinates, config
  pattern, engine version, the git rule, etc.).

Pure tuning that does not change structure (e.g. nudging an existing export's default)
only needs a doc update if the doc cites that specific value.

## Workflow checklist

Create a TodoWrite item per applicable step, then work through them:

1. **Identify the change.** Classify it (entity / component / module / mechanic /
   convention) and list which module(s) under `docs/architecture/modules/` it touches.
2. **Update the module doc(s).** In `docs/architecture/modules/<module>.md`, update the
   **directory map** and the affected **mechanic** subsection with real file paths and
   measured values.
3. **Update `PROJECT.md` if needed.** Only when module boundaries, the module map table,
   the autoload set, the shared-systems list, or a convention changed.
4. **Update the per-entity doc.** If the change was an entity:
   - **Added** → create the doc beside the entity (`ENEMY.md` for assault enemies,
     `HAZARD.md` for assault hazards, `RACER.md` for racers) using the template below.
   - **Changed** → update the Stats / Behaviour / Config-exports / State-graph sections
     from the real `.gd` / `.tscn` / `*_config.tres`.
   - **Renamed / moved** → move the doc with the entity and fix its title + Files tree.
   - **Deleted** → delete the doc and remove links to it.
5. **Sync `CLAUDE.md`.** Only if the module map or a key convention changed (keep it lean —
   depth stays in the hub).
6. **Do NOT commit.** The user handles all git. Leave the doc changes unstaged.

## Format reference

The canonical per-entity format to mirror is
`assault/scenes/race/racers/fang/RACER.md`. Use real file paths and real values read from
source — never placeholders.

## Per-entity doc template

```markdown
# <Name> — <one-line role>

**Role:** <what it does in a fight>
**Fantasy / threat:** <how it feels to face it>

---

## Stats

| Property | Value |
|---|---|
| HP | <n> |
| Damage | <n / per source> |
| Speed | <n> |
| Sprite | `<file>.png` |
| Scene | `<file>.tscn` |
| Config | `<file>_config.tres` |

---

## Behaviour & Movement

- **Movement:** <EnemyPathMover / state machine / movement resource — be specific>
- **Attack:** <attack_controller / aim_mode / projectile scene — be specific>
- **Death / scoring:** <what happens on death, score contribution if any>

---

## State Graph        (include ONLY if the entity has a states/ folder)

<ascii state graph like RACER.md>

### <STATE> (`<state_file>.gd`)
<behaviour bullets + tuning exports table>

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `<name>` | `<value>` | <meaning> |

(Read the real defaults from `<x>_config.gd` and `<x>_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.<method>()` — see `docs/enemy-roster.md`.
- Typical placement / role in waves.

---

## Files

\`\`\`
<x>/
├── <DOC>.md            ← this file
├── <x>.tscn
├── <x>.gd
└── <x>_config.gd / .tres
\`\`\`
```

For shared components / ship modules, there is no per-entity doc — update the relevant
**integration recipe** or list in `docs/architecture/modules/global.md` instead.
