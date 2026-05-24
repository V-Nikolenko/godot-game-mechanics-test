# Implementation Plan — Interceptor Enemy

**Date:** 2026-05-24  
**Sprite:** `res://assault/assets/sprites/enemies/interceptor.png` (naturally faces UP at rotation 0)  
**Design brief:** Persistent pursuit unit that orbits the player at close-to-mid range, fires while circling, and periodically dashes toward the player's predicted position.

---

## 1. Behaviour overview

```
ENTER ──────────────────────────────────────────────────────────────────────────
  Fly toward player at APPROACH_SPEED.
  Transition → ORBIT when within ORBIT_RADIUS.

ORBIT ───────────────────────────────────────────── (loops, fires on timer)
  Advance _orbit_angle at ORBIT_SPEED (rad/s).
  Steer toward orbit position:  player_pos + Vector2.RIGHT.rotated(_orbit_angle) × ORBIT_RADIUS
  Face player via lerp_angle.
  _dash_timer counts down → when 0, transition → DASH.

DASH ────────────────────────────────────────────────────────────────────────────
  Predict player position:  player_pos + player.velocity × DASH_PREDICTION_TIME
  Burst at DASH_SPEED toward predicted position for DASH_DURATION seconds.
  Transition → REACQUIRE.

REACQUIRE ───────────────────────────────────────────────────────────────────────
  If distance_to_player > ORBIT_RADIUS × 1.5: fly toward orbit position.
  Else: snap back into ORBIT at current angle, reset _dash_timer.

RETREAT (exit) ──────────────────────────────────────────────────────────────────
  Triggered when _lifetime_timer exceeds MAX_LIFETIME.
  Accelerate off-screen upward. queue_free on screen-exit.
```

### State machine diagram

```
         ENTER
           │ distance ≤ ORBIT_RADIUS
           ▼
    ┌─── ORBIT ◄──────────────────────────────────────────────┐
    │      │ _dash_timer == 0                                   │
    │      ▼                                                    │
    │    DASH                                                   │
    │      │ _dash_duration_timer == 0                          │
    │      ▼                                                    │
    │  REACQUIRE ──────────────────────────────────────────────┘
    │
    │ _lifetime_timer ≥ MAX_LIFETIME (from any phase)
    ▼
  RETREAT → (off-screen) → queue_free
```

---

## 2. File structure

```
assault/scenes/enemies/interceptor/
├── interceptor.gd          Main script (extends BaseEnemy)
├── interceptor.tscn        Scene (CharacterBody2D root)
├── interceptor_config.gd   Config resource class (extends ShipConfig)
└── interceptor_config.tres Default config values
```

**Modified files:**
- `assault/scenes/systems/wave_builder.gd` — add `INTERCEPTOR` constant + `interceptor()` factory

---

## 3. `interceptor_config.gd`

Extends `ShipConfig` (same pattern as `GunshipConfig`, `SniperConfig`).

```gdscript
class_name InterceptorConfig
extends ShipConfig

@export var orbit_radius        : float = 200.0  ## preferred distance from player (px)
@export var orbit_speed         : float = 1.4    ## angular velocity (rad/s)
@export var approach_speed      : float = 220.0  ## speed during ENTER / REACQUIRE
@export var orbit_correct_speed : float = 170.0  ## max speed correcting orbit position
@export var dash_speed          : float = 440.0  ## burst speed during DASH
@export var dash_duration       : float = 0.35   ## seconds per dash
@export var dash_interval       : float = 3.5    ## seconds between dashes (ORBIT timer)
@export var dash_prediction_time: float = 0.28   ## seconds ahead to predict player position
@export var fire_interval       : float = 0.55   ## seconds between shots
@export var bullet_speed        : float = 290.0  ## px/s
@export var bullet_damage       : int   = 10
@export var max_health          : int   = 70
```

`interceptor_config.tres` should be a saved `.tres` with these defaults pre-filled.

---

## 4. `interceptor.gd`

