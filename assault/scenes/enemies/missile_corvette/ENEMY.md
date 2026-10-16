# Missile Corvette — medium-range rocket launcher

**Role:** Holds medium range on broad arcs and fires predicted rocket salvos from two nose tubes (Dumb, Pursuit, Cluster, Delayed Warhead).
**Fantasy / threat:** A wide, slow gunboat whose threat is its ordnance, not its hull — every rocket can be outrun, out-turned or shot down.

> **Build state (Phase 5, in progress).** t7 (this file's content) built the **shell**: scene, config, four rocket pools, `fire()`,
> the launcher answers, a minimal brain (APPROACH + Assault budget → DISENGAGE) and the rail fallback. Still to come: the
> fight itself — HOLD_ARC / TELEGRAPH / SALVO (t8), the real sprite (t9), the hub idle (t15), the hub patrol (t16) and level 1 (t17).
> Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.9 (rockets: §2.6–§2.8). Decisions: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` ("t7 as built").

---

## Stats

| Property | Value |
|---|---|
| HP | 160 (`missile_corvette_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 30 contact (`ContactHitBox`, COLLISION); rockets deal their own impact / blast damage |
| Speed | `max_speed` 210, `acceleration` 240, `max_turn_rate` 1.2 |
| Body | one `CircleShape2D` r 40 shared by the body, `HurtBox` and `ContactHitBox` |
| Sprite | placeholder (`ram_corvette.png`) until t9; nose-down (`sprite_forward_angle = PI / 2`) |
| Scene / config | `missile_corvette.tscn` / `missile_corvette_config.tres` (flat `MissileCorvetteConfig`) |

---

## Behaviour

- **Brain:** `MissileCorvetteBrain` (`Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }`, `enter_phase()` seam,
  `start_engaged` test seam). t7 plays APPROACH (`arrive` at `held_range()` = `preferred_range` 620 in Open Space, `assault_preferred_range` 460 in
  Assault, along the line to the player) and DISENGAGE (Assault budget `engage_seconds` 7.0 → release the corridor, curve out at `exit_speed` 280, freed
  outside the projectile rect). `accepts_tow()` already refuses TELEGRAPH / SALVO.
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
| `min_range`, `range_drift`, `range_tolerance` | 380, 80, 120 | Fight tuning for t8 |
| `orbit_angular_speed`, `reversal_min/max` | 0.22, 4.0–7.0 | The broad arc (t8) |
| `launch_cone_deg`, `salvo_telegraph`, `salvo_count`, `warhead_salvo_count`, `salvo_gap`, `salvo_period_min/max`, `salvo_lead_step`, `warhead_offset`, `warhead_range`, `cluster_min_range`, `pursuit_flee_speed` | 45, 0.7, 3, 2, 0.22, 4.0–5.0, 0.25, 90, 420, 700, 300 | Salvo tuning (t8); the counts and `salvo_period_min` size the pools today |
| `engage_seconds` / `exit_speed` | 7.0 / 280 | Assault budget and exit speed |
| `rail_rocket_interval` | 2.5 s | Rail fallback rate |

---

## Spawn notes

- WaveBuilder method: `b.missile_corvette()` (const `MISSILE_CORVETTE`) — see `docs/enemy-roster.md`. Not in any wave yet (t17 for level 1).

---

## Files

```
missile_corvette/
├── ENEMY.md
├── missile_corvette.tscn / .gd           MissileCorvette (fire, launch_velocity, rocket_clear_radius, rail fallback)
├── missile_corvette_brain.gd             MissileCorvetteBrain
└── missile_corvette_config.gd / .tres    MissileCorvetteConfig
```
