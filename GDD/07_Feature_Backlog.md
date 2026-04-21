# VOID BREACH — Game Design Document
## 07 · Feature Backlog

---

## Priority Legend
| Priority | Meaning |
|---|---|
| **P1 — Critical** | Game does not function without this |
| **P2 — High** | Core experience; must ship |
| **P3 — Medium** | Important; ship if time allows |
| **P4 — Low** | Polish / nice-to-have |

---

## Implementation Order

Features should be built in this sequence to enable early playtesting:
1. Core player movement (Land Mission)
2. Core combat (Land Mission)
3. Module system (basic)
4. Open Space flight
5. Assault prototype
6. Save/load + upgrade system
7. Full module roster
8. Enemy AI (all types)
9. Level content
10. Narrative systems
11. Polish

---

## Feature List

### CORE SYSTEMS

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 1 | Land Mission Player Movement | Run, jump, coyote time, jump buffer, dash (Default Module) | P1 | None |
| 2 | Land Mission Combat — Ranged | Blaster weapon, fire, projectile, enemy HP | P1 | Player Movement |
| 3 | Land Mission Combat — Melee | Slot 3 baseline: push + minor damage | P1 | Player Movement |
| 4 | Land Mission Combat — Grenades | Slot 2: throw, arc preview, explosion | P1 | Player Movement |
| 5 | Health System | Player HP bar, damage receive, death + respawn at checkpoint | P1 | Player Movement |
| 6 | Checkpoint System | Implicit checkpoints in key rooms | P1 | Health System |
| 7 | Module Slot Manager | 3 slots, equip/unequip, broadcast events | P1 | None |
| 8 | Default Dash Module | Short dash + invincibility frames | P1 | Module System |
| 9 | Open Space Flight | Thrust, strafe, dash, inertia, gravity drift | P1 | None |
| 10 | Open Space Ship Combat | Primary fire, charged laser, missile | P1 | Open Space Flight |
| 11 | Ship Health System | Hull bar + Shield bar; shield regenerates | P1 | Open Space Combat |
| 12 | Assault Mode — Basic | Vertical scroll, ship movement, primary fire | P1 | Ship Combat |
| 13 | Alert System (Assault) | Red/Yellow alert; directional indicators; audio stings | P1 | Assault Mode |

---

### PROGRESSION SYSTEMS

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 14 | Upgrade Manager | Tracks all permanent upgrades; applies stat changes | P1 | Save System |
| 15 | Save / Load System | Autosave + manual save; all state persisted | P1 | None |
| 16 | Fragment Upgrade System | Collect N fragments → upgrade completes | P2 | Upgrade Manager |
| 17 | Module Discovery | Find module in world → appears in loadout screen | P2 | Upgrade Manager |
| 18 | Module Loadout Screen | UI to equip/swap modules in Open Space | P2 | Module System |
| 19 | Progression Gating — Open Space | Obstacles unlock with specific ship upgrades | P2 | Upgrade Manager |
| 20 | Key Inventory | Persistent key collection + key-locked doors | P2 | Save System |
| 21 | Temporary Booster System | In-mission consumable pickups (HP, Speed) | P3 | Health System |

---

### MODULE ROSTER

| # | Module | Priority | Dependencies |
|---|---|---|---|
| 22 | Heavy Armor Module | P2 | Module System |
| 23 | Parry Module | P2 | Module System |
| 24 | Blink Module | P2 | Module System |
| 25 | Afterburner Module | P2 | Module System |
| 26 | Reactor Surge Module | P2 | Module System |
| 27 | Magno-Boost Module | P2 | Module System |
| 28 | Pulse Strike Module | P2 | Module System |
| 29 | Phase Shift Module | P3 | Module System |
| 30 | Counter Impact Module | P3 | Module System |
| 31 | Magnetic Pull Module | P3 | Module System |
| 32 | Pulse Step Module | P3 | Module System |
| 33 | Momentum Crash Module | P3 | Module System |
| 34 | Nanofiber Layer Module | P3 | Module System |
| 35 | Emergency Overload Module | P3 | Module System |
| 36 | Static Charge Module | P3 | Module System |
| 37 | Temporal Drift Module | P3 | Module System |
| 38 | Vampiric Strike Module | P3 | Module System |
| 39 | Volatile Armor Module | P3 | Module System |
| 40 | Afterswing Module | P3 | Module System |
| 41 | Body Shield Module | P4 | Module System |
| 42 | Corpse Blast Module | P3 | Module System + Corpse System |
| 43 | Plunge Strike Module | P3 | Module System |

---

### ENEMY AI

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 44 | Guard AI | Patrol → Alert → Chase → Combat; cover usage; calls backup | P2 | Land Mission |
| 45 | Heavy AI | Slow charge attack; unstoppable during charge | P2 | Land Mission |
| 46 | Drone AI | Flying; ranged; ignores ground cover | P2 | Land Mission |
| 47 | Shield Trooper AI | Frontal block; shield drops during attack; must be flanked | P2 | Land Mission |
| 48 | Scavenger AI | Fast melee rush; comes in groups; erratic | P2 | Land Mission |
| 49 | Demolisher AI | Grenade spam; flushes cover | P3 | Land Mission |
| 50 | Commander AI | Buffs nearby enemies; priority target | P3 | Guard AI |
| 51 | Placed Turret (Land) | Fixed direction high damage; destroyable | P2 | Land Mission |
| 52 | Open Space Turret | 360° sensor; burst fire; may have blind spot | P2 | Open Space |
| 53 | Patrol Fighter AI | Patrol → Chase → Attack → Retreat → Rally | P2 | Open Space |
| 54 | Heavy Fighter AI | Slow, armored; leads shots | P3 | Patrol Fighter AI |
| 55 | Assault Enemy Patterns | All Assault enemy types with defined patterns | P2 | Assault Mode |

