# Bonus Drone — Rare medal target

**Role:** Fast, fragile, non-shooting flyby worth a big score chunk. Optional reward, not a real threat.
**Fantasy / threat:** A gold-tinted prize streaking across the screen — shoot it fast or it's gone. Missing it costs nothing; killing it pays out.

---

## Stats

| Property | Value |
|---|---|
| HP | 1 |
| Damage | 0 (no contact HitBox — `_add_contact_hitbox()` is overridden to do nothing) |
| Speed | 280 (`movement_speed`; effective speed comes from the `.move()` path) |
| Sprite | `drone.png` (gold modulate, 1.5× scale) |
| Scene | `bonus_drone.tscn` |
| Config | `bonus_drone_config.tres` |

---

## Behaviour & Movement

- **Movement:** Fully delegated to `EnemyPathMover` via the WaveBuilder `.move()` call — no internal physics. Typically a fast horizontal `StraightMovement` with `free_after`.
- **Attack:** None. Does not shoot and deals no contact damage.
- **Death / scoring:** Dies to a single hit (1 HP). Awards `score_value` 500 but `counts_toward_wave_clear = false`, so missing it does NOT block wave-clear bonuses.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `1` | One-shot kill. |
| `collision_damage` | `0` | No contact damage (and no contact HitBox is added). |
| `score_value` | `500` | Large bonus payout. |
| `counts_toward_wave_clear` | `false` | Excluded from wave-clear bonus accounting. |
| `movement_speed` | `280.0` | Nominal speed (actual path speed set by `.move()`). |

(Read the real defaults from `bonus_drone_config.gd` and `bonus_drone_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.bonus_drone()` — see `docs/enemy-roster.md`.
- Normally spawned from `level_director.gd` via `_spawn_bonus_drone()`, not from wave lists. Standard offsets: `Vector2(-680, 60)` (left-to-right) or `Vector2(680, 60)` (right-to-left), with `free_after(4.0)`.

---

## Files

```
bonus_drone/
├── ENEMY.md            ← this file
├── bonus_drone.tscn
├── bonus_drone.gd
└── bonus_drone_config.gd / .tres
```
