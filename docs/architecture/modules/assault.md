# Assault Module

The `assault/` module is the action-mission gameplay layer of the game: a vertical
**autoscroller shoot-'em-up** ("shmup"). The camera scrolls the world upward at a
fixed rate, timed enemy waves stream down from the top, and the player flies a fighter
that dodges and shoots while a scoring/combo system rewards aggressive, damage-free play.

The module also **hosts a self-contained race sub-mode** (`assault/scenes/race/`) — a
top-down racing game built on the same scene infrastructure but with its own director,
track-space scroll model, and per-racer AI. The race mode is summarized at a high level
below and documented in depth in the per-racer `RACER.md` files.

Most shared, reusable machinery (health/shield, overheat, bullet pool, hit/explosion
effects, the `EventBus` autoload, `UpgradeState`/`ShipModuleState`, the `MovementResource`
path classes, and `ArenaCamera`) lives in `global/` and is documented in
[the global module doc](./global.md). This doc covers what is specific to the assault
mission and links out where a mechanic crosses into `global/`.

---

## Directory map

Annotated tree of `assault/scenes/`:

```
assault/scenes/
├── player/                      Player fighter (assault mission)
│   ├── player_fighter.gd        AssaultPlayer — extends PlayerBase; ship-module integration, death → GameOver
│   ├── movement_controller.gd   Input → single/double-press signals + movement lock
│   ├── overheat.gd / overheat_bar.gd   Weapon heat component + its HUD bar
│   ├── states/                  State-machine states: idle, move, dash, shooting, warhead/rocket
│   └── weapons/                 Weapon modes, fire behaviors, and aim visualizers
│       ├── weapon_mode.gd       WeaponModeResource — per-weapon data (behavior, fire_interval, heat)
│       ├── behaviors/           STRAIGHT / LONG / SPREAD / BEAM / SNIPER fire behaviors
│       └── visualizers/         e.g. sniper aim line
├── projectiles/                 Player + enemy ordnance
│   ├── bullets/bullet.gd        Player bullet — UNPOOLED, frees itself off-screen (pierce, sniper)
│   ├── enemy_bullet/            EnemyBullet (become_friendly() flips it to a player projectile)
│   ├── missiles/                homing/ + warhead/ missiles
│   └── piercing_beam/           Sustained BEAM weapon projectile
├── systems/                     Mission orchestration (non-visual)
│   ├── scroll_controller/       Drives the autoscroll: moves the camera + emits distance
│   ├── arena_camera.gd          Pinned camera; WORLD_SCALE for design-unit → world conversion
│   ├── wave_manager/            WaveManager — time-triggered enemy spawning
│   ├── wave_builder.gd          WaveBuilder — fluent DSL for authoring waves/formations/movement
│   ├── level_director/          LevelDirector — sequences LevelSection resources
│   ├── score_tracker/           ScoreTracker — all scoring/combo math
│   └── skill_challenge/         SkillChallengeRunner — timed dodge bonuses
├── levels/
│   ├── edelia/1/                Level 1: background + level_1_director.gd (5 sections, mini-boss + "boss" phase)
│   ├── level_2_waves.gd         Level 2 wave list
│   └── race/                    Race-level scenes/config
├── enemies/                     base_enemy.gd, enemy_path_mover.gd + one folder per enemy type
├── hazards/                     asteroid_base.gd + big/small asteroids, laser_ray
├── allies/ally_fighter/         AI escort fighters (group "allies")
├── gui/                         HUD, score widgets/popups, weapon selector, game-over, debrief
└── race/                        Race sub-mode (core/, racers/, track/, ui/)
```

---

## Mechanics

### Player ship

Source: `assault/scenes/player/`.

`assault/scenes/player/player_fighter.gd` defines `AssaultPlayer`, which **extends
`PlayerBase`** (in `global/`, see [global.md](./global.md)) for shared health, shield,
overheat, the score-multiplier fields, and `EventBus` emission. It adds:

- **Ship-module integration.** Equipped modules from `ShipModuleState` (e.g. Warp,
  Overclock, Engine Boost) are instantiated lazily into `_module_pool` and `tick()`-ed
  every physics frame. Live equip/unequip is handled via the `module_equipped` /
  `module_unequipped` signals. Module flags such as `warp_module_active`,
  `overclock_module_active`, and `engine_boost_active` are read by the states and the
  weapon system. The `use_ability` action is offered to modules first via `_input`.
- **Death handling.** `_on_health_changed(0)` plays the explosion, shakes the camera,
  spawns `gui/game_over.tscn`, and pauses the tree (left paused until "Continue").
- **Overheat gating.** `_on_overheat_updated` implements the can-attack lock with 80%
  hysteresis, plus Overclock (never locks, self-damages) and Overdrive overrides.

**State machine** (`assault/scenes/player/states/`): each state is a `State` node wired
to the player via exported `actor` / `movement_controller` references.
- `idle_state.gd`, `move_state.gd` — resting / steered flight.
- `dash_state.gd` — double-tap barrel-roll (i-frames on side rolls); when the Warp module
  is active it teleports + deals contact damage instead.
- `weapon_state.gd` — primary weapon. Loads `WeaponModeResource`s from `weapons/modes/`,
  gates on `UpgradeState` unlocks, dispatches to a `WeaponBehavior`
  (STRAIGHT/LONG/SPREAD/BEAM/SNIPER), accrues heat per shot, and emits
  `EventBus.player_weapon_changed`.
- `warhead_missile_shooting_state.gd` (`RocketState`) — secondary missiles (warhead/homing).

`movement_controller.gd` converts raw input into `action_single_press` /
`action_double_press` signals and owns a movement lock used during dashes.

### Wave / spawn system

