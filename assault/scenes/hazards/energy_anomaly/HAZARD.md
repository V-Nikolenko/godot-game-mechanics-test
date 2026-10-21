# Energy Anomaly — the pulsed swirl

**Role / threat:** A distortion that, while lit, swirls every mover-driven ship sideways around its centre. It
never damages and never slows; it bends a course. It pulses on a visible rhythm so the player can read when to
cross it. Plan §2.6 (`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`).

## Stats

| Property | Value |
|---|---|
| Reach (`radius`) | 300 px |
| `core_radius` | 80 px — the swirl is constant inside it |
| `tangential_force` | 260 px/s² (+ = clockwise). **An instance swirls the other way by setting −260**; there is no `clockwise` export |
| `pull_force`, damage, slow | none |
| Cycle | TELEGRAPH 1.0 s → ACTIVE 2.5 s → QUIET 3.0 s, looping (a fresh anomaly starts in TELEGRAPH) |
| `avoid_weight` | 0.7 during TELEGRAPH and ACTIVE, 0 while QUIET (`HazardField` does this) |
| Scene | `energy_anomaly.tscn` — `HazardField` root (`kind = &"anomaly"`) + `Sprite` (t5 art, `dim` / `lit`) |

## Behaviour

- **Sampled, never applied.** Outside ACTIVE the field's forces are 0. `EnemyMover` integrates
  `Hazards.accel_at()` into its drift (scaled by `1 − hazard_resistance`); the Open Space player adds the same
  acceleration to its velocity. A swirl never rotates a ship.
- **No physics body, no line-of-sight blocking.** Ships and shots pass through; collision bit 12 stays free.
- Opted-in projectiles (rockets, bombs) are bent by it through `Hazards` (a later task); bullets fly true.

## Telegraph

Violet / magenta only (cyan means shield). `energy_anomaly_sprite.gd` on the sprite reads the parent's
`phase_changed` and `phase_progress()`: TELEGRAPH — dim frames, brightness climbing 0.55 → 1.0; ACTIVE — lit
frames, full brightness, the sprite spins; QUIET — dim frames, brightness 0.45, still. It also draws a faint ring at
the full `radius`. Presentation only: nothing here touches a ship or the field.

## Files

```
energy_anomaly/
├── HAZARD.md                  ← this file
├── energy_anomaly.tscn        ← HazardField values + animated sprite
└── energy_anomaly_sprite.gd   ← EnergyAnomalySprite: look follows the cycle
```

Tests: `tests/integration/test_energy_anomaly.gd` (real scene, dual-mode where enemies are involved).
