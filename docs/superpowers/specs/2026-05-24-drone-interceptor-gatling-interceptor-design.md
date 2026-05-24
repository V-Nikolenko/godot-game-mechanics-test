# Design: DroneInterceptor + Interceptor Rework
**Date:** 2026-05-24

## Overview

Two changes:
1. **New `drone_interceptor` enemy** — a kamikaze unit that inherits the Interceptor's orbit/dash movement pattern but commits to a one-way dash instead of returning to orbit.
2. **Interceptor rework** — strips out the orbit/dash AI entirely and replaces it with a fast-firing Gatling weapon. Movement is fully delegated to `EnemyPathMover`. A new `PlayerFocusMovement` resource is added so any ship can lock onto the player's position and fly straight through.

---

## Part 1 — DroneInterceptor

### Scene & Files
- `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd`
- `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.gd`
- `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres`
- `assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn`
- Texture: `res://assault/assets/sprites/enemies/drone_2.png`

### Phases

| Phase | Behaviour |
|-------|-----------|
| `ENTER` | Fly toward player at `approach_speed` until within `orbit_radius`. |
| `ORBIT` | Circle player. Timer is `randf_range(1.0, 2.0)` seconds, then trigger DASH. |
| `DASH` | Lock direction to predicted player position (prediction time: 0.2 s). Fly at `dash_speed` indefinitely. Freed by off-screen check. |

No `REACQUIRE` or `RETREAT` — the DASH is one-way.

### Contact Kill
Overrides `_add_contact_hitbox()` (same pattern as `KamikazeDrone`): `collision_mask = 128` (player HurtBox), damage triggers `health.set_health(0)` on contact. The drone dies and the player takes damage.

### No Weapon
DroneInterceptor carries no `AttackController`. It is the weapon.

### Config Defaults (`drone_interceptor_config.tres`)

| Field | Value |
|-------|-------|
| `max_health` | 25 |
| `score_value` | 40 |
| `orbit_radius` | 130.0 |
| `approach_speed` | 200.0 |
| `orbit_speed` | 1.8 |
| `dash_speed` | 480.0 |
| `dash_prediction_time` | 0.2 |

### Implementation Notes
- Uses `_physics_process` (no EnemyPathMover) — same pattern as current Interceptor.
- Rotation: `_face_target()` during ENTER/ORBIT; `_face_direction()` during DASH.
- ORBIT uses the same proportional-speed approach correction as Interceptor (`clampf(dist * 4.0, 60.0, orbit_correct_speed)`).
- Off-screen check frees on any edge (top/bottom/left/right), matching `EnemyPathMover._check_off_screen()`.

### WaveBuilder
```gdscript
func drone_interceptor() -> SpawnConfig: return SpawnConfig.new(DRONE_INTERCEPTOR)
const DRONE_INTERCEPTOR := "res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn"
```
Usage: `b.drone_interceptor().at(-150, -420)` — no `.move()` needed (self-managed AI).

---

## Part 2 — PlayerFocusMovement

### File
- `global/resources/movement/player_focus_movement.gd`

### Design
A `MovementResource` subclass that computes direction toward the player once at spawn time, then flies straight in that direction.

```gdscript
class_name PlayerFocusMovement
extends MovementResource

@export var speed: float = 220.0
## Set by EnemyPathMover._ready() — not exported, not shared across ships.
var direction: Vector2 = Vector2.DOWN

func sample(t: float) -> Vector2:
    return direction * speed * t
```

### EnemyPathMover Change
In `_ready()`, before the `set_physics_process(false)` call:
```gdscript
if movement is PlayerFocusMovement:
    movement = movement.duplicate() as PlayerFocusMovement
    var players := _actor.get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        (movement as PlayerFocusMovement).direction = \
            ((players[0] as Node2D).global_position - _actor.global_position).normalized()
    else:
        (movement as PlayerFocusMovement).direction = Vector2.DOWN
```

Duplicating the resource ensures formation-expanded ships each get their own direction. The rest of `_physics_process` is **unchanged** — it calls `movement.sample(elapsed)` as normal.

### WaveBuilder Addition
```gdscript
func player_focus(speed: float = 220.0) -> PlayerFocusMovement:
    var m := PlayerFocusMovement.new()
    m.speed = speed
    return m
```
Usage: `b.interceptor().at(0, -400).move(b.player_focus(240))`

---