Source: `assault/scenes/systems/wave_manager/wave_manager.gd`,
`assault/scenes/systems/wave_builder.gd`,
`assault/scenes/enemies/enemy_path_mover.gd`,
`assault/scenes/enemies/base_enemy.gd`.
See the full spawn reference: [enemy roster & WaveBuilder](../../enemy-roster.md).

- **`WaveManager`** is a time-driven spawner. Each wave has a `trigger` time (relative to
  section start) and a list of spawn descriptors. `load_section()` resets the clock and
  loads a new section's waves; `_process()` fires each wave when `_time_elapsed` reaches
  its trigger. On spawn it instantiates the ship scene at an offset (scaled by
  `ArenaCamera.WORLD_SCALE`) from the camera's **current view** — `cam.global_position +
  cam.offset`, not just `global_position`, since `ArenaCamera` pans entirely through
  `offset` while pinning `global_position` at the level origin — so a spawn meant to land
  off the visible edge stays off the visible edge regardless of how far the player has
  panned. Emits `enemy_spawned(enemy, wave_index)` for `ScoreTracker`, and — when the
  descriptor carries a `MovementResource` — attaches an `EnemyPathMover`. It also expands
  `FormationResource`s into per-slot spawns.
- **`WaveBuilder`** is a fluent authoring DSL (`b.fighter().at(x,y).move(b.straight(...))
  .delay(...).shoot_forward()` …). It builds `SpawnEntryResource` / `WaveResource` /
  `LevelResource` objects and centralizes the enemy scene-path constants. Movement helpers
  (`straight`, `arc`, `sine`, `u_sweep`, `curve`, `player_focus`, `sequence`, `hold`) and
  formation helpers (`v_`, `wedge_`, `line_`, `diagonal_`, `cluster_`) live here.
- **`EnemyPathMover`** attaches to any `CharacterBody2D` enemy and drives **position only**
  by sampling its `MovementResource` each frame plus the camera scroll offset. It suspends
  the ship's own physics/AI (so timer-based shooting still works), faces the travel
  direction (or a fixed `look_angle`), and frees the enemy on screen exit or after a
  duration (`ExitMode`). `PlayerFocusMovement` is duplicated per-ship so each gets its own
  aim vector. **Suspension is three unconditional steps, never a conditional fallback:**
  `_actor.set_physics_process(false)`, the `"AIStateMachine"` child name lookup →
  `PROCESS_MODE_DISABLED` (both today's behaviour), *and* `_actor.suspend_ai()` when the actor
  `has_method` it (new — see [global.md](global.md) → *Enemy AI*). The name lookup is not a
  fallback the brain contract can switch off: the light assault ship is a `BaseEnemy` (so it
  *has* `suspend_ai()`), but its `AIStateMachine` states write `velocity` and call
  `move_and_slide()` from `StateMachine._process`, which only the name lookup stops. All 264
  path-driven spawns in Level 1 are unchanged by this addition.
- **`BaseEnemy`** is the shared enemy root: it owns `Health` + `HurtBox`, a contact hitbox,
  hit-flash/explosion effects, and emits `died` on death (setting `was_killed`). Scoring
  fields (`score_value`, `counts_toward_wave_clear`, `counts_as_escape`) are pulled from
  the subclass's `ShipConfig` resource. Each concrete enemy lives in its own folder under
  `assault/scenes/enemies/<type>/` with a `*_config.tres` and (often) bespoke AI states.
  **Contact damage is the one stat the base scene does not wire up for you:** every `BaseEnemy`
  subclass's `.tscn` authors a `ContactHitBox` node with `damage = 20`, which knows nothing about
  the subclass's own `.tres`, so a subclass wanting its configured `collision_damage` must
  re-apply it in `_ready()` off `contact_hit_box` (`gunship.gd`, `bomber.gd`,
  `light_assault_ship.gd`, `ram_ship.gd`, `space_station.gd`) or author a different default
  directly on its own scene node (`razor_drone.tscn`, `swarm_drone.tscn` — 30, still
  re-applied from config where one exists). Forgetting leaves the `.tres` value dead with no
  symptom; `tests/integration/test_enemy_contact_damage.gd` asserts it for the whole roster.
  *When* that hitbox is live is the enemy's `contact_profile` (`ContactProfile`, resolved like
  `defense_profile`): every legacy enemy gets the default COLLISION (always live, hitbox untouched);
  RAMMING and EXPLOSIVE arm it only in a committed state, and `suspend_ai()` arms it on rails — see
  [global.md](global.md) → ContactProfile.
  The hitbox's *geometry* is handled for you: every `ContactHitBox` node's `CollisionShape2D`
  references the same `SubResource` shape id as the body's and copies its `scale`, so a scaled
  body gets a correctly sized ram box for free — see `global.md`'s Hurtbox/Hitbox section for the
  authoring pattern. `tests/integration/test_contact_hitbox_geometry.gd` asserts that for every
  entity that has one.

  The *incoming* side has its own invariant: an enemy's `HurtBox` must **cover** the body
  `CollisionShape2D` the player collides with, swept over the whole roster by
  `tests/integration/test_enemy_hurtbox_geometry.gd`. Armour is a damage *rule* on a full-size
  hurtbox (deflect, flash, report 0), never a missing hurtbox — a shrunken one leaves visible hull
  that swallows shots and reports nothing, which reads as a broken gun rather than as armour. The
  space station is the worked example and the reason the file exists: see its
  [ENEMY.md](../../../assault/scenes/enemies/space_station/ENEMY.md) -> "Core hurtbox: why it
  spans the whole hull".

  A third sweep polices the **art** rather than the collision shapes:
  `tests/integration/test_entity_sprite_transparency.gd` fails any texture an entity draws over
  the game world that is 90%+ fully opaque, because a painted-in background renders as a card that
  cuts a hard rectangle out of the starfield. `station_core.png` shipped that way at 100% and
  survived two cycles, since nothing in the gate renders a scene. Recovery for art that is already
  correct in angle and palette is `./scripts/strip-sprite-bg.sh` (border flood fill) rather than a
  regeneration.

### Enemy AI in Assault — the `ArenaCamera` provider and the corridor constraint

The mode-neutral enemy AI stack (`global/enemy_ai/`, see [global.md](global.md) → *Enemy AI*)
knows nothing about Assault by name. It finds the mode by duck type, through one group:
`ArenaCamera` (`systems/arena_camera.gd`) joins `&"assault_arena"` in `_ready()`, **before** its
early return for a missing `Level1Background` sibling — a bare `ArenaCamera` (e.g. in a test) is
still a provider. It answers three methods, each with an `EnemyWorld.has_*` companion so "no
provider" and "a legitimately empty `Rect2()`" are never confused:

- **`projectile_world_rect()`** — the corridor's visible rect grown by 64 px: x −164…1444, y
  −444…1164. Consumed by `ProjectileLifetime` (above).
- **`enemy_cull_rect()`** — the legacy off-screen cull: `global_position` ± half the viewport ± 80 px. Phase 1's
  Razor Drone ended its dash with it; since Phase 2 (t10) the Razor survives its dash and leaves through
  `EngagementBudget` instead, so nothing in production reads it. It is kept behind `EnemyWorld.cull_rect()`.
- **`enemy_movement_constraint()`** — a fresh `AssaultCorridorConstraint` instance per call (a
  constraint holds a per-enemy "entered" latch, so `EnemyMover.AUTO` must get its own).

**`AssaultCorridorConstraint`** (`systems/assault_corridor_constraint.gd`, extends
`global/enemy_ai/movement_constraint.gd`'s identity `MovementConstraint`) is the velocity filter
between an `EnemyMover`'s desired velocity and its one `move_and_slide()`. It works **per axis**
against the corridor's `visible` rect (the same 1480×1480 square `ArenaCamera` frames, derived
from its own `SCREEN_W`/`SCREEN_H`/`H_LIMIT`/`V_LIMIT` constants — never duplicated):

| Band | Rule |
|---|---|
| Not yet entered (an axis outside `visible`) | Outward velocity discarded; inward speed floored at `entry_speed` (60 px/s). Every Assault spawn starts above the screen, so a fresh enemy is governed by this rule alone until both axes are inside. |
| Soft band (0–120 px past `visible`) | Outward component kept, reduced by `edge_pressure · d / soft_band` (200 px/s at the outer edge). |
| Outer band (120–450 px) | Full `edge_pressure`; the outward component itself scales linearly to 0 at `hard_band` (450 px). |
| Past `hard_band` | Outward component removed entirely, full `edge_pressure` applied — "forced to re-enter" (IDEAS §34). |

The `entered` latch is permanent once set: an enemy that has been inside `visible` at least once
never re-triggers the not-yet-entered rule. The tangential axis (already inside `visible`) is
always passed through untouched, so a corridor-constrained orbit or strafe is not damped on its
free axis.

**The Razor Drone was Phase 1's proof consumer for the stack (as the Drone Interceptor, with
`constraint_mode = NONE`), and since Phase 2 t10 it runs with the corridor on (`constraint_mode =
AUTO`)** — see [razor_drone/ENEMY.md](../../../assault/scenes/enemies/razor_drone/ENEMY.md). Its
`RazorDroneBrain` orbits, reverses, feints and dashes under an `EngagementBudget` (9 s). In Assault it
clamps its orbit centre into `inner_rect()` and attacks only from a 30°–75° side lane. It has a RAMMING
`ContactProfile` (armed only in DASH), a `StateLight` (white only before a real dash), and a post-miss
pulse through a brain-driven `AttackController.fire_now()`. Its behaviour spec is
`tests/integration/test_razor_drone.gd`, mostly dual-mode. The fixture's and the Razor's cross-mode
cases are in `tests/integration/test_enemy_dual_mode.gd`, built on `tests/helpers/enemy_ai_harness.gd`;
the corridor's contract tests are `tests/unit/test_assault_corridor_constraint.gd`. In Assault the
`EngagementBudget` being active also skips the Open Space hub idle below — the level has already
decided the fight is on, so the brain starts straight in ENTER.

**The same brain patrols its own `patrol_anchor` in Open Space until it notices the player** —
`AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) decides IDLE / NOTICING / (orbit-and-dash) /
RETURNING; the idle ring itself drifts, brakes, reverses and takes short boosts (`IDLE_ORBIT` /
`IDLE_BRAKE` / `IDLE_REVERSE` / `IDLE_BOOST`), and NOTICING hands over to combat from the drone's
current velocity, with no `halt()` or `boost()`. See razor_drone/ENEMY.md's "Hub idle" section for
the exact radii and timings.

