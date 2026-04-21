# VOID BREACH — Game Design Document
## 03 · Systems · Movement

---

### Design Intent
Movement is the primary skill expression in every mode. It should feel satisfying to execute correctly and punishing to execute poorly — but never arbitrary.

---

## Open Space Movement

### Physics Model
- **Inertia-based:** Ship maintains velocity; thrust changes velocity, not position directly
- **Gravity drift:** Subtle constant pull in certain sectors; not strong enough to trap players
- **No friction** in deep space; friction applies near celestial bodies

### Actions

| Action | Description | Upgrade Dependency |
|---|---|---|
| **Thrust** | Accelerate in facing direction | None |
| **Strafe** | Instantaneous lateral velocity shift | None |
| **Dash (Forward)** | Speed burst forward; brief cooldown | None (upgradeable distance/cooldown) |
| **Reverse Thrust** | Decelerate or push backward | Unlocked via upgrade |
| **Rotation** | Free 360° facing | None |

### Upgrade-Gated Movement
Certain areas require specific movement capabilities unlocked by ship upgrades:

| Required Capability | Upgrade Name | Blocks Access To |
|---|---|---|
| High-speed forward dash | Afterburner Module | Gravitational Anomaly zones |
| Reverse thrust | Manual Reverse Thrust | Tight tunnel sub-missions |
| None (weapon-gated) | High-Chargeable Cannon | Heavy Ship Wreck paths |
| None (weapon-gated) | Explosive Rockets | Heavy Asteroid paths |
| Passive (shield-gated) | Radiation Shield | Radiation Field zones |
| Passive (system-gated) | EMP Hardening | EMP Zone paths |

### Obstacles (Environmental)
| Obstacle | Behavior | Interaction |
|---|---|---|
| Small Asteroids | Stationary or slowly drifting | Shoot to destroy; navigate around |
| Small Ship Wrecks | Stationary debris | Navigate around; some destructible |
| Energy Doors | Temporary — block until generator destroyed | Find and destroy linked generator |
| Metal Doors | Permanent until destroyed | Shoot to destroy |
| Mines | Explode on collision; chain-react | Shoot at range to trigger safely |
| Static Laser Grids | Fixed timing pattern | Memorize pattern, pass in window |
| Heavy Ship Wrecks | Indestructible without upgrade | Require High-Chargeable Cannon |
| Heavy Asteroids | Indestructible without upgrade | Require Explosive Rockets |
| Radiation Fields | Damage-over-time zone | Require Radiation Shield |
| EMP Zones | Disable ship systems temporarily | Require EMP Hardening |
| Gravitational Anomalies | Pull ship off course; can trap | Require Dash (Afterburner) |

---

## Assault Movement

### Physics Model
- **Arcade responsive:** No inertia. Position snaps to input immediately.
- Ship stays within screen bounds (scrolling viewport)
- Scroll speed is constant; varies by section

### Actions

| Action | Description |
|---|---|
| **Move** | Full 2D movement within scroll bounds |
| **Strafe** | Same as move; no distinction in this mode |
| **Dash** | Burst dash left/right; brief invincibility; cooldown |

### Key Behavior
- Dash has **invincibility frames** during the burst — intentional. Players should use dash offensively to phase through bullets.
- Staying still is punished by obstacle density — the level is designed to force movement.
- Screen edges are lethal (ship flies out of bounds = hull damage).

---

## Land Mission Movement

### Physics Model
- **Standard platformer physics:** gravity, jump arc, fall speed cap
- **Coyote time:** ~5 frames of jump grace after walking off ledge
- **Jump buffering:** ~8 frames of pre-input buffering for jump

### Actions

| Action | Description | Upgrade Dependency |
|---|---|---|
| **Run** | Horizontal movement | None |
| **Jump** | Standard jump arc | None |
| **Double Jump** | Second jump in air | Upgrade (Double Jump Module) |
| **Hover** | Hold jump on second press; slow fall | Upgrade (Hover Module) |
| **Dash** | Behavior depends on equipped Dash Module | Module-dependent |
| **Crouch** | (TBD — possible for low passages) | None |

### Dash Module Movement Interactions

Dash is the core movement tool in Land Missions. The equipped module completely changes how the player traverses space:

| Module | Movement Implication |
|---|---|
| Default Dash | Short burst; clears standard gaps |
| Blink Module | Instant teleport — bypasses walls/enemies |
| Afterburner Module | Double-dash in air — extreme aerial range |
| Magno-Boost Module | Stick to and bounce off walls — vertical exploration |
| Phase Shift Module | Pass through solid objects briefly |
| Heavy Armor Module | Dash distance reduced — areas feel tighter |

**Design rule:** Map design must be playtestable with the Default Dash Module. Other modules create shortcuts, not requirements.

### Exploration Movement Gates (Land Mission)

| Gate Type | Solution |
|---|---|
| Cracked walls | Shoot or melee to reveal hidden room |
| Cracked floors | Drop through; or shoot to reveal lower path |
| Pressure plates | Stand on them OR place an enemy corpse |
| Key-locked doors | Find key in this mission or carry from previous |
| Dash-only passages | Gap that requires a dash to cross |
| Circuit puzzles | Environmental puzzle — restore power sequence |

**Key persistence:** Keys found in one mission can be carried to future missions. The player's key inventory is visible in the HUD.

---

### Movement Feel Targets
- **Open Space:** Like flying a real spacecraft — deliberate, inertia-driven, satisfying to master.
- **Assault:** Snappy and precise — like a classic shoot-em-up, zero input lag tolerance.
- **Land Mission:** Fluid and readable — every movement option should be clearly communicable to new players within 2 minutes of play.
