# Project Knowledge Base Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a maintained knowledge base (`docs/architecture/` hub + per-entity docs + root `CLAUDE.md` + an updating skill) describing the project's structure and every game mechanic, reconciling the stale existing docs.

**Architecture:** A `docs/architecture/` hub (`PROJECT.md` + one doc per module) is the source of truth. Per-entity `ENEMY.md`/`HAZARD.md` files live beside their entities, mirroring the existing `RACER.md` format. `global.md` doubles as a "how to wire shared components into an entity" guide. A lean root `CLAUDE.md` links into the hub and mandates a `updating-project-docs` skill after structural changes. Analysis is done by parallel subagents, one per module; the main session assembles the cross-linked top level.

**Tech Stack:** Godot 4.6 / GDScript project. Deliverables are Markdown only. No code is changed.

**Constraints:**
- **NEVER commit.** Per project rule the user handles all git. Every task leaves files **unstaged**. There are no `git commit` steps anywhere in this plan.
- Ignore `.claude/worktrees/` and editor temp files (`*.tmp`) during analysis.
- Reference **real** file paths and **measured** values — no placeholders in generated docs.

**Reference spec:** `docs/superpowers/specs/2026-06-14-project-knowledge-base-design.md`

**Format mirror (all per-entity docs copy this layout):** `assault/scenes/race/racers/fang/RACER.md`

---

## File Structure (what gets created)

```
docs/architecture/
├── PROJECT.md                              (Task 9)
└── modules/
    ├── global.md                           (Task 2)
    ├── assault.md                          (Task 3)
    ├── open_space.md                       (Task 6)
    ├── infiltration.md                     (Task 7)
    └── shell.md                            (Task 8)

assault/scenes/enemies/<x>/ENEMY.md         (Task 4 — 9 files)
assault/scenes/hazards/<x>/HAZARD.md        (Task 5 — 3 files)

CLAUDE.md                                   (Task 10)
.claude/skills/updating-project-docs/SKILL.md (Task 11)
ProjectStructure.md                         (Task 12 — rewritten)
```

**Per-entity doc template** (used by Tasks 4 & 5; copied verbatim into the subagent prompts):

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

## State Graph        ← include ONLY if the entity has a states/ folder

```
<ascii state graph like RACER.md>
```

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

