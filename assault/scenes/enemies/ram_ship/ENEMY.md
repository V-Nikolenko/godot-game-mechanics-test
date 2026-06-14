# Ram Ship — Armoured charger

**Role:** Heavy charger that dives straight down with massive contact damage. Effectively bullet-proof until a missile strips its armour, after which it's finishable.
**Fantasy / threat:** A battering ram. Shooting it with bullets does nothing until you hit it with a missile — then its armour shatters and two bullets finish it. Blocks the piercing laser while armoured.

---

## Stats

| Property | Value |
|---|---|
| HP | 999 while armoured (config); resets to 100 after the first missile hit strips armour |
| Damage | 50 (contact HitBox — `collision_damage`) |
| Speed | 100 (`movement_speed`) |
| Sprite | `ram_ship.png` (swaps to `ram_ship_damaged.png` once armour is stripped) |
| Scene | `ram_ship.tscn` |
| Config | `ram_config.tres` |

---

## Behaviour & Movement

- **Movement:** Self-driven straight-down charge in `_physics_process` (`velocity = Vector2(0, speed)`), frees itself off the bottom edge. The roster lists it as `EnemyPathMover`-driven via `.move()` (which would suspend this self-charge).
- **Attack:** No projectiles — high contact damage only (50). Contact HitBox damage set from `collision_damage`.
- **Armour gimmick:** `hurt_box.collision_mask = 33` initially (missiles only — bullets pass through). The first `received_damage` triggers `_enter_damaged_state()` instead of dealing damage: swaps to the damaged sprite, opens the hurtbox to bullets (`collision_mask = 97`), and resets HP to 100 so two bullets finish it. `is_laser_blocking()` returns true until armour is stripped.
- **Death / scoring:** Joins group `ram_ships` (not the standard contact-hitbox flow). Awards `score_value` 35.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `999` | Armoured HP (practically unkillable by bullets; reset to 100 on armour strip). |
| `collision_damage` | `50` | Contact HitBox damage. |
| `score_value` | `35` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `movement_speed` | `100.0` | Downward charge speed. |

(Read the real defaults from `ram_config.gd` and `ram_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.ram()` — see `docs/enemy-roster.md`. The roster says to add `.move()`.
- Use as a forced-missile target / lane blocker. Common patterns: straight dive, angled pairs from the sides, or a surprise charge from below.

---

## Files

```
ram_ship/
├── ENEMY.md            ← this file
├── ram_ship.tscn
├── ram_ship.gd
└── ram_config.gd / .tres
```
