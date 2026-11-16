# Heavy Gunship — mobile gun platform built from parts

**Role:** A heavy that keeps its distance, turns a battery side-on to the player, strafes wide arcs and boosts away when rushed. It never parks at
the top of the screen and never leaves the fight because it is hurt.
**Fantasy / threat:** A slow, armed hull you take apart. Each gun is a separate part, so killing a battery removes that attack for good and the
ship turns its other side to you. The parts sit on the hull's edges, so you aim at them by looking. Hurt it and it overheats: it has to stop
and vent through two glowing weak points. Hurt it more and it panics, boosting away and firing rear missiles at whoever chases it.

Plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.4 (Phase 10 t4) and §2.5 / §2.9 (t5); task plans `docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md`
(t4) and `docs/plans/cmwafsrb400abqs2yt38khcyu/3-plan.md` (t5). The multi-part art arrives in t9; level 1's rails come off in t11.

---

## Stats

| Property | Value |
|---|---|
| Hull HP | 700 (the phase bar; `config.max_health`) |
| Contact | 30 (`ContactProfile` COLLISION) |
| Score | 300 |
| Body | one 112 × 144 `RectangleShape2D` shared by the body, the root `HurtBox` and the `ContactHitBox` |
| Speed | `max_speed` 140 (84 while venting), `acceleration` 120, `max_turn_rate` 0.9 rad/s; break-away boost 360 px/s for 0.7 s; emergency boost 420 px/s for 0.9 s |
| Hazards | avoidance 1.0, margin 90, resistance 0.6 |
| Scene / config | `heavy_gunship.tscn`, `heavy_gunship_config.tres` (`HeavyGunshipConfig`, flat) |

## Parts (`Modules/*`, `EnemyModule`s; `ModularHull` beside them)

Nose-down art: the nose is local +y, so **port (the hull's left) is local +x**.

| Part | id | HP | Rect (centre, size) | Exposed edge | Mount |
|---|---|---|---|---|---|
| `BatteryPort` | `battery_port` | 160 | (40, 10), 32 × 40 | port flank x = 56 | Burst cannon (Pulse rounds), rest 0°, traverse 160° |
| `BatteryStarboard` | `battery_starboard` | 160 | (−40, 10), 32 × 40 | starboard flank x = −56 | Burst cannon, rest 180°, traverse 160° |
| `Cannon` | `cannon` | 200 | (0, 60), 32 × 24 | nose y = 72 | Heavy cannon (Heavy Shell, 220 px/s), rest 90°, traverse 70°; frontal shield |
| `Missiles` | `missiles` | 140 | (0, −60), 40 × 24 | aft y = −72 | Rocket battery, rest 270°, 360° (EMERGENCY only) |
| `VentPort` / `VentStarboard` | `vent_port` / `vent_starboard` | indestructible | (±48, −34), 16 × 24 | flanks | — (WEAK_POINT, open only in VENT, `hull_share` 1.0) |

Every part carries a `Light` (`StateLight`, at its centre).

**The flush-edge rule.** Every part's hurtbox has its outer side exactly on the hull rectangle's side, along the part's whole width (its exposed
edge). A shot that enters through that edge overlaps the part and the hull in the same physics step, and both take it, so a part hit is also a
hull hit. A shot that enters anywhere else hits only the hull. Each part's `HomingPoint` is the midpoint of its exposed edge.
`homing_point(from)` returns the nearest live vulnerable part's marker, so a player homing rocket flies into an edge. The beam and the nova reach
parts directly (`enemy_parts` group) and do not wear the hull through them. **Art (t9) may not move or resize a shape.**

**The vents.** Closed, a vent deflects (a white ping): a shot through its edge hurts the hull once. Open (VENT only), it is vulnerable and forwards
every hit to the hull (`hull_share` 1.0), so a shot through its edge hurts the hull **twice**. The beam and the nova never hurt a closed vent.

**The cannon shield.** `Modules/Cannon/Shield` is a Phase 5 `EnemyShield` on the cannon's own hurtbox: a 120° arc along the nose (the brain keeps it
there), 60 points, regeneration after 2 s over 4 s, a 5 s reboot after a break; it goes with the cannon. It protects **only the cannon's HP**: the
hull still takes a frontal hit through the nose edge. It decides by the bearing from the cannon's centre to where the shot is reported, one step
past the edge, so a frontal shot near the edge's corners can slip past the arc (accepted). A plain round cannot reach the cannon from the side (it
is spent on the bare flank first); the Sniper Shot can, and the shield does not cover it.

---

## Behaviour (`HeavyGunshipBrain`, `enum Phase`, append-only)

