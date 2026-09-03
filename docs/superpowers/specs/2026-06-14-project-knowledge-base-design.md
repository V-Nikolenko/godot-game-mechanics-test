# Project Knowledge Base — Design

**Date:** 2026-06-14
**Status:** Approved (design); pending implementation plan

---

## Problem

There is no single, accurate, maintained description of the project's structure and
mechanics. The existing docs are partial and partly stale:

- `ProjectStructure.md` describes an idealised layout and names a `sector_operations`
  module that does not exist (the real hub module is `open_space`).
- `docs/game-structure.md` (accurate game-loop overview) and `docs/enemy-roster.md`
  (accurate WaveBuilder spawn reference) exist but are not tied into any structural map.
- The race mode already has per-racer `RACER.md` files, but assault enemies and hazards
  have none.

We want a **knowledge base** that is the foundation for a root `CLAUDE.md` and for
future "add a new X" skills, plus a rule/skill that keeps it current after structural
changes.

---

## Goals

1. A **source-of-truth hub** under `docs/architecture/` mapping every module and
   describing every game mechanic, with file paths.
2. **Per-entity docs** for assault enemies and hazards, mirroring the existing
   `RACER.md` format.
3. A concise **root `CLAUDE.md`** derived from the hub, including a mandatory
   "update the docs" rule.
4. A **`updating-project-docs` skill** that walks an agent through updating the hub +
   per-entity docs after structural changes.
5. **Reconcile** stale docs: rewrite `ProjectStructure.md` as a pointer; cross-link the
   accurate existing docs.

Non-goal: documenting every private method. The hub describes mechanics, wiring, and
"how to add/extend", not line-by-line internals.

---

## Module inventory (measured)

| Module | Dir | Scripts | Role |
|---|---|---|---|
| Assault Mission | `assault/` | ~112 gd / 47 tscn | Autoscroller shmup; also hosts the **race** sub-mode |
| Open Space | `open_space/` | ~10 gd / 7 tscn | Persistent hub world + mission select |
| Infiltration | `infiltration/` | ~15 gd / 3 tscn | Isometric ground combat |
| Global (shared) | `global/` | ~99 gd / 21 tscn | Components, entities, ship modules, state machine, pickups, resources, UI, autoloads, systems |
| Shell | `boot/`, `cutscenes/`, `dialog/` | ~5 gd | Boot entry, cutscene player, dialog speaker data |

Autoloads (from `project.godot`): `MissionState`, `DialogPlayer`, `UpgradeState`,
`EventBus`, `ShipModuleState`, `ShipProgressionState`, `SessionState`, `CameraShake`.

---

## Deliverable 1 — `docs/architecture/` hub

```
docs/architecture/
├── PROJECT.md
└── modules/
    ├── assault.md
    ├── open_space.md
    ├── infiltration.md
    ├── global.md
    └── shell.md
```

### `PROJECT.md` (top level)
- One-paragraph game description + the boot/game loop (reuse the accurate flow from
  `docs/game-structure.md`, cross-linked not copied).
- Module map table (the inventory above) with links to each module doc.
- The 8 autoloads: what each owns and when it is read/written.
- Shared `global/systems` (`EventBus`, `CameraShake`, `CameraDirector`,
  `BackgroundController`) — one line each, link to `global.md`.
- Cross-cutting conventions: Godot 4.6; component-composition pattern; config-driven
  enemies (`*_config.tres`); **never commit (user handles git)**; world-scale / design-unit
  coordinate convention.
- Links to `docs/game-structure.md`, `docs/enemy-roster.md`, and the per-mode race docs.

### Module docs (`modules/*.md`)
Each contains, scaled to module size:
- **Directory map** — annotated tree of the module.
- **Scene ↔ script wiring** — the key scenes and the scripts/nodes that drive them.
- **Mechanics** — prose per mechanic with file paths (e.g. assault: wave/spawn system,
  scoring, player ship + states, projectiles/bullet pool, levels/director, race sub-mode,
  GUI). For each mechanic: what it does, where it lives, how it connects.
- **Links** to relevant per-entity docs and existing `docs/*.md`.

### `global.md` — also a usage guide ("how to add to an entity")
Beyond mapping shared code, `global.md` MUST include **integration recipes** showing how
to wire shared systems into a new entity. At minimum:

- **Health** (`health_component.gd`) — add the node, set `max_health`, connect
  `amount_changed`; relationship to `temp_health_component.gd`.
- **Hurtbox / Hitbox** (`hurtbox_component.gd`, `hitbox_component.gd`) — Area2D layers &
  masks, the `received_damage` signal path, how damage actually reaches Health.
- **Shield** (`shield_component.gd`, `bubble_shield.tscn`, `damage_reaction.gd`) — charges,
  `consume_one()`, the DamageReaction order (`on_hit` → flash → shield → health), and the
  `BubbleShield` visual `setup(shield)`.
- **DamageReaction** — what `setup(health, shield, hurtbox, sprite)` wires, flash, on_hit.
- **Overheat** (`overheat_component.gd`) — weapon heat gating.
- **State machine** (`state_machine.gd` + `state.gd`) — the `State` base contract
  (`process_physics`, transitions), how `StateMachine` picks the initial state, and the
  per-state-folder convention used by the player, light_assault_ship, and racers.
- **Ship modules** (`ship_module_base.gd` + the ~17 modules, `ShipModuleState`) — what a
  module is, `apply()/remove()/tick()`, how the player equips them, how to add a new one.
- **Effects** (`hit_effect`, `explosion_effect`, `thruster_effect`, `low_health_smoke`,
  `rocket_trail`) — attach-and-go visual components.
