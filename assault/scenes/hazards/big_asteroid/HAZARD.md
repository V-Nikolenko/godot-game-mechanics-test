# Big Asteroid — The splitting boulder

**Role / threat:** A large, durable obstacle that drifts down the play-field along an `EnemyPathMover` path. It is a momentum threat first and foremost: at or above its `one_shot_speed_threshold` of 150 px/s it deals 9999 contact damage (an instant kill), so flying into a fast-moving big asteroid is fatal. Even destroyed, it is dangerous — on death it shatters into 2–4 small asteroid shards that inherit its travel direction, turning one slow threat into a spreading cone of faster ones. It awards 15 points when killed.

---

## Stats

| Property | Value |
|---|---|
| HP | 100 (inherited `health_amount` default) |
| Contact damage | 40 base; 9999 (one-shot) at speed ≥ 150 px/s |
| Score value | 15 |
| Body / hurt / contact radius | 28.0 px (CircleShape2D each) |
| Movement | Path-driven by `EnemyPathMover` (no self-propulsion in script) |
| On death | Splits into 2–4 `SmallAsteroid` shards |
| Sprite | `big_asteroid_tileset.png` (3×2 grid of 64×64 tiles, one picked at random) |
| Scene | `big_asteroid.tscn` |

---

## Behaviour

**Spawning & movement.** `BigAsteroid` extends the shared `asteroid_base.gd`. On `_ready()` it joins the `asteroids` group, attaches an `ExplosionEffect`, picks a random tile region from `big_asteroid_tileset.png`, and seeds its health. The node carries an `EnemyPathMover` that drives its `global_position` directly; the script never touches `velocity`, so to know its real speed each `_process` samples `(global_position - _prev_pos) / delta` and caches it as `_last_velocity`.

**On contact.** The `ContactHitBox` (layer 1024, `DamageType.CONTACT`) carries the contact damage. The base class re-evaluates damage every `_physics_process`: because `one_shot_speed_threshold` is 150.0, whenever the asteroid's measured speed reaches that threshold `current_contact_damage()` returns 9999 — a guaranteed kill. Below the threshold it deals the base 40.

**How it is destroyed.** Its `HurtBox` (layer 512, mask 32, accepts damage type 1 only) feeds incoming hits into `Health`. When health drops to 0 the base class plays the explosion, sets `was_killed = true`, emits `died(global_position)`, then calls the overridden `_on_destroyed()` before `queue_free()`. `_on_destroyed()` spawns `randi_range(split_min, split_max)` (2–4) `SmallAsteroid` shards at its position. Each shard's `drift_velocity` is the parent's inherited direction (or `Vector2.DOWN` if it never measurably moved) rotated by a random angle within ±`split_cone_spread` (≈±20°), scaled by `split_speed_factor` (0.5) — with a floor of `split_fallback_speed × split_speed_factor`. Shards are `call_deferred("add_child")`-ed onto the parent and announced to `ScoreTracker` via `EventBus.enemy_spawned_orphan` so killing them still awards points.

---

## Files

```
big_asteroid/
├── HAZARD.md             ← this file
├── big_asteroid.gd       ← BigAsteroid: split-on-death logic, velocity sampling
└── big_asteroid.tscn     ← scene: CharacterBody2D + Health/HurtBox/ContactHitBox + EnemyPathMover
```

Inherits shared behaviour from `../asteroid_base.gd` (random sprite, contact damage, death handling).
