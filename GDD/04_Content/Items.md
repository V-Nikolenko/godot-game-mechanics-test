# VOID BREACH — Game Design Document
## 04 · Content · Items

---

## Item Philosophy
All items are found in the world. There are no drops from standard enemy kills. Items are placed by designers at specific locations — their scarcity and position communicate the game's pacing.

---

## Permanent Upgrades

### Player Permanent Upgrades

| Item | Type | Effect | Fragment? |
|---|---|---|---|
| Health Upgrade | Stat | +1 Health Bar segment | Yes — 3 or 4 fragments per upgrade |
| Damage Booster | Stat | +10–15% player weapon damage | No |
| Primary Weapon | Equipment | New weapon for weapon slot | No |
| Module | Equipment | New module available to equip | No |
| Grenade Capacity Upgrade | Stat | +2 grenade/mine slots | No |

### Ship Permanent Upgrades

| Item | Type | Effect | Fragment? |
|---|---|---|---|
| Shield Upgrade | Stat | +1 Shield Bar segment | Yes — 3 or 4 fragments per upgrade |
| Ship Damage Booster | Stat | +10–15% ship weapon damage | No |
| Ship Module (Open Space) | Equipment | Unlocks new Open Space ability | No |
| Ship Module (Assault) | Equipment | Unlocks new Assault ability | No |
| Missile Capacity Upgrade | Stat | +3 missile slots | No |

### Progression-Gating Upgrades (Ship)

These are treated as Ship Modules but have environmental unlock significance:

| Upgrade | Unlocks Access To |
|---|---|
| High-Chargeable Cannon | Heavy Ship Wreck obstacles |
| Explosive Rockets | Heavy Asteroid obstacles |
| Radiation Shield | Radiation Field zones |
| EMP Hardening | EMP Zone paths |
| Afterburner (Ship Dash) | Gravitational Anomaly zones |
| Manual Reverse Thrust | Tight tunnel sub-missions |

---

## Player Weapons (Slot 1)

| Weapon | Range | Rate | Damage Profile | Notes |
|---|---|---|---|---|
| **Blaster** (starter) | Medium | Fast | Low per-shot, good DPS | Always available; never lost |
| **Scatter Shot** | Short | Medium | Medium spread | Best vs clusters of weak enemies |
| **Plasma Rifle** | Long | Slow | High single-target | Best vs armored single targets |
| **Grenade Launcher** | Medium arc | Slow | AOE on impact | Bounces off walls; dangerous in tight spaces |
| **TBD** | — | — | — | Late game weapons; TBD in content pass |

**Design rule:** Each weapon should have a situation where it is clearly the best tool. No weapon should feel strictly inferior to the Blaster at all ranges.

---

## Grenades and Mines (Slot 2)

| Item | Behavior | Best Use |
|---|---|---|
| **Frag Grenade** | Thrown arc; explodes on impact or timer | Groups of enemies; flushing cover |
| **EMP Grenade** | Short-range pulse on detonation | Shield Troopers; Drone disabling; activating circuits |
| **Proximity Mine** | Placed at feet; triggered by enemy proximity | Defensive setups; chokepoints |
| **Cluster Grenade** | Splits into 3 on impact | Wide area coverage; less concentrated damage |

*Additional types can be added as mission rewards.*

---

## Consumable Pickups (In-Mission Only)

These items do not persist between missions. They can only be found during active missions.

| Item | Effect | Duration / Limit |
|---|---|---|
| Temporary Health Booster | Exceeds current max HP | Lasts until HP is lost down to max |
| Temporary Speed Booster | Exceeds current max speed | Lasts until end of current room or timer (~60s) |
| Ammo Pack | Refills all grenade/mine inventory | Instant |
| Repair Kit (in-mission) | Restores small amount of ship hull HP | Only available in Assault waypoints |

---

## Keys

Keys are a special persistent item type:

- Found in Land Missions
- Displayed in HUD (key icon + count)
- Can be carried across missions (they do not disappear when a mission ends)
- Used to open locked doors in current or future missions
- Multiple key types may exist (color-coded to their lock)

**Design rule:** A key and its lock should always be in the same mission OR the key should be clearly labeled for another mission. Never create a key without a corresponding lock.

---

## Item Discovery Design Rules
1. Every hidden room should contain something worth finding — never an empty room after breaking a cracked wall.
2. Fragment items should visually communicate how many pieces are collected vs total (e.g., "2/4" displayed on pickup).
3. All weapons and modules found for the first time should auto-equip (with confirmation prompt) to ensure players actually try them.
4. Permanent upgrades glow or have distinct particle effects to distinguish them from consumables.
5. Consumable pickups should be visually smaller/simpler than permanent upgrades — size communicates value.
