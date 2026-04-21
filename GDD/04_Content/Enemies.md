# VOID BREACH — Game Design Document
## 04 · Content · Enemies

---

### Enemy Design Philosophy
- Every enemy type has a **primary threat** and a **readable tell**
- Difficulty comes from combinations, not individual unit strength
- Enemies exist in specific contexts — not all enemies appear in all modes

---

## Open Space Enemies

### Standard Enemies

| Enemy | HP | Primary Attack | Special Behavior | Weak Point |
|---|---|---|---|---|
| **Turret** | Low | Burst fire (3 shots) | Fixed position; rotates; may have blind spot | Base mount |
| **Patrol Fighter** | Medium | Rapid plasma shots | Patrol → chase → retreat when low HP | Engines |
| **Heavy Fighter** | High | Slow heavy cannon | Slow, armored; leads shots | Cockpit |
| **Mine Layer** | Low | Deploys proximity mines | Flees when in combat; drops mines while fleeing | Direct hit |

### Sub-Mission Enemies

| Enemy | Context | Notes |
|---|---|---|
| **Fortress Turrets** | Enemy Fortress | Multiple covering different arcs; phase 1 target |
| **Fortress Defender Ships** | Enemy Fortress | Spawn from Runway; stop spawning after Runway destroyed |
| **Caravan Guard Ships** | Enemy Caravan | Escort formation; scatter when leader destroyed |
| **Colony Attackers** | Asteroid City defense | Wave-based; mixed fighters and heavies |

### Open Space Boss / Mini-Boss (TBD)
*To be designed once main sectors are mapped. Should involve multi-phase ship destruction, not just HP drain.*

---

## Assault Enemies

| Enemy | Attack Pattern | Alert Color | Notes |
|---|---|---|---|
| **Scout Fighter** | Straight shots | Yellow | Fast, low HP; comes in pairs |
| **Bomber** | Spread shot | Yellow | Slow; wide spread |
| **Cruiser** | Slow tracking missile | Yellow | High HP; persistent threat |
| **Sniper Satellite** | Instant beam after long charge | Red | Must dodge; cannot be destroyed |
| **Laser Platform** | Sweeping laser beam | Red | Moves laterally; timing window to pass |
| **Asteroid Belt** | Mixed field | Yellow (small) / Red (field edges) | Navigate the destructible rocks |
| **Meteor** | Large fast projectile | Yellow | Destroyable; debris scatters |
| **Mine Field** | Stationary proximity mines | Yellow | Shoot ahead or navigate carefully |

**Note:** All Assault enemies must be designed with the Alert system in mind first. Define Red vs Yellow designation before designing the attack.

---

## Land Mission Enemies

### Standard Enemies

| Enemy | HP | Primary Attack | Alert Range | Special |
|---|---|---|---|---|
| **Guard** | Medium | Ranged weapon | Medium sight + hearing | Uses cover; calls backup when alerted |
| **Heavy** | High | Slow charge attack | Wide sight | Unstoppable during charge; must dodge |
| **Shield Trooper** | Medium | Ranged (behind shield) | Medium sight | Frontal shield blocks; hit from side during attack |
| **Drone** | Low | Ranged from above | 360° sight | Flies; ignores ground cover |
| **Scavenger** | Low | Fast melee rush | Close sight | Comes in groups of 3–5; erratic movement |
| **Demolisher** | Medium | Grenade spam | Medium hearing | Flushes players from cover; weak to melee |
| **Commander** | Medium-High | Ranged + orders | Wide sight | Boosts nearby enemy stats; priority kill |
| **Turret (placed)** | Low-Medium | High damage fixed beam | Fixed direction | Destroyable; placed by level designers |

### Enemy Interactions with Player Systems

| Situation | Result |
|---|---|
| Enemy corpse on pressure plate | Plate activates |
| Magnetic Pull module used near Scavengers | Scavengers pulled into melee range |
| Corpse Blast module + melee kill | Corpse becomes AOE explosion on push |
| Plunge Strike on group | All enemies in radius stunned + pushed outward |
| Pulse Step dash near Shield Trooper | Shield disabled briefly — window to attack front |
| Body Shield module + light enemy | Enemy becomes temporary projectile blocker |

### Mini-Boss Enemies (Land Mission)

| Boss | HP | Primary Threat | Phase Gimmick |
|---|---|---|---|
| **Defense Mech** | High | Laser sweep + stomp | Phase 2: deploys Shield Troopers |
| **Elite Commander** | Medium | Heavy firepower + rally | Phase 2: reinforcements arrive |
| **Corrupted Turret Array** | High | Multi-directional laser grid | Requires destroying nodes in sequence |

### Final Mission — Companion Mini-Boss
See Characters.md. Unique enemy that adapts to player's equipped modules. Should feel like fighting a dark mirror.

---

### Boss Design Rules
1. All bosses must have at least 2 phases.
2. Phase transitions are triggered by HP thresholds (50% and 25% recommended).
3. Each phase introduces at least one new attack not seen in the previous phase.
4. Bosses do not regenerate health between phases.
5. Boss arenas must have enough space to fully use the player's equipped modules — no "unavoidable hit" zones.
6. After a boss is defeated, a narrative beat plays before the upgrade is awarded.

---

### Naming and Visual Conventions
- Open Space enemies: mechanical, angular, military-industrial aesthetic
- Assault enemies: designed to read clearly at high speeds — bold silhouettes, strong color coding
- Land Mission enemies: humanoid threats wear faction insignia; automatons have clearly mechanical silhouettes
- All enemies with shields should have a visual shield that clearly wraps around the protected area
