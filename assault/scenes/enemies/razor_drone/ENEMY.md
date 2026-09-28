# Razor Drone — blade-like orbiting duellist

**Role:** A self-managed pursuit drone that circles the player, reverses, fakes dashes, and makes a telegraphed
real dash that it survives. After a missed dash it fires one pulse shot and curves back round.
**Fantasy / threat:** A fencer. It circles you, feints a lunge past you, and then commits from the far side. The white
flash is the one moment to dodge; yellow alone might be a bluff.

Plan: `docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md` §2.8.2–§2.8.3. Task plan (numbers, review):
`docs/plans/cmuj4y8rr007gp52xxs8dec5s/`.

---

## Stats

| Property | Value |
|---|---|
| HP | 25 |
| Damage | 30 contact while dashing (RAMMING); pulse shot 10 |
| Speed | 200 approach/return · orbit anchor 1.8 rad/s at 130 px · 360 feint lunge · 480 dash · 200 overshoot · 320 exit |
| Mover | acceleration 900, braking 700, `max_turn_rate` 6 rad/s, `turn_lerp` 7, `constraint_mode = AUTO` |
| Sprite | `drone_2.png` (placeholder until the t13 sprite; nose-up, `sprite_forward_angle = -PI/2`) |
| Scene | `razor_drone.tscn` |
| Config | `razor_drone_config.tres` |

---

## Behaviour & Movement

- **Movement:** self-managed AI on the shared brain/mover architecture. `RazorDroneBrain` decides, and the sibling
  `EnemyMover` moves the drone through `BaseEnemy`'s shared tick; `razor_drone.gd` has no `_physics_process`.
  - The corridor is **on** (`constraint_mode = AUTO`). In Assault it keeps to the corridor and its orbit centre is
    clamped into `inner_rect()` shrunk by `orbit_radius`.
  - Do NOT attach `.move()`: a rail suspends the brain (`BaseEnemy.suspend_ai()`, which arms the RAMMING profile and
    shows the light red).
- **Contact:** a scene-authored `ContactProfile` in **RAMMING** mode. The `ContactHitBox` (damage =
  `collision_damage`) is live **only during DASH**, and touching it at any other time deals 0. A registered touch
  marks the dash as a hit; it does **not** kill the drone.
- **Telegraph:** a `StateLight` at the nose:
  - CHARGING (yellow) during both wind-ups;
  - COMMIT (white) only in the 0.12 s before a real dash (the only code path that shows white);
  - ARMED (red) while dashing;
  - OFF otherwise, including during the feint's lunge and brake.
- **Attack:** after a *missed* dash (the boost ended with no `contact_made`), one pulse shot at OVERSHOOT entry:
  - the scene-authored `AttackController` (`driven_by_brain`, `enabled = false`) calls `fire_now()` with an
    `AimedAttackPattern` built per instance in `razor_drone.gd` (`pulse_damage` 10, `pulse_speed` 250, accuracy 0);
  - the bullet comes from its own `BulletPool` (4 × `enemy_bullet.tscn`) and flies in the drone's container.
  - A hit fires nothing.
- **Assault exit:** an `EngagementBudget` of `engage_seconds` (9 s). Expiry waits for any boost to end, then the drone
  goes to DISENGAGE: it releases the corridor, seeks the nearest edge of `projectile_world_rect()`, and is freed once
  strictly outside it, which counts as an escape. Open Space never disengages.