**The Swarm Drone is the first Phase 2 enemy on the stack with the corridor on (`constraint_mode =
AUTO`)** — see [swarm_drone/ENEMY.md](../../../assault/scenes/enemies/swarm_drone/ENEMY.md). Its
`SwarmDroneBrain` runs the solo ram cycle (corkscrew → spiral → wind-up → burst → curved overshoot →
one more pass) under an `EngagementBudget`, with an EXPLOSIVE `ContactProfile` and a `StateLight`;
its behaviour spec runs in both harnesses in `tests/integration/test_swarm_drone.gd`. In Assault the
`EngagementBudget` being active is also what skips the Open Space hub idle below — the level has
already decided the fight is on, so the brain starts straight in APPROACH.

**The same brain patrols its `patrol_anchor` in Open Space when nobody has engaged it** — `AnchorIdle`
(`global/enemy_ai/anchor_idle.gd`) decides IDLE / NOTICING / (attack-cycle) / RETURNING; a whole
`SquadController` squad wakes together the tick after any one member perceives the player
(`squad.set_engaged` / `is_engaged` / `hold_combat`) and returns together once none of them are
engaged. See swarm_drone/ENEMY.md's "Hub idle" section for the exact radii and timings.

### Projectiles & bullet pool

Source: `assault/scenes/projectiles/`. Pooling: `global/components/bullet_pool.gd`
(see [BULLET_POOL.md](../../BULLET_POOL.md)).

