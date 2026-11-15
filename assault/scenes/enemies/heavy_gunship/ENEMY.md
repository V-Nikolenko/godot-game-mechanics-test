# Heavy Gunship — mobile gun platform built from parts

**Role:** A heavy that keeps its distance, turns a battery side-on to the player, strafes wide arcs and boosts away when rushed. It never parks at
the top of the screen and never leaves the fight because it is hurt.
**Fantasy / threat:** A slow, armed hull you take apart. Each gun is a separate part, so killing a battery removes that attack for good and the
ship turns its other side to you. The parts sit on the hull's edges, so you aim at them by looking.

Plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.4 (Phase 10 t4); task plan `docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md`. The
overheat-and-vent and emergency phases, rear missiles and cannon shield arrive in t5; the multi-part art in t9; level 1's rails come off in t11.

---

## Stats

| Property | Value |
|---|---|
| Hull HP | 700 (the phase bar; `config.max_health`) |
| Contact | 30 (`ContactProfile` COLLISION) |
| Score | 300 |
| Body | one 112 × 144 `RectangleShape2D` shared by the body, the root `HurtBox` and the `ContactHitBox` |
| Speed | `max_speed` 140, `acceleration` 120, `max_turn_rate` 0.9 rad/s; break-away boost 360 px/s for 0.7 s |
| Hazards | avoidance 1.0, margin 90, resistance 0.6 |
| Scene / config | `heavy_gunship.tscn`, `heavy_gunship_config.tres` (`HeavyGunshipConfig`, flat) |

## Parts (`Modules/*`, `EnemyModule`s; `ModularHull` beside them)

Nose-down art: the nose is local +y, so **port (the hull's left) is local +x**.

| Part | id | HP | Rect (centre, size) | Exposed edge | Mount |
|---|---|---|---|---|---|
| `BatteryPort` | `battery_port` | 160 | (40, 10), 32 × 40 | port flank x = 56 | Burst cannon (Pulse rounds), rest 0°, traverse 160° |
| `BatteryStarboard` | `battery_starboard` | 160 | (−40, 10), 32 × 40 | starboard flank x = −56 | Burst cannon, rest 180°, traverse 160° |
| `Cannon` | `cannon` | 200 | (0, 60), 32 × 24 | nose y = 72 | Heavy cannon (Heavy Shell), rest 90°, traverse 70° |
| `Missiles` | `missiles` | 140 | (0, −60), 40 × 24 | aft y = −72 | Rocket battery, rest 270°, 360° (closed until t5) |
| `VentPort` / `VentStarboard` | `vent_port` / `vent_starboard` | indestructible | (±48, −34), 16 × 24 | flanks | — (WEAK_POINT, locked until t5's VENT, `hull_share` 1.0) |

**The flush-edge rule.** Every part's hurtbox has its outer side exactly on the hull rectangle's side, along the part's whole width (its exposed
edge). A shot that enters through that edge overlaps the part and the hull in the same physics step, and both take it, so a part hit is also a
hull hit. A shot that enters anywhere else hits only the hull. Each part's `HomingPoint` is the midpoint of its exposed edge.
`homing_point(from)` returns the nearest live vulnerable part's marker, so a player homing rocket flies into an edge. The beam and the nova reach
parts directly (`enemy_parts` group) and do not wear the hull through them. **Art (t9) may not move or resize a shape.**

---

## Behaviour (`HeavyGunshipBrain`, `enum Phase`, append-only)

```
APPROACH ──in range──▶ BROADSIDE ⇄ BREAK_AWAY (player inside min_range, once per 3 s)
                          │
       Assault budget ────┴──▶ DISENGAGE (curved exit, freed outside the projectile rect)
Open Space hub: IDLE ──perceive──▶ NOTICING ──▶ APPROACH …   beyond lose_radius ──▶ RETURNING ──▶ IDLE
VENT / EMERGENCY: t5 (stubs that fall back to BROADSIDE)
```

- **APPROACH:** arrives at `held_range()` (Open Space 560, Assault 420) on the line to the player, with the nose (the cannon) on the player.
- **BROADSIDE:** orbits the player at the held range ± 90 px (a 7–10 s drift), at 0.16 rad/s (Assault 0.26), and reverses every 5–8 s. In Assault
  the arc stays within ±70° of straight above the player and reverses at its ends. The hull turns its chosen battery side to the player. That
  side is the one the player was on when first needed, and it is kept while its battery lives. **When the battery dies the hull swings its other
  side round.** With no battery left the nose faces the player; with only the missiles left it faces away.
- **BREAK_AWAY:** the player inside `min_range` 260 triggers one committed `mover.boost` along `Steering.break_contact` (the arc's own sense),
  then BROADSIDE; rearm 3 s.
- **Weapons:** the mounts are built by `ModularHull.build_mounts()`. Every gun mount is ticked with `can_fire = can_see_player() or
  fires_past_cover()`. A destroyed part's mounts are unpowered for good.
- **Assault life:** `EngagementBudget` 9.0 s. The attack gate refuses a telegraph that would not finish inside the budget, and no break-away
  starts with less than 0.7 s left. DISENGAGE releases the corridor and writes `exit_speed` 300 / `exit_acceleration` 240 onto the mover. The
  hull then curves toward the nearest projectile-rect edge and is freed. The worst exit is measured once per GUT run through
  `tests/helpers/ph10_exit_keys.gd`.
- **Never towed** (`accepts_tow()` false). It answers EMP (AI-driven). A rail (`.move()`) suspends the brain: it rides and does not fire.

## Spawn notes

- `b.heavy_gunship().at(x, y)`; spawn above the screen in Assault. Level 1 still rides rails on the three Cloud Descent rows until t11.

## Files

```
heavy_gunship/
├── ENEMY.md                    ← this file
├── heavy_gunship.tscn / .gd    (HeavyGunship extends BaseEnemy)
├── heavy_gunship_brain.gd      (HeavyGunshipBrain)
└── heavy_gunship_config.gd / .tres (HeavyGunshipConfig)
```

Gate: `tests/integration/test_heavy_gunship.gd`.
