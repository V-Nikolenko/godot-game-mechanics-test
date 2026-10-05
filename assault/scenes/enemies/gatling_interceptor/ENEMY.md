# Gatling Interceptor — side-on suppression gunship

**Role:** A suppression unit, not a chaser (Tier 2). It holds a side-on range of about 380 px on one flank of the
player. It fires one readable stream there, goes quiet, and swings round to the other flank for the next one.
**Fantasy / threat:** A yellow light means a stream is coming from the side. The stream is aimed at where you are
*going*. Move across it, or away from it, and the pressure stops until it comes round again.

Plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.6 and §2.8. Task plan, with the numbers and the one
deviation: `docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md`. Convergence fire for a pair is built (t11, below); hub idle (t12) is
not built yet.

---

## Stats

| Property | Value |
|---|---|
| HP | 70 |
| Damage | 20 contact (`collision_damage`, applied from config) / 4 per round (`round_damage`; rail `rail_damage`) |
| Speed | 260 px/s cruise; 140 px/s strafe while firing; 520 px/s on the Assault exit |
| Rounds | Gatling Stream (`EnemyRounds.GATLING_STREAM`): a thin red streak, 1400 px range. AI 240 px/s, rail 220 px/s |
| Sprite | `interceptor.png` (legacy placeholder, a `Sprite2D`; replaced in t15) |
| Scene | `gatling_interceptor.tscn` |
| Config | `gatling_interceptor_config.tres` |

---

## Behaviour & Movement

`GatlingInterceptorBrain` decides, and `EnemyMover` (constraint AUTO: the corridor in Assault) moves. `BaseEnemy` ticks
the brain, then the mover. The brain only requests motion (the single-writer gate).

| Phase | What it does | Light |
|---|---|---|
| APPROACH | Routes to the first flank point `F`. Hands over once `F` is within `swing_in_reach` (300 px). | off |
| SWING_IN | Routes to `F` and slows into it. Within 60 px, or after `swing_in_max` (1.5 s), it moves to SPIN_UP. | **yellow** |
| SPIN_UP | `spin_up_seconds` (0.25 s). Brakes into the strafe, nose on the player. No rounds. | **yellow** |
| STREAM | One stream of `rng` 8–12 rounds, 0.09 s apart, each aimed at the player's predicted position (`accuracy` 0.8, ±0.05 rad jitter). It slides along the flank while firing. | **red** |
| COOLDOWN | `cooldown_seconds` (0.4 s), still drifting. No rounds. | off |
| REPOSITION | Flips to the other flank, brakes and swings round (never across the player). It lasts at least 1.0–1.5 s, until the new `F` is in reach, capped at 5 s. | off |
| DISENGAGE | Assault only, on budget expiry: releases the corridor, curves out of the world rect and frees itself. | off |

- **Flank point:** `F = P̂ + right(h) × side × 380`. `P̂` is the player 0.3–0.8 s ahead. `h` is the player's heading
  (`UP` in Assault).
  - In Assault, `F` sits 60 px ahead of the player and is clamped into the corridor.
  - "Side-on" means the bearing from the player stays within 90° ± 35° of `h` while the Gatling streams.
- **Sides:**
  - **First window.** Open Space: the side it is already on. Assault: the half of the corridor opposite the player's x.
  - **Every later window:** the other side.
  - **Assault exception:** if the other side's `F` would be within `min_flank_range` (220 px) horizontally of a player
    hugging a wall, it stays on the open side.
- **Swings:** the route steps round a 380 px ring, 50° at a time.
  - In Assault it goes round **ahead** of the player, through the upper corridor. It goes round behind only when the
    corridor clamp would pull the route within 220 px of a player near the top.
  - In Open Space it takes the short way.
- **Fire direction (settles the old "forward or at the player?" question):** every round is **aimed at the player's
  predicted position**. What keeps it side-on is the *movement*, not the gun. The ship's nose faces the player while it
  spins up and fires.
- **No false telegraphs:** in Assault, a window starts only with at least `swing_in_max` of the engagement budget left,
  so a yellow light is always followed by a stream.
  - A budget that runs out mid-window lets the stream finish all its rounds, and DISENGAGE starts on the tick the stream
    ends.
  - The worst case solo is 0.25 + 11 × 0.09 ≈ 1.24 s. The epic bound with a convergence pair is 2.08 s.
- **Rhythm:** a window comes about every 5.8 s, ≈ 1.7 shots/s on average. The shortest possible period is 2.28 s
  (`min_window_period()`), which sizes the pool.
  - In Assault, at `engage_seconds` 7.0, a Gatling usually gets **one** window before it leaves.