- `bullets/bullet.gd` — the player bullet (`Area2D`). Moves forward, optionally
  inherits the shooter's forward velocity, supports **pierce** (limited, with per-hit
  damage decay) and **sniper unlimited-pierce** (passes through regular enemies, stops on
  asteroids/ram-ships). Uses `HitBox`/`HurtBox` from `global/`.

  **The player's bullets are not pooled.** `WeaponBehavior._launch()` spawns them and calls
  `Bullet.free_when_offscreen()`, so each one owns its own lifetime and frees itself at the
  viewport edge. The same scene *is* pooled by `AllyFighter`, which is why that free is opt-in
  rather than built into `bullet.gd` — see `free_when_offscreen()`'s comment and
  [BULLET_POOL.md](../../BULLET_POOL.md) ("the pool is smart, bullets are dumb").

  **`expired` means "something happened", not "I am done".** It fires on an ordinary hurtbox hit
  as well as at the range cap and the screen edge, and only the range cap frees. A pool can
  legitimately listen to it (recycling is reversible); the player path must not wire it to
  `queue_free`, because that consumes the shot on first contact and makes the space-station boss
  unkillable — see the ENEMY.md link above.

  **Player and enemy projectiles despawn on different boundaries, deliberately.** Player bullets
  use `VisibleOnScreenNotifier2D` (the *viewport* edge); `EnemyBullet` carries a
  `ProjectileLifetime` child (`global/components/projectile_lifetime.gd` — see
  [global.md](global.md)) with world-space rules instead: `max_time = 18 s`, `max_distance = 2400
  px` from where it armed, and — when an `ArenaCamera` provider is in the tree — the corridor's
  `projectile_world_rect()` (x −164…1444, y −444…1164, reproducing the old hardcoded arena-bounds
  check exactly). The player's weapons are also mounted in Open Space (`player_ship.tscn`), which
  has no `ArenaCamera` and a different world extent, so hardcoding the assault arena's bounds into
  them would be wrong in one of the two modes; `ProjectileLifetime`'s `max_time`/`max_distance`
  rules are what govern an enemy bullet fired in Open Space, with no rect at all. The cost is that
  a shot fired at an enemy that is in the arena but above the visible top now despawns; that band
  is off-screen and unaimable, so it is accepted. The sniper's unpooled shot
  (`enemy_sniper_bullet.tscn`, same script) carries its own `ProjectileLifetime` and arms lazily on
  its first physics tick, since it is positioned at the muzzle only *after* `add_child()` and is
  never `reset()`.

  All of the above is pinned by `tests/integration/test_player_bullet_lifetime.gd` and
  `tests/integration/test_enemy_bullet_lifetime.gd`.
- `enemy_bullet/enemy_bullet.gd` — `EnemyBullet`; `become_friendly()` flips its direction and
  collision so it damages enemies instead of the player. Currently unused — its only caller,
  the parry ability `reflect_state.gd`, was removed as dead code (2026-09-08): its input action
  had already been replaced by `use_ability` and no scene instanced it.
- `missiles/` — `homing/` and `warhead/` secondary munitions fired by `RocketState`.
- `piercing_beam/` — the sustained beam projectile for the BEAM weapon behavior.

`BulletPool` (in `global/`) is instantiated by shooters (allies and many enemies — **not** the
player, whose bullets are unpooled) to
recycle bullet instances rather than allocate per shot — see the linked doc for the
pool/`AttackController`/`AttackPattern` flow.

### Scoring

Source: `assault/scenes/systems/score_tracker/score_tracker.gd`.
Player-facing rules: [scoring guide](../../scoring_guide.md).
Implementation details: [assault spawning & scoring internals](../../assault-spawning-scoring-internals.md).

`ScoreTracker` lives next to `LevelDirector`/`WaveManager` and owns **all** scoring math;
UI nodes only subscribe to `EventBus`. It listens to `WaveManager.enemy_spawned`,
`BaseEnemy.died` / `AsteroidBase.died`, `Node.tree_exited` (escape vs kill),
`EventBus.player_health_changed`, and `EventBus.skill_challenge_completed`. It computes:

