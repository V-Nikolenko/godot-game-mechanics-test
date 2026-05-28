# Design: Gunship Rework
**Date:** 2026-05-24

## Overview

Full rework of the existing `Gunship` enemy, which is currently a placeholder (wrong texture, fires straight down, minimal config). The reworked Gunship is a heavy, slow unit that enters from the top, holds a fixed vertical position, fires dual-barrel aimed bursts at the player, swaps to a damaged sprite at 50% HP, and retreats at 30% HP.

Same `class_name Gunship`, same scene path — no WaveBuilder changes needed.

---

## Files Modified

| File | Change |
|------|--------|
| `assault/scenes/enemies/gunship/gunship.gd` | Full rewrite |
| `assault/scenes/enemies/gunship/gunship_config.gd` | Expand config with all tuning fields |
| `assault/scenes/enemies/gunship/gunship_config.tres` | Update stored values |
| `assault/scenes/enemies/gunship/gunship.tscn` | Replace AnimatedSprite2D with Sprite2D; update texture |

---

## Part 1 — Movement & Phases

Three phases driven by `_physics_process`. A `_phase` enum (`ENTER`, `HOLD`, `RETREAT`) replaces the current boolean flags.

### ENTER
Moves straight down at `entry_speed` until `global_position.y >= _hold_y`. No firing. `_hold_y` is computed once in `_ready()`:
```gdscript
_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset
```

### HOLD
- Stays at fixed Y (`velocity.y = 0`).
- If `track_player = true`: tracks player X with proportional speed capped at `track_speed`:
  ```gdscript
  var diff := player.global_position.x - global_position.x
  velocity.x = sign(diff) * minf(absf(diff) * 2.0, track_speed)
  ```
- Fires bursts via a child `Timer` at `burst_interval`.
- If `health.current_health <= health.max_health * retreat_hp_ratio` → switch to RETREAT.

### RETREAT
- Moves straight up at `entry_speed * 1.5`.
- `queue_free()` when `global_position.y < cam.global_position.y - viewport_size.y * 0.5 - 50.0`.
- Firing timer is stopped on entry to RETREAT.

---

## Part 2 — Dual-barrel Burst Weapon

A repeating child `Timer` at `burst_interval` triggers `_fire_burst()`. The burst:

1. Fire from **left barrel** at `Vector2(-12, 8)` relative to ship, aimed at player
2. `await get_tree().create_timer(burst_gap).timeout`
3. Fire from **right barrel** at `Vector2(+12, 8)` relative to ship, aimed at player

Aim direction per shot: `(player_global_pos - barrel_world_pos).normalized()` at fire time. Falls back to `Vector2.DOWN` if no player found.

`BulletPool` with `pool_size = 15` manages bullet recycling. No `AttackController` — the `await`-based burst gap requires direct coroutine control.

### GunshipConfig fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `burst_interval` | float | 1.0 | Seconds between bursts |
| `burst_gap` | float | 0.12 | Delay between L and R shot in a burst |
| `bullet_damage` | int | 15 | Per-bullet damage |
| `bullet_speed` | float | 260.0 | Bullet travel speed (px/s) |
| `entry_speed` | float | 60.0 | Enter and retreat speed (px/s) |
| `hold_y_offset` | float | 55.0 | px below viewport top edge for hold position |
| `track_speed` | float | 70.0 | Max horizontal tracking speed (px/s) |
| `track_player` | bool | true | Enable/disable horizontal tracking |
| `retreat_hp_ratio` | float | 0.3 | HP fraction that triggers retreat |

(Inherited from `ShipConfig`: `max_health = 200`, `collision_damage = 30`, `score_value = 200`)

---

## Part 3 — Health-based Sprite Swap

Two textures preloaded as script constants:
```gdscript
const _TEXTURE_FULL    := preload("res://assault/assets/sprites/enemies/heave_gunship.png")
const _TEXTURE_DAMAGED := preload("res://assault/assets/sprites/enemies/heavy_gunship_non_shielded.png")
```

Scene uses a single `Sprite2D` node (replacing the `AnimatedSprite2D` placeholder). In `_ready()`, a dedicated signal connection is added:
```gdscript
health.amount_changed.connect(_on_health_changed_gunship)
```

Handler swaps texture **once**, when HP first crosses 50%:
```gdscript
func _on_health_changed_gunship(current: int) -> void:
    if current <= health.max_health / 2:
        _sprite.texture = _TEXTURE_DAMAGED
```

- No per-frame check.
- No reverse swap (damage is one-way).
- `BaseEnemy._on_health_changed` is untouched — hit flash and explosion fire normally via the base class signal connection.

---

## Scene Structure

```
Gunship (CharacterBody2D)
  Sprite2D            ← heave_gunship.png, scale=(2,2), rotation_degrees=180, hit flash shader
  CollisionShape2D    ← CircleShape2D radius=18
  HurtBox (Area2D)    ← layer=512, mask=65
    CollisionShape2D
  Health (Node)       ← max_health=200
  HitFlashAnimationPlayer
```

`rotation_degrees = 180` on the Sprite2D so the UP-facing sprite points downward, consistent with the project's sprite convention.

---

## WaveBuilder

No changes needed. Existing `func gunship() -> SpawnConfig` and `GUNSHIP` constant remain valid. The rework is a drop-in replacement.

The Gunship manages its own ENTER/HOLD/RETREAT AI in `_physics_process`. Do **not** use `.move()` — attaching EnemyPathMover would disable `_physics_process` and break the AI.

```gdscript
b.gunship().at(0, -500)   ✓   correct
b.gunship().at(0, -500).move(b.straight(60))   ✗   breaks AI
```