- **Death / scoring:** shot down (25 HP) → `score_value` 40.
- **Hub idle (Open Space only)** — the drone owns an `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) around an
  exported `patrol_anchor` (`Vector2.INF` = "unset", defaulted to the spawn position in `_start()`). Assault never
  builds one — `EngagementBudget.active` alone decides combat-from-spawn there, and `start_engaged` is a test-only
  seam that makes an Open Space drone skip idle too, for every test written before this behaviour existed.
  - **IDLE_ORBIT** — a slow ring orbit around `patrol_anchor`, radius `idle_radius` ± `idle_radius_jitter` and
    angular speed `idle_speed` ± `idle_speed_jitter`, both redrawn every 2–4 s leg. Re-anchors on entry (from a
    fresh spawn, a brake, a reversal, a boost or a return), so it never snaps to the far side of the ring.
  - Each leg ends in one of, equally likely: **IDLE_BRAKE** (a 0.6 s hold), **IDLE_REVERSE** (the ring's angular
    speed ramps through zero to the opposite sense, like combat's REVERSE), or **IDLE_BOOST** (a brief boost at
    1.8× the leg's tangential speed along the current heading).
  - A drone that perceives the player (`perceive_radius` 450 px) enters **NOTICING**: the light blinks once, it
    faces the player for `notice_time` (0.35 s), then hands over to **ENTER** from its *current* velocity — no
    `halt()`, no `boost()`, so the mover's own accel/turn-rate caps bound the handover.
  - It drops back to patrol once beyond `lose_radius` (700 px), never before — no flicker at the boundary. It
    enters **RETURNING** (`arrive` at `patrol_anchor`), reaching `IDLE_ORBIT` once within the ring. RETURNING never
    interrupts a live DASH: a contact-armed pass always finishes first.

---

## State Graph

```
ENTER ──≤ orbit_radius──▶ ORBIT ◀──────────────────────────────────────────────┐
                            │ window (1–2 s) ends → roll                          │
          ┌─────────────────┼──────────────────────┐                              │
     reverse_chance    fake_chance             otherwise                          │
          ▼                 ▼                      │                              │
       REVERSE        FEINT_WINDUP (0.75 s)        │                              │
     (ω ramps through  → FEINT_LUNGE (70 px        │                              │
      0, 0.25 s)          beside the player)       │                              │
          │            → FEINT_BRAKE (< 40 px/s)   │                              │
          ▼                 │ flip orbit_dir       ▼                              │
        ORBIT               └──────────────▶ WINDUP (0.5 s yellow, 0.12 s white)  │
                                                   ▼                              │
                                             DASH (armed, red)                    │
                                                   ▼                              │
                                             OVERSHOOT (pulse if missed; turn_toward curve)
                                                   ▼                              │
                                             RETURN (arrive on ring) ─────────────┘
Assault only: any phase ──budget expired, not boosting──▶ DISENGAGE ──outside world rect──▶ freed

Open Space only, cold start:
IDLE_ORBIT ──2-4s leg ends, roll──▶ IDLE_BRAKE / IDLE_REVERSE / IDLE_BOOST ──▶ IDLE_ORBIT (fresh leg)
   │
   ├──perceives (perceive_radius)──▶ NOTICING ──notice_time──▶ ENTER (current velocity)
   ▲                                                                  │
   └──arrives at patrol_anchor──────────── RETURNING ◀──beyond lose_radius (never mid-DASH)──┘
