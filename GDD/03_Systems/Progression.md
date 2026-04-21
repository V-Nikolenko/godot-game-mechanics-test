# VOID BREACH — Game Design Document
## 03 · Systems · Progression

---

### Core Principle
There is no economy. There are no shops. All progression comes from exploration and completion. Power is never sold — it is earned.

---

## Upgrade Categories

### Player Upgrades

| Upgrade | Type | Acquisition | Effect |
|---|---|---|---|
| Health Upgrade | Fragment (1/3 or 1/4 parts) | Land Mission secrets, boss drops | +1 Health Bar segment |
| Damage Booster | Whole item | Land Mission bosses, hidden rooms | +X% damage to all player weapons |
| Primary Weapon | Whole item | Boss drops, hidden rooms | New weapon unlocked for slot 1 |
| Module | Whole item | Hidden rooms, sub-mission rewards | New module available to equip |
| Temporary Health Booster | Consumable (in-mission only) | In-mission pickups | Exceed max HP for this run only |
| Temporary Speed Booster | Consumable (in-mission only) | In-mission pickups | Exceed max speed for this run only |

### Ship Upgrades

| Upgrade | Type | Acquisition | Effect |
|---|---|---|---|
| Shield Upgrade | Fragment (1/3 or 1/4 parts) | Open Space secrets, Fortress rewards | +1 Shield Bar segment |
| Ship Damage Booster | Whole item | Sub-mission rewards, Fortresses | +X% damage to all ship weapons |
| Ship Module (Open Space) | Whole item | Hidden in Open Space sectors | Unlocks: Reverse Thrust, Dash improvements, etc. |
| Ship Module (Assault) | Whole item | Assault completion bonus | Unlocks: new Assault abilities |

---

## Module System (Character)

Modules are the primary build identity system. The player equips up to **3 modules simultaneously** (upgradeable to 4–5 via extremely rare super-hidden upgrades).

### Module Slots
- 3 standard slots (unlocked from game start)
- 4th slot: hidden upgrade found in a specific, non-obvious location
- 5th slot: legendary-tier hidden upgrade — intended for completionists

**Equipping:** Modules are swapped in the Open Space hub between missions. Cannot be swapped during missions.

**Design philosophy:** "Even bad abilities/modules should have emergence to make them useful." No module should ever be strictly worse than another in all situations.

---

### Complete Module List

| # | Module Name | Effect | Playstyle |
|---|---|---|---|
| 1 | Default Dash | Short dash with invincibility frames | Baseline — everyone starts here |
| 2 | Heavy Armor | Reduced dash distance; greatly increased armor | Tank — survive, not dodge |
| 3 | Parry | Replace dash with a timed parry; deflects or stuns | Reactive — defensive skill expression |
| 4 | Blink | Instant teleport a short distance | Mobility — bypass barriers, extreme repositioning |
| 5 | Afterburner | Double dash without touching ground | Aerial — platforming specialist |
| 6 | Reactor Surge | Dashing through attacks restores small health/shield | Aggressive sustain — risk = reward |
| 7 | Magno-Boost | Dash briefly sticks to walls; wall-bouncing enabled | Vertical — opens secret routes |
| 8 | Pulse Strike | Dash deals direct damage to enemies hit | Offensive — dash into enemies intentionally |
| 9 | Phase Shift | Dash becomes teleport; pass through enemies and thin barriers | Extreme mobility — high ceiling |
| 10 | Counter Impact | Dashing through a projectile triggers a shockwave counterattack | Precision — rewarded perfect play |
| 11 | Magnetic Pull | Dash pulls nearby small enemies toward player | AOE setup — group enemies for explosives/melee |
| 12 | Pulse Step | Dash emits EMP pulse; disables enemy shields briefly | Tactical — hard counters shield units |
| 13 | Momentum Crash | Dash damage scales with pre-dash movement speed | Chain — maintain speed for power |
| 14 | Nanofiber Layer | After dash, gain 0.3s invincibility window | Forgiveness — survivability buffer |
| 15 | Emergency Overload | On lethal damage: auto-dash + shield burst; survive at 1 HP | Emergency — once-per-encounter lifesaver |
| 16 | Static Charge | Standing still charges dash for stronger stun/push | Setup — punishes aggressive players |
| 17 | Temporal Drift | After dash, brief bullet-time slowdown | Control — time manipulation |
| 18 | Vampiric Strike | Dealing damage restores small health | Sustain — melee focused |
| 19 | Volatile Armor | Taking damage causes small explosion near player | Deterrent — punishes enemies for close combat |
| 20 | Afterswing | After dash, projectile swing to damage enemies at range | Melee extender — hybrid range/melee |
| 21 | Body Shield | Grab light enemies; use as a temporary shield | Tactical — creative crowd control |
| 22 | Corpse Blast | After melee kill, push corpse; it explodes | Chain kill — AOE combo enabler |
| 23 | Plunge Strike | Plunge attack stuns + pushes enemies outward from player | Crowd control — AoE disruption; combos with Magnetic Pull |

### Intended Build Archetypes

| Build | Key Modules | Strategy |
|---|---|---|
| **Ghost** | Blink + Phase Shift + Temporal Drift | Never get hit; teleport through everything |
| **Tank** | Heavy Armor + Reactor Surge + Emergency Overload | Absorb everything; fight through damage |
| **Parry God** | Parry + Counter Impact + Nanofiber Layer | Perfect timing; deflect and punish |
| **Melee Brawler** | Vampiric Strike + Corpse Blast + Plunge Strike | Close in, kill fast, chain kills |
| **Crowd Controller** | Magnetic Pull + Plunge Strike + Pulse Step | Group enemies, disable, AOE punish |
| **Aerial Assassin** | Afterburner + Pulse Strike + Momentum Crash | Stay airborne, dash through enemies for speed damage |

---

## Progression Gate Map (Design Reference)

```
[Start]
  │
  ├── Sector A (Tutorial) ─── Radiation Shield ──→ Sector C
  │       └── Assault A ──→ Land Mission A (yields: 1x Module, 1x Health Fragment)
  │
  ├── Sector B ─── Ship Dash (Afterburner) ──→ Sector D
  │       └── Sub-Mission: Fortress B (yields: 1x Shield Fragment, 1x Ship Damage Booster)
  │
  ├── Sector C (unlocked by Radiation Shield)
  │       └── Assault C ──→ Land Mission C (yields: Explosive Rockets)
  │
  ├── Sector D (unlocked by Ship Dash)
  │       └── Assault D ──→ Land Mission D (yields: 1x Module, 1x Health Upgrade)
  │
  └── [Final Sector] — unlocked by completing all main Land Missions
          └── Point of No Return
```

*Note: Gate map above is schematic — exact layout TBD in Level Design phase.*

---

## Fast Travel System

**Space Navigation Beacons** enable fast travel between discovered sectors.

- All beacons start disabled (abandoned/damaged)
- Activating a beacon requires one of:
  - A short puzzle (power restoration)
  - A defense mission (hold the beacon against waves)
  - Collecting parts found in nearby exploration
- Once active, beacon appears on the map as a travel node
- Fast travel is instant (no loading screen intended)

**Design intent:** Activating beacons is a rewarding sub-activity, not a chore. The puzzle or defense challenge should feel appropriately sized for the beacon's location difficulty.

---

## Progression Rules
1. No power upgrade should be locked behind a skill check alone — exploration finds it; skill uses it.
2. Fragment upgrades (Health, Shield) should be distributed so the player never waits more than 2 missions for a completion.
3. The player should feel meaningfully stronger after every 1 hour of play.
4. No upgrade should be missable permanently — all can be found post-game.
