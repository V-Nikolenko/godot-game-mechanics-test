# VOID BREACH — Game Design Document
## 03 · Systems · Economy

---

### There Is No Economy

This is intentional and foundational. VOID BREACH has:
- No currency
- No shops
- No trading
- No crafting
- No resource management (except limited ammo)

This is a **core design pillar**, not a feature gap.

---

### Why No Economy

Standard game economies (buy, sell, upgrade for gold) create:
- Grind loops that extend playtime artificially
- Players feeling "not ready" to progress
- Tension between exploring for fun vs. farming for stats

VOID BREACH replaces economy with **exploration as the sole progression driver.** Every powerful item is a reward for going somewhere dangerous or clever — not for grinding enemies or saving currency.

---

### What Replaces Economy

| Economic Concept | VOID BREACH Equivalent |
|---|---|
| Buying upgrades | Finding upgrades in the world |
| Spending currency on power | Completing challenges for power |
| Shop refreshes / rerolls | Revisiting sectors with new abilities |
| Resource management | Limited grenade/mine inventory |
| Crafting | No equivalent — items are found whole or in fragments |

---

### Limited Resource: Ammunition

The only managed resource in the game is **special ammo** (grenades, mines, missiles).

| Resource | Capacity | Refill Source |
|---|---|---|
| Grenades / Mines | 3–6 (capacity upgradeable) | Ammo caches in Land Missions |
| Ship Missiles | 5–10 (capacity upgradeable) | Navigation Beacons, destroyed enemy ships |

**Primary weapons (both ship and character) have infinite ammo.** Running out of special ammo is inconvenient, not punishing.

---

### Consumable Pickups (In-Mission Only)

These pickups exist only within missions and do not persist to Open Space:

| Pickup | Effect | Design Purpose |
|---|---|---|
| Temporary Health Booster | Exceeds max HP temporarily | Increases survival odds in tense sections |
| Temporary Speed Booster | Exceeds max speed temporarily | Enables faster clears or bypassing threats |
| Ammo Pack | Refills grenade/mine inventory | Ensures players are not permanently stuck without grenades |

Consumable pickups **never carry between missions.** This prevents hoarding and keeps each mission run self-contained.

---

### Anti-Grind Rules (Design Constraints)

1. **Enemy kills never drop currency or repeatable power items.** Only collectibles (ammo packs, consumables) drop.
2. **Revisiting areas does not yield new upgrades** — permanent upgrades can only be collected once.
3. **There is no benefit to killing extra enemies** beyond clearing a room. Farming is not a strategy.
4. **Upgrade density is fixed by map design** — the designer controls all power, not the player's time spent.

These rules must be enforced at implementation level. If any system accidentally creates a farm loop, it is a bug, not a feature.