- **Rails** (`.move()`, the station's LEFT/RIGHT reinforcements, and level 1 until it migrates): `on_suspended()` runs
  the legacy constant stream from the `rail_*` fields.
  - Every 0.09 s, 220 px/s, ±0.08 rad, aimed at the player with accuracy 0.
  - It uses the same 36-round `StreamPool`. The rail need is 71, so a rail Gatling fires about 36 rounds and then stalls
    until they expire. That is the legacy starvation shape (the legacy pool was 20), kept deliberately until Ph15 takes
    the rails away.
- **Convergence fire (a squad of two or more; plan §2.6.1):** two Gatlings charge together, cross their streams at the
  player's likely next position from the *same* side, and leave the other side open. A solo Gatling, or a squad of
  one, never converges.
  - The LEAD opens the window at its SWING_IN entry (`squad.attack_window_open`, `convergence_stage[lead] = 0`) and
    rewrites `squad.convergence_point` every tick until the window closes: the player predicted
    `clamp(d / round_speed, 0.4, 0.8)` s ahead. It opens no second window while one is open (it holds in REPOSITION).
  - A FLANK within `convergence_join_range_factor × preferred_range` (570 px) of the player answers **once**, on its
    next tick, only from APPROACH, COOLDOWN or REPOSITION: it takes the LEAD's *intended* `side` (not the half its
    hull is in — after a REPOSITION flip the LEAD has not crossed yet) and swings to a flank point rotated
    `convergence_bearing_offset_deg` (40°) toward the heading. Both lights go yellow within one tick. A far FLANK, or
    one in its own SWING_IN / SPIN_UP / STREAM, skips the window and keeps its own rhythm. A REAR never joins.
  - **Rendezvous:** each participant marks itself ready (`convergence_stage` 1) when its own spin-up is over and
    streams once every participant is ready, or after `sync_wait_max` (0.75 s) of waiting. Both streams then start
    within one tick.
  - **Aim:** every round is aimed at the shared point, rotated by a ±`convergence_aim_error_deg` (3°) error drawn
    once per window, plus the usual jitter. The pattern's `aim_point` is cleared on COOLDOWN.
  - **Close:** a finished stream marks the member done (stage 2); the LEAD closes the window (point and stages
    cleared) on the first tick every key is done, i.e. the *later* COOLDOWN. A member that leaves the board (dies,
    DISENGAGE, rail) is erased. If the LEAD dies or changes, the whole board is cleared and a FLANK mid-stream
    finishes all its rounds at its own predicted point.
- **Death / scoring:** 75 points on kill.

---

## Config exports (`gatling_interceptor_config.gd`; the `.tres` sets every field)

| Group | Export | Value | Meaning |
|---|---|---|---|
| — | `max_health` / `collision_damage` / `score_value` | 70 / 20 / 75 | Legacy |
| Movement | `max_speed`, `acceleration`, `braking`, `turn_rate` | 260, 600, 900, 2.0 | Pinned: `turn_rate × max_speed ≤ acceleration` |
| Geometry | `preferred_range` | 380 | Side-on distance (px) |
| | `min_flank_range` | 220 | Assault wall exception; also how close a swing may route (px) |
| | `approach_margin` | 250 | APPROACH's close range is `preferred_range` + this (px) |
| | `swing_in_reach` | 300 | APPROACH / REPOSITION hand over once `F` is this close (px) |
| | `reposition_cap` | 5.0 | The longest APPROACH-in-range or REPOSITION (s) |
| Window | `swing_in_max`, `spin_up_seconds` | 1.5, 0.25 | s |
| | `sync_wait_max` | 0.75 | A pair's rendezvous cap (t11). Unused solo (s) |
| | `stream_rounds_min/max`, `stream_interval` | 8 / 12, 0.09 | Rounds, s |
| | `stream_strafe_speed` | 140 | px/s |
| | `cooldown_seconds`, `reposition_min/max` | 0.4, 1.0 / 1.5 | s |
| Rounds | `round_speed`, `round_damage`, `stream_spread`, `accuracy` | 240, 4, 0.05, 0.8 | The AI stream |
| Tactics | `engage_seconds`, `exit_speed` | 7.0, 520 | Assault budget (s), exit speed (px/s) |
| Rail | `rail_stream_interval`, `rail_stream_speed`, `rail_spread`, `rail_damage` | 0.09, 220, 0.08, 4 | The legacy weapon (formerly `fire_interval`, `bullet_speed`, `spread_angle`, `bullet_damage`) |

---

## Spawn notes

- WaveBuilder method: `b.gatling_interceptor()`. See `docs/enemy-roster.md`.
- With no `.move()` it is an AI Gatling. With `.move(...)` it rides the rail and fires the legacy stream.
- Keep it out of ENEMIES_CLEARED sections (epic plan §2.6). Its window deferral is not in the deadline formula.

---

## Tests

- `tests/integration/test_gatling_interceptor.gd`: scene and pool sizing, the rail fallback, the window rhythm and
  cadence in both harnesses, the seed sweep (8 and 12), side-on streams, sides (first window, alternation, the wall
  exception and its boundary), the corridor-top routing and its boundary, the budget rule and the deferred DISENGAGE.
- `tests/integration/test_enemy_dual_mode.gd`: an identical APPROACH mid-corridor, and DISENGAGE in Assault only.

---

## Files

```
gatling_interceptor/
├── ENEMY.md                         ← this file
├── gatling_interceptor.tscn         (root, Sprite2D, shapes, HurtBox, Health, HitFlash, ContactHitBox,
│                                      EnemyMover, Brain, StateLight, StreamPool, Attack)
├── gatling_interceptor.gd           (config → mover / pattern / brain)
├── gatling_interceptor_brain.gd     (GatlingInterceptorBrain)
└── gatling_interceptor_config.gd / .tres
```
