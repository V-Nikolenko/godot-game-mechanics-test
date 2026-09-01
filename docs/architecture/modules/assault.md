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
│   ├── states/                  State-machine states: idle, move, dash, shooting, reflect, warhead/rocket
│   └── weapons/                 Weapon modes, fire behaviors, and aim visualizers
│       ├── weapon_mode.gd       WeaponModeResource — per-weapon data (behavior, fire_interval, heat)
│       ├── behaviors/           STRAIGHT / LONG / SPREAD / BEAM / SNIPER fire behaviors
│       └── visualizers/         e.g. sniper aim line
├── projectiles/                 Player + enemy ordnance
│   ├── bullets/bullet.gd        Pooled player bullet (pierce, sniper unlimited-pierce)
│   ├── enemy_bullet/            EnemyBullet (can be reflected → become_friendly)
│   ├── missiles/                homing/ + warhead/ missiles
│   ├── piercing_beam/           Sustained BEAM weapon projectile
│   └── primary_homing/          Homing primary-weapon variant
├── systems/                     Mission orchestration (non-visual)
│   ├── scroll_controller/       Drives the autoscroll: moves the camera + emits distance
│   ├── arena_camera.gd          Pinned camera; WORLD_SCALE for design-unit → world conversion
│   ├── wave_manager/            WaveManager — time-triggered enemy spawning
│   ├── wave_builder.gd          WaveBuilder — fluent DSL for authoring waves/formations/movement
│   ├── level_director/          LevelDirector — sequences LevelSection resources
│   ├── score_tracker/           ScoreTracker — all scoring/combo math
│   └── skill_challenge/         SkillChallengeRunner — timed dodge bonuses
├── levels/
│   ├── edelia/1/                Level 1: background + level_1_director.gd (4 sections, "boss" phase)
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
- `shooting_state.gd` / `weapon_state.gd` — primary weapon. `weapon_state.gd` loads
  `WeaponModeResource`s from `weapons/modes/`, gates on `UpgradeState` unlocks, dispatches
  to a `WeaponBehavior` (STRAIGHT/LONG/SPREAD/BEAM/SNIPER), accrues heat per shot, and
  emits `EventBus.player_weapon_changed`.
- `warhead_missile_shooting_state.gd` (`RocketState`) — secondary missiles (warhead/homing).
- `reflect_state.gd` — timed parry: opens a brief `Area2D` that flips incoming
  `EnemyBullet`s to friendly (`become_friendly()`); gated on the `reflect` upgrade.

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
  its trigger. On spawn it instantiates the ship scene at a **camera-relative offset**
  (scaled by `ArenaCamera.WORLD_SCALE`), emits `enemy_spawned(enemy, wave_index)` for
  `ScoreTracker`, and — when the descriptor carries a `MovementResource` — attaches an
  `EnemyPathMover`. It also expands `FormationResource`s into per-slot spawns.
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
  aim vector.
- **`BaseEnemy`** is the shared enemy root: it owns `Health` + `HurtBox`, a contact hitbox,
  hit-flash/explosion effects, and emits `died` on death (setting `was_killed`). Scoring
  fields (`score_value`, `counts_toward_wave_clear`) are pulled from the subclass's
  `ShipConfig` resource. Each concrete enemy lives in its own folder under
  `assault/scenes/enemies/<type>/` with a `*_config.tres` and (often) bespoke AI states.

### Projectiles & bullet pool

Source: `assault/scenes/projectiles/`. Pooling: `global/components/bullet_pool.gd`
(see [BULLET_POOL.md](../../BULLET_POOL.md)).

- `bullets/bullet.gd` — the pooled player bullet (`Area2D`). Moves forward, optionally
  inherits the shooter's forward velocity, supports **pierce** (limited, with per-hit
  damage decay) and **sniper unlimited-pierce** (passes through regular enemies, stops on
  asteroids/ram-ships). Uses `HitBox`/`HurtBox` from `global/`. `expired` signals the pool
  to reclaim it.
- `enemy_bullet/enemy_bullet.gd` — `EnemyBullet`; can be reflected by the player's parry
  (`become_friendly()`), which flips its collision so it damages enemies.
- `missiles/` — `homing/` and `warhead/` secondary munitions fired by `RocketState`.
- `piercing_beam/` — the sustained beam projectile for the BEAM weapon behavior.
- `primary_homing/` — homing variant of the primary weapon.

`BulletPool` (in `global/`) is instantiated by shooters (player, allies, many enemies) to
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
  enemy escape.

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

**`level_1_director.gd`** is the level-specific orchestrator. In `_ready()` it builds and
adds four sections, boots `ScoreTracker`, spawns the HUD, and wires per-section schedules
for bonus drones, laser-column hazards, and skill challenges (kept decoupled from the wave
lists). The four sections are:

1. `deep_space` — 30 s timed, fighters/drones.
2. `asteroid_belt` — 30 s timed asteroid gauntlet (no enemies).
3. `planet_approach` — 110 s cinematic with light harassment.
4. `cloud_descent` — the **boss-phase / climax** section.

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

### Hazards

Source: `assault/scenes/hazards/`.

Hazards share `asteroid_base.gd` (`AsteroidBase`, which emits `died(world_position)` and
splits into shards) and include `big_asteroid/`, `small_asteroid/`, and `laser_ray/`
(telegraphed vertical laser columns lit by the level director). They are spawned through
the same `WaveManager`/`WaveBuilder` path as enemies (`b.big_asteroid()`, `b.laser()`,
etc.). For per-hazard detail, see the source folders under `assault/scenes/hazards/<type>/`
(each has its `.gd` + `.tscn`).

### Enemies

Source: `assault/scenes/enemies/`.

Each enemy type has its own folder with a scene, a `*_config.tres` (a `ShipConfig` carrying
HP, score value, fire pattern, etc.), and — for AI-driven ships — bespoke state scripts
(e.g. `light_assault_ship/states/`). Roster: bomber, bonus_drone, drone_interceptor,
gunship, interceptor, kamikaze_drone, light_assault_ship, ram_ship, sniper_enemy. For the
catalogued stats and how to spawn each one, see the per-enemy detail in the source folders
under `assault/scenes/enemies/<type>/` and the consolidated
[enemy roster](../../enemy-roster.md).

**`space_station/`** is the odd one out: a multi-part **mini-boss** rather than a wave enemy.
`SpaceStation` (`extends BaseEnemy`) carries four `StationTurret` children, each individually
damageable on its own `Health`, and its core refuses all damage while any turret lives —
`is_armored()` is `live_turret_count() > 0`, and the `_on_received_damage` override emits
`armor_deflected(damage)` and returns without touching `Health`. Destroyed turrets stay in the
tree as wreckage. It is **not yet spawned by anything**: sub-item 2 of the Level 1 mini-boss epic
adds the `station_assault` `LevelSection`. Behaviour, the collision-layer rules and the known
test-coverage gap: [`space_station/ENEMY.md`](../../../assault/scenes/enemies/space_station/ENEMY.md).

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
  indicators, updated from `EventBus.player_weapon_changed`.
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
