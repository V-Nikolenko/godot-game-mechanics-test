# Gravity Well — the crushing core

**Role / threat:** A permanent field that drags every mover-driven ship toward its centre and crushes hulls close
in. It hurts both sides: the player can bait drones into it, and it will pull the player too. Plan §2.5
(`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`).

## Stats

| Property | Value |
|---|---|
| Reach (`radius`) | 420 px — pull, avoidance footprint and the drawn ring |
| `core_radius` | 90 px — the pull is constant (520 px/s²) inside it |
| `pull_force` | 520 px/s² at ≤ 90 px; 334 at 140, 234 at 200, 131 at 357, 0 at 420 (softened 1/r, linear taper from 0.85 × radius) |
| Hull stress | 5 damage every 0.5 s (10 /s) to any ship whose **centre** is within `damage_radius` 150 px |
| `avoid_weight` | 1.0 (the AI keeps clear of it) |
| Slow, cycle, duration | none (`movement_penalty` 0, no cycle, `duration` 0 = permanent) |
| Scene | `gravity_well.tscn` — `GravityWell` (`gravity_well.gd`, a `HazardField`) + `Sprite` (t5 art, `swirl`) + `Glow` |

## Behaviour

- **A pull, never a push.** The field writes nothing on a ship. `HazardField` registers with `Hazards`; an enemy's
  `EnemyMover` and the player sample `Hazards.accel_at()` themselves (§2.2, §2.3). Whether a ship escapes is
  profile arithmetic: Swarm drone terminal drift 263 px/s vs its own 220 → captured; Fighter 236 vs 300 → gets out.
  The Open Space player cannot thrust out inside ~123 px (thrust 380 px/s²) and must boost.
- **Hull stress** is `Hazards.pulse_damage` — a direct `received_damage.emit(5)` on the `HurtBox` of every node in
  groups `enemies` and `player`. It **bypasses `EnemyShield`** (a direct emit never meets the absorber hook), and a
  **plated Ram deflects it**: `RamCorvette._on_received_damage` refuses every hit while a plate lives. The player's
  own shield charge still absorbs a pulse like any hit.
- **No physics body.** Ships and shots pass through it (the root is a plain `Node2D`; no `Area2D`, collision
  bit 12 stays free) and it does **not** block line of sight (`line_of_sight_blocker` false).
- **Claim:** its `HazardInfo` carries the Ram's well-station ticket (`try_claim` / `release`, §2.14).

## Telegraph

A faint violet ring at the full `radius`, drawn in `GravityWell._draw()`; an inner gold ring and fill (`Glow`) whose
brightness follows the field strength **at the player's position** (`glow_strength()`, floor 0.15). Presentation
only. A stressed ship flashes from its normal hit path.

## Files

```
gravity_well/
├── HAZARD.md            ← this file
├── gravity_well.gd      ← GravityWell: ring + glow strength (read-only presentation)
├── gravity_well_glow.gd ← Glow child: draws the inner glow
└── gravity_well.tscn    ← HazardField values + animated sprite
```

Tests: `tests/integration/test_gravity_well.gd` (real scene, dual-mode where enemies are involved).
