# Enemy Roster & Wave Builder Reference

> Part of the project knowledge base — see [`architecture/PROJECT.md`](architecture/PROJECT.md). Per-enemy behaviour docs live beside each enemy as `ENEMY.md`.

Reference for all enemy types in the assault mission and how to spawn them via `WaveBuilder`.

**Coordinate system:** All `.at(x, y)` offsets are camera-relative in design units (640×360 space). `WaveManager` scales them by `ArenaCamera.WORLD_SCALE` (2.0) automatically — never pre-multiply.

---

## How to Spawn Enemies

### 1. Create a WaveBuilder instance

```gdscript
var b := WaveBuilder.new()
```

### 2. Build wave entries using the fluent API

```gdscript
b.fighter().at(0, -400).move(b.straight(150)).delay(0.5)
```

| Method | What it does |
|--------|-------------|
| `.at(x, y)` | Spawn offset from camera centre (design units). Positive Y = below camera. |
| `.move(movement)` | Attach an `EnemyPathMover` with this movement. |
| `.delay(seconds)` | Seconds after the wave trigger before this enemy spawns. |
| `.free_after(seconds)` | Force-free after N seconds (use for enemies that enter from the side). |
| `.formation(f)` | Expand one entry into multiple ships using a formation resource. |
| `.shoot_forward()` | Set `aim_mode = "FORWARD"` on spawn. |
| `.shoot_at_player()` | Set `aim_mode = "PLAYER"` on spawn. |
| `.look_at_angle(radians)` | Fix rotation — `0` = down, `PI` = up, `PI/2` = left, `-PI/2` = right. |
| `.prop(key, value)` | Set any exported property on the enemy node before `_ready()`. |

### 3. Wrap entries in a wave

```gdscript
b.wave(trigger_time_seconds, [ ...entries... ])
```

### 4. Assign waves to a section

```gdscript
var raw_waves: Array = [ b.wave(0.0, [...]), b.wave(2.0, [...]) ]
s.waves.assign(raw_waves)
```

---

## Enemy Types

### `fighter` — Light Assault Ship

**Builder:** `b.fighter()`  
**Scene:** `light_assault_ship.tscn`  
**Movement:** Fully delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** Yes — at player or forward depending on `aim_mode`.  
**HP:** Low  
**Score:** Low