- **Pickups** (`global/pickups`) and **resources** (`global/resources/*`: attack,
  movement, formation, waves, levels) — what each resource type configures.
- **PlayerBase** (`player_base.gd`) — the shared base every player ship extends; what it
  provides (health/shield/overheat, knockback, EventBus emission).

Each recipe: the node(s) to add, required exports/wiring, the signal(s) to connect, and a
short code snippet. This section is the reference future "add an entity" work relies on.

---

## Deliverable 2 — Per-entity docs (mirror `RACER.md`)

In-tree, beside the entity, using the existing `RACER.md` layout adapted for
config-driven enemies.

- **Enemies (9):** `assault/scenes/enemies/<x>/ENEMY.md` for bomber, bonus_drone,
  drone_interceptor, gunship, interceptor, kamikaze_drone, light_assault_ship, ram_ship,
  sniper_enemy.
- **Hazards (3):** `assault/scenes/hazards/<x>/HAZARD.md` for big_asteroid, small_asteroid,
  laser_ray.

**Template (per entity):**
```
# <Name> — <one-line role>

**Role:** ...
**Fantasy / threat:** ...

## Stats
| Property | Value |  (HP, damage, speed, sprite, scene, config .tres)

## Behaviour & Movement
- How it moves (EnemyPathMover / states / config movement resource)
- How it attacks (attack_controller / aim_mode / projectile)
- Death / scoring contribution

## Config exports
| Export | Default | Meaning |   (read from <x>_config.gd / .tres)

## Spawn notes
- WaveBuilder method (e.g. `b.gunship()`), typical placement; link to docs/enemy-roster.md

## Files
<annotated file tree of the entity dir>
```

For enemies that use a state folder (e.g. `light_assault_ship/states`), include a small
**State Graph** section as `RACER.md` does. The boss-phase logic in
`level_1_director.gd` is documented in `assault.md` (no discrete boss entity exists).

---

## Deliverable 3 — Root `CLAUDE.md`

Concise, derived from the hub:
- Project one-liner + the module map table (links into `docs/architecture/`).
- Key conventions: Godot 4.6, component-composition, config-driven enemies, design-unit
  coordinates, **never commit — user handles all git**.
- A short "where things live" pointer list.
- **Mandatory rule:** "After any structural change to scenes/scripts (new/renamed/moved/
  deleted entity, component, module, or mechanic), invoke the `updating-project-docs`
  skill before finishing." Keep CLAUDE.md lean — depth stays in the hub.

---

## Deliverable 4 — `updating-project-docs` skill

Project-local skill at `.claude/skills/updating-project-docs/SKILL.md` (with the standard
`name` + `description` frontmatter so the Skill tool discovers it).

Workflow the skill enforces:
1. Identify what changed (entity / component / module / mechanic) and which module(s).
2. Update the affected `modules/<module>.md` (directory map + mechanics).
3. If module boundaries or the autoload set changed, update `PROJECT.md`.
4. Add/update/remove the relevant per-entity doc (`ENEMY.md` / `HAZARD.md` / `RACER.md`)
   using the inline template.
5. If the module map or a convention changed, sync `CLAUDE.md`.
6. Do **not** commit (user handles git).

The skill embeds the per-entity template and a short checklist so updates stay uniform.

---

## Deliverable 5 — Reconcile existing docs

- `ProjectStructure.md` → **rewrite** as a short pointer to `docs/architecture/PROJECT.md`
  (removes the stale `sector_operations` naming).
- `docs/game-structure.md` → **keep**, cross-link from `PROJECT.md`.
- `docs/enemy-roster.md` → **keep** (accurate WaveBuilder reference), cross-link from
  `assault.md` and every `ENEMY.md`.
- Other `docs/*.md` (scoring, bullet pool, race-improvements, superpowers/*) → left as-is;
  linked from the relevant module doc where useful.

---

## Execution method — subagents per module

Dispatch parallel **analysis + drafting** subagents, one per module, each scoped to its
directory:

- `assault` agent → drafts `modules/assault.md` **and** the 9 `ENEMY.md` + 3 `HAZARD.md`
  drafts (largest job; may be split enemies vs module if needed).
- `open_space` agent → `modules/open_space.md`.
- `infiltration` agent → `modules/infiltration.md`.
- `global` agent → `modules/global.md` **including the integration recipes**.
- `shell` agent → `modules/shell.md` (boot, cutscenes, dialog).

Each agent returns finished Markdown (it may read source freely but only writes its own
doc files). The main session then assembles `PROJECT.md`, `CLAUDE.md`, the skill, and the
reconciliation edits, ensuring cross-links and naming are consistent.

Subagents receive: the target file path(s), the `RACER.md` template to mirror, the naming
conventions, and an instruction to use real file paths and measured values (no
placeholders).

---

## Verification

- Every module dir has a `modules/<module>.md`; `PROJECT.md` links resolve.
- All 9 enemies + 3 hazards have a doc; each references its real scene/config files.
- `global.md` integration recipes name real components and compile-plausible snippets.
- `CLAUDE.md` module table matches `PROJECT.md`.
- `ProjectStructure.md` no longer mentions `sector_operations`.
- `.claude/skills/updating-project-docs/SKILL.md` has valid frontmatter and is invokable.
- Spot-check 2–3 per-entity docs against their `.gd`/`.tres` for accuracy.

---

## Notes / constraints

- **Never commit** — per project rule, the user handles all git. The spec and all
  generated docs are left unstaged for the user to review and commit.
- Leftover editor temp files (e.g. `light_assault_ship.tscn*.tmp`) are ignored.
- The `.claude/worktrees/` copy is ignored during analysis.