---

### WORLD CONTENT

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 56 | Cracked Wall Secret | Destructible wall reveals room | P2 | Land Mission |
| 57 | Pressure Plate Puzzle | Requires weight; corpse-compatible | P2 | Corpse System |
| 58 | Corpse Persistence System | Corpses stay in room for full visit | P2 | Enemy AI |
| 59 | Circuit Puzzle | Restore power to open path | P3 | Land Mission |
| 60 | Energy Door + Generator | Door blocks until generator destroyed | P2 | Open Space |
| 61 | Mine Field | Proximity mines; chain reaction | P2 | Open Space |
| 62 | Static Laser Grid | Timed laser pattern; timing window | P3 | Open Space |
| 63 | Fast Travel Beacon — Power Puzzle | Restore beacon via circuit puzzle | P2 | Open Space |
| 64 | Fast Travel Beacon — Defense Mission | Hold beacon against waves | P3 | Beacon System |
| 65 | Sub-Mission: Distress Signal | Ambiguous encounter; enemy trap or salvage | P3 | Open Space AI |
| 66 | Sub-Mission: Enemy Fortress | 5-phase destruction sequence | P3 | Open Space AI |
| 67 | Sub-Mission: Enemy Caravan | Destroy patrol + supply convoy | P3 | Open Space AI |
| 68 | Sub-Mission: Asteroid City Defense | Wave defense → unlock friendly ships | P4 | Open Space AI |
| 69 | Sub-Mission: Abandoned Station | Land-mission style inside derelict | P3 | Land Mission |
| 70 | Double Jump Upgrade | 2nd jump in air | P2 | Player Movement |
| 71 | Hover Upgrade | Hold jump to slow fall | P3 | Double Jump |

---

### NARRATIVE SYSTEMS

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 72 | Relationship Manager | Silent per-companion integer tracker | P2 | Save System |
| 73 | Companion NPC — ANCHOR | Sub-mission, dialogue, final mission role | P3 | Relationship System |
| 74 | Companion NPC — CIPHER | Sub-mission, dialogue, final mission role | P3 | Relationship System |
| 75 | Companion NPC — SPARK | Sub-mission, dialogue, final mission role | P4 | Relationship System |
| 76 | Final Mission — Point of No Return | Warning prompt; consequence state loaded | P2 | Relationship + Ship Upgrade |
| 77 | Companion Mini-Boss | Bad-relationship companion becomes boss | P3 | Relationship Manager |
| 78 | Ship Upgrade Consequence System | Under-upgraded ship triggers narrative events | P3 | Ship Upgrade State |
| 79 | True Ending Trigger | All beacons + all upgrades + all companion missions | P3 | All Systems |
| 80 | Post-Game Summary Screen | Completion %, companion outcome, true ending hint | P3 | Final Mission |

---

### UI / UX

| # | Feature | Description | Priority | Dependencies |
|---|---|---|---|---|
| 81 | Open Space HUD | Hull, Shield, Missiles, Minimap, Beacon proximity | P2 | Open Space |
| 82 | Assault HUD | Hull, Shield, Alert indicators, Missile count | P1 | Assault Mode |
| 83 | Land Mission HUD | HP, weapon slot, grenade count, modules, keys | P1 | Land Mission |
| 84 | Grenade Arc Preview | Real-time trajectory display while holding throw | P1 | Grenade System |
| 85 | Fragment Pickup UI | Progress display on fragment collection | P2 | Fragment System |
| 86 | Module Loadout UI | Open Space only; drag/select to equip | P2 | Module System |
| 87 | Minimap (Open Space) | Fog of war; beacons; objectives | P3 | Open Space |
| 88 | Colorblind Mode | Alternative visual coding for all color-dependent UI | P3 | All UI |
| 89 | Settings Menu | Controls, accessibility, audio | P2 | None |
| 90 | Pause Menu | Mode-appropriate options | P2 | All Modes |

---

## Suggested Sprint Order (Rough)

| Sprint | Focus |
|---|---|
| Sprint 1 | Features 1–8 (Land Mission core loop) |
| Sprint 2 | Features 9–13 (Open Space + Assault core) |
| Sprint 3 | Features 14–21, 81–84 (Progression + basic UI) |
| Sprint 4 | Features 44–55 (Enemy AI) |
| Sprint 5 | Features 22–43 (Module roster — P2 first) |
| Sprint 6 | Features 56–71 (World content) |
| Sprint 7 | Features 72–80 (Narrative systems) |
| Sprint 8 | Features 85–90 (UI polish) |
| Sprint 9 | Remaining P3 features + balancing |
| Sprint 10 | P4 features + final QA |