- **Kill points** scaled by a live **combo multiplier** (grows per kill, decays over time).
- **Wave-clear bonuses** via per-wave `WaveTally` bookkeeping (only enemies with
  `counts_toward_wave_clear` count; bonus drones don't). `section_loaded` clears tallies so
  wave indices don't collide across sections.
- **Survival** ticks, **skill-challenge** bonuses, and combo penalties on player damage or
  enemy escape — the escape penalty (`escape_combo_multiplier`, 0.75×) applies to every
  spawn source (waves, station reinforcements, asteroid shards) **except** one whose
  `ShipConfig.counts_as_escape` is `false` (currently only the bonus drone — see
  `tests/integration/test_score_tracker_escape_penalty.gd`). Independent of
  `counts_toward_wave_clear`: station reinforcements are exempt from wave-clear bonuses but
  still deliberately pay the escape penalty (see below).

Results publish via `EventBus.score_changed` / `combo_changed` / `score_event`, consumed
by `gui/hud_score_widget.gd` and `gui/score_popup*.gd`. A categorized `_breakdown` feeds
the end-of-level debrief.

### Levels & director

Source: `assault/scenes/levels/edelia/1/`.

The generic **`LevelDirector`** (`systems/level_director/level_director.gd`) sequences an
ordered list of `LevelSection` resources. On each section it transitions the background,
calls `wave_manager.load_section()`, and advances on the section's `EndCondition`
(`DURATION`, `WAVES_COMPLETE`, or `ENEMIES_CLEARED`). It emits `section_started` /
`level_complete`.

**`level_1_director.gd`** is the level-specific orchestrator. In `_ready()` it loops over
`_build_sections()` and adds each one, boots `ScoreTracker`, spawns the HUD, and wires per-section
schedules for bonus drones, laser-column hazards, and skill challenges (kept decoupled from the
wave lists). `_build_sections()` is split out of `_ready()` so the sequence can be asserted without
booting the level — every `_build_*` body touches only `LevelSection.new()`, `preload` and
`WaveBuilder`, so it is safe on a bare instance. The five sections are:

1. `deep_space` — 30 s timed, fighters/drones.
2. `asteroid_belt` — 30 s timed asteroid gauntlet (no enemies).
3. `station_assault` — the **space-station mini-boss**, `ENEMIES_CLEARED` (see below).
4. `planet_approach` — 110 s cinematic with light harassment.
5. `cloud_descent` — the **boss-phase / climax** section.

**Boss-phase logic (there is no discrete boss entity).** The climax is encoded entirely in
`level_1_director.gd`'s `_build_section_3()` ("cloud_descent") plus its section schedule.
Instead of a single boss node, the phase is an **`ENEMIES_CLEARED` section**: it opens with
a 5-ship ally escort arrowhead, then escalates through fighter sweeps, sniper crossfire,
ram surprises, and two **gunship waves** (the heaviest enemies in the roster) interleaved
with drone screens. Because the section ends on `ENEMIES_CLEARED` (not a timer), the level
will not complete until the player has destroyed/cleared every remaining enemy — the
director's `_wait_enemies_cleared()` polls the enemy container before advancing.
`_on_level_complete()` then plays the debrief dialog, computes the final score/stars from
`ScoreTracker`, shows `gui/level_debrief.tscn`, persists to `MissionState`, and transitions
to the exit cutscene.

**`level_1.tscn` also carries static, non-wave children** — `PlayerFighter`, `LaserWallWave`,
and (added for the log-records epic) one `InfoLogInteractable` instance (node name `LogRecord`,
see [global.md](global.md)) — parented directly under the level root at a resolved-pixel
`position`, never routed through `WaveManager`. A pickup or interactable spawned through
`WaveManager` would fire `ScoreTracker`'s `enemy_spawned`/`enemy_freed` bookkeeping (`_spawn_ship`
emits `enemy_spawned` for *any* `PackedScene`, and a spawned node with neither
`counts_in_wave` nor `counts_as_escape` defaults both to `true`), so collecting it would silently
misfire the wave-clear tally and the escape-combo penalty — static placement sidesteps that
entirely. `LogRecord`'s position is derived from the same design-space formula waves use, at
`t = 0` (`world_pos = Vector2(640, 360) + design_offset * ArenaCamera.WORLD_SCALE`), with the
derivation written as a `;`-comment in the `.tscn` file.

### Hazards

Source: `assault/scenes/hazards/`.

Hazards share `asteroid_base.gd` (`AsteroidBase`, which emits `died(world_position)` and
splits into shards) and include `big_asteroid/`, `small_asteroid/`, and `laser_ray/`
(telegraphed vertical laser columns lit by the level director). They are spawned through
the same `WaveManager`/`WaveBuilder` path as enemies (`b.big_asteroid()`, `b.laser()`,
etc.). For per-hazard detail, see the source folders under `assault/scenes/hazards/<type>/`
(each has its `.gd` + `.tscn`).

`LaserRay` is also used **outside** the wave path, as a component: the race gauntlet instances it
with `race_hazard`/`loop`, and the space station's `StationLaserPhase` spawns it per volley. Its
`hit_mask_override` export exists for that second case — see
[`laser_ray/HAZARD.md`](../../../assault/scenes/hazards/laser_ray/HAZARD.md).

### Enemies

Source: `assault/scenes/enemies/`.

Each enemy type has its own folder with a scene, a `*_config.tres` (a `ShipConfig` carrying
HP, score value, fire pattern, etc.), and — for AI-driven ships — bespoke state scripts
(e.g. `light_assault_ship/states/`). Roster: bomber, bonus_drone, razor_drone,
gunship, interceptor, light_assault_ship, ram_ship, sniper_enemy, swarm_drone. For the
catalogued stats and how to spawn each one, see the per-enemy detail in the source folders
under `assault/scenes/enemies/<type>/` and the consolidated
[enemy roster](../../enemy-roster.md).

#### Per-instance config resources

Every entity declares `@export var config: XConfig = load("res://.../x_config.tres")` and
`ResourceLoader` caches by path, so all instances of a type would otherwise share **one** config
object — the same one a test's `preload()` returns. `ShipConfig.privatise()` gives each entity a
`duplicate()` instead, called from `BaseEnemy._init()` **and** `_enter_tree()` (and the same pair on
`AllyFighter`, which is not a `BaseEnemy`). `_init()` covers writes made before `add_child`, which is
where `WaveManager` applies `initial_props`; `_enter_tree()` covers an override substituted in
afterwards and still lands before any child's `_ready()`, which the space station's four child nodes
depend on. Full reasoning: the `ShipConfig` section of [global.md](global.md). Pinned by
`tests/integration/test_config_instance_isolation.gd`.

