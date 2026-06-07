# Race Mode Combat Improvements — Overview

**Date:** 2026-06-07  
**Context:** All six AI racers have been analyzed. This document lists every planned improvement step and links to the detail document for each.

---

## Goal

Make race mode feel like a full contact sport, not a solo time trial with obstacles:
- Racers deal damage to **each other**, not only to the player.
- AI shooters fire **straight forward** and only when a ship is **directly ahead** in their lane.
- **Physical collisions** between any two ships result in damage and a push-apart.
- **Mines** (Bogomol) already damage all racers correctly — no code change needed.
- AI racers **dodge each other's bullets**, not just the player's.

---

## Racer Roster & Combat Status

| Racer | Role | Shoots? | Contact dmg? | Notes |
|---|---|---|---|---|
| **Pacer** | Pure speedster | ✗ | ✗ | No combat by design; just receives damage |
| **Bogomol** | Mine-layer | ✗ | ✗ | Mines already hit all ships; no shooting |
| **Fang** | Tail-hunter | ✓ bullet + lunge | ✓ (lunge) | Bullets can't hit AI yet (mask bug) |
| **Booster Gold** | Front-runner | ✓ bullet + dash | ✓ (dash) | Bullets can't hit AI yet (mask bug) |
| **Isac** | Area suppressor | ✓ gatling | ✗ | Bullets can't hit AI; fires in all directions |
| **Reacher** | Long-range sniper | ✓ heavy shot | ✗ | Bullets can't hit AI; already forward-aimed |

---

## Improvement Steps

| Step | File(s) | What changes | Effort |
|---|---|---|---|
| [01 — Fix AI bullet collision masks](01-fix-ai-projectile-masks.md) | `race_ship.gd` | 1-line fix; AI bullets now damage AI racers | Trivial |
| [02 — Straight-forward bullets + forward-only constraint](02-straight-forward-bullets.md) | `racer_weapon.gd`, `isac_spray_state.gd` | Bullets fly up; Isac gains forward-target guard | Small |
| [03 — Reduce AI fire rates](03-fire-rate-reduction.md) | 2 state files | Export var defaults only; no logic change | Trivial |
| [04 — Racer body collision damage](04-racer-body-collision.md) | `race_level_config.gd` | New geometric pair-check system | Medium |
| [05 — Expand threat detection to AI bullets](05-threat-detection-expansion.md) | `sensors.gd` | 1-line default change; AI dodges other AI fire | Trivial |

Steps 1, 3, and 5 are one-line changes. Do them first for the biggest immediate impact.  
Step 2 changes bullet behavior for all shooters. Do it after Step 1 so you can observe the full effect.  
Step 4 is the most substantial new system.

---

## What Already Works (No Changes Needed)

- **Mines** (`mine.gd`): polls `["player", "racers"]` geometrically, lines 32–41. Bogomol's mines already hit all ships.
- **Track obstacles** (`obstacle.gd`): same pattern, already hits all ships with per-ship cooldown.
- **Lunge contact damage** (Fang `fang_lunge_state.gd`): iterates both groups, ~22 dmg per ship passed.
- **Dash contact damage** (BG `bg_dash_state.gd`): iterates both groups, ~45 dmg per ship passed.
- **AI targeting via Sensors**: `ship_ahead()` already returns any participant — player OR rival AI. Fang, BG Reclaim, Reacher, and Isac all naturally target whoever is closest ahead, not exclusively the player.
