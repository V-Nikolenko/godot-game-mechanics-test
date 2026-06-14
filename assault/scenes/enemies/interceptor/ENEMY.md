# Interceptor — Flying Gatling gunship

**Role:** Path-following strafer that hoses a rapid stream of slightly-scattered bullets in its direction of travel.
**Fantasy / threat:** A buzzsaw of low-damage rounds. Individually each shot is trivial, but the 11-shots-per-second stream punishes anyone sitting in its lane.

---

## Stats

| Property | Value |
|---|---|
| HP | 70 |
| Damage | 20 contact (`collision_damage`, default ShipConfig — not overridden in `.tres`) / 4 per bullet (`bullet_damage`) |
| Speed | n/a internally — movement is fully delegated to the `.move()` path |
| Sprite | `interceptor.png` |
| Scene | `interceptor.tscn` |
| Config | `interceptor_config.tres` |

---

## Behaviour & Movement

- **Movement:** Fully delegated to `EnemyPathMover` via the WaveBuilder `.move()` call — no self-managed movement AI. Typically `b.straight()` (strafing run) or `b.player_focus()` (lock-on dive).
- **Attack:** `AttackController` driving a `GatlingAttackPattern` (built in `_ready()`): `fire_interval` 0.09 s (~11 shots/s), `bullet_damage` 4, `bullet_speed` 220, `spread_angle` 0.08 rad (±~4.5° scatter). Bullets pooled (`BulletPool`, size 20). Fires forward in the direction of travel.
- **Death / scoring:** Awards `score_value` 75 on kill. Freed by `EnemyPathMover` on screen exit.

---

## Config exports

| Export | Default (`.gd`) | `.tres` override | Meaning |
|---|---|---|---|
| `max_health` | `100` (ShipConfig) | `70` | HP. |
| `collision_damage` | `20` (ShipConfig) | — (default) | Contact HitBox damage. |
| `score_value` | `0` (ShipConfig) | `75` | Points on kill. |
| `counts_toward_wave_clear` | `true` | — | Counts toward wave-clear bonus. |
| `fire_interval` | `0.09` | — | Seconds between shots (~11/s). |
| `bullet_damage` | `4` | — | Per-bullet damage. |
| `bullet_speed` | `220.0` | — | Bullet speed (px/s); lower = shorter range. |
| `spread_angle` | `0.08` | — | Max random scatter per shot (rad, ≈±4.5°). |

(Read the real defaults from `interceptor_config.gd` and `interceptor_config.tres`. The `.tres` only overrides `max_health` and `score_value`; all other fields use the script defaults.)

---

## Spawn notes

- WaveBuilder method: `b.interceptor()` — see `docs/enemy-roster.md`. **Always add `.move()`.**
- `b.player_focus(240)` for a lock-on dive; `b.straight(200, PI/2).free_after(5.0)` for a side strafing run.

---

## Files

```
interceptor/
├── ENEMY.md            ← this file
├── interceptor.tscn
├── interceptor.gd
└── interceptor_config.gd / .tres
```
