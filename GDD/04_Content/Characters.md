# VOID BREACH — Game Design Document
## 04 · Content · Characters

---

## The Player Character

**Role:** Special operative. The player's avatar.
**Background:** TBD (narrative team) — should feel competent but not invincible. A soldier, not a superhero.

### Equipment Overview
| Slot | Category | Notes |
|---|---|---|
| Slot 1 | Primary Weapon | 1 active weapon; swapped by finding new ones |
| Slot 2 | Grenades / Mines | Short press = near, long press = far; trajectory preview |
| Slot 3 | Melee Weapon | Baseline: push + minor damage; upgraded via modules |
| Module Slots (3) | Modules | Up to 3 active; swapped in Open Space only |

The player character has no visible personality in gameplay — narrative is communicated through NPC dialogue and environmental storytelling.

---

## NPC Companions

### Design Overview
Companion NPCs are encountered through specific sub-missions in Open Space. Each has:
- A unique mission tied to them (optional — player can ignore it)
- A **relationship track** — silently modified by player choices
- A **final mission role** — determined by relationship state at the point of no return

There is **no visible relationship meter.** Consequences emerge through how characters speak to the player and what happens in the final mission.

### Relationship Modifiers (examples)

| Player Action | Relationship Effect |
|---|---|
| Complete companion's personal sub-mission | Positive |
| Abandon companion's mission mid-way | Negative |
| Save companion from danger in Open Space | Positive |
| Ignore distress signal from companion's zone | Negative |
| Destroy companion's preferred area/resource | Negative |
| Choose dialogue option that respects companion's view | Positive |

### Final Mission Outcomes by Relationship State

| Relationship | Companion Role | Narrative |
|---|---|---|
| **Good** | Allied gunner | Companion survives on ship wreck, mans turret, provides fire support |
| **Neutral** | Reluctant assist | Companion helps but gets injured; bittersweet outcome |
| **Bad** | Mini-boss | Companion confronts player; becomes combat encounter |

**Key narrative beat:** In the Bad ending path, even after defeating the companion as a mini-boss, they do not die — they retreat. The game does not reward killing allies, even difficult ones.

---

### Companion Roster (Placeholder — to be named by narrative team)

| Codename | Role | Personal Mission Type | Final Mission Role |
|---|---|---|---|
| ANCHOR | Military veteran, ship gunner | Defend their outpost in Open Space | Turret operator |
| CIPHER | Engineer / hacker | Retrieve data from an Abandoned Station | Opens locked route in final mission |
| SPARK | Pilot / scout | Escort their damaged ship through hostile sector | Distraction run; draws enemy fire |

*At least 1 companion should be available; 2–3 is target for shipped game.*

---

## Narrative: The Final Mission

### Setup
The final mission is reached by completing all required main Land Missions. It is a **point of no return** — a prompt warns the player before proceeding.

### Consequences of Ship Upgrade State

| Ship Upgrade Level | Result |
|---|---|
| **Fully upgraded** | Ship takes hits but holds; full crew survives into mission |
| **Partially upgraded** | Ship is badly damaged; some crew must evacuate early |
| **Under-upgraded** | Ship is shot down before landing; some crew die in the crash |

**The player can complete the game regardless of upgrade state.** Lower upgrade = harder final mission, not a locked-out ending.

### Post-Game
After completing the final mission:
- All of Open Space remains accessible
- True Ending: Restore all beacons + collect all major upgrades + complete all companion missions → Triggers final cutscene/epilogue
- The player is told this via a post-mission screen — not during gameplay

---

## Character Design Rules
1. The player character should have no dialogue lines during missions — expression through action only.
2. Companions should feel like real people with stakes, not mission dispensers.
3. The bad-relationship path should feel tragic, not punishing. Players should feel regret, not frustration.
4. Companion death should never happen as a direct result of player action — only as narrative consequence of neglect.
