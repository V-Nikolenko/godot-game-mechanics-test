# Bomber — Horizontal bomb-dropper

**Role:** Crosses the screen horizontally and rains gravity bombs onto the player's lane, forcing repositioning.
**Fantasy / threat:** A slow, fat target that's easy to shoot — but ignore it and the bombs it leaves behind will catch you. Area denial on a timer.

---

## Stats

| Property | Value |
|---|---|
| HP | 150 (from `bomber_config.tres`; the `.tscn` Health default of 250 is overwritten in `_ready()`) |
| Damage | 35 contact (collision HitBox) / 40 per bomb (`bomb.tscn` HitBox) |
| Speed | 80 (`movement_speed`) |
| Sprite | `bomber.png` |
| Scene | `bomber.tscn` |
| Config | `bomber_config.tres` |

---

## Behaviour & Movement

- **Movement:** Self-managed in `_physics_process` — constant horizontal velocity `Vector2(direction * speed, 0)` (`direction` 1 = left-to-right, -1 = right-to-left). Frees itself when it passes the horizontal screen edge (+70 px margin). Despite the roster listing it as `EnemyPathMover`-driven, the script drives its own horizontal sweep; attaching `.move()` would suspend this via `set_physics_process(false)`.
- **Attack:** Drops a `bomb.tscn` every `bomb_interval` (1.2 s) via a child `Timer` (fires independently of `_physics_process`). Each bomb falls at 120 px/s, auto-detonates after a 5 s fuse, or detonates 1 s after the player enters its 80-px proximity ring; the explosion HitBox deals 40 damage for 0.15 s.
- **Death / scoring:** On HP 0, `BaseEnemy` emits `died`, plays explosion, awards `score_value` 80. Bombs already dropped persist and fall independently.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `150` | HP (overrides the scene Health node). |
| `collision_damage` | `35` | Contact HitBox damage. |
| `score_value` | `80` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `movement_speed` | `80.0` | Horizontal sweep speed. |
| `bomb_interval` | `1.2` | Seconds between bomb drops. |

(Read the real defaults from `bomber_config.gd` and `bomber_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.bomber()` — see `docs/enemy-roster.md`.
- The roster examples pair it with a `.move()` and escort drones; in practice the script also self-drives a horizontal pass. Use as a slow area-denial threat that the player must clear before its bombs accumulate.

---

## Files

```
bomber/
├── ENEMY.md            ← this file
├── bomber.tscn
├── bomber.gd
├── bomber_config.gd / .tres
├── bomb.tscn
└── bomb.gd
```