```
<x>/
├── ENEMY.md            ← this file
├── <x>.tscn
├── <x>.gd
└── <x>_config.gd / .tres
```
```

---

## Task 1: Scaffold the hub directory

**Files:**
- Create: `docs/architecture/modules/` (directory)

- [ ] **Step 1: Create the directory tree**

Run:
```bash
mkdir -p docs/architecture/modules
```

- [ ] **Step 2: Verify it exists and is empty**

Run:
```bash
ls -la docs/architecture && ls -la docs/architecture/modules
```
Expected: both directories exist; `modules/` is empty.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 2: `global.md` (shared systems + integration recipes)

Dispatch a `general-purpose` analysis subagent scoped to `global/`. This runs first because every other module doc references shared components.

**Files:**
- Create: `docs/architecture/modules/global.md`

- [ ] **Step 1: Dispatch the global-analysis subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> You are documenting the `global/` module of a Godot 4.6 GDScript game (working dir is the repo root). Write a single Markdown file to `docs/architecture/modules/global.md`. Do not change any code. Do not run git.
>
> Read these directories fully before writing: `global/components/`, `global/statemachine/`, `global/entities/`, `global/ship_modules/`, `global/systems/`, `global/autoloads/`, `global/autoload/`, `global/pickups/`, `global/resources/`, `global/ui/`. Use real file paths and real exported property names/defaults read from the source.
>
> The document MUST have these sections:
> 1. **Overview** — one paragraph: what `global/` is (shared, reused across all modules).
> 2. **Directory map** — annotated tree of `global/`.
> 3. **Autoloads** — table of the 8 autoloads (`MissionState`, `DialogPlayer`, `UpgradeState`, `EventBus`, `ShipModuleState`, `ShipProgressionState`, `SessionState`, `CameraShake`): file, what state it owns, when read/written.
> 4. **Shared systems** (`global/systems/`): `event_bus.gd`, `camera_shake.gd`, `camera_director.gd`, `background_controller.gd` — one short subsection each.
> 5. **Integration recipes — "How to add X to an entity"** (THIS IS THE MOST IMPORTANT SECTION). For each of the following, give: the node(s)/script(s) to add, the required exports/wiring, the signal(s) to connect, and a short GDScript snippet showing the wiring. Cover: **Health** (`health_component.gd`, + `temp_health_component.gd`); **Hurtbox/Hitbox** (`hurtbox_component.gd`, `hitbox_component.gd` — explain collision_layer/mask and the `received_damage` signal path to Health); **Shield** (`shield_component.gd`, `bubble_shield.tscn`, and how `damage_reaction.gd` orders on_hit → flash → shield → health); **DamageReaction** (what `setup(health, shield, hurtbox, sprite)` wires); **Overheat** (`overheat_component.gd`); **State machine** (`state_machine.gd` + `state.gd` — the `State` base contract, how the initial state is chosen, the per-state-folder convention); **Ship modules** (`ship_module_base.gd`, the ~17 modules, `ShipModuleState` — what a module is, `apply()/remove()/tick()`, how to add a new one); **Effects** (`hit_effect.gd`, `explosion_effect.gd`, `thruster_effect.gd`, `low_health_smoke.gd`, `rocket_trail.gd`); **PlayerBase** (`player_base.gd` — what the shared base provides). Verify each snippet against the real component API (read the .gd first).
> 6. **Pickups & resources** — `global/pickups/` and `global/resources/` (attack, movement, formation, waves, levels): what each resource type configures.
>
> Keep snippets minimal but real. End the file. Report back the path you wrote and a 5-line summary.

- [ ] **Step 2: Verify the file exists and references real components**

Run:
```bash
test -f docs/architecture/modules/global.md && echo OK
grep -c -E "health_component|shield_component|hurtbox_component|state_machine|ship_module_base|player_base" docs/architecture/modules/global.md
```
Expected: `OK`, and a count ≥ 6.

- [ ] **Step 3: Spot-check one recipe for accuracy**

Read the Shield recipe in `global.md` and confirm it matches `global/components/damage_reaction.gd` (the on_hit → flash → shield → health order). Fix inline if wrong.

- [ ] **Step 4: Do NOT commit.** Leave unstaged.

---

## Task 3: `assault.md` (module map + mechanics)

Dispatch a subagent scoped to `assault/` (excluding per-entity deep-dives, which are Tasks 4–5).

**Files:**
- Create: `docs/architecture/modules/assault.md`

- [ ] **Step 1: Dispatch the assault-module subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> You are documenting the `assault/` module of a Godot 4.6 GDScript game (working dir is the repo root). Write `docs/architecture/modules/assault.md`. Do not change code. Do not run git. Ignore `*.tmp` files and `.claude/worktrees/`.
>
> Read: `assault/scenes/player/`, `assault/scenes/projectiles/`, `assault/scenes/systems/`, `assault/scenes/levels/` (esp. `levels/edelia/1/level_1_director.gd`), `assault/scenes/gui/`, `assault/scenes/allies/`, and the top of `assault/scenes/enemies/base_enemy.gd` and `assault/scenes/enemies/enemy_path_mover.gd`. Skim `assault/scenes/race/` enough to describe the race sub-mode at a high level (it has its own per-racer docs — link to them, don't re-document each racer).
>
> The document MUST have:
> 1. **Overview** — what the assault mission is (autoscroller shmup) + that it hosts the race sub-mode.
> 2. **Directory map** — annotated tree of `assault/scenes/`.
> 3. **Mechanics** — a subsection per mechanic, each with real file paths and how it connects to `global/` components (link to `../modules/global.md`):
>    - Player ship (`assault/scenes/player/` — states folder, modules integration).
>    - Wave / spawn system (`WaveManager`, `WaveBuilder`, `enemy_path_mover.gd`, `base_enemy.gd`) — link to `docs/enemy-roster.md`.
>    - Projectiles & bullet pool (`assault/scenes/projectiles/`, and `global/components/bullet_pool.gd`) — link to `docs/BULLET_POOL.md`.
>    - Scoring (link to `docs/scoring_guide.md` and `docs/assault-spawning-scoring-internals.md`).
>    - Levels & director (`assault/scenes/levels/edelia/1/`), including the **boss-phase logic in `level_1_director.gd`** (there is no discrete boss entity — document it here).
>    - Hazards (point to the per-hazard docs under `assault/scenes/hazards/`).
>    - Enemies (point to the per-enemy docs under `assault/scenes/enemies/`).
>    - Race sub-mode (`assault/scenes/race/`) — high-level only; link to the racer `RACER.md` files.
>    - GUI (`assault/scenes/gui/`).
> 4. **Links** — to `global.md`, `docs/enemy-roster.md`, `docs/scoring_guide.md`, `docs/BULLET_POOL.md`, and the race docs.
>
> Report the path written and a 5-line summary.

- [ ] **Step 2: Verify the file**

Run:
```bash
test -f docs/architecture/modules/assault.md && echo OK
grep -c -E "enemy-roster|scoring_guide|level_1_director|global.md" docs/architecture/modules/assault.md
```
Expected: `OK`, count ≥ 3.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 4: 9× `ENEMY.md` (per-enemy docs)

Dispatch a subagent to write all nine enemy docs using the template. Enemies:
`bomber`, `bonus_drone`, `drone_interceptor`, `gunship`, `interceptor`,
`kamikaze_drone`, `light_assault_ship`, `ram_ship`, `sniper_enemy`.

**Files:**
- Create: `assault/scenes/enemies/<x>/ENEMY.md` (9 files)

- [ ] **Step 1: Dispatch the enemy-docs subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt (paste the template from this plan's "Per-entity doc template" section into the prompt where indicated):

> You are writing per-enemy documentation for the assault mission of a Godot 4.6 game (working dir is the repo root). Do not change code. Do not run git.
>
> First read the format you must mirror: `assault/scenes/race/racers/fang/RACER.md`. Also read `docs/enemy-roster.md` for the WaveBuilder spawn methods.
>
> For EACH of these enemy directories, write a file named `ENEMY.md` inside that directory:
> `assault/scenes/enemies/bomber/`, `assault/scenes/enemies/bonus_drone/`, `assault/scenes/enemies/drone_interceptor/`, `assault/scenes/enemies/gunship/`, `assault/scenes/enemies/interceptor/`, `assault/scenes/enemies/kamikaze_drone/`, `assault/scenes/enemies/light_assault_ship/`, `assault/scenes/enemies/ram_ship/`, `assault/scenes/enemies/sniper_enemy/`.
>
> For each enemy, READ its `.gd`, its `.tscn`, and its `*_config.gd` + `*_config.tres` to get real HP, damage, speed, and every exported config value with its real default. `light_assault_ship` has a `states/` folder — read it and include a State Graph section. Use this exact template (fill every field from the real files; omit the State Graph section for enemies with no states/ folder):
>
> [PASTE THE PER-ENTITY DOC TEMPLATE HERE]
>
> Match each enemy's WaveBuilder spawn method from `docs/enemy-roster.md`. Do not invent values — if something isn't in the files, say "n/a". After writing all 9 files, report each path and confirm the config values came from the real `.tres`/`.gd`.

- [ ] **Step 2: Verify all 9 files exist**

Run:
```bash
for e in bomber bonus_drone drone_interceptor gunship interceptor kamikaze_drone light_assault_ship ram_ship sniper_enemy; do test -f assault/scenes/enemies/$e/ENEMY.md && echo "OK $e" || echo "MISSING $e"; done
```
Expected: 9 lines all `OK`.

- [ ] **Step 3: Spot-check 2 enemies against source**

Read `assault/scenes/enemies/gunship/ENEMY.md` and `assault/scenes/enemies/sniper_enemy/ENEMY.md`; confirm HP/damage/exports match `gunship_config.tres` and `sniper_enemy.gd`. Fix inline if any value is wrong or a placeholder.

- [ ] **Step 4: Do NOT commit.** Leave unstaged.

---

## Task 5: 3× `HAZARD.md` (per-hazard docs)

**Files:**
- Create: `assault/scenes/hazards/<x>/HAZARD.md` (big_asteroid, small_asteroid, laser_ray)

- [ ] **Step 1: Dispatch the hazard-docs subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> You are writing per-hazard documentation for the assault mission of a Godot 4.6 game (working dir is the repo root). Do not change code. Do not run git.
>
> Mirror the format of `assault/scenes/race/racers/fang/RACER.md`, adapted for hazards. Read `assault/scenes/hazards/asteroid_base.gd` (shared base) first, then each hazard.
>
> Write a `HAZARD.md` inside each of: `assault/scenes/hazards/big_asteroid/`, `assault/scenes/hazards/small_asteroid/`, `assault/scenes/hazards/laser_ray/`. For each, read its `.gd` and `.tscn` for real values. Use this structure: a title + one-line role; **Role / threat**; a **Stats** table (HP if any, contact damage, speed/behaviour, sprite, scene); a **Behaviour** section (how it moves/spawns, what it does on contact, how it is destroyed — note `big_asteroid` and `small_asteroid` share `asteroid_base.gd`, and `laser_ray` has a `laser_wall.tscn` variant); and a **Files** tree. Use real values; write "n/a" where a property does not apply.
>
> After writing all 3 files, report each path.

- [ ] **Step 2: Verify all 3 files exist**

Run:
```bash
for h in big_asteroid small_asteroid laser_ray; do test -f assault/scenes/hazards/$h/HAZARD.md && echo "OK $h" || echo "MISSING $h"; done
```
Expected: 3 lines all `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 6: `open_space.md`

