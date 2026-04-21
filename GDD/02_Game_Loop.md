# VOID BREACH — Game Design Document
## 02 · Game Loop

---

### Macro Loop

```
┌─────────────────────────────────────────────────────────┐
│                    OPEN SPACE HUB                       │
│  Explore → Find Upgrade → Unlock New Area → Repeat      │
│  ↓                                                      │
│  Encounter Sub-Mission → Complete → Reward              │
│  ↓                                                      │
│  Find Mission Entry → Run Assault → Clear               │
│  ↓                                                      │
│  Run Land Mission → Complete Objective                  │
│  ↓                                                      │
│  Return to Open Space (now with new upgrades)           │
└─────────────────────────────────────────────────────────┘
```

The core tension is always: **"What can I reach now, and what do I need to reach later?"**

---

### Session Loop (typical 60-90 min session)

1. **Orientation** — Player re-enters Open Space, identifies new reachable areas since last session.
2. **Exploration** — Navigate, fight patrols, find 1–2 upgrade fragments or a new module.
3. **Sub-Mission** — Tackle an optional sub-mission for additional rewards or narrative.
4. **Assault Run** — Attempt a new or previously blocked assault mission.
5. **Land Mission** — Complete objectives, find secrets, collect upgrade pieces.
6. **Reflection** — Return to Open Space; equip new modules, update loadout.

Each session should feel complete — players should always leave with at least one new thing.

---

### Upgrade Loop

Upgrades are found in fragments (partial items) or whole:

| Upgrade Type | Fragment System | Found In |
|---|---|---|
| Player Health | 1/3 or 1/4 parts = 1 upgrade | Land Missions, secrets |
| Ship Shield | 1/3 or 1/4 parts = 1 upgrade | Open Space secrets, Fortresses |
| Player Modules | Whole item | Land Missions (hidden rooms), sub-missions |
| Ship Modules | Whole item | Open Space secrets, Assault rewards |
| Player Damage Boosters | Whole item | Land Missions, bosses |
| Ship Damage Boosters | Whole item | Sub-missions, Fortresses |
| Primary Weapons (Player) | Whole item | Land Mission bosses, hidden areas |
| Temporary Health Booster | Consumed on pickup | In-mission only — does not persist |
| Temporary Speed Booster | Consumed on pickup | In-mission only — does not persist |

**Temporary boosters** allow players to exceed their current max HP or speed ceiling during a mission run, meaningfully increasing moment-to-moment survival chances without breaking long-term balance.

---

### Progression Gating (Metroidvania Layer)

Open Space sectors are blocked by obstacles that require specific upgrades to pass. This creates natural exploration order without a mandatory linear path.

| Obstacle | Required Upgrade | Where Upgrade Is Found |
|---|---|---|
| Heavy Ship Wrecks | High-Chargeable Cannon | (TBD — late game Land Mission) |
| Heavy Asteroids | Explosive Rockets | (TBD — mid game assault reward) |
| Radiation Fields | Radiation Shield | (TBD — early fortress sub-mission) |
| EMP Zones | EMP Hardening | (TBD — specific Land Mission) |
| Gravitational Anomalies | Ship Dash (Afterburner) | (TBD — early open space secret) |

**Design rule:** The first time a player encounters a gate, the upgrade that unlocks it should be findable within 1–2 sessions of normal play in adjacent areas.

---

### Narrative Loop

Narrative beats are triggered by:
- Reaching certain upgrade thresholds (ship quality)
- Completing specific sub-missions tied to companion characters
- Entering the final mission

**Three outcome states for the final mission:**

| State | Condition | Outcome |
|---|---|---|
| **Optimal** | Ship fully/well upgraded + good companion relationship | Companion assists; all survive |
| **Partial** | Ship somewhat upgraded OR neutral relationship | Companion assists but may not survive |
| **Bad Ending** | Ship poorly upgraded AND bad relationship | Companion becomes mini-boss; hardest final mission |

The game signals none of this directly — players discover it organically.

---

### Post-Game Loop

After completing the final mission:
- Open Space remains fully accessible
- All previously locked areas can now be explored
- True ending is unlocked by finding all major upgrades + restoring all beacons
- No new enemies — but some areas only become navigable with fully-upgraded ship

The post-game is about **completion and narrative closure**, not new challenge.

---

### Pacing Guidelines

| Zone | Typical Upgrade Density | Difficulty |
|---|---|---|
| Starting Sector | High — onboarding | Low |
| Mid Sectors | Medium | Medium |
| Late Sectors | Low — must work for it | High |
| Final Mission Area | None — point of no return | Climactic |

**Rule:** Players should never feel stuck for more than 10 minutes without finding something. If they are, a beacon or hint system should nudge exploration direction (not waypoints — environmental storytelling only).