## Part 3 — Interceptor Rework

### What Changes
- **Removed**: entire state machine (`Phase` enum, `_physics_process`, orbit/dash/reacquire/retreat logic, orbit and dash config fields).
- **Added**: `GatlingAttackPattern`, fast `BulletPool`, `AttackController`.
- Movement is now fully via `EnemyPathMover` — always use `.move()` in WaveBuilder.

### GatlingAttackPattern

**File**: `global/resources/attack/gatling_attack_pattern.gd`

```gdscript
class_name GatlingAttackPattern
extends AttackPatternResource
# fire_interval inherited; default 0.09 s (≈11 shots/sec)

@export var bullet_damage: int = 4
@export var bullet_speed: float = 220.0
@export var spread_angle: float = 0.08   ## radians; ±~4.5° per shot
@export var aim_at_player: bool = true
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)

func fire(ship: Node2D, pool: BulletPool) -> void:
    var bullet := pool.acquire(ship.global_position + spawn_offset)
    if not bullet: return
    bullet.get_node("HitBox").damage = bullet_damage
    bullet.speed = bullet_speed
    var base_dir: Vector2
    if aim_at_player:
        var players := ship.get_tree().get_nodes_in_group("player")
        base_dir = ((players[0] as Node2D).global_position - ship.global_position).normalized() \
                   if players.size() > 0 else Vector2.DOWN
    else:
        base_dir = Vector2.DOWN.rotated(ship.rotation)
    var scatter := randf_range(-spread_angle, spread_angle)
    bullet.set_direction(base_dir.rotated(scatter))
```

### Updated InterceptorConfig Fields

| Field | Value |
|-------|-------|
| `max_health` | 70 |
| `score_value` | 75 |
| `fire_interval` | 0.09 |
| `bullet_damage` | 4 |
| `bullet_speed` | 220.0 |
| `spread_angle` | 0.08 |

Orbit/dash fields removed entirely.

### Interceptor `_ready()` (simplified)
```gdscript
func _ready() -> void:
    super._ready()
    add_to_group("enemies")
    if config:
        health.max_health     = config.max_health
        health.current_health = config.max_health
        score_value           = config.score_value

    _bullet_pool            = BulletPool.new()
    _bullet_pool.bullet_scene = _BULLET_SCENE
    _bullet_pool.pool_size  = 20   # fast fire rate needs larger pool
    add_child(_bullet_pool)

    var pattern                  := GatlingAttackPattern.new()
    pattern.fire_interval        = config.fire_interval if config else 0.09
    pattern.bullet_damage        = config.bullet_damage if config else 4
    pattern.bullet_speed         = config.bullet_speed  if config else 220.0
    pattern.spread_angle         = config.spread_angle  if config else 0.08

    _attack_controller           = AttackController.new()
    _attack_controller.pattern   = pattern
    _attack_controller.bullet_pool = _bullet_pool
    add_child(_attack_controller)
```

No `_physics_process` defined — movement entirely via EnemyPathMover.

### Level 1 Test Spawns (updated)
```gdscript
# 0.0s — interceptors fly toward player, shoot through with Gatling
b.wave(0.0, [
    b.interceptor().at(-200, -420).move(b.player_focus(240)),
    b.interceptor().at( 200, -420).move(b.player_focus(240)).delay(0.4),
]),
```

---

## File Summary

### New Files
| File | Purpose |
|------|---------|
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd` | Kamikaze orbit+dash AI |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.gd` | Config resource class |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres` | Default values |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn` | Scene with Sprite2D, HurtBox, Health, HitFlash |
| `global/resources/movement/player_focus_movement.gd` | Focus movement resource |
| `global/resources/attack/gatling_attack_pattern.gd` | Gatling attack pattern |

### Modified Files
| File | Change |
|------|--------|
| `assault/scenes/enemies/enemy_path_mover.gd` | Inject player direction for `PlayerFocusMovement` in `_ready()` |
| `assault/scenes/enemies/interceptor/interceptor.gd` | Remove state machine; add GatlingAttackPattern setup |
| `assault/scenes/enemies/interceptor/interceptor_config.gd` | Replace orbit/dash fields with Gatling fields |
| `assault/scenes/enemies/interceptor/interceptor_config.tres` | Update values |
| `assault/scenes/systems/wave_builder.gd` | Add `drone_interceptor()`, `player_focus()` |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Update test spawns to use focus movement |