**Files:**
- Create: `docs/architecture/modules/open_space.md`

- [ ] **Step 1: Dispatch the open_space subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> Document the `open_space/` module of a Godot 4.6 game (working dir is repo root). Write `docs/architecture/modules/open_space.md`. Do not change code or run git.
>
> Read all of `open_space/scenes/` (`entities/`, `gui/`, `levels/`, `mission_data/`, `mission_select_hubs/`, `mission_select_ui/`) and their scripts. The doc MUST have: **Overview** (the persistent hub world + mission select that connects the three game modes — cross-link `docs/game-structure.md`); **Directory map** (annotated tree); **Mechanics** (hub/player entity, mission-select UI and hubs, mission_data resources — how a mission is defined and launched, which autoloads it reads/writes e.g. `MissionState`/`SessionState`); **Links** to `../modules/global.md` and `docs/game-structure.md`.
>
> Report the path and a short summary.

- [ ] **Step 2: Verify**

Run: `test -f docs/architecture/modules/open_space.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 7: `infiltration.md`

**Files:**
- Create: `docs/architecture/modules/infiltration.md`

- [ ] **Step 1: Dispatch the infiltration subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> Document the `infiltration/` module of a Godot 4.6 game (working dir is repo root). Write `docs/architecture/modules/infiltration.md`. Do not change code or run git.
>
> Read all of `infiltration/scenes/` (`effects/`, `entities/`, `levels/`, `systems/`) and `infiltration/scripts/` (esp. `scripts/player/`). The doc MUST have: **Overview** (isometric ground-combat mission); **Directory map** (annotated tree of `infiltration/scenes/` and `infiltration/scripts/`); **Mechanics** (player controller, entities/enemies, level/systems, effects — real file paths, and how it reuses `global/` components, cross-link `../modules/global.md`); **Links**.
>
> Report the path and a short summary.

- [ ] **Step 2: Verify**

Run: `test -f docs/architecture/modules/infiltration.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 8: `shell.md` (boot, cutscenes, dialog)

