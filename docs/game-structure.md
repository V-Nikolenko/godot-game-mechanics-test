# Game Structure

## Overview

A space action game with three distinct gameplay zones connected through a persistent hub.
The player begins with a first-launch cinematic and then cycles between missions via the
Open Space hub, with progression gated by mission completion.

---

## Game Loop

```
First launch:
  Boot → Intro Cutscene → Assault L1 → Level Exit Cutscene → Infiltration

Every launch after:
  Boot → Open Space Hub → (select mission) → play → return to Hub
```

### Boot

`boot/boot.gd` runs on every launch. It checks `MissionState.has_cutscene_been_seen("intro_to_assault")`:
- **First launch** → `cutscenes/intro/intro_cutscene.tscn`
- **All other launches** → `open_space/scenes/levels/sector_hub.tscn`

---

## Zones

### Open Space Hub
Free-roam arcade flight. The player navigates a ship in 360° inertia-based flight,
interacts with a planet to select and launch missions.

- **Player:** `OpenSpacePlayerShip` — rotate + thrust + flip-boost + shoot
- **Mission select:** Hold `E` near planet for 2.2 s. Arc fills as progress indicator.
- **Locking:** Infiltration locked until Assault is complete (`MissionState`)
- **NPCs:** 3 patrol drones orbit the sector

### Assault Mission
Top-down vertical shoot-em-up. Enemies scroll in from the top in scripted waves.

- **Player:** `PlayerFighter` — state-machine movement (idle / move / dash), homing missiles, warhead missiles, overheat system
- **Enemies:** 8 types — Light Assault, Sniper, Gunship, Bomber, Ram, Kamikaze Drone + allies + asteroids
- **Waves:** Defined in `level_1_waves.gd` / `level_2_waves.gd` using `WaveBuilder`
- **Exit:** All waves complete → `LevelExitCutscene` → Infiltration (first clear) or Hub (replay)

### Infiltration Mission
Isometric top-down exploration. Player controls a humanoid character through an enemy base.

- **Player:** `Player` — cardinal + diagonal movement, dash, shadow sprite, upgrade loadout
- **Upgrades:** Double-jump, hover-jump (resources ready, no UI yet)
- **Exit:** Not yet defined (MVP)

---

## Scene Routing Map

```
boot.tscn
  ↓ first launch          ↓ subsequent
intro_cutscene.tscn    sector_hub.tscn
  ↓                         ↑   ↑
level_1.tscn ─────────────────   │
  ↓                              │
level_exit_cutscene.tscn         │
  ↓ first clear   ↓ replay ──────┘
TestIsometricScene.tscn
```

---

## Persistence

`MissionState` autoload writes to `user://mission_state.cfg` (ConfigFile).

| Key | Type | Meaning |
|-----|------|---------|
| `assault` / `infiltration` | completed + stars | Mission beaten, star rating |
| `intro_to_assault` | cutscene flag | Intro already played — skip on next boot |

---

## Global Systems

| System | Location | Used by |
|--------|----------|---------|
| `MissionState` | `global/autoloads/` | Boot, Hub, Level exit, Cutscenes |
| `Health` | `global/components/` | All player ships + enemies |
| `HurtBox` / `HitBox` | `global/components/` | All combat entities |
| `ThrusterEffect` | `global/components/` | Open space ship, Assault ship, Cutscene ships |
| `ExplosionEffect` / `HitEffect` | `global/components/` | All combat entities |
| `RocketTrail` | `global/components/` | Missiles |
| `CutsceneBase` | `cutscenes/base/` | All cutscenes |
| `WaveBuilder` | `global/utils/` | Assault level scripts |
| Movement / Formation / Wave resources | `global/resources/` | Assault enemy system |

---
---

# Directory Structure

## Current Structure (annotated)

```
game-test-mechanics/
├── boot/                           ✅ clean, single responsibility
│   ├── boot.gd
│   └── boot.tscn
│
├── cutscenes/                      ✅ well organised
│   ├── base/
│   │   ├── cutscene_base.gd
│   │   ├── dialog_presenter.gd
│   │   └── dialog_presenter.tscn
│   ├── intro/
│   │   ├── intro_cutscene.gd
│   │   └── intro_cutscene.tscn
│   └── level_exit/
│       ├── level_exit_cutscene.gd
│       └── level_exit_cutscene.tscn
│
├── global/                         ✅ shared systems well separated
│   ├── assets/                     (fonts, ui, vfx — mostly empty)
│   ├── autoloads/
│   │   └── mission_state.gd
│   ├── components/                 (11 reusable components)
│   ├── resources/
│   │   ├── attack/
│   │   ├── formation/
│   │   ├── movement/
│   │   └── waves/
│   ├── statemachine/
│   └── utils/
│       └── wave_builder.gd         ⚠️  assault-specific utility in global
│
├── assault/                        ⚠️  inconsistent internal layout
│   ├── assets/
│   │   ├── sprites/                ⚠️  all 17 sprites flat, no subfolders by entity
│   │   ├── gui/
│   │   ├── particles/
│   │   ├── shader/
│   │   └── sounds/
│   ├── player/                     ⚠️  player lives at assault root, not under scenes/
│   │   ├── player_fighter.gd
│   │   ├── player_fighter.tscn
│   │   ├── movement_controller.gd
│   │   ├── overheat.gd
│   │   ├── overheat_bar.gd
│   │   └── states/
│   ├── scenes/
│   │   ├── allies/
│   │   ├── enemies/                (8 enemy types, each in own subfolder ✅)
│   │   ├── gui/
│   │   ├── hazards/
│   │   ├── levels/
│   │   ├── projectiles/
│   │   └── systems/
│   └── tools/
│
├── infiltration_mission/           ⚠️  scripts split from scenes
│   ├── assets/
│   │   ├── tilesets/
│   │   └── upgrades/               ⚠️  resource .tres files under assets/
│   ├── scenes/
│   │   ├── effects/
│   │   ├── entities/
│   │   │   ├── player/             (player.tscn + player.png here)
│   │   │   └── props/
│   │   ├── levels/
│   │   └── systems/
│   └── scripts/                    ⚠️  all player scripts here, far from their scenes
│       └── player/
│           ├── config/
│           ├── runtime/
│           └── upgrades/
│
└── open_space/                     ⚠️  sparse — only 2 scripts, no assets subfolder pattern
    ├── assets/
    │   └── sprites/
    │       └── planet_stub.png
    └── scenes/
        ├── entities/
        │   ├── enemies/
        │   ├── interactables/      ⚠️  MissionConfigResource here, not in global/resources
        │   └── player/
        └── levels/
```

