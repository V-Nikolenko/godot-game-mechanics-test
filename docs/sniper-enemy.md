# Sniper Enemy

**Scene:** `res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn`  
**Script:** `res://assault/scenes/enemies/sniper_enemy/sniper_enemy.gd`  
**Class:** `SniperEnemy` (extends `BaseEnemy`)

---

## Overview

The Sniper Enemy is a stationary threat that descends from off-screen, locks onto
the player with a visible red aim line, fires a high-speed piercing bullet, then
retreats. It repeats the aim-and-fire cycle a configurable number of times before
flying out.

Movement is entirely driven by an `EnemyPathMover` with a three-step sequence
(fly in → hold → fly out). The enemy's own code handles only the shooting
state machine.

---

## Behaviour — state machine

```
APPROACH ──(FLY_IN_TIME seconds)──► AIM ──(AIM_DURATION)──► LOCK ──(LOCK_DURATION)──► FIRE
                                     ▲                                                    │
                                     └──────────── repeat until shot_count ───────────────┘
                                                                                          │
                                                                               (IDLE) ◄──┘
                                                                    EnemyPathMover flies out
```

| Phase      | What happens |
|------------|--------------|
| `APPROACH` | Enemy descends. Sprite is forced to face the player (rotation `PI`). **No red line.** Timer counts `FLY_IN_TIME` seconds. |
| `AIM`      | Single red aim line appears. Enemy rotates toward the player via `lerp_angle`. Line colour is dim red. Runs for `AIM_DURATION` seconds. |
| `LOCK`     | Rotation freezes. Line turns bright orange-red (charge = 1.0). Held for `LOCK_DURATION` seconds — the player's last warning. |
| `FIRE`     | Bullet spawned at the muzzle in the locked direction. Visualizer destroyed. If `shots_fired < shot_count`, loops back to `AIM`; otherwise enters `IDLE`. |
| `IDLE`     | No logic runs. `EnemyPathMover` is now in its exit step and flies the enemy off-screen upward. |

---

## Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `AIM_DURATION` | `2.0 s` | Time the aim line tracks the player before locking. |
| `LOCK_DURATION` | `0.5 s` | Freeze time between lock and firing. |
| `ROTATION_LERP` | `4.0` | Lerp factor for aim tracking (`delta × ROTATION_LERP`). Higher = snappier. |
| `FLY_IN_TIME` | `2.5 s` | How long the APPROACH phase lasts. **Must match the `straight` step duration in the spawn sequence.** |

---

## Exported parameter

```gdscript
@export var shot_count: int = 5
```

Number of times the enemy fires before retreating. Override per-spawn with
`.prop("shot_count", N)` in the wave builder (see examples below).

---

## Projectile

**Scene:** `res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn`

| Property | Value |
|----------|-------|
| Speed | 1 400 px/s |
| Damage | 25 |
| Collision layer | 256 (enemy bullet) |
| Collision mask | 128 (player hurtbox) |
| Lifetime | Self-destructs on hit or when it leaves the arena (`expired` signal) |

