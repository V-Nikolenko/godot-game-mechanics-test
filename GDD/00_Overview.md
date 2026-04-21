# VOID BREACH — Game Design Document
## 00 · Overview

---

### Working Title
**VOID BREACH**

### Genre
Space Action Metroidvania — three interlocking gameplay modes (Exploration, Assault, Infiltration) unified by exploration-driven progression.

### Platform Target
PC (primary), Console (secondary)

### Core Pillars

| Pillar | Statement |
|---|---|
| **No Economy** | Nothing is bought. Everything is found. Exploration is the only currency. |
| **Layered Mastery** | Each of the three modes has its own skill ceiling; players who master all three are rewarded. |
| **Meaningful Modularity** | The module system allows wildly different playstyles — every build should feel viable. |
| **Consequence Without Punishment** | The game is hard but never unfair. Permanent death does not exist. Bad choices cost time, not save files. |
| **Narrative Through Systems** | Story beats emerge from gameplay state (upgrade level, NPC relationships) rather than cutscenes alone. |

---

### Elevator Pitch
You are an operative dropped into hostile deep space. Your ship is your lifeline across three worlds of play:
- **Open Space** — a freeform 360° exploration hub connecting everything.
- **Assault** — fast vertical shoot-em-up breaching planetary defenses.
- **Land Missions** — boots-on-ground infiltration through enemy installations.

Every sector you unlock, every module you equip, every relationship you build or burn feeds directly into how the final mission plays out. There is one ending with many shapes.

---

### Structural Summary

```
[Open Space Hub]
      |
      |── Sub-Missions (Fortresses, Caravans, Distress Signals…)
      |── Secrets / Upgrade Pickups
      |── Fast Travel Beacons
      |
      └── [Assault Mission]  ──→  [Land Mission]
                                        |
                                        └── Boss / Objective
```

The player always returns to Open Space after missions. Progression gates in Open Space are unlocked by upgrades found in missions, and vice versa — a classic metroidvania loop across three mode layers.

---

### Key Design Decisions

- **No shops, no currency, no grind.** All power is tied to exploration depth and skill.
- **Modules replace a skill tree.** Up to 3 (hidden: 4–5) equippable modules shape the character's entire combat identity.
- **The final mission is a point of no return** but the game can be completed afterward for the true ending.
- **Character relationships are tracked silently.** No visible friendship meter — consequences emerge naturally.
- **Alert colors are the difficulty communicator** in Assault (Red = dodge-only, Yellow = destroy-or-dodge).

---

### References / Tone
- **Genre inspirations:** Metroid (exploration gating), Returnal (tight 3rd-person combat), Ikaruga/Cuphead (assault mode), Dead Cells (modular builds)
- **Tone:** Grim, atmospheric sci-fi. Not comedic. Not grimdark. Tense and purposeful.
- **Art direction:** Hard sci-fi aesthetic — industrial ships, cold star fields, brutalist enemy installations.
