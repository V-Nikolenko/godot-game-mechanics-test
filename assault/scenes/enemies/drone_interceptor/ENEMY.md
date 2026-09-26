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

- **Movement:** ⚠️ Self-managed AI, on the shared brain/mover architecture
  (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.11) — the first enemy ported onto it.
  `DroneInterceptorBrain` (a child `EnemyMover`-sibling `EnemyBrain`) decides; a sibling
  `EnemyMover` (`acceleration = 0`, `turn_lerp = 7`, `constraint_mode = NONE`) turns that into
  `velocity`/`move_and_slide()`/facing, via the shared `BaseEnemy._physics_process` tick loop —
  `drone_interceptor.gd` itself defines no `_physics_process` any more. `constraint_mode = NONE`
  means it ignores the Assault corridor even when one exists, keeping it 1:1 with its pre-Phase-1
  behaviour; Phase 2's Razor Drone is the one that turns the corridor on. Do NOT attach `.move()`
  — `EnemyPathMover` suspends the brain (`BaseEnemy.suspend_ai()`) exactly like any other
  brain-driven enemy, which defeats the point of a self-managed kamikaze. Three phases: ENTER →
  ORBIT → DASH, using `Steering.seek` / `Steering.orbit` and `TargetInfo.player()` for perception
  and dash prediction.
- **Attack:** No projectiles. Its contact HitBox uses `collision_mask = 128` (player HurtBox); on contact it sets its own health to 0 (kamikaze), dealing `collision_damage` 30.
- **Death / scoring:** Dies on contact or when shot down (25 HP). Awards `score_value` 40. The DASH
  flies until it leaves the world: in Assault, the legacy off-screen cull (camera ± viewport/2 ±
  80 px, via `ArenaCamera.enemy_cull_rect()`); in Open Space (no `ArenaCamera` in the tree), the new
  `dash_max_distance` (1600 px) travelled from the dash's own start.

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

> Note: phases are an `enum` inside `drone_interceptor_brain.gd` (not separate `State` node
> files); there is no `states/` folder. IDEAS §4's shared vocabulary (documented in
> `global/enemy_ai/enemy_brain.gd`): ENTER = APPROACH, ORBIT = POSITION, DASH = ATTACK.

### ENTER (`drone_interceptor_brain.gd`)
- Flies straight at the player at `approach_speed` (`Steering.seek`).
- When distance ≤ `orbit_radius`, transitions to ORBIT.

### ORBIT (`drone_interceptor_brain.gd`)
- Counts down a randomised `_dash_timer` (1.0–2.0 s, drawn from `brain.rng` at spawn, so a seeded
  run is reproducible).
- Advances `_orbit_angle` by `orbit_speed`, steers toward the orbit ring (`Steering.orbit`,
  correction speed clamped to `[60, orbit_correct_speed]`).
- When `_dash_timer ≤ 0` → DASH.

### DASH (`drone_interceptor_brain.gd`)
- On entry, locks `_dash_direction` toward `TargetInfo.player().predicted_position(dash_prediction_time)`
  (straight down with no player).
- Flies at `dash_speed`. Freed once it leaves the world: the Assault provider's legacy off-screen
  cull rect when there is one (`ArenaCamera.enemy_cull_rect()`), else `dash_max_distance` travelled
  from the dash's own start (Open Space). Kamikazes on player contact.

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
| `dash_max_distance` | `1600.0` | Open Space only (no Assault provider): DASH frees the drone this far from where it began. |

(Read the real defaults from `drone_interceptor_config.gd` and `drone_interceptor_config.tres` —
copied onto `DroneInterceptorBrain`'s own matching `@export`s by `drone_interceptor.gd`'s `_ready()`.)

---

## Spawn notes

- WaveBuilder method: `b.drone_interceptor()` — see `docs/enemy-roster.md`.
- ⚠️ Spawn with `.at(x, y)` only — never `.move()`. Stagger orbit angle/dash timers are randomised so clusters don't behave identically.

---

## Files

```
drone_interceptor/
├── ENEMY.md                    ← this file
├── drone_interceptor.tscn      ← CharacterBody2D + EnemyMover + Brain children
├── drone_interceptor.gd        ← wires config onto the brain; contact-kill only
├── drone_interceptor_brain.gd  ← ENTER/ORBIT/DASH decision logic (EnemyBrain)
└── drone_interceptor_config.gd / .tres
```
