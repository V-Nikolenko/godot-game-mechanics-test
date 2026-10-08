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

### `fighter` — Fighter

**Builder:** `b.fighter()`  
**Scene:** `fighter.tscn`  
**Movement:** AI (`FighterBrain` + `EnemyMover`): attack runs — a lead-in to a start point, a pass at a set lane beside the player, a wide turn, a reposition and a second pass. **Do NOT add `.move()` in a level wave**: a rail (`EnemyPathMover`) suspends the brain, and the fighter then fires the legacy weapon along the path (the station's TOP reinforcements still do this on purpose). Nothing in level 1 flies a fighter rail any more.  
**Squads:** a `.formation()` is automatically one squad. Loose `b.fighter()` lines in one `b.wave()` form a squad only if they share `.squad(&"<id>")`; level 1 uses `&"w<n>f"` (fighters) / `&"w<n>g"` (Gatlings) per wave. A loose line with no id is a squad of one. Roles: the closest leads head-on (FRONTAL pass), the next two close as a pincer (FLANK_LEFT / FLANK_RIGHT lanes), a 4th and later wait as REARs (dry passes, never fire). At most three fighters shoot at once. Details: `assault/scenes/enemies/fighter/ENEMY.md` → *Squad*.  
**Shoots:** Yes — a burst per pass leg, chosen by **distance** (never by a spawn property): an AIMED burst of 3–5 Pulse Rounds at the player's predicted point from 385 px and beyond, a FORWARD burst of 5–7 Scatter Rounds out of the nose below 325 px (in between: the last mode). A yellow light shows 0.3 s before every burst. `.shoot_forward()` / `.shoot_at_player()` are **rail-only** inputs.  
**Assault exit:** leaves by the nearest edge after `engage_seconds` (6.0 s) or two passes, curving out of the corridor (`test_level1_fighter_exit.gd`).  
**HP:** Low (60)  
**Score:** Low (25)

**Config fields** (`FighterConfig`): the full table is in `fighter/ENEMY.md`. The ones a level author meets:

| Field | Default | Notes |
|-------|---------|-------|
| `engage_seconds` | 6.0 s | Assault budget before DISENGAGE (pre-approved level-1 lever: 4.5). |
| `passes` | 2 | Passes per cycle. |
| `pass_offset`, `flank_lane_gap` | 160, 100 px | How far beside the player a pass goes. |
| `forward_range`, `mode_hysteresis` | 325, 60 px | The distance rule that picks the weapon. |
| `min_burst_period` | 1.2 s | The fewest seconds between two burst starts; sizes the pools. |
| `aim_mode`, `fire_interval`, `bullet_damage`, `rail_*` | `"PLAYER"`, 0.8 s, 8, … | **Rail fallback only** (`.move()`). |

**Examples:**
```gdscript
# A lone fighter — spawn and let it fly its own attack runs (no .move())
b.fighter().at(-160, -400).delay(0.5)

# A V of 3 is one squad: lead head-on, two flanks as a pincer
b.fighter().formation(b.v_formation(3, 80)).at(0, -420)

# A W of 5 adds two REARs (dry passes, never fire); the first spawns are staggered centre-out
b.fighter().formation(b.w_formation(5)).at(0, -420)

# Two loose fighters in one wave as one squad
b.fighter().at(-120, -400).squad(&"w9f")
b.fighter().at(120, -400).squad(&"w9f")

# On a rail (station reinforcement shape): legacy weapon, fired along the path
b.fighter().at(-60, -360).move(b.straight(180)).shoot_forward().free_after(6.0)
```

---
### `drone` — Swarm Drone

**Builder:** `b.drone()`  
**Scene:** `swarm_drone.tscn`  
**Movement:** ⚠️ **Self-managed squad AI. Do NOT add `.move()`** in a level wave. A rail suspends its brain and arms
its contact (it then flies the path and rams like the old Kamikaze Drone); only the space station's BOTTOM
reinforcement squad still does that on purpose.  
**Squads:** a `.formation()` is automatically one squad. Loose `b.drone()` lines in one `b.wave()` form a squad only
if they share `.squad(&"<id>")`; level 1 uses `&"w<n>"` for every wave with 2–7 loose drones. A loose line with no
id is a squad of one.  
**Shoots:** No — corkscrews in, winds up (yellow), rams the predicted player position (red), explodes on contact.  
**Assault exit:** leaves by the nearest edge after `engage_seconds` (5.5 s; REAR members after
`rear_engage_seconds`), so an ENEMIES_CLEARED section is never held open (`test_level1_drone_exit.gd`).  
**HP:** Very low  
**Score:** Very low

**Config fields** (`SwarmDroneConfig`): the full table is in `swarm_drone/ENEMY.md`.

**Examples:**
```gdscript
# A pair arriving from the top as one squad
b.drone().at(-260, -400).squad(&"w2"),
b.drone().at( 260, -400).delay(0.2).squad(&"w2"),

# A formation is one squad on its own
b.drone().formation(b.cluster_formation(3, 30)).at(0, -400).delay(0.4)

# Arriving from below
b.drone().at(-150, 400)
```

---

### `ram` — Ram Ship

**Builder:** `b.ram()`  
**Scene:** `ram_ship.tscn`  
**Movement:** Delegated to `EnemyPathMover`. **Always add `.move()`.**  
**Shoots:** No — high collision damage.  
**HP:** Bullet-proof until hit by a missile, then 100 HP (two bullets)  
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
**Scene:** `sniper.tscn`  
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

### `gatling_interceptor` — Gatling Interceptor

**Builder:** `b.gatling_interceptor()`  
**Scene:** `gatling_interceptor.tscn`  
**Movement:** AI (`GatlingInterceptorBrain`): holds side-on range on the player's flank, swings to the other flank between windows. **Do NOT add `.move()` in a level wave** — a rail suspends the brain and it fires the legacy stream along the path (only the station's LEFT/RIGHT reinforcements still do this). See `assault/scenes/enemies/gatling_interceptor/ENEMY.md`.  
**Shoots:** Yes — pressure windows: yellow spin-up, one 8–12-round Gatling Stream **aimed at the player's predicted position** (it never fires "forward"; the old "always fires forward" note was wrong), a pause, a swing. On a rail: the legacy constant stream (0.09 s, slight spread), also aimed at the player.  
**Assault exit:** leaves after `engage_seconds` (7.0 s), never starting a window it cannot finish. **Keep it out of `ENEMIES_CLEARED` sections** — its window deferral is not in the deadline formula (a boundary row in `test_engagement_deadline.gd` pins this).  
**Squads:** two Gatlings in one squad (a `.formation()` or a shared `.squad(&"<id>")`) charge together and cross their streams at the player's likely next position from the same side, leaving the other side open; a solo Gatling never does. See `ENEMY.md` → *Convergence fire*.  
**HP:** Low–Medium  
**Score:** Medium