```gdscript
class_name Interceptor
extends BaseEnemy

@export var config: InterceptorConfig = preload("…/interceptor_config.tres")

enum Phase { ENTER, ORBIT, DASH, REACQUIRE, RETREAT }

## ── Tuning (read from config in _ready) ──────────────────────────────────────
var _orbit_radius         : float
var _orbit_speed          : float
var _approach_speed       : float
var _orbit_correct_speed  : float
var _dash_speed           : float
var _dash_duration        : float
var _dash_interval        : float
var _dash_prediction_time : float

## ── Runtime state ─────────────────────────────────────────────────────────────
var _phase               : Phase   = Phase.ENTER
var _orbit_angle         : float   = 0.0   ## radians, advances each frame in ORBIT
var _dash_timer          : float   = 0.0   ## counts DOWN to next dash
var _dash_duration_timer : float   = 0.0   ## counts DOWN to end of current dash
var _lifetime_timer      : float   = 0.0   ## total time alive; triggers RETREAT
var _dash_direction      : Vector2 = Vector2.ZERO

const MAX_LIFETIME : float = 45.0
const ROTATION_LERP: float = 6.0

const _BULLET_SCENE: PackedScene = preload(
    "res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
var _bullet_pool: BulletPool
```

### `_ready()`

```gdscript
func _ready() -> void:
    super._ready()
    add_to_group("enemies")

    # Apply config values
    if config:
        health.max_health         = config.max_health
        health.current_health     = config.max_health
        score_value               = config.score_value
        _orbit_radius             = config.orbit_radius
        _orbit_speed              = config.orbit_speed
        _approach_speed           = config.approach_speed
        _orbit_correct_speed      = config.orbit_correct_speed
        _dash_speed               = config.dash_speed
        _dash_duration            = config.dash_duration
        _dash_interval            = config.dash_interval
        _dash_prediction_time     = config.dash_prediction_time

    # Bullet pool (same pattern as Gunship/LightAssaultShip)
    _bullet_pool = BulletPool.new()
    _bullet_pool.bullet_scene = _BULLET_SCENE
    _bullet_pool.pool_size    = 12
    add_child(_bullet_pool)

    # Attack controller wired to config fire_interval
    var pattern := AimedAttackPattern.new()
    pattern.fire_interval = config.fire_interval if config else 0.55
    pattern.bullet_damage = config.bullet_damage if config else 10
    pattern.bullet_speed  = config.bullet_speed  if config else 290.0
    pattern.aim_at_player = true
    pattern.spawn_offset  = Vector2(0.0, 10.0)
    var controller := AttackController.new()
    controller.pattern     = pattern
    controller.bullet_pool = _bullet_pool
    add_child(controller)

    # Randomise starting orbit angle and dash timer so a pair of interceptors
    # don't perfectly mirror each other
    _orbit_angle = randf_range(0.0, TAU)
    _dash_timer  = randf_range(_dash_interval * 0.5, _dash_interval)
```

### `_physics_process(delta)`

```gdscript
func _physics_process(delta: float) -> void:
    _lifetime_timer += delta
    if _lifetime_timer >= MAX_LIFETIME and _phase != Phase.RETREAT:
        _phase = Phase.RETREAT

    var player := _get_player()

    match _phase:
        Phase.ENTER     : _phase_enter(delta, player)
        Phase.ORBIT     : _phase_orbit(delta, player)
        Phase.DASH      : _phase_dash(delta, player)
        Phase.REACQUIRE : _phase_reacquire(delta, player)
        Phase.RETREAT   : _phase_retreat(delta)

    # Face the player in all active phases (except RETREAT which faces movement dir)
    if _phase != Phase.RETREAT and player:
        _face_player(delta, player)

    move_and_slide()
```

### Phase implementations

#### `_phase_enter`
```gdscript
func _phase_enter(delta: float, player: Node2D) -> void:
    if not player:
        return
    var to_player := player.global_position - global_position
    if to_player.length() <= _orbit_radius:
        _phase = Phase.ORBIT
        return
    velocity = to_player.normalized() * _approach_speed
```