The bullet is a thin red beam (matching the player's sniper bullet visually).
It is **not** pooled — each round is instantiated and cleaned up via `expired`.

---

## Aim visualiser

`SniperAimVisualizer` is shared with the player's sniper weapon.
When `initial_angles` is **empty** (the enemy's case) it draws a **single line**:

| State | Colour | Width |
|-------|--------|-------|
| Tracking (AIM) | Dim red `Color(1, 0.1, 0.1, 0.55)` | 1 px |
| Locked (LOCK)  | Bright orange-red `Color(1, 0.15, 0, 1)` | 2 px |

The line is drawn from the muzzle (`Marker2D` at local `(0, –20)`) outward
600 px in the aim direction.

---

## Node structure

```
SniperEnemy  [CharacterBody2D]
├── Sprite2D            scale (2, 2), sniper.png, hit-flash ShaderMaterial
├── CollisionShape2D    CircleShape2D r=14
├── Muzzle              [Marker2D]  position (0, –20)
│   └── SniperAimVisualizer  (created at runtime, only during AIM/LOCK)
├── HurtBox             [Area2D]  layer=512, mask=97
│   └── CollisionShape2D
├── Health              [Node]  max_health=60
└── HitFlashAnimationPlayer
```

---

## Adding to a wave

### Required sequence structure

The enemy's `FLY_IN_TIME` constant (`2.5 s`) must match the duration of the
`straight` step. The `hold` step must be long enough to cover the full shoot
cycle:

```
hold_time >= shot_count × (AIM_DURATION + LOCK_DURATION)
           = shot_count × 2.5 s
```

Add a small buffer (≥ 0.5 s). For the default `shot_count = 5`:

```
hold_time >= 5 × 2.5 + 0.5 = 13.0 s
```

### Minimal example (default 5 shots)

```gdscript
var b := WaveBuilder.new()

b.wave(0.5, [
    b.sniper_enemy()
        .at(0, -500)
        .move(b.sequence([
            b.straight(150, 0.0, 2.5),   # fly in  (must equal FLY_IN_TIME)
            b.hold(13.0),                 # hold while shooting (5 × 2.5 s + buffer)
            b.straight(220, PI),          # fly out upward (no duration = until off-screen)
        ])),
])
```

### Overriding shot count

```gdscript
b.sniper_enemy()
    .at(0, -500)
    .prop("shot_count", 2)           # fires twice then retreats
    .move(b.sequence([
        b.straight(150, 0.0, 2.5),
        b.hold(5.5),                 # 2 × 2.5 s + 0.5 s buffer
        b.straight(220, PI),
    ]))
```

### Staggered pair (used in Level 1)

```gdscript
b.wave(0.5, [
    b.sniper_enemy().at(-120, -500).move(b.sequence([
        b.straight(150, 0.0, 2.5),
        b.hold(13.0),
        b.straight(220, PI),
    ])),
    b.sniper_enemy().at( 120, -500).move(b.sequence([
        b.straight(150, 0.0, 2.5),
        b.hold(13.0),
        b.straight(220, PI),
    ])).delay(0.5),   # 0.5 s stagger so shots don't land simultaneously
])
```

### Positioning tips

| Offset Y | Effect |
|----------|--------|
| `–500` | Spawns ~200 px above the top edge (standard; enemy is invisible on entry) |
| `–400` | Spawns just above the top edge (visible sooner) |

Use `x` offsets to control where the sniper hovers horizontally. The enemy
descends straight down, stopping approximately 28 % from the top of the viewport
(governed by `FLY_IN_TIME × fly_in_speed`).

### Fly-out speed

The third sequence step can be adjusted freely — `b.straight(220, PI)` is the
recommended default (220 px/s, upward, duration open-ended so screen-exit culling
handles cleanup). Increase speed for a faster retreat, or replace with a different
exit angle if side-exit is desired (e.g. `b.straight(280, PI/2)` to exit left).

---

## Technical notes

### Why `_process` instead of `_physics_process`

`EnemyPathMover._ready()` calls `_actor.set_physics_process(false)` to take sole
ownership of the actor's position. Moving the state machine to `_process` sidesteps
this: `_process` is never disabled by `EnemyPathMover`, and in Godot 4 it runs
*after* `_physics_process` within the same frame, so `_track_player()` always
writes rotation last.

### Rotation during APPROACH

`EnemyPathMover` sets `rotation = 0` (nose-up) each physics frame while the
straight-down movement is active. `_phase_approach()` forcibly resets it to `PI`
(nose-down, facing the player) every `_process` frame — overriding the mover
before the frame is rendered.

### Bullet direction

```gdscript
bullet.set_direction(Vector2.UP.rotated(rotation))
```

`Vector2.UP.rotated(PI)` = `(0, 1)` = downward. When the enemy has tracked and
locked onto a player to the side, the same formula correctly angles the shot.