```
APPROACH ──in range──▶ BROADSIDE ⇄ BREAK_AWAY (player inside min_range, once per 3 s)
                          │  ▲
            OVERHEAT: 4 bursts ▼  │ 2.2 s
                         VENT
hull < 30 % ──▶ EMERGENCY (from any fight phase; never back)
       Assault budget ────▶ DISENGAGE (curved exit, freed outside the projectile rect)
Open Space hub: IDLE ──perceive──▶ NOTICING ──▶ APPROACH …   beyond lose_radius ──▶ RETURNING ──▶ IDLE
```

**Hull phases** (`enum HullPhase`, append-only; `hull_phase_changed(hull_phase)`) are read off the root `Health` once a tick and never step back (a
Support Ship's repair cannot undo one): **CONTROLLED** at 60 % and above, **OVERHEAT** at 30 % and above, **EMERGENCY** below.

- **APPROACH:** arrives at `held_range()` (Open Space 560, Assault 420) on the line to the player, with the nose (the cannon) on the player.
- **BROADSIDE:** orbits the player at the held range ± 90 px (a 7–10 s drift), at 0.16 rad/s (Assault 0.26), and reverses every 5–8 s. In Assault
  the arc stays within ±70° of straight above the player and reverses at its ends. The hull turns its chosen battery side to the player. That
  side is the one the player was on when first needed, and it is kept while its battery lives. **When the battery dies the hull swings its other
  side round.** With no battery left the nose faces the player; with only the missiles left it faces away.
- **BREAK_AWAY:** the player inside `min_range` 260 triggers one committed `mover.boost` along `Steering.break_contact` (the arc's own sense),
  then BROADSIDE; rearm 3 s.
- **OVERHEAT and VENT:** in OVERHEAT every battery or cannon burst adds 1 heat when it ends. The 4th vents on that tick: for 2.2 s the vents are
  open and glow orange, the hull slows to 84 px/s and keeps its arc and broadside, a burst already firing finishes and no new one starts (a charge
  in progress is cancelled). Then BROADSIDE again, heat 0.
- **EMERGENCY:** a committed boost away from the player (420 px/s for 0.9 s along `break_contact`) on entry and every 5 s after; between boosts the
  arc at 800 px (Assault 540) with the broadside facing, so the batteries keep firing. From each boost's end the **rear Missiles** pod may fire for
  2 s at a player behind the hull (inside the rear 200°: a pursuer), and only a salvo that fits in the window starts. The pod's own 5.5 s cooldown
  means it fires after every other boost. No break-away, no venting. **It never despawns because it is hurt**: in Open Space it fights until killed.
- **Weapons:** the mounts are built by `ModularHull.build_mounts()`. Every gun mount is ticked with `can_fire = can_see_player() or
  fires_past_cover()`; in Assault nothing fires while the hull is outside the view. A destroyed part's mounts are unpowered for good and its light
  goes dark: **a destroyed battery, cannon or missile pod never fires again.**
- **Reach in EMERGENCY:** the Open Space hold (800 ± 90 px) is beyond the batteries' ≈ 770 px broadside reach and a boost carries the hull past the
  pod's 900 px, so the guns and the pod reach a player who chases it. In Assault a boost usually carries the hull out of the fixed view, where no
  mount fires, so the pod rarely completes a salvo there (accepted by the owner).
- **Assault life:** `EngagementBudget` 9.0 s. The attack gate refuses a telegraph that would not finish inside the budget, and no break-away or
  emergency boost starts with less than its length left. **The rear pod is open only while the budget runs** (its gate and `can_fire` both ask, and
  DISENGAGE `scan(0.0)`s it), so every rocket leaves inside the budget and lives at most its scene's `max_time` (PURSUIT 6.0 s) after it: the
  bounded exception to "persistent ordnance stays out of `ENEMIES_CLEARED` sections". DISENGAGE releases the corridor and writes `exit_speed`
  300 / `exit_acceleration` 240 onto the mover. The hull then curves toward the nearest projectile-rect edge and is freed. The worst exit is
  measured once per GUT run through `tests/helpers/ph10_exit_keys.gd`.
- **EMP:** every mount `scan(0.0)`s (a charge never lands), the hull and weapon-part lights go OFF and the brain is frozen for the window, so a VENT
  in progress stays open (and orange) through it and resumes its clock after. **A rail** (`.move()`) suspends the brain: it rides and does not
  fire, and an open VENT closes at once.
- **Never towed** (`accepts_tow()` false). It answers EMP (AI-driven). Its own rockets have never hit it (measured over 60 s of EMERGENCY).

## Lights

| Light | Shows |
|---|---|
| Hull `StateLight` | yellow while a gun (in EMERGENCY also the pod) charges, red while one tracks, fires or cools, else off |
| A weapon part's `Light` | yellow while its mount charges |
| A vent's `Light` | orange while it is open (VENT) |
| A wreck's `Light` | off for good |
| Cannon shield | cyan arc (the shield's own drawing) |

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