**Config fields** (`GatlingInterceptorConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `preferred_range` | 380 px | Side-on distance a window is fired from. |
| `stream_rounds_min/max`, `stream_interval` | 8 / 12, 0.09 s | One stream per window. |
| `round_speed`, `round_damage` | 240, 4 | The AI stream's Gatling Stream rounds. |
| `engage_seconds` | 7.0 s | Assault budget before it leaves. |
| `convergence_bearing_offset_deg`, `convergence_aim_error_deg`, `convergence_join_range_factor` | 40°, 3°, 1.5 | Convergence fire for a squad of two or more: the FLANK's bearing offset from the LEAD, each shooter's per-window aim error, and the FLANK's join range (× `preferred_range`). |
| `rail_stream_interval`, `rail_stream_speed`, `rail_spread`, `rail_damage` | 0.09 s, 220, 0.08 rad, 4 | The rail (`.move()`) fallback: the legacy constant stream. |

Full table in `ENEMY.md`.

**Examples:**
```gdscript
# A Gatling pair in one squad: they charge together and cross their streams
b.gatling_interceptor().at(-200, -420).squad(&"w0g")
b.gatling_interceptor().at(200, -420).squad(&"w0g")

# A lone Gatling
b.gatling_interceptor().at(0, -420)

# On a rail (station reinforcement shape): the legacy constant stream
b.gatling_interceptor().at(-500, 0).move(b.straight(200, PI / 2)).free_after(5.0)
```

---

### `razor_drone` — Razor Drone (orbiting duellist)

**Builder:** `b.razor_drone()`  
**Scene:** `razor_drone.tscn`  
**Movement:** ⚠️ **Self-managed AI. Do NOT add `.move()`.** A rail suspends its brain.  
**Shoots:** One pulse shot (10 dmg, 250 px/s), only after a *missed* dash.  
**Contact:** RAMMING — hurts (30) only while it is dashing (red light).  
**HP:** Very low (25)  
**Score:** Low (40)

**Behaviour** (full detail in `razor_drone/ENEMY.md`):
1. `ENTER` — flies toward the player.
2. `ORBIT` — circles the player. Every 1–2 s it rolls to reverse its orbit, to fake a dash, or to make a real one.
3. **Fake:** a long yellow wind-up, a lunge that passes 70 px beside the player, a brake on the far side, then
   straight into a real wind-up.
4. **Real:** yellow 0.5 s, white 0.12 s (only a real dash is ever white), then a dash through the predicted player
   position. It survives, curves back round and returns to orbit.
5. Assault only: it attacks from a 30°–75° side lane, stays inside the corridor, and leaves by the nearest edge after
   9 s.

**Config fields** (`RazorDroneConfig`): the full table is in `razor_drone/ENEMY.md`. The key ones:

| Field | Default | Notes |
|-------|---------|-------|
| `orbit_radius` / `orbit_speed` | 130 / 1.8 rad/s | The orbit ring |
| `reverse_chance` / `fake_chance` | 0.35 / 0.35 | Roll odds |
| `windup_seconds` / `commit_flash_seconds` | 0.5 / 0.12 s | Telegraph |
| `dash_speed` | 480 | px/s |
| `engage_seconds` | 9.0 s | Assault time in the fight |

**Examples:**
```gdscript
# Self-managed — just .at(), no .move()
b.razor_drone().at(-160, -420)
b.razor_drone().at( 160, -420).delay(0.35)
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
| `b.w_formation(count, spread, depth, stagger)` | W shape: centre and outer slots forward, the odd slots trail | `count` (5), `spread` (px, 60), `depth` (px the odd slots trail, 40), `stagger` (s per step out from the centre, 0.1). Spawns centre first (`WFormation`, Ph3) |

**A formation is a spawn layout, not a behaviour.** The slots only decide where and when the ships appear. An AI enemy
(`fighter`, `gatling_interceptor`, `drone`) then takes its role from the squad's `SquadController` — closest = LEAD, the
next two = flanks, the rest = REARs, recomputed whenever someone joins or leaves — and the layout is forgotten. A
formation with `.move()` on a rail ship keeps its shape for as long as the rail runs. (Ph3: `test_wave_builder_formations.gd`
for the layout, `test_fighter_squad.gd` for the handoff.) A W5 of fighters is LEAD + two flanks + two dry REARs; only three
ever shoot.

```gdscript
# V of 5 fighters: one squad (lead + two flanks + two dry REARs), flying its own attack runs
b.fighter().formation(b.v_formation(5)).at(0, -400)

# Diagonal formation of rail ships from the right (a rail keeps the shape)
b.ram().formation(b.diagonal_formation(5, 30, 35)).at(370, -400).move(b.straight(220, -PI / 3.6))

# Random cluster of drones
b.drone().formation(b.cluster_formation(3, 30)).at(0, -400)
```

---

## Enemy Rounds (the bullet family, Ph3)

`assault/scenes/projectiles/enemy_bullet/rounds/` holds four **pooled** enemy rounds, each an inherited scene of
`enemy_bullet.tscn` (so each is an `EnemyBullet` with a `ProjectileLifetime`). `EnemyRounds` (`enemy_rounds.gd`) holds
the four `PackedScene` constants and `pool_size_for()`. A shooter picks one by giving its `BulletPool.bullet_scene`
that scene — there is no per-bullet script and no per-round retuning.

| Round | Constant | Scene speed | Damage | Lifetime (`max_time` / `max_distance`) | Look | Used by |
|---|---|---|---|---|---|---|
| Pulse | `EnemyRounds.PULSE` | 300 | 8 | 8 s / 1400 px | red-pink bolt, 3 px wide | Fighter (AIMED burst) |
| Scatter | `EnemyRounds.SCATTER` | 420 | 6 | 2 s / 450 px | short pink pellet, 4 px wide, 2 px hitbox | Fighter (FORWARD burst) |
| Gatling Stream | `EnemyRounds.GATLING_STREAM` | 240 | 4 | 8 s / 1400 px | thin red streak, 2 px wide | Gatling Interceptor |
| Heavy Shell | `EnemyRounds.HEAVY_SHELL` | 160 | 20 | 12 s / 1800 px | big pale-pink slug with a dark rim | **nobody yet** (first consumer: Ph4 Bomber/Ram or Ph10 Gunship) |

- **One pool per round per shooter**, a direct child of the enemy root. Size it with
  `EnemyRounds.pool_size_for(max_burst, round_lifetime, min_burst_period)`; a self-timed rail pattern is a burst of 1
  at its own interval. The shooter's pattern may still override `speed` / `damage` on the acquired bullet;
  `EnemyBullet.reset()` restores the scene's own authored values on reuse.
- `enemy_bullet.tscn` itself stays the legacy orange bolt, and every other enemy (Gunship, Bomber, Sniper, Ram, the
  drones' pulse shots) keeps it until the Ph17 audit.
- Each round's `max_distance / slowest speed any shooter fires it at` must fit its `max_time`
  (`test_enemy_bullet_lifetime.gd`), reading the speeds from the shooters' config fields.
- Tests: `tests/integration/test_enemy_rounds.gd` (shape, reset, lifetimes, the Heavy Shell fixture shooter).

---

## Quick Rules

| Rule | Detail |
|------|--------|
| **Always `.move()` path-following enemies** | `ram`, `sniper`, `sniper_enemy`, `bomber` (the `fighter` and `gatling_interceptor` are AI enemies; `.move()` puts them on a rail) — they have no self-managed movement. |
| **Never `.move()` self-AI enemies** | `drone`, `razor_drone`, `gunship`, `fighter`, `gatling_interceptor` — attaching `EnemyPathMover` suspends their AI. `fighter` and `gatling_interceptor` fall back to the legacy weapon on a rail (so the station's reinforcements still fire); everything else in this list goes quiet. |
| **Off-screen entries need `.free_after()`** | Enemies entering from the sides never exit via the top/bottom. Without `free_after` they linger indefinitely. |
| **`sniper_enemy` needs a `sequence()`** | The approach step must be `straight(speed, 0.0, 2.5)` (exactly 2.5 s). Hold step must cover `shot_count × 2.5 s`. |
| **Gunship spawns above the screen** | Use `y` between `-400` and `-600` in design units so it enters from off-screen top. |
| **Offsets are design-unit (640×360 space)** | Do NOT multiply by 2. `WaveManager` handles the `WORLD_SCALE` conversion. |

---

## Not in this roster: the space-station mini-boss

`assault/scenes/enemies/space_station/` is a multi-part mini-boss, not a regular wave enemy — it
has no movement, no exit mode and four independently destructible turrets, so the roster's
per-enemy stat columns do not describe it.

It **is** `WaveBuilder`-spawnable: `b.space_station()` (`SPACE_STATION` const). It is spawned
exactly once, by the `station_assault` section of Level 1, as
`b.wave(0.0, [ b.space_station().at(0, -90) ])`. Two rules, both load-bearing:

- **No `.delay()`.** `waves_complete` fires when the last wave *triggers*, not when its spawns
  land, so a delayed boss lets an `ENEMIES_CLEARED` section see an empty container and advance
  instantly.
- **No `.move()`.** A `MovementResource` attaches an `EnemyPathMover`, which would free the boss
  on screen exit mid-fight. This is now doubly load-bearing: the laser phase writes
  `station.rotation` directly, so an `EnemyPathMover` would also be fighting it for control.

It has a **second phase**: once the last turret dies the station rotates and fires telegraphed
`LaserRay` volleys (`StationLaserPhase`). Nothing about spawning changes, but the boss stops being
a stationary target, and its rotating 240×240 core hurtbox sweeps ~34 px past its axis-aligned
footprint at 45°.

**It also spawns other enemies from this roster.** During phase 1 only, `StationReinforcements`
sends squads across the arena on a fixed `LEFT → RIGHT → BOTTOM → TOP` cycle: two `gatling_interceptor`
from either side, two `swarm_drone` from below, two `fighter` with `.shoot_forward()` from
above. Things to know if you edit that table (`station_reinforcements.gd::_build_squads()`):

- It uses this file's own vocabulary — `b.gatling_interceptor().at(…).move(b.straight(…)).free_after(…)` —
  so the rules below apply unchanged. In particular **`gunship` and `razor_drone` must never
  go in it**: both are self-managed AI, and `EnemyPathMover` silently disables the AI they need.
  A test enforces that.
- **Every entry needs `.free_after(…)`.** The default `FREE_ON_SCREEN_EXIT` only culls a ship that
  has already been on screen once, so one that never arrives would hold `ENEMIES_CLEARED` open.
- **A squad ship must be killable by the player's primary weapon.** `ram_ship` is not:
  `ram_ship.gd` narrows its HurtBox mask to 33, which excludes the bullet's layer 64. A test
  checks every ship in the table for this.

Behaviour and constraints: [`space_station/ENEMY.md`](../assault/scenes/enemies/space_station/ENEMY.md).
