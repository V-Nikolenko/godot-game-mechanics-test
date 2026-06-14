# Small Asteroid — The shard

**Role / threat:** A small, fragile obstacle. It exists both as a wave-spawned hazard in its own right and as the shrapnel a `BigAsteroid` throws off when destroyed. It has no speed-scaled one-shot — its contact damage is a flat 30 — so it is a chip-damage and clutter threat rather than an instant kill. When spawned as a split shard it drives its own movement via `drift_velocity` and self-frees once it leaves the screen. It awards 5 points when killed.

---

## Stats

| Property | Value |
|---|---|
| HP | 40 (`health_amount`) |
| Contact damage | 30 (flat; `one_shot_speed_threshold` = 0.0, no speed scaling) |
| Score value | 5 |
| Body / hurt / contact radius | 14.0 px (CircleShape2D each) |
| Movement | `drift_velocity` (split shards) or `EnemyPathMover` (wave-spawned) |
| On death | n/a (no split) |
| Sprite | `small_asteroid_tileset.png` (4×3 grid of 33×33 tiles, one picked at random) |
| Scene | `small_asteroid.tscn` |

---

## Behaviour

**Spawning & movement.** `SmallAsteroid` extends the shared `asteroid_base.gd`. Two spawn paths exist:
- **Split shard:** a `BigAsteroid` sets `drift_velocity` on spawn. Each `_physics_process` the asteroid adds `drift_velocity * delta` directly to `global_position`, deliberately bypassing `move_and_slide()` so it keeps moving regardless of physics-layer setup.
- **Wave-spawned:** `drift_velocity` is left at zero, and an external `EnemyPathMover` (as on the big asteroid scene) drives its position. In this branch the script falls back to `move_and_slide()`.

After moving, `_check_off_screen()` queries the active `Camera2D` and `queue_free()`s the asteroid once it passes more than `_OFF_SCREEN_MARGIN` (80 px) beyond any edge of the visible rect — so escaped shards do not linger. Because the base class only sets `was_killed = true` on a health-zero death, an off-screen free counts as an escape, not a kill, for `ScoreTracker`.

**On contact.** The `ContactHitBox` (layer 1024, `DamageType.CONTACT`) deals a flat 30. With `one_shot_speed_threshold` at 0.0 the base class never overrides this value, so there is no speed-scaled one-shot.

**How it is destroyed.** Its `HurtBox` (layer 512, mask 96) feeds hits into `Health`. At 0 HP the base class explodes, marks `was_killed`, emits `died`, runs `_on_destroyed()` (a no-op here — small asteroids do not split further) and frees the node.

---

## Files

```
small_asteroid/
├── HAZARD.md             ← this file
├── small_asteroid.gd     ← SmallAsteroid: drift movement + off-screen culling
└── small_asteroid.tscn   ← scene: CharacterBody2D + Health/HurtBox/ContactHitBox
```

Inherits shared behaviour from `../asteroid_base.gd` (random sprite, contact damage, death handling).
