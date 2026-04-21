# VOID BREACH — Game Design Document
## 04 · Content · Levels

---

## Level Structure Overview

```
Open Space (Hub)
├── Sector A — Tutorial / Starting Zone
├── Sector B — Mid-game
├── Sector C — Mid-game (gate: Radiation Shield)
├── Sector D — Late-game (gate: Ship Dash)
├── Sector E — Late-game (TBD)
└── Final Sector — Point of No Return
```

Each sector contains:
- Open Space navigable area (flight)
- Optional sub-missions
- 1–2 hidden secrets (upgrades)
- 1 main Assault + Land Mission pair
- Fast Travel Beacon (starts disabled)

---

## Open Space — World Design

### Sector Layout Principles
- Each sector is visually distinct — color palette, asteroid type, wreck style
- Sectors connect through gated or open pathways
- Dead ends always have something in them — never a dead end for nothing
- The player should be able to see things they cannot reach yet (future motivation)

### Sector Content Template

| Element | Count per Sector | Notes |
|---|---|---|
| Fast Travel Beacon | 1 | Disabled at start; requires activation |
| Sub-Missions | 1–3 | At least 1 mandatory for story, rest optional |
| Open Space Secrets | 1–2 | Behind obstacles or in hidden nooks |
| Enemy Patrols | 2–4 groups | Scale with sector difficulty |
| Upgrade Fragments | 0–1 | Spread across full game; not every sector |

### Sub-Mission Types

| Sub-Mission | Description | Reward Type |
|---|---|---|
| **Distress Signal** | Ambiguous: could be trap or salvage. Player investigates. | Upgrade fragment or enemy ambush |
| **Enemy Fortress** | Destroy fortress in 4-step sequence | Ship Damage Booster, Shield Fragment |
| **Enemy Caravan** | Destroy patrol + supply convoy | Ammo, possible module |
| **Asteroid City Defense** | Defend colony from waves → unlocks friendly ships in zone | Narrative + zone benefit |
| **Abandoned Station/Ship** | Land mission gameplay inside derelict — puzzles + scavengers | Module, weapon, or upgrade |
| **Labyrinth Run** | Navigate a massive asteroid or destroyed flagship by ship | Ship Module, rare upgrade |

### Beacon Activation Types

| Activation Type | Description |
|---|---|
| **Power Puzzle** | Restore power to beacon by connecting circuit elements |
| **Defense Mission** | Hold beacon against enemy waves for 60–90 seconds |
| **Salvage Mission** | Find 2–3 beacon parts scattered in surrounding area |

---

## Assault Missions — Level Design

### Structure
- Each Assault is a single scrolling run, 3–7 minutes
- Divided into distinct sections (waves, obstacle gauntlets, open stretches)
- Ends with entry animation into the planet/target

### Assault Level Template

| Section | Purpose | Length |
|---|---|---|
| Opening — Clear | Low density; teach this mission's obstacle types | 30–45s |
| First Wave | Standard enemies; introduce formation patterns | 60–90s |
| Obstacle Gauntlet | Pure navigation challenge; alert system prominent | 45–60s |
| Mid-section | Mixed enemies + obstacles | 90–120s |
| Final Push | Highest density; boss encounter (optional per mission) | 60–90s |
| Landing Sequence | Scripted arrival; no combat | 10–15s |

### Assault Design Rules
1. First encounter of every new obstacle type should be shown in isolation (no other threats simultaneously).
2. Red Alert obstacles must appear 2+ seconds before they're on screen.
3. Player should never face more than 2 Red Alert threats simultaneously.
4. Missions should be completable with base ship (no upgrades) — upgrades reduce difficulty, not enable completion.

---

## Land Missions — Level Design

### Structure
- Non-linear within a mission (multiple routes, branching paths)
- Main objective is always clear (on HUD); secret objectives are discovered
- Checkpoint system: implicit (key rooms + sub-boss rooms)

### Land Mission Layout Template

| Zone | Purpose | Design Focus |
|---|---|---|
| Entry Area | Establish visual theme; introduce enemy types | Combat encounter |
| Exploration Zone 1 | Main path + first branch | Secrets, key item |
| Mid-section | Sub-boss or puzzle gate | Challenge spike |
| Exploration Zone 2 | Optional area (new upgrade behind cracked wall, etc.) | Secrets |
| Boss Arena | Main mission objective | Boss fight + cutscene |
| Exit | Clear path back | Possibly shortcut |

### Secret Rooms and Hidden Exploration

All secrets in Land Missions use visual tells — never invisible walls or arbitrary.

| Secret Type | Visual Tell | Solution |
|---|---|---|
| Cracked Wall | Visible crack pattern on wall texture | Shoot or melee |
| Cracked Floor | Crack pattern on floor | Drop through or shoot |
| Pressure Plate Room | Plate visible, nothing on it | Place corpse or player weight |
| Key-Locked Door | Colored lock icon on door | Find matching key |
| Dash-Only Passage | Gap too wide to jump normally | Dash across |
| Circuit Puzzle | Powered-off terminals, visible conduits | Trace and restore connections |
| Hidden Route | Tight space behind destructible object | Shoot object, enter |

### Mission Variety Targets
- Each Land Mission should have a unique mechanical focus beyond combat (puzzle, traversal, stealth section, etc.)
- No two consecutive missions should share the same primary gimmick
- At least 1 mission should heavily reward a melee-focused build
- At least 1 mission should favor ranged/stealth approach

---

## Final Mission Level Design

### Requirements
- No new upgrades available — player brings what they have
- Must account for all three ship upgrade states (full / partial / under-equipped)
- Companion's role changes the fight flow (see Characters.md)
- Should feel like the convergence of all three gameplay modes:
  - Opening: Assault sequence (breaching final defenses)
  - Entry: Ship crash / landing sequence (narrative beat)
  - Core: Land Mission (infiltration of final target)
  - Climax: Boss fight + narrative resolution

### Post-Final Mission (True Ending Path)
- All Open Space remains accessible
- New areas of the final sector become explorable
- True ending cutscene triggers when: all beacons active + all major upgrades collected + all companion missions complete