#### `_phase_orbit`
```gdscript
func _phase_orbit(delta: float, player: Node2D) -> void:
    _dash_timer -= delta
    if _dash_timer <= 0.0:
        _begin_dash(player)
        return

    if not player:
        return

    # Advance orbit angle
    _orbit_angle += _orbit_speed * delta

    # Steer toward the orbit anchor point
    var orbit_target := player.global_position \
        + Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
    var to_target := orbit_target - global_position
    var dist      := to_target.length()

    # Proportional speed: faster when far from target, clamped to max
    var speed := clampf(dist * 4.0, 60.0, _orbit_correct_speed)
    velocity = to_target.normalized() * speed

    # AttackController fires independently — nothing extra needed here
```

#### `_begin_dash` + `_phase_dash`
```gdscript
func _begin_dash(player: Node2D) -> void:
    _phase = Phase.DASH
    _dash_duration_timer = _dash_duration

    var predicted_pos: Vector2
    if player and player is CharacterBody2D:
        predicted_pos = player.global_position \
            + (player as CharacterBody2D).velocity * _dash_prediction_time
    elif player:
        predicted_pos = player.global_position
    else:
        predicted_pos = global_position + Vector2(0.0, 200.0)

    _dash_direction = (predicted_pos - global_position).normalized()

func _phase_dash(delta: float, _player: Node2D) -> void:
    _dash_duration_timer -= delta
    velocity = _dash_direction * _dash_speed
    if _dash_duration_timer <= 0.0:
        _phase = Phase.REACQUIRE
```

#### `_phase_reacquire`
```gdscript
func _phase_reacquire(delta: float, player: Node2D) -> void:
    if not player:
        return
    var dist := global_position.distance_to(player.global_position)
    if dist > _orbit_radius * 1.5:
        # Still too far — fly back toward orbit position
        var orbit_target := player.global_position \
            + Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
        velocity = (orbit_target - global_position).normalized() * _approach_speed
    else:
        # Close enough — snap back into orbit, reset dash cooldown
        _phase = Phase.ORBIT
        _dash_timer = _dash_interval
```

#### `_phase_retreat`
```gdscript
func _phase_retreat(delta: float) -> void:
    velocity = Vector2(0.0, -_approach_speed * 1.2)
    # Face upward (direction of retreat)
    rotation = lerp_angle(rotation, 0.0, delta * ROTATION_LERP)
    _check_off_screen_top()

func _check_off_screen_top() -> void:
    var cam := get_viewport().get_camera_2d()
    if not cam:
        return
    var vs := get_viewport().get_visible_rect().size
    if global_position.y < cam.global_position.y - vs.y * 0.5 - 80.0:
        queue_free()
```

### Helpers

```gdscript
func _get_player() -> Node2D:
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return null
    return players[0] as Node2D

func _face_player(delta: float, player: Node2D) -> void:
    var dir := (player.global_position - global_position).normalized()
    # atan2(dir.x, -dir.y) makes Vector2.UP face the target direction.
    # Sprite naturally faces UP at rotation=0 — consistent with SniperEnemy.
    var target_rot := atan2(dir.x, -dir.y)
    rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
```

---

## 5. `interceptor.tscn`

Node structure mirrors `sniper_enemy.tscn`:

```
Interceptor  [CharacterBody2D]
  script = interceptor.gd
├── Sprite2D
│     texture = interceptor.png
│     scale   = Vector2(2, 2)
│     material = ShaderMaterial (hit_flash_vs.tres, same as other enemies)
├── CollisionShape2D   CircleShape2D  radius ≈ 14
├── HurtBox  [Area2D]
│     collision_layer = 512
│     collision_mask  = 97
│     script = hurtbox_component.gd
│   └── CollisionShape2D  (same CircleShape2D)
├── Health  [Node]
│     script = health_component.gd
│     max_health = 70
│     current_health = 70
└── HitFlashAnimationPlayer  [AnimationPlayer]
      (same RESET + hit library used by SniperEnemy)
```