⚠️ **The object `load()`/`preload()` returns is still shared and must never be written** — that is
process-wide balance data. The per-instance copy is what `entity.config` holds, not what the loader
hands you.

**`space_station/`** is the odd one out: a multi-part **mini-boss** rather than a wave enemy.
`SpaceStation` (`extends BaseEnemy`) carries four `StationTurret` children, each individually
damageable on its own `Health`, and its core refuses all damage while any turret lives —
`is_armored()` is `live_turret_count() > 0`, and the `_on_received_damage` override emits
`armor_deflected(damage)` and returns without touching `Health`. Destroyed turrets stay in the
tree as wreckage. It is spawned by the **`station_assault`** section (`_build_station_assault()`),
as a single zero-delay wave with no `MovementResource` — a spawn delay would let `waves_complete`
fire before the station existed, and a movement resource would attach an `EnemyPathMover` that
frees it on screen exit. Behaviour and the collision-layer rules — all four incoming damage paths
gated by physics rather than by reading the scene, and the duck-typed `is_armored()` exemption that
lets both bullets and rockets survive a deflected hit on the core to reach a turret behind it —
[`space_station/ENEMY.md`](../../../assault/scenes/enemies/space_station/ENEMY.md).

It has **two phases**. Killing the last turret makes `SpaceStation` emit `armor_broken` (a
zero-argument signal, latched so it fires exactly once), which starts **`StationLaserPhase`** — a
`Node2D` child of the scene, `station_laser_phase.gd`, that owns the whole second phase and keeps
`space_station.gd` free of laser logic. It rotates the station at a constant
`laser_rotation_speed` and fires volleys of `laser_ray.tscn` beams from a fixed, **deterministic**
angle list (never `randf()` — random attack ordering cannot be balanced or tested; the rotating
hull already varies the world angle). Beams are children of the phase node, so rotating the
station sweeps them for free. All five timings live in `space_station_config.tres` and are
**copied into the phase's own fields in `_ready()`** — those fields are the phase's tunable surface
(what tests override) and its fallback when a station has no config at all. Each station's
`config` is a private copy: see **Per-instance config resources** below.

⚠️ **A station beam must not use `LaserRay`'s default hit mask.** `_HIT_MASK` is
`128 | 256 | 512`, and the station's own core `HurtBox` is on layer 512, so a beam fired from
inside the hull takes the boss 600 → 0 HP in one frame. `StationLaserPhase` sets
`LaserRay.hit_mask_override = 128` before `add_child()`. See
[`space_station/ENEMY.md`](../../../assault/scenes/enemies/space_station/ENEMY.md) for why the
regression test has to force a *diagonal* volley to catch it.

**The station shoots back**, via a second sibling node, **`StationGunnery`**
(`station_gunnery.gd`) — same composition split as the laser phase, so `space_station.gd` holds
no gun logic either and gained only a `turrets()` data accessor. It drives one
`RadialAttackPattern` per phase, on its own `Timer`s:

- **Phase 1** — every **live** turret fires an aimed 3-bullet fan on one shared cadence
  (`turret_fire_interval`). The turret list is re-read per volley, so killing a gun visibly
  removes it from the volley for free, and the armour is also the threat. Each firing turret's
  `global_rotation` is set to its aim direction first — the sprite's barrels point along local
  -Y and nothing else sets `rotation`, so without that the barrels point at the top of the screen
  while firing elsewhere.
- **Phase 2** — `armor_broken` stops the turret cadence and starts full core rings that precess by
  `core_ring_step` each time, interleaving with the laser volleys.

⚠️ **The `BulletPool` must stay a *direct* child of `SpaceStation`.** `bullet_pool.gd` hardcodes
its container as `get_parent().get_parent()` with no override, so only that placement resolves to
`enemy_container` and puts bullets in unrotated world space. Placed under `Gunnery` or a turret it
would resolve to the station itself and the whole bullet field would swing with the rotating hull.
It is therefore **authored in `space_station.tscn`**, not created in code — and it has to be:
a child cannot `add_child()` onto its own parent from `_ready()`, because `_propagate_ready()`
blocks the parent while readying its children. The pool leaving the tree with the station is also
what frees in-flight bullets, which otherwise hold `ENEMIES_CLEARED` open. Pinned by
`tests/integration/test_station_gunnery.gd`.

The ten gunnery timings live in `space_station_config.tres` and are **copied into the gunnery's
own fields in `_ready()`**, for the same reason as the laser block.

**The station calls for help**, via a third sibling node, **`StationReinforcements`**
(`station_reinforcements.gd`) — the same composition split again, so `space_station.gd` gained
nothing at all this time. On a one-shot `Timer` it spawns small squads of **existing** enemy
scenes that cross the arena, so the player can no longer camp one spot while streaming into a
turret. The squad table is fixed and cycles `LEFT → RIGHT → BOTTOM → TOP` (never `randf()`, for
the same reason the beam angles are a list): two `interceptor` sweeping in from either side
through the vertical middle, two `swarm_drone` rising from below, two `fighter` with
`.shoot_forward()` angling down-and-inward from above. Squads are authored with `WaveBuilder`'s
own fluent API (`b.interceptor().at(…).move(b.straight(…)).free_after(…)`), in **640×360 design
units** scaled by `ArenaCamera.WORLD_SCALE` once at spawn — speeds are left unscaled because
`EnemyPathMover` applies the scale itself.

- **Phase 1 only.** Everything stops on `armor_broken`, and again on `died` as a backstop. Adds
  running through phase 2 is the documented way a boss ends up overshadowed by its own minions,
  and phase 2 is already beams every 6.5 s over rings every 2.0 s against a 48-bullet pool.
- **Reinforcements are spawned as *siblings* of the station**, into `_station.get_parent()` —
  i.e. `WaveManager.enemy_container`, the same place waves land. Never as children: the laser
  phase rotates the hull, and a ship parented under it would be dragged around the arena along
  with its own `BulletPool`'s bullets.
