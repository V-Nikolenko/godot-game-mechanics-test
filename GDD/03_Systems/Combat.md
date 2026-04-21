# VOID BREACH — Game Design Document
## 03 · Systems · Combat

---

### Combat Layers

The game has two distinct combat contexts: **Ship Combat** (Open Space + Assault) and **Character Combat** (Land Missions). Both share design principles but operate independently.

---

## Ship Combat

### Open Space Combat
- **Style:** Free-form, inertia-based. Enemies engage at range and close in.
- **Primary fire** — rapid shots, medium damage
- **Charged Laser** — hold to charge; releases high-damage precision beam; cooldown after use
- **Explosive Missiles** — auto-targeting; limited ammo; refilled at beacons

**Enemy engagement pattern (Open Space):**
- Turrets: stationary, predictable fire patterns — learn and dodge
- Enemy ships: patrol → aggro → chase → attack; retreat at low HP
- Boss structures (Fortresses): multi-phase destruction targets (see AI.md)

### Assault Combat
- **Style:** Vertical scroller — constant pressure, precise movement
- Same weapon set as Open Space but in a 2D movement context
- Alert system controls pacing (Red = dodge, Yellow = shoot)

**Damage model:**
- Ship has a **Shield** bar (regenerates slowly between damage events) and a **Hull** bar (does not regenerate)
- Shield absorbs damage first; when depleted, hull takes damage
- Hull damage persists through missions; repairs require returning to Open Space and finding a repair kit or beacon
- If Hull reaches 0 in Assault: mission failed, narrative consequence possible (see Characters.md)

---

## Character Combat (Land Missions)

### Weapons
Player has **1 active weapon slot** at a time. Weapons are found throughout missions; switching requires finding the new weapon.

| Weapon Type | Range | Rate | Notes |
|---|---|---|---|
| Blaster (starter) | Medium | Fast | Low damage, always available |
| Scatter Shot | Short | Medium | Spread pattern, strong vs clusters |
| Plasma Rifle | Long | Slow | High single-target damage |
| Grenade Launcher | Medium arc | Slow | AOE — bounces off walls |
| (More TBD) | — | — | Found in late missions |

### Grenades / Mines (Slot 2)
- **Short press:** throws at short distance (arc preview shown)
- **Long press / hold:** charges throw distance (arc preview updates dynamically)
- **Mines:** placed at feet; proximity trigger or manual detonation
- Limited inventory; refilled at ammo caches in missions

### Melee (Slot 3)
- **Baseline (no modules):** short push + minor damage — emergency spacing tool only
- **With modules:** can become primary offensive tool (see Progression.md — Module System)
- Melee hits have knockback; intentional synergy with ledges, environmental hazards, and pressure plates

### Dash
Dash behavior is determined entirely by the equipped **Dash Module** (see Progression.md). Baseline: short-distance, brief invincibility frames.

---

### Combat Flow (Land Mission)

Standard enemy encounter structure:
1. Player enters area → enemies patrol
2. Player detected / attacks → enemies aggro
3. Enemy attacks: mix of ranged + melee attempts
4. Player uses movement (dash), positioning, and weapon choice
5. Enemy death: corpse persists (can be used for pressure plates, explode-on-push module, etc.)

**Corpse persistence is a design feature, not a side effect.** Environmental puzzle solutions and module interactions depend on it.

---

### Health System (Character)
- Player has a **Health** bar (increased by Health Upgrades)
- **Temporary Health Boosters** found in missions push above max HP ceiling — shown as an overflow section on the health bar
- No regeneration during missions (unless a specific module provides it)
- If Health reaches 0: respawn at mission checkpoint (not mission start)

**Checkpoints** in Land Missions are implicit — triggered by reaching key rooms or defeating sub-bosses. Never more than 5 minutes of progress lost.

---

### Combat Design Rules
1. Every enemy type should telegraph its dangerous attack with a clear animation or audio cue.
2. Every module that modifies combat (Pulse Strike, Magnetic Pull, etc.) must have a situation where it is clearly the best tool — no "trap" builds.
3. Melee without modules should feel **weak but not useless** — always a valid panic button.
4. Grenade trajectory preview is non-negotiable — players need reliable aim.
5. Enemy corpses should never auto-despawn during a mission room (only after leaving and re-entering).

---

### Boss Combat
- Each Land Mission ends with a boss or a high-difficulty objective
- Bosses have multiple phases; each phase introduces a new attack pattern
- Bosses do NOT have regenerating health — sustained pressure is rewarded
- Boss death triggers a cutscene or narrative beat before upgrade reward

**Mini-bosses** appear in sub-missions (Fortress destruction sequences) and as mid-mission challenges in larger Land Missions.
