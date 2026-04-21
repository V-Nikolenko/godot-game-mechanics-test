# VOID BREACH — Game Design Document
## 01 · Core Gameplay

---

### Three Modes, One Game

VOID BREACH is built from three distinct gameplay modes that each operate with their own rules, camera, and control scheme — but share the same character, upgrades, and narrative state.

| Mode | View | Pace | Purpose |
|---|---|---|---|
| **Open Space** | Free 360° top-down / isometric flight | Exploration | Hub world, secrets, sub-missions |
| **Assault** | Vertical scrolling shoot-em-up | Fast / reactive | Mandatory gate before Land Missions |
| **Land Mission** | 2D side-scrolling platformer | Tactical | Primary content — combat, puzzles, bosses |

Modes are **not optional** — Assault must be cleared to unlock its corresponding Land Mission. Open Space is always accessible between missions.

---

### Mode 1 — Open Space

**Camera:** Top-down or loose isometric, free rotation
**Control feel:** Inertia-based flight with gentle gravity drift. Not arcade-snap.

#### Core Actions
- **Thrust** — accelerate in facing direction
- **Strafe** — sideways burn, instant velocity shift
- **Dash (Forward)** — speed burst; required for gravitational obstacles; has cooldown
- **Reverse Thrust** (upgrade) — decelerate or back-burn
- **Fire** — primary weapon (configurable)
- **Missile** — auto-targeting explosive; limited ammo
- **Charged Laser** — hold to charge, releases high-damage beam

#### Interaction
- Approach objects to trigger context actions (activate beacon, collect upgrade, enter sub-mission)
- Enemy bases auto-aggro at range
- Mines chain-react; use this deliberately

---

### Mode 2 — Assault

**Camera:** Vertical scrolling, fixed perspective (ship moves, background scrolls)
**Control feel:** Tight, responsive, shoot-em-up precision

#### Core Actions
- **Move** — full 2D movement within scroll bounds
- **Strafe** — same as Open Space; lateral burst dodge
- **Fire** — continuous primary fire
- **Missile** — limited use
- **Charged Laser** — charged beam attack

#### Alert System
The game communicates incoming threats via a two-color visual alert:

| Alert Color | Meaning | Player Response |
|---|---|---|
| **Red** | Obstacle/projectile is indestructible | Dodge only |
| **Yellow** | Obstacle/projectile can be destroyed | Shoot or dodge |

Alerts appear on-screen with directional indicators before the threat enters visible range. This is the game's primary difficulty communication tool — players learn the grammar quickly.

#### Obstacles
- Incoming Laser Shots (single, Yellow)
- Giant Laser Beams (sweeping, Red)
- Meteors (Yellow — can be destroyed, debris scatters)
- Asteroid Belts (mixed — some Yellow, field edges Red)
- Enemy ships (standard combat)

#### Completion
Assault ends when the player reaches the planet/target. Failure returns to Open Space — no permadeath. Players keep any ship HP lost from Open Space encounters.

---

### Mode 3 — Land Mission

**Camera:** 2D side-scrolling
**Control feel:** Responsive platformer with combat emphasis — Hollow Knight / Dead Cells speed

#### Core Actions
- **Move / Run**
- **Jump** (double jump available via upgrade)
- **Hover** (hold jump on second press — upgrade)
- **Dash** — core mobility; behavior shaped by equipped module
- **Primary Weapon** — ranged, 1 active slot
- **Grenades / Mines** — slot 2; short-press = near throw, long-press = far throw; trajectory preview shown
- **Melee** — slot 3; baseline pushes + small damage; upgraded by modules into primary tool

#### Exploration Interactions
- Breakable walls (cracked texture = secret room)
- Pressure plates (requires weight — enemy corpses are valid)
- Key-locked doors (keys found in this mission or previous ones — keys are persistent)
- Circuit puzzles (environmental — restore power to open paths)
- Dash-only passages (gap too small to walk through)

---

### Mode Transitions

```
Open Space
    └── Player approaches mission entry point
            └── [Assault starts]
                    └── Assault cleared
                            └── [Land Mission starts]
                                    └── Land Mission complete
                                            └── Return to Open Space
```

If Assault is failed, the player returns to Open Space with no Land Mission access until Assault is re-attempted and cleared.

If Land Mission is abandoned mid-way, the player returns to Open Space. Re-entering costs another Assault run (by design — each attempt is a breach attempt).

---

### Difficulty Philosophy

- No lives system. No permadeath.
- Failure returns to last safe Open Space position.
- Power comes from found upgrades + equipped modules, not grinding.
- The game should feel harder at the start and gradually open up as the player finds their build.
- The final mission difficulty is directly tied to ship upgrade state — under-upgraded ships create narrative consequences (see Characters.md).
