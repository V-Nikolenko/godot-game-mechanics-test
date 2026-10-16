# Missile Corvette — medium-range rocket launcher

**Role:** Holds medium range on broad arcs and fires predicted rocket salvos from two nose tubes (Dumb, Pursuit, Cluster, Delayed Warhead).
**Fantasy / threat:** A wide, slow gunboat whose threat is its ordnance, not its hull — every rocket can be outrun, out-turned or shot down.

> **Build state (Phase 5, in progress).** t7 built the **shell** (scene, config, four rocket pools, `fire()`, the launcher
> answers, the rail fallback); t8 built the **fight** (HOLD_ARC, the launch cone, TELEGRAPH, SALVO, predicted aim points, the
> Assault gate and deferral). t9 gave it its real hull sprite and the rocket sprites. t15 gave it the **hub idle** (IDLE / NOTICING / RETURNING). Still to come: the hub patrol (t16) and level 1 (t17).
> Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.9–§2.10 (rockets: §2.6–§2.8); t8's own build plan
> `docs/plans/cmv9szqlq001zqs2x6vi0nlxj/3-plan.md`. Decisions: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` ("t7 as built", "t8 as built").

---

## Stats

| Property | Value |
|---|---|
| HP | 160 (`missile_corvette_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 30 contact (`ContactHitBox`, COLLISION); rockets deal their own impact / blast damage |
| Speed | `max_speed` 210, `acceleration` 240, `max_turn_rate` 1.2 |
| Body | one `CircleShape2D` r 40 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | `missile_corvette.png` (96 x 96, PixelLab hull + hand-drawn launch tubes at the `Tubes/TubeL` / `TubeR` markers; the `TubeLight*` lamps are separate code-glow sprites); nose-down (`sprite_forward_angle = PI / 2`) |
| Scene / config | `missile_corvette.tscn` / `missile_corvette_config.tres` (flat `MissileCorvetteConfig`) |

---

## Behaviour

- **Brain:** `MissileCorvetteBrain` (`Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }`, `enter_phase()` seam,
  `start_engaged` and `force_next_kind(kind)` test seams). The held range `R` (`held_range()`) is `preferred_range` 620 in Open Space and
  `assault_preferred_range` 460 in Assault.
  - **Hub idle (t15, Open Space only):** `AnchorIdle` runs ahead of the phase dispatch. IDLE = a slow `idle_radius` ring orbit round `patrol_anchor` (default: the spawn point), no salvo; NOTICING = stop and face the player for `notice_time` (the salvo clock restarts), then APPROACH; RETURNING = `arrive` at the anchor then IDLE. RETURNING (and every other idle change) is **never taken during TELEGRAPH or SALVO**, it is retried each tick, so a started salvo always lands. `start_engaged` skips the idle (tests; Assault ignores it and builds no `AnchorIdle`).
  - **APPROACH:** `arrive` at `R` along the line to the player; HOLD_ARC once within `range_tolerance` 120 of it.
  - **HOLD_ARC (broad arcs):** `Steering.orbit` about the player at `R + drift` (drift = `range_drift` 80 × a sine of rng period 6–9 s, starting
    at 0), `orbit_angular_speed` 0.22 rad/s, `orbit_dir` ±1 flipped every rng 4–7 s. Inside `min_range` 380 it adds
    `Steering.break_contact` with side `-orbit_dir` (the sense the arc turns) until back outside, then re-syncs the orbit to its bearing. The
    nose tracks the player through `face_toward` at 1.2 rad/s, independent of travel.
  - **Launch cone:** a salvo starts only with the player within `launch_cone_deg / 2` (22.5°) of the nose and `salvo_cooldown` (rng
    `salvo_period_min`–`max`, 4–5 s, from spawn and after each salvo) run out. Get behind it faster than it turns and it cannot shoot.
  - **Kind:** `choose_kind(distance, player_speed, radial_speed)`: closer than `warhead_range` 420 → WARHEAD; fleeing at ≥ `pursuit_flee_speed`
    300 → PURSUIT; beyond `cluster_min_range` 700 and crossing → CLUSTER; else DUMB, swapped for PURSUIT one time in four (rng).
    `salvo_size(kind)`: 2 Warheads, else 3 rockets.
  - **TELEGRAPH** (`salvo_telegraph` 0.7 s): `StateLight` CHARGING, tube lamps ramp 0 → 1, arc at half speed. Open Space cancels it if the player
    gets more than 45° off the nose; Assault never does.
  - **SALVO:** a `BurstClock` of `salvo_size` rockets `salvo_gap` 0.22 s apart, the first on the telegraph's last tick; `StateLight` ARMED, lamps
    flash per launch. Aim points: DUMB rocket *i* at `predicted_position(intercept time + i × salvo_lead_step 0.25)` (a line along the player's
    path); PURSUIT / CLUSTER at the intercept point; WARHEAD *i* at the intercept point ± `warhead_offset` 90 across the player's path (fixed
    once per salvo), a pair 180 px apart. Then HOLD_ARC, light OFF. Never COMMIT.
  - **DISENGAGE (Assault):** budget `engage_seconds` 7.0 → release the corridor, curve out at `exit_speed` 280, freed outside the projectile
    rect. A started TELEGRAPH / SALVO finishes first (≤ `attack_window()` 1.14 s); a TELEGRAPH starts only with `budget.remaining() >=
    attack_window() + 0.05`.
  - **Tow:** `accepts_tow()` is false in TELEGRAPH and SALVO, so an ally never moves it while its tubes glow or fire.