- **Every entry uses `ExitMode.FREE_ON_DURATION`**, not `FREE_ON_SCREEN_EXIT`. The latter only
  culls a ship that has been on screen at least once, so one that never quite arrives would live
  forever and hold `ENEMIES_CLEARED` open.
- **Each ship is announced on `EventBus.enemy_spawned_orphan`**, which `ScoreTracker` routes to
  `_on_enemy_spawned(enemy, -1)`. That buys kill score without disturbing any wave-clear tally —
  and it opts these ships into the game's universal 0.75× escape-combo penalty, which is a
  deliberate balance decision pinned by a test, not an oversight.
- **`reinforcement_max_alive` skips a *whole* squad** rather than spawning part of one, so the
  ceiling is exactly that number. The live list is pruned with `is_instance_valid` each time or
  the cap would jam permanently once ships start being culled.

The three cadence/cap fields live in `space_station_config.tres` and are copied in `_ready()` like
the other two blocks; the squad table itself stays in the script, because it is scene geometry
rather than a stat — the same split that keeps `laser_emitter_radius` on the phase node. Pinned by
`tests/integration/test_station_reinforcements.gd`.

**The station's death plays out**, via a fifth sibling node, **`StationDeathSequence`**
(`station_death_sequence.gd`) — the same composition split a fifth time. `BaseEnemy` emits `died`
and calls `queue_free()` in the same call (`BaseEnemy._on_health_changed`), which gave the 256×256 mini-boss
the identical one-frame death a 40 px interceptor gets. `SpaceStation` now overrides
`_on_health_changed`: everything that happened *at* the moment of death still happens there —
`was_killed`, `died`, and disarming the corpse — and only `queue_free()` moves, behind a
`death_duration` (1.8 s) `Timer` **node**. Seven blasts then roll across the hull at deterministic
hull-local offsets while it drifts and darkens, ending on one central blast and a
`CameraShake.add(1.0)`.

The handoff to `planet_approach` needed **no director change at all**:
`LevelDirector._wait_enemies_cleared()` already polls the enemy container's child count, so a
station that stays parented while it dies holds `station_assault` open for free.
`tests/integration/test_level_1_sequence.gd` walks Level 1's real five-section sequence with a real
station killed in the middle and asserts it reaches `level_complete`.

Three things here are load-bearing:

- **The station owns `queue_free()`, not the sequence node.** If the visual node owned it, a
  renamed or missing `DeathSequence` would hang `station_assault` for its full 180 s timeout with
  no error, then take the escape-combo penalty.
- **The `ExplosionEffect` is parented to the *station*, never to the sequence node.**
  `explosion_effect.gd` resolves its container as `get_parent().get_parent()`, so one hop too deep
  puts every blast inside the rotating hull — where it is freed with the wreck and invisible to the
  container the director polls. It is added lazily in the `death_started` handler, because
  `_propagate_ready()` blocks the parent during `_ready()`.
- **`StationGunnery._stop()` now calls `bullet_pool.cancel_active()`.** `BulletPool._exit_tree()`
  used to free in-flight bullets at the moment of death; with the wreck lingering ~1.8 s, a corpse
  would otherwise keep a live ring of bullets in the air — which both endangers the player after
  the boss is dead and holds `ENEMIES_CLEARED` open, since bullets live in that same container.

Pinned by `tests/integration/test_station_death_sequence.gd` and `test_level_1_sequence.gd`.

**`LevelSection.enemies_cleared_timeout`** is the safety net for `ENEMIES_CLEARED`: seconds to
wait for `enemy_container` to empty before giving up. It defaults to `10.0` — the constant it
replaced, sized for "wait for the last stragglers to leave", which is what `cloud_descent` wants —
and `station_assault` sets `180.0`, because there the fight *is* the section. On expiry
`LevelDirector` now **frees whatever is left** in the container before advancing, rather than
carrying it into the next section: a mini-boss has no `EnemyPathMover`, so nothing else would ever
remove it, and `_wait_enemies_cleared()` polls that same container, so a leftover would block the
next `ENEMIES_CLEARED` section forever. Each freed child takes `ScoreTracker`'s escape path, so
timing out costs one combo penalty (x0.75) per leftover.

**How the wait actually polls.** `_wait_enemies_cleared()` loops on the container's child count and
re-checks its deadline only *between* polls, so the effective granularity is
`_wait_for_child_exit_or_timeout(container, 1.0)` — a 0.3 s timeout really expires at ~1.0 s, plus
a 0.2 s settle in `_wait_seconds()` before `_advance()`. Budget any test off the poll, not the
nominal timeout. Both helpers measure their deadline with `Time.get_ticks_msec()` and create **no**
`SceneTreeTimer`: the old implementation raced a `create_timer(poll_seconds)` against
`child_exiting_tree`, so every early return — which is the normal case, since a dying enemy ends
the poll on the next frame — abandoned a timer that kept ticking for the rest of the window and
leaked if anything tore the tree down first. Wall-clock also matches the outer
`enemies_cleared_timeout` deadline, which was always ticks-based, so the two no longer disagree
while `Engine.time_scale` is off 1.0 (`trajectory_calc_module.gd:34`). Pinned by
`tests/integration/test_level_director_polling.gd`.

### Race sub-mode

Source: `assault/scenes/race/` (high-level only).

The race sub-mode reuses the assault scene/background/effects stack but swaps the shmup
director for a **racing** one:

- **`race/core/race_director.gd`** owns the participant list and standings (sorted by
  `track_y`), the finish line, and the fail-on-player-death signal.