**Config fields** (`FighterConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `movement_speed` | 100.0 | Used internally by the AI state machine when no EnemyPathMover is present. Usually irrelevant — use `.move()` speed instead. |
| `fire_interval` | 0.8 s | Seconds between shots. |
| `bullet_damage` | 8 | Per-bullet damage. |
| `aim_mode` | `"PLAYER"` | `"PLAYER"` or `"FORWARD"`. Set via `.shoot_at_player()` / `.shoot_forward()`. |

**Examples:**
```gdscript
# Straight dive from above
b.fighter().at(0, -400).move(b.straight(150)).shoot_at_player()

# Sweep in from off-screen left (must use free_after — never exits top)
b.fighter().at(-500, 30).move(b.straight(230, PI / 2)).shoot_forward().free_after(5.0)

# V-formation of 5
b.fighter().formation(b.v_formation(5)).at(0, -400).move(b.straight(138)).shoot_forward()

# U-sweep arc from the right
b.fighter().at(260, -400).move(b.u_sweep(510, 730, 10)).free_after(12).shoot_forward()
```

---

### `drone` — Kamikaze Drone

**Builder:** `b.drone()`  
**Scene:** `kamikaze_drone.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** No — rams the player on contact.  
**HP:** Very low  
**Score:** Very low

**Config fields** (`DroneConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `movement_speed` | 140.0 | Irrelevant when EnemyPathMover is attached — use `.move()` speed. |

**Examples:**
```gdscript
# Sine weave from the top
b.drone().at(-260, -400).move(b.sine(170, 30))

# Straight dive with stagger
b.drone().at(-100, -400).move(b.straight(220)).delay(0.15)

# Cluster formation rushing down
b.drone().formation(b.cluster_formation(3, 30)).at(0, -400).move(b.straight(180))

# Approaching from below
b.drone().at(-150, 400).move(b.straight(185, PI))
```

---

### `ram` — Ram Ship

**Builder:** `b.ram()`  
**Scene:** `ram_ship.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** No — high collision damage.  
**HP:** Medium  
**Score:** Medium

**Config fields** (`RamShipConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `movement_speed` | 100.0 | Irrelevant — use `.move()` speed. |

**Examples:**
```gdscript
# Classic straight dive
b.ram().at(0, -400).move(b.straight(280))

# Angled pair from the sides
b.ram().at(-255, -400).move(b.straight(350))
b.ram().at( 255, -400).move(b.straight(350)).delay(0.5)

# Surprise from below
b.ram().at(0, 400).move(b.straight(260, PI))
```

---

### `sniper` — Sniper Skimmer

**Builder:** `b.sniper()`  
**Scene:** `sniper_skimmer.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** Yes — fires once at midpoint of its travel. Always aims at player.  
**HP:** Low  
**Score:** Low–Medium

**Config fields** (`SniperConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `movement_speed` | 130.0 | Irrelevant — use `.move()` speed. |

**Notes:**
- Fires exactly once during its path — no burst, no repeat.
- Typically use `.shoot_at_player()` (the default behaviour).
- Use `.free_after()` when entering from off-screen sides.

**Examples:**
```gdscript
# Diagonal skimmer from top-left
b.sniper().at(-185, -400).move(b.straight(82, PI / 10)).shoot_at_player()

# From off-screen side — must free explicitly
b.sniper().at(-500, 50).move(b.straight(180, PI / 2)).shoot_at_player().free_after(4.0)

# From below as an ambush
b.sniper().at(-260, 400).move(b.straight(100, -PI / 2 - PI / 12)).shoot_at_player().free_after(5.5)
```

---

### `sniper_enemy` — Sniper Enemy (hovering)

**Builder:** `b.sniper_enemy()`  
**Scene:** `sniper_enemy.tscn`  
**Movement:** Must use a **sequence movement**: fly in → hold → fly out.  
**Shoots:** Yes — fires `shot_count` aimed sniper shots while hovering.  
**HP:** Medium  
**Score:** Medium

**Behaviour phases:**
1. `APPROACH` — descends into position (nose-down). Duration = first `straight()` step.
2. `AIM` → `LOCK` → `FIRE` — cycles `shot_count` times. Each cycle: 2.0 s aim + 0.5 s lock.
3. `IDLE` — `EnemyPathMover`'s exit step (last `straight()`) retreats the ship.

**Key constant:** `FLY_IN_TIME = 2.5 s` — the approach step **must** be exactly 2.5 s duration.  
**Hold duration formula:** `shot_count × 2.5 s` minimum (5 shots × 2.5 = 13 s → use `hold(13.0)`).

**Exports:**

| Field | Default | Notes |
|-------|---------|-------|
| `shot_count` | 5 | Override via `.prop("shot_count", N)`. |

**Examples:**
```gdscript
# Standard 5-shot hovering sniper
b.sniper_enemy().at(-120, -500).move(b.sequence([
    b.straight(150, 0.0, 2.5),   # fly in (exactly 2.5 s)
    b.hold(13.0),                 # hover (5 shots × 2.5 s)
    b.straight(220, PI),          # retreat upward
]))

# 3-shot variant (holds for 7.5 s)
b.sniper_enemy().at(120, -500).move(b.sequence([
    b.straight(150, 0.0, 2.5),
    b.hold(7.5),
    b.straight(220, PI),
])).prop("shot_count", 3)
```

---

### `interceptor` — Gatling Interceptor

**Builder:** `b.interceptor()`  
**Scene:** `interceptor.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** Yes — rapid-fire Gatling (0.09 s interval, slight spread). Always fires forward (in direction of travel).  
**HP:** Low–Medium  
**Score:** Medium

**Config fields** (`InterceptorConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `fire_interval` | 0.09 s | Very fast — 11 shots/second. |
| `bullet_damage` | 4 | Per-bullet damage. |
| `bullet_speed` | 220.0 | px/s. |
| `spread_angle` | 0.08 rad | ±4.5° random scatter per shot. |

**Examples:**
```gdscript
# Player-focus dive — locks on at spawn time and flies through
b.interceptor().at(-200, -420).move(b.player_focus(240))

# Strafing run from the side
b.interceptor().at(-500, 0).move(b.straight(200, PI / 2)).free_after(5.0)
```

---

### `drone_interceptor` — Drone Interceptor (Kamikaze Orbiter)

**Builder:** `b.drone_interceptor()`  
**Scene:** `drone_interceptor.tscn`  
**Movement:** ⚠️ **Self-managed AI. Do NOT add `.move()`.** Adding `.move()` disables `_physics_process` and breaks the AI entirely.  
**Shoots:** No — kamikaze dash on contact.  
**HP:** Very low  
**Score:** Low

**Behaviour phases:**
1. `ENTER` — flies toward the player.
2. `ORBIT` — circles the player for 1–2 seconds (randomised).
3. `DASH` — locks direction to predicted player position, flies at `dash_speed` indefinitely.

**Config fields** (`DroneInterceptorConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `orbit_radius` | 130.0 | Distance from player while orbiting. |
| `orbit_speed` | 1.8 rad/s | Counter-clockwise by default. |
| `approach_speed` | 200.0 | px/s during ENTER. |
| `orbit_correct_speed` | 160.0 | Max correction speed during ORBIT. |
| `dash_speed` | 480.0 | px/s during kamikaze DASH. |
| `dash_prediction_time` | 0.2 s | How far ahead to predict player position. |

**Examples:**
```gdscript
# Self-managed — just .at(), no .move()
b.drone_interceptor().at(-160, -420)
b.drone_interceptor().at( 160, -420).delay(0.35)
```

---

### `gunship` — Heavy Gunship

**Builder:** `b.gunship()`  
**Scene:** `gunship.tscn`  
**Movement:** ⚠️ **Self-managed AI. Do NOT add `.move()`.** Adding `.move()` disables `_physics_process` and breaks the AI entirely.  
**Shoots:** Yes — dual-barrel burst fire aimed at the player.  
**HP:** High (200)  
**Score:** High

**Behaviour phases:**
1. `ENTER` — drops straight down at `entry_speed` until `hold_y`.
2. `HOLD` — sits at fixed Y, tracks player horizontally, fires bursts. Sprite swaps at 50% HP.
3. `RETREAT` — flies straight up at `entry_speed × 1.5` when HP ≤ `retreat_hp_ratio`.

**`hold_y` formula:**  
`hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset`  
Default: `hold_y_offset = 55` → sits 55 px below the top screen edge in world space.

**Config fields** (`GunshipConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `burst_interval` | 1.0 s | Seconds between burst pairs. |
| `burst_gap` | 0.12 s | Delay between left and right shot in a burst. |
| `bullet_damage` | 15 | Per-bullet. |
| `bullet_speed` | 260.0 | px/s. |
| `entry_speed` | 60.0 | px/s descent and retreat. |
| `hold_y_offset` | 55.0 | px below viewport top where it holds. |
| `track_speed` | 70.0 | Max horizontal tracking speed. |
| `track_player` | true | Enable horizontal tracking during HOLD. |
| `retreat_hp_ratio` | 0.3 | HP fraction (0–1) that triggers RETREAT. |

**⚠️ Important:** The gunship descends to `hold_y` on its own. Its spawn Y should be above the visible screen (`y < -360` in design units / `y < -720` in world units after HD scale). Typical spawn: `at(0, -400)`.

**Examples:**
```gdscript
# Single gunship
b.gunship().at(0, -500)

# Two gunships staggered
b.gunship().at(-100, -400)
b.gunship().at( 100, -400).delay(0.8)

# Gunship with covering fighters — fighters use .move(), gunship does NOT
b.wave(50.0, [
    b.gunship().at(0, -400),
    b.fighter().at(-65, -400).move(b.arc(L, 145, 4.5)).delay(0.8).free_after(5.0),
    b.fighter().at( 65, -400).move(b.arc(R, 145, 4.5)).delay(0.8).free_after(5.0),
])
```

---

### `bomber` — Bomber

**Builder:** `b.bomber()`  
**Scene:** `bomber.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** Yes — drops bombs at `bomb_interval`.  
**HP:** Medium–High  
**Score:** Medium–High

**Config fields** (`BomberConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `movement_speed` | 80.0 | Irrelevant — use `.move()` speed. |
| `bomb_interval` | 1.2 s | Seconds between bombs. |

**Examples:**
```gdscript
# Slow straight dive with escort drones
b.bomber().at(0, -400).move(b.straight(82)).shoot_at_player()
b.drone().at(-72, -400).move(b.sine(170, -30)).delay(0.4)
b.drone().at( 72, -400).move(b.sine(170,  30)).delay(0.4)
```

---

### `bonus_drone` — Bonus Drone

**Builder:** `b.bonus_drone()`  
**Scene:** `bonus_drone.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** No.  
**Score:** Very high (medal enemy — does not count toward wave-clear bonuses).

**Notes:**
- Typically spawns from `level_director.gd` via `_spawn_bonus_drone()`, not from wave lists.
- Fast horizontal pass — `StraightMovement` at `angle = PI/2` or `-PI/2` with `free_after(4.0)`.
- Standard spawn offsets (design units): `Vector2(-680, 60)` for left-to-right, `Vector2(680, 60)` for right-to-left.

**Example (from level_1_director.gd pattern):**
```gdscript
# This is normally done via the section schedule, not as a wave entry.
# But if you do use it as a wave entry:
b.bonus_drone().at(-680, 60).move(b.straight(560, PI / 2)).free_after(4.0)
```

---

## Non-Enemy Spawns

### `ally` — Ally Fighter

**Builder:** `b.ally()`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Behaviour:** Friendly — kills enemies, ignored by player weapons.

```gdscript
b.ally().at(-180, 400).move(b.straight(165, PI - 0.2))
```

### `big_asteroid` / `small_asteroid` — Hazards

**Builders:** `b.big_asteroid()`, `b.small_asteroid()`  
**Movement:** Always add `.move()` — they have no AI.

```gdscript
b.big_asteroid().at(-195, -400).move(b.straight(210))
b.small_asteroid().at(-65, -400).move(b.straight(330)).delay(0.3)
```

---

## Movement Types

All movements are in design-unit speed (px/s in 640×360 space). `EnemyPathMover` multiplies by `WORLD_SCALE = 2.0` automatically.

| Builder | What it does | Key params |
|---------|-------------|------------|
| `b.straight(speed, angle, duration)` | Constant velocity in direction `angle`. `angle=0` = down. `duration=0` = forever. | `speed` (px/s), `angle` (rad), `duration` (s) |
| `b.sine(base_speed, amplitude, frequency)` | Forward movement with horizontal sine weave. | `base_speed`, `amplitude` (px), `frequency` (cycles/s, default 2.5) |
| `b.arc(direction, amplitude, duration)` | Circular sweep left or right. | `direction` (LEFT/RIGHT), `amplitude` (px, default 130), `duration` (s, default 3.5) |
| `b.u_sweep(sweep_width, sweep_depth, curve_duration)` | Dips down into a U shape then exits up. | `sweep_width` (px), `sweep_depth` (px), `curve_duration` (s) |
| `b.hold(duration)` | Sits still for N seconds. Use in `sequence()`. | `duration` (s) |
| `b.sequence(steps)` | Plays movements in order. Steps are any movement resources. | `steps: Array[MovementResource]` |
| `b.player_focus(speed)` | Locks direction toward the player at spawn time, then flies straight. | `speed` (px/s, default 220) |
| `b.curve(path, duration, loop)` | Follows a `Curve2D` path. | `path: Curve2D`, `duration` (s), `loop` (bool) |

**Direction constants:**
```gdscript
var L := WaveBuilder.LEFT   # ArcMovement.ArcDirection.LEFT
var R := WaveBuilder.RIGHT
```

**Angle quick-reference:**

| Value | Direction |
|-------|-----------|
| `0` | Down |
| `PI` | Up |
| `PI / 2` | Left |
| `-PI / 2` | Right |
| `PI / 4` | Down-left diagonal |
| `-PI / 4` | Down-right diagonal |

---

## Formation Types

Formations expand **one** `SpawnConfig` entry into N ships. Offsets and delays are relative to the base entry's `.at()` and `.delay()`.

| Builder | Shape | Key params |
|---------|-------|-----------|
| `b.v_formation(count, spread, row_gap, stagger)` | V shape, lead at front | `count`, `spread` (px, default 40), `row_gap` (px, default 12), `stagger` (s delay, default 0.1) |
| `b.wedge_formation(count, spread, row_gap, stagger)` | ^ shape, wings fan forward | Same as v_formation |
| `b.line_formation(count, spacing, axis)` | Horizontal or vertical line | `count`, `spacing` (px, default 30), `axis` (HORIZONTAL/VERTICAL) |
| `b.diagonal_formation(count, step_x, step_y, stagger)` | Diagonal stagger | `count`, `step_x` (px), `step_y` (px), `stagger` (s, default 0.15) |
| `b.cluster_formation(count, radius, seed_override)` | Random cluster | `count`, `radius` (px, default 30), `seed_override` (int) |

```gdscript
# V of 5 fighters straight down
b.fighter().formation(b.v_formation(5)).at(0, -400).move(b.straight(138)).shoot_forward()

# Diagonal formation from the right
b.fighter().formation(b.diagonal_formation(5, 30, 35)).at(370, -400).move(b.straight(220, -PI / 3.6))

# Random cluster of drones
b.drone().formation(b.cluster_formation(3, 30)).at(0, -400).move(b.straight(180))
```

---

## Quick Rules

| Rule | Detail |
|------|--------|
| **Always `.move()` path-following enemies** | `fighter`, `drone`, `ram`, `sniper`, `sniper_enemy`, `interceptor`, `bomber` — they have no self-managed movement. |
| **Never `.move()` self-AI enemies** | `drone_interceptor`, `gunship` — attaching `EnemyPathMover` disables their `_physics_process`. |
| **Off-screen entries need `.free_after()`** | Enemies entering from the sides never exit via the top/bottom. Without `free_after` they linger indefinitely. |
| **`sniper_enemy` needs a `sequence()`** | The approach step must be `straight(speed, 0.0, 2.5)` (exactly 2.5 s). Hold step must cover `shot_count × 2.5 s`. |
| **Gunship spawns above the screen** | Use `y` between `-400` and `-600` in design units so it enters from off-screen top. |
| **Offsets are design-unit (640×360 space)** | Do NOT multiply by 2. `WaveManager` handles the `WORLD_SCALE` conversion. |

---

## Not in this roster: the space-station mini-boss

`assault/scenes/enemies/space_station/` is a multi-part mini-boss, **not** a `WaveBuilder`-spawnable
wave enemy. It has no builder method and appears in no level yet. Placing it is sub-item 2 of the
Level 1 mini-boss epic in `BACKLOG.md`; behaviour and constraints are in
[`space_station/ENEMY.md`](../assault/scenes/enemies/space_station/ENEMY.md).
