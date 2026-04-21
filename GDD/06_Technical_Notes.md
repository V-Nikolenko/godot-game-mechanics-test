# VOID BREACH — Game Design Document
## 06 · Technical Notes

---

## Engine
**Godot 4.x** (inferred from existing codebase — see project repository)

---

## Architecture Overview

The game is structured around three distinct gameplay modes. Each mode is a separate scene/state with its own controller but shares:
- Player stats (HP, modules, weapon loadout, keys)
- Save state (upgrade collection, beacon activation, relationship values)
- Game Manager (persistent across mode transitions)

### Mode Separation

| Mode | Scene Type | Camera | Physics |
|---|---|---|---|
| Open Space | 3D or top-down 2D | Free camera, 360° | Inertia + gravity drift |
| Assault | 2D | Fixed vertical scroll | Arcade — no inertia |
| Land Mission | 2D side-scroll | Follow camera | Standard platformer gravity |

### Shared Systems
- **Save/Load:** All upgrade state, relationship values, beacon states, key inventory persist
- **Upgrade Manager:** Single source of truth for all permanent upgrades
- **Module System:** Active modules registered to a global slot manager; combat and movement components query it
- **Relationship Manager:** Silent tracker per-companion; integer value, no UI representation
- **Alert System (Assault):** Separate from general UI — lives in Assault scene

---

## Player Controller Architecture
*(Based on existing codebase splits observed in the project)*

The player controller is split into:
- **MovementStateManager** — owns movement state machine (idle, run, jump, dash, hover)
- **DashController** — queries active Dash Module; applies module-specific behavior
- **CombatController** — handles weapon fire, grenade throw, melee
- **ModuleSlotManager** — manages 3 module slots; broadcasts module events

Each module modifies behavior via composition, not inheritance. Modules attach effects to events (OnDash, OnHit, OnKill, OnTakeDamage) rather than overriding base behavior.

---

## Dash Module Implementation Pattern

Modules should be implemented as **Resources** (Godot Resource type) with:
- `module_id: String`
- `module_name: String`
- `description: String`
- `cooldown: float`
- `on_dash_start()` — override per module
- `on_dash_end()` — override per module
- `on_hit_enemy(enemy)` — optional; only override if module reacts to hits
- `on_take_damage(amount)` — optional; for defensive modules

The DashController calls `active_module.on_dash_start()` — no switch statements. New modules require no changes to the controller.

---

## Upgrade Fragment System

Fragments use a persistent dictionary keyed by upgrade ID:
```
upgrade_fragments = {
  "health_upgrade_1": 2,   # 2/4 collected
  "shield_upgrade_1": 0,   # not started
}
```

When fragment count reaches threshold → emit `upgrade_completed` signal → apply stat change → remove from fragment dict.

**Design constraint:** Fragment thresholds (3 vs 4 per upgrade) are set per-upgrade in designer data, not hardcoded.

---

## Alert System (Assault)

Alerts are issued by incoming obstacle/enemy objects:

1. Obstacle spawns off-screen
2. On spawn, obstacle registers with `AlertManager` with its type (RED/YELLOW) and screen entry direction
3. `AlertManager` pushes alert to HUD with direction vector
4. Alert expires when obstacle enters visible screen area

**Alert lifetime:** 2 seconds minimum before obstacle is on screen. Level designers must ensure spawn distances match this constraint.

---

## Enemy Corpse Persistence

Land Mission corpses must persist for the full duration of a room visit.

- Corpses use a lightweight static physics body after ragdoll settles (~0.5s)
- They register with the room's `CorpseManager`
- `CorpseManager` clears corpses only when the player exits and re-enters the room
- Pressure plates query `CorpseManager` for weight on plate

---

## Relationship System

The Relationship Manager stores per-companion integer values:
```
relationships = {
  "ANCHOR": 2,    # positive
  "CIPHER": -1,   # slightly negative
  "SPARK": 0,     # neutral
}
```

Threshold behavior:
- >= 3: Good relationship → companion ally in final mission
- 1–2: Neutral → reluctant assist
- <= 0: Bad → companion mini-boss

Values are never shown to the player. Companion dialogue lines change tone based on thresholds (requires writer flag system).

---

## Save System

Autosave triggers:
- Returning to Open Space after a mission
- Activating a beacon
- Collecting a permanent upgrade

Manual save: available from pause menu in Open Space only.

Save data includes:
- Upgrade collection state
- Beacon activation state
- Key inventory
- Relationship values
- Mission completion state
- Player loadout (equipped modules, active weapon)

**No cloud save dependency required for launch** — local file save sufficient.

---

## Performance Targets

| Context | Target FPS | Resolution |
|---|---|---|
| Open Space | 60 fps | 1080p (PC) |
| Assault | 60 fps locked | 1080p |
| Land Mission | 60 fps | 1080p |

Particle effects (CPU Particles preferred per existing codebase pattern) should be profiled at maximum enemy count per room.

---

## Known Technical Risks

| Risk | Mitigation |
|---|---|
| Module interaction edge cases (3 modules active simultaneously) | Build interaction test matrix early; all 23 modules × 23 combinations = 529 pairs |
| Corpse physics in large rooms | Limit ragdoll time; static body after settling |
| Open Space inertia feel | Requires dedicated playtesting; not solvable by design doc alone |
| Assault alert timing with high-density sections | Alert timing is data-driven; tweak per-obstacle in inspector |
| Companion AI in final mission | Mirror-player AI is complex; scope to 3 attack patterns minimum, polish later |