**Files:**
- Create: `docs/architecture/modules/shell.md`

- [ ] **Step 1: Dispatch the shell subagent**

Use the Agent tool (`subagent_type: general-purpose`) with this exact prompt:

> Document the small "shell" support modules of a Godot 4.6 game (working dir is repo root): `boot/`, `cutscenes/`, `dialog/`. Write `docs/architecture/modules/shell.md`. Do not change code or run git.
>
> Read `boot/` (the boot entry scene/script and `project.godot`'s `run/main_scene`), `cutscenes/` (`base/`, `intro/`, `level_exit/`), and `dialog/` (`scripts/speakers/`). The doc MUST have: **Overview** (these three are the app shell: boot entry, cutscene playback, dialog speaker data); a short section per module with directory map and how it plugs into the game loop (cross-link `docs/game-structure.md` and the `DialogPlayer` autoload in `../modules/global.md`); **Links**.
>
> Report the path and a short summary.

- [ ] **Step 2: Verify**

Run: `test -f docs/architecture/modules/shell.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 9: `PROJECT.md` (assemble the top level — main session)

Write this yourself in the main session after Tasks 2–8 so links resolve.

**Files:**
- Create: `docs/architecture/PROJECT.md`

- [ ] **Step 1: Write `PROJECT.md`**

Include, in order:
1. **Title + one-paragraph game description.**
2. **Game loop** — short, cross-linking `docs/game-structure.md` (do not duplicate it).
3. **Module map table** — exactly this content (links must point to the files created above):

```markdown
| Module | Path | Role | Doc |
|---|---|---|---|
| Assault Mission | `assault/` | Autoscroller shmup; hosts the race sub-mode | [assault.md](modules/assault.md) |
| Open Space | `open_space/` | Persistent hub world + mission select | [open_space.md](modules/open_space.md) |
| Infiltration | `infiltration/` | Isometric ground combat | [infiltration.md](modules/infiltration.md) |
| Global (shared) | `global/` | Components, entities, ship modules, state machine, pickups, resources, UI, autoloads | [global.md](modules/global.md) |
| Shell | `boot/`, `cutscenes/`, `dialog/` | Boot entry, cutscenes, dialog data | [shell.md](modules/shell.md) |
```

4. **Autoloads** — table of the 8 autoloads (name, file, one-line responsibility), pointing to `global.md` for detail.
5. **Shared systems** — one line each for `EventBus`, `CameraShake`, `CameraDirector`, `BackgroundController`, link to `global.md`.
6. **Conventions** — Godot 4.6; component-composition; config-driven enemies (`*_config.tres`); design-unit/world-scale coordinates; **never commit (user handles git)**.
7. **Per-entity docs index** — note that racers have `RACER.md`, enemies have `ENEMY.md`, hazards have `HAZARD.md` beside each entity; link to `docs/enemy-roster.md`.
8. **Related docs** — links to `docs/game-structure.md`, `docs/enemy-roster.md`, `docs/scoring_guide.md`, `docs/BULLET_POOL.md`.

- [ ] **Step 2: Verify all module links resolve**

Run:
```bash
cd docs/architecture && for f in $(grep -oE 'modules/[a-z_]+\.md' PROJECT.md | sort -u); do test -f "$f" && echo "OK $f" || echo "BROKEN $f"; done; cd - >/dev/null
```
Expected: 5 lines all `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 10: Root `CLAUDE.md`

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write `CLAUDE.md`** (lean; derived from `PROJECT.md`)

Contents:
1. **Project one-liner.**
2. **Module map table** — same 5 rows as `PROJECT.md` Step 1.3 but with links pointing to `docs/architecture/modules/<x>.md` and a link to `docs/architecture/PROJECT.md` as the full map.
3. **Key conventions** (bulleted): Godot 4.6; component-composition pattern; config-driven enemies; design-unit coordinates; **NEVER commit — the user handles all git; work on `main` unless asked otherwise.**
4. **Where things live** — 4–6 pointer lines (shared components → `global/`; how to wire a component → `docs/architecture/modules/global.md`; per-entity behaviour → `RACER.md`/`ENEMY.md`/`HAZARD.md` beside the entity; spawn reference → `docs/enemy-roster.md`).
5. **MANDATORY — keep docs current:** a bold rule:
   > After any structural change to scenes/scripts (adding, renaming, moving, or deleting an entity, component, module, or mechanic), you MUST invoke the `updating-project-docs` skill before finishing the task.

- [ ] **Step 2: Verify links resolve**

Run:
```bash
grep -oE 'docs/architecture/[A-Za-z_/]+\.md' CLAUDE.md | sort -u | while read f; do test -f "$f" && echo "OK $f" || echo "BROKEN $f"; done
```
Expected: all `OK`.

- [ ] **Step 3: Do NOT commit.** Leave unstaged.

---

## Task 11: `updating-project-docs` skill

**Files:**
- Create: `.claude/skills/updating-project-docs/SKILL.md`

- [ ] **Step 1: Create the skill directory**

Run:
```bash
mkdir -p .claude/skills/updating-project-docs
```

- [ ] **Step 2: Write `SKILL.md`** with valid frontmatter and the workflow

The file MUST begin with YAML frontmatter:
```markdown
---
name: updating-project-docs
description: Use after any structural change to the game's scenes or scripts (adding, renaming, moving, or deleting an entity, component, module, or mechanic) to keep the docs/architecture hub, per-entity docs, and CLAUDE.md in sync.
---
```

Then the body MUST contain:
1. **When to use** — bullet list of structural-change triggers.
2. **Workflow checklist** (numbered, the agent creates a TodoWrite item per step):
   1. Identify what changed (entity / component / module / mechanic) and which module(s).
   2. Update the affected `docs/architecture/modules/<module>.md` (directory map + mechanics).
   3. If module boundaries or the autoload set changed, update `docs/architecture/PROJECT.md`.
   4. Add/update/remove the relevant per-entity doc (`ENEMY.md` / `HAZARD.md` / `RACER.md`) using the embedded template.
   5. If the module map or a convention changed, sync `CLAUDE.md`.
   6. Do **not** commit — the user handles git.
3. **Per-entity template** — embed the full template from this plan's "Per-entity doc template" section so updates stay uniform.
4. **Format reference** — note that `assault/scenes/race/racers/fang/RACER.md` is the canonical format to mirror.

- [ ] **Step 3: Verify frontmatter and discoverability**

Run:
```bash
test -f .claude/skills/updating-project-docs/SKILL.md && head -5 .claude/skills/updating-project-docs/SKILL.md
```
Expected: the file exists and the first lines show the `---` / `name:` / `description:` frontmatter.

- [ ] **Step 4: Do NOT commit.** Leave unstaged.

---

## Task 12: Reconcile existing docs

**Files:**
- Modify (rewrite): `ProjectStructure.md`
- Modify: `docs/game-structure.md` (add a back-link)
- Modify: `docs/enemy-roster.md` (add a back-link)

- [ ] **Step 1: Rewrite `ProjectStructure.md` as a pointer**

Replace the entire contents with a short stub:
```markdown
# Project Structure

> **Moved.** The authoritative project structure and mechanics reference now lives in
> [`docs/architecture/PROJECT.md`](docs/architecture/PROJECT.md), with one doc per module
> under [`docs/architecture/modules/`](docs/architecture/modules/).
>
> Per-entity behaviour is documented beside each entity as `RACER.md` (racers),
> `ENEMY.md` (assault enemies), and `HAZARD.md` (assault hazards).

This file is kept only as a redirect; do not add structure docs here.
```

- [ ] **Step 2: Add a back-link to `docs/game-structure.md`**

Insert as the second line (after the H1 title) of `docs/game-structure.md`:
```markdown

> Part of the project knowledge base — see [`architecture/PROJECT.md`](architecture/PROJECT.md).
```

- [ ] **Step 3: Add a back-link to `docs/enemy-roster.md`**

Insert as the second line (after the H1 title) of `docs/enemy-roster.md`:
```markdown

> Part of the project knowledge base — see [`architecture/PROJECT.md`](architecture/PROJECT.md). Per-enemy behaviour docs live beside each enemy as `ENEMY.md`.
```

- [ ] **Step 4: Verify `ProjectStructure.md` no longer mentions the stale module name**

Run:
```bash
grep -i "sector_operations" ProjectStructure.md && echo "STALE STILL PRESENT" || echo "OK clean"
```
Expected: `OK clean`.

- [ ] **Step 5: Do NOT commit.** Leave unstaged.

---

## Task 13: Final verification pass (main session)

- [ ] **Step 1: All hub + module files exist**

Run:
```bash
for f in docs/architecture/PROJECT.md docs/architecture/modules/global.md docs/architecture/modules/assault.md docs/architecture/modules/open_space.md docs/architecture/modules/infiltration.md docs/architecture/modules/shell.md CLAUDE.md .claude/skills/updating-project-docs/SKILL.md; do test -f "$f" && echo "OK $f" || echo "MISSING $f"; done
```
Expected: 8 lines all `OK`.

- [ ] **Step 2: All per-entity docs exist (9 enemies + 3 hazards)**

Run:
```bash
n=0; for e in bomber bonus_drone drone_interceptor gunship interceptor kamikaze_drone light_assault_ship ram_ship sniper_enemy; do test -f assault/scenes/enemies/$e/ENEMY.md && n=$((n+1)); done; for h in big_asteroid small_asteroid laser_ray; do test -f assault/scenes/hazards/$h/HAZARD.md && n=$((n+1)); done; echo "entity docs present: $n / 12"
```
Expected: `entity docs present: 12 / 12`.

- [ ] **Step 3: Scan generated docs for placeholder leakage**

Run:
```bash
grep -rIEln "TBD|TODO|FILL IN|PASTE THE|<x>|placeholder" docs/architecture assault/scenes/enemies/*/ENEMY.md assault/scenes/hazards/*/HAZARD.md CLAUDE.md .claude/skills/updating-project-docs/SKILL.md || echo "OK no placeholders"
```
Expected: `OK no placeholders` (if any file lists, open it and fix the leaked placeholder).

- [ ] **Step 4: Report completion to the user**

Summarize what was created and remind the user the files are **unstaged** for them to review and commit.

- [ ] **Step 5: Do NOT commit.** Leave everything unstaged.

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Hub `PROJECT.md` + 5 module docs → Tasks 2,3,6,7,8,9 ✓
- Per-entity ENEMY.md (9) + HAZARD.md (3) → Tasks 4,5 ✓
- `global.md` integration recipes ("how to add to an entity") → Task 2 Step 1 (explicit) ✓
- Root `CLAUDE.md` with mandatory update rule → Task 10 ✓
- `updating-project-docs` skill → Task 11 ✓
- Reconcile stale docs (rewrite ProjectStructure.md, cross-link game-structure/enemy-roster) → Task 12 ✓
- Subagent-per-module execution → Tasks 2–8 dispatch subagents ✓
- Never-commit constraint → every task ends "Do NOT commit"; no commit steps ✓

**Placeholder scan:** The only `<x>` / "PASTE THE" tokens are inside the *template* and subagent-prompt instructions (intentional); Task 13 Step 3 verifies they did not leak into generated output.

**Type/name consistency:** File paths (`docs/architecture/modules/<module>.md`, `ENEMY.md`, `HAZARD.md`, `.claude/skills/updating-project-docs/SKILL.md`) and the 5-row module table are identical across Tasks 9, 10, 13. Enemy/hazard lists match the measured directory inventory.
