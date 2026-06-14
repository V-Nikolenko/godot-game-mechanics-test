# Drone Interceptor — Kamikaze orbiter

**Role:** Self-managed pursuit drone. Closes on the player, circles briefly, then commits to a one-way predictive dash that explodes on contact.
**Fantasy / threat:** A wasp that won't be shaken — it stalks, winds up an orbit, then lances at where you're *about* to be. Must be killed before it commits.

---

## Stats

| Property | Value |
|---|---|
| HP | 25 |
| Damage | 30 (contact HitBox — kamikaze on player contact) |
| Speed | 200 approach / 480 dash (`approach_speed` / `dash_speed`) |
| Sprite | `drone_2.png` |
| Scene | `drone_interceptor.tscn` |
| Config | `drone_interceptor_config.tres` |

---

## Behaviour & Movement

- **Movement:** ⚠️ Self-managed AI in `_physics_process` (`move_and_slide`). Do NOT attach `.move()` — `EnemyPathMover` would call `set_physics_process(false)` and break the brain. Three phases: ENTER → ORBIT → DASH.
- **Attack:** No projectiles. Its contact HitBox uses `collision_mask = 128` (player HurtBox); on contact it sets its own health to 0 (kamikaze), dealing `collision_damage` 30.
- **Death / scoring:** Dies on contact or when shot down (25 HP). Awards `score_value` 40. The DASH flies indefinitely until it hits the player or leaves the screen (+80 px margin).

---

## State Graph

```
        within orbit_radius
ENTER ──────────────────────▶ ORBIT ──dash_timer (1–2 s) expires──▶ DASH
  │                              │                                     │
fly at approach_speed      circle player,                       lock predicted dir,
toward player              correct toward ring                  fly at dash_speed →
```

**Initial phase:** `ENTER`

> Note: phases are an `enum` inside `drone_interceptor.gd` (not separate `State` node files); there is no `states/` folder.

### ENTER
- Flies straight at the player at `approach_speed`.
- When distance ≤ `orbit_radius`, transitions to ORBIT.

### ORBIT
- Counts down a randomised `_dash_timer` (1.0–2.0 s, set on spawn).
- Advances `_orbit_angle` by `orbit_speed`, steers toward the orbit ring (correction speed clamped to `orbit_correct_speed`).
- When `_dash_timer ≤ 0` → DASH.

### DASH
- On entry, locks `_dash_direction` toward the player's predicted position (`player.velocity * dash_prediction_time`).
- Flies at `dash_speed` indefinitely; freed by the off-screen check. Kamikazes on player contact.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `25` | HP. |
| `collision_damage` | `30` | Kamikaze contact damage. |
| `score_value` | `40` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `orbit_radius` | `130.0` | Preferred distance from player while orbiting (px). |
| `orbit_speed` | `1.8` | Orbit angular velocity (rad/s, counter-clockwise). |
| `approach_speed` | `200.0` | Speed during ENTER (px/s). |
| `orbit_correct_speed` | `160.0` | Max correction speed during ORBIT (px/s). |
| `dash_speed` | `480.0` | Burst speed during DASH (px/s). |
| `dash_prediction_time` | `0.2` | Seconds ahead to predict player position. |

(Read the real defaults from `drone_interceptor_config.gd` and `drone_interceptor_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.drone_interceptor()` — see `docs/enemy-roster.md`.
- ⚠️ Spawn with `.at(x, y)` only — never `.move()`. Stagger orbit angle/dash timers are randomised so clusters don't behave identically.

---

## Files

```
drone_interceptor/
├── ENEMY.md            ← this file
├── drone_interceptor.tscn
├── drone_interceptor.gd
└── drone_interceptor_config.gd / .tres
```