> **Sprite orientation note:** `interceptor.png` naturally faces UP (rotation=0 = nose up).
> `_face_player()` uses `atan2(dir.x, -dir.y)` — the same formula as `SniperEnemy` —
> which produces `rotation = PI` when the player is directly below, correctly
> pointing the nose downward toward the player.

---

## 6. WaveBuilder integration

Add to `assault/scenes/systems/wave_builder.gd`:

```gdscript
# In ship constructors block:
func interceptor() -> SpawnConfig: return SpawnConfig.new(INTERCEPTOR)

# In scene path constants block:
const INTERCEPTOR := "res://assault/scenes/enemies/interceptor/interceptor.tscn"
```

### Spawning

The Interceptor owns its entire movement AI — **do not use `.move()`**.
Spawn it above or to the side of the screen and let it find the player:

```gdscript
# Single interceptor entering from above-centre
b.wave(10.0, [
    b.interceptor().at(0, -420),
])

# Pair entering from opposite sides simultaneously
b.wave(15.0, [
    b.interceptor().at(-300, -420),
    b.interceptor().at( 300, -420).delay(0.5),
])

# Override shot count or dash interval via .prop()
b.interceptor()
    .at(0, -420)
    .prop("_dash_interval", 2.0)   # more aggressive dashing
```

> **No `.move()` or `.free_after()` required.** The Interceptor self-manages
> its lifetime (`MAX_LIFETIME = 45 s`) and retreats off-screen automatically.

---

## 7. Tuning guide

| Dial | Effect when increased |
|------|-----------------------|
| `orbit_radius` | Wider orbit, harder to close with melee weapons, easier to dodge shots |
| `orbit_speed` | Faster circling, harder to predict position |
| `dash_interval` | Fewer dashes, more predictable; lower = relentless |
| `dash_speed` | Harder to evade the intercept burst |
| `dash_prediction_time` | Punishes steady movement more; too high = misses if player turns |
| `fire_interval` | More bullet pressure; balance against bullet speed |
| `orbit_correct_speed` | Snappier orbit tracking; too high = jittery movement |

Recommended difficulty progression:

| Tier | `orbit_speed` | `dash_interval` | `fire_interval` | `max_health` |
|------|--------------|-----------------|-----------------|-------------|
| Early | 1.0 | 5.0 | 0.75 | 50 |
| Default | 1.4 | 3.5 | 0.55 | 70 |
| Elite | 2.0 | 2.2 | 0.40 | 100 |

---

## 8. Build order

1. **`interceptor_config.gd`** — resource class, no dependencies
2. **`interceptor_config.tres`** — fill in default values
3. **`interceptor.gd`** — script, test with a placeholder scene
4. **`interceptor.tscn`** — assemble scene, wire nodes
5. **`wave_builder.gd`** — add `INTERCEPTOR` const + `interceptor()` method
6. **Test** — spawn one interceptor at a fixed position, verify all five phases transition correctly; check dash prediction with a moving player
7. **Tune** — adjust `orbit_radius`, `dash_interval`, `fire_interval` for feel
8. **Document** — add `docs/interceptor-enemy.md` (same format as `docs/sniper-enemy.md`)

---

## 9. Open questions / future extensions

- **Pair coordination:** Two Interceptors could orbit at opposite angles (`_orbit_angle` offset by PI) for a pincer pattern. This needs no code change — just spawn two with the angle prop set.
- **Shield break on dash:** The dash could deal contact damage while passing through the player's position (add a brief hitbox active only during DASH).
- **Elite variant:** Higher `max_health`, leaves a slower homing bullet behind on each dash miss.
- **Sound cues:** A distinct audio cue at the start of DASH would let skilled players react — implement as an `AudioStreamPlayer2D` child triggered in `_begin_dash()`.
