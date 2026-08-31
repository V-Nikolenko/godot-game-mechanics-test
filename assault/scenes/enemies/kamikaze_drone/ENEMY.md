# Kamikaze Drone — Disposable rusher

**Role:** Cheap, fast, non-shooting drone that locks a straight-line heading at spawn and rams the player.
**Fantasy / threat:** Swarm fodder. Any single one is trivial, but they come in formations and clusters to force constant dodging.

---

## Stats

| Property | Value |
|---|---|
| HP | 30 (from `drone_config.tres`; the `.tscn` Health default of 40 is overwritten in `_ready()`) |
| Damage | 30 (contact HitBox — kamikaze on player contact) |
| Speed | 140 (`movement_speed`; effective speed comes from the `.move()` path) |
| Sprite | `drones.png` (random 1-of-6 region variant per spawn) |
| Scene | `kamikaze_drone.tscn` |
| Config | `drone_config.tres` |

---

## Behaviour & Movement

- **Movement:** The script self-drives a straight heading: on spawn it points `_direction` at the player and translates `global_position` each frame in `_physics_process`. In wave use it is driven by `EnemyPathMover` via `.move()` (which suspends `_physics_process`); the roster lists it as path-following. Frees itself off the bottom edge.
- **Attack:** None — kamikaze only. Its contact HitBox uses `collision_mask = 128` (player HurtBox) and hardcodes `damage = 30`; on contact it sets its own health to 0.
- **Death / scoring:** Dies to contact or one burst of fire (30 HP). Awards `score_value` 10.

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `30` | HP (overrides the scene Health node). |
| `collision_damage` | `30` | Contact damage (note: the contact HitBox hardcodes `damage = 30` in code). |
| `score_value` | `10` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `movement_speed` | `140.0` | Self-driven speed (irrelevant when `.move()` is attached). |

(Read the real defaults from `drone_config.gd` and `drone_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.drone()` — see `docs/enemy-roster.md`. **Always add `.move()`.**
- Common patterns: `b.sine()` weave, staggered `b.straight()` dives, `b.cluster_formation()` rushes, or `b.straight(185, PI)` from below.

---

## Files

```
kamikaze_drone/
├── ENEMY.md            ← this file
├── kamikaze_drone.tscn
├── kamikaze_drone.gd
└── drone_config.gd / .tres
```