- **Launcher API:** `MissileCorvette.fire(kind, aim_point) -> EnemyRocket` takes a rocket from that kind's pool at the next tube (`Tubes/TubeL`, `TubeR`,
  local (±18, 30), alternating) and calls `launch(dir, aim_point, self)`. It sets **no** rocket field; arming, speeds and damage are the rocket's own.
  Null (counted in `rockets_refused`) when the pool is exhausted. `launch_velocity()` is `velocity` under AI and the position change observed per physics
  tick (`SceneTree.physics_frame`) while a rail drives it; `rocket_clear_radius()` is 40, so a rocket arms only once clear of the hull.
- **Pools:** `DumbPool` 3, `PursuitPool` 6, `ClusterPool` 3, `WarheadPool` 4 — direct root children, `persist_after_owner_death`, sized by
  `EnemyRocketScenes.pool_size_for(kind, config)`; rockets in flight outlive the corvette.
- **Rail fallback:** while a rail owns it (`is_ai_suspended()`), a root `_process` clock fires a Dumb rocket straight DOWN every `rail_rocket_interval` 2.5 s.
- **Death / scoring:** score 70, standard `BaseEnemy` death. Rockets are never in group `enemies` and never scored.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_speed` / `acceleration` / `max_turn_rate` | 210 / 240 / 1.2 | Mover caps; the rocket scenes' launcher inequalities are checked against the first two |
| `preferred_range` / `assault_preferred_range` | 620 / 460 | Held range, Open Space / Assault |
| `min_range`, `range_drift`, `range_tolerance` | 380, 80, 120 | Range: held ring, inner limit (break-off), drift of the ring, APPROACH → HOLD_ARC hand-over |
| `orbit_angular_speed`, `reversal_min/max` | 0.22, 4.0–7.0 | The broad arc: angular speed, reversal interval |
| `launch_cone_deg`, `salvo_telegraph`, `salvo_count`, `warhead_salvo_count`, `salvo_gap`, `salvo_period_min/max`, `salvo_lead_step`, `warhead_offset`, `warhead_range`, `cluster_min_range`, `pursuit_flee_speed` | 45, 0.7, 3, 2, 0.22, 4.0–5.0, 0.25, 90, 420, 700, 300 | Salvo: cone, telegraph, counts, gap, period, Dumb lead step, Warhead spread and range, Cluster range, Pursuit flee speed; the counts and `salvo_period_min` also size the pools |
| `engage_seconds` / `exit_speed` | 7.0 / 280 | Assault budget and exit speed |
| `rail_rocket_interval` | 2.5 s | Rail fallback rate |
| `perceive_radius` / `lose_radius` / `notice_time` / `idle_radius` / `idle_speed` | 720 / 1500 / 0.35 / 150 / 0.5 | Hub idle (Open Space, t15): notice the player inside 720 px, go home beyond 1500 (> `preferred_range + range_drift + range_tolerance` = 820), the patrol ring |

---

## Spawn notes

- WaveBuilder method: `b.missile_corvette()` (const `MISSILE_CORVETTE`) — see `docs/enemy-roster.md`. Not in any wave yet (t17 for level 1).

---

## Files

```
missile_corvette/
├── ENEMY.md
├── missile_corvette.tscn / .gd           MissileCorvette (fire, launch_velocity, rocket_clear_radius, rail fallback)
├── missile_corvette_brain.gd             MissileCorvetteBrain (APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE)
└── missile_corvette_config.gd / .tres    MissileCorvetteConfig
```
