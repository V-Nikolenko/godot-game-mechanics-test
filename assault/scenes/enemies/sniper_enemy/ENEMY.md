# Sniper Enemy — Hovering marksman

**Role:** Flies into position, hovers, and fires a series of slow telegraphed aimed shots with a charging red laser-sight, then retreats. Carried in and out by its movement path.
**Fantasy / threat:** A patient sniper. Each shot is broadcast by a converging red line, so it's about reading the tell and sidestepping — but it keeps coming back for `shot_count` shots.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 (from `sniper_enemy.tscn` Health node — no config file exists) |
| Damage | 20 contact (BaseEnemy default contact HitBox; no `collision_damage` config) / sniper bullet damage per `enemy_sniper_bullet.tscn` |
| Speed | n/a internally — movement is supplied by the `.move()` sequence path |
| Sprite | `sniper.png` |
| Scene | `sniper_enemy.tscn` |
| Config | n/a — there is no `sniper_enemy_config` resource; tuning lives as constants/exports in `sniper_enemy.gd` |

---

## Behaviour & Movement

- **Movement:** Carried by `EnemyPathMover` using a **sequence** movement (fly in → hold → fly out). The approach step must be `straight(speed, 0.0, 2.5)` to match `FLY_IN_TIME = 2.5 s`. Logic runs in `_process()` (not `_physics_process`, which `EnemyPathMover` disables) so its rotation always wins.
- **Attack:** Fires `enemy_sniper_bullet.tscn` from the `Muzzle` marker. Cycles AIM (2.0 s, red sight converges via `SniperAimVisualizer`) → LOCK (0.5 s, line brightens, rotation frozen) → FIRE, repeating until `shot_count` shots are fired.
- **Death / scoring:** `score_value` is set to 50 in `_ready()` (no config). After all shots, enters IDLE and lets the path's exit step retreat it.

---

## State Graph

```
APPROACH ──FLY_IN_TIME (2.5 s)──▶ AIM ──2.0 s──▶ LOCK ──0.5 s──▶ FIRE
              (nose-down)          ▲                                │
                                   └──── shots_fired < shot_count ──┘
                                                                    │ shots_fired == shot_count
                                                                    ▼
                                                                  IDLE  (path retreats it out)
```

**Initial phase:** `APPROACH`

> Note: phases are an `enum` inside `sniper_enemy.gd`, not separate `State` node files — there is no `states/` folder. Constants are listed below.

### APPROACH
- Holds `rotation = PI` (nose-down) against `EnemyPathMover`. After `FLY_IN_TIME` (2.5 s) → AIM.

### AIM
- Lerp-rotates to track the player (`ROTATION_LERP` 4.0); the single-line `SniperAimVisualizer` charges over `AIM_DURATION` (2.0 s) → LOCK.

### LOCK
- Rotation frozen; sight held bright for `LOCK_DURATION` (0.5 s) → FIRE.

### FIRE
- Spawns one sniper bullet along current facing, frees the visualizer, increments `_shots_fired`. Loops back to AIM until `shot_count` met, then IDLE.

### IDLE
- Does nothing; `EnemyPathMover`'s exit step retreats the ship.

---

## Config exports

| Export / constant | Default | Meaning |
|---|---|---|
| `shot_count` (export) | `5` | Shots fired before going idle. Override via `.prop("shot_count", N)`. |
| `AIM_DURATION` (const) | `2.0` | Seconds the aim sight converges. |
| `LOCK_DURATION` (const) | `0.5` | Seconds the lock is held before firing. |
| `ROTATION_LERP` (const) | `4.0` | How fast it lerp-rotates to track the player. |
| `FLY_IN_TIME` (const) | `2.5` | Approach duration; must match the path's fly-in step. |
| `score_value` (set in `_ready()`) | `50` | Points on kill. |

(No `.tres`/`.gd` config resource exists — values read directly from `sniper_enemy.gd`. HP 60 comes from the `.tscn` Health node.)

---

## Spawn notes

- WaveBuilder method: `b.sniper_enemy()` — see `docs/enemy-roster.md`. Must use a `sequence()`: `straight(150, 0.0, 2.5)` fly-in (exactly 2.5 s), `hold(shot_count × 2.5)`, then a retreat `straight()`.
- Hold formula: `shot_count × 2.5 s` minimum (5 shots → `hold(13.0)`; 3 shots → `hold(7.5)`).

---

## Files

```
sniper_enemy/
├── ENEMY.md            ← this file
├── sniper_enemy.tscn
└── sniper_enemy.gd
```