```

Phases are an `enum` in `razor_drone_brain.gd` (there is no `states/` folder). ENTER, ORBIT and DASH keep the
values 0–2; the rest are appended. `phase_changed(new_phase: int)` fires on every transition, and `enter_phase()` is
the one transition path (and the test seam). `force_next_choice(&"real" | &"fake" | &"reverse")` forces the next
combat roll; `force_next_idle_leg(&"brake" | &"reverse" | &"boost")` forces the next idle-leg roll.

- **ORBIT:** `Steering.orbit` round `orbit_centre` at `orbit_correct_speed` 260, which is at least
  `orbit_speed × orbit_radius`, so it holds about 119 px. It re-anchors where it arrives (never on the far side).
  - A reversal is barred from its end until the next attack begins.
  - **Side lane (Assault only):** an attack starts only when the point the *real* dash will start from is 30°–75° off
    the vertical axis about the player, with a 3° inner margin. That point is the WINDUP hold point for a real attack,
    or the predicted far-side stop for a feint; the lunge side is chosen so it lands in a lane. Otherwise ORBIT waits,
    for at most 2 s.
- **FEINT:** the lunge aims `feint_clearance_px` beside the player, so the closest approach is about 62 px against a
  44 px hull + player hurtbox. It sweeps about 128° round (measured from the lunge start), brakes, flips `orbit_dir`,
  and enters WINDUP at once, with no orbit leg. The profile is never armed and the light never goes white.
- **WINDUP:** holds at its stopping point (`hold_position(…, 4, orbit_correct_speed)`). It locks the dash point on the
  first white tick: `TargetInfo.predicted_position(dash_prediction_time)`.
- **DASH:** `boost` for `min((distance + overshoot_px) / dash_speed, max_dash_seconds)`, facing along the velocity.
- **OVERSHOOT:** each tick requests `Steering.turn_toward(actor.velocity, to_player, 3.0 rad/s) × 200`, rebuilt from
  the current velocity (D7). It turns about 145° in 1.2 s and never stops. It ends within 20° of the bearing, or after
  `overshoot_max_seconds`.
- **RETURN:** `arrive` back on the ring at `approach_speed`, within 20 px or after 2 s, then ORBIT with a new window.
- **IDLE_ORBIT** (Open Space only) — `Steering.orbit` around `patrol_anchor` at `idle_radius` ± `idle_radius_jitter`,
  angular speed `idle_speed` ± `idle_speed_jitter`, both redrawn every 2–4 s leg; re-anchors on entry.
- **IDLE_BRAKE** — holds (zero velocity request) for 0.6 s, then a fresh IDLE_ORBIT leg.
- **IDLE_REVERSE** — the ring's angular speed ramps through zero to the opposite sense over `reverse_seconds`
  (shared with combat's REVERSE), flips `orbit_dir`, then a fresh IDLE_ORBIT leg.
- **IDLE_BOOST** — a brief boost (0.4 s) at 1.8× the leg's tangential speed along the current heading, then a fresh
  IDLE_ORBIT leg.
- **NOTICING** — blink the light once, `face_toward` the player for `notice_time` 0.35 s.
- **RETURNING** — `mover.arrive` at `patrol_anchor`; reaches IDLE_ORBIT within the ring, or NOTICING again if the
  player re-enters `perceive_radius` first. Never interrupts a live DASH.

---

## Config exports

Read from `razor_drone_config.gd` / `.tres`. `razor_drone.gd`'s `_ready()` copies them onto the mover, the pattern and
the brain's matching exports.

| Export | Default | Meaning |
|---|---|---|
| `max_health` / `collision_damage` / `score_value` | 25 / 30 / 40 | `ShipConfig` basics; contact damage applies only while dashing |
| `orbit_radius` / `orbit_speed` | 130 px / 1.8 rad/s | The orbit ring and its anchor's angular speed |
| `approach_speed` | 200 px/s | ENTER and RETURN |
| `orbit_correct_speed` | 260 px/s | Orbit correction cap; must be ≥ `orbit_speed × orbit_radius` (pinned) |
| `acceleration` / `braking` / `max_turn_rate` | 900 / 700 / 6.0 | `EnemyMover` limits |
| `reverse_chance` / `reverse_seconds` | 0.35 / 0.25 s | Orbit reversal |
| `fake_chance` / `fake_windup_scale` | 0.35 / 1.5 | Feint odds; its wind-up = `windup_seconds` × this |
| `feint_lunge_speed` / `feint_lunge_seconds` / `feint_clearance_px` | 360 / 0.45 s / 70 px | The feint lunge |
| `windup_seconds` / `commit_flash_seconds` | 0.5 / 0.12 s | Yellow, then white |
| `dash_speed` / `dash_prediction_time` | 480 px/s / 0.2 s | The real dash |
| `overshoot_px` / `max_dash_seconds` | 120 px / 0.9 s | Dash length past the locked point, capped |
| `overshoot_speed` / `overshoot_turn_rate` / `overshoot_max_seconds` | 200 / 3.0 / 1.2 s | The curve; pinned `rate × speed ≤ acceleration` and ≥ 60° after shedding the dash speed |
| `pulse_damage` / `pulse_speed` | 10 / 250 | The post-miss pulse |
| `engage_seconds` / `exit_speed` | 9.0 s / 320 px/s | Assault exit. Razors spawn only in DURATION sections; `test_engagement_deadline.gd` fails if one is added to an ENEMIES_CLEARED one |
| `side_lane_min_deg` / `side_lane_max_deg` | 30 / 75 | Assault side lane |
| `idle_radius` / `idle_radius_jitter` | 160 / 40 px | Open Space patrol ring radius, redrawn ± jitter every leg |
| `idle_speed` / `idle_speed_jitter` | 0.5 / 0.2 rad/s | Open Space patrol ring angular speed, redrawn ± jitter every leg |
| `perceive_radius` / `lose_radius` | 450 / 700 px | Open Space idle: enter / drop combat (hysteresis; `lose_radius` must exceed `perceive_radius`) |
| `notice_time` | 0.35 s | Open Space idle: the NOTICING beat before combat |

---

## Spawn notes

- WaveBuilder method: `b.razor_drone()`; see `docs/enemy-roster.md`. Level 1 spawns one pair in `deep_space`.
- Spawn with `.at(x, y)` only, never `.move()`. An above-screen spawn enters through the corridor's entry rule.
- Tests: `tests/integration/test_razor_drone.gd` (the behaviour spec, most cases in both harnesses) and the Razor
  cases in `tests/integration/test_enemy_dual_mode.gd`.

---

## Files

```
razor_drone/
├── ENEMY.md                ← this file
├── razor_drone.tscn        ← CharacterBody2D + EnemyMover + Brain + ContactProfile (RAMMING) + StateLight
│                             + BulletPool + AttackController
├── razor_drone.gd          ← config copy, per-instance pulse pattern, contact_made → brain
├── razor_drone_brain.gd    ← the phase machine (EnemyBrain)
└── razor_drone_config.gd / .tres
```