---

## Preferred Structure

Key principles:
- **Co-locate scripts with their scenes** — a `.gd` lives next to its `.tscn`
- **Assets separate from code** — per-mission `assets/` holds only images, audio, shaders
- **Mission folder is self-contained** — everything for one mission in one place
- **Global only for truly shared code** — assault-specific utilities belong in `assault/`
- **Sprites organised by entity type** — not a flat dump

```
game-test-mechanics/
├── boot/                           (unchanged)
├── cutscenes/                      (unchanged)
│
├── global/
│   ├── autoloads/
│   ├── components/
│   ├── resources/
│   │   ├── attack/
│   │   ├── formation/
│   │   ├── movement/
│   │   ├── waves/
│   │   └── mission_config_resource.gd   ← move from open_space/
│   ├── statemachine/
│   └── utils/                      (general utilities only)
│
├── assault/
│   ├── assets/
│   │   ├── sprites/
│   │   │   ├── player/             ← group by entity
│   │   │   ├── enemies/
│   │   │   ├── projectiles/
│   │   │   └── environment/
│   │   ├── audio/
│   │   ├── shader/
│   │   └── ui/
│   ├── scenes/
│   │   ├── levels/
│   │   │   ├── level_1.tscn
│   │   │   └── level_1_waves.gd
│   │   ├── player/                 ← move from assault/player/
│   │   │   ├── player_fighter.tscn
│   │   │   ├── player_fighter.gd
│   │   │   ├── movement_controller.gd
│   │   │   ├── overheat.gd
│   │   │   ├── overheat_bar.gd
│   │   │   └── states/
│   │   ├── enemies/
│   │   ├── hazards/
│   │   ├── projectiles/
│   │   ├── systems/
│   │   │   ├── wave_manager/
│   │   │   └── wave_builder.gd     ← move from global/utils/
│   │   └── ui/
│   └── allies/
│
├── infiltration/                   ← rename: drop "_mission" suffix for consistency
│   ├── assets/
│   │   ├── sprites/
│   │   ├── tilesets/
│   │   └── audio/
│   ├── scenes/
│   │   ├── levels/
│   │   ├── entities/
│   │   │   ├── player/
│   │   │   │   ├── player.tscn
│   │   │   │   ├── player.gd
│   │   │   │   ├── player.png      ← sprite co-located
│   │   │   │   ├── shadow.png
│   │   │   │   ├── config/         ← move from scripts/player/config/
│   │   │   │   ├── states/         ← move from scripts/player/runtime/
│   │   │   │   └── upgrades/       ← move from scripts/player/upgrades/
│   │   │   └── props/
│   │   └── systems/
│   └── resources/
│       └── upgrades/               ← move .tres files here from assets/upgrades/
│
└── open_space/
    ├── assets/
    │   └── sprites/
    ├── scenes/
    │   ├── levels/
    │   └── entities/
    │       ├── player/
    │       ├── enemies/
    │       └── interactables/      ← keep planet here; MissionConfigResource → global
```

---

## Comparison Table

| Issue | Current | Preferred |
|-------|---------|-----------|
| Assault player location | `assault/player/` (root level) | `assault/scenes/player/` |
| Infiltration scripts | `infiltration_mission/scripts/player/` separate from scenes | Merged into `infiltration/scenes/entities/player/` |
| Assault sprites | 17 files flat in `assault/assets/sprites/` | Subfolders: `player/`, `enemies/`, `projectiles/`, `environment/` |
| WaveBuilder location | `global/utils/` (assault-specific) | `assault/scenes/systems/` |
| MissionConfigResource | `open_space/scenes/entities/interactables/` | `global/resources/` |
| Upgrade .tres files | `infiltration_mission/assets/upgrades/` | `infiltration/resources/upgrades/` |
| Mission folder naming | `infiltration_mission/` vs `open_space/` vs `assault/` | Consistent: `assault/` `infiltration/` `open_space/` |
| Scripts vs scenes split | Infiltration splits them entirely | Co-locate `.gd` next to `.tscn` |

---

## What to Change First

Highest impact, lowest risk:

1. **Rename `infiltration_mission/` → `infiltration/`** — cosmetic, fixes naming inconsistency
2. **Move assault sprites into entity subfolders** — assets only, no code changes
3. **Move `assault/player/` → `assault/scenes/player/`** — update `.tscn` node script paths
4. **Merge infiltration scripts into their scene folders** — biggest cleanup, requires path updates
5. **Move `WaveBuilder` → `assault/scenes/systems/`** — one file, low risk
6. **Move `MissionConfigResource` → `global/resources/`** — update `open_space` import path
