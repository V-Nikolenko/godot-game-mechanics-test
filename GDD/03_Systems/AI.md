# VOID BREACH — Game Design Document
## 03 · Systems · AI

---

### AI Design Philosophy
Enemies should feel purposeful, not mechanical. Each enemy type communicates its behavior through visual design — players should be able to predict what an enemy will do before it does it.

**Rules:**
1. No enemy should one-shot a player with a telegraphed attack (only surprise/unfair-feeling hits).
2. Enemy difficulty should come from combination and positioning, not individual unit stats.
3. All enemy attacks must have a readable windup animation or audio cue.

---

## Open Space Enemy AI

### Default Enemies

#### Turrets (Stationary)
- **Detection:** 360° sensor, range-limited
- **Behavior:** Rotate toward player → charge shot → fire
- **Attack pattern:** Burst fire (3 shots), brief pause, repeat
- **Special:** Some turrets have blind spots (rotating only left/right or covering fixed arc)
- **Destroyed:** Explodes; debris can damage nearby enemies

#### Patrol Ships
- **States:** Patrol → Alerted → Chase → Attack → Retreat
- **Patrol:** Follow preset waypoints; slow speed
- **Alert:** Triggered by proximity or sight line; plays audio cue
- **Chase:** Accelerate toward player; formation with nearby ships
- **Attack:** Fire while maneuvering; break formation for flanking attempts
- **Retreat:** When HP < 20%; will attempt to reach a Fortress or rally point; if it reaches rally point, HP partially restores

### Mini-Boss: Fortress Defense Sequence
The Fortress is destroyed in a structured multi-step sequence — not a single HP pool.

**Phase order:**
1. **Turret Defense Line** — destroy outer turrets protecting the fortress
2. **Distress Signal Antenna** — destroy to prevent enemy ship reinforcements
3. **Enemy Ship Runway** — destroy to stop new ship spawning
4. **Mini-Boss Ship** — dedicated combat encounter; unique attack patterns
5. **'Call Alias Beacon' Defense** — player defends their own beacon while it transmits; wave-based

**Fortress behavior during sequence:**
- Continuously spawns patrol ships until Antenna is destroyed
- Increases turret fire rate as more components are destroyed
- Mini-Boss enters combat at Phase 4 regardless of player's approach order for Phases 1–3

**Design note:** Players can attempt Phases 1–3 in any order. This rewards tactical thinking and allows different play styles (destroy Antenna first to prevent reinforcements vs clear turrets first for safety).

### Enemy Distress Signal
- Triggered by patrol ships that escape at low HP
- If not intercepted within ~60 seconds, spawns a reinforcement wave
- Wave size depends on how many ships successfully escaped
- Creates time pressure without hard failure state

---

## Assault Enemy AI

Assault enemies operate on fixed scripts with procedural variation within their pattern type. They are NOT reactive to player position in a complex sense — the difficulty is the pattern density.

### Pattern Types

| Type | Description |
|---|---|
| **Straight Shot** | Single projectile fired directly downward |
| **Spread Shot** | 3–5 projectiles in a spread pattern |
| **Tracking Shot** | Slow projectile that curves toward player position at time of fire |
| **Formation Flight** | Group of enemies in formation; maintain relative positions |
| **Kamikaze** | Ship accelerates directly toward player; destroys on contact |
| **Shield Bearer** | Enemy with frontal shield; must be flanked or hit from behind |
| **Sniper** | Long pause then very fast single projectile; Red alert issued |

**Alert rules:**
- Any attack the player **cannot** destroy = Red Alert
- Any attack the player **can** destroy = Yellow Alert
- Alerts appear 1–2 seconds before the threat reaches visible screen area

---

## Land Mission Enemy AI

### States (all humanoid-type enemies)

```
Idle → Patrol → Alert → Chase → Combat → Stunned → Dead
```

| State | Trigger | Behavior |
|---|---|---|
| **Idle** | Default | Stand/sit; minimal animation |
| **Patrol** | Assigned waypoints | Walk between points; look around at ends |
| **Alert** | Noise, partial sight | Stop, scan; if confirmed → Chase |
| **Chase** | Full sight / combat detection | Rush toward player; call for nearby enemies |
| **Combat** | In range | Attack with weapon/ability; use cover |
| **Stunned** | Parry, Plunge Attack, EMP | Briefly unable to act; takes bonus damage |
| **Dead** | HP = 0 | Ragdoll; corpse persists; interactable |

### Sight and Hearing
- **Sight cone:** ~120° forward facing; blocked by walls and obstacles
- **Hearing radius:** Triggered by gunshots, running, explosions (not by walking)
- **Alert propagation:** Alerted enemy calls nearby enemies within 15m radius; they enter Alert state immediately

### Enemy Types (Land Mission)

| Type | Primary Threat | Special Behavior |
|---|---|---|
| **Guard** | Ranged weapon | Patrols; uses cover; calls for backup |
| **Heavy** | Slow melee charge | High HP; breaks cover; unstoppable during charge |
| **Drone** | Flies; ranged | Cannot be blocked by ground cover; limited HP |
| **Shield Trooper** | Frontal block | Must be flanked or hit while attacking (shield drops briefly) |
| **Turret (placed)** | Fixed direction | Stationary; high damage; destroyable |
| **Scavenger** | Fast melee rush | Low HP; moves unpredictably; comes in groups |
| **Demolisher** | Grenade spam | Flushes players from cover; low melee ability |
| **Commander** | Ranged + buffs nearby | Boosts nearby enemy damage/awareness; priority target |

### Companion AI (Hostile — Bad Relationship)
If the player has a **bad relationship** with the companion NPC and reaches the final mission, the companion becomes a mini-boss.

**Companion mini-boss behavior:**
- Knows the player's loadout — will prioritize countering the player's primary damage source
- Has a health bar; when depleted, companion retreats (does not die — narrative beat)
- Uses the same dash system as the player — creating a mirror-match feel

---

## AI Design Rules
1. Enemies should never feel cheap — deaths from enemy AI should feel like the player's fault.
2. Heavy enemies must have clear audio/visual charge animation (minimum 0.8 second windup).
3. Group encounters should never start with more than 3 enemies in melee range simultaneously.
4. Companion mini-boss should have distinct music, slightly different color palette, and voiced lines.
