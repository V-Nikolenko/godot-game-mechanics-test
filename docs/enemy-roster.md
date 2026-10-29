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

### `ram` — Ram Corvette

**Builder:** `b.ram()`  
**Scene:** `ram_corvette.tscn`  
**Movement:** AI (`RamCorvetteBrain`): approaches at `cruise_speed` (in Assault toward a point beside and above/below the player, so its charge is diagonal), lines up on where the player will be, winds up with its plates glowing (0.65 s, a crawl - the player's window), rams in a straight line 220 px past that point and swings round in a wide 1.4 rad/s turn to go again. A plate broken during its line-up or wind-up staggers it (0.4 s, charge cancelled). Exposed: cruise 340, charge 700, strafes out of the player's aim. In Assault it gets one charge per life and leaves after `engage_seconds` (4.0 s), straight along its charge if the time runs out mid-charge. **Level 1 gives it no rail in any section (t21, t22)**; on a rail its brain is suspended and its ARMOR contact stays armed.  
**Shoots:** No — contact damage 50 armoured (with a shove), 60 once exposed.  
**HP:** three armour plates (50 each) over a 120 HP hull. Bullets glance off plates and hull (not consumed); each rocket breaks the plate it hits; a Sniper Shot chips a plate (40) and flies on; only with every plate gone does the hull take damage. One homing volley strips all three plates.  
**Score:** Medium (35)

**Config fields** (`RamCorvetteConfig`, flat):

| Field | Default | Notes |
|-------|---------|-------|
| `max_health` | 120 | The hull, once exposed. |
| `plate_health` | 50 | Each of the three plates. |
| `collision_damage` / `exposed_collision_damage` | 50 / 60 | Contact, armoured / exposed. |
| `armor_shove_speed` | 260.0 | ARMOR contact shove while armoured; 0 once exposed. |
| `cruise_speed` / `acceleration` / `max_turn_rate` | 280 / 500 / 2.2 | Mover caps. |
| `engage_seconds` / `exit_speed` | 4.0 / 560 | Assault budget and exit (4.5 / 500 until t22: both pre-approved levers, for Cloud Descent's ENEMIES_CLEARED deadline). |
| `engage_range` / `assault_side_offset` | 420 / 240 | LINE_UP range; Assault approach offset (each axis). |
| `line_up_cap` / `braking` | 0.5 / 1600 | Max line-up; the hard brake used only while it stops to aim. |
| `wind_up_seconds` / `crawl_speed` | 0.65 / 20 | The telegraph. |
| `charge_speed` / `exposed_charge_speed` | 620 / 700 | The ram. |
| `overshoot` / `charge_max_time` | 220 / 1.45 | Past the aim point; hard cap on the boost. |
| `wide_turn_rate` | 1.4 | rad/s after a charge. |
| `exposed_cruise_speed` | 340 | Once every plate is gone. |
| `evade_cone_deg` / `evade_range` / `evade_speed` | 20 / 600 / 180 | Exposed strafe out of the player's aim. |
| `stagger_seconds` | 0.4 | Charge cancelled by a broken plate. |

**Examples:**
```gdscript
# Spawn it and let it fly its own charges (no .move()) - level 1's shape
b.ram().at(0, -400)

# A pair from the sides, staggered
b.ram().at(-255, -400)
b.ram().at( 255, -400).delay(0.5)

# Surprise from below
b.ram().at(0, 400)

# On a rail (legacy shape): the brain is suspended, the ARMOR contact stays armed, nothing else happens
b.ram().at(0, -400).move(b.straight(280))
```

---

### `sniper` — Sniper (alias `sniper_enemy`)

**Builder:** `b.sniper()` (alias `b.sniper_enemy()`)  
**Scene:** `sniper.tscn`  
**Movement:** AI (`SniperBrain`): a relocation cycle — flies to its nearest legal firing point, settles, aims (1.3 s, dim line) and locks (0.5 s, bright line) standing still, fires one rail round (with a fading `RailTrail`), breaks contact, then relocates to a new firing angle at least 45° round the player, never across it; it holds fire when a rock blocks its line of sight. In Assault the firing points stay a margin inside the corridor and a budget expiry in AIM/LOCK waits for the shot. **Level 1 gives it no rail in any section (t21, t22)**; a rail still suspends the brain and `SniperTelegraph` runs the legacy cycle (aim 2.0 s, lock 0.5 s, a 1400 px/s round, 5 shots), starting at spawn. There is no fly-in constant to match any more.  
**Shoots:** Yes — one rail round per telegraphed shot (`rail_round.tscn`).  
**Assault exit:** leaves after `engage_seconds` (9.0 s).  
**HP:** 60 · **Score:** 50  

See `assault/scenes/enemies/sniper/ENEMY.md`.

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
**Movement:** AI-driven (`BomberBrain` + `EnemyMover`); `.move()` puts it on a rail, where it drops a gravity bomb DOWN every `rail_bomb_interval`. Off rails it flies bombing runs (Phase 4 t10): a mine wall across where a moving player is heading, a gravity bomb on a slow close player, a pursuit bomb on a far or boosting one, then an escape arc — see `bomber/ENEMY.md`. Level 1 spawns it off rails since t21.  
**Shoots:** Yes — gravity bombs, mines, pursuit bombs (`EnemyOrdnance`), shootable.  
**HP:** 150 (a wide 96 × 44 body: the wings are shootable); every bomb, mine and pursuit bomb it leaves can be shot down  
**Score:** 80 (ordnance scores nothing)

**Config fields** (`BomberConfig`):

| Field | Default | Notes |
|-------|---------|-------|
| `max_speed` | 240.0 | Transit speed. |
| `run_speed` | 170.0 | Bombing-run speed. |
| `rail_bomb_interval` | 1.2 s | Seconds between bombs while on a rail. |

(Plus the ordnance and prediction fields: read `bomber_config.gd`.)

**Examples:**
```gdscript
# Spawn it and let it fly its own bombing run (no .move()) - level 1's shape
b.bomber().at(0, -400)

# With escort drones (the drones are AI too)
b.bomber().at(0, -400)
b.drone().at(-72, -400).delay(0.4)
b.drone().at( 72, -400).delay(0.4)

# On a rail (legacy shape): a gravity bomb straight down every rail_bomb_interval
b.bomber().at(0, -400).move(b.straight(82))
```

---

### `missile_corvette` — Missile Corvette

**Builder:** `b.missile_corvette()`  
**Scene:** `missile_corvette.tscn`  
**Movement:** AI-driven (`MissileCorvetteBrain` + `EnemyMover`); closes to its held range (620 Open Space / 460 Assault), then circles the player on a broad, drifting, reversing arc with its nose on them, breaking off sideways inside `min_range` 380. Fires a telegraphed (0.7 s, tubes glow) salvo of 3 rockets (2 Warheads) only at a player inside its 45° nose cone, every 4–5 s, aimed at where the player is heading (kind by distance and motion: Warhead < 420 px, Pursuit at a fleeing player, Cluster at a far crossing one, else Dumb). Leaves when its Assault budget (`engage_seconds` 7.0) ends, after any salvo it has started. `.move()` puts it on a rail, where it fires a Dumb rocket DOWN every `rail_rocket_interval`. See `missile_corvette/ENEMY.md`.  
**Shoots:** Rockets (`EnemyRocket`: Dumb, Pursuit, Cluster, Delayed Warhead) from four persistent pools; every rocket can be shot down.  
**HP:** 160 (a 40 px circle); contact damage 30  
**Score:** 70 (rockets score nothing)

**Config fields** (`MissileCorvetteConfig`): `max_speed` 210, `acceleration` 240, `salvo_count` 3, `warhead_salvo_count` 2, `salvo_period_min` 4.0, `rail_rocket_interval` 2.5 s — the rest in `missile_corvette_config.gd`.

**Level 1:** deep_space 12.0 s, planet_approach 40.0 s and 85.0 s, AI-driven (no `.move()`). **Never place it in an `ENEMIES_CLEARED` section** — its persistent rockets would hold the section open (`test_engagement_deadline.gd`).

**Examples:**
```gdscript
b.missile_corvette().at(0, -400)
```

---

### `support_ship` — Support Ship

**Builder:** `b.support_ship()`  
**Scene:** `support_ship.tscn`  
**Movement:** AI-driven (`SupportShipBrain` + `EnemyMover`); shadows the highest-threat AI-driven ally worth >= 20 (never a Swarm Drone, Gunship, Bonus Drone or another support) from behind, jinks and evades the player, re-picks a ward the tick its ward dies, and in Assault stays inside the camera view; with no ward it holds near the nearest ally (Assault: leaves after 1.5 s in view without one). Leaves when its Assault budget (`engage_seconds` 9.0) ends. Unarmed: no rail fallback. It repairs its ward in pulses (`BaseEnemy.repair()`), projects a cyan `EnemyShield` arc onto it (a 360° bubble during the emergency escort) and tows a badly hurt ward away through `accept_tow()`; see `support_ship/ENEMY.md`.  
**Shoots:** Nothing.  
**HP:** 55 (a 34 px circle); contact damage 0 (`ContactProfile` NONE; it cannot be repaired by another support)  
**Score:** 60

**Level 1:** with deep_space's 26.0 s ram pair and planet_approach's 28.0 s ram triple, 60 units behind the ram (`.at(x, -460)` against the ram's -400), AI-driven. Kept out of `ENEMIES_CLEARED` sections.

**Examples:**
```gdscript
b.support_ship().at(0, -400)
```

---

### `mine_layer` — Mine Layer

**Builder:** `b.mine_layer()`  
**Scene:** `mine_layer.tscn`  
**Movement:** AI-driven (`MineLayerBrain` + `EnemyMover`). Open Space: idles at its patrol point, then, once it notices the player, orbits at 600 px and flies **passes** — it closes on a run-in point, then crosses the player's path sideways at `lay_speed` 170, laying one line of 6 mines (ZIGZAG or ARC, 600 px) from its stern, breaks off and repositions; one line every ~10-14 s. Assault: the same logic clamped to the corridor, **one pass per life** along the horizontal axis, then it leaves. `.move()` puts it on a rail, where it drops a PROXIMITY mine every `rail_mine_interval` 1.6 s.  
**Shoots:** No guns. Mines (`EnemyMine`: proximity 50 %, chain 20 %, pulse 15 %, homing 15 % by default; drifting and EMP weight 0) from four persistent pools; a player bullet defuses a mine (a chain mine detonates).  
**HP:** 140 (an r 40 circle, ~96 px hull); contact damage 25 (COLLISION)  
**Score:** 60 (mines score nothing)

**Config fields** (`MineLayerConfig`): `max_speed` 240, `lay_speed` 170, `exit_speed` 300, `mines_per_pass` 6, `pass_length` 600, `mine_step` 100, `max_live_mines` 18 / `assault_max_live_mines` 8, `assault_mine_life` 9.0 s, `open_space_mine_life` 0 (never fizzles) with a 240 s backstop, `engage_seconds` 9.0, `pass_period_min`/`max` 5-7 s, `perceive_radius` 650 / `lose_radius` 1500, `rail_mine_interval` 1.6, mine weights `w_*` — the rest in `mine_layer_config.gd`. `.tres` wins over the scene.

**Level 1:** deep_space 16.0 s (from the left) and planet_approach 47.0 s (from the right), AI-driven (no `.move()`). **Never place it in an `ENEMIES_CLEARED` section** — its persistent mines would hold the section open (`test_engagement_deadline.gd`). **Hub:** one patrols a 2600 px ring at bearing −22.5°. Counts as a specialist in the frozen 2.5× density gate (`EXPECTED_PH7`).

**Examples:**
```gdscript
# Spawn it and let it fly its own pass (no .move()) - level 1's shape
b.mine_layer().at(-400, -160)

# On a rail (legacy shape): a proximity mine every rail_mine_interval
b.mine_layer().at(0, -400).move(b.straight(82))
```

---

### `defense_turret` — Stationary Defense Turret

**Builder:** `b.defense_turret()`  
**Scene:** `defense_turret.tscn`  
**Movement:** None: no `EnemyMover`, and the root never rotates. Its weapon mount turns its head (2.0 rad/s), scans a 90° arc when idle, notices the player (Open Space: within 900 px, lost beyond 1100; Assault: once its centre is inside the view) and tracks them. In Assault an `AssaultDrift` child scrolls it down at 60 px/s like wreckage and frees it below the world; it never counts as an escape.  
**Shoots:** The weapon is its mount (`TurretMount`), picked with `.prop("variant", TurretMount.Variant.X)`. Built so far: BURST_CANNON (variant 0), a 0.4 s charge then 4 Pulse rounds (8 dmg, 300 px/s) 0.12 s apart with a 0.6 partial lead, then 2.2 s cooldown. It holds fire without line of sight (a wreck or asteroid between) and never fires from off-screen. SWEEP_BEAM (a 0.9 s line at the start bearing on the side the player is moving from, then a 2.0 s sweep of 100 degrees; range 400), LANCE (1.0 s warning, aim locked for the last 0.5 s, one 24-damage hit; range 1100) and BEAM_CANNON (0.9 s warning on a bearing frozen when it appears, 1.2 s lit; range 700) fire `EnemyBeam`s that hurt everything on their line except the turret and its group. The rocket battery and pulse ring arrive in t8.  
**HP:** 90 (an r 28 circle); contact damage 0 (`ContactProfile` NONE, no `ContactHitBox`)  
**Score:** 60 (`counts_as_escape` false)

**Config fields** (`DefenseTurretConfig`): `perceive_radius` 900, `lose_radius` 1100, `notice_time` 0.3, `assault_drift_speed` 60. Weapon tuning lives in the mount scene (`defense_turret/mounts/burst_cannon_mount.tscn`), never in the config.

**Not placed in level 1 or the hub yet.** **Never place it in an `ENEMIES_CLEARED` section** (persistent fire).

**Examples:**
```gdscript
b.defense_turret().at(-200, -100)
b.defense_turret().at(200, -100).prop("variant", TurretMount.Variant.BURST_CANNON)
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

### Hazard profile and wrecks (Phase 6)

Every mover-driven enemy carries three flat `ShipConfig` hazard fields and three wreck fields (`@export_group("Hazards")`).
Avoidance 0..1 is how readily the mover's context-steering stage steers round a hazard, margin is the skim distance in px,
resistance 0..1 scales the pull and slow the ship feels. A `boost()` (every committed attack) ignores avoidance. The wreck
columns are rolled once on death from the brain's seeded `rng`; with no `HazardContainer` nothing spawns. Wreck size:
0 small, 1 medium, 2 large. Rails, the Gunship and the station are untouched.

| Enemy | avoidance | margin | resistance | wreck chance | wreck size | explosive chance |
|---|---|---|---|---|---|---|
| Swarm Drone | 1.0 | 12 | 0.0 | 0 | small | - |
| Razor Drone | 1.0 | 16 | 0.0 | 0 | small | - |
| Fighter | 0.8 | 60 | 0.1 | 0.2 | small | - |
| Gatling Interceptor | 0.8 | 60 | 0.15 | 0.2 | small | - |
| Bomber | 0.6 | 70 | 0.4 | 0.6 | large | 0.5 |
| Sniper | 1.0 | 90 | 0.1 | 0.3 | small | - |
| Ram Corvette | 0.5 | 60 | 0.5 | 0.5 | medium | - |
| Missile Corvette | 0.7 | 80 | 0.4 | 0.5 | medium | 0.5 |
| Support Ship | 1.0 | 80 | 0.1 | 0.3 | small | - |

Hazards as tools: the Sniper fires from the far side of a wreck, a solo Fighter or squad LEAD waits behind one (COVER) before a
pass, and a Ram near a gravity well lines up its charge to shove the player in. Breaking a Ram plate throws a 12-damage
`DebrisFragment`. See each `ENEMY.md` and `assault/scenes/hazards/*/HAZARD.md`.

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

`assault/scenes/projectiles/enemy_bullet/rounds/` holds five **pooled** enemy rounds, each an inherited scene of
`enemy_bullet.tscn` (so each is an `EnemyBullet` with a `ProjectileLifetime`). `EnemyRounds` (`enemy_rounds.gd`) holds
the five `PackedScene` constants and `pool_size_for()`. A shooter picks one by giving its `BulletPool.bullet_scene`
that scene — there is no per-bullet script and no per-round retuning.

| Round | Constant | Scene speed | Damage | Lifetime (`max_time` / `max_distance`) | Look | Used by |
|---|---|---|---|---|---|---|
| Pulse | `EnemyRounds.PULSE` | 300 | 8 | 8 s / 1400 px | red-pink bolt, 3 px wide | Fighter (AIMED burst) |
| Scatter | `EnemyRounds.SCATTER` | 420 | 6 | 2 s / 450 px | short pink pellet, 4 px wide, 2 px hitbox | Fighter (FORWARD burst) |
| Gatling Stream | `EnemyRounds.GATLING_STREAM` | 240 | 4 | 8 s / 1400 px | thin red streak, 2 px wide | Gatling Interceptor |
| Rail | `EnemyRounds.RAIL` | 2200 | 28 | 4 s / 2400 px | white-hot 3 px core with a glow, and a fading `RailTrail` behind it | Sniper (AI shot; its rail fallback fires 1400 px/s for 25) |
| Heavy Shell | `EnemyRounds.HEAVY_SHELL` | 160 | 20 | 12 s / 1800 px | big pale-pink slug with a dark rim | **nobody yet** (Ph4's Bomber and Ram fire no rounds; first consumer: Ph10 Heavy Gunship) |

- **One pool per round per shooter**, a direct child of the enemy root. Size it with
  `EnemyRounds.pool_size_for(max_burst, round_lifetime, min_burst_period)`; a self-timed rail pattern is a burst of 1
  at its own interval. The shooter's pattern may still override `speed` / `damage` on the acquired bullet;
  `EnemyBullet.reset()` restores the scene's own authored values on reuse.
- `enemy_bullet.tscn` itself stays the legacy orange bolt, and every other shooter (Gunship, the drones' pulse shots)
  keeps it until the Ph17 audit. The Bomber and the Ram fire no rounds.
- Each round's `max_distance / slowest speed any shooter fires it at` must fit its `max_time`
  (`test_enemy_bullet_lifetime.gd`), reading the speeds from the shooters' config fields.
- Tests: `tests/integration/test_enemy_rounds.gd` (shape, reset, lifetimes, the Heavy Shell fixture shooter).

### Enemy ordnance (Ph4)

Not rounds: `assault/scenes/projectiles/enemy_ordnance/` holds the Bomber's gravity bomb, proximity mine and pursuit
bomb (`EnemyOrdnance`, an `Area2D`; not an `EnemyBullet`, not in `enemies`, never scored). Any player hit defuses one.
Its pools set `persist_after_owner_death`, so what a Bomber dropped outlives it. See `docs/BULLET_POOL.md` and
`bomber/ENEMY.md`.

The proximity mine is the first of the Ph7 **mine family** (`EnemyMine`, `mines/`): PROXIMITY (this one), DRIFTING, HOMING, CHAIN, PULSE (boost
disruption) and EMP, laid by the Mine Layer (`mine_layer/ENEMY.md`) or placed in a `Minefield` (`hazards/minefield/HAZARD.md`). Every mine registers as a
`&"mine"` hazard, so enemies steer round it. Detail: [assault.md](architecture/modules/assault.md) → *Mines and the Mine Layer*.


### Enemy rockets (Ph5)

`assault/scenes/projectiles/enemy_rockets/` holds the Missile Corvette's ordnance: `EnemyRocket` (`enemy_rocket.gd`, an
`Area2D`; one script, `kind` plus exports, no per-kind subclass), `EnemyRocketScenes` (`scene_for(kind)`,
`pool_size_for(kind, cfg)`, `export_of(kind, property, fallback)`) and five scenes. Not rounds and not in `enemies`; never
scored. **Tuning lives in each scene's exports.** Art and `rotation` are nose-up.

| Kind | Scene | Speed (launch → cruise) | Steering | Impact / blast | Life |
|---|---|---|---|---|---|
| Dumb | `dumb_rocket.tscn` | 140 → 520, accel 900 | none (straight at the aim point) | 16 / 36 px, 16 | 4 s / 1800 px |
| Pursuit | `pursuit_rocket.tscn` | 120 → 520, accel 600 | `turn_rate` 1.6 rad/s for `guidance_seconds` 3.0 toward the player's predicted path (`lead_max` 0.8 s) | 18 / 40 px, 18 | 6 s / 2400 px |
| Cluster | `cluster_rocket.tscn` | 120, accel 600 | `turn_rate` 0.7 for 4.0 s; splits within `split_distance` 260 px of the player or at `split_time` 2.0 s into 4 submunitions on a 36° fan, no blast | 16 / 36 px, 16 | 4 s / 1200 px |
| Delayed Warhead | `delayed_warhead.tscn` | 100, accel 300 | `turn_rate` 0.6 for 4.0 s; a player (or any layer-128 hurtbox) inside `trigger_radius` 70 px after `prox_arm_seconds` 0.6 stops it dead; it blinks and detonates after `warning_time` 0.4 s | 12 / 110 px, 30 | 7 s / 1300 px |
| Submunition | `submunition.tscn` | 520, no accel | none; unpooled, frees itself | 8 / 22 px, 8 | 1.2 s / 600 px |

- **Collision (no layer renamed):** the impact `HitBox` is on layer 32 only (`CollisionLayers.PLAYER_ROCKETS`; the name predates
  enemy rockets), mask 128 | 512, closed until the rocket is clear of its launcher (`rocket_clear_radius()`). The shoot-down
  `HurtBox` is on 512, mask 96. So the **impact** hurts enemies, enemy ordnance, Ram plates and asteroids; the **blast**
  (`ContactBlast`, layer 256) is the only thing that hurts the player or allies. A player bullet or missile and a rocket destroy
  each other with no blast; rockets ignore each other; an armoured hull lets a rocket through (`ArmorQuery`).
- **Launcher contract:** `launch(dir, aim_point, launcher)`; the launcher answers `launch_velocity()` (inherited along `dir`) and
  `rocket_clear_radius()`. A launcher that counts `expired` must allow the two-tick lag after a detonation or shoot-down.
- **Pools** are direct root children with `persist_after_owner_death`; submunitions are unpooled and own themselves. See
  `docs/BULLET_POOL.md` ("Enemy rockets").
- Tests: `tests/integration/test_enemy_rockets.gd` (both harnesses plus real-physics shoot-down, friendly-fire and pool hand-over
  rows), `test_enemy_bullet_lifetime.gd` (lifetime rows), `tests/helpers/rocket_launcher_fixture.gd`.

---

## Quick Rules

| Rule | Detail |
|------|--------|
| **Always `.move()` path-following enemies** | None left on the AI roster. `ram`, `sniper` / `sniper_enemy` and `bomber` are AI enemies since Phase 4 (level 1 spawns them with no `.move()` in every section, t21 / t22); a rail still works and runs each one's rail fallback (sniper telegraph cycle, bomber rail bombs, ram straight line). |
| **Never `.move()` self-AI enemies** | `drone`, `razor_drone`, `gunship`, `fighter`, `gatling_interceptor`, `ram`, `sniper`, `bomber` — attaching `EnemyPathMover` suspends their AI. `fighter`, `gatling_interceptor`, `sniper` and `bomber` fall back to a legacy weapon on a rail (so the station's reinforcements still fire); the ram keeps its ARMOR contact armed; the rest go quiet. |
| **Off-screen entries need `.free_after()`** | Enemies entering from the sides never exit via the top/bottom. Without `free_after` they linger indefinitely. |
| **`sniper_enemy` on a rail** | No fly-in constant any more: a rail suspends the brain and the telegraph cycle starts at spawn. Without `.move()` it runs its AI relocation loop. |
| **Gunship spawns above the screen** | Use `y` between `-400` and `-600` in design units so it enters from off-screen top. |
| **Offsets are design-unit (640×360 space)** | Do NOT multiply by 2. `WaveManager` handles the `WORLD_SCALE` conversion. |
| **Rockets hurt enemies by impact only** | An `EnemyRocket`'s impact hits enemies, ordnance, Ram plates and asteroids; its blast hurts only the player and allies. Never put a rocket launcher where its own rockets can overlap its hull (`rocket_clear_radius()`). |
| **Supports never repair supports** | A `SupportShip` is never a ward and `can_be_repaired()` is false; it deals 0 contact damage. |
| **`missile_corvette` and `support_ship` are DURATION-only** | Never place either in an `ENEMIES_CLEARED` section: rockets persist and hold the section open, and a support has no wave-clear role (`test_engagement_deadline.gd`). |
| **`mine_layer` (and anything that drops persistent mines) is DURATION-only** | Never place it in an `ENEMIES_CLEARED` section: mines outlive the layer (`assault_mine_life` 9 s) and the layer itself defers its budget to the end of a pass. A mine is never in `enemies` and never scored. |

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
- **A squad ship must be killable by the player's primary weapon.** The Ram Corvette is not: its hull
  deflects every bullet until rockets have broken all three of its plates. A test checks every ship in
  the table keeps the bullet layer in its HurtBox mask (the legacy ram narrowed it to 33).

Behaviour and constraints: [`space_station/ENEMY.md`](../assault/scenes/enemies/space_station/ENEMY.md).