- **`race/core/race_world.gd`** implements a **track-space scroll model**: it scrolls the
  Track `Node2D` downward at the player's top speed (objects authored at negative Track-Y
  are encountered as the player advances) and maps each AI racer's `track_y` to a screen Y.
- **`race/core/`** also holds the shared racer chassis (`race_ship.gd`,
  `race_participant.gd`, `racer_state_machine.gd`, `racer_weapon.gd`, `sensors.gd`,
  `lateral_mover.gd`) and the side-wall/barrier collision pieces.
- **Lethal track-hazard system** (`race/core/hazard_system.gd`): hazards in group
  `race_hazards` expose a duck-typed contract (`danger_rect()`, `is_lethal_now()`).
  `HazardSystem` polls every ship vs every lethal hazard each frame and applies a
  **shield-bypassing one-shot** — player → `RaceDirector.fail_race()` (restart); AI →
  `RaceShip.apply_lethal_hazard()` (explode + eliminate = attrition). The same hazard data
  feeds AI avoidance: `sensors.gd` (`race_hazard_ahead()`, `safe_x()`) drives a pre-FSM
  **dodge reflex** in `race_ship.gd`. Hazard entities live in `race/track/`: breakable
  `RaceWall`, static `RaceAsteroid`, and pulsing `RaceLaser` (an inherited scene of the
  assault `laser_ray.gd` in `race_hazard`/`loop` mode — horizontal timing gate or vertical
  lateral band). See [RACE_HAZARDS.md](../../../assault/scenes/race/track/RACE_HAZARDS.md).
- **Laser timing & player throttle:** horizontal lasers can't be dodged — the AI brakes and
  crosses during the dark gap (`sensors.blocking_laser_ahead()` / `laser_should_brake()`),
  and the player has a **brake** (`race_brake`, Left Shift) that lowers their
  `RaceParticipant.cruise_factor` to slow and time the beam (`player_race_controller.gd`).
- **Trapped panels:** a wall authored within `panel_lunge` (650) ahead of a dash panel in
  its lane is rocket-or-die (the boost lunges you into it). `sensors.panel_is_trapped()`
  makes every AI panel-seeker refuse such panels (filtered in `nearest_panel_ahead()`).
- **Speed feel:** `race/ui/speed_streaks.gd` (a CanvasLayer overlay) draws vertical streaks
  whose speed/opacity scale with the player's `top_speed_fraction()`, and
  `player_race_controller.gd` adds a quick `Camera2D` zoom-out punch on each panel boost.
- **`race/track/`** holds furniture (dash panels, mines, obstacles, finish line) and the
  **lethal hazards** (`race_wall`, `race_asteroid` — [RACE_HAZARDS.md](../../../assault/scenes/race/track/RACE_HAZARDS.md));
  **`race/ui/`** the race HUD, and **`race/player_race_controller.gd`** /
  `race_level_config.gd` the player input + level wiring.

Each AI rival has a **bespoke FSM** under `assault/scenes/race/racers/<name>/states/`.
Rather than re-document each here, see the per-racer design docs:
[bogomol](../../../assault/scenes/race/racers/bogomol/RACER.md) ·
[booster_gold](../../../assault/scenes/race/racers/booster_gold/RACER.md) ·
[fang](../../../assault/scenes/race/racers/fang/RACER.md) ·
[isac](../../../assault/scenes/race/racers/isac/RACER.md) ·
[pacer](../../../assault/scenes/race/racers/pacer/RACER.md) ·
[reacher](../../../assault/scenes/race/racers/reacher/RACER.md).

### GUI

Source: `assault/scenes/gui/`.

The HUD and overlays are pure **view** layers — they subscribe to `EventBus` and own no
game logic:
- `hud_score_widget.gd` — top-right score + combo readout (tweened), driven by
  `EventBus.score_changed` / `combo_changed`.
- `score_popup.gd` / `score_popup_spawner.gd` — floating "+N" popups from
  `EventBus.score_event`.
- `health_shield_bar.gd`, `overheat`'s `overheat_bar.gd` (under `player/`) — vitals.
- `weapon_selector.gd` / `weapon_chip.gd` / `ability_chip.gd` — current weapon/ability
  indicators, updated from `EventBus.player_weapon_changed`. `WeaponChip` draws
  `WeaponModeResource.icon`, set in each `assault/scenes/player/weapons/modes/*.tres`. That field
  is the single id → icon map: the ship menu's main-weapon column reads the same one. There used
  to be a second, hard-coded map in `player_menu.gd` keyed on a mode id that no longer existed;
  `tests/integration/test_weapon_unlock_sources.gd` now asserts every mode ships with an icon.
- `game_over.gd` — death overlay (spawned by the player; pauses the tree).
- `level_debrief.gd` — end-of-level score/stars breakdown screen.

---

## Links

- [Global module](./global.md) — shared components (PlayerBase, Health/HurtBox/HitBox,
  BulletPool, EventBus, UpgradeState/ShipModuleState, MovementResource path classes,
  ArenaCamera).
- [Enemy roster & WaveBuilder reference](../../enemy-roster.md)
- [Scoring guide](../../scoring_guide.md)
- [Assault spawning & scoring internals](../../assault-spawning-scoring-internals.md)
- [Bullet pool](../../BULLET_POOL.md)
- Race racer designs:
  [bogomol](../../../assault/scenes/race/racers/bogomol/RACER.md) ·
  [booster_gold](../../../assault/scenes/race/racers/booster_gold/RACER.md) ·
  [fang](../../../assault/scenes/race/racers/fang/RACER.md) ·
  [isac](../../../assault/scenes/race/racers/isac/RACER.md) ·
  [pacer](../../../assault/scenes/race/racers/pacer/RACER.md) ·
  [reacher](../../../assault/scenes/race/racers/reacher/RACER.md)
