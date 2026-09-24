# Enemies — current state (base for the Open Space rework)

Everything the game has today on its enemies, gathered from the code so the rework starts from
facts: movement, shooting, sprites (each PNG was opened and described), stats, states, collision,
spawning, tests and known issues — plus what Open Space already offers and which Assault-only
assumptions would break there. **Racers are excluded. Infiltration has no enemies.**

- Researched 2026-09-24 against `agent/auto-dev` by four parallel research agents; behaviour
  claims cite `file:line`, numbers are quoted from `.tres`/`.gd`, and anything not read directly
  is marked *(inferred)*. Spot-check a number before building on it.
- Descriptions of what exists — **no redesign proposals**. Each enemy ends with *Open Space notes*.

## Roster

| Enemy | Folder | Role today |
|---|---|---|
| [Bomber](#bomber) | `assault/scenes/enemies/bomber/` | Slow horizontal crosser that drops gravity bombs on the player's lane — area denial on a timer. |
| [Bonus Drone](#bonus-drone) | `assault/scenes/enemies/bonus_drone/` | Fast, fragile, non-shooting flyby worth a big score chunk; an optional reward, not a threat. |
| [Drone Interceptor](#drone-interceptor) | `assault/scenes/enemies/drone_interceptor/` | Self-managed pursuit drone: closes in, circles, then commits to a predictive suicide dash. |
| [Kamikaze Drone](#kamikaze-drone) | `assault/scenes/enemies/kamikaze_drone/` | Cheap swarm fodder that locks a straight heading at spawn and rams the player. |
| [Interceptor](#interceptor) | `assault/scenes/enemies/interceptor/` | Path-following Gatling strafer hosing a fast stream of low-damage, slightly scattered bullets. |
| [Light Assault Ship](#light-assault-ship) | `assault/scenes/enemies/light_assault_ship/` | The baseline shooter: flies in, holds a line, fires aimed or forward shots (has a state machine). |
| [Gunship](#gunship) | `assault/scenes/enemies/gunship/` | Self-managed mini-boss: parks near the top, tracks the player sideways, dual-barrel burst fire. |
| [Ram Ship](#ram-ship) | `assault/scenes/enemies/ram_ship/` | Armoured charger with heavy contact damage; bullet-immune until a missile strips its armour. |
| [Sniper Enemy](#sniper-enemy) | `assault/scenes/enemies/sniper_enemy/` | Hovering marksman: slow, heavily telegraphed aimed shots (converging laser sight), then retreats. |
| [Space Station (mini-boss)](#space-station-mini-boss) | `assault/scenes/enemies/space_station/` | Fortress boss: four turrets must die before the armoured core takes damage; gunnery, laser phase, reinforcements. |
| [Patrol Drone *(Open Space)*](#6-open-space-today) | `open_space/scenes/entities/enemies/` | The only enemy in Open Space today — documented in Part 1 §6. |

Shared machinery (`BaseEnemy`, `EnemyPathMover`, configs, components, projectiles, wave
choreography) and the current Open Space context are in [Part 1](#part-1--shared-machinery-and-open-space).

## Cross-cutting findings worth knowing before a rework

- **Every enemy's hurtbox mask is overwritten at runtime** to `97 | 1024` (1121) in
  `assault/scenes/enemies/base_enemy.gd:51`, whatever the scene authors.
- **Documented self-driven movement is often not what runs**: waves attach an `EnemyPathMover` via
  WaveBuilder `.move()`, which disables the enemy's own `_physics_process` and AI state machine.
  Bomber and Kamikaze Drone describe self-driven behaviour in their `ENEMY.md` that every real spawn
  suspends (see their sections).
- **Dead config fields**: Kamikaze Drone's `collision_damage` (the script never applies it; the
  scene's hardcoded 30 wins — the values happen to match), Bonus Drone's `movement_speed` (the live
  spawn hardcodes 560).
- **Orphan art**: `yellow_shielded.png` / `yellow_unshielded.png` are referenced nowhere;
  `laser_wall.png` is a separate hazard, not part of the station boss.
- **Naming collision**: Open Space already has an unrelated "space station" (the mission hub).
- **No test pins `BaseEnemy`, `EnemyPathMover` or `PatrolDrone` directly** — only roster-wide
  invariant sweeps; per-enemy tests are listed in each section.
- Drone Interceptor's AI is the most Open-Space-portable of the lot; most others assume a fixed
  scroll direction, camera-relative spawn/path maths and screen-edge despawn.

---

## Part 1 — Shared machinery and Open Space

Researcher slice: shared machinery under `assault/scenes/enemies/base_enemy.gd` +
`enemy_path_mover.gd`, the config-resource pattern, `global/components/`, enemy
projectiles, wave/spawn choreography, and everything Open Space offers today.
Repo root: `\\192.168.50.4\docker\game-development\repo`.

---

### 1. `BaseEnemy` and `EnemyPathMover`

**`assault/scenes/enemies/base_enemy.gd`** — `class_name BaseEnemy extends CharacterBody2D`.

- `@onready` wiring (base_enemy.gd:6-9): `health: Health = $Health`, `hurt_box: HurtBox =
  $HurtBox`, `hit_flash_player: AnimationPlayer = $HitFlashAnimationPlayer`,
  `contact_hit_box: HitBox = get_node_or_null("ContactHitBox")` (nullable — not every
  concrete enemy authors one, e.g. `bonus_drone.tscn`).
- Scoring fields owned here, read by `ScoreTracker`: `score_value: int = 0`,
  `was_killed: bool = false`, `counts_toward_wave_clear: bool = true`,
  `counts_as_escape: bool = true` (base_enemy.gd:12-21).
- **Config privatisation** (base_enemy.gd:40-45): `_init()` and `_enter_tree()` both call
  `ShipConfig.privatise(self)`. `_init()` covers writes made before `add_child()` (where
  `WaveManager` applies spawn overrides, wave_manager.gd:107-112); `_enter_tree()` covers a
  `.tscn`/`initial_props` override substituted in afterward, and still runs before any
  **child's** `_ready()` (space station's four child nodes depend on this). Idempotent —
  `duplicate()` blanks `resource_path`, and a blank path is the "already private" marker.
- `_ready()` (base_enemy.gd:48-68):
  - Connects `hurt_box.received_damage -> _on_received_damage`,
    `health.amount_changed -> _on_health_changed`.
  - **Hardcodes** `hurt_box.collision_mask = 97 | 1024` — i.e. 64 (player bullets, layer_7
    `player_hitbox`) + 32 (rockets, unnamed layer_6) + 1 (layer_1 `environment`) + 1024
    (asteroid contact, unnamed layer_11). This line runs for **every** `BaseEnemy` subclass
    regardless of any mask a `.tscn` author set on the `HurtBox` node — it always wins.
  - `_rotate_sprite()` sets `AnimatedSprite2D.rotation_degrees = 180.0` if a node named
    `AnimatedSprite2D` exists (base_enemy.gd:70-73) — a top-down "sprite drawn facing up,
    game plays with enemies coming down the screen" convention baked into the base class.
  - Instantiates and adds a `HitEffect` and an `ExplosionEffect` as children (base_enemy.gd:54-58).
  - Duck-types the subclass's `config` property via `get("config")`; if it `is ShipConfig`,
    copies `score_value`, `counts_toward_wave_clear`, `counts_as_escape` onto the base fields
    (base_enemy.gd:60-68). No compile-time knowledge of the concrete config subclass.
- Damage → death flow (base_enemy.gd:75-86):
  - `_on_received_damage(damage)` → `health.decrease(damage)`.
  - `_on_health_changed(current)` on every health change: plays `"hit"` on
    `hit_flash_player`, bursts `_hit_effect`. **On `current == 0`**: prints a despawn line
    (unconditional `print`, not verbose-gated — inconsistent with the rest of the codebase's
    logging convention), sets `was_killed = true`, emits `died`, calls
    `_explosion_effect.explode()`, then **`queue_free()`** — death and free happen in the
    same call, synchronously (this is what `SpaceStation` overrides to add a lingering death
    sequence — see assault.md's `StationDeathSequence` section).
- **What subclasses override/extend**: none of `_ready()`/`_on_received_damage`/
  `_on_health_changed` are virtual hooks with call-you-back extension points — subclasses
  (`Gunship`, etc.) call `super._ready()` then add their own timers/state, and some
  (`Gunship`) connect a **second** listener to `health.amount_changed` directly for their own
  needs (sprite damage-texture swap), alongside `BaseEnemy`'s own listener.
- **No AI/movement/shooting logic lives in `BaseEnemy` itself** — every concrete enemy either
  drives its own `_physics_process` phases (state-enum style, e.g. `Gunship`) or gets its
  position driven externally by `EnemyPathMover`, and shooting is bespoke per enemy
  (`BulletPool` + a `Timer`, or bespoke state scripts under `<enemy>/states/`).

**`assault/scenes/enemies/enemy_path_mover.gd`** — `class_name EnemyPathMover extends Node`.
Attaches to any `CharacterBody2D`; **owns position only**.

- `@export var movement: MovementResource`, `@export var exit_mode: ExitMode` (`FREE_ON_SCREEN_EXIT`
  default, or `FREE_ON_DURATION`), `@export var exit_time: float = 0.0` (0 = use
  `movement.total_duration()`), `@export var look_in_moving_direction: bool = true`,
  `@export var look_angle: float = 0.0` (sprite convention: `0 = down, PI = up, PI/2 = left,
  -PI/2 = right` — path_mover.gd:21-22).
- `_ready()` (path_mover.gd:34-65):
  - Resolves `_actor = get_parent() as CharacterBody2D`; `push_error` + `queue_free()` if the
    parent isn't one.
  - Records `_initial_world_pos = _actor.global_position`.
  - `_cam = _actor.get_viewport().get_camera_2d()` — **assumes an active `Camera2D` exists**;
    without one, screen-exit culling is skipped with only a `push_warning`.
  - **`PlayerFocusMovement` is duplicated per-actor** (path_mover.gd:51-58) so formation
    members sharing one `MovementResource` reference each compute their own aim direction from
    `(players[0].global_position - _actor.global_position).normalized()`, falling back to
    `Vector2.DOWN` if no node is in group `"player"`.
  - **Suspends the actor's own physics/AI**: `_actor.set_physics_process(false)`, and disables
    any child node literally named `"AIStateMachine"` via `process_mode =
    PROCESS_MODE_DISABLED` (path_mover.gd:62-65) — a magic node-name lookup, not a duck-typed
    interface. Timer-based shooting keeps working since timers aren't gated by
    `_physics_process`.
- `_physics_process(delta)` (path_mover.gd:67-117):
  - `pos_offset = movement.sample(_elapsed) * ArenaCamera.WORLD_SCALE` (**hard `ArenaCamera`
    dependency** — the scale constant, not the node), then
    `_actor.global_position = _initial_world_pos + pos_offset + Vector2(0, cam_scroll_y)`
    (`cam_scroll_y` is always 0 today since `ArenaCamera` scrolls via `.offset`, not
    `.global_position` — comment at path_mover.gd:73-75 explicitly says this is "retained as a
    hook if the camera strategy ever changes").
  - Facing: `atan2(-vel.x, vel.y)` from the frame-over-frame position delta when
    `look_in_moving_direction`; else the fixed `look_angle`.
  - `FREE_ON_DURATION`: frees at `exit_time` or `movement.total_duration()`.
  - `FREE_ON_SCREEN_EXIT` → `_check_off_screen(cam)` (path_mover.gd:100-117): computes
    `vp = _actor.get_viewport().get_visible_rect().size` and an 80 px margin, tests the
    actor's **world position** against `cam.global_position ± vp*0.5 ± margin` on both axes.
    Only culls **after** `_has_been_on_screen` first went true (so an actor that spawns
    off-screen and never arrives is never culled by this path — that's what
    `enemies_cleared_timeout`/`FREE_ON_DURATION` exist to backstop at the level-section level).

---

### 2. Config-resource pattern (`*_config.gd` / `*_config.tres`)

Base class: **`global/resources/ship_config.gd`** — `class_name ShipConfig extends Resource`.
Fields shared by every ship type: `max_health: int = 100`, `collision_damage: int = 20`,
`score_value: int = 0`, `counts_toward_wave_clear: bool = true`, `counts_as_escape: bool = true`.

`ShipConfig.privatise(node, property = "config")` (ship_config.gd:44-47): if
`node.get(property)` is a `Resource` with a non-empty `resource_path` (i.e. still the
`ResourceLoader`-cached shared object), replaces it with `duplicate()`. Idempotent by
construction (`duplicate()` blanks `resource_path`). **The shallow copy is only complete
while the resource stays flat** — asserted by `tests/integration/test_config_instance_isolation.gd`.

Per-enemy subclasses (`class_name X extends ShipConfig`) and their shipped `.tres` values:

| Config class | File | Extra fields | Shipped `.tres` highlights |
|---|---|---|---|
| `GunshipConfig` | `gunship/gunship_config.gd` | `burst_interval`, `burst_gap`, `bullet_damage`, `bullet_speed`, `entry_speed`, `hold_y_offset`, `track_speed`, `track_player`, `retreat_hp_ratio` | `max_health=200, collision_damage=30, score_value=200, burst_interval=1.0, bullet_damage=15, bullet_speed=260.0, entry_speed=60.0, hold_y_offset=55.0, track_speed=70.0, retreat_hp_ratio=0.3` |
| `FighterConfig` (`light_assault_ship`) | `light_assault_ship/fighter_config.gd` | `movement_speed`, `fire_interval`, `bullet_damage`, `aim_mode` ("PLAYER"/"FORWARD" string) | `max_health=60, collision_damage=20, score_value=25, movement_speed=100.0, fire_interval=0.8, bullet_damage=8, aim_mode="PLAYER"` |
| `RamShipConfig` | `ram_ship/ram_config.gd` | `movement_speed` (no shooting) | `movement_speed=100.0, max_health=999, collision_damage=50, score_value=35` |
| `BonusDroneConfig` | `bonus_drone/bonus_drone_config.gd` | `movement_speed` | `max_health=1, collision_damage=0, score_value=500, counts_toward_wave_clear=false, counts_as_escape=false, movement_speed=280.0` |
| `SpaceStationConfig` | `space_station/space_station_config.gd` | ~25 fields across turret HP, laser-phase, gunnery, reinforcements, death-sequence blocks (see file for full tuning surface) | boss-only; blocks are **read once** into the owning child node's own fields, never re-read |

Others present but not opened in full: `bomber_config.gd/.tres`, `drone_interceptor_config.gd/.tres`,
`interceptor_config.gd/.tres`, `drone_config.gd/.tres` (kamikaze_drone — no `.tres` glob hit, i.e.
may be absent/inlined). `sniper_enemy` has **no config at all** per
`test_enemy_contact_damage.gd`'s header comment, inheriting `ShipConfig` defaults nowhere via a
loaded resource.

**Pattern**: every concrete enemy declares `@export var config: XConfig =
load("res://.../x_config.tres")`. Because `ResourceLoader` caches by path, that `load()` call
returns the **same object** for every instance and every `preload()` in the test suite — hence
`privatise()`. The `.tres` value **wins over the scene's Health node** where they differ
(`Gunship._ready()`: `health.max_health = config.max_health; health.current_health =
config.max_health`, gunship.gd:36-37) — a project-wide convention, not special to Gunship.

**Contact damage is NOT auto-wired from config.** `ContactHitBox` on every `BaseEnemy`
subclass's `.tscn` defaults to `damage = 20` and never reads `config`; each concrete script
must re-apply `contact_hit_box.damage = config.collision_damage` in its own `_ready()`
(gunship.gd:50-51 is the pattern; also `bomber.gd`, `light_assault_ship.gd`, `ram_ship.gd`,
`space_station.gd`). Forgetting is silent — this is exactly the bug
`tests/integration/test_enemy_contact_damage.gd` now gates (Gunship shipped ramming for 20
instead of its configured 30 for some time).

---

### 3. Shared components (`global/components/`)

One line each, plus enemy-relevant detail:

- **`health_component.gd`** (`class_name Health extends Node`) — `max_health`/`current_health`
  ints, `increase()`/`decrease()`/`set_health()`, optional invincibility-frames timer.
  `amount_changed(current_health: int)` fires on **every** call including no-ops. `decrease()`
  is a no-op while `invincibility_timer` is running. Verbose-gated debug print
  (`OS.is_stdout_verbose()`).
- **`hurtbox_component.gd`** (`class_name HurtBox extends Area2D`) — `received_damage(damage:
  int)`; on `area_entered`, casts to `HitBox`, optionally filters by
  `accepted_damage_types: Array[HitBox.DamageType]` (empty = accept all), then re-emits the
  hitbox's `damage`.
- **`hitbox_component.gd`** (`class_name HitBox extends Area2D`) — `enum DamageType { LASER,
  ROCKET, CONTACT }`, `damage: int = 1`, `damage_type: DamageType = LASER`. Pure data node; no
  logic.
- **`shield_component.gd`** (`class_name Shield extends Node`) — discrete-charge shield:
  permanent charges (regen 1 per 5 s of no damage) + a temporary stack (cap `max_temporary`,
  no regen). `consume_one()` absorbs one hit (temp first, then permanent); `is_hacked` drains
  everything on one call. `bind_progression` ties permanent max to
  `ShipProgressionState.permanent_shield_count` (player-only pattern; enemies would use
  `permanent_charges` directly if they ever carried one — none of the read enemy scenes do).
- **`overheat_component.gd`** (`class_name Overheat extends Node`) — `heat`/`heat_limit`,
  `increase_heat()`, dissipates over `cooldown_time` after a `_SHOOT_GRACE = 0.5 s` no-shoot
  window; emits `overheat(overheat_percentage: float)`. Used by player ships, not seen wired
  into any enemy scene.
- **`damage_reaction.gd`** (`class_name DamageReaction extends Node`) — an **alternative** to
  `BaseEnemy`'s own hand-wired damage flow: `setup(health, shield, hurt_box, sprite)` wires
  `HurtBox.received_damage` → optional `Shield.consume_one()` → `Health.decrease()`, flashes
  the sprite, and on death emits `died`, explodes, and calls `get_parent().queue_free()`.
  **Not used by `BaseEnemy`/its subclasses** — `BaseEnemy` reimplements this flow itself
  (hit-flash `AnimationPlayer` instead of a tween-flash, no `Shield` support). `DamageReaction`
  appears to be the shared-component version used elsewhere (allies/player-adjacent), while
  assault enemies have their own bespoke, shield-less path. Worth checking during redesign
  whether Open Space enemies should adopt `DamageReaction` instead of `BaseEnemy`'s inline flow.
- **`hit_effect.gd`** (`class_name HitEffect extends Node2D`) — one-shot `CPUParticles2D`
  burst (`amount=10, lifetime=0.25` default), triggered via `burst()`. Instantiated per-enemy
  by `BaseEnemy._ready()`.
- **`explosion_effect.gd`** (`class_name ExplosionEffect extends Node2D`) — larger one-shot
  burst (`amount=22, lifetime=0.5` default) via `explode(at?, container?)`. Spawns its
  particles into `container` or, by default, **the actor's parent** (`_nearest_node2d()` walks
  up from `get_parent()` to the nearest `Node2D`) — this is why it must be a child of the dying
  entity and why nesting depth matters (see `assault.md`'s `StationDeathSequence` notes on this
  exact trap). `always_process` lets the burst render through a paused tree (used for player
  death, not seen on enemies).
- **`bullet_pool.gd`** (`class_name BulletPool extends Node`) — pre-allocates `pool_size`
  bullets as disabled/invisible children; `acquire(pos)` reparents one into `_container`
  (resolved as `get_parent().get_parent()` — **hardcoded grandparent assumption**, "pool → ship
  → container", matching the wave-manager `enemy_container` hierarchy) and returns it reset
  and visible; recycles automatically when the bullet's `expired` signal fires
  (`call_deferred("_recycle", …)`). `cancel_active()` force-frees all in-flight bullets;
  `_exit_tree()` calls it automatically so a killed shooter doesn't leave orphaned bullets with
  a dead recycle target.
- **`attack_controller.gd`** (`class_name AttackController extends Node`) — generic
  `AttackPatternResource` + `BulletPool` driver on its own accumulating timer (subtracts
  `fire_interval`, not reset-to-0, to preserve overshoot accuracy). Not seen wired into any of
  the enemy scenes opened directly (they roll their own `Timer`s) — likely used by
  `AttackPatternResource`-driven enemies covered by other researchers, or is available/unused
  infrastructure.
- Not opened in full (present, enemy-adjacent): `bubble_shield.gd`, `shield_icon.gd`,
  `shield_icon_strip.gd`, `thruster_effect.gd`, `temp_health_component.gd`, `rocket_trail.gd`,
  `low_health_smoke.gd` — these read as player/ally-presentation components based on name and
  the `global.md` overview; not confirmed wired into any assault enemy.

---

### 4. Enemy projectiles

- **`assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`** (`class_name EnemyBullet
  extends Area2D`) — `expired` signal.
  - **Hardcoded arena bounds** (enemy_bullet.gd:6-16), derived from `arena_camera.gd`'s
    constants: `cam.global_position=(640,360)`, `H_LIMIT=100`, `V_LIMIT=380`, viewport
    1280×720 → `x ∈ [-164, 1444]`, `y ∈ [-444, 1164]` (64 px margin added). Despawns in
    `_physics_process` when `global_position` leaves that box — **this is the Assault-arena
    despawn rule**, distinct from the player bullet's viewport-edge rule (see `assault.md`).
  - `set_direction(dir)` sets `_direction` and `rotation = dir.angle() - PI/2`.
  - `become_friendly()` (enemy_bullet.gd:44-51) — the reflect/parry hook: flips `_direction`,
    adds `PI` to rotation, and swaps the child `HitBox`'s `collision_layer = 64` /
    `collision_mask = 513` (player-projectile layer hitting enemy hurtbox + something on bit
    1). Per `assault.md`, its only caller (`reflect_state.gd`) was removed as dead code
    2026-09-08 — **currently unused**.
  - Scene (`enemy_bullet.tscn`): root `Area2D` + `Visual` (`Line2D`), child `HitBox`
    (`collision_layer=256` i.e. `enemy_hitbox`, `collision_mask=128` i.e. `player_hurtbox`,
    `damage=10` default — overridden per-shooter, e.g. `gunship.gd:149` sets
    `hb.damage = _bullet_damage`). `area_entered` on `HitBox` wired to
    `_on_hit_box_area_entered` → just emits `expired` (any hit ends the bullet — enemy bullets
    have no pierce logic).
- **`bullets/bullet.gd`** (`class_name Bullet`) — the **player's** bullet, also reused/pooled
  by `AllyFighter`; documented here because enemies are its target, not its owner. Despawns at
  the **viewport** edge (`VisibleOnScreenNotifier2D`), not the arena bound — the asymmetry with
  `EnemyBullet` is deliberate per `assault.md` (player weapons are also mounted in Open Space,
  which has no `ArenaCamera`). Pierce/sniper/armor-deflection logic lives here
  (`_hit_is_deflected` duck-types `is_armored()` on the hit target's parent).
- **Ownership rule (project-wide, `assault.md`/`CLAUDE.md`)**: every projectile has exactly one
  owner — either a `BulletPool` recycles it, or it frees itself leaving the world.
  `EnemyBullet` is always pooled (every enemy that shoots owns a `BulletPool` child, e.g.
  `gunship.gd:58-61`); nothing observed calls `free_when_offscreen()`-equivalent on it directly
  since the arena-bounds check in `_physics_process` **is** its self-expiry path, feeding into
  the pool's `expired`-signal recycle.
- **Damage types**: `HitBox.DamageType` enum is `{ LASER, ROCKET, CONTACT }`. `EnemyBullet`'s
  `HitBox` doesn't set `damage_type` explicitly in the `.tscn` (defaults to `LASER`).
  `HurtBox.accepted_damage_types` can filter by type but `BaseEnemy`'s own `HurtBox` doesn't
  restrict types (empty array = accept all) — type filtering appears to be an opt-in per-entity
  mechanism (e.g. armor that only blocks certain types), not exercised by the base enemy path.
- Not opened in full: `piercing_beam/piercing_beam.gd` (BEAM weapon projectile — per
  `assault.md`, sustained, player-side), `missiles/homing/homing_missile.gd`,
  `missiles/warhead/warhead_missile.gd` (player secondary munitions). None of these are enemy
  ordnance based on `assault.md`'s directory map — flagged for the racer/enemy-specific
  researchers if any enemy actually fires them.

---

### 5. Spawning & choreography in Assault

- **`assault/scenes/systems/wave_manager/wave_manager.gd`** (`class_name WaveManager`) — pure
  time-driven spawner, no AI:
  - Wave dict: `{trigger: float, spawns: Array}`; spawn dict includes `ship.scene`, `offset:
    Vector2` (design-space, camera-relative), `delay`, optional `on_spawned: Callable`,
    optional `movement: MovementResource` (→ attaches `EnemyPathMover`), `exit_mode`,
    `exit_time`, `look_in_moving_direction`, `look_angle`.
  - `load_level(LevelResource)` / `load_section(Array[WaveResource])` convert
    `SpawnEntryResource`s into these dicts via `_entry_to_dict()` (wave_manager.gd:94-113) —
    `initial_props: Dictionary` on the resource becomes an `on_spawned` callable that does
    `e.set(key, value)` for each prop, applied **before** `add_child()` (wave_manager.gd:180-182),
    landing inside `BaseEnemy._init()`'s privatisation window.
  - `_expand_formation()` (wave_manager.gd:130-149) expands a `FormationResource` into one
    spawn dict per `FormationSlot`, offsetting `offset`/`delay` per slot; `MovementResource` is
    shared by shallow-duplicate reference across slots (safe since it's stateless data — actual
    per-actor divergence, e.g. `PlayerFocusMovement`, happens later in `EnemyPathMover._ready()`).
  - `_spawn_ship()` (wave_manager.gd:159-208): resolves the active `Camera2D`, computes
    `spawn_pos = cam.global_position + cam.offset + offset * ArenaCamera.WORLD_SCALE`
    (**camera-relative in the ArenaCamera sense — `cam.offset` is Assault's pan mechanism**),
    instantiates, applies `on_spawned` before `add_child`, adds to `enemy_container`, emits
    `enemy_spawned(entity, wave_index)` for `ScoreTracker`, then conditionally attaches an
    `EnemyPathMover` if a real `MovementResource` was supplied.
- **`assault/scenes/systems/wave_builder.gd`** (`class_name WaveBuilder`) — fluent DSL:
  `b.fighter().at(x,y).move(b.straight(...)).delay(...).shoot_forward()`. `SpawnConfig.at(x,y)`
  is explicitly "relative to camera centre (px)" in **640×360 design units**. Movement helpers
  (`straight`, `arc`, `sine`, `u_sweep`, `curve`, `player_focus`, `sequence`, `hold` — not
  individually opened here, see `docs/enemy-roster.md`) and formation helpers (`v_`, `wedge_`,
  `line_`, `diagonal_`, `cluster_`) centralize scene-path constants for each enemy type
  (`FIGHTER`, `DRONE`, `RAM`, …).
- **640×360 design space / `ArenaCamera.WORLD_SCALE`**: `assault/scenes/systems/arena_camera.gd`
  — `class_name ArenaCamera extends Camera2D`. `WORLD_SCALE = 2.0` const scales all spawn
  offsets and `EnemyPathMover` sampled positions from 640×360 design units to the actual
  1280×720 viewport (`SCREEN_W/H` consts). Camera **follow strategy is offset-based, not
  position-based**: `global_position` is pinned forever at `(640, 360)` (the level origin);
  all panning happens through `Camera2D.offset`, clamped to `H_LIMIT=100`/`V_LIMIT=380` around
  a Hollow-Knight-style deadzone box (`deadzone_half_size = (40, 30)`) following
  `get_tree().get_nodes_in_group("player")[0]`. This is *why* `EnemyPathMover`'s
  `cam_scroll_y` is always 0 (comment at path_mover.gd:73-75) and why spawn math must add both
  `cam.global_position` and `cam.offset`.
- **How a wave references an enemy**: `SpawnEntryResource.ship_scene: PackedScene` (a direct
  scene reference) plus `MovementResource`/`FormationResource`/`initial_props`. `WaveBuilder`'s
  scene-path constants (`FIGHTER`, `DRONE`, etc.) are the canonical source of "this string names
  this enemy scene" — see `docs/enemy-roster.md` for the full mapping (not opened by this
  researcher; owned by the roster doc).
- **`LevelDirector`/`level_1_director.gd`**: sequences `LevelSection` resources
  (`DURATION`/`WAVES_COMPLETE`/`ENEMIES_CLEARED` end conditions); calls
  `wave_manager.load_section()` per section. Full detail in `assault.md` (§ Levels & director) —
  not re-derived here since it's level-orchestration, not enemy machinery per se, but it's the
  thing that ultimately drives `WaveManager`.

---

### 6. Open Space today

#### 6.1 `PatrolDrone` (`open_space/scenes/entities/enemies/patrol_drone.gd`)

`class_name PatrolDrone extends CharacterBody2D` — **does not extend `BaseEnemy`** and has no
`ShipConfig`. Minimal, ambient-only:

- `@export var move_speed: float = 60.0`, `@export var initial_direction: Vector2 =
  Vector2.RIGHT`.
- `@onready var health_component: Health = $HealthComponent`, `@onready var hurt_box: HurtBox =
  $HurtBox`.
- `_ready()`: `add_to_group("enemies")`, normalizes `initial_direction` (falls back to
  `Vector2.RIGHT` if zero), connects `health_component.amount_changed -> _on_health_changed`.
  **Note**: `hurt_box.received_damage` is never connected to `_on_received_damage` in `_ready()`
  — `_on_received_damage()` exists as a method but appears dead/unwired in this file (no
  `.connect()` call for it here; may be wired in the `.tscn` instead — not confirmed).
- `_physics_process`: `velocity = _direction * move_speed; move_and_slide()` — **constant
  straight-line drift forever**, no bouncing, no turning, no state machine, no attack. No
  `EnemyPathMover`, no `MovementResource`, no config resource, no contact-hitbox
  scoring/wave-clear fields (`score_value`, `counts_toward_wave_clear`, etc. don't exist here —
  it was never plugged into `ScoreTracker`'s conventions since Open Space has no `ScoreTracker`).
- `_on_health_changed(current)`: `if current == 0: died.emit(); queue_free()` — no explosion
  effect, no hit flash, no hit-effect burst (unlike `BaseEnemy`).
- Scene (`patrol_drone.tscn`): root `collision_layer=256` (`enemy_hitbox`)
  `collision_mask=1` (`environment`); `HurtBox` `layer=512`(`enemy_hurtbox`)
  `mask=64`(`player_hitbox`); `HitBox` (contact) `layer=256`(`enemy_hitbox`)
  `mask=128`(`player_hurtbox`). Visual is a plain `ColorRect`, not a sprite.
- **Spawning**: `SectorHub._spawn_initial_drones()` (called from `sector_hub.gd::_ready()`)
  instantiates `drone_count` (`3`) `PatrolDrone`s at random angles/distances within
  `spawn_radius` (`600`) around the hub, each given a random `initial_direction`, parented into
  an `EnemyContainer` node. This is the **only** spawn path in Open Space today — no
  `WaveManager`, no timed triggers, no waves/sections/level director equivalent.

#### 6.2 Player ship / world Open Space offers enemies

- **`open_space/scenes/entities/player/player_ship.gd`** (`class_name OpenSpacePlayerShip
  extends PlayerBase`) — free-flight ship, **not** an autoscroller fighter. Key facts relevant
  to an enemy redesign:
  - Movement is **omnidirectional thrust + damping + rotation**, not lane-dodging: `move_up`/
    `move_down` thrust forward/back (`thrust_acceleration=380.0`,
    `reverse_acceleration=220.0`), `max_speed=420.0`, `damping=0.6` lerp-to-zero when idle.
  - **Rotation is owned entirely by `ShipTurnController`** (a child, resolved by type in
    `_ready()`), the project's single writer of the ship's `rotation` — two schemes,
    `&"mouse"` (default; clamped exponential chase toward cursor, `mouse_max_turn_rate_deg=150`,
    `mouse_turn_half_life=0.14`, `mouse_dead_zone_px=48`) or `&"keys"`
    (`keyboard_turn_rate_deg=220`, instantaneous). **The ship can face and travel in any
    direction — there is no fixed "up" or "forward-only" convention** the way Assault's
    downward autoscroll implies.
  - **Shift boost**: hold-to-boost, redirects momentum onto current nose heading at
    `boost_exit_speed=700.0` (must exceed `max_speed`), sustained by `BoostMeter` drain,
    minimum burn `boost_hold_sec=0.35s`, ceiling decays at `boost_ceiling_decay=400.0 px/s²`.
  - Player body: `collision_layer = 4` (`environemnt_player`, layer_3). `HurtBox`:
    `collision_layer = 128` (`player_hurtbox`), `collision_mask = 1281` = 1
    (`environment`) + 256 (`enemy_hitbox`) + 1024 (unnamed layer_11, same "asteroid contact"
    bit `BaseEnemy` reads).
  - No `ArenaCamera` — camera is a bare `Camera2D` child with a `CameraDirector` doing effect
    blending (`speed_feel` from `OpenSpaceCameraRig`, `planet_dwell` from `MissionTrigger`), not
    a follow-with-clamped-offset scheme. **No `WORLD_SCALE`, no design-unit convention, no
    fixed viewport-relative bounds** in this script.
  - Death: explosion + camera shake + 1.2 s wait + `get_tree().reload_current_scene()` (respawn
    in the hub), vs. Assault's game-over overlay + pause.
  - Composed from `HealthComponent`, `ShieldComponent`, `OverheatComponent`,
    `TempHealthComponent`, a `HurtBox`, an `AttackStateMachine` (`WeaponState` +
    `WarheadMissileShootingState`) — i.e. the player **can already shoot** in Open Space using
    the same weapon-behavior infrastructure as Assault.
- **Camera**: `OpenSpaceCameraRig` (child of ship) computes speed-zoom (`zoom_min=0.85` at
  `zoom_speed_threshold=400.0 px/s`) + a velocity-direction camera lead (`lead_max_px=90.0`,
  `lookahead_time=0.30s`) fed into `CameraDirector` under effect `&"speed_feel"`. Lead direction
  is `velocity.normalized()`, deliberately **not** `rotation` — the ship can move backward/
  sideways relative to its facing (boost + turning), unlike Assault's fixed-forward scroll.
- **World bounds/scale**: no `ArenaCamera`-equivalent bounding box was found wired to
  `SectorHub` or `PlayerShip` in the files read — the hub appears to be an open, unbounded
  plane (parallax stars only, no wall/edge collider referenced in `sector_hub.gd`'s own logic).
  `PatrolDrone`s drift forever with no despawn-on-distance logic at all (confirmed: no
  off-screen or out-of-radius check in `patrol_drone.gd`).
- **How anything currently spawns there**: only `SectorHub._spawn_initial_drones()` (§6.1) —
  no wave system, no director, no formation/movement-resource authoring today.
- **Mission select / hub structure**: `MissionTrigger` (`Area2D`, `mission_select_hub.gd`) is a
  dwell-triggered (`dwell_duration_sec=2.0`, cancels if player speed > `_MAX_APPROACH_SPEED=150
  px/s`) interactable that freezes the player, opens `MissionSelectMenu`
  (`open(PlanetConfigResource)`), and on confirm does `get_tree().change_scene_to_file(scene_path)`
  into an Assault or Infiltration mission scene — Open Space itself never plays a "mission," it's
  pure hub + launcher. Trigger scene collision: `collision_layer=2`, `collision_mask=4` (matches
  the player body's `collision_layer=4`).
- **Collision layers/masks (from `project.godot [layer_names]` + scene reads)**:

  | Bit | Named as | Seen used by |
  |---|---|---|
  | 1 (layer_1) | `environment` | enemy `HurtBox` mask component; `PatrolDrone` body mask; player `HurtBox` mask component |
  | 2 (layer_2) | `environment_interactable` | (not directly observed in read files) |
  | 4 (layer_3) | `environemnt_player` [sic, typo in project.godot] | `OpenSpacePlayerShip` body `collision_layer` |
  | 32 (layer_6, unnamed) | — | enemy `HurtBox` mask component ("rockets" per base_enemy.gd comment) |
  | 64 (layer_7) | `player_hitbox` | player bullets' `HitBox.collision_layer`; enemy `HurtBox` mask; `PatrolDrone.HurtBox` mask |
  | 128 (layer_8) | `player_hurtbox` | `OpenSpacePlayerShip.HurtBox` / `PlayerShip.HurtBox.collision_layer`; enemy `ContactHitBox`/`HitBox` mask target (e.g. `PatrolDrone.HitBox.collision_mask=128`) |
  | 256 (layer_9) | `enemy_hitbox` | `EnemyBullet.HitBox.collision_layer`; `Gunship`/`PatrolDrone` body & contact-`HitBox` `collision_layer` |
  | 512 (layer_10) | `enemy_hurtbox` | `Gunship`/`PatrolDrone` `HurtBox.collision_layer` |
  | 1024 (layer_11, unnamed) | — | "asteroid contact" per base_enemy.gd comment; also present in player `HurtBox` mask (1281 = 1+256+1024) |

  Only layers 1–3, 7–10 are named in `project.godot`; layers 6 and 11 are used numerically with
  no `[layer_names]` entry — worth flagging to the project owner if the redesign wants clean
  layer semantics for Open Space enemies.

---

### 7. Assault-specific assumptions in shared enemy code (would break in free-flight Open Space)

Concrete, file:line-cited:

- **`base_enemy.gd:70-73`** — `_rotate_sprite()` unconditionally flips any `AnimatedSprite2D`
  child 180°, baking in "art drawn facing up, gameplay faces down" — meaningless once an enemy
  can face any direction in free flight (Open Space already handles facing via `rotation`, not
  a fixed sprite flip).
- **`base_enemy.gd:51`** — `hurt_box.collision_mask = 97 | 1024` is hardcoded in the **base**
  class and runs for every subclass; fine as a layer scheme (Open Space reuses the same
  layers), but it's a fixed constant with no notion of "which layers exist in this scene" —
  would need auditing if Open Space wants finer-grained enemy factions/friendly-fire rules.
- **`base_enemy.gd:82`** — unconditional `print(...)` on every enemy death, not verbose-gated
  like the rest of the codebase's logging convention (`Health.decrease`,
  `StateMachine.change_state`, `DialogPlayer` all fixed this per `docs/discovered-bugs.md`;
  `BaseEnemy._on_health_changed` was apparently missed).
- **`enemy_path_mover.gd:43-46,73-75`** — `_cam = _actor.get_viewport().get_camera_2d()` and
  the entire position model assumes **`ArenaCamera`'s offset-only pan** (`global_position`
  pinned, `cam_scroll_y` always 0 today, called out in-comment as "retained as a hook"). Open
  Space's camera is a bare `Camera2D` with `CameraDirector`-blended effects and **does move its
  `global_position`** implicitly via being parented to the ship (ship moves, camera follows as
  a child) — `EnemyPathMover`'s scroll-compensation math would need rework, not just reuse.
- **`enemy_path_mover.gd:77`** — `movement.sample(_elapsed) * ArenaCamera.WORLD_SCALE` is a
  **hard compile-time dependency on the `ArenaCamera` class** (for its `WORLD_SCALE` constant)
  from a file under `assault/`. Any Open Space reuse of `EnemyPathMover` either needs an
  equivalent scale constant/class or a parameterized scale.
  `MovementResource`/`WaveBuilder`-authored paths (straight/arc/sine/u_sweep/curve/player_focus)
  are all expressed in the 640×360 design-unit space Assault waves are authored in
  (`wave_builder.gd:24-25` doc comment) — meaningless coordinates without an equivalent
  design-space convention in Open Space's apparently-unbounded plane.
- **`enemy_path_mover.gd:100-109`** — `_check_off_screen()` culls based on
  `cam.global_position ± viewport_half_size ± 80px` — a **fixed rectangular offscreen margin
  keyed to the current viewport**, which assumes the camera framing is the gameplay boundary
  (true in Assault's scrolling corridor). In an open, free-flight plane where the player can
  fly away from spawned enemies in any direction (or enemies can be far outside camera view but
  still "in the level"), this despawn rule either strands enemies that never enter view or
  culls enemies the player intentionally flew away from and might return to.
- **`wave_manager.gd:175`** — `spawn_pos = cam.global_position + cam.offset + offset *
  ArenaCamera.WORLD_SCALE` — spawn placement is defined **relative to the current camera view**
  (an Assault-only concept: "off the visible edge, scaled from design units"). Open Space has
  no such camera-relative spawn convention; `SectorHub._spawn_initial_drones()` instead spawns
  at random angle/distance from a **world-space point** (the hub), which is a fundamentally
  different placement model.
- **`gunship.gd:53-56, 84-90, 114-120`** (representative of the AI-phase style used by heavier
  enemies) — `Phase.ENTER` moves the ship down until it reaches
  `cam.global_position.y - viewport_height*0.5 + hold_y_offset` (a **fixed point below the top
  of the screen**), `Phase.HOLD` tracks the player only on the **X axis**
  (`velocity.x = sign(diff) * ...`, `velocity.y = 0.0` — 1-D tracking assuming the player is
  always roughly level or below), and `Phase.RETREAT` flies **straight up** until it passes
  `cam.global_position.y - viewport_height*0.5 - 50.0` (i.e. off the **top** of the screen) —
  three separate hardcoded assumptions that "down" is the entry direction, "the player is
  horizontally adjacent, not above/below," and "up and off-screen" is a valid despawn/retreat
  direction. None of this holds in an omnidirectional Open Space.
- **`base_enemy.gd` (implicit, via every reader of `get_tree().get_nodes_in_group("player")`,
  e.g. `gunship.gd:98-101,140-141` and `enemy_path_mover.gd:53-58`)** — targeting/aim code reads
  the player's `global_position` directly with no concept of "is the player even nearby /
  in this arena" — this part **does** carry over fine to Open Space (group-based lookup, no
  scroll assumption), it's specifically the **axis-restricted tracking and phase-transition
  screen-edge checks layered on top** that are Assault-specific.
- **`enemy_bullet.gd:6-16`** — arena-bounds despawn constants are **literal numbers derived from
  `ArenaCamera`'s fixed 740×740 world**, not a reference to any camera or world-bounds object.
  Reusing `EnemyBullet` in Open Space as-is means enemy bullets fired far from the hub's nominal
  center never expire until they cross an arbitrary box that has no relation to Open Space's
  actual play area.
- **`bullet_pool.gd:47`** — `_container = get_parent().get_parent()` assumes the fixed
  "pool → ship → level's enemy container" hierarchy depth used by `WaveManager`'s
  `enemy_container`. `SectorHub` uses its own `EnemyContainer` node at a potentially different
  nesting depth relative to where a ship (and its pool) would sit — needs verifying per scene,
  not a given.
- **`arena_camera.gd` itself** is `assault/scenes/systems/arena_camera.gd` — a class the whole
  chain above (`EnemyPathMover`, `WaveManager`) references by name/constant. It is **not**
  present in Open Space at all (Open Space's camera is a plain `Camera2D` + `CameraDirector`),
  so any code path that does `get_viewport().get_camera_2d()` and then treats the result as an
  `ArenaCamera` (or just reads `.offset` expecting Assault's pan convention) silently
  misbehaves rather than erroring, since GDScript's duck-typed `Camera2D` calls
  (`.global_position`, `.offset`) are valid on both but mean different things.

---

### 8. Tests pinning shared enemy behaviour

None of `tests/**` target `base_enemy.gd` or `enemy_path_mover.gd` **by name** (no
`test_base_enemy.gd` / `test_enemy_path_mover.gd` found) — their behaviour is pinned
**indirectly**, through cross-cutting invariant sweeps over the whole enemy roster:

- **`tests/integration/test_config_instance_isolation.gd`** — sweeps every `ShipConfig`
  subclass (directory-swept, so new enemies are covered automatically): asserts no two entity
  instances share a config object, the private copy is value-identical to the shipped `.tres`,
  and every config class is flat enough for `duplicate()` to be a complete (non-shallow-bug)
  copy. Boundary cases: the copy survives a re-parent, and it exists before any **child's**
  `_ready()` (checked by identity from a probe child).
- **`tests/integration/test_enemy_contact_damage.gd`** — asserts every assault enemy's
  `ContactHitBox` deals the damage its `*_config.tres` declares (`collision_damage`); documents
  the `no_hitbox` exception for `bonus_drone`. This is the test that caught Gunship's dead 30
  vs. shipped 20.
- **`tests/integration/test_contact_hitbox_geometry.gd`** — asserts a `ContactHitBox` node's
  `CollisionShape2D` references the **same `SubResource` shape id** as the body's collider and
  **copies its `scale`** — catches the "18px ram box on a 41.5px hull" class of bug
  (`docs/discovered-bugs.md` doesn't list this one directly but `assault.md` describes the
  gunship incident it fixed).
- **`tests/integration/test_enemy_hurtbox_geometry.gd`** — the mirror invariant: every assault
  entity's `HurtBox` must **cover** (not just intersect) the body `CollisionShape2D`, so armour
  is a damage rule on a full-size hurtbox, never a shrunken/absent one. Carries a permanent
  boundary case pinning that the rejected "narrow the station core to 88×240" proposal fails
  the sweep.
- **`tests/integration/test_entity_sprite_transparency.gd`** — sweeps every entity under
  `assault/scenes/{enemies,player,projectiles,hazards,allies}` (so it covers the enemy roster)
  for 90%+ opaque textures drawn over the game world (art invariant, not behaviour, but rides
  the same "every enemy scene" sweep pattern).
- **Component-level unit tests** (`tests/unit/`), one file per shared component used by
  enemies: `test_health_component.gd`, `test_hitbox_hurtbox.gd`, `test_damage_reaction.gd`,
  `test_shield_component.gd`, `test_overheat_component.gd`, `test_temp_health_component.gd` —
  these pin `Health`/`HurtBox`/`HitBox`/`DamageReaction`/`Shield`/`Overheat` in isolation, not
  through any specific enemy.
- **Open Space specific** (none reference `PatrolDrone` by name in the glob results returned):
  the `tests/integration/test_open_space_*` and `tests/unit/test_open_space_camera_rig.gd`
  files found all target the **player ship's** flight/boost/camera/aim systems (§6.2), not the
  ambient enemy. No characterization test appears to pin `PatrolDrone`'s drift/health/death
  behaviour today — **(inferred: a gap, not confirmed by an exhaustive tests/ listing beyond
  the glob patterns run)**.
- **`tests/integration/test_player_bullet_lifetime.gd`** — pins the player-bullet lifetime
  rules that touch `is_armored()` duck-typing enemies must respect if they want to deflect
  shots (relevant if a redesigned Open Space enemy wants armor behaviour).

---

### Open Space porting notes

- `BaseEnemy`'s damage/health/death plumbing (`Health` + `HurtBox` + `HitBox` + hit-flash +
  `HitEffect`/`ExplosionEffect`) is mode-agnostic and should port cleanly; `ShipConfig` +
  `privatise()` likewise. `PatrolDrone` already proves the same `Health`/`HurtBox` pair works
  standalone in Open Space without `BaseEnemy` at all.
- Everything **downstream of "where is the camera and which way is down"** is the Assault-only
  layer to strip or replace: `EnemyPathMover`'s camera-relative scroll model and off-screen
  culling, `WaveManager`'s camera-relative spawn placement, `ArenaCamera.WORLD_SCALE`/640×360
  design-space coordinates, and `EnemyBullet`'s fixed arena-bounds despawn box.
  A free-flight equivalent needs its own notion of "world bounds" or "distance from player/hub"
  for both spawn placement and despawn, since Open Space today has no visible bounding
  construct at all.
- Any enemy AI written in the Assault "phase enum with axis-restricted tracking and
  screen-edge retreat" style (Gunship is the clearest example) encodes "player is below,
  scrolling is vertical, screen edges are meaningful" three times over and cannot be reused
  as-is — it needs to become a genuinely 2-axis pursue/orbit/retreat model to fit Open Space.
  `Gunship`'s player-group lookup and burst-fire timer logic, by contrast, has no axis
  assumption and would carry over.
- `BulletPool`'s `get_parent().get_parent()` container resolution is a hidden scene-shape
  contract; confirm `SectorHub`'s node depth matches before reusing enemy scenes verbatim, or
  make the container resolution explicit/overridable.
- No test currently pins `PatrolDrone` behaviour — worth adding characterization coverage
  before/while reworking it, per this project's own testing convention (`CLAUDE.md`: pin
  current behaviour before changing it).
- The player ship in Open Space already carries a full `AttackStateMachine` (weapon +
  missiles) and `Health`/`Shield`/`Overheat`, so a ported enemy's *incoming* damage model
  (what hits it) needs no new player-side work — only the enemy's own aiming/attack logic needs
  to target an omnidirectional ship instead of one that is always below and closing vertically.

---

## Part 2 — Drones and bomber

### Bomber

#### 1. Identity
- Folder: `assault/scenes/enemies/bomber/`
- Scene: `bomber.tscn`, script: `bomber.gd`, `class_name Bomber`, extends `BaseEnemy`.
- Config: `bomber_config.tres` → `class_name BomberConfig extends ShipConfig` (`bomber_config.gd`).
- Companion projectile: `bomb.tscn`/`bomb.gd`, `class_name Bomb extends Area2D` (not a `BaseEnemy`).

#### 2. Role
"Crosses the screen horizontally and rains gravity bombs onto the player's lane, forcing repositioning." A slow, easy-to-hit target whose real threat is the bombs it leaves behind — area denial on a timer (`bomber/ENEMY.md:3-4`).

#### 3. Visuals
- `assault/assets/sprites/enemies/bomber.png`, **92×42 px**, single static texture (no `AnimatedSprite2D`, no frame animation).
- `bomber.tscn`: `Sprite2D` with `rotation = 3.1415927` (180°), `ShaderMaterial` using `hit_flash_vs.tres` (`shader_parameter/enabled` toggled true→false over 0.2s by the `HitFlashAnimationPlayer`'s `"hit"` track — a functional white hit-flash).
- Visual read of `bomber.png`: a wide (92×42), dark purple/near-black, symmetrical bat/beetle-like silhouette with wing-like lobes on both sides and dark maroon/red highlights — an ominous, insectoid, top-down design, wider than it is tall.

#### 4. Stats
Per CLAUDE.md convention, the `.tres` value wins over the scene default where they differ.
| Field | `.tres`/config | scene default | winner at runtime |
|---|---|---|---|
| HP | `max_health=150` | Health node `max_health/current_health=250` | **150** (`bomber.gd:19-20` overwrites in `_ready()`) |
| Contact damage | `collision_damage=35` | `ContactHitBox.damage=20` | **35** (`bomber.gd:23-24`) |
| score_value | `80` | — | 80 |
| movement_speed | `80.0` (also `@export var speed:float=80.0` on the script itself) | — | 80.0 when self-driven |
| bomb_interval | `1.2` s | — | 1.2 s |
| counts_toward_wave_clear / counts_as_escape | not set in `.tres` → `ShipConfig` defaults | — | both `true` |

Bomb (`bomb.gd`/`bomb.tscn`, no config resource, all values hardcoded): `fall_speed=120.0` px/s, `fuse_time=5.0` s, `trigger_time=1.0` s, `HitBox.damage=40`, HitBox `CircleShape2D radius=28`, `ProximityDetector radius=80`.

#### 5. Movement
`bomber.gd:34-37` self-drives in `_physics_process`: `velocity = Vector2(direction * speed, 0)`, `move_and_slide()`, then `_check_off_screen()` frees the node once `abs(global_position.x - cam.global_position.x) > viewport.x*0.5 + 70`. `direction` is `1.0` (left-to-right) by default, exported, overridable via spawn `initial_props` (`{"direction": 1.0}` / `{"direction": -1.0}` seen in the commented-out `level_2_waves.gd`). No entry curve, no exit besides the edge check — constant horizontal velocity for its whole life.

**Contradiction found:** `bomber/ENEMY.md:23` explicitly documents this horizontal self-drive and warns "attaching `.move()` would suspend this via `set_physics_process(false)`." But the only *live* spawn (`level_1_director.gd:693,777`) attaches `.move(b.straight(82))` / `.move(b.straight(80))` — which **does** suspend `bomber.gd`'s own `_physics_process`/off-screen check via `EnemyPathMover`, handing movement to a vertical `StraightMovement` (angle defaults to 0 = "down" per the sprite-rotation convention documented in `wave_builder.gd:65`) instead of the horizontal sweep ENEMY.md describes (see §12).

#### 6. Attack
Drops a `bomb.tscn` every `bomb_interval` (1.2 s) via a dedicated child `Timer` created in `_ready()` (`bomber.gd:28-32`), **independent of `_physics_process`** — so bombing continues even when `EnemyPathMover` suspends the bomber's own movement code (comment at `bomber.gd:26-27`). `_drop_bomb()` spawns the bomb at the bomber's current `global_position` and parents it to `get_parent()`, not to the bomber itself, so dropped bombs outlive the bomber. No aim — bombs simply fall straight down from the drop point. Also has 35 contact damage via its own `ContactHitBox` (layer 256, mask 0 — harmless, see §8).

#### 7. States / phases
No enum on Bomber itself — continuous flight + independent bomb timer.

`Bomb` has an explicit `enum State { FALLING, TRIGGERED, EXPLODED }` (`bomb.gd:12`), initial state `FALLING`:
```
                 player HurtBox (layer 128) enters
                 ProximityDetector (r=80)
FALLING ───────────────────────────────────────▶ TRIGGERED ──trigger_time (1.0s) elapses──▶ EXPLODED
   │                                                                                             │
   └── fuse_time (5.0s) elapses without proximity trigger ─────────────────────────────────────▶ ┘
                                                                                                    │
                                                                            HitBox active 0.15s, then queue_free()
```
The bomb keeps falling at 120 px/s through every state until EXPLODED or off-screen exit; TRIGGERED lerps its `ColorRect` from dark grey `(0.15,0.15,0.15)` to bright orange `(1.0,0.15,0.0)` as a visual countdown.

#### 8. Collision & damage
- Body `CollisionShape2D`: `CircleShape2D radius=22`.
- `HurtBox`: layer 512, `.tscn` mask 65 — **forced to 1121 (`97|1024`) at runtime** by `base_enemy.gd:51`; shares the same radius-22 shape as the body.
- `ContactHitBox`: layer 256, **mask 0** in the `.tscn`; `damage` starts at 20, overwritten to 35 in `_ready()`; `damage_type=2` (`CONTACT`, from `HitBox.DamageType{LASER,ROCKET,CONTACT}`); same radius-22 `CircleShape2D` as the body (matches the geometry invariant `test_contact_hitbox_geometry.gd` enforces). Mask 0 is not a bug here — damage detection is driven from the *player's* `HurtBox` scanning for layer-256 areas, not from the bomber's own `ContactHitBox` scanning outward (see `global/components/hurtbox_component.gd:9-18`, `hitbox_component.gd`).
- No armour/shield/deflection logic anywhere in this enemy.

#### 9. Death & rewards
Standard `BaseEnemy` flow: HP 0 → `died` emitted, `ExplosionEffect.explode()`, `was_killed=true`, `queue_free()`. `score_value=80`. `counts_toward_wave_clear=true`, `counts_as_escape=true` (both defaults, unmodified) — escaping off-screen alive costs the normal escape-combo penalty. Bombs already dropped are separate nodes and persist/detonate independently of the bomber's death.

#### 10. Where it's used
- WaveBuilder: `b.bomber()` (`wave_builder.gd:86`).
- **Live** (`assault/scenes/levels/edelia/1/level_1_director.gd`): 2 solo spawns —
  - `~58.0s` ("bomber + escort drones + side fighters"): `b.bomber().at(0,-400).move(b.straight(82)).shoot_at_player()` (line 693), paired with 2 `b.drone()` escorts.
  - `~98.0s` ("second bomber pressure"): `b.bomber().at(0,-400).move(b.straight(80)).shoot_at_player()` (line 777).
- **Inactive**: referenced 3× (fully `#`-commented) in `assault/scenes/levels/level_2_waves.gd` (waves 6, 9, 12 — "Bomber run", "Heavy bomber pair", "Double bomber"), each paired with `{"direction": 1.0}` / `{"direction": -1.0}` — i.e. that draft *does* match ENEMY.md's self-driven horizontal-sweep design, unlike the live Level 1 usage.

#### 11. Tests
No dedicated `test_bomber.gd`. Covered by roster-driven invariant tests: `tests/integration/test_config_instance_isolation.gd`, `tests/integration/test_enemy_contact_damage.gd` (asserts `ContactHitBox.damage==35==bomber_config.tres.collision_damage`), `tests/integration/test_contact_hitbox_geometry.gd`, `tests/integration/test_enemy_hurtbox_geometry.gd`, plus project-wide `test_entity_sprite_transparency.gd` (sweeps `bomber.png`), `test_project_load_integrity.gd`, `test_suite_integrity.gd`, `test_resource_uid_integrity.gd`.

#### 12. Known issues
- **(inferred)** Movement-design contradiction: ENEMY.md documents and the script implements a self-driven horizontal sweep, but the only live wave spawn attaches `.move()` with a vertical `StraightMovement`, which suspends that self-drive via `EnemyPathMover.set_physics_process(false)`. Either the ENEMY.md/self-drive code is stale, or the live spawn is not doing what was intended.
- **(inferred)** `.shoot_at_player()` on both live spawns sets `initial_props["aim_mode"]="PLAYER"` (`wave_builder.gd:54-57`), but `bomber.gd` has no weapon/gun component that reads `aim_mode` — only the bomb-drop `Timer`. The call appears to be inert boilerplate.
- Not present in `docs/discovered-bugs.md`.

#### 13. Open Space notes
- `bomber.gd:44-51` `_check_off_screen()` computes despawn bounds from `get_viewport().get_camera_2d()` and the current viewport half-width — a fixed-camera/autoscroll assumption that has no direct equivalent in free-flight.
- `bomber.gd:34-37`'s constant horizontal velocity assumes a portrait autoscroll arena with a "player's lane" to cross; that concept doesn't exist in open, all-directions flight.
- `bomb.gd:91-97` `_check_off_screen()` similarly keys off `cam.global_position.y` and viewport height.
- `bomb.gd:47` (`position.y += fall_speed*delta`) and its layer-128 proximity trigger assume "down" always means "toward the player" — breaks once the player can approach from any angle.
- The forced `hurt_box.collision_mask=1121` (`base_enemy.gd:51`) and the 256/512 layer scheme are Assault-specific; Open Space's own collision-layer numbering was not examined in this pass and should be confirmed separately.

---

### Bonus Drone

#### 1. Identity
- Folder: `assault/scenes/enemies/bonus_drone/`
- Scene: `bonus_drone.tscn`, script: `bonus_drone.gd`, `class_name BonusDrone`, extends `BaseEnemy`.
- Config: `bonus_drone_config.tres` → `class_name BonusDroneConfig extends ShipConfig` (`bonus_drone_config.gd`).

#### 2. Role
"Fast, fragile, non-shooting flyby worth a big score chunk. Optional reward, not a real threat." — "missing it costs nothing; killing it pays out" (`bonus_drone/ENEMY.md:3-4`).

#### 3. Visuals
- Reuses `assault/assets/sprites/enemies/drone.png`, **32×32 px** (a different texture from `drones.png`/`drone_2.png` used by the other two drone enemies).
- `bonus_drone.tscn`: `Sprite2D` at `position=(0,-1)`, `rotation=3.14159` (180°), no `ShaderMaterial`. The `"hit"`/`"RESET"` `Animation` sub-resources in this `.tscn` have **no tracks defined at all** (`bonus_drone.tscn:11-16`) — unlike bomber/drone_interceptor's functional shader-flash animations, this one is an empty stub, so `hit_flash_player.play("hit")` (called by `base_enemy.gd` on every hit) has nothing to animate here.
- At runtime, `bonus_drone.gd:23-26` sets `sprite.modulate = Color(1.4, 1.15, 0.4, 1.0)` (gold/amber, overbright) and `sprite.scale = Vector2(1.5, 1.5)` — so the on-screen result is `drone.png` at 1.5× scale, gold-tinted instead of its native red.
- Visual read of `drone.png`: a small, simple red/maroon angular diamond/crystal-shaped ship, top-down, pointed nose, minimal detail (32×32 is small).

#### 4. Stats
| Field | value | note |
|---|---|---|
| max_health | `1` | matches scene Health default (both `1`) — no discrepancy here |
| collision_damage | `0` | **no `ContactHitBox` node exists at all** in `bonus_drone.tscn` — deliberate, confirmed by `test_enemy_contact_damage.gd`'s own comment (line 30-33) |
| score_value | `500` | largest of the four researched enemies by far |
| counts_toward_wave_clear | `false` | explicit override |
| counts_as_escape | `false` | explicit override |
| movement_speed | `280.0` (`BonusDroneConfig`) | **(inferred) dead field** — never read by `bonus_drone.gd`, and the only live spawn path hardcodes `560.0` instead (see §5) |

#### 5. Movement
No `_physics_process` override at all — fully delegated to an externally-attached `EnemyPathMover`. The only live spawn path is `level_1_director.gd::_spawn_bonus_drone()` (lines 104-146):
- Spawn position: `cam.global_position + cam.offset + camera_offset`, where `camera_offset` is `Vector2(-680, 60)` (left-to-right call) or `Vector2(680, 60)` (right-to-left call).
- Attaches a `StraightMovement` with `speed = 560.0`, `angle = PI/2` (L→R) or `-PI/2` (R→L) — **not** the config's `movement_speed=280.0`.
- `EnemyPathMover.exit_mode = FREE_ON_DURATION`, `exit_time = 4.0` s (code comment: the drone visually crosses the screen in ~1.1 s at both resolutions, so 4 s is "generous").
- Bypasses the normal wave registry: `wave_manager.enemy_spawned.emit(entity, -1)` — wave index `-1` means it never contributes to any wave-clear tally.
- `docs/enemy-roster.md:386` gives the equivalent WaveBuilder form: `b.bonus_drone().at(-680, 60).move(b.straight(560, PI / 2)).free_after(4.0)` — confirming 560/4.0/±PI-2 as the tuned real numbers, not the `.tres`'s 280.0.

#### 6. Attack
None. No `ContactHitBox` node, no weapon — deals 0 contact damage by construction, not by a zeroed damage value.

#### 7. States / phases
None — no enum, no state machine, straight flyby only.

#### 8. Collision & damage
- Body `CollisionShape2D`: `CircleShape2D radius=12.0`.
- `HurtBox`: layer 512, `.tscn` mask 65 — forced to 1121 at runtime by `base_enemy.gd:51`, same as all `BaseEnemy` subclasses; same radius-12 shape as the body.
- No armour. Dies to any single hit of any damage type (`max_health=1`).

#### 9. Death & rewards
Standard `BaseEnemy` death flow. `score_value=500`. Because `counts_toward_wave_clear=false`, never killing it doesn't block a wave-clear bonus; because `counts_as_escape=false`, letting it fly off unkilled costs the player's escape-combo multiplier **nothing** — verified directly by `tests/integration/test_score_tracker_escape_penalty.gd::test_bonus_drone_escaping_does_not_cost_combo`, whose header (lines 1-11) explains this test exists because `score_tracker.gd:210-211` used to apply the escape penalty unconditionally on every `tree_exited` before `counts_as_escape` was added as a second, independent flag alongside `counts_toward_wave_clear`.

#### 10. Where it's used
**Not** spawned via any WaveBuilder call in the shipped level — no `b.bonus_drone()` appears in `level_1_director.gd` or `level_2_waves.gd`; only `docs/enemy-roster.md`'s illustrative example uses the builder form. It is spawned exclusively by `Level1Director`'s own section-relative scheduled callables (`level_1_director.gd:44-69`):
- `deep_space` section @ t=15.0 → left-to-right
- `planet_approach` section @ t=40.0 → right-to-left, and @ t=90.0 → left-to-right
- `cloud_descent` section @ t=25.0 → right-to-left

4 scheduled appearances total across Level 1's sections, always solo, alternating entry side.

#### 11. Tests
No dedicated file, but the one test written specifically for this enemy's *behavior* (not just generic roster geometry) is `tests/integration/test_score_tracker_escape_penalty.gd::test_bonus_drone_escaping_does_not_cost_combo`. Also covered by roster entries in `test_enemy_contact_damage.gd` (`no_hitbox: true`, asserting both "no ContactHitBox" and "config.collision_damage==0"), `test_contact_hitbox_geometry.gd::test_bonus_drone_still_has_no_contact_hitbox` (~line 191), `test_config_instance_isolation.gd`, `test_enemy_hurtbox_geometry.gd`, `test_entity_sprite_transparency.gd`.

#### 12. Known issues
- **(inferred)** `BonusDroneConfig.movement_speed` (280.0) is exported but never consumed anywhere — the sole live spawn path hardcodes 560.0 directly in `level_1_director.gd`. Dead config field.
- **(inferred)** The `"hit"`/`"RESET"` animation tracks in `bonus_drone.tscn` are empty stubs and there's no `ShaderMaterial` on its `Sprite2D`, so the hit-flash `base_enemy.gd` triggers on every hit is a visual no-op for this enemy (low practical impact since it dies in one hit).

#### 13. Open Space notes
- `level_1_director.gd:127` spawn math (`cam.global_position + cam.offset + camera_offset`) depends on `ArenaCamera`'s fixed-origin-plus-panning-offset model (comment cites `arena_camera.gd:5-12`) — free-flight has no equivalent fixed origin/offset pair to anchor an "off both edges" spawn.
- `EnemyPathMover.exit_mode=FREE_ON_DURATION` with a flat `exit_time=4.0` (`level_1_director.gd:141`) assumes a bounded, predictable screen-crossing time at a fixed viewport size.
- `StraightMovement` angles `PI/2`/`-PI/2` are defined against Assault's fixed portrait viewport axes; Open Space would need a player/hub-relative direction instead.

---

### Drone Interceptor

#### 1. Identity
- Folder: `assault/scenes/enemies/drone_interceptor/`
- Scene: `drone_interceptor.tscn`, script: `drone_interceptor.gd`, `class_name DroneInterceptor`, extends `BaseEnemy`.
- Config: `drone_interceptor_config.tres` → `class_name DroneInterceptorConfig extends ShipConfig` (`drone_interceptor_config.gd`).

#### 2. Role
"Self-managed pursuit drone. Closes on the player, circles briefly, then commits to a one-way predictive dash that explodes on contact." — "A wasp that won't be shaken... must be killed before it commits." (`drone_interceptor/ENEMY.md:3-4`).

#### 3. Visuals
- `assault/assets/sprites/enemies/drone_2.png`, **64×64 px**.
- `drone_interceptor.tscn`'s `Sprite2D` has **no authored `rotation`** (unlike the other three, which set 180°) — the whole node's `rotation` is instead actively driven every frame by `_face_target`/`_face_direction` (`ROTATION_LERP=7.0`), since the sprite node is literally named `"Sprite2D"` and `base_enemy.gd::_rotate_sprite()` only touches a node named `"AnimatedSprite2D"` (a no-op here).
- Same functional `hit_flash_vs.tres` `ShaderMaterial` + `"hit"`/`"RESET"` `AnimationPlayer` tracks (0.2s white flash) as Bomber — this one works.
- `CollisionShape2D`, `HurtBox`, `ContactHitBox` are all scaled `Vector2(3.0799994, 3.0799994)` over a default (radius-10) `CircleShape2D` → effective collision radius ≈ **30.8 px**, the largest of the four.
- Visual read: dark navy/near-black angular wasp/stealth-fighter silhouette with crimson accent markings and swept wing-like protrusions, symmetric, top-down, more detailed shading than the other three sprites (largest canvas at 64×64).

#### 4. Stats
| Field | value | note |
|---|---|---|
| max_health | `25` | matches scene Health default (`25`) — no discrepancy |
| collision_damage | `30` | scene's `ContactHitBox.damage` is already `30`, **and** re-applied in `_ready()` (`drone_interceptor.gd:59`) — both agree |
| score_value | `40` | re-applied explicitly in `_ready()` (line 46) — redundant with `base_enemy.gd`'s generic `cfg.score_value` propagation, but harmless |
| orbit_radius | `130.0` px | preferred orbit distance |
| orbit_speed | `1.8` rad/s | orbit angular velocity, counter-clockwise |
| approach_speed | `200.0` px/s | ENTER phase speed |
| orbit_correct_speed | `160.0` px/s | max ORBIT correction speed |
| dash_speed | `480.0` px/s | DASH burst speed |
| dash_prediction_time | `0.2` s | how far ahead the DASH aim predicts |
| counts_toward_wave_clear | `true` | explicit in `.tres`, matches default |

#### 5. Movement
Fully self-managed in `_physics_process` (`drone_interceptor.gd:64-79`), 3-phase AI, **never given `.move()`** in practice (ENEMY.md explicitly warns against it). See §7 for the full state graph. `_orbit_angle` and `_dash_timer` are randomised per spawn (`randf_range(0.0, TAU)`, `randf_range(1.0, 2.0)`) "so groups don't behave identically" (line 54-56).

#### 6. Attack
No projectile weapon. Pure kamikaze: `ContactHitBox` (mask 128 = player `HurtBox`) is connected to `_on_contact_hit`, which on first trigger calls `health.set_health(0)` (guarded by `if health.current_health > 0` against double-firing before `queue_free()` processes) — this routes through the normal `BaseEnemy` death flow, dealing its 30 `collision_damage` to the player through the same `ContactHitBox` the player's own `HurtBox` detects. No distinct telegraph beyond the ORBIT→DASH trajectory change itself (no pre-dash flash or sound coded).

#### 7. States / phases
`enum Phase { ENTER, ORBIT, DASH }` (`drone_interceptor.gd:20`), initial phase `ENTER`.
```
        distance to player <= orbit_radius (130px)
ENTER ────────────────────────────────────────────▶ ORBIT ──_dash_timer (1.0–2.0s, randomised)──▶ DASH
  │ fly straight at player,                             │ reaches 0                                  │
  │ approach_speed 200 px/s                              │ orbit_speed 1.8 rad/s around player,        │ lock _dash_direction toward
  │                                                       │ correction speed = clamp(dist*4, 60, 160)   │ predicted player position
  │                                                       │ px/s toward the ring                        │ (player.velocity * 0.2s ahead);
  │                                                       │                                              │ fly dash_speed 480 px/s
  │                                                       │                                              │ indefinitely; ends only by
  │                                                       │                                              │ off-screen despawn or contact
```
DASH is terminal — no transition back to ENTER/ORBIT.

#### 8. Collision & damage
- Body `CollisionShape2D`: default (radius 10) `CircleShape2D`, scaled 3.08× → ≈30.8 px effective radius.
- `HurtBox`: layer 512, `.tscn` mask 97 (forced to 1121 at runtime by `base_enemy.gd:51`, same as the others); same 3.08×-scaled shape as the body.
- `ContactHitBox`: layer 256, mask **128** (the one enemy of these four whose `ContactHitBox` mask matters functionally, since it self-detects the player for its own kamikaze trigger), `damage=30`, `damage_type=2` (`CONTACT`), same 3.08×-scaled shape as the body.
- No armour/deflection.

#### 9. Death & rewards
Dies either from being shot down (25 HP) via the normal damage flow, or from its own kamikaze self-kill on player contact — both converge on the identical `BaseEnemy` death flow (`died` signal, `ExplosionEffect`, `was_killed=true`, `queue_free()`). `score_value=40`. `counts_toward_wave_clear=true` (default) — a drone that dashes off-screen without ever reaching the player still counts as a standard "escape" against wave-clear/combo bonuses.

#### 10. Where it's used
WaveBuilder: `b.drone_interceptor()`. Only live use found: `level_1_director.gd:288-291`, under the wave comment `"1.5 s — drone interceptor pair for testing; self-managed AI, no .move() needed"`:
```
b.drone_interceptor().at(-160, -420)
b.drone_interceptor().at( 160, -420).delay(0.35)
```
2 units, spawned with `.at()` only (correctly following the "never `.move()`" rule), staggered 0.35 s apart. The in-code comment "for testing" is the only signal this pairing might be a placeholder rather than deliberately tuned encounter design (**inferred**). Not referenced anywhere in `level_2_waves.gd`, not even in commented-out form.

#### 11. Tests
No dedicated file. Covered by `test_config_instance_isolation.gd`, `test_enemy_contact_damage.gd` (asserts `ContactHitBox.damage==30==.tres`), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_entity_sprite_transparency.gd` (`drone_2.png`), plus project-wide integrity tests.

#### 12. Known issues
Not mentioned in `docs/discovered-bugs.md`; no TODO/FIXME in its files. The only soft signal of anything provisional is the "for testing" wave comment noted in §10 (**inferred**).

#### 13. Open Space notes
- `drone_interceptor.gd:129-140` `_check_off_screen()` is explicitly camera/viewport-rect based (`cam.global_position ± viewport*0.5 ± 80px margin`, all 4 sides) — DASH's only exit besides killing the player is leaving this camera-relative rectangle, meaningless without a fixed camera rect.
- `_get_player()` (`drone_interceptor.gd:151-155`) grabs `get_tree().get_nodes_in_group("player")[0]` — should work in Open Space as long as the player is in the same group there (not verified in this pass).
- The ENTER/ORBIT/DASH AI itself is already fully 2D/omnidirectional (`Vector2.RIGHT.rotated(_orbit_angle)` orbit math, free rotation via `_face_target`/`_face_direction`) and is **the one enemy of the four whose core AI looks most portable to free-flight as-is** (**inferred**) — the main blocker is just the camera-relative despawn check above.

---

### Kamikaze Drone

#### 1. Identity
- Folder: `assault/scenes/enemies/kamikaze_drone/`
- Scene: `kamikaze_drone.tscn`, script: `kamikaze_drone.gd`, `class_name KamikazeDrone`, extends `BaseEnemy`.
- Config: `drone_config.tres` → `class_name DroneConfig extends ShipConfig` (`drone_config.gd`) — note the file/class name says "Drone," not "Kamikaze," a naming mismatch with the folder.
- WaveBuilder exposes it as **`b.drone()`** (`wave_builder.gd:79`, `SpawnConfig.new(DRONE)`), not `b.kamikaze_drone()` — another folder/class-vs-API naming mismatch worth flagging for a redesign pass, especially since `drone.png` (bonus_drone's texture) and `drone_2.png` (drone_interceptor's texture) are separate files from this enemy's `drones.png`.

#### 2. Role
"Cheap, fast, non-shooting drone that locks a straight-line heading at spawn and rams the player." — "Swarm fodder... come in formations and clusters to force constant dodging." (`kamikaze_drone/ENEMY.md:3-4`).

#### 3. Visuals
- `assault/assets/sprites/enemies/drones.png`, **126×84 px** sheet, laid out **3 columns × 2 rows = 6 variants** (cell size 42×42, derived at runtime from `_sprite.texture.get_size() / [3,2]`, `kamikaze_drone.gd:26-29` — not hardcoded).
- On `_ready()`, picks `randi() % 6` and sets `region_enabled=true` + a `region_rect` to that cell (lines 30-37) — one of 6 pre-baked variants per spawn, chosen randomly, no animation.
- `"hit"`/`"RESET"` `Animation` sub-resources in `kamikaze_drone.tscn` have **no tracks** (same empty-stub pattern as `bonus_drone.tscn`), and there's no `ShaderMaterial` on its `Sprite2D` either — the hit-flash is a visual no-op here too (**inferred**).
- `Sprite2D` starts at `position=(0,-1)`, `rotation=3.14159` (180°) in the `.tscn`, then is further rotated at runtime: `rotation = _direction.angle() + PI/2` (line 45), with the code comment "drones.png naturally faces UP, so offset by +PI/2 to align with `_direction`."
- Visual read of the sheet: 6 small, dark navy/near-black angular "arrow"/"manta" silhouettes with red/crimson trim, top-down, simpler/smaller than `drone_2.png` but same design language; arranged 2 rows × 3 columns on a mostly-transparent sheet.

#### 4. Stats
| Field | value | note |
|---|---|---|
| max_health | `30` (`.tres`) | scene Health default is `40`, overwritten in `_ready()` — same "tres wins" pattern as Bomber (ENEMY.md itself notes this) |
| collision_damage | `30` (`.tres`) | **but never actually read** — `kamikaze_drone.gd`'s `_ready()` never touches `contact_hit_box.damage`; the `.tscn`'s `ContactHitBox` simply hardcodes `damage=30` directly, which happens to equal the `.tres` value. ENEMY.md flags this explicitly ("note: the contact HitBox hardcodes damage = 30 in code"). The **scene's hardcoded node value is what actually wins**, not the config. |
| score_value | `10` | lowest of the four researched enemies — cheapest/most disposable |
| movement_speed | `140.0` | assigned to `speed` in `_ready()`, but only used by the self-driven fallback path (see §5), which is suspended in every observed wave call |
| counts_toward_wave_clear | not set in `.tres` → `ShipConfig` default `true` | |

#### 5. Movement
Two coexisting systems, same tension as Bomber:
- **(a) Self-driven fallback** (`kamikaze_drone.gd:39-52`): on `_ready()`, computes `_direction` as the normalized vector from itself to the first node in group `"player"` (or `Vector2(0,1)` — straight down — if none found), a **one-time heading lock at spawn, never re-aimed**. Every frame: `global_position += _direction * speed * delta` (speed=140 from config). Off-screen check (`_check_off_screen`, lines 59-67) only checks the **bottom** camera-relative edge (`cam.global_position.y + viewport.y*0.5 + 60`).
- **(b) Path-driven** — every live wave spawn found attaches `.move()` (`b.sine()`, `b.straight()`, or a `.formation()` variant), which per `EnemyPathMover`'s convention calls `set_physics_process(false)` on the drone, **suspending the self-aimed rush entirely**. In practice, the drone's actual flight path in every shipped wave is whatever `EnemyPathMover` computes from the attached movement/formation — not the self-aimed rush.

**Contradiction found:** `ENEMY.md`'s own "Behaviour & Movement" section (line 23) describes the self-aimed rush as the live behavior, while its own "Spawn notes" section (line 45) says "Always add `.move()`" — which suspends that exact behavior. The self-aimed-rush code appears to be dead in every currently-authored wave (**inferred**).

#### 6. Attack
None ranged — kamikaze only, identical mechanism to `DroneInterceptor`: `contact_hit_box.area_entered.connect(_on_contact_hit)`, first trigger sets `health.set_health(0)` (same double-fire guard). `ContactHitBox` mask=128 (player `HurtBox`), damage hardcoded 30 (see §4). No telegraph.

#### 7. States / phases
None — single continuous flight (self-aimed or externally path-driven) from spawn to either player contact, being shot down, or leaving the bottom edge.

#### 8. Collision & damage
- Body `CollisionShape2D`: default (unscaled) `CircleShape2D`, no radius override in the `.tscn` → Godot engine default **radius 10.0** (**inferred** default, not overridden anywhere in the file) — the smallest collision circle of the four despite a 42×42 px visible sprite cell (visible sprite noticeably larger than the hittable/hurtable circle; not caught by `test_enemy_hurtbox_geometry.gd`, which only checks HurtBox-vs-body-shape coverage, not sprite bounds) (**inferred** mismatch).
- `HurtBox`: layer 512, `.tscn` mask 65 (forced to 1121 at runtime by `base_enemy.gd:51`); same radius-10 shape as the body.
- `ContactHitBox`: layer 256, mask 128, `damage=30` (hardcoded, see §4), `damage_type=2` (`CONTACT`), same radius-10 shape.
- No armour/deflection.

#### 9. Death & rewards
Dies from being shot (30 HP) or from its own kamikaze self-kill on player contact, both via the standard `BaseEnemy` death flow. `score_value=10` — the lowest payout of the four researched enemies, matching its disposable-swarm role. `counts_toward_wave_clear=true` and `counts_as_escape=true` (both unmodified defaults) — a drone that rams the player still "counts as killed" for wave-clear purposes (it died, by suicide), while one that flies off the bottom edge unshot pays the normal escape-combo penalty.

#### 10. Where it's used
By far the **most-spawned enemy in Level 1** — `b.drone()` appears roughly 80+ times across `assault/scenes/levels/edelia/1/level_1_director.gd`, in every section, as solo drops, staggered pairs/trios, and `cluster_formation()`/`wedge_formation()`/`line_formation()` groups of 3–5, using `sine()` and `straight()` paths from above, from the sides, and (in the "cloud_descent" section) from below — e.g. `b.drone().at(-150, 400).move(b.straight(185, PI))` (angle `PI` = "up," per the sprite-rotation convention in `wave_builder.gd:65-66`). Also referenced, fully commented out (`#`), as `builder.DRONE` throughout `assault/scenes/levels/level_2_waves.gd` (waves 4, 6, 7, 9, 11, 12) — that inactive draft leans on it just as heavily.

#### 11. Tests
No dedicated file. Covered by `test_config_instance_isolation.gd`, `test_enemy_contact_damage.gd` (asserts `ContactHitBox.damage==30`, cross-checked against `drone_config.tres.collision_damage==30` — passes only because the hardcoded scene value and the unread config value coincidentally agree, per that test file's own header, `test_enemy_contact_damage.gd:12-15`), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_entity_sprite_transparency.gd` (`drones.png`), plus project-wide integrity tests.

#### 12. Known issues
- The movement-system contradiction in §5 (ENEMY.md's two sections disagree; the self-aimed-rush `_physics_process` code is suspended by `.move()` in every observed spawn) — partly explicit in ENEMY.md, partly **inferred**.
- `collision_damage` in `drone_config.tres` is never actually read for the `ContactHitBox` — explicitly flagged by ENEMY.md itself, not inferred.
- Collision circle (radius 10, unscaled) noticeably smaller than the 42×42 visible sprite cell — **(inferred)**, not gate-checked.
- Not present in `docs/discovered-bugs.md`.

#### 13. Open Space notes
- `kamikaze_drone.gd:39-45` locks `_direction` once at spawn and never re-aims — viable in a scrolling corridor with limited player maneuvering room, but trivially sidestepped in free-flight; would need continuous homing or much larger swarm counts to stay threatening.
- `kamikaze_drone.gd:59-64` `_check_off_screen()` only checks the camera-relative **bottom** edge — assumes Assault's autoscroll always eventually carries the drone off the bottom of a portrait viewport; free-flight has no "bottom edge."
- The "`drones.png` faces UP, offset +PI/2" convention (line 44) is tied to Assault's screen-space orientation baked into the art; harmless to keep as long as the same offset convention is preserved, but notable coupling between the art asset and the mode's screen-space assumptions.
- Per CLAUDE.md's design-unit-coordinates convention, all wave x/y offsets this enemy consumes (e.g. `Vector2(-260,-400)`) are authored in 640×360 space and scaled by `ArenaCamera.WORLD_SCALE` (2.0); Open Space's own coordinate convention was not examined in this pass.

---

## Part 3 — Fighters and gunship

### Interceptor

#### 1. Identity
- Folder: `assault/scenes/enemies/interceptor/`
- Scene: `interceptor.tscn` (`assault/scenes/enemies/interceptor/interceptor.tscn:56`, root node `Interceptor` of type `CharacterBody2D`)
- Script: `interceptor.gd`, `class_name Interceptor extends BaseEnemy` (`interceptor.gd:2-3`)
- Config resource: `InterceptorConfig` (`interceptor_config.gd`, `class_name InterceptorConfig extends ShipConfig`), instance `interceptor_config.tres`
- Extends `BaseEnemy` -> `CharacterBody2D`

#### 2. Role
"Flying Gatling gunship" — a path-following strafer with no self-managed AI; it hoses an 11-shot/s stream of low-damage, slightly scattered bullets along its direction of travel (`ENEMY.md:1-4`). Used as a lock-on diver (`player_focus`) or a side-strafing lane threat (`straight`).

#### 3. Visuals
- Sprite: `res://assault/assets/sprites/enemies/interceptor.png`, single plain `Sprite2D` (not `AnimatedSprite2D`) — `interceptor.tscn:59-61`. No animation frames beyond the shared hit-flash shader track.
- Texture size (read from PNG header): **64×74 px**.
- Description from opening the PNG: a small, dark angular starfighter viewed top-down/orthographic, nose pointing up in the source art. Silhouette is a narrow forward fuselage flanked by two swept-back side pods/wings, mostly near-black/charcoal hull with red glowing accent panels down the spine and small red engine-glow dots — reads as a "buzzsaw" gunship, compact and aggressive.
- `CollisionShape2D` (visual body) scale `Vector2(1.8000002, 1.8000002)` over a `CircleShape2D radius=14.0` (`interceptor.tscn:63-65`) → effective ~25.2 px radius.
- Rotation: no explicit scene rotation; `BaseEnemy._rotate_sprite()` only affects `AnimatedSprite2D` nodes and this uses `Sprite2D`, so it is **not** flipped 180° by the base class — facing is whatever `EnemyPathMover` sets from travel direction (or 0 if undriven).
- Hit flash: `HitFlashAnimationPlayer` plays `"hit"` (0.2 s) toggling `Sprite2D:material:shader_parameter/enabled` via a shared `hit_flash_vs.tres` shader (`interceptor.tscn:10-14, 34-48`). No damaged/shield texture swap, no particle child beyond the base `HitEffect`/`ExplosionEffect` added generically in `BaseEnemy._ready()`.

#### 4. Stats
- HP: `.tres` `max_health = 70` (`interceptor_config.tres:7`) overrides the `.gd` default `100` (inherited `ShipConfig.max_health`, `ship_config.gd:7`); scene's own `Health` node also authors `max_health=70 current_health=70` (`interceptor.tscn:78-82`) — all three agree at 70, applied again explicitly in `interceptor.gd:26-27`.
- Contact damage: `collision_damage` **not overridden** in `.tres` → inherits `ShipConfig` default **20** (`ship_config.gd:8`); scene's `ContactHitBox damage=20` (`interceptor.tscn:91`) matches, and `interceptor.gd` never re-applies `contact_hit_box.damage`, so the effective value is 20 either way (pinned by `tests/integration/test_enemy_contact_damage.gd`, which explicitly notes Interceptor has no `collision_damage` line so it "inherits ShipConfig's default of 20 ... which happens to equal the base helper's hardcoded 20").
- Score: `score_value = 75` (`interceptor_config.tres:8`, applied `interceptor.gd:28`).
- `counts_toward_wave_clear`/`counts_as_escape`: inherited `ShipConfig` defaults `true`/`true` (not overridden).
- Bullet stats (from `InterceptorConfig` defaults, `interceptor_config.gd:6-13`, none overridden in `.tres`): `fire_interval = 0.09` s (~11.1 shots/s), `bullet_damage = 4`, `bullet_speed = 220.0` px/s, `spread_angle = 0.08` rad (≈±4.5°).
- `BulletPool.pool_size = 20` (`interceptor.gd:33`, sized for 0.09s interval / ~1.5s effective range).

#### 5. Movement
No self-managed movement AI at all — `interceptor.gd` has no `_physics_process`/`_process` override. Movement is 100% delegated to `EnemyPathMover` via WaveBuilder `.move()`. Documented typical uses (`interceptor.gd:8-10`, `ENEMY.md:23,48-49`):
- `b.interceptor().at(x,y).move(b.player_focus(240))` — locks onto the player's direction at spawn (240 px/s) and flies through (`PlayerFocusMovement` is duplicated per-instance by `EnemyPathMover._ready()`, `enemy_path_mover.gd:51-58`, direction computed once from `(player.global_position - actor.global_position).normalized()`).
- `b.interceptor().at(x,y).move(b.straight(200, PI/2)).free_after(5.0)` — straight strafing run.
`EnemyPathMover` rotates the actor to face travel direction each frame (`atan2(-vel.x, vel.y)`, `enemy_path_mover.gd:87`) and culls it 80 px past any viewport edge once it has been on-screen once (`_check_off_screen`, lines 100-117), or via `exit_time`/duration mode if configured.

#### 6. Attack
`AttackController` (generic `global/components/attack_controller.gd`) drives a `GatlingAttackPattern` (`global/resources/attack/gatling_attack_pattern.gd`) built fresh in `interceptor.gd:36-40`:
- `fire_interval = 0.09`, `bullet_damage = 4`, `bullet_speed = 220.0`, `spread_angle = 0.08` (class defaults for the pattern itself are `0.8`/`4`/`220.0`/`0.08`/`aim_at_player=true`/`spawn_offset=(0,10)` — Interceptor only overrides the first three from config; `aim_at_player` and `spawn_offset` are left at the `GatlingAttackPattern` script defaults, i.e. it **does** aim at the player by default despite ENEMY.md calling it "fires forward in the direction of travel" — see Open Space notes).
- `fire()` (`gatling_attack_pattern.gd:18-37`) acquires a bullet from the pool at `ship.global_position + spawn_offset`, sets its `HitBox.damage` and `speed`, computes `base_dir` toward the nearest node in group `"player"` (falls back to `Vector2.DOWN` if none) when `aim_at_player` is true, else `Vector2.DOWN.rotated(ship.rotation)`, then applies `base_dir.rotated(randf_range(-spread_angle, spread_angle))` — the ±4.5° scatter.
- Bullet scene: `res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` (`EnemyBullet`, `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`), speed field defaults 250 but is overwritten per-shot to 220; expires past a 740×740-scaled arena boundary (`enemy_bullet.gd:12-16`, margin 64 px).
- No burst/telegraph — steady single-shot stream at ~11/s.
- Contact/ram damage: 20 (see Stats).

#### 7. States / phases
None — Interceptor has no enum/state machine. It is pure config + `AttackController` + (optionally) `EnemyPathMover`.
```
[spawn] -> (EnemyPathMover drives position every frame) -> AttackController fires every 0.09s -> despawn on screen-exit / free_after
```

#### 8. Collision & damage
- `HurtBox` (`Area2D`): `collision_layer = 512`, `collision_mask = 97` (`interceptor.tscn:67-69`) — narrower than `BaseEnemy._ready()`'s own assignment of `97 | 1024`; `_ready()` runs after scene instantiation and overwrites this to `1121` (97|1024) at runtime, so the scene-authored `97` is only the design-time value.
- `HurtBox` `CollisionShape2D` scale `1.8` over the same `CircleShape2D radius=14.0` (`interceptor.tscn:73-76`) — matches body shape+scale (only 0.0000002 float noise difference from the body's 1.8000002), satisfying the hurtbox-covers-body invariant (`tests/integration/test_enemy_hurtbox_geometry.gd`).
- `ContactHitBox` (`Area2D`): `collision_layer = 256`, `collision_mask = 0`, `damage = 20`, `damage_type = 2` (CONTACT, per `HitBox.DamageType` enum `LASER=0, ROCKET=1, CONTACT=2`), shape scale `1.8000002` over the same circle (`interceptor.tscn:87-96`) — geometry matches the body per `tests/integration/test_contact_hitbox_geometry.gd`.
- No armour/shield/deflection logic. Damage reaction is the shared `HitFlashAnimationPlayer` + `HitEffect` burst from `BaseEnemy`.

#### 9. Death & rewards
- On `Health.amount_changed` reaching 0, `BaseEnemy._on_health_changed` sets `was_killed = true`, emits `died`, plays `ExplosionEffect.explode()`, and `queue_free()`s (`base_enemy.gd:78-86`). No Interceptor-specific override.
- Score: 75 points (`ScoreTracker` reads `score_value` off the config, per `base_enemy.gd:60-68` comment).
- `counts_toward_wave_clear = true`, `counts_as_escape = true` (defaults).

#### 10. Where it's used
`assault/scenes/levels/edelia/1/level_1_director.gd` is the only level director in the repo; `interceptor` appears **2** times there:
- `level_1_director.gd:262`: `b.interceptor().at(-200, -420).move(b.player_focus(240))`
- `level_1_director.gd:263`: `b.interceptor().at( 200, -420).move(b.player_focus(240)).delay(0.4)`
  (a symmetric lock-on pair, staggered 0.4 s, in Section with comment "0.0 s — interceptor pair: lock onto player and fly through with Gatling", `level_1_director.gd:260`).
Also documented (not necessarily currently spawned) in `docs/enemy-roster.md:227-251` under "Gatling Interceptor" with the same two movement idioms.

#### 11. Tests
- `tests/integration/test_enemy_contact_damage.gd` includes `interceptor` in its roster (`test_enemy_contact_damage.gd:76-79`) and asserts its `ContactHitBox.damage` equals its config's `collision_damage` (20, via `ShipConfig` default since `.tres` has no override).
- `tests/integration/test_config_instance_isolation.gd` sweeps every `ShipConfig` subclass directory-wide, which includes `InterceptorConfig`.
- No Interceptor-specific test file exists (no `test_interceptor*.gd` found under `tests/`).

#### 12. Known issues
- None called out in `docs/discovered-bugs.md` specific to Interceptor.
- `ENEMY.md:24` documents the attack as firing "forward in the direction of travel," but the actual `GatlingAttackPattern` instance built in `interceptor.gd:36-40` leaves `aim_at_player` at its class default `true` (never set to `false`), so it currently **aims at the player**, not the travel direction — a doc/code mismatch worth flagging (inferred from reading `gatling_attack_pattern.gd:14,28-33` against `interceptor.gd`; not called out in `discovered-bugs.md`).

#### 13. Open Space notes
- Movement is entirely `EnemyPathMover`-driven, which assumes a scrolling `Camera2D` (`_cam.global_position`) and a fixed viewport rect for off-screen culling (`enemy_path_mover.gd:100-109`) — in free-flight Open Space there is no autoscroll and the "camera" may not track a single forward axis, so the off-screen cull and the `PlayerFocusMovement` one-shot direction-at-spawn model (computed once, `enemy_path_mover.gd:52-58`) would need to become continuous homing or an arena-relative check instead of screen-relative.
- `GatlingAttackPattern.fire()` (`gatling_attack_pattern.gd:33-35`) falls back to `Vector2.DOWN.rotated(ship.rotation)` when `aim_at_player=false` and no players are found — "down" is an Assault-autoscroll convention (bullets a mover's `look_angle` convention: 0=down, PI=up, PI/2=left, `enemy_path_mover.gd:22`); Open Space has no privileged "down," so this fallback and the sprite/rotation convention baked into `EnemyPathMover._physics_process` (`enemy_path_mover.gd:85-89`) are Assault-specific and would need a facing-relative replacement.
- `EnemyBullet` expiry is a hardcoded 740×740 world-space box derived from Assault's `ArenaCamera` (`enemy_bullet.gd:6-16`), not a viewport- or camera-relative bound — would need to key off Open Space's own play-area bounds (or a lifetime timer) instead.

---

### Light Assault Ship

#### 1. Identity
- Folder: `assault/scenes/enemies/light_assault_ship/`
- Scene: `light_assault_ship.tscn` (root node `LightAssaultShip`, `CharacterBody2D`, `light_assault_ship.tscn:70-71`)
- Script: `light_assault_ship.gd`, `class_name LightAssaultShip extends BaseEnemy` (`light_assault_ship.gd:1-2`)
- Config resource: `FighterConfig` (`fighter_config.gd`, `class_name FighterConfig extends ShipConfig`), instance `fighter_config.tres`
- State scripts: `states/approach_state.gd` (`class_name FighterApproachState extends State`) and `states/strafe_exit_state.gd` (`class_name FighterStrafeExitState extends State`) — both children of an `AIStateMachine` node (`global/statemachine/state_machine.gd`) authored directly in the scene.
- WaveBuilder name: `b.fighter()` (the folder/class is "light assault ship" but every spawn call and `ENEMY.md` heading call it "Light Assault Ship — Standard fighter" / builder `fighter`).

#### 2. Role
"The baseline shooter" — a path-following workhorse that flies in, holds a line, and fires aimed or forward shots; also carries its own fallback `ApproachState -> StrafeExitState` AI for when no path is attached (`ENEMY.md:1-4`). Described as manageable alone but dangerous in formations with overlapping fire.

#### 3. Visuals
- Sprite: `res://assault/assets/sprites/enemies/assault.png`, wrapped in an `AnimatedSprite2D` with a single-frame `SpriteFrames` ("default" animation, 1 frame, `loop=true`, `speed=5.0`) — `light_assault_ship.tscn:19-28,73-76`. Effectively static art (one frame) using the `AnimatedSprite2D` node type specifically so `BaseEnemy._rotate_sprite()` (which only targets `AnimatedSprite2D`) flips it 180°.
- Texture size: **64×64 px**.
- Description from the PNG: a compact dark starfighter, top-down view, nose pointing up, with a bulbous red/maroon cockpit cluster at the front-top and twin sharp swept wings; hull is near-black with subtle red glow accents — visually similar family to the Interceptor sprite but stockier/rounder nose.
- Scale: body `CollisionShape2D scale = Vector2(2.199998, 2.199998)` over `CircleShape2D radius=13.0` (`light_assault_ship.tscn:78-80`) → ~28.6 px effective radius.
- Rotation: `BaseEnemy._rotate_sprite()` sets `AnimatedSprite2D.rotation_degrees = 180.0` at `_ready()` (`base_enemy.gd:70-74`), flipping the sprite to face downward/toward the player from its as-authored upward orientation.
- Hit flash: same shared `hit_flash_vs.tres` shader pattern as Interceptor, `"hit"` anim 0.2s toggling `AnimatedSprite2D:material:shader_parameter/enabled` (`light_assault_ship.tscn:33-68`).
- No damaged/shield texture swap.

#### 4. Stats
- HP: `.tres` `max_health = 60` (`fighter_config.tres:7`); the scene's `Health` node authors **no** explicit `max_health`/`current_health` (`light_assault_ship.tscn:93-96` — only `script=` line, no value overrides), so the config value (60) is what actually applies at runtime via `light_assault_ship.gd:19-20`. `ENEMY.md:12` confirms: "the `.tscn` Health node has no explicit max, so config sets it."
- Contact damage: `collision_damage = 20` (`fighter_config.tres:8`, equals `ShipConfig` default), re-applied explicitly to `contact_hit_box.damage` in `light_assault_ship.gd:21-22` (guarded by `if contact_hit_box:`). Scene's own `ContactHitBox damage=20` (`light_assault_ship.tscn:104`) already matches.
- Score: `score_value = 25` (`fighter_config.tres:9`) — propagated generically via `BaseEnemy._ready()`'s `cfg.score_value` read (`base_enemy.gd:66`), not re-set in `light_assault_ship.gd`.
- Movement: `movement_speed = 100.0` (`fighter_config.tres:10`) — **only used by the AI fallback** (`ApproachState`/`StrafeExitState` have their own hardcoded speeds, see below); irrelevant when `EnemyPathMover` is attached.
- Attack: `fire_interval = 0.8` s (`fighter_config.tres:11`), `bullet_damage = 8` (`fighter_config.tres:12`), `aim_mode = "PLAYER"` (`fighter_config.tres:13`).
- FORWARD-mode overrides applied only in code, never in `.tres`: `fire_interval = 0.3`, `bullet_speed = 420.0` vs PLAYER mode's `bullet_speed = 250.0` (`light_assault_ship.gd:40-42`) — "forward shooters fire faster with faster bullets — they can't lead their target, so higher volume compensates" (comment, line 38-39).
- `AIStateMachine` fallback speeds (used only when undriven): `ApproachState.speed = 80.0` (`approach_state.gd:10`), `hold_y_offset = 80.0` (line 11); `StrafeExitState.strafe_speed = 120.0` (`strafe_exit_state.gd:5`), `downward_drift = 20.0` (line 6).

#### 5. Movement
Two mutually-exclusive systems, selected by whether an `EnemyPathMover` child is present:
- **Normal (path-driven):** `.move()` supplies an `EnemyPathMover`, which disables `AIStateMachine` (`process_mode = PROCESS_MODE_DISABLED`, `enemy_path_mover.gd:63-65`) and drives position directly, same mechanics as Interceptor above.
- **Fallback AI (`AIStateMachine`, initial state `ApproachState`, `light_assault_ship.tscn:111-113`):**
  - `ApproachState.enter()` (`approach_state.gd:16-20`) computes `_hold_y = cam.global_position.y - viewport_size.y*0.5 + hold_y_offset(80)`.
  - `process_physics()` (lines 22-27): moves straight down at `speed=80` via `velocity=Vector2(0,80); move_and_slide()` until `global_position.y >= _hold_y`, then `state_transition.emit(strafe_state)`.
  - `StrafeExitState.enter()` (`strafe_exit_state.gd:10-11`) picks `_direction = ±1` randomly.
  - `process_physics()` (lines 13-25): `velocity = Vector2(_direction*120, 20)` (constant downward drift 20 px/s while strafing 120 px/s horizontally); frees itself once `global_position.x` passes 60 px beyond the left/right camera-relative viewport edge.
  - Firing continues unaffected in both states — handled by the ship's own `AttackController`, not the state nodes (`approach_state.gd:4`, `ENEMY.md:43`).

#### 6. Attack
`AttackController` driving an `AimedAttackPattern` (`global/resources/attack/aimed_attack_pattern.gd`) built in `light_assault_ship.gd:39-44`:
- `aim_mode` resolution: spawn-time `aim_mode` string (set by WaveBuilder `.shoot_forward()`/`.shoot_at_player()` before the node enters the tree) takes priority over `config.aim_mode` default `"PLAYER"` (`light_assault_ship.gd:32-33`).
- FORWARD (`forward=true`): `fire_interval=0.3`, `bullet_speed=420.0`, `aim_at_player=false` → fires straight down (`Vector2.DOWN.rotated(ship.rotation)`, `aimed_attack_pattern.gd:29-31`, using the ship's current rotation which `EnemyPathMover` keeps aligned to travel direction).
- PLAYER (`forward=false`, default): `fire_interval = config.fire_interval (0.8)`, `bullet_speed=250.0`, `aim_at_player=true` → aims at nearest node in group `"player"`, falling back to `Vector2.DOWN` if none (`aimed_attack_pattern.gd:21-27`).
- `bullet_damage = config.bullet_damage (8)` in both modes; `spawn_offset = Vector2(0.0, 10.0)` (`light_assault_ship.gd:44`).
- Bullet scene: same `enemy_bullet/enemy_bullet.tscn` as Interceptor. `BulletPool.pool_size = 20` (comment: "Arena diagonal 1047px / 420px/s / 0.3s interval ≈ 8.3 → 20 is comfortable," `light_assault_ship.gd:27-29`).
- No burst/spread/telegraph — one aimed (or forward) shot per interval.
- Contact/ram damage: 20.

#### 7. States / phases
`AIStateMachine` (only active when undriven by `EnemyPathMover`):
```
ApproachState ──(global_position.y >= hold_y)──▶ StrafeExitState ──(x past L/R edge ±60px)──▶ queue_free()
   descend Vector2(0,80)                             strafe Vector2(±120, 20) — random L/R dir
```
`AttackController` fires independently in both states, unaffected by the state machine.

#### 8. Collision & damage
- `HurtBox`: `collision_layer = 512`, `collision_mask = 65` as scene-authored (`light_assault_ship.tscn:82-84`), overwritten to `97|1024=1121` by `BaseEnemy._ready()` at runtime (same pattern as Interceptor).
- `HurtBox CollisionShape2D` scale `2.199998` over the same `CircleShape2D radius=13.0` (`light_assault_ship.tscn:88-90`) — matches body.
- `ContactHitBox`: `collision_layer=256`, `collision_mask=0`, `damage=20`, `damage_type=2` (CONTACT), shape scale `2.199998` over the same circle (`light_assault_ship.tscn:100-109`) — geometry-matched to body.
- No armour/shield mechanic; standard `HitFlashAnimationPlayer`/`HitEffect` reaction from `BaseEnemy`.

#### 9. Death & rewards
Standard `BaseEnemy._on_health_changed` path (explosion, `died` signal, `queue_free`). Score 25. `counts_toward_wave_clear`/`counts_as_escape` default `true`/`true` (not overridden in `fighter_config.tres`).

#### 10. Where it's used
By far the most-spawned enemy in `level_1_director.gd` — `b.fighter(` appears **62** times, in solo runs, `.v_formation()`, `.diagonal_formation()`, `.wedge_formation()`, `.u_sweep()`, `.arc()` paths, combined with `.shoot_forward()` / `.shoot_at_player()` and `.free_after()`. Representative examples:
- `level_1_director.gd:301`: `b.fighter().formation(b.v_formation(5)).at(-150, -400).move(b.straight(138)).delay(0.5).shoot_forward()`
- `level_1_director.gd:322`: `b.fighter().formation(b.v_formation(3)).at(260, -400).move(b.u_sweep(510, 730, 10)).delay(0.5).free_after(12).shoot_forward()`
- `level_1_director.gd:328-329`: symmetric side-entry pair with `.shoot_at_player().free_after(5.5)`
- `level_1_director.gd:336-337` (in `docs/enemy-roster.md`): escort pair flanking a `gunship` on arcing paths.
Also documented in `docs/enemy-roster.md:54-84` under `fighter` — Light Assault Ship.

#### 11. Tests
- `tests/integration/test_enemy_contact_damage.gd` includes `light_assault_ship` in its roster (lines 86-89), asserting `ContactHitBox.damage == config.collision_damage (20)`.
- `tests/integration/test_config_instance_isolation.gd` covers `FighterConfig` as part of its directory sweep.
- No dedicated `test_light_assault_ship*.gd` / `test_fighter*.gd` file found under `tests/`.

#### 12. Known issues
- No Light-Assault-Ship-specific entries in `docs/discovered-bugs.md`.
- `states/approach_state.gd:5-6` carries an explicit historical-bug comment: "This state previously fired bullets directly without the pool — that bug is now fixed," confirming firing now correctly routes through the shared `AttackController`/`BulletPool`.

#### 13. Open Space notes
- Both movement systems are screen/camera-relative: `EnemyPathMover`'s off-screen cull and `ApproachState`/`StrafeExitState`'s `cam.global_position` + `viewport_size` hold-line and edge-exit math (`approach_state.gd:17-20`, `strafe_exit_state.gd:17-24`) all assume a single scrolling `Camera2D` with a fixed autoscroll axis — none of this generalizes to free-flight without a redefinition of "hold line" and "off the edge" in open, non-scrolling space.
- `AimedAttackPattern`'s FORWARD mode reuses `ship.rotation` as a stand-in for "current travel direction" (`light_assault_ship.gd:29-31` comment), which only holds because `EnemyPathMover` keeps rotation synced to travel heading under Assault's convention (0=down); in Open Space this coupling would need to be made explicit/general rather than assumed.
- The random L/R strafe-exit direction and downward drift (`strafe_exit_state.gd:10-11,13-14`) are meaningless without a fixed "down"-is-forward-scroll orientation.

---

### Gunship

#### 1. Identity
- Folder: `assault/scenes/enemies/gunship/`
- Scene: `gunship.tscn` (root `Gunship`, `CharacterBody2D`, `gunship.tscn:56-57`)
- Script: `gunship.gd`, `class_name Gunship extends BaseEnemy` (`gunship.gd:1-2`)
- Config resource: `GunshipConfig` (`gunship_config.gd`, `class_name GunshipConfig extends ShipConfig`), instance `gunship_config.tres`
- Extends `BaseEnemy` -> `CharacterBody2D`

#### 2. Role
"Self-managed mini-boss" — drops in from the top, parks just below the top screen edge, tracks the player horizontally, and pours dual-barrel burst fire until nearly dead, then retreats upward rather than dying outright (`ENEMY.md:1-4`).

#### 3. Visuals
- Sprites: **two**, both plain `Sprite2D` (not `AnimatedSprite2D`) swapped in code, not via `AnimationPlayer`:
  - Full health: `res://assault/assets/sprites/enemies/heave_gunship.png` (`gunship.tscn:5,59-62`; preloaded as `_TEXTURE_FULL`, `gunship.gd:9`) — **92×84 px**. A large red-and-black saucer/turret hull viewed top-down: a glowing red dome/eye at center-front ringed by dark angular armor plates and turret nubs radiating outward — reads as a heavy stationary gun platform.
  - ≤50% HP: `res://assault/assets/sprites/enemies/heavy_gunship_non_shielded.png` (preloaded as `_TEXTURE_DAMAGED`, `gunship.gd:10`) — **92×84 px**, same silhouette/layout but the central dome is dark/cracked instead of glowing red — "shielded" (red, energized) vs "non_shielded" (dark, depleted) reading, i.e. the swap functions as a shield-down / cracked-core damage tell (`ENEMY.md:15,25`: "sprite cracks at half health").
  - The `yellow_shielded.png` / `yellow_unshielded.png` sprites (64×64 px each; a small blue-orange starfighter with an energy-shield dome in the "shielded" variant) are **not referenced anywhere in the repo** — confirmed via a full-repo grep for both filenames returning zero matches in any `.tscn`/`.gd`. They are unused/orphaned art, not used by Gunship or any other enemy currently.
- Scale: body `CollisionShape2D scale = Vector2(2.3077412, 2.3077412)` over `CircleShape2D radius=18.0` (`gunship.tscn:64-66`) → ~41.5 px effective radius — the largest of the five enemies in this batch.
- Rotation: `Sprite2D` node is scene-authored at `rotation = 3.1415927` (π, i.e. 180°) directly (`gunship.tscn:59-62`) — a static flip baked into the scene (not `BaseEnemy._rotate_sprite()`, which only targets `AnimatedSprite2D` and would not touch this `Sprite2D` anyway).
- Hit flash: same shared shader/AnimationPlayer pattern, 0.2s `"hit"` toggle (`gunship.tscn:10-14,34-48`).
- Texture swap trigger: `_on_health_changed_gunship()` (`gunship.gd:154-156`), a **separate** signal connection from `BaseEnemy`'s own `_on_health_changed` (both connected to `health.amount_changed`, comment at `gunship.gd:70`: "so we don't interfere with BaseEnemy's hit flash") — swaps `_sprite.texture` to `_TEXTURE_DAMAGED` once `current <= health.max_health/2`.

#### 4. Stats
- HP: `.tres` and scene agree at `max_health = 200` (`gunship_config.tres:7`; scene `Health` node also authors `max_health=200 current_health=200`, `gunship.tscn:79-83`), re-applied in `gunship.gd:36-37`.
- Contact damage: `collision_damage = 30` (`gunship_config.tres:8`) — **the specific regression `tests/integration/test_enemy_contact_damage.gd` was written for**: the scene's `ContactHitBox` defaults to `damage=20` (`gunship.tscn:92`), and `gunship.gd:50-51` explicitly re-applies `contact_hit_box.damage = config.collision_damage` to fix it (per the test file's header comment: "gunship rammed for 20 while its config said 30"). Effective runtime value: **30**.
- Score: `score_value = 200` (`gunship_config.tres:9`), propagated via the generic `BaseEnemy._ready()` config read.
- Bullet: `bullet_damage = 15` (`gunship_config.tres:10`), `bullet_speed = 260.0` (line 11).
- Movement: `entry_speed = 60.0` (line 12; retreat speed = `entry_speed * 1.5 = 90`), `hold_y_offset = 55.0` (line 13), `track_speed = 70.0` max (line 14), `track_player = true` (line 15).
- Burst timing: `burst_interval = 1.0` s between burst pairs (line 9), `burst_gap = 0.12` s between the left and right shot within a burst (line 10).
- `retreat_hp_ratio = 0.3` (line 16) — HP fraction that triggers RETREAT.
- `BulletPool.pool_size = 15` (`gunship.gd:60`).

#### 5. Movement
⚠️ **Self-managed `_physics_process` AI — must never receive `.move()`**, which would disable it via `EnemyPathMover`'s `set_physics_process(false)` (`ENEMY.md:23,82`, `gunship.gd:74-81`). Three-phase `Phase` enum (`ENTER, HOLD, RETREAT`, `gunship.gd:6`):
- **ENTER** (`_phase_enter`, `gunship.gd:84-91`): descends `velocity=Vector2(0, 60)` until `global_position.y >= _hold_y` (`_hold_y = cam.y - viewport.y*0.5 + 55`, computed once in `_ready()`, lines 53-56), then zeroes velocity, switches to HOLD, starts the burst `Timer`.
- **HOLD** (`_phase_hold`, lines 94-111): `velocity.y=0`; if `track_player`, steers `velocity.x = sign(diff) * min(|diff|*2.0, 70)` toward the nearest player (diff = player.x − self.x); fires bursts via the 1.0s `Timer`; when `current_health <= int(max_health*0.3)` (i.e. ≤60 HP), stops the timer and switches to RETREAT.
- **RETREAT** (`_phase_retreat`, lines 114-120): flies up at `velocity = Vector2(0, -90)` (`-entry_speed*1.5`), frees itself once `global_position.y < cam.y - viewport.y*0.5 - 50`.

#### 6. Attack
Dual-barrel burst fired by a child `Timer` (`wait_time=1.0`, `one_shot=false`, `gunship.gd:63-68`) calling `_fire_burst()`:
- `_fire_burst()` (lines 123-135): guarded by `_phase != HOLD or _firing` (no re-entrant bursts). Fires the **left barrel** at local offset `Vector2(-12.0, 8.0)`, `await get_tree().create_timer(_burst_gap /*0.12s*/).timeout`, checks `is_instance_valid(self)` and `_phase == HOLD` again (both bail out cleanly if the ship died or retreated mid-burst), then fires the **right barrel** at `Vector2(12.0, 8.0)`.
- `_shoot_from_barrel()` (lines 137-151): computes `direction` toward the nearest player from the barrel's world position (falls back to `Vector2.DOWN` if none), acquires a bullet from the pool, sets `HitBox.damage = 15`, `bullet.speed = 260.0`, `set_direction(direction)` — each shot is independently aimed from its own barrel position, so left/right barrels can diverge slightly.
- Bullet scene: same `enemy_bullet/enemy_bullet.tscn`.
- No spread/scatter (unlike Interceptor) — pure aimed shots, twice per `burst_interval`.
- Contact/ram damage: 30 (see Stats).

#### 7. States / phases
```
ENTER ──(y ≥ hold_y)──▶ HOLD ──(HP ≤ 0.3·max_health)──▶ RETREAT ──(y < top edge −50px)──▶ queue_free()
  descend @60px/s        track player X (≤70px/s),        fly up @90px/s
                          burst-fire every 1.0s
                          (L barrel, 0.12s gap, R barrel)
```
Implemented as an in-script `enum Phase` in `gunship.gd:6`, not separate `State` node files — no `states/` folder, matching `ENEMY.md:40`.

#### 8. Collision & damage
- `HurtBox`: `collision_layer=512`, `collision_mask=65` as scene-authored (`gunship.tscn:68-70`), overwritten to `97|1024` by `BaseEnemy._ready()` at runtime.
- `HurtBox CollisionShape2D` scale `2.289032` (note: slightly different from the body's `2.3077412`, `gunship.tscn:74-76`) over the same `CircleShape2D radius=18.0` — the hurtbox is marginally *smaller* than the body scale (2.289 vs 2.3077), though both still comfortably exceed the 1px-per-edge tolerance `test_enemy_hurtbox_geometry.gd` checks for at this radius (~0.16px shape-radius difference).
- `ContactHitBox`: `collision_layer=256`, `collision_mask=0`, scene-default `damage=20` but **overridden at runtime to 30** (`gunship.gd:50-51`, see Stats), `damage_type=2` (CONTACT), shape scale `2.3077412` matching the body exactly (`gunship.tscn:88-97`).
- No armour/shield deflection mechanic (despite the "shielded"-looking full-health sprite, there is no `is_armored()`-style query — armor visuals only, HP-gated texture swap).

#### 9. Death & rewards
If killed via damage (HP hits 0 during HOLD before retreat threshold triggers, or in ENTER/HOLD generally), standard `BaseEnemy._on_health_changed` explosion/`died`/`queue_free` path applies, score 200. If it survives to `retreat_hp_ratio` (30% HP, i.e. HP≤60), it instead flees off the top of the screen and `queue_free()`s itself in `_phase_retreat()` **without** going through `_on_health_changed`'s death branch — i.e. a successfully-retreated Gunship does *not* emit `died`/`was_killed=true`/award its score (inferred from code: `_phase_retreat`'s `queue_free()` is a direct call, not routed through `Health`).

#### 10. Where it's used
`b.gunship(` appears **4** times in `level_1_director.gd`:
- `level_1_director.gd:296`: `b.gunship().at(0, -500)` (commented "3.5 s — gunship test; self-managed AI, no .move() needed", line 294)
- Also referenced generically in the module doc comment `level_1_director.gd:6`: "Section 4 (Cloud Descent) — ENEMIES_CLEARED boss-area section with ally escort + gunship wave."
`docs/enemy-roster.md:290-337` documents it under "Heavy Gunship," including the explicit warning that spawn Y must be above the visible screen (design-unit `y < -360`) and the "covering fighters" pattern (gunship stationary, two fighters arcing in on either side using `.move()`).

#### 11. Tests
- `tests/integration/test_enemy_contact_damage.gd` — `gunship` roster entry (lines 71-74) plus a dedicated named test `test_gunship_rams_for_its_configured_collision_damage()` (lines 179-195) specifically pinning the fix for the "rams for 20 instead of 30" regression described in the file header and in `CLAUDE.md`'s testing section.
- `tests/integration/test_config_instance_isolation.gd` covers `GunshipConfig`.
- No dedicated `test_gunship*.gd` behavior file exists (the burst/phase/track logic is not directly unit-tested).

#### 12. Known issues
- `CLAUDE.md` (testing conventions section) documents the historical bug this enemy is famous for: "gunship rammed for 20 while its config said 30" — now fixed and pinned by `test_enemy_contact_damage.gd`.
- No `docs/discovered-bugs.md` entries specific to Gunship.
- `_fire_burst()`'s `await get_tree().create_timer(...)` mid-burst pattern (`gunship.gd:128`) is guarded against the ship being freed mid-await (`is_instance_valid(self)` check, line 129) — worth noting as a pattern other await-based enemy attacks should follow, but not itself a bug.

#### 13. Open Space notes
- The entire ENTER/HOLD/RETREAT state machine is defined in terms of `cam.global_position` and `viewport_size` (`gunship.gd:53-56, 117-119`) — "hold near the top edge," "retreat off the top edge" are Assault-autoscroll-specific framings that assume a single fixed camera-relative "top." In free-flight Open Space there is no "top of the screen" to park below or flee off of.
- Horizontal-only player tracking (`velocity.x` steered, `velocity.y` pinned to 0 during HOLD, `gunship.gd:94-107`) assumes the player always approaches from directly below along a vertical autoscroll axis; open space would need full-2D (or 3D) positioning logic.
- `_shoot_from_barrel`'s fallback `direction = Vector2.DOWN` when no player is found (`gunship.gd:139-142`) is the same Assault "down"-convention dependency seen in the other enemies.

---

### Ram Ship

#### 1. Identity
- Folder: `assault/scenes/enemies/ram_ship/`
- Scene: `ram_ship.tscn` (root `RamShip`, `CharacterBody2D`, `ram_ship.tscn:67-68`)
- Script: `ram_ship.gd`, `class_name RamShip extends BaseEnemy` (`ram_ship.gd:1-2`)
- Config resource: `RamShipConfig` (`ram_config.gd`, `class_name RamShipConfig extends ShipConfig`), instance `ram_config.tres`
- Extends `BaseEnemy` -> `CharacterBody2D`

#### 2. Role
"Armoured charger" — dives straight down with massive contact damage, effectively bullet-immune until a missile strips its armour, after which two bullets finish it off; also blocks the piercing laser while armoured (`ENEMY.md:1-4`).

#### 3. Visuals
- Sprite(s): **two**, swapped via a dynamically-built `SpriteFrames` on an `AnimatedSprite2D`:
  - Armoured: `res://assault/assets/sprites/enemies/ram_ship.png`, wired via a `SpriteFrames` sub-resource with one frame, `loop=false`, `speed=5.0` (`ram_ship.tscn:16-25,70-74`). **32×32 px** — a small, aggressive-looking red/maroon craft with a bull-like or ram-like angular front silhouette (bulky forward "horns"/prow shape narrowing to a tail), dark red body with darker shading; distinctly blockier/more compact than the fighters above.
  - Damaged (after first missile hit): `res://assault/assets/sprites/enemies/ram_ship_damaged.png`, **32×32 px**, same 32×32 canvas but the silhouette reads more battered/cracked — darker, more fragmented-looking wings/edges, still red-toned but duller — swapped in code via `_enter_damaged_state()` (`ram_ship.gd:34-42`): builds a brand-new one-frame `SpriteFrames` at runtime (`frames.add_frame("default", damaged_tex, 1.0)`) and reassigns `_sprite.sprite_frames`, rather than referencing a second pre-authored animation track.
- Scale: body `CollisionShape2D` has **no explicit scale** override (`ram_ship.tscn:76-77`, default `Vector2(1,1)`) over `CircleShape2D radius=36.0` — i.e. 36 px effective radius at native 32×32 texture size, the largest hitbox-to-texture ratio of the five (texture is smallest, hitbox radius is second-largest after Gunship).
- Rotation: `AnimatedSprite2D` — `BaseEnemy._rotate_sprite()` would flip it 180° via `rotation_degrees`, standard for this node type.
- Hit flash: standard shared shader pattern (`ram_ship.tscn:10-14,30-44`), played via `hit_flash_player.play("hit")` — but note `RamShip._on_received_damage()` (below) also explicitly calls `hit_flash_player.play("hit")` a second time on the armour-strip hit (`ram_ship.gd:36`), independent of `BaseEnemy`'s own flash-on-damage wiring (since the armour-strip hit is intercepted before `health.decrease()` runs, so `Health.amount_changed` never fires for it — the explicit `hit_flash_player.play("hit")` call is what makes that specific hit still flash).

#### 4. Stats
- HP: `.tres` `max_health = 999` (`ram_config.tres:8`) — described by `ENEMY.md:12` as "practically unkillable by bullets" while armoured. Applied in `ram_ship.gd:18-19`. Confirmed by test comment (`tests/integration/test_ram_ship.gd:5-8`) that this application was itself once a bug: "`ram_ship.gd` never applied `config.max_health` ... a config field a developer can read but the runtime never honours" — now fixed and pinned by `test_applies_config_max_health_on_ready`.
- After armour strips (`_enter_damaged_state()`, `ram_ship.gd:47-49`): HP is hard-reset to `max_health=100, current_health=100` regardless of config — "so two bullets finish it" (comment, matches `ENEMY.md:12` "resets to 100 after the first missile hit strips armour").
- Contact damage: `collision_damage = 50` (`ram_config.tres:9`), applied via `contact_hit_box.damage = config.collision_damage if config else 50` (`ram_ship.gd:22-24`) — the **actual runtime value is 50**, overriding the scene's `ContactHitBox damage=20` default (`ram_ship.tscn:102`).
- Score: `score_value = 35` (`ram_config.tres:10`), propagated generically.
- Speed: `movement_speed = 100.0` (`ram_config.tres:7`), applied to the local `speed` export in `ram_ship.gd:17` (`@export var speed: float = 100.0` on the script itself, `ram_ship.gd:6`, overwritten from config if present).

#### 5. Movement
Self-driven, straight-down charge, **not** delegated to `EnemyPathMover` in the script's own `_physics_process` (`ram_ship.gd:56-59`): `velocity = Vector2(0, speed); move_and_slide()` every physics frame, unconditionally (no phase/hold logic — it's a constant one-directional charge), plus `_check_off_screen()` (lines 61-67) which frees it once `global_position.y > cam.y + viewport.y*0.5 + 60`.
⚠️ **Documented inconsistency**: `ENEMY.md:23` explicitly flags that "The roster lists it as `EnemyPathMover`-driven via `.move()` (which would suspend this self-charge)" — i.e. the design docs (`docs/enemy-roster.md`) tell wave authors to attach `.move()`, but doing so would call `set_physics_process(false)` on the actor (`enemy_path_mover.gd:62`) and disable this exact `_physics_process`, silently replacing the ram's straight-down self-charge with whatever path was passed to `.move()`. Whether that is intentional (path overrides charge) or a latent authoring trap is not resolved in the code or docs (inferred — flagging as a discrepancy, not asserting which side is "correct").

#### 6. Attack
No projectiles at all — pure contact damage (50, see Stats). `ContactHitBox` is the only offensive component.

**Armour gimmick** (the enemy's signature mechanic):
- `hurt_box.collision_mask = 33` set in `_ready()` (`ram_ship.gd:21`) — binary 33 = 32|1, i.e. missiles (32) + layer 1 only; **bullets (64) are excluded**, overriding `BaseEnemy._ready()`'s own `hurt_box.collision_mask = 97|1024` assignment (RamShip's `_ready()` runs after `super._ready()` and reassigns the mask). Pinned by `test_hurtbox_mask_excludes_player_bullet_layer_while_armoured` (`tests/integration/test_ram_ship.gd:45-50`), which checks specifically against the player's primary bullet layer `64` (`bullet.tscn:44`).
- `_on_received_damage(damage)` is **overridden** from `BaseEnemy` (`ram_ship.gd:28-32`): while `not _damaged`, the *first* hit of any kind (necessarily a missile, since bullets can't reach the hurtbox yet) calls `_enter_damaged_state()` **instead of** dealing damage — the incoming `damage` value is discarded entirely on this first hit.
- `_enter_damaged_state()` (lines 34-49): sets `_damaged=true`, flashes, swaps sprite to the damaged texture, **opens** `hurt_box.collision_mask = 97` (bullets 64 + layer 1, no longer includes missile bit 32 or asteroid bit 1024 — narrower than `BaseEnemy`'s own post-`_ready()` mask of `97|1024`), and resets HP to 100/100.
- All subsequent hits (`_damaged == true`) call `health.decrease(damage)` normally (line 32) — pinned by `test_second_hit_after_armour_stripped_deals_damage` (100 HP − 30 damage → 70, `tests/integration/test_ram_ship.gd:63-70`).
- `is_laser_blocking()` (`ram_ship.gd:52-54`): returns `not _damaged` — true while armoured. Per `ENEMY.md:4,25`, this is read by the player's piercing-laser logic (via the `ram_ships` group, same pattern as `asteroids`, per the test file header) to make the armoured hull block a piercing shot until the armour is stripped.
- Contact/ram damage: 50 (constant, unaffected by armour state).

#### 7. States / phases
Two-state boolean flag (`_damaged: bool`), not a formal enum/state machine:
```
[ARMOURED] ──first received_damage (any source, necessarily missile — mask=33)──▶ [DAMAGED]
  hurt_box mask = 33 (missiles+layer1 only)         hurt_box mask = 97 (bullets+layer1)
  HP = 999, bullets pass through                     HP reset to 100/100
  is_laser_blocking() = true                          is_laser_blocking() = false
  contact damage 50                                   contact damage 50 (unchanged)
                                                        subsequent hits deal normal damage
```
Movement (straight-down charge) and off-screen despawn run independently of this state, unconditionally, the whole time.

#### 8. Collision & damage
- `HurtBox`: scene-authored `collision_layer=512`, `collision_mask=33` (`ram_ship.tscn:79-81`) — this scene-default already matches the script's own `_ready()`-time reassignment (`ram_ship.gd:21`), unlike the other four enemies where the scene value gets overwritten to something different by `BaseEnemy._ready()`. (Sequence: `BaseEnemy._ready()` sets `97|1024` first, then `RamShip._ready()`'s own body, running after `super._ready()`, immediately overwrites it back to 33.)
- `HurtBox CollisionShape2D`: no explicit scale (`ram_ship.tscn:85-86`), same `CircleShape2D radius=36.0` as the body — exact geometry match.
- `ContactHitBox`: `collision_layer=256`, `collision_mask=0`, scene-default `damage=20` overridden at runtime to **50**, `damage_type=2` (CONTACT), same unscaled `radius=36.0` shape as the body (`ram_ship.tscn:98-107`) — exact match, satisfying `test_contact_hitbox_geometry.gd`.
- Armour = a `HurtBox.collision_mask` toggle, not a "damage type" or armored-flag mechanic like the space station's `is_armored()` duck-type (mentioned in `CLAUDE.md`'s bullet-ownership convention) — RamShip's armour instead physically excludes the bullet collision layer from ever reaching the hurtbox at all, and separately exposes `is_laser_blocking()` for the piercing-laser's own group-based check.

#### 9. Death & rewards
- Joins group `"ram_ships"` in `_ready()` (`ram_ship.gd:14`) — **not** the generic `"enemies"` group every other enemy in this batch joins (Interceptor, Light Assault Ship, Gunship, Sniper Enemy all call `add_to_group("enemies")`; RamShip does not, per `ENEMY.md:26`: "Joins group `ram_ships` (not the standard contact-hitbox flow)" — though it still uses `BaseEnemy`'s standard `_on_health_changed` death path once damaged normally, since `_on_received_damage` is only overridden for the routing logic, not the death signal chain).
- On death (health reaching 0 post-armour-strip), standard `BaseEnemy._on_health_changed` explosion/`died`/`queue_free` applies. Score: 35.

#### 10. Where it's used
`b.ram(` appears **22** times in `level_1_director.gd` — heavy recurring use across many sections, both solo dives and multi-ship angled formations:
- `level_1_director.gd:334`: `b.ram().at(0, -400).move(b.straight(280))`
- `level_1_director.gd:628-629`: angled pair, `b.ram().at(-220,-400).move(b.straight(310, PI/10)).delay(0.4)` / mirrored `+PI/10` — converging-angle pairs
- `level_1_director.gd:754-756`: triple ram formation (two angled + one straight, staggered delays)
- `level_1_director.gd:785-786`, `879-880`, `901`, etc. — recurs through nearly every section of the level as a lane-blocking/forced-missile-target threat.
`docs/enemy-roster.md:123-146` documents it under `b.ram()`, listing straight dives, angled pairs from the sides, and surprise charges from below as the common patterns.

#### 11. Tests
- `tests/integration/test_ram_ship.gd` — the only enemy in this batch of five with a **dedicated** test file. 4 tests: `test_applies_config_max_health_on_ready` (intent — pins the max_health-application fix), `test_hurtbox_mask_excludes_player_bullet_layer_while_armoured` (characterization of the armour design), `test_first_hit_strips_armour_and_opens_hurtbox_to_bullets` (characterization — armour strip + HP reset to 100), `test_second_hit_after_armour_stripped_deals_damage` (characterization — 100−30=70 HP after strip).
- `tests/integration/test_enemy_contact_damage.gd` — `ram_ship` roster entry (lines 90-93), asserts `ContactHitBox.damage == 50`.
- `tests/integration/test_config_instance_isolation.gd` covers `RamShipConfig`.

#### 12. Known issues
- The `.move()`/self-charge conflict flagged in `ENEMY.md:23` (see Movement, section 5) is the standout open question for this enemy — not logged in `docs/discovered-bugs.md` but explicitly called out in the enemy's own doc as an unresolved discrepancy between the documented spawn pattern and the actual code behavior.
- No other TODO/FIXME comments found in `ram_ship.gd`/`ram_config.gd`.

#### 13. Open Space notes
- `_check_off_screen()` (`ram_ship.gd:61-67`) is purely camera/viewport-relative (60px below the bottom edge) — same Assault-scroll assumption as the rest of the roster; in Open Space "off screen" has no fixed meaning.
- The armour/laser-block mechanic (`is_laser_blocking()`, group `"ram_ships"`) is read by name/group elsewhere (per the test file's header note comparing it to `"asteroids"`) by Assault's own piercing-bullet logic (`bullet.gd`'s `is_armored()`-style duck-typing per `CLAUDE.md`) — this cross-file coupling to Assault-specific bullet-piercing code would need to be re-verified/re-implemented if Ram Ship's armour behavior is carried into Open Space's own projectile system.
- The unconditional straight-down `_physics_process` charge (`ram_ship.gd:56-59`) has no entry/telegraph/turn logic at all — moving it to free-flight would need an explicit "charge run-up" direction/target concept, since currently "down" is the only charge vector the code knows.

---

### Sniper Enemy

#### 1. Identity
- Folder: `assault/scenes/enemies/sniper_enemy/`
- Scene: `sniper_enemy.tscn` (root `SniperEnemy`, `CharacterBody2D`, `sniper_enemy.tscn:56-57`)
- Script: `sniper_enemy.gd`, `class_name SniperEnemy extends BaseEnemy` (`sniper_enemy.gd:2-3`)
- Config resource: **none** — `ENEMY.md:17` and the script confirm "there is no `sniper_enemy_config` resource; tuning lives as constants/exports in `sniper_enemy.gd`" directly (`shot_count` is the only `@export`; `AIM_DURATION`, `LOCK_DURATION`, `ROTATION_LERP`, `FLY_IN_TIME` are `const`).
- Extends `BaseEnemy` -> `CharacterBody2D`
- Not to be confused with the separate `sniper`/`sniper_skimmer.tscn` enemy documented earlier in `docs/enemy-roster.md` (builder `b.sniper()`) — that is a different, out-of-scope entity; this section covers `b.sniper_enemy()` / `sniper_enemy.tscn` only.

#### 2. Role
"Hovering marksman" — flies in, hovers, and fires a series of slow, heavily telegraphed aimed shots (converging red laser-sight) before retreating; carried entirely in and out by its movement path (`ENEMY.md:1-4`). The threat is about reading the telegraph and sidestepping, repeated `shot_count` times.

#### 3. Visuals
- Sprite: `res://assault/assets/sprites/enemies/sniper.png`, plain `Sprite2D` (`sniper_enemy.tscn:59-61`) — **64×64 px**. Description from the PNG: a sleek, narrow dark starfighter viewed top-down, nose-up orientation, with long thin swept wings/fins that taper to points and a small red/orange cockpit glow near the front — visually leaner and more angular than the Interceptor/Light Assault Ship, consistent with a "sniper" silhouette (long barrel-like body).
- `Muzzle` marker: a `Marker2D` child at local `position = Vector2(0, -20)` (`sniper_enemy.tscn:67-69`) — the firing point and the parent for the aim-visualizer line while charging.
- Scale: body `CollisionShape2D scale = Vector2(1.4400002, 1.4400002)` over `CircleShape2D radius=14.0` (`sniper_enemy.tscn:63-65`) → ~20.2 px effective radius.
- Rotation: uses plain `Sprite2D`, so `BaseEnemy._rotate_sprite()` does **not** affect it (same as Interceptor/Gunship). The ship's own `rotation` is instead actively driven every `_process()` frame by the sniper's own state logic (see Movement/Attack below) — `_ready()` sets `rotation = PI` immediately (nose-down toward the player, `sniper_enemy.gd:46`).
- Telegraph VFX: `SniperAimVisualizer` (`assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd`) — a shared script also used by the player's own sniper weapon. For this enemy it runs in **single-line mode** (`initial_angles` left empty, `sniper_enemy.gd:75-76`): draws one line from the muzzle straight ahead (`Vector2.UP * 600.0`, `sniper_aim_visualizer.gd:38-44`), colored dim red `Color(1.0,0.1,0.1,0.55)` width 1.0 while charging (`charge_fraction < 1.0`), switching to bright orange-red `Color(1.0,0.15,0.0,1.0)` width 2.0 once `charge_fraction >= 1.0` (locked) — i.e. the sight visibly brightens/thickens right before firing.
- Hit flash: standard shared shader pattern (`sniper_enemy.tscn:10-14,34-48`).
- No damaged/shield texture swap.

#### 4. Stats
- HP: **60**, read directly from the scene's `Health` node (`max_health=60 current_health=60`, `sniper_enemy.tscn:81-85`) — no config resource exists, so there is no `.tres`-vs-scene conflict for this enemy; the scene value is the only source (`ENEMY.md:12`).
- Contact damage: **20**, the `BaseEnemy`/scene default `ContactHitBox damage=20` (`sniper_enemy.tscn:94`), never overridden in `sniper_enemy.gd` (no config exists to read from) — confirmed by `test_enemy_contact_damage.gd`'s roster entry for `sniper_enemy` (`config: "", expected: 20`, lines 100-105), which notes it "inherit[s] `ShipConfig`'s default of 20 ... which happens to equal the base helper's hardcoded 20."
- Score: `score_value = 50`, hardcoded directly in `_ready()` (`sniper_enemy.gd:45`) — not read from any config.
- `shot_count = 5` (export default, `sniper_enemy.gd:30`), overridable per-spawn via `.prop("shot_count", N)`.
- Timing constants: `AIM_DURATION = 2.0` s, `LOCK_DURATION = 0.5` s, `ROTATION_LERP = 4.0`, `FLY_IN_TIME = 2.5` s (`sniper_enemy.gd:21-26`).
- Sniper bullet: `enemy_sniper_bullet.tscn` — `EnemyBullet` script, `speed = 1400.0` (much faster than the base `EnemyBullet` default of 250, `enemy_sniper_bullet.tscn:19`), `HitBox.damage = 25` (line 45), `HitBox.collision_mask = 128` (differs from the standard enemy bullet's mask, notable — see Collision section), `CapsuleShape2D radius=2.0 height=18.0` (a long thin capsule matching the "laser beam" visual, lines 13-15).

#### 5. Movement
Carried entirely by `EnemyPathMover` using a **sequence** movement (fly-in → hold → fly-out), per `ENEMY.md:23,78-79`: the approach step must be exactly `straight(speed, 0.0, 2.5)` to match the hardcoded `FLY_IN_TIME = 2.5` constant, and the hold step must cover `shot_count * 2.5` seconds minimum (5 shots → `hold(13.0)`; 3 shots → `hold(7.5)`).

Critically, the sniper's own state-machine logic runs in **`_process()`**, not `_physics_process()` (`sniper_enemy.gd:14-17,51`) — `EnemyPathMover` only disables the actor's `set_physics_process(false)` (`enemy_path_mover.gd:62`), so `SniperEnemy._process()` keeps running every frame regardless, and because Godot always runs `_process` after `_physics_process` within a frame, the sniper's own `rotation` assignment always overrides whatever `EnemyPathMover` set that frame (`sniper_enemy.gd:15-17` comment: "our rotation always wins"). This is a deliberate two-owner split: `EnemyPathMover` owns position, `SniperEnemy._process()` owns rotation.

#### 6. Attack
Spawns `enemy_sniper_bullet.tscn` from the `Muzzle` marker (`sniper_enemy.gd:32-33,100-113`). Full cycle: **AIM (2.0s) → LOCK (0.5s) → FIRE**, repeated until `shot_count` shots fired.
- **APPROACH** (`_phase_approach`, lines 61-68): holds `rotation = PI` (nose-down, overriding whatever `EnemyPathMover` would set) for `FLY_IN_TIME=2.5s`, then `_begin_aim()`.
- **AIM** (`_begin_aim`/`_phase_aim`, lines 72-86): instantiates a `SniperAimVisualizer` as a child of `_muzzle`; each frame, `_track_player()` lerp-rotates the ship toward the player at `ROTATION_LERP=4.0` (`rotation = lerp_angle(rotation, target_rot, delta*4.0)`, where `target_rot = atan2(dir.x, -dir.y)` so `Vector2.UP.rotated(target_rot)` points at the target, lines 119-127); visualizer charge `t = clamp(_timer/2.0, 0, 1)` updates every frame; after 2.0s → LOCK.
- **LOCK** (`_phase_lock`, lines 91-96): rotation frozen (no further `_track_player()` calls), visualizer held at `update_charge(1.0)` (bright/locked); after 0.5s → FIRE.
- **FIRE** (`_phase_fire`, lines 100-115): instantiates the bullet, connects `expired -> queue_free`, `set_direction(Vector2.UP.rotated(rotation))` (fires along current facing, which was frozen during LOCK), reparents to `get_parent()`, positions at `_muzzle.global_position`, frees the visualizer, increments `_shots_fired`; loops back to `_begin_aim()` if `_shots_fired < shot_count`, else → IDLE.
- **IDLE** (line 57): no-op; `EnemyPathMover`'s own exit/retreat step (authored in the wave's `sequence()`) carries the ship out.
- No spread/burst — one precisely aimed shot per AIM→LOCK→FIRE cycle, telegraphed by the visualizer for the full 2.5s (2.0 charging + 0.5 locked) before each shot.
- Contact/ram damage: 20 (base default, unmodified).

#### 7. States / phases
```
APPROACH ──FLY_IN_TIME (2.5s), rotation held at PI──▶ AIM ──2.0s, lerp-rotate + track, sight charges──▶ LOCK ──0.5s, rotation frozen, sight bright──▶ FIRE ──spawn bullet, shots_fired++──┐
     ▲                                                                                                                                                                                      │
     └──────────────────────────────────────────────────────── shots_fired < shot_count: loop back to AIM ─────────────────────────────────────────────────────────────────────────────┘
                                                                                                                       shots_fired == shot_count
                                                                                                                                 ▼
                                                                                                                               IDLE (EnemyPathMover's path exit step retreats the ship)
```
Implemented as in-script `enum Phase { APPROACH, AIM, LOCK, FIRE, IDLE }` (`sniper_enemy.gd:19`) — no `states/` folder, matches `ENEMY.md:42`.

#### 8. Collision & damage
- `HurtBox`: scene-authored `collision_layer=512`, `collision_mask=97` (`sniper_enemy.tscn:70-72`) — this already equals what `BaseEnemy._ready()` would set minus the 1024 (asteroid-contact) bit; `BaseEnemy._ready()` runs and overwrites it to `97|1024=1121` at runtime same as Interceptor/Light-Assault-Ship/Gunship.
- `HurtBox CollisionShape2D` scale `1.4505496` (`sniper_enemy.tscn:76-78`) vs body's `1.4400002` (`sniper_enemy.tscn:63-64`) — the hurtbox is marginally *larger* than the body here (opposite of Gunship, where it was smaller), both over the same `CircleShape2D radius=14.0`.
- `ContactHitBox`: `collision_layer=256`, `collision_mask=0`, `damage=20`, `damage_type=2` (CONTACT), shape scale `1.4400002` matching the body exactly (`sniper_enemy.tscn:90-99`).
- Sniper bullet's own `HitBox`: `collision_layer=256` (same as other enemy projectile hitboxes) but `collision_mask=128` — **different** from the base `enemy_bullet.tscn`'s hitbox mask (not directly compared here since `enemy_bullet.tscn` itself wasn't opened, but this is worth flagging as a distinct value on the sniper round specifically, `enemy_sniper_bullet.tscn:41-46`). `damage_type` defaults to `LASER` (0) since it's not set on this node (unlike the standard `HitBox` default of `LASER` too, so no explicit override here — just noting it is not `CONTACT`).
- No armour/shield mechanic.

#### 9. Death & rewards
Standard `BaseEnemy._on_health_changed` death path — explosion, `died` signal, `queue_free()`. Score: 50 (hardcoded, not config-driven). `counts_toward_wave_clear`/`counts_as_escape`: **not applicable via config propagation** — since `get("config")` returns null (no `config` property declared on `SniperEnemy` at all), `BaseEnemy._ready()`'s `if cfg is ShipConfig:` branch (`base_enemy.gd:64-68`) never runs for this enemy, so `score_value` is set purely by the explicit `score_value = 50` line in `sniper_enemy.gd:45`, and `counts_toward_wave_clear`/`counts_as_escape` stay at `BaseEnemy`'s own field defaults (`true`/`true`, `base_enemy.gd:18,21`) since nothing ever overrides them.

#### 10. Where it's used
`b.sniper_enemy(` appears **2** times in `level_1_director.gd`, both using the required `sequence()` movement pattern:
- `level_1_director.gd:270`: `b.sniper_enemy().at(-120, -500).move(b.sequence([...]))`
- `level_1_director.gd:275`: `b.sniper_enemy().at(120, -500).move(b.sequence([...]))`
  (a symmetric pair, part of the same section as the interceptor pair above).
`docs/enemy-roster.md:185-224` documents it under "Sniper Enemy (hovering)" with example 5-shot sequences (`hold(13.0)` matching `5*2.5`) for both spawn positions.

#### 11. Tests
- `tests/integration/test_enemy_contact_damage.gd` includes `sniper_enemy` with `config: ""` and `expected: 20` (lines 100-105) — the roster's only config-less entry alongside the general-default reasoning explained in the file header.
- No dedicated `test_sniper_enemy*.gd` file exists under `tests/` — its AIM/LOCK/FIRE cycle, telegraph timing, and rotation-ownership split are **not** directly unit/integration-tested (only the contact-damage invariant touches it).
- Not covered by `test_config_instance_isolation.gd` since it has no `config` resource to isolate.

#### 12. Known issues
- No entries in `docs/discovered-bugs.md` specific to Sniper Enemy.
- No TODO/FIXME comments found in `sniper_enemy.gd`.
- The `_process()`-vs-`_physics_process()` rotation-ownership trick (`sniper_enemy.gd:14-17`) is a fragile, order-dependent pattern the file itself flags with an explicit comment rather than a formal API contract — any future change to Godot's process-order guarantees or to `EnemyPathMover` would silently break it.

#### 13. Open Space notes
- The hardcoded `FLY_IN_TIME = 2.5` s **must match** the wave-authored `straight(speed, 0.0, 2.5)` step duration exactly (`ENEMY.md:23,78-79`) — a magic-number coupling between the script and every spawn call site. Open Space's free-flight spawning (if it doesn't use the same `sequence()`/`.move()` WaveBuilder idiom) would need this either parameterized or re-derived from the actual path, not left as a silently-desyncable constant.
- `_track_player()`'s `atan2(dir.x, -dir.y)` convention (`sniper_enemy.gd:126`) encodes "ship forward = `Vector2.UP` in local space, world down = positive Y" — standard 2D screen-space assumptions that would carry over fine to a 2D open-space mode but would need rethinking for any 3D free-flight variant.
- Retreat/exit entirely depends on the `EnemyPathMover`'s path-authored exit step (comment at `sniper_enemy.gd:57`, "EnemyPathMover's exit step drives retreat") — there is no self-contained "fly away" fallback in the sniper's own code at all, unlike Gunship's self-managed RETREAT phase; Open Space would need either a new path system providing the same exit-step concept or a self-managed retreat added directly to `SniperEnemy`.

---

## Part 4 — Boss: Space Station

### Space Station (mini-boss)

Level 1 mini-boss family, spawned in the `assault` gameplay mode. Source tree:
`assault/scenes/enemies/space_station/` — `space_station.gd`/`.tscn`, `space_station_config.gd`/`.tres`,
`station_turret.gd`/`.tscn`, `station_laser_phase.gd`, `station_gunnery.gd`, `station_reinforcements.gd`,
`station_death_sequence.gd`, `ENEMY.md`. Epic dossier: `docs/epics-done/station-mini-boss/{PRD,REPORT,SOURCES}.md`.
Plan/review trail: `docs/plans/station-mini-boss-destructible/`, `station-assault-section/`,
`station-laser-phase/`, `station-bullet-hell/`, `station-reinforcements/`, `station-death-handoff/`,
plus two later code-health plans, `should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/` and
`rockets-cannot-damage-the-space-station-s-turrets-they-deton/`.

**`laser_wall.png` / `laser_wall.tscn` do NOT belong to this boss.** `assault/scenes/hazards/laser_ray/laser_wall.tscn`
is a sibling hazard scene under the `laser_ray` folder (a separate red/black-striped static laser barrier), never
referenced by `space_station.tscn` or any station script. It is a distinct Level-1 hazard, not part of this
mini-boss's assets.

#### Identity

- **`SpaceStation`** (`space_station.gd`) — `class_name SpaceStation extends BaseEnemy` (so it extends `CharacterBody2D`
  via `BaseEnemy`, like all nine other assault enemies). Root node in `space_station.tscn` is a `CharacterBody2D`
  named `SpaceStation` (`collision_layer = 0`, `collision_mask = 0`). Owns only *lifetime*: health application, the
  armour rule (`is_armored()`), the death timer/`queue_free()`, and data accessors (`turrets()`, `live_turret_count()`).
  No gun, laser, reinforcement or death-spectacle logic lives on it — that is delegated to five sibling child nodes
  (composition over inheritance, per project `CLAUDE.md`).
- **`StationTurret`** (`station_turret.gd`, `station_turret.tscn`) — `class_name StationTurret extends Node2D` (NOT a
  `BaseEnemy`: it never moves, never scores, and must persist as visible wreckage after death). One of four, scene
  children under a `Turrets` `Node2D` in `space_station.tscn`, at local offsets `(-76,-76)`, `(76,-76)`, `(-76,76)`,
  `(76,76)` (`space_station.tscn:106-116`). Each turret has its own `Health`, `HurtBox` (`Area2D`,
  `hurtbox_component.gd`), and `Sprite2D`.
- **`StationLaserPhase`** (`station_laser_phase.gd`) — `class_name StationLaserPhase extends Node2D`, child node
  `LaserPhase`. Owns the entire phase-2 rotation/beam system.
- **`StationGunnery`** (`station_gunnery.gd`) — `class_name StationGunnery extends Node2D`, child node `Gunnery`.
  Owns all turret/core bullet fire in both phases, driving a `BulletPool` sibling via `node_paths=PackedStringArray("bullet_pool")`.
- **`StationReinforcements`** (`station_reinforcements.gd`) — `class_name StationReinforcements extends Node2D`,
  child node `Reinforcements`. Spawns squads of *existing* enemy ships (not new content) as siblings of the station.
- **`StationDeathSequence`** (`station_death_sequence.gd`) — `class_name StationDeathSequence extends Node2D`, child
  node `DeathSequence`. Spectacle-only; the station itself owns the actual `queue_free()`.
- **Config:** `SpaceStationConfig extends ShipConfig` (`space_station_config.gd`), resource file
  `space_station_config.tres`. `@export var config: SpaceStationConfig = load(".../space_station_config.tres")` on
  `SpaceStation`. Per-instance privatised via `ShipConfig.privatise()` from `BaseEnemy._init()`/`_enter_tree()`
  (`base_enemy.gd:26-45`), so every spawned station gets its own duplicate — the shared `load()`d object must never
  be written to.
- **Scene assembly** (`space_station.tscn`, 6 top-level behaviour/data nodes under `SpaceStation`): `Sprite2D`,
  `CollisionShape2D` (240×240 `RectangleShape2D`), `HurtBox` (`Area2D`, layer 512 / mask 1121), `Health`,
  `HitFlashAnimationPlayer`, `ContactHitBox` (`Area2D`, layer 256), `Turrets` (4× `StationTurret` instances),
  `LaserPhase`, `BulletPool` (`pool_size = 48`, must stay a **direct child** of `SpaceStation` — see Collision &
  damage), `Gunnery`, `Reinforcements`, `DeathSequence`.
- **How turrets "attach" to the core:** purely scene hierarchy — plain scene children under `Turrets`, not attached
  via any script-level docking/joint mechanism. `SpaceStation._turrets()` reads `turret_root.get_children()` live on
  every call (no cached array, no counter — so the count "cannot desync", `space_station.gd:135-152`).

#### Role and intended fight design

From `ENEMY.md`/`PRD.md`: "A fortress, not a ship." Two-phase cores-and-turrets mini-boss on a 256×256 hull. Four
turrets, each on its own HP bar; **the core refuses all damage until the last turret dies.** Every live turret fires
an aimed 3-bullet fan, so "the armour is also the threat" — each gun killed visibly quietens the station (6.7
bullets/s at full strength down to 1.7 with one gun left). Shooting the hull sparks and does nothing — teaches "kill
the guns first" with zero UI. Killing the last turret "wakes the superweapon up": the hull starts rotating, fires
telegraphed sweeping beams, and throws precessing bullet rings from the exposed core — "the second half is fought on
the move." Intended fight length: 30–60 s (the 180 s section timeout is a safety net, not a pacing target). Player
never picks a comfortable spot: reinforcement squads cross the arena from all four edges during phase 1.

**Assault section lead-in:** Level 1 runs Deep Space → Asteroid Belt → **Space Station** → Planet Approach → Cloud
Descent. The station sits between the asteroid belt and the planet approach as a wall the player "cannot skip"
(`LevelSection.EndCondition.ENEMIES_CLEARED`).

#### Visuals

All three sprites were personally opened and inspected with the Read tool:

- **`station_core.png`** (`assault/assets/sprites/enemies/station_core.png`, 256×256, authored at final on-screen
  pixel size, `scale = 1`). Strict top-down/orthographic view (no perspective, per project convention). Silhouette:
  a square/diamond hull — four grey rectangular "shoulder" armor blocks at the corners (each with an X-shaped
  crosshatch rivet pattern), connected by four thin **red** bars/struts forming a plus/cross through the middle, and
  a large circular mechanical core in the centre with concentric grey rings, small bolt/rivet details, a
  darker inner ring, and a small bright orange-red glowing dot/eye at the very centre (the "reactor" — the
  vulnerable core once turrets die). Palette: cool greys/blue-greys for the hull plating, red accent stripes, warm
  orange-red for the core glow. Ships with a transparent background (previously shipped fully opaque at 65536/65536
  px alpha 1.0 — see *Known issues* below; now flood-fill keyed to 47.63% opaque).
- **`station_turret.png`** (`assault/assets/sprites/enemies/station_turret.png`, 64×64, player-fighter-sized). Strict
  top-down view: a rounded/circular grey turret base with a darker circular gun-mount ring, a single stubby cannon
  barrel (dark, roughly vertical/pointing toward local −Y i.e. screen-top in the resting sprite) with a small red
  warning/vent light near its base, and a faint blue engine-glow accent at the rear. Reads as a compact gun
  emplacement, silhouette closer to circular/round than square. 54.71% opaque.
- **`station_turret_destroyed.png`** (`assault/assets/sprites/enemies/station_turret_destroyed.png`, 64×64,
  `create_object_state`-derived from the intact turret so footprint/palette match). Same circular base silhouette
  but rendered charred/burnt — muted dark blue-grey/near-black tones throughout, no red warning light, no barrel
  standing upright (the cannon reads as slumped/destroyed), an ashen, scorched look consistent with "wreckage that
  stays visible."
- **Animations:** no `AnimatedSprite2D`/frame animation anywhere in this family — sprites are static `Sprite2D`
  textures. The only "animation" is `HitFlashAnimationPlayer` (`space_station.tscn`) with a two-clip
  `AnimationLibrary`: `RESET` (0.001 s, flash off) and `hit` (0.2 s, toggles `Sprite2D:material:shader_parameter/enabled`
  true→false via `hit_flash_vs.tres`, a `ShaderMaterial` set `resource_local_to_scene = true`). Turrets use the same
  hit-flash idiom implicitly via `HitEffect` bursts, not a dedicated `AnimationPlayer`.
- **Destroyed/damaged states:** the core has **no distinct damaged sprite** — only the turret has a swapped texture
  (`_TEXTURE_DESTROYED` in `station_turret.gd:15,67`) on death. There is no intermediate "damaged" hull texture for
  the core; visual damage feedback for the core comes entirely from the hit-flash animation and `HitEffect` sparks
  per hit, plus the death sequence's darkening tint at the very end.
- **VFX:** `HitEffect` (spark burst) on every non-lethal hit (both core and turret, `base_enemy.gd:54-58`,
  `station_turret.gd:22,37,54-57`). `ExplosionEffect` on each turret's death (`station_turret.gd:79-91`) and on the
  station's own multi-stage death chain (see Death & rewards). No muzzle-flash sprite for turret/core gunfire — bullets
  are plain `enemy_bullet.tscn` instances from the pool.
- **Laser visuals:** the laser phase spawns **no new art** — it reuses `assault/scenes/hazards/laser_ray/laser_ray.tscn`'s
  existing warning-line → charge-up → active-beam → dissolve frames (`ENEMY.md:757-759`). No station-specific laser
  sprite exists.

#### Stats

| Property | Value | Source |
|---|---|---|
| Core HP (`max_health`) | 600 | `space_station_config.tres:7`; also authored 600/600 directly on the scene's `Health` node (`space_station.tscn:87-88`) |
| Turret HP (`turret_health`) | 120 each × 4 | `space_station_config.tres:11`; scene `Health` nodes also author 120/120 (`station_turret.tscn:29-30`) |
| Contact damage (`collision_damage`) | 40 | `space_station_config.tres:8`; `ContactHitBox` scene-authored default is 20 (`space_station.tscn:98`) but is overwritten |
| Turret bullet damage | 12/bullet | `turret_bullet_damage`, `.tres:20` |
| Core ring bullet damage | 10/bullet | `core_bullet_damage`, `.tres:25` |
| Score (core, on death) | 1000 | `score_value`, `.tres:9`; **turrets award nothing** (no payout path exists — `ENEMY.md:606-612`) |
| Turret fire interval | 1.8 s | `.tres:17`. 4 turrets × 3 bullets / 1.8 s = 6.7 bullets/s full strength, 1.7/s with one turret left |
| Turret burst | 3 bullets, 0.35 rad (~20°) arc | `.tres:18-19` |
| Turret bullet speed | 240 px/s | `.tres:21` (60% of player's 400 px/s top speed) |
| Core ring interval | 2.0 s | `.tres:22`; 10 bullets/ring, 36° spacing, step 0.24 rad (golden-angle derived) |
| Core bullet speed | 210 px/s | `.tres:26` |
| Laser warn duration | 1.4 s | `.tres:12` (time-to-lethal ≈ 1.9–2.0 s once `LaserRay`'s own 0.56 s charge-up is counted) |
| Laser active duration | 2.0 s | `.tres:13` |
| Laser volley interval | 6.5 s | `.tres:14` |
| Laser rotation speed | 0.5 rad/s (~29°/s) | `.tres:15` |
| Laser beam count | 2 opposed | `.tres:16` |
| Reinforcement first delay / interval / cap | 8.0 s / 10.0 s / 4 alive | `.tres:27-29` |
| Death sequence duration | 1.8 s (script default `0.0`) | `.tres:30`; `space_station.gd:62` |
| Death blast count | 7 (script default 3) | `.tres:31` |

**Which value wins at runtime:** the `.tres` wins over scene-authored `Health` node values. `SpaceStation._ready()`
(`space_station.gd:108-125`) explicitly overwrites `health.max_health`/`health.current_health` and every turret's
`Health` from `config` if `config` is non-null (config is non-null by default since it's `load()`ed at declare time).
Pinned by `test_config_max_health_wins_over_scene_health_node` and `test_config_turret_health_is_applied_to_every_turret`.
Likewise `ContactHitBox.damage` (scene default 20) is re-applied to `config.collision_damage` (40) after
`super._ready()`. All per-phase timing/behaviour fields (laser, gunnery, reinforcements, death) are **read exactly
once** by each sibling node's own `_ready()` and copied into that node's own fields — nothing re-reads `config`
afterward. Each node's own script-default fields are a deliberately *different*, more conservative fallback (used
only if `config` were null), which is what stops the config test from passing vacuously (e.g. gunnery script default
`turret_fire_interval = 3.0` vs shipped `1.8`).

#### Movement

- **Entry:** the station's wave entry has **no `.move()`** (`level_1_director.gd:241`,
  `b.wave(0.0, [ b.space_station().at(0, -90) ])`). Because `WaveManager` only attaches an `EnemyPathMover` for a real
  `MovementResource`, the station gets none — it spawns and **stays put**. `at(0, -90)` is a design-unit offset (640×360
  space) scaled by `ArenaCamera.WORLD_SCALE` (2.0) at spawn, landing the hull at world (640, 180), spanning world y
  52–308.
- **In-fight movement:** none during phase 1 — the station is entirely stationary. During phase 2 the hull **rotates
  in place** at `laser_rotation_speed` (0.5 rad/s, constant angular velocity, no easing) via
  `StationLaserPhase._physics_process` writing `_station.rotation += rotation_speed * delta`
  (`station_laser_phase.gd:121-124`). Nothing ever writes station `position` — it is a fixed point on the arena for
  the entire fight.
- **Turret rotation/tracking:** turrets themselves never rotate on their own — they are plain, static `Node2D`s. The
  barrel orientation is **snapped, not tracked/tweened**: immediately before firing a volley,
  `StationGunnery.fire_turret_volley()` sets `t.global_rotation = dir.angle() + PI/2.0` for each live turret
  (`station_gunnery.gd:194-204`), aiming at the player at that instant. `global_rotation` (not `rotation`) is used so
  the aim survives the hull's own spin during phase 2. **Nothing updates rotation between volleys** — turrets hold
  their last-fired aim (or the authored `rotation = 0` resting pose) until the next volley, and during phase 2 the
  turret *wrecks* passively spin with the rotating hull.

#### Attack

**Phase 1 — turret fans (`StationGunnery`):**
- Every **live** turret fires a `turret_burst_count`-bullet (3) fan of angular width `turret_burst_arc` (0.35 rad,
  ~20°), centred on the player, all on one shared `turret_fire_interval` (1.8 s) cadence —
  `fire_turret_volley()` (`station_gunnery.gd:194-204`), driven by `RadialAttackPattern` with `aim_at_player = true`.
  `_live_turrets()` re-reads live turret state per volley, so a destroyed gun drops out for free.
  **Full strength:** 4 turrets × 3 bullets / 1.8 s = 6.7 bullets/s. **One turret left:** 1.7 bullets/s.
- **First volley lands one full `turret_fire_interval` after spawn** (never on spawn) — falls out of `Timer.start()`,
  no dedicated config field; this is the player's grace period.
- Bullet damage 12, speed 240 px/s, spawn radius = turret hurtbox rim (26 px, `turret_spawn_radius`).
- **Deterministic, never `randf()`** — `test_volleys_are_deterministic` fails if RNG is introduced.
- A forced volley call in the wrong phase fires nothing: `fire_turret_volley()` early-returns once `is_core_firing()`.

**Phase 2 — core rings (`StationGunnery`, triggered by `armor_broken`):**
- Turret cadence stops; `core_ring_interval` (2.0 s) full rings of `core_ring_count` (10) bullets fire from the hull
  rim (`core_spawn_radius = 130.0`, outside the 240×240 hull), via `RadialAttackPattern` with `arc = TAU`,
  `aim_at_player = false`.
- Each ring's base angle **precesses** by `core_ring_step` (0.24 rad) from the last ring — derived from the golden
  angle (`spacing × 0.381966`, ratio 2.618) specifically to avoid a permanent safe radial lane. The originally-planned
  value 0.21 was caught at review as producing a 3-lane collapse with a 31.8% max gap; 0.24 leaves only 9.0%.
  `test_the_ring_step_leaves_no_permanent_safe_lane` rejects anything above a 25% max-gap bound.
- **First ring lands one `core_ring_interval` (2.0 s) after `armor_broken`**, deliberately not immediately, because
  `StationLaserPhase` already fires a beam volley on the same frame the armour breaks.
- Bullet damage 10 (softer than turret fan — position alone can't dodge a full ring), speed 210 px/s (slowest of the
  three attack types, since phase 2 already has beams to dodge).

**Laser phase (`StationLaserPhase`, triggered by `armor_broken`):**
- **Trigger:** connects to `SpaceStation.armor_broken`, latched (`_armor_broken`) so it fires exactly once.
- **Telegraph:** each `LaserRay` beam warns `laser_warn_duration` = 1.4 s, then a ~0.56 s charge-up
  (`LaserRay`'s own internal `laser_increase`), for a measured **~1.9–2.0 s total time-to-lethal** — ~6× the 0.3 s
  human-reaction floor, deliberately shorter than Level 1's static laser columns (3.0 s), which wouldn't fit twice
  inside one 6.5 s volley cycle.
- **Active/lethal window:** `laser_active_duration` = 2.0 s.
- **Volley cadence:** `laser_volley_interval` = 6.5 s, start-to-start; must exceed full beam lifetime (warn + 0.56
  charge + 2.0 active + ~0.84 dissolve ≈ 4.8 s), leaving ~1.7 s of clear screen between volleys.
- **First volley fires immediately on `armor_broken`** (not after a full interval — waiting would read as "the boss
  stopped").
- **Sweep:** each volley spawns `laser_beam_count` (2) beams at local angles `_VOLLEY_ANGLES[k % 4] + i*TAU/beam_count`,
  where `_VOLLEY_ANGLES = [0, PI/2, PI/4, 3PI/4]` — a fixed, cycled (never `randf()`) list, deliberately including two
  diagonal indices so a beam-angle off-by-one can't silently disarm the self-damage regression test. Since the hull
  is simultaneously rotating at 0.5 rad/s, every volley's *world* angle differs even off a fixed local list.
- **Emitter radius:** 140 px from station centre (`emitter_radius`, scene geometry, not config).
- **Sweeping mechanic:** rotating the whole station (`_station.rotation += rotation_speed * delta`) sweeps every live
  beam for free — beams are children of `LaserPhase`, a child of the station, so there's no per-beam rotation code.
- **Self-damage guard:** `LaserRay`'s default hit mask (`128|256|512`) would hit the station's own core `HurtBox`
  (layer 512, kept live) — a beam on default mask kills the station 600→0 HP in one frame. Every beam this node
  spawns sets `laser.hit_mask_override = 128` (player hurtbox only) **before** `add_child()`. Reproduced empirically,
  not theorised — see the load-bearing test note below.

#### States / phases

Text state diagram:

```
[SPAWN]
   │  station at world (640,180), stationary, armored=true (4/4 turrets alive)
   │
   ├─► [PHASE 1: Turrets Up]  (StationGunnery: turret fans @1.8s; StationReinforcements: squads @8s→10s, cap 4)
   │      per-turret: alive ──(HP→0)──► destroyed (sprite swap, hurtbox closed, wreckage stays in tree,
   │                                     `destroyed` signal emitted, `ExplosionEffect`)
   │      core: HurtBox live but `_on_received_damage` always deflects while is_armored()==true
   │             (any turret alive) → emits `armor_deflected(damage)`, hit-flash, NO HP loss
   │      when live_turret_count() hits 0 → SpaceStation emits `armor_broken` (latched, fires once)
   │
   ├─► [PHASE 2: Armor Broken]  (triggered by `armor_broken`)
   │      - StationReinforcements: _stop() — no more squads
   │      - StationGunnery: turret timer stops; core ring timer starts (first ring @ +2.0s)
   │      - StationLaserPhase: _active=true; hull begins rotating @0.5 rad/s; first beam volley fires
   │                            immediately, then every 6.5s
   │      - core: `_on_received_damage` now falls through to BaseEnemy — takes real damage
   │
   ├─► [DYING]  (core Health hits 0, `_dying` latch set exactly once)
   │      SpaceStation._on_health_changed(0): was_killed=true, `died` emitted, corpse made harmless
   │      (HurtBox.monitoring=false deferred; ContactHitBox.collision_layer=0 deferred),
   │      `death_started` emitted
   │        │
   │        ├── StationGunnery (on `died`): stop both timers, bullet_pool.cancel_active()
   │        ├── StationLaserPhase (on `died`): stop rotation/volleys, dissolve/free live beams
   │        ├── StationReinforcements (on `died`): _stop() (backstop; already stopped at armor_broken)
   │        └── StationDeathSequence (on `death_started`): 7 blasts over 1.8s at deterministic
   │             hull-local offsets (opposite sides alternating), decaying spin (1.2 rad/s→0),
   │             modulate lerped to burnt_tint, camera shake 0.25/blast; final central blast +
   │             1.0 shake at `_finish()`
   │      if death_duration <= 0 → _finish_death() immediately (identical to plain BaseEnemy)
   │      else → `_death_timer` (1.8s) → _finish_death()
   │
   └─► [FREED]
          _finish_death(): final ExplosionEffect burst, queue_free() — station leaves
          enemy_container → LevelSection.ENEMIES_CLEARED sees an empty container → advances
          to `planet_approach`
```

Note: the last-turret-dies transition and the "as turrets die" behaviour is exactly the phase-1→phase-2 armour rule
above — there is no separate machine per turret; each turret has its own trivial alive/destroyed binary state
(`StationTurret._alive`), and the station-level phase only changes once the **count** hits zero.

#### Collision & damage

**The armour/deflection mechanic (`is_armored()`):**
`SpaceStation.is_armored()` returns `live_turret_count() > 0` (`space_station.gd:147-156`), read live from the
`Turrets` node's children every call — no cache, cannot desync. The core's `HurtBox` **stays fully live and
monitoring** the whole fight; armour is enforced as a damage *rule*, not a disabled hurtbox:
`_on_received_damage(damage)` override (`space_station.gd:171-176`) — while armored, emits `armor_deflected(damage)`
+ plays the hit-flash animation, and **returns without touching `Health` at all**; once unarmored it falls through to
`super._on_received_damage(damage)` (normal `BaseEnemy` damage). This is deliberate, documented in `CLAUDE.md` and
`ENEMY.md`: two shipped systems bypass physics entirely and drive damage straight into `received_damage.emit(...)` —
`plasma_nova_module.gd:39-41` and `beam_behavior.gd:75-76,99-102` (mining laser) — both of which iterate group
`"enemies"`, so a disabled hurtbox would silently leak both weapons straight past the armour.

**Bullet ownership & pierce-through-deflection (project-wide convention, load-bearing here):** a default player
bullet does **not** stop on a deflected hit. `bullet.gd::_hit_is_deflected()` duck-types a check for
`area.get_parent().has_method("is_armored") and is_armored() == true` on the hit target; if true, the bullet
continues flying with no `expired` emit, no free, and no pierce charge spent. This is the **only** mechanism that
makes the turrets (and the station) killable at all — without it, every shot aimed at a turret would be consumed by
the core's armoured hurtbox before reaching the turret behind it. `homing_missile.gd` and `warhead_missile.gd` read
the identical `is_armored()`-shaped query before `queue_free()`-ing themselves, so rockets get the same pass-through.

**Hurtboxes / layers / masks:**

| Node | Layer | Mask | Notes |
|---|---|---|---|
| `SpaceStation` root (`CharacterBody2D`) | **0** | **0** | Deliberate. At the default layer 1, `beam_behavior.gd`'s mining-laser raycast (`_RAY_BLOCK_MASK = 1\|1024`) would truncate at the hull edge and make the station immune to the player's mining laser, and also block player collision with a 256×256 body. Contact damage still works — it comes from the separately-layered `ContactHitBox`. |
| `HurtBox` (core, `Area2D`) | 512 | 1121 (`97\|1024`) | Layer is scene-authored (`space_station.tscn:76`); `BaseEnemy._ready()` sets only the *mask*, never the layer. Mask = bullets(64)+rockets(32)+layer1+asteroids(1024). |
| `StationTurret/HurtBox` | 512 | 1121 | Set explicitly in `station_turret.gd::_ready()` (a plain `Node2D` has nothing else setting it). |
| `ContactHitBox` (core) | 256 | 0 | `damage` re-applied from `config.collision_damage` (40) in `_ready()`, overriding the scene-authored default of 20. |

Copying the gunship's raw `collision_mask = 65` would have been wrong — it omits bit 6 (32, rockets), letting the
player's homing/warhead missiles pass straight through.

**Core hurtbox spans the whole hull (240×240), not just the visible core.** Shares the same `RectangleShape2D_ss`
sub-resource as the station's body collider (`space_station.tscn:22-23,71-72,80-81`). A proposal to narrow it to an
88×240 central strip (so it wouldn't overlap the turrets' x-extent `[50,102]`) was **formally rejected** — full
reasoning in `docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/`:
- No real benefit: a bullet already survives the deflection and hits the turret behind it in the same pass (see
  pierce-through above), so narrowing only removes one redundant hull-flash.
- Real cost: 64 of 256 px (25%) of visible width would swallow shots and report *nothing at all* (not even a
  deflect); in phase 2, once turret hurtboxes close on death, only 88/256=34% of the visible width would remain
  live, 66% dead, at the exact moment the fight has told the player the core is open.
- Enforced by `tests/integration/test_enemy_hurtbox_geometry.gd::test_the_88x240_proposal_fails_this_sweep`, which
  applies the exact rejected shape to a live station instance and asserts it fails — a permanent gate, not prose.
- Project-wide rule this establishes: "an enemy's `HurtBox` covers the body collider the player collides with.
  Armour is a damage rule on a full-size hurtbox, never an absent hurtbox."

**Pierce interaction / turret-behind-core reach — verified by real physics** (not just logic):
`test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core` fires a real
`bullet.tscn` up the `x=76` turret lane; it crosses the core rect (bottom edge y=+120), deflects for 0 damage
(`armor_deflected` fires), survives, and lands full 50 damage on the turret at y=+102. A second test proves the
inverse (core damage once armour is broken). `test_station_incoming_damage_paths.gd` closes the same path for
**rockets** (`homing_missile`, `warhead_missile` — same deflect-and-continue behaviour) and for **asteroids**
(layer/mask 1024 contact). A boundary test, `test_a_station_on_the_default_body_layer_would_block_its_own_fight`,
sets the root to the default layer 1 on a live instance and proves the mining laser then stops dead at the hull edge
— confirming the layer-0 root rule is load-bearing, not cosmetic.

**Note (open code-health item, not yet fixed):** the project's own backlog flags that a *default* player bullet is
"effectively infinitely piercing" against stacked hurtboxes in general (it doesn't die on first overlap at all,
independent of armour) — filed as `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`. The station's
armour design explicitly depends on this remaining true; if a future change makes bullets die on first hurtbox
overlap, the turrets (and the boss) become unkillable unless the deflection exemption in `bullet.gd::_hit_is_deflected()`
is preserved.

#### Death & rewards

- **Ownership split (deliberate):** `SpaceStation` owns the *timer and the actual `queue_free()`* — never
  `StationDeathSequence`. If the visual node were renamed/removed and tried to own the free, a station without it
  would never leave `enemy_container` and `station_assault` would hang for the full 180 s timeout with no error.
- **Sequence:** on core `Health` reaching 0, `_dying` latches (guards against `Health.set_health()`'s
  unconditional re-emit on repeated 0-damage hits), `was_killed = true`, `died` signal emitted (scoring hook — see
  below), corpse made harmless (`hurt_box.monitoring = false` deferred, `ContactHitBox.collision_layer = 0`
  deferred), then `death_started` emitted. If `death_duration <= 0` (no config), the station frees itself the same
  frame — identical to any other `BaseEnemy`. Shipped config value 1.8 s: the wreck stays in the tree, visibly
  exploding, camera shaking, hull spinning down and darkening, before the final `_finish_death()` frees it.
- **Blast chain:** 7 explosions (`death_blast_count`) roll across the hull over 1.8 s at deterministic hull-local
  offsets from a fixed 8-direction table cycled by index (never random), consecutive blasts on opposite sides so it
  reads as disintegration rather than a spinner. `blast_spread_radius = 96` px. `blast_particle_amount = 18` per
  blast (below `ExplosionEffect`'s default 22 so the finale stays the biggest thing on screen). Camera shake 0.25 per
  chain blast (deliberately near-invisible — decays before it can accumulate) + 1.0 on the final central blast (the
  project's reserved "boss death" shake value). Hull drifts with decaying spin (`death_spin = 1.2 rad/s → 0` linear)
  and darkens toward `burnt_tint = Color(0.35,0.32,0.30,1.0)`.
- **Scoring:** core awards `score_value = 1000` through the normal `BaseEnemy.died` path
  (`ScoreTracker` connects to `died` for kills, `tree_exited` + `was_killed` discrimination for escapes — deferring
  either past HP-hit-0 would misscore the boss as an *escape* and apply the 0.75× combo penalty, which is exactly why
  only `queue_free()` moved and `died`/`was_killed` still fire at the true HP=0 instant). **Turrets award zero
  points** — there is no payout path (`ScoreTracker` only registers via `WaveManager.enemy_spawned` + `BaseEnemy.died`,
  and a turret is a `Node2D` that's never spawned through `WaveManager` and never leaves the tree).
- **Signals:** `armor_deflected(damage: int)` (feedback hook, every armoured hit), `armor_broken` (zero-arg, fires
  exactly once, the phase-transition hook every sibling node listens on), `death_started` (zero-arg, separate from
  `died` — `died` means "stop doing things", `death_started` means "begin the spectacle"), `died` (inherited from
  `BaseEnemy`, zero-arg).
- **Mission completion hook:** none bespoke. `LevelSection.ENEMIES_CLEARED` polls `wave_manager.enemy_container`'s
  child count (`level_director.gd:116`) — the station holding itself in the tree for `death_duration` while dying
  holds the section open "for free"; the section only advances once the wreck (and its blast particles, which are
  parented to the station, not to `DeathSequence`) fully leaves the container.

#### Where it's used

Spawned by exactly one place: `station_assault`, the **third of five** sections of Level 1
(`assault/scenes/levels/edelia/1/level_1_director.gd::_build_station_assault()`, lines 230-244):
```
s.section_name = &"station_assault"
s.end_condition = LevelSection.EndCondition.ENEMIES_CLEARED
s.enemies_cleared_timeout = 180.0   # vs. the 10.0 s default used elsewhere
b.wave(0.0, [ b.space_station().at(0, -90) ])
```
Spawn method: `WaveBuilder.space_station()` (`assault/scenes/systems/wave_builder.gd:93`, constant
`SPACE_STATION = "res://assault/scenes/enemies/space_station/space_station.tscn"` at line 245).

Three load-bearing details of this spawn call, documented in both the director's comments and `ENEMY.md`:
- **No `.delay()`** — `waves_complete` fires when the wave *triggers*, not when spawns land; a delay would let
  `_wait_enemies_cleared()` see an empty container and advance instantly.
- **No `.move()`** — a `MovementResource` would attach an `EnemyPathMover` and could fly the boss off-screen
  mid-fight (and free it via screen-exit).
- **180 s `enemies_cleared_timeout`** is a safety net (G-Darius's cited boss-timer floor), not a balance number; if
  it expires, `LevelDirector` frees leftover container children and advances anyway (at the cost of one escape-combo
  penalty).

Not spawned anywhere else — not by any other level, not in Open Space, not in Infiltration.

#### Tests

All under `tests/integration/`. Per the project's `CLAUDE.md` and `tests/README.md`, this whole family **asserts
intent, not just current behaviour** (it's new code, so the tests are the spec).

- **`test_space_station.gd`** (11 tests) — armour rule end to end: `test_station_starts_armored_with_four_live_turrets`,
  `test_core_ignores_damage_while_any_turret_lives`, `test_core_becomes_damageable_after_last_turret_dies`,
  `test_armored_core_emits_armor_deflected_and_keeps_full_health`, `test_turret_damage_does_not_leak_into_core_health`,
  `test_destroyed_turret_ignores_further_damage`, `test_station_with_no_live_turrets_is_immediately_damageable`,
  `test_config_max_health_wins_over_scene_health_node`, `test_config_turret_health_is_applied_to_every_turret`,
  plus two **real-physics bullet** tests: `test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core`
  and `test_a_real_bullet_damages_the_core_once_the_armor_is_broken` (instance a real `bullet.tscn`, step physics —
  proves the collision layer/mask chain and the not-consumed-bullet premise, not just the signal logic).
- **`test_station_assault_section.gd`** (7) — the level gate: `test_enemies_cleared_timeout_defaults_to_ten_seconds`
  (pins `cloud_descent` unaffected), `test_section_does_not_advance_while_an_enemy_lives`,
  `test_section_advances_when_the_last_enemy_is_freed`, `test_timeout_frees_leftover_enemies_then_advances`,
  `test_level_1_sections_are_in_order_with_station_assault_third`, `test_station_assault_is_enemies_cleared_with_a_long_timeout`,
  `test_station_assault_spawns_one_station_at_zero_delay_with_no_movement` (pins no `.delay()`/no `.move()`).
- **`test_station_laser_phase.gd`** (12) — `test_armor_broken_does_not_fire_while_any_turret_lives`,
  `test_armor_broken_fires_when_the_last_turret_dies`, `test_armor_broken_emits_exactly_once`,
  `test_phase_does_not_start_while_any_turret_lives`, `test_phase_starts_when_last_turret_dies`,
  `test_beam_is_not_lethal_during_the_warning_window`, `test_beam_damages_the_player_during_the_active_window` (the
  exact pair the PRD's done-condition asked for), `test_beam_does_not_damage_the_station_that_fires_it` (the
  self-destruct regression, forces a diagonal volley), `test_station_rotates_only_during_the_laser_phase`,
  `test_volley_angles_are_deterministic`, `test_beams_stop_and_do_not_outlive_the_station`,
  `test_config_laser_values_win_over_script_defaults`.
- **`test_laser_ray_hit_mask.gd`** (4) — the shared `LaserRay.hit_mask_override` extension stays additive:
  `test_default_hit_mask_is_unchanged_when_override_is_zero`, `test_override_replaces_the_default_mask_entirely`,
  `test_zero_means_default_and_never_an_inert_beam`, `test_override_value_is_readable_after_ready`.
- **`test_station_gunnery.gd`** (18) — `test_nothing_is_fired_before_the_first_volley`,
  `test_the_pool_is_a_direct_child_of_the_station`, `test_config_values_are_copied_onto_the_gunnery`,
  `test_a_volley_fires_one_fan_per_live_turret`, `test_destroying_turrets_removes_their_guns`,
  `test_turret_bullets_are_aimed_at_the_player`, `test_turret_barrels_face_the_player_when_firing` (the barrel-facing
  regression), `test_bullets_live_in_the_enemy_container_not_in_the_station`, `test_volleys_are_deterministic`,
  `test_the_core_does_not_fire_until_the_armor_breaks`, `test_a_core_ring_is_a_full_evenly_spaced_ring`,
  `test_successive_rings_precess_by_the_configured_step`, `test_the_ring_step_leaves_no_permanent_safe_lane` (the
  design-lock test, reads the step off the live node so it pins the shipped `.tres`), `test_turret_fire_stops_when_the_armor_breaks`,
  `test_everything_stops_and_bullets_are_freed_when_the_station_dies`, `test_the_timers_actually_run`,
  `test_bullet_pool_cancel_active_frees_in_flight_bullets`, `test_the_gunnery_cancels_its_bullets_when_the_station_dies`.
- **`test_radial_attack_pattern.gd`** (10) — the shared `RadialAttackPattern` resource in isolation:
  `test_a_full_ring_is_evenly_spaced`, `test_an_arc_is_centred_on_the_base_angle`,
  `test_a_single_bullet_arc_does_not_divide_by_zero`, `test_a_zero_bullet_count_fires_nothing`,
  `test_aim_at_player_offsets_the_base_angle_toward_the_player`, `test_aim_at_player_falls_back_to_down_with_no_player`,
  `test_the_pattern_ignores_ship_rotation`, `test_spawn_radius_places_each_bullet_on_its_own_angle`,
  `test_damage_and_speed_are_written_onto_the_bullet`, `test_it_returns_quietly_when_the_pool_is_exhausted`.
- **`test_station_reinforcements.gd`** (18) — `test_the_node_copies_its_three_fields_from_the_config`,
  `test_the_squads_cover_four_distinct_screen_edges`, `test_every_entry_starts_outside_the_play_area`,
  `test_every_entry_clears_the_off_screen_spawn_margin`, `test_squads_cycle_left_right_bottom_top_and_then_repeat`,
  `test_ships_are_siblings_of_the_station_with_a_path_mover`, `test_every_entry_moves_into_the_screen`,
  `test_every_spawned_mover_frees_on_a_fixed_duration`, `test_each_spawned_ship_is_announced_as_an_orphan_spawn`,
  `test_breaking_the_armour_stops_reinforcements`, `test_the_stations_death_stops_reinforcements`,
  `test_the_cap_skips_a_whole_squad_and_recovers_when_ships_are_freed`, `test_no_squad_uses_a_self_managed_ai_enemy`
  (guards against a `ram_ship`-style unkillable squad ship), `test_the_scene_carries_a_reinforcements_node`,
  `test_the_first_delay_and_then_the_repeat_interval`, `test_spawning_a_squad_does_not_touch_the_timer`,
  `test_every_squad_ship_can_be_hit_by_the_players_primary_weapon`,
  `test_a_squad_that_flies_through_costs_two_escape_combo_penalties` (pins the accepted 0.75×2 scoring wart).
- **`test_station_death_sequence.gd`** (14) — `test_the_wreck_stays_in_the_tree_after_hp_reaches_zero`,
  `test_died_and_was_killed_fire_at_the_moment_hp_reaches_zero`,
  `test_further_damage_during_the_death_sequence_does_not_re_emit_died`, `test_the_corpse_cannot_ram_the_player`,
  `test_the_wreck_is_freed_after_death_sequence_duration`, `test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour`
  (the additive boundary case), `test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre`,
  `test_blast_offsets_are_deterministic`, `test_every_blast_lands_on_the_hull`,
  `test_the_hull_drifts_and_darkens_during_the_sequence`, `test_the_spin_decays_rather_than_staying_constant`,
  `test_the_station_copies_its_death_duration_from_the_config`, `test_the_script_defaults_differ_from_the_shipped_values`,
  `test_shortening_the_station_duration_does_not_write_back_to_the_shared_config`.
- **`test_station_incoming_damage_paths.gd`** (9) — the real-physics collision-layer closure, per
  `docs/discovered-bugs.md`/`CLAUDE.md`: `test_a_real_homing_missile_damages_the_unarmored_core_through_the_collision_layers`,
  `test_a_real_warhead_missile_damages_the_unarmored_core_through_the_collision_layers`,
  `test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it`,
  `test_a_rocket_up_a_turret_lane_survives_the_armored_core_and_damages_the_turret_behind_it`,
  `test_a_real_asteroid_damages_the_unarmored_core_through_the_collision_layers`,
  `test_a_real_asteroid_is_deflected_by_the_armored_core_rather_than_missing_it`,
  `test_the_station_hull_does_not_block_the_players_mining_laser`, `test_the_mining_laser_burns_the_unarmored_core`,
  `test_a_station_on_the_default_body_layer_would_block_its_own_fight` (the boundary test proving layer-0 root is
  load-bearing, per `CLAUDE.md`'s reference to "bits 32 and 1024 and the layer-0 root").
- **`test_enemy_hurtbox_geometry.gd`** — project-wide invariant, but carries the station's permanent 88×240
  rejection: `test_the_88x240_proposal_fails_this_sweep`, `test_the_station_core_hurtbox_spans_the_hull_not_just_the_core`.
- **`test_player_bullet_lifetime.gd::test_a_deflected_hit_does_not_consume_the_bullet`** — the bullet-level half of
  the armour-deflection contract, via a duck-typed `ArmoredStandIn.is_armored()`, independent of the real boss scene.
- **`test_level_1_sequence.gd::test_level_1_runs_all_five_sections_end_to_end_with_a_real_station`** — the only test
  exercising the whole Level 1 section chain with a real station killed mid-run, proving the handoff to
  `planet_approach` with no `LevelDirector` change needed.

Gate at epic close: **26 scripts / 253 tests / 950 asserts, `GATE PASS`**; 9 of those scripts and 93 of those tests
belong to this epic (`REPORT.md`).

#### Known issues and design decisions

From `ENEMY.md`, `REPORT.md` → *Known gaps*, `docs/discovered-bugs.md`, and review-round rejections:

1. **Nobody has ever played this fight.** No GUI in the build container; every "feels fair" claim (telegraph timing,
   turret-count pacing, bullets/s pressure, phase-flip escalation, death-chain readability) is inference from
   research + arithmetic, unverified in play. Flagged as the single most valuable next step.
2. **`station_core.png` shipped as a fully opaque 256×256 grey rectangle** (65536/65536 px at alpha 1.0), because
   `create_image_pixflux`'s `no_background` parameter defaults unset. No gate step renders a scene, so nothing caught
   it until visual composite check. **Fixed 2026-09-07** via `scripts/strip-sprite-bg.sh` (4-connected flood fill
   from the image border) — 34324 px of `#565657` sky removed, 41 enclosed px of the same colour correctly kept,
   opacity now 47.63%. Regeneration was explicitly rejected (capped monthly PixelLab allowance, can't be undone,
   would discard art the turrets were designed to match). Pinned by `test_entity_sprite_transparency.gd`.
3. **Turret sprites shipped twice as 3/4 views** instead of top-down, because `create_image_pixflux`'s `view` param
   is only "weakly guiding" even when set. Regenerated with `create_map_object` (`view: "high top-down"` as a *real*
   control) on 2026-09-01. Root-caused to the tool, not the prompt; the `pixel-art-generation` skill now mandates
   this per-tool distinction project-wide.
4. **All four turrets are authored at `rotation = 0`** (barrels point local −Y / screen-top, away from the player,
   who is always below). `StationGunnery.fire_turret_volley()` snaps `global_rotation` at the moment of firing, so
   the barrel is only correctly aimed *during* a volley — the resting pose between volleys is still wrong-facing.
   Filed as an accepted, un-fixed cosmetic gap; the firing behaviour (not the resting pose) is what
   `test_turret_barrels_face_the_player_when_firing` pins. (Listed in `docs/discovered-bugs.md` as "closed by
   sub-item 4a", meaning the *firing* case was fixed, but the *resting* pose issue persists by design.)
5. **Collision layers were "only half proven" for most of the epic** — `test_space_station.gd` originally drove
   damage via direct `received_damage.emit()` calls, proving armour *logic* but nothing about whether a bullet could
   physically reach a hurtbox. **Closed** by the later real-physics tests in `test_space_station.gd` (bullet) and
   `test_station_incoming_damage_paths.gd` (rockets, asteroids, mining laser) — see Tests above.
6. **No boss-arrival beat.** The genre-standard "WARNING — HUGE BATTLESHIP APPROACHING" framing (researched,
   confirmed standard since Darius 1987) was deliberately left unbuilt as scope creep. Nothing in `EventBus` or
   `LevelDirector` announces the boss; research explicitly warns a stationary, unannounced boss "reads as scenery
   rather than a boss" — flagged as the most likely first-playtest complaint ("I didn't realise that was a boss").
7. **Reinforcement squads cost the player score twice if ignored** — `ScoreTracker`'s 0.75× escape-combo penalty
   applies outside the `if counts_in_wave:` guard, so a `wave_index == -1` orphan spawn (which reinforcements use)
   isn't exempt: ignoring one squad costs 0.75×0.75 = 0.5625 of the combo. Accepted deliberately (the alternative —
   not announcing the spawn — means killing a reinforcement pays out nothing, which reads as a worse bug); pinned by
   `test_a_squad_that_flies_through_costs_two_escape_combo_penalties`; filed for the user to overrule.
8. **Phase 2 has no aimed component at all** — the core ring is fixed-angle, beams are static in kind; nothing in
   phase 2 tracks the player directly. Justified only because the hull rotation + ring precession + beam sweep
   together mean no single position stays safe *over time*. Unverified in play; flagged as the first thing to
   re-examine if a "safe spot" turns out to exist.
9. **The core hurtbox spans the entire 240×240 hull**, not just the visible reactor core — by design (see Collision
   & damage), but explicitly recorded as a design call with real cost (25% of visible width swallows shots silently
   in phase 1, 66% in phase 2) rather than a free decision.
10. **Vertical reinforcement spawn margin (design y ±290 = 580 world px) does not survive a full camera pan**, against
    a strict requirement of `360 + V_LIMIT(380) + 37 ≈ 777`. This is a **pre-existing, project-wide** gap (every spawn
    site had this issue), not something the station's reinforcements introduced — and it was separately fixed
    project-wide by `docs/plans/a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr/`, which changed every
    spawn site (including `StationReinforcements._spawn_origin()`) to resolve against the camera's *current* pan
    position rather than its fixed centre. Margin numbers themselves were unchanged (already had headroom to spare).
11. **`ram_ship` remains unkillable by the player's primary weapon** (its `HurtBox` mask narrows to 33 post-`_ready()`,
    excluding the bullet's layer 64) and carries a dead `max_health = 999` config field nothing applies. The
    reinforcement squad table deliberately avoids `ram_ship` for this reason (uses `fighter` instead) rather than
    fixing the underlying enemy — filed as a separate design call, tracked by
    `docs/plans/ramship-cannot-be-hit-by-the-player-s-primary-weapon-and-its/`.
12. **The player's default gun is effectively infinitely piercing against stacked hurtboxes** (a project-wide
    property the station's armour design depends on — see Collision & damage). Filed as an open balance question,
    not acted on; the station's whole "shoot through the core to reach a turret" mechanic assumes this stays true,
    and any fix must preserve the `is_armored()` deflection exemption or the boss becomes unkillable.
13. **Rockets could previously "snipe" turrets through the armoured core for full damage without a deflection
    registering** — fixed by transplanting the same `is_armored()`-duck-typed deflection guard `bullet.gd` already
    used into `homing_missile.gd` and `warhead_missile.gd` (`docs/plans/rockets-cannot-damage-the-space-station-s-turrets-they-deton/`,
    reviewed APPROVED with no blocking findings). Pinned by `test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it`
    and `test_a_rocket_up_a_turret_lane_survives_the_armored_core_and_damages_the_turret_behind_it`.
14. **No `Engine.time_scale` hitstop on the death blow**, despite two research sources recommending it. Declined for
    a concrete reason (not scope/time): `LevelDirector`'s state machine and every station timer run on
    `get_tree().create_timer()`, so a global time-scale change would slow the level's own progression logic along
    with the death spectacle.
15. **No escalating fire rate for surviving turrets** (the "Gradius pattern" of turrets firing faster as siblings
    die) — found in research twice, rejected both times on purpose: it would cancel out the 4→3→2→1 quietening that
    is the player's feedback signal for "you're doing this right."
16. **Turret sprite/hurtbox has a known project-wide gotcha:** `Health.set_health()` emits `amount_changed`
    unconditionally on every call including 0→0, so a dead turret hit again would re-enter its death handler without
    the `_alive` guard present in both `_on_received_damage` and `_on_health_changed`; removing **both** guards makes
    `destroyed` fire 4× instead of once (verified by mutation test per `ENEMY.md`).
17. **`Gunnery` node's `bullet_pool` export requires `node_paths=PackedStringArray("bullet_pool")` in the `.tscn` text
    format**, or the exported `Node` reference is silently left `null` with **no error and a green gate** — the
    script's `get_node_or_null` fallback is the only thing that would save it. A structural scene-authoring trap
    worth knowing before touching the scene.
18. **`BulletPool` must stay a direct child of `SpaceStation`** — `bullet_pool.gd:47` hardcodes its bullet container
    as `get_parent().get_parent()`; parented anywhere else (e.g. under `Gunnery` or a turret) the whole in-flight
    bullet field would swing around with the hull's phase-2 rotation. Similarly, `StationReinforcements` spawns must
    be **siblings** of the station (into `enemy_container`), never children, for the identical rotation-drag reason,
    and the `ExplosionEffect` used by the death sequence must be parented to the **station**, never to
    `DeathSequence`, or blasts land inside the (rotating, about-to-be-freed) hull instead of the enemy container.

#### Open Space notes (Assault-specific assumptions)

The entity is **entirely Assault-scoped today** — it does not exist anywhere in `open_space/`. Concrete
Assault-specific assumptions baked into the current implementation, each file:line:

1. **Fixed single spawn point, no travel.** `level_1_director.gd:241` — `b.wave(0.0, [ b.space_station().at(0, -90) ])`
   with **no `.move()`**, in an autoscroller where the "arena" is the camera's fixed 1280×720 viewport
   (`ArenaCamera`). The whole fight assumes the player is always *below* the hull (turret sprites rest with barrels
   pointing screen-top, i.e. away from the player, and `StationGunnery` always aims *at* the single player node in
   group `"player"`). An open-space free-flight fight would need the station to be a fixed *world* object the player
   can approach and circle from any direction — the turret resting orientation, contact-hitbox layer-0 root
   rationale (built to not block a mining-laser raycast that assumes a fixed beam direction), and the assumed
   "player is below" geometry for reinforcement squad angling (`station_reinforcements.gd:177-186`, "top squad
   enters angled inward, clearing the hull by 41.8 units") would all need re-deriving for 360° approach.
2. **`ArenaCamera.WORLD_SCALE` / design-unit coordinate system.** `space_station.gd`, `station_reinforcements.gd`,
   and `level_1_director.gd` all depend on the 640×360-design-space-scaled-by-2.0 convention
   (`ENEMY.md`'s "Design-unit coordinates" rule, `CLAUDE.md`). Open Space's coordinate/camera model is different
   (free-flight hub, no fixed arena camera) — every scaled offset in this entity (spawn position, reinforcement
   offsets, off-screen margins) is Assault-camera-relative and would need a different basis in Open Space.
3. **`LevelSection.EndCondition.ENEMIES_CLEARED` gate + `wave_manager.enemy_container` child-count poll**
   (`level_director.gd:116`) is an Assault-only progression primitive tied to `LevelDirector`/`LevelSection`. Open
   Space uses a persistent hub + mission-select model (`open_space/scenes/levels/sector_hub.tscn`, mission resources
   under `open_space/scenes/mission_data/`), not sectioned levels with enemies-cleared gates — the "cannot progress
   until boss dead" mechanic would need a different completion hook (e.g. a mission-objective flag) in Open Space.
4. **Single hardcoded player reference via `get_tree().get_nodes_in_group("player")[0]`**
   (`station_gunnery.gd:165-169`, `_player_direction_from`) — assumes exactly one player ship in a single-player
   autoscroller. Should still hold in Open Space (also single-player), but the group-based lookup pattern itself is
   Assault-authored and untested against Open Space's player controller.
5. **`BulletPool`/reinforcement/explosion "must be a direct child of X" placement rules are all rotation-hazard
   workarounds specific to this station's own `rotation` being written directly by `StationLaserPhase`**
   (`station_laser_phase.gd:124`). Any Open-Space redesign that keeps the station "fixed" (not rotating, or rotating
   about a world position the player orbits) would need to re-derive whether these hard-coded
   `get_parent().get_parent()` container assumptions (`bullet_pool.gd:47`, `explosion_effect.gd:28,31`) still hold.
6. **Naming note:** Open Space already has an unrelated concept called "space station"
   (`open_space/scenes/mission_select_hubs/space_stations/fortuna_station.tres`,
   `open_space/scenes/levels/sector_hub.tscn`) — a mission-select hub location, completely unrelated to this
   mini-boss enemy. Moving/renaming this entity into Open Space should avoid colliding with that existing
   "space station" vocabulary (e.g. `fortuna_station`).
7. **`counts_toward_wave_clear` / `WaveManager.enemy_spawned` scoring plumbing** — `ScoreTracker` registers kills via
   `WaveManager.enemy_spawned + BaseEnemy.died` (why turrets can't score) — this whole scoring pathway is
   Assault/`WaveManager`-specific; Open Space would need its own equivalent hook for turret/core kill rewards if the
   fight is ported as-is.

(inferred) None of the above are stated as Open Space requirements anywhere in the dossier — they are derived
directly from reading the Assault-specific code paths this entity depends on, since the epic and all its plans were
scoped and built entirely within `assault/`.
