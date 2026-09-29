# `global/` Module

> Cross-cutting code shared by every gameplay mode. See [project overview](../PROJECT.md) for how `global/` relates to the `assault/` and race modules that consume it.

## 1. Overview

`global/` is the shared library of the game: reusable components, autoload singletons, the state-machine base classes, ship modules, particle effects, pickups, and data-driven `Resource` types. Nothing here is specific to a single level or mode — `assault/`, the race mode, and the open-space hub all compose these same building blocks. Entities are built by *composition*: you add a `HealthComponent`, `HurtBox`, `ShieldComponent`, etc. as child nodes and wire their signals, rather than inheriting one monolithic actor class.

## 2. Directory map

```
global/
├── autoload/                  # one stray autoload (DialogPlayer) — note the singular name
│   └── dialog_player.gd       # DialogPlayer: global dialog runner (autoload)
├── autoloads/                 # persistent state singletons (autoloads)
│   ├── mission_state.gd       # MissionState: per-mission completion/stars/high score + cutscene flags
│   ├── session_state.gd       # SessionState: temp buffs surviving level transitions / restarts
│   ├── ship_module_state.gd   # ShipModuleState: equipped/unlocked module per slot
│   ├── ship_progression_state.gd # ShipProgressionState: permanent shield slot count
│   ├── upgrade_state.gd       # UpgradeState: unlocked weapon mode ids (validated); STARTING_IDS seeds a fresh profile
│   ├── log_state.gd           # LogState: which lore-log entries are collected, catalogue swept from disk
│   ├── pickup_state.gd        # PickupState: which persistent_id pickup placements have ever been collected
│   └── settings_state.gd      # SettingsState: player settings (open_space_scheme mouse/keys)
├── components/                # composable child-node behaviours
│   ├── health_component.gd        # Health (Node)
│   ├── temp_health_component.gd   # TempHealth (Node) — drains before Health
│   ├── hurtbox_component.gd       # HurtBox (Area2D) — receives hits
│   ├── hitbox_component.gd        # HitBox (Area2D) — deals hits, DamageType enum
│   ├── shield_component.gd        # Shield (Node) — discrete-charge shield
│   ├── damage_reaction.gd         # DamageReaction (Node) — generic "take a hit" router
│   ├── defense_profile.gd         # DefenseProfile (Node) — per-instance HurtBox mask/damage-type data
│   ├── contact_profile.gd         # ContactProfile (Node) — what touching an enemy does: NONE / COLLISION / RAMMING / EXPLOSIVE
│   ├── contact_blast.gd           # ContactBlast (HitBox) — code-built blast an EXPLOSIVE profile leaves in the owner's parent
│   ├── state_light.gd             # StateLight (Node2D) — one small red/yellow/white attack-telegraph light
│   ├── overheat_component.gd      # Overheat (Node) — weapon heat
│   ├── attack_controller.gd       # AttackController (Node) — drives an AttackPatternResource
│   ├── projectile_lifetime.gd     # ProjectileLifetime (Node) — world-space projectile expiry
│   ├── bullet_pool.gd             # BulletPool — bullet object pool
│   ├── bubble_shield.gd/.tscn     # BubbleShield (AnimatedSprite2D) — shield visual
│   ├── shield_icon*.gd/.tscn      # ShieldIconStrip / ShieldIcon — shield HUD
│   ├── hit_effect.gd              # HitEffect — per-hit particle burst
│   ├── explosion_effect.gd        # ExplosionEffect — death burst
│   ├── thruster_effect.gd         # ThrusterEffect — engine flame
│   ├── rocket_trail.gd            # RocketTrail — missile trail
│   └── low_health_smoke.gd        # LowHealthSmoke — smoke below an HP threshold
├── enemy_ai/                  # mode-neutral enemy AI stack (enemy rework phase 1, squads/idle phase 2)
│   ├── enemy_brain.gd         # EnemyBrain (Node) — decides: tick(delta), on_suspended(), seeded rng
│   ├── enemy_mover.gd         # EnemyMover (Node) — the single writer of an AI enemy's velocity/rotation
│   ├── movement_constraint.gd # MovementConstraint (RefCounted) — identity filter; mode constraints extend it
│   ├── steering.gd            # Steering — pure seek/arrive/orbit/intercept/evade/strafe/hold/drift/spiral/corkscrew/… primitives
│   ├── target_info.gd         # TargetInfo — player resolver + prediction/intercept snapshot
│   ├── engagement_budget.gd   # EngagementBudget (RefCounted) — Assault-only per-brain exit timer
│   ├── burst_clock.gd         # BurstClock (RefCounted) — counts down an exact-size, evenly-spaced burst
│   ├── squad_controller.gd    # SquadController (RefCounted) — event-driven lead/flank/rear role board
│   ├── anchor_idle.gd         # AnchorIdle (RefCounted) — generic idle-around-an-anchor → combat handover
│   └── enemy_world.gd         # EnemyWorld — the one lookup of the &"assault_arena" mode provider
├── physics/
│   └── collision_layers.gd    # CollisionLayers — named constants, one per project.godot layer_names entry
├── entities/
│   └── player_base.gd         # PlayerBase (CharacterBody2D) — shared player base class
├── interactables/              # input-driven world objects (sibling of pickups/, not a subclass)
│   ├── info_log_interactable.gd    # InfoLogInteractable (Area2D) — re-readable message, never consumed
│   └── scenes/
│       └── info_log_interactable.tscn
├── statemachine/
│   ├── state.gd               # State base contract
│   └── state_machine.gd       # StateMachine — runs child States
├── ship_modules/              # 15 module scripts + base (ShipModuleBase) — see SHIP_MODULES.md
│   ├── ship_module_base.gd    # ShipModuleBase (RefCounted) + create() registry
│   └── *_module.gd            # one file per module (armor_plating, overclock, …)
├── systems/                   # global services (some are autoloads)
│   ├── event_bus.gd           # EventBus (autoload) — decoupled signals
│   ├── camera_shake.gd        # CameraShake (autoload) — trauma-based screen shake
│   ├── camera_director.gd     # CameraDirector — arbitrates zoom/offset effects
│   ├── background_controller.gd # BackgroundController — abstract level-bg base
│   └── aim_cursor.gd          # AimCursor — static helper: hardware crosshair cursor (apply/restore)
├── pickups/                   # PickupBase + collectibles (+ scenes/)
├── resources/                 # data-driven Resource definitions
│   ├── attack/                # AttackPatternResource + subtypes
│   ├── movement/              # MovementResource + path subtypes
│   ├── formation/             # FormationResource + formation subtypes
│   ├── waves/                 # LevelResource / WaveResource / SpawnEntryResource
│   ├── levels/                # LevelSection / BackgroundPhase
│   ├── ship_config.gd, score_config.gd, skill_challenge_resource.gd
└── ui/                        # dialog system, pause menu, player/ship menu, mission HUD
```

## 3. Autoloads

All eleven are registered in `project.godot` under `[autoload]`. The `*` prefix means the script is the singleton root. Note the path quirk: most live in `global/autoloads/` (plural), `DialogPlayer` lives in `global/autoload/` (singular), and `EventBus`/`CameraShake` live in `global/systems/`.

| Autoload | File | State it owns | Read / written |
|---|---|---|---|
| `MissionState` | `global/autoloads/mission_state.gd` | Per-mission `completed` / `stars` / `high_score`, plus cutscene-seen flags. Persists to `user://mission_state.cfg`. | Written on mission win (`complete`, `record_score`) and when a cutscene plays (`mark_cutscene_seen`); read by the mission-select hub and HUD. Stars run on a `MIN_STARS`–`MAX_STARS` (1–3) scale: **0 is the reserved "never completed" sentinel** returned by `get_stars()` for an unplayed mission and drawn as three empty stars by `MissionListItem`, so a stored clear is always worth at least 1 star. `complete()` clamps out-of-range input into the scale *and* `push_warning`s, since every caller comes via `MissionConfigResource.stars_for_score()` (already floored at 1) and an out-of-range value therefore means the caller miscomputed. |
| `DialogPlayer` | `global/autoload/dialog_player.gd` | Active dialog run state (`is_active`, `auto_mode`, current script/line). Owns a `DialogBox` instance. | Written by callers via `play(script)` / `skip_dialog()`; read by player controllers to gate input while `is_active`. |
| `UpgradeState` | `global/autoloads/upgrade_state.gd` | Set of unlocked ids, one list — `ALL_IDS` weapon modes (`default`, `sniper_shot`, `spread`, `gatling`, `mining_laser`). Persists to `user://upgrades.cfg`. `STARTING_IDS` (`[&"default"]`) is what a fresh profile is seeded with; every other id must be granted by a `WeaponModeUnlockerPickup` in the world. | Written by `unlock(id)` — whose only production caller is that pickup; read by weapon-selection UI via `is_unlocked` / `unlocked_ids`. Emits `unlocked_changed`, which `PlayerMenu` listens to so the main-weapon column rebuilds when an unlock lands mid-scene. Both `unlock()` and `_load()` reject any id failing `is_known_id()` with a `push_warning`, so a typo or a stale save entry can no longer sit in the store invisibly. |
| `EventBus` | `global/systems/event_bus.gd` | No state — pure signal hub (health, overheat, weapon, mission, scoring signals). | Emitted by gameplay (e.g. `PlayerBase` emits `player_health_changed`); subscribed by HUD/UI instead of polling nodes. |
| `ShipModuleState` | `global/autoloads/ship_module_state.gd` | Equipped + unlocked module id per slot (`cockpit`/`armor`/`weapons`/`engines`). Persists to `user://ship_modules.cfg`. **`equip()` refuses a module that is not unlocked** (`&""`/unequip is exempt), so `unlock()` is the only way in. | Written by `equip` / `unlock`; read by the ship menu (`ModuleList` greys locked rows) and the player ship on spawn. Emits `module_equipped` / `module_unequipped` / `module_unlocked`. |
| `ShipProgressionState` | `global/autoloads/ship_progression_state.gd` | Two independent stats on one `ConfigFile`: permanent shield slot count (clamped 1..5) and open-space boost charge capacity (clamped `MIN_BOOST_CHARGES`..`MAX_BOOST_CHARGES` = 2..5). Persists to `user://ship_progression.cfg` (`KEY_SHIELDS` / `KEY_BOOST`). | Shield side written by `add_permanent_shield` / `set_permanent_shield_count`, read by `Shield._ready()` when `bind_progression == true`, emits `permanent_shield_count_changed`. Boost side written by `add_boost_charge` / `set_boost_charge_count`, read by `BoostMeter._ready()` when `bind_progression == true` (the default), emits `boost_charge_count_changed`; `BoostMeter._on_progression_changed()` raises `max_charges` **and** grants the new charge immediately, so a pickup collected mid-flight is usable that session, not the next. Each stat's setter clamps, no-ops when unchanged, saves, and emits independently — raising one never disturbs the other on the shared file. |
| `SessionState` | `global/autoloads/session_state.gd` | Cross-level temporary buffs: temp shield count, temp HP pool, timed damage buff (saved as Unix expiry). Persists to `user://session.cfg`. | `apply_to(player)` called from `PlayerBase._setup_components()`; auto-saved when shield/temp-HP/damage-buff state changes. `apply_to` binds the `TempHealth` node into the `amount_changed` handler so the saved stack size is read off the component rather than derived from the payload. |
| `CameraShake` | `global/systems/camera_shake.gd` | A single `_trauma` float (0..1) that decays each frame. | Written by any system via `add(amount)`; read each frame by cameras via `get_offset()` (used inside `CameraDirector`). |
| `LogState` | `global/autoloads/log_state.gd` | Which `LogEntryResource` ids are collected. Persists to `user://log_state.cfg`. `total_count()` is a `DirAccess` sweep of `catalogue_dir` (`global/resources/logs/entries/` in production) — never a hand-maintained list, unlike `UpgradeState.ALL_IDS`. | `collect_next()` is the only mutator: an anonymous lore-log pickup calls it with no id and it grants the lowest-`sequence` entry not yet collected, so the story reads in catalogue order regardless of where in the world it was found. Read via `is_collected` / `collected_ids` / `all_ids` (catalogue order, unfiltered — the ESC menu's Lore Logs reader below is its only caller) / `get_entry` / `total_count`. Emits `log_collected(id)`. Validates on load like `ShipModuleState`/`UpgradeState`: an id in the save file with no matching catalogue entry is `push_warning`ed and dropped. Information logs (one-time, non-persisted) never touch this store. |
| `PickupState` | `global/autoloads/pickup_state.gd` | Which `StringName` `persistent_id`s have ever been collected, independent of any physical node. Persists to `user://pickup_state.cfg`, same `ConfigFile` shape as `LogState`. | `mark_collected(id)` (idempotent) is the only mutator, called from `PickupBase._on_body_entered()` when a collected pickup's `persistent_id` is non-empty; `has_collected(id)` gates the same handler so a respawned pickup (e.g. an assault mission restart, which reloads the scene) does not re-grant an id already collected. A pickup that leaves `persistent_id` at its default `&""` (every pickup shipped today) never touches this store and keeps respawning every scene load. |
| `SettingsState` | `global/autoloads/settings_state.gd` | Player settings, one `ConfigFile` (`user://settings.cfg`). First key: `open_space_scheme` (`&"mouse"` / `&"keys"`, default `&"mouse"`), re-validated against `SCHEMES` on load with a fallback to the default. Named `SettingsState`, not `ControlsState`, so a future setting (e.g. mouse sensitivity) lands as another key here rather than a second autoload. | `set_open_space_scheme(scheme)` validates, saves and emits `open_space_scheme_changed(scheme: StringName)` — but only on an actual change, so a redundant set neither writes to disk nor re-seeds a live `ShipTurnController` mid-flight. `OpenSpacePlayerShip._ready()` seeds its `ShipTurnController.scheme` from `get_open_space_scheme()` and connects the signal to re-seed it live, without a scene reload. The player changes it from the ESC menu's **Settings** panel (`SettingsPanel`, below) — the store's only writer outside tests. |

## 4. Shared systems (`global/systems/`)

### `event_bus.gd` — `EventBus`
Autoload signal hub for decoupling gameplay from UI. Declares typed signals only (no logic): player health/overheat/weapon/rocket/death, ability activate/deselect, mission wave/complete/failed, and scoring (`score_changed`, `combo_changed`, `score_event`, `skill_challenge_completed`, `enemy_spawned_orphan`). Subscribe here instead of `get_nodes_in_group()`.

### `camera_shake.gd` — `CameraShake`
Trauma-model screen shake (Eiserloh). Systems call `CameraShake.add(amount)` to inject trauma in `[0,1]` (saturating); trauma decays at `_DECAY = 1.5`/s. The visible offset is quadratic — `get_offset()` returns a random vector scaled by `trauma² * _MAX_OFFSET (8.0 px)`. Cameras add this to their own offset each frame.

### `camera_director.gd` — `CameraDirector`
Owns a `Camera2D` (default sibling at `camera_path = ".."`) and arbitrates competing zoom/offset drivers. Systems call `set_effect(name, zoom, offset, priority)`; each frame the highest-priority effect wins and the director blends toward it (`blend_speed = 6.0`) so hand-offs don't pop, then composes `CameraShake.get_offset()` on top. If an external animator writes `camera.zoom` directly (e.g. the pause menu tween), the director detects the mismatch, resyncs, and yields that frame.

### `background_controller.gd` — `BackgroundController`
Abstract base for level background renderers. Subclasses must override `transition_to(phase: BackgroundPhase, duration)` to tween toward a `BackgroundPhase` snapshot. Optional overrides `set_scroll_multiplier(m)` and `set_throttle_scroll(m)` (default no-ops) let dash panels / race throttle speed up scrolling. `LevelDirector` calls these per section.

### `aim_cursor.gd` — `AimCursor`
Static-only helper (`RefCounted`, never instantiated) that swaps the OS mouse arrow for a procedurally-drawn 32×32 crosshair via `Input.set_custom_mouse_cursor()` — a hardware cursor rather than a `_draw()`-based one, since a software cursor adds a frame of input latency the engine docs call out by name. `build_image(size, color)` is a pure `Image` builder (four ticks around a transparent centre gap); `apply()`/`restore()` wrap the sticky, process-global `Input` call, and `is_applied()` is the read-back seam tests use since `Input`'s cursor state itself cannot be queried. Currently owned by `OpenSpacePlayerShip` — see [open_space.md](open_space.md) §3.2.6 — but lives here rather than beside the ship because nothing about it is open-space-specific.

## 5. Integration recipes — "How to add X to an entity"

> Entities compose behaviour by adding child nodes and wiring signals. The canonical wiring of all of this for the player is `PlayerBase` (`global/entities/player_base.gd`); generic ships use `DamageReaction` instead. Verify the API of each component (linked file) before copying a snippet.

> **Not every component lives here.** Two of the open-space ship's children are deliberately kept beside it in `open_space/scenes/entities/player/` rather than in `global/components/`, because they are open-space-only verbs and this project's mode isolation is structural: `ShipTurnController` (steering — [open_space.md](open_space.md) §3.2.1) and `BoostMeter` (the Shift boost's charge economy — §3.2.3). Both are resolved **by type** from `player_ship.gd::_ready()`. `class_name` still registers globally, so the placement is a signal of intent; the enforcement is `tests/integration/test_open_space_boost_wiring.gd`'s invariant cases over the assault and infiltration player scenes.

> **Every component in this section has a characterization test.** Before changing one, read its
> test — it is the fastest correct description of what the component actually does, including the
> edge cases the source does not spell out. Mapping: `Health` → `tests/unit/test_health_component.gd`,
> `TempHealth` → `test_temp_health_component.gd`, `HitBox`/`HurtBox` → `test_hitbox_hurtbox.gd`,
> `Shield` → `test_shield_component.gd`, `DamageReaction` → `test_damage_reaction.gd`,
> `DefenseProfile` → `test_defense_profile.gd`, `ContactProfile`/`ContactBlast` → `test_contact_profile.gd` (+ `tests/integration/test_contact_blast_damage.gd`, real player hurtbox and health), `AttackController` → `test_attack_controller.gd`,
> `ProjectileLifetime` → `test_projectile_lifetime.gd` (+ `tests/integration/test_enemy_bullet_lifetime.gd`
> for the `EnemyBullet` migration), `TargetInfo` → `test_target_info.gd`,
> `SquadController` → `test_squad_controller.gd` (+ `tests/integration/test_wave_squads.gd` for how
> Assault spawns get one), `AnchorIdle` → `test_anchor_idle.gd`, `EngagementBudget` →
> `test_engagement_budget.gd` (+ `tests/integration/test_engagement_deadline.gd`, the level-timing
> proof), `BurstClock` → `test_burst_clock.gd`, `StateLight` → `test_state_light.gd`, `Steering` → `test_steering.gd`,
> `Overheat` → `test_overheat_component.gd`, the state machine → `test_state_machine.gd`, and the
> whole `PlayerBase` damage chain → `tests/integration/test_player_damage_chain.gd`. The autoloads
> in §3–4 are covered by `tests/unit/test_<autoload>.gd`. See [`tests/README.md`](../../../tests/README.md).

### Health — `health_component.gd` (+ `temp_health_component.gd`)

Add a `Health` node (`class_name Health extends Node`) as a child named `HealthComponent`. Exports: `max_health: int = 100`, `current_health: int = 100`, `invincibility_frames_enabled: bool = false`, `invincibility_time_in_sec: float = 0.5`. API: `increase(amount)`, `decrease(amount)`, `set_health(v)`; signal `amount_changed(current_health: int)`, emitted by `set_health()` on **every** call including no-op ones, so handlers must tolerate repeats and must take one argument. `decrease()` is ignored while its internal invincibility timer is running (only when `invincibility_frames_enabled`); it also traces the hit to stdout, but only under `--verbose` (see the logging convention in [PROJECT.md](../PROJECT.md)), and it does not require the component to have a parent.

`TempHealth` (`class_name TempHealth extends Node`, child named `TempHealthComponent`) is an optional buffer that drains *before* `Health`. `add_stack(base_health)` adds one stack of `base_health/2` HP (cap `MAX_STACKS = 5`); `take_damage(amount)` drains and returns the overflow that should hit `Health`. Signal `amount_changed(current, maximum)`.

Read-only properties `max_temp` (the cap, `MAX_STACKS * stack_hp`) and `stack_hp` (what one stack is worth, locked in by the first `add_stack`/`restore` and `0` before that). **Anything persisting the pool must save `stack_hp` and feed it back through `restore(current, saved_stack_hp)` — never recover it as `max_temp / MAX_STACKS`.** That division inverts an invariant the component is free to change, and truncates toward zero if it stops holding, silently handing the player back a smaller pool than they earned. `SessionState` does this correctly by binding the component into its `amount_changed` handler.

```gdscript
# Manual damage routing (TempHealth in front of Health):
var overflow := temp_health.take_damage(damage)   # returns leftover
if overflow > 0:
    health.decrease(overflow)
```

### Hurtbox / Hitbox — `hurtbox_component.gd`, `hitbox_component.gd`

`HitBox` (`extends Area2D`) is the *attacker* side: exports `damage: int = 1` and `damage_type: DamageType` (`enum DamageType { LASER, ROCKET, CONTACT }`). Put it on bullets, rockets, and ramming bodies.

**Contact hitboxes are scene-authored, not code-built.** An entity that damages the player on
ramming contact — every assault enemy, `ally_fighter`, the asteroid family — authors a
`ContactHitBox` node directly in its `.tscn`: an `Area2D` running `hitbox_component.gd`
(`uid://deqgbl6m44nrj`), with a `CollisionShape2D` child whose `shape` references the **exact same
`SubResource` id** as the entity's body `CollisionShape2D` (Godot resolves a `SubResource` id to
one shared object per scene file, so this reproduces object-identity sharing, not a copy) and
whose `scale` is copied verbatim from the body node. `layer`/`mask`/`damage`/`damage_type` are
authored directly on the node; a script only overwrites `.damage` in `_ready()` when a
`*_config.tres` needs to override the scene's default (see `BaseEnemy.contact_hit_box` below).
Copying only the `Shape2D` and skipping the node's `scale` is how every code-built contact box in
the game used to end up smaller than its visible hull — the gunship rammed with an 18 px box
against a 41.5 px ship — which is why this is authored geometry now, not code. See
`assault/scenes/hazards/big_asteroid/big_asteroid.tscn` for the pattern this was modelled on, and
`assault/scenes/enemies/bomber/bomber.tscn` for a `BaseEnemy` subclass's version.
`tests/integration/test_contact_hitbox_geometry.gd` sweeps every entity that has one and fails the
gate if a hitbox stops matching its body; the same file also asserts `damage_type` is authored as
`CONTACT` rather than the `HitBox` class default of `LASER`, since a ram is contact damage.

`BaseEnemy` exposes the node as `@onready var contact_hit_box: HitBox =
get_node_or_null("ContactHitBox") as HitBox` (nullable — `bonus_drone` authors none, which is its
"contact-harmless" behaviour). `AllyFighter` (not a `BaseEnemy`) does the same under its own
`_contact_hit_box`.

`HurtBox` (`extends Area2D`) is the *target* side. In `_ready()` it connects `area_entered`; when an overlapping area is a `HitBox` (and passes the optional `accepted_damage_types` filter), it re-emits `received_damage(damage)`. Filtering by type is via the exported `accepted_damage_types: Array[HitBox.DamageType]` (empty = accept all).

Collision wiring: set the `HitBox`'s `collision_layer` to a "damage" layer and leave its mask empty; set the `HurtBox`'s `collision_mask` to scan that same layer. Only `Area2D`↔`Area2D` overlap is detected — `HurtBox` ignores non-`HitBox` areas. The damage path is **HitBox overlaps HurtBox → `HurtBox.received_damage` → your handler (or `DamageReaction`) → Shield/Health**.

Geometry: a `HurtBox` should **cover** the body `CollisionShape2D` the entity collides with. Armour and invulnerability are damage *rules* applied in the `received_damage` handler — deflect, flash, report 0 — never a shrunken or absent hurtbox, which leaves visible hull that swallows shots and reports nothing (it reads to the player as a broken gun, not as armour, and it silently disables the two systems that drive `received_damage` with no physics at all). `tests/integration/test_enemy_hurtbox_geometry.gd` sweeps every assault entity and fails the gate on a hurtbox that stops covering its body.

```gdscript
# On the target entity:
@onready var hurtbox: HurtBox = $HurtBox
func _ready() -> void:
    hurtbox.received_damage.connect(_on_hit)
func _on_hit(damage: int) -> void:
    health.decrease(damage)   # or route through DamageReaction (below)
```

### CollisionLayers — `global/physics/collision_layers.gd`

`CollisionLayers` (`class_name CollisionLayers extends RefCounted`, constants only) names every
physics layer bit the project uses, mirroring `project.godot [layer_names]` exactly: one constant
per named `2d_physics/layer_N`, equal to `1 << (N - 1)`. Layer numbers and every scene's authored
`collision_layer`/`collision_mask` values are unchanged — this only gives code a name to write
instead of a magic number.

| Constant | Value | `project.godot` name |
|---|---|---|
| `ENVIRONMENT` | 1 | `environment` |
| `ENVIRONMENT_INTERACTABLE` | 2 | `environment_interactable` |
| `ENVIRONMENT_PLAYER` | 4 | `environment_player` (typo `environemnt_player` fixed) |
| `PICKUPS` | 16 | `pickups` |
| `PLAYER_ROCKETS` | 32 | `player_rockets` |
| `PLAYER_HITBOX` | 64 | `player_hitbox` |
| `PLAYER_HURTBOX` | 128 | `player_hurtbox` |
| `ENEMY_HITBOX` | 256 | `enemy_hitbox` |
| `ENEMY_HURTBOX` | 512 | `enemy_hurtbox` |
| `HAZARD_CONTACT` | 1024 | `hazard_contact` |

Bit 4 (value 8) is deliberately unnamed and unused; no layer is allocated until something uses it
(e.g. `area_control`, 2048, planned for the gravity-well phase). `tests/integration/
test_collision_layer_names.gd` sweeps every `.tscn`/`.tres` outside `addons/` for a
`collision_layer`/`collision_mask` value and fails the gate if any set bit has no name in
`project.godot`, and separately asserts every named layer has a matching `CollisionLayers`
constant of the right value.

### DefenseProfile — `defense_profile.gd`

`DefenseProfile` (`class_name DefenseProfile extends Node`) is per-instance data for what a
`HurtBox` accepts, replacing a hardcoded mask assignment. A `Node`, not a `Resource`, because
armour state is runtime state that must be per-instance — a shared `Resource` would leak one
instance's "armour stripped" flip to every instance using it, the same trap `ShipConfig.privatise()`
exists to avoid.

Exports `accepts_player_bullets` / `accepts_player_rockets` / `accepts_environment` /
`accepts_hazard_contact` (all default `true`) and `accepted_damage_types: Array[HitBox.DamageType]`
(default empty = accept all). `mask()` folds the four flags into a `CollisionLayers` bitmask (all
four true = 1121: `PLAYER_HITBOX | PLAYER_ROCKETS | ENVIRONMENT | HAZARD_CONTACT`). `apply_to(hurt_box)`
writes `mask()` and `accepted_damage_types` onto a `HurtBox` and remembers it for later.

`apply_alternate()` is a **one-way** switch to a second flag set (`alternate_accepts_*`, same
defaults) and re-applies to the last `HurtBox` passed to `apply_to()` — exactly the ram ship's
"armour breaks on the first missile hit and never re-forms" rule, and no more. There is no way
back to the primary flags once switched.

`BaseEnemy._ready()` resolves a `DefenseProfile` child by type if the scene authored one (e.g.
`ram_ship.tscn`, whose profile gives 33 — rockets + environment — with the alternate 97 applied in
`RamShip._enter_damaged_state()`), otherwise creates a default one on the fly (mask 1121, so no
scene needs editing) and exposes it as `defense_profile` for a subclass to call `apply_alternate()`
on. `StationTurret` (a plain `Node2D`, not a `BaseEnemy`) reproduces the default mask by hand
through the same `CollisionLayers` constants rather than using a profile, since it has nothing to
resolve one for it.

```gdscript
# Scene-authored two-state armour (see ram_ship.tscn / ram_ship.gd):
@onready var defense_profile: DefenseProfile = $DefenseProfile   # or BaseEnemy.defense_profile
func _enter_damaged_state() -> void:
    defense_profile.apply_alternate()   # one-way; re-applies to the HurtBox automatically
```

### ContactProfile and ContactBlast — `contact_profile.gd`, `contact_blast.gd`

`ContactProfile` (`class_name ContactProfile extends Node`) is the offensive twin of `DefenseProfile`:
per-instance data for what **touching** an enemy does. `BaseEnemy._ready()` resolves a scene-authored one by
type, otherwise creates a default, exposes it as `contact_profile`, and calls
`setup(self, contact_hit_box, health)` (the hitbox may be null — the Bonus Drone has none).

| `mode` | `ContactHitBox` | On a registered touch |
|---|---|---|
| `NONE` | disabled | nothing |
| `COLLISION` (default) | **never touched** — every legacy enemy keeps its hitbox exactly as authored | `contact_made(area)` |
| `RAMMING` | on only while armed | `contact_made(area)` |
| `EXPLOSIVE` | on only while armed | `contact_made(area)`, then `detonate()` |

- **Damage is always the hitbox's own `damage`** (`config.collision_damage`); "ramming only hurts while
  committed" is full damage while armed and none at rest.
- `set_armed(bool)` (RAMMING / EXPLOSIVE only; a no-op otherwise) toggles `monitorable` + `monitoring` with
  `set_deferred`, so it is legal from a physics callback. Arming while already overlapping the player registers
  exactly one hit (pinned engine behaviour). `BaseEnemy.suspend_ai()` arms the profile, so a rail-driven enemy hurts
  on contact.
- EXPLOSIVE also detonates when the owner's `Health` (the one passed to `setup()`) reaches 0 **while armed**; dying
  unarmed never detonates. `detonate()` is idempotent and emits `detonated(position)` once.
- The blast is a `ContactBlast` (`extends HitBox`, layer 256, mask 0, CONTACT damage, circle of `blast_radius`) built
  by `ContactBlast.spawn(container, at, radius, damage, frames)` into the **owner's parent**, at the owner's global
  position, so it outlives the owner (same reason as `ExplosionEffect`). It parents itself through a deferred call
  on the blast (safe inside `area_entered`; frees itself if the container is gone first), stays live for
  `blast_frames` physics frames (default 3, clamped to ≥ 2 with an error) on its own counter — never
  `create_timer` — and then frees itself. The player's `HurtBox` (mask 1281) takes it like an enemy bullet.

```gdscript
# Scene-authored: add a ContactProfile child to the enemy's .tscn, then from the brain:
contact_profile.set_armed(true)     # entering the committed attack state
contact_profile.set_armed(false)    # leaving it
contact_profile.contact_made.connect(func(_a: Area2D) -> void: health.set_health(0))  # a drone that dies on impact
```

### SquadController — `squad_controller.gd`

`SquadController` (`class_name SquadController extends RefCounted`) is a **role board, not a
mover** — it holds `LEAD` / `FLANK_LEFT` / `FLANK_RIGHT` / `REAR` assignments for a group of
`Node2D` members and moves nothing itself, so it never touches the single-writer gate. It is
**event-driven**: roles are recomputed only inside `join()`, `leave()` and `release_lead()` —
there is no clock and no `_process`.

- `join(member)` / `leave(member)` (explicit and idempotent — rail suspension calls `leave()`
  directly, same as a free) / `role_of(member)` / `members()`.
- **Assignment is a full recompute every time**, not an incremental fill: on any join/leave/
  release it re-sorts every current member by distance to `target_position_hint` (ties by join
  order) and reassigns LEAD/FLANK_LEFT/FLANK_RIGHT/REAR from scratch. LEAD always goes to
  whoever is currently closest — "the closest steals the token" is a **steady-state property**,
  not a one-time election. `release_lead(member)` is the one exception: it pins the releasing
  member to REAR for that call only, so a plain recompute cannot just re-elect the same member
  and stall the rotation.
- `update_target(position, heading)` is how members report `TargetInfo` to the board each tick
  (`target_position_hint` / `target_heading_hint`); left/right is the sign of
  `heading.cross(member_pos - position)`, falling back to the squad-centroid → target direction
  when the heading is zero.
- `claim_side(member, preferred: int)` / `release_side(member)` hand out one of four sectors
  (`Side.LEFT/RIGHT/FRONT/BACK`, relative to the target's heading) so two attackers don't
  converge on one point; if every sector is taken, the preferred one is shared. **`claim_side`
  and `role_changed` pass `Side`/`Role` as plain `int`, not the enum type** — Godot 4.6's static
  checker treats `SquadController.Side` named from outside the script as a different type from
  `Side` named from inside, so a caller passes `SquadController.Side.LEFT`-shaped values and
  compares/keys on the underlying int.
- `set_engaged(member, on)` / `is_engaged()` is shared *state*, not a message: it is how a whole
  hub squad wakes and returns together (§*AnchorIdle* below and
  [assault.md](assault.md) → *Enemy AI in Assault*). `attack_window_open` is set by the current
  LEAD entering its committed state so FLANKs know to start their own wind-up, and is cleared
  automatically whenever `_reassign()` changes who holds LEAD — not just on a clean end-of-burst.
- **Membership is weak** (`is_instance_valid`, pruned on every read) and **members hold the only
  strong reference to the board** — `join()` connects `member.tree_exiting -> leave(member)`, but
  that connection does not itself keep a `RefCounted` alive in this Godot version, so the board
  dies once every member drops its own reference. A caller that wants to keep a board across
  spawns (`WaveManager`, see [assault.md](assault.md) → *Wave / spawn system*) must store only a
  `WeakRef`.
- Brains read it through a duck-typed `actor.squad` property; `null` means "a squad of one".
  `EnemyBrain` itself gained nothing — this is entirely a brain-side convention.

### AnchorIdle — `anchor_idle.gd`

`AnchorIdle` (`class_name AnchorIdle extends RefCounted`) is the **generic idle-around-an-anchor
→ combat handover** any brain can own — it decides *when* to fight, never *how to move*:

```
var state := anchor_idle.update(delta, actor.global_position, TargetInfo.player(tree))
# state is IDLE / NOTICING / COMBAT / RETURNING (int, same int-boundary reason as SquadController)
```

- **Two radii give hysteresis on purpose:** IDLE → NOTICING → COMBAT at `perceive_radius`;
  COMBAT only drops to RETURNING beyond the larger `lose_radius`, so a target drifting back and
  forth across `perceive_radius` alone never flips state. Construction rejects
  `perceive_radius >= lose_radius` (`push_error`, then `lose_radius = perceive_radius * 1.25`).
  RETURNING reaches IDLE within `home_radius` of `anchor` (the idle ring's own radius, not the
  anchor point) and re-enters NOTICING if the target comes back inside `perceive_radius`.
- `hold_combat` is an external reason to keep fighting (a squad mate is still engaged) — while
  true, COMBAT never drops to RETURNING regardless of distance. `force_notice()` moves IDLE or
  RETURNING straight to NOTICING (a squad mate perceived first).
- **It never snaps a velocity.** The handover is a state change only; the brain's own request and
  the mover's `acceleration`/`braking` produce the actual turn. Idle ticks are a squared-distance
  check only — no `TargetInfo` prediction, no squad query — so idling is cheap.
- **Assault skips it entirely:** a brain in a world with a provider (`EnemyWorld.arena(tree) !=
  null`) starts straight in combat, because the level has already decided the fight is on.
- The idle *motion* (the ring's drift, brakes, reversals, boosts) is the brain's own request, not
  `AnchorIdle`'s — see [assault.md](assault.md) → *Enemy AI in Assault* and each drone's
  `ENEMY.md` for the exact per-enemy shape.

### StateLight — `state_light.gd`

`StateLight` (`class_name StateLight extends Node2D`) is the **one small light** an enemy shows
to telegraph its own attack intent (IDEAS §21.1 — one gameplay light per state, never a recoloured
hull): `set_state(OFF | ARMED | CHARGING | COMMIT)` maps to invisible / red / yellow / white, and
`blink_once()` flashes CHARGING for `BLINK_SECONDS` then restores whatever state was active
before the call (used for a NOTICING beat, which is not a threat level of its own). Its texture is
a radial `GradientTexture2D` **built in code in `_ready()`**, 8×8 px, white fading to alpha 0 at
the edge — never scene-authored, so `test_entity_sprite_transparency.gd`'s `.tscn` sweep never
sees it; the state colour lives entirely in `modulate`, capped at `MAX_ALPHA = 0.85` so a
projectile stays the most vivid thing on screen. Brains resolve it duck-typed
(`actor.get_node_or_null("StateLight")`). **`COMMIT` (white) is exclusive to a real, committed
attack — a feint may only ever show CHARGING**, so the white flash is the one moment worth
reacting to.

### AttackController — `attack_controller.gd` (extended for the enemy AI stack)

`AttackController` (`class_name AttackController extends Node`) drives an `AttackPatternResource`
on a timer; add it as a child of any ship with `pattern` and `bullet_pool` set. Two exports beyond
the original per-ship timer: `enabled: bool = true` is a **hold-fire switch** — while `false` the
fire-interval timer keeps running and wrapping, but the shot itself is withheld, so re-enabling
mid-interval never fires early or double-fires; `driven_by_brain: bool = false` hands the timer to
the owner — `_process` becomes a no-op and something else (an `EnemyBrain`) must call `tick(delta)`
itself, on the same clock as its own AI tick. Existing timer-driven users leave both at their
defaults and are unaffected. `fire_now()` fires immediately regardless of the timer's phase, for a
telegraphed shot the caller triggers directly — it ignores `enabled` and never touches the timer.

`aimed_attack_pattern.gd` and `gatling_attack_pattern.gd` both add `accuracy: float = 0.0` and aim
through `TargetInfo.player(ship.get_tree()).aim_direction(ship.global_position, bullet_speed,
accuracy)` instead of aiming straight at the player. `accuracy = 0.0` (every shipped pattern's
default) reproduces today's direct aim exactly; `1.0` aims at the full lead/intercept point. See
`TargetInfo.aim_direction` below.

Both patterns also carry `aim_point: Vector2 = Vector2.INF` — when finite (`.is_finite()`), the
shot aims there instead of querying `TargetInfo` (a squad's shared convergence point); a per-instance
`rng: RandomNumberGenerator = null` — `null` (every existing consumer) draws jitter from the global
`randf_range`, as before; and `AimedAttackPattern` gained `spread_angle: float = 0.0` (Gatling
already had it), so both patterns jitter the same way. Their non-aimed (`aim_at_player = false`)
branch is `Vector2.RIGHT.rotated(ship.rotation + EnemyMover.sprite_forward_angle_of(ship))` — equal
to the legacy `Vector2.DOWN.rotated(ship.rotation)` only when the actor's `sprite_forward_angle` is
the default `PI/2`, and correct for any other value (see "Facing, one rule" below).

### Enemy AI — `enemy_brain.gd` + `enemy_mover.gd` (`global/enemy_ai/`)

An AI-driven enemy is a `BaseEnemy` with two extra children, both resolved **by type** in
`BaseEnemy._ready()`: an `EnemyBrain` subclass (decides) and an `EnemyMover` (moves).
`BaseEnemy._physics_process` is the one clock: `brain.tick(delta)` then `mover.step(delta)`, once per
physics frame. With no brain it returns immediately, so every legacy enemy is unchanged (the ones with
their own `_physics_process` replace it outright — GDScript does not chain callbacks).

```
# my_enemy.tscn
MyEnemy (CharacterBody2D, my_enemy.gd extends BaseEnemy)
├── Health / HurtBox / HitFlashAnimationPlayer    # as every BaseEnemy
├── EnemyMover        # max_speed, acceleration, braking (0 = acceleration), turn_lerp,
│                     # max_turn_rate (rad/s, 0 = off), constraint_mode AUTO | NONE
└── Brain (my_enemy_brain.gd extends EnemyBrain)  # rng_seed export (0 = randomize)

# my_enemy_brain.gd
func tick(delta: float) -> void:
	var player := TargetInfo.player(get_tree())     # perception only through TargetInfo
	_clock += delta                                  # accumulated delta, never a Timer
	if player.has_target:
		mover.orbit(player.position, 130.0, _angle, 350.0)  # one primary request per tick
		mover.face_toward(player.position)
```

- **Requests are per step.** `request_velocity()` (or a `Steering` wrapper: `seek`, `arrive`, `orbit`,
  `intercept`, `retreat_from`, `evade`, `strafe`, `hold_position`, `drift`, `spiral`, `corkscrew`,
  `formation_slot`) is the one primary request — a second call replaces it; `add_nudge()` adds an
  offered correction (flocking's `separation`/`alignment`/`cohesion`, capped at a fraction of
  `max_speed` — there is no weighted blend of every term into the primary request); `face_toward()`
  overrides the heading; all three clear after `step()`. `boost(dir, speed, duration)` overrides
  requests and limits for `duration`; `halt()` stops dead. `clamped_lead_time(distance, speed,
  t_min, t_max)` is the pure `clamp(distance / speed, t_min, t_max)` behind a prediction window
  (e.g. the Swarm Drone's 0.4–0.8 s ram lead).
- **`EnemyMover.max_turn_rate` only turns the sprite — it never bends the path.** `step()` sets
  `velocity` by `move_toward` toward the requested vector and applies `max_turn_rate` to
  `rotation` alone, so a brain that wants an actual curved path (an overshoot after a missed
  attack, a wide turn-back) must build it itself with **`Steering.turn_toward(current_dir,
  desired_dir, max_rate, delta)`**, called every tick from the actor's *current* velocity — never
  from the brain's own last request, which would let the curve run away from what the mover can
  actually follow. Because `move_toward` only ever moves the velocity along the straight segment
  from where it is to what was just requested, the true heading turns by at most `max_rate·delta`
  per tick, which is the bound every curving enemy's test asserts. A config that curves must pin
  `turn_rate × speed ≤ acceleration` so the mover's own accel/braking can keep up with the
  request — see `swarm_drone/ENEMY.md` and `razor_drone/ENEMY.md`'s OVERSHOOT sections for the
  worked numbers.
- **Facing, one rule:** `rotation → heading.angle() - sprite_forward_angle`, heading = the face
  request or the velocity; `sprite_forward_angle` is read duck-typed off the actor (default `PI/2`)
  through the one shared reader, the public static `EnemyMover.sprite_forward_angle_of(node)` —
  `EnemyPathMover`'s own facing, and both `AimedAttackPattern`/`GatlingAttackPattern`'s forward
  (non-aimed) fire direction, call the same function instead of duplicating the duck-typed read, so
  a shot fired "forward" always leaves the actor's actual nose, whichever way its sprite was drawn.
- **Constraint:** `AUTO` asks `EnemyWorld.movement_constraint(tree)` once in `_ready()` (none in
  Open Space); `NONE` never asks; a `constraint` set before `add_child` wins.
  `MovementConstraint.inner_rect()` returns the region a brain may treat as "inside the fight"
  without naming the mode's provider — an empty `Rect2()` (the identity) means "unbounded";
  `AssaultCorridorConstraint.inner_rect()` returns its own visible rect, so a brain can keep an
  orbit or hold-position centre clear of the corridor's edge pressure. `mover.release_constraint()`
  drops the constraint for good (a field write, not a motion write — see the Assault exit below).
- **Single writer:** with a mover present, nothing else writes the body's `velocity`/`rotation` or
  calls `move_and_slide()` — gated by `tests/integration/test_enemy_mover_single_writer.gd`.
- **Rails override it:** `EnemyPathMover._ready()` calls `suspend_ai()` (brain `on_suspended()`, mover
  `halt()`, no more ticks) *in addition to* its unconditional `set_physics_process(false)` and
  `"AIStateMachine"` lookup. A `driven_by_brain` `AttackController` stops with the brain.
- Contract tests: `tests/unit/test_enemy_mover.gd`, `tests/integration/test_enemy_brain_contract.gd`;
  fixture enemy: `tests/helpers/fixture_enemy.tscn`.

**`EnemyWorld` (`enemy_world.gd`, static-only `RefCounted`) is the one lookup of the Assault-vs-Open-Space
mode provider.** The provider is whatever node has joined group `&"assault_arena"` (today, only
`ArenaCamera` — see [assault.md](assault.md) §"Enemy AI in Assault"); `EnemyWorld` is the only file
project-wide that looks that group up, and it does so duck-typed (`has_method`), so nothing under
`global/` names the Assault-only `ArenaCamera` class. With no provider, the mode is Open Space:
every `EnemyWorld` getter returns empty/null. `arena(tree)` returns the provider node or `null`;
`projectile_world_rect(tree)`, `cull_rect(tree)` and `movement_constraint(tree)` each have a
`has_*` companion, because an absent result and a legitimately empty `Rect2()` are not
distinguishable by value alone. `EnemyMover`'s `AUTO` constraint mode and `ProjectileLifetime`
(below) are its two callers; tests inject a rect/constraint directly instead of building a provider.

**`TargetInfo` (`target_info.gd`, `RefCounted`) is the one way new code finds or predicts the
player** — a snapshot (`position`, `velocity`, `facing`, `has_target`) taken once, so reading it
after the source node is freed is safe. `TargetInfo.player(tree)` is the resolver (replaces
scattered `get_nodes_in_group("player")[0]` calls); `TargetInfo.of(node)` snapshots any `Node2D`.
`intercept(from, shot_speed)` is a closed-form quadratic solve returning `{ok, point, time}` — `ok`
is `false` with no target, a non-positive `shot_speed`, or no `t >= 0` solution (the target outruns
the shot). `aim_direction(from, shot_speed, accuracy)` blends direct aim at `position` (`accuracy
0.0`) with the intercept point (`1.0`), clamped, falling back to direct aim whenever `intercept`
fails — this is what `AttackController`'s aimed/gatling patterns call (above). `line_of_sight()` is
a stub that always agrees with `has_target`; the real raycast is a later phase.

**`EngagementBudget` (`engagement_budget.gd`, `RefCounted`) is how an Assault AI enemy leaves the
arena in time for an `ENEMIES_CLEARED` section to advance**, rather than living until killed —
`AssaultCorridorConstraint` otherwise forces it to keep re-entering forever. A brain constructs one
with `EngagementBudget.new(seconds, tree)`: `active` resolves once, from `EnemyWorld.arena(tree)
!= null`, so it is only ever true in Assault — in Open Space `update(delta)` is a permanent no-op
and always returns `false`, and the same brain runs there without an exit. The brain calls
`update(delta)` every tick from its first one (the spawn frame); the first `true` is the signal to
enter a DISENGAGE-style state: call `mover.release_constraint()`, raise `mover.max_speed` to an
exit speed, `seek()` the nearest point outside `EnemyWorld.projectile_world_rect()`, and free the
actor once outside that rect (strict compare, as `EnemyPathMover._check_dash_end()` does). Scoring
is unchanged — the actor leaves with `was_killed == false`, counted as an escape.
`remaining()` returns the seconds left (`INF` when inactive); the Swarm Drone reads it to never start
an attack it cannot finish before expiry, so its exit always begins exactly at `seconds`.
`tests/integration/test_engagement_deadline.gd` pins the arithmetic that keeps this from stalling a
level: for every drone/razor spawn in every `ENEMIES_CLEARED` section, the worst-case time from
`waves_complete` to that enemy leaving the level must clear the section's own
`enemies_cleared_timeout`. Each kind is judged by its own config: the Razor Drone, which defers its
expiry through a dash, has a longer formula, and a boundary case asserts a Razor placed in
cloud_descent would miss the timeout (Razors spawn only in DURATION sections).

**`BurstClock` (`burst_clock.gd`, `RefCounted`) counts down a fixed-size, evenly-spaced burst of
shots — no node, no `Timer`.** A brain calls `start(count, gap)` once, then `advance(delta) -> int`
from its own tick, firing `attack.fire_now()` once per shot the call reports due; the burst's size
is exact even across a long frame, because `advance()` never reports more shots due than remain in
the burst, however large `delta` is. The first shot is due immediately on the first `advance()`
call, whatever `delta` is — the internal clock starts pre-loaded with `gap`. Time accumulates with
subtract-not-reset, the same overshoot-preserving rule `AttackController.tick()` uses. `is_running()`
reports whether shots remain; `stop()` ends the burst early. `shots_fired` is a running count, reset
by `start()`. Has no consumer yet this phase (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.3);
the Fighter and Gatling Interceptor brains, landing later in the same phase, are its first callers —
an exact 3–5 / 5–7 / 8–12-round burst instead of a free-running interval timer.

### ProjectileLifetime — `projectile_lifetime.gd`

`ProjectileLifetime` (`class_name ProjectileLifetime extends Node`) is a projectile's world-space
lifetime: add it as a child of the projectile (the "host"). Three independent rules, each disabled
at its zero default: `max_time` (seconds since arming), `max_distance` (px from the origin — the
point where it armed, not the owner, which may move or die), and `use_world_rect` (expire on
leaving the mode's rect, via `EnemyWorld.projectile_world_rect()` — a no-op in Open Space or on any
Assault camera that is not a provider). It never frees anything itself: the first rule that trips
emits the host's `expired` signal exactly once (duck-typed via `has_signal("expired")`, so it has
no dependency on `EnemyBullet`) and latches until the next `reset()`. A pooled bullet recycles
through its pool's `expired` connection; an unpooled one frees itself through its own `expired ->
queue_free` wiring. `expire_now()` is an immediate, explicit trip through the same latch.

**It arms lazily** — on `reset()`, or on its own first physics tick, whichever comes first, never
in `_ready()` — because an unpooled projectile positioned at its muzzle only *after* `add_child()`
(the sniper shot, `sniper_enemy.gd`) is never `reset()`; arming in `_ready()` would record the
wrong origin and never resolve the rect. `EnemyBullet` carries one with derived defaults
(`max_time = 18 s`, `max_distance = 2400 px`) that reproduce its old hardcoded arena-bounds check
exactly against every shipped enemy-bullet speed; a new, slower bullet source must be added to
`tests/integration/test_enemy_bullet_lifetime.gd`'s source list and the defaults re-derived.
`persist_after_owner_death` is documented only in Phase 1 — a future flag for `BulletPool` to skip
`cancel_active()` on a flagged projectile.

### Shield — `shield_component.gd`, `bubble_shield.tscn`, ordering in `damage_reaction.gd`

`Shield` (`class_name Shield extends Node`, child named `ShieldComponent`) is a *discrete-charge* shield: each charge absorbs one whole hit regardless of damage. Exports: `max_temporary: int = 5`, `bind_progression: bool = false`, `permanent_charges: int = 1` (range 0..10). When `bind_progression` is true the permanent count comes from `ShipProgressionState` and tracks it; otherwise it uses `permanent_charges` (use this for racers/generic ships to avoid the autoload dependency). Key API: `consume_one() -> bool` (temp stack first, then permanent; returns true if a hit was absorbed), `add_temporary()`, `restore_all_permanent()`, `set_all_zero()`, `set_hacked(bool)`. Permanent charges regenerate one per `REGEN_INTERVAL_SEC = 5.0` of no damage. Emits `shield_state_changed(snapshot)` (keys `perm_active`, `perm_max`, `temp_count`, `hacked`) and `shield_pickup_collected`.

The visual `bubble_shield.tscn` (`BubbleShield extends AnimatedSprite2D`, animations `shield_idle` / `shield_pick_up` / `shield_break`) is wired automatically by `PlayerBase._setup_bubble_shield()` — it instantiates the scene under `SpriteAnchor` and calls `setup(shield_component)`. Do not add it manually.

Ordering: in `DamageReaction._on_received_damage` the sequence is **on_hit hook → flash → `shield.consume_one()` (return if absorbed) → `health.decrease()`**. In `PlayerBase._apply_damage` it is **invincibility check → `shield.consume_one()` → `temp_health.take_damage()` → `health.decrease()`**, with `damage_reduction` applied only against Health.

```gdscript
shield.consume_one()        # returns true and pops one charge if any available
shield.add_temporary()      # pickup adds a temp charge (false if at cap)
```

### DamageReaction — `damage_reaction.gd`

`DamageReaction` (`class_name DamageReaction extends Node`) is the drop-in "ship takes a hit" router for *generic* destructible ships. Add it as a child, then call:

```gdscript
# setup(health, shield, hurt_box, sprite)
@onready var reaction: DamageReaction = $DamageReaction
func _ready() -> void:
    reaction.setup($HealthComponent, $ShieldComponent, $HurtBox, $Sprite2D)
    reaction.on_hit = func(dmg): top_speed *= 0.9   # optional per-hit hook
    reaction.died.connect(_on_died)
```

`setup(health, shield, hurt_box, sprite)` connects `hurt_box.received_damage → _on_received_damage` and `health.amount_changed → _on_health_changed`, and creates an internal `ExplosionEffect`. On a hit it runs the optional `on_hit: Callable`, flashes `sprite` to `flash_color` (export, default `(1,0.4,0.4,1)`) over `flash_time` (`0.18`), consumes a shield charge if present, else decreases health. When health hits 0 it emits `died`, explodes, and frees the parent. Pass `null` for `shield` if the ship has none.

### Overheat — `overheat_component.gd`

`Overheat` (`class_name Overheat extends Node`, child named `OverheatComponent`) tracks weapon heat. Exports: `heat_limit: float = 20.0`, `cooldown_time: float = 10.0`. Call `increase_heat(amount)` on each shot; heat dissipates in `_physics_process` after a `_SHOOT_GRACE = 0.5 s` grace window with no shots. Emits `overheat(percentage)` (0–100). `PlayerBase._on_overheat_updated` forwards it to `EventBus.player_overheat_changed`.

```gdscript
@onready var overheat: Overheat = $OverheatComponent
func _on_shot_fired() -> void:
    overheat.increase_heat(2.0)   # heat per shot
```

### State machine — `state_machine.gd` + `state.gd`

`State` (`class_name State extends Node`) is the base contract: override `enter()`, `process_physics(delta)`, `exit()`, and emit `state_transition(next_state)` to request a change. `StateMachine` (`class_name StateMachine extends Node`) holds an exported `initial_state: State`. In `_ready()` it connects every child `State`'s `state_transition` signal to `change_state`, then enters `initial_state`. Each `_process(delta)` it calls `current_state.process_physics(delta)`. `change_state` ignores a transition to the same/null state, else calls `exit()` on the old (skipped when the machine is still idle, i.e. built with no `initial_state`) and `enter()` on the new. Its transition tracing is behind `OS.is_stdout_verbose()`.

Convention: states are child nodes of the `StateMachine` node; the **initial state is whatever the `initial_state` export points at**; per-entity state classes live in that entity's own folder (e.g. an `idle_state.gd` / `move_state.gd` / `dash_state.gd` set next to the player scene), each `extends State`.

```gdscript
# move_state.gd
extends State
func process_physics(delta: float) -> void:
    if Input.is_action_just_pressed("dash"):
        state_transition.emit(get_parent().get_node("DashState"))
```

### Ship modules — `ship_module_base.gd`, the 15 modules, `ship_module_state.gd`

> **Full per-module roster:** [`global/ship_modules/SHIP_MODULES.md`](../../../global/ship_modules/SHIP_MODULES.md) — id, class, slot, type, and effect for every module.

A *module* is a `RefCounted` strategy object (not a node) that mutates the player on equip. `ShipModuleBase` defines the contract and a central `static func create(id) -> ShipModuleBase` registry. Override points: `get_display_name`, `get_description`, `get_icon`, `get_slot` (`cockpit`/`armor`/`weapons`/`engines`), `apply(player)` (on equip), `remove(player)` (on unequip/scene change), `try_activate(player) -> bool` (H-key for active modules), `tick(player, delta)` (per-frame for the equipped active module, e.g. cooldown/expiry), `can_activate() -> bool` (report readiness *without* spending anything — mirrors `try_activate()`'s own guard, defaults `false`), and `is_open_space_boost_verb() -> bool` (defaults `false`; `true` marks a module as the open-space Shift boost's own upgraded tier, currently only `EngineBoostModule` — see below). Passive modules (e.g. `ArmorPlatingModule` adds +40 HP and +0.25 `damage_reduction`) only override `apply`/`remove`; active ones (e.g. `TrajectoryCalcModule`, `EMPBlastModule`) implement `try_activate`/`tick`.

**`EngineBoostModule` is the one module `OpenSpacePlayerShip` treats specially.** Equipping it into `&"engines"` re-partitions the ship's `BoostMeter` from one continuous bar (`tanks = 1`) into 3 discrete tanks (4 once `ShipProgressionState.boost_charge_count` is maxed) — `OpenSpacePlayerShip._update_boost_tanks()`, called from the existing `module_equipped`/`module_unequipped` wiring, so the tier switch needed no new state. With it equipped, Shift (`_step_boost()`'s press branch) stops running the default hold-to-boost model and instead spends one tank (`BoostMeter.try_spend_tank()`) to fire the module's own burst — gated on `can_activate()` *before* the spend, so a press during the module's 2 s cooldown costs nothing (the module's own retrigger floor is shorter than the ship's, so spending first would burn a tank for an activation that was always going to refuse). `is_open_space_boost_verb() == true` is also what makes `OpenSpacePlayerShip._input`'s H-key loop skip this module in open space — Shift already pays for the same burst there, so leaving H wired would fire it for free; `AssaultPlayer`'s own H loop does not consult this at all, so Boost Drive still fires on H in assault, where there is no Shift boost to conflict with.

`ShipModuleState` persists which module id is equipped/unlocked per slot (`SLOT_MODULES` lists the valid ids; the registered ids are: cockpit `trajectory_calc`/`emp_blast`/`ai_targeting`/`cockpit_heal`; armor `armor_plating`/`parry`/`shield_overload`/`final_resort`; weapons `overclock`/`plasma_nova`/`overheat_nullifier`/`pierce`/`shooting`; engines `warp`/`engine_boost`). All 15 module scripts are registered in `create()` (one class per id).

**The unlock gate.** `equip(slot, id)` validates the slot, then the catalogue, then `is_unlocked(slot, id)` — a module the player has not recovered cannot be installed. `&""` (unequip) is exempt at every layer, so a slot can always be cleared; a gate that could trap a module in a slot would be worse than no gate. `ShipModuleUnlockerPickup` is the only writer of the unlock store, and the sector hub carries one unlocker for every module (see [`open_space.md`](./open_space.md)). `_load()` grandfathers a module that is equipped but not unlocked — that is every save written before the gate existed — appending it to the slot's unlocked list rather than confiscating a loadout the player is flying with; the append is guarded on `!= &""` and `not in list`, so it neither pollutes the store with the `&""` sentinel nor duplicates on every boot.

In the ship menu, `ModuleList` shows locked modules greyed rather than hiding them, prefixes their description with `LOCKED — recover this module's unlocker to install it.`, and makes `confirm()` a defined no-op on a locked row — the same shape `MissionSelectMenu` already uses for a locked mission. Row 0 (`&""`/None) is never locked.

### Lore Logs reader — `pause_menu/lore_log_list.gd` (`LoreLogList`), `lore_log_list_item.gd`

A fourth `PauseMenu` option (`Option3`, present in both `mission_mode` states) opens a full-catalogue
reader over `LogState`: every entry from `LogState.all_ids()` gets a row in catalogue order, found
ones show their real title and — once the cursor lands on them — their full body, unfound ones show
a `???` title and a locked placeholder body. The header reads `Lore Logs — <collected> / <total>`.
It reuses `ModuleList`'s locked-row modulate language (`LoreLogListItem` — title only, no icon, no
equipped tint, since nothing here is ever installed) but **pages instead of truncating**:
`ModuleList.MAX_ITEMS = 8` silently drops any row past the 8th, which is fine for a module slot list
that never grows past a handful of options but wrong for a log catalogue expected to outgrow one
screen. `LoreLogList.PAGE_SIZE = 8` instead splits the catalogue into fixed-size pages —
`menu_left`/`menu_right` change page (header appends `(Page P/N)` when there's more than one),
`menu_up`/`menu_down` move the cursor within the current page. There is no separate "confirm to
read" step; navigating already reveals a row's body, the same way `ModuleList._refresh_cursor()`
shows a hovered row's description.

`PauseMenu` owns opening/closing it directly (`_lore_logs_open: bool`, mirroring
`PlayerMenu._module_list_open`) rather than the reader emitting a `closed`/`cancelled` signal:
while it's open, `_unhandled_input` routes `menu_up/down/left/right` to the reader and absorbs
everything else (`menu_confirm` included — it must never fall through to `_confirm()` and
re-trigger `_lore_log_list.open()`), and `ui_cancel` closes the reader back to the option list
instead of closing the whole pause menu.

### Settings panel — `pause_menu/settings_panel.gd` (`SettingsPanel`)

`Option4` = **Settings**, which opens a second sub-overlay with exactly the same
`open()`/`close()`/`navigate(dir)` shape as `LoreLogList` and the same routing rules
(`_settings_open: bool`; while open `_unhandled_input` absorbs **all** menu input, `menu_confirm`
included, and `ui_cancel` returns to the option list rather than closing the pause menu). It adds
one verb the reader does not have: `cycle(dir)`, bound to `menu_left`/`menu_right`.

Settings was **appended before Exit Game, not inserted elsewhere**, so Exit Game stays last where a
player expects it — which moved Exit Game from `Option4` to **`Option5`** in both
`pause_menu.tscn` and `open_space_pause_menu.tscn` (the two scenes duplicate their option nodes
rather than sharing them, and their row geometry differs: mission rows sit at
`110/178/244/310/376/442` under a container at `y = 184`, open-space rows at `112/—/—/178/244/310`
under a container at `y = 226`, with `Option1`/`Option2` bare `Node2D`s carrying no `Label` child
at all — never loop `get_node("Label")` over `_options` in that scene).

One row today — **Open-Space Steering: Mouse Aim / Classic (A/D)** — cycling straight into
`SettingsState.set_open_space_scheme()`, which owns validation, persistence and the change signal.
`_refresh()` re-reads the store on every `open()` and every `cycle()` rather than caching, because
the panel is built with the pause-menu scene long before anyone opens it. A second row is another
entry in `_rows` plus another branch in `cycle()`; there is deliberately **no generic settings
framework**, which for a single two-valued key would be pure churn.

The row is shown in **all three modes**, not just open space: it is a stored preference, and hiding
it during a mission would mean flying back to the hub to change your controls. The label names its
scope, which is what keeps it from being a discoverability trap.

Gated by `tests/integration/test_pause_menu_settings.gd`, whose load-bearing case drives the **live**
`SettingsState` through `menu_right` — a settings row with an empty handler passes every "is it
visible and labelled" assertion, the same placement-only trap `test_weapon_unlock_sources.gd`
records for pickups.

To add a new module:
1. Create `global/ship_modules/foo_module.gd` (`class_name FooModule extends ShipModuleBase`); override `get_slot`, names/icon, and `apply`/`remove` (+ `try_activate`/`tick` if active).
2. Add a `match` arm in `ShipModuleBase.create()`.
3. Add its id to the slot's list in `ShipModuleState.SLOT_MODULES` **and** to the `ShipModuleUnlockerPickup.Module` enum.
4. Place a `ship_module_unlocker_pickup.tscn` instance that grants it. This is **not optional** since the unlock gate landed: a module with no unlocker is a row the player can see and can never install. `tests/integration/test_module_unlock_sources.gd` fails if you skip it.

```gdscript
class_name FooModule
extends ShipModuleBase
func get_slot() -> StringName: return &"weapons"
func apply(player: Node) -> void:
    player.set("damage_multiplier", player.get("damage_multiplier") + 0.2)
func remove(player: Node) -> void:
    player.set("damage_multiplier", player.get("damage_multiplier") - 0.2)
```

### Effects — `hit_effect.gd`, `explosion_effect.gd`, `thruster_effect.gd`, `low_health_smoke.gd`, `rocket_trail.gd`

All are `Node2D` wrappers around `CPUParticles2D`. Set their `@export`s *before* `add_child()` so `_ready()` reads them.

- **`HitEffect`** — one-shot burst on damage. Call `burst()` from the hit handler. Exports include `amount: int = 10`, `lifetime: float = 0.25`, `color`, velocity/scale ranges.
- **`ExplosionEffect`** — bigger one-shot burst on death; call `explode()` just before `queue_free()`. Resolves its **actor** by walking up from its own parent to the nearest `Node2D` ancestor — so it may sit under a non-`Node2D` behaviour node (`DamageReaction`) without losing its position — and spawns particles at that actor's world position, into that actor's parent by default. `explode(at, container)`: `at` (optional `Vector2`) overrides *where* the blast lands, for entities whose death is a chain of blasts across a large hull rather than one central burst (`StationDeathSequence`); `container` (optional `Node`) overrides *what it lands in*, for an actor whose default parent is not a safe home (`StationTurret`, whose particles would otherwise die with the hull or inherit its spin). Both default to the historic behaviour when omitted. A `container` that is null, freed, or outside the tree falls back to the actor's parent. If no `Node2D` ancestor exists at all, it `push_warning()`s and does nothing, rather than failing silently. `always_process: bool = false` lets the player death burst render while paused.
- **`ThrusterEffect`** — continuous engine flame. Call `set_state(state)` each physics frame with `State.{IDLE,THRUST,BOOST,POWER,BOOST_PANEL}`; transitions are instant and de-duplicated.
- **`LowHealthSmoke`** — call `setup(health)` after `add_child()`; it connects `health.amount_changed` and emits smoke automatically when HP ≤ `threshold` (default `0.3`) and `current > 0`. `deactivate()` stops it.
- **`RocketTrail`** — continuous world-space trail; add under a rocket scene. `offset_behind: float = 8.0` places it behind the nose.

```gdscript
# In an entity's _setup_effects():
var hit := HitEffect.new()
hit.color = Color(0.4, 0.8, 1.0)
add_child(hit)
# ...later, in the hit handler:
hit.burst()
```

### PlayerBase — `player_base.gd`

`PlayerBase` (`class_name PlayerBase extends CharacterBody2D`) is the shared base for every player implementation. In `_ready()` it adds itself to group `"player"`, then `_setup_components()` + `_setup_effects()`. It:

- Resolves and wires components: `$HealthComponent`, `$ShieldComponent`, `$OverheatComponent`, optional `TempHealthComponent`; connects health → `_on_health_changed` (→ `EventBus.player_health_changed`) and overheat → `_on_overheat_updated` (→ `EventBus.player_overheat_changed`).
- Owns the unified damage path `_apply_damage(damage)`: post-hit invincibility (`invincibility_sec = 0.5`), then shield → temp-HP → health, with `damage_reduction` applied only against health.
- Holds the multipliers/flags that ship modules write: `damage_multiplier`, `fire_rate_multiplier`, `damage_reduction`, `overdrive_active`, `can_attack`, `pierce_module_active`, `engine_boost_active`.
- Provides the temporary damage buff API (`apply_temp_damage_buff(bonus, duration)`, persisted via `SessionState`), the bubble-shield auto-setup, and knockback helpers (`apply_knockback`, `is_knockback_active`, `apply_knockback_motion`).
- Calls `SessionState.apply_to(self)` to restore cross-level temp buffs on spawn.

Subclasses call `super()` in `_ready()` (and in the overridable hooks `_setup_effects`, `_on_health_changed`, `_on_overheat_updated`) then add mode-specific behaviour.

## 6. Pickups & resources

### Pickups (`global/pickups/`)
`PickupBase` (`class_name PickupBase extends Area2D`) connects `body_entered`; when a body in group `"player"` enters, it casts to `PlayerBase` and, if that succeeds, calls `_collect(player)` exactly as before — subclasses override `_collect(player: PlayerBase)` / `_get_dialog_text`, and none of the 10 concrete pickups below changed. If the cast fails (the body is in group `"player"` but is not a `PlayerBase` — currently only the infiltration player), it instead calls the opt-in fallback hook `_collect_any(body: Node2D) -> bool`, whose base-class default returns `false` and leaves the pickup completely untouched (no free, no notification) — the same no-op as before this hook existed. A subclass meant to work against a non-`PlayerBase` body overrides `_collect_any` and returns `true` when it handles the pickup. Either path then checks `@export var persistent_id: StringName` (empty by default, matching every pickup today): if set and `PickupState.has_collected(persistent_id)` is already true, the pickup silently `queue_free()`s without re-running `_collect`/`_collect_any` — this is what stops a one-time pickup placed in a replayable mission (an assault restart does `get_tree().reload_current_scene()`, respawning every static child fresh) from re-granting itself. `PickupState` (`global/autoloads/pickup_state.gd`, autoload) is the persisted "ever collected" store behind it, modeled on `LogState`'s save shape. Then, same as before: shows a notification via `DialogPlayer` if `_get_dialog_text()` is non-empty, then `queue_free()`s.

**A pickup/interactable Area2D also only ever sees a body whose `collision_layer` overlaps its `collision_mask`** (every pickup scene and `InfoLogInteractable` use `collision_mask = 4`, the `"environemnt_player"` layer) — the group/cast check inside the handler is a second, independent gate that only runs once the signal has already fired. `assault/scenes/player/player_fighter.tscn` sets `collision_layer = 4` on its body; `infiltration/scenes/entities/player/player.tscn`'s `CharacterBody2D` now does too (added alongside its `"player"` group membership — see Interactables below). Concrete pickups:

| Pickup | Effect |
|---|---|
| `health_tank_pickup.gd` | `health.increase(40)` |
| `armor_and_health_pickup.gd`, `armor_tank_pickup.gd` | restore armor (shields) and/or health |
| `ship_shield_up_pickup.gd` | `ShipProgressionState.add_permanent_shield()` (permanent slot) |
| `ship_boost_up_pickup.gd` | `ShipProgressionState.add_boost_charge()` (open-space Shift-boost capacity, +1, capped at `MAX_BOOST_CHARGES`) |
| `temporary_shield_up_pickup.gd`, `temporary_health_up_pickup.gd`, `temporary_health_shield_up_pickup.gd` | add temp shield charge / temp-HP stack (persisted by `SessionState`) |
| `temporary_damage_up_pickup.gd` | `player.apply_temp_damage_buff(0.5, 15.0)` |
| `ship_module_unlocker_pickup.gd` | `ShipModuleState.unlock(slot, module_id)`; inspector-selectable `module_slot` / `module_id` enums |
| `weapon_mode_unlocker_pickup.gd` | `UpgradeState.unlock(weapon_id())` — grants one main-weapon mode permanently; inspector-selectable `weapon` enum (`SNIPER_SHOT`, `SPREAD`, `GATLING`, `MINING_LASER`). Dialog line reads `display_name` off the mode's own `.tres`. |
| `lore_log_pickup.gd` | `LogState.collect_next()` — no `@export`, deliberately anonymous like `LogState`'s own model: grants whichever catalogue entry has the lowest `sequence` and isn't collected yet, regardless of where in the world it was found. Dialog line names the entry title, or is empty (no notification) once the catalogue is exhausted. Placed 3 times in `open_space/scenes/levels/sector_hub.tscn`, one per `global/resources/logs/entries/*.tres` — see [`../open_space.md`](../open_space.md) → 3.1. |

Each has a matching scene under `global/pickups/scenes/`.

### Interactables (`global/interactables/`)
Deliberately **not** under `pickups/` and **not** a `PickupBase` subclass: `InfoLogInteractable`
(`class_name InfoLogInteractable extends Area2D`) is input-driven and never consumes itself, the
opposite of a pickup's free-on-contact contract. It represents an **information log** — a tablet,
terminal, or scrap of hull carrying one-time flavor text that is never stored and never counted
toward completion (contrast `LogState`'s lore logs, above). `body_entered`/`body_exited` (filtered
to group `"player"`) track how many player bodies currently overlap it and show/hide a child
`PromptLabel` accordingly; `_unhandled_input` fires on the `interact` action (bound to **F** in
`project.godot`) while a player is in range, guarded by `DialogPlayer.is_active` exactly like
`PickupBase._show_notification()`'s busy-guard. Firing builds a one-line, `INSTANT`, `INNER_THOUGHT` `DialogScriptResource` with
`pause_gameplay = false` via its own `_build_script()` (mirrors `PickupBase`'s notification
construction rather than sharing code with it — the two call sites' lifecycles differ enough,
and it's only two of them, that extracting a shared helper wasn't worth touching an unrelated
file for) and hands it to `DialogPlayer.play()` — nothing frees the node or marks it "read," so
interacting again replays the same message.
Physics layers: `collision_layer = 2` (`environment_interactable`, named for exactly this kind of
object in `project.godot`), `collision_mask = 4` (`environemnt_player` — the same mask every
pickup scene uses to detect the `open_space`/`assault` player bodies, which set
`collision_layer = 4` on their main shape). The shipped scene,
`global/interactables/scenes/info_log_interactable.tscn`, carries no sprite by design — "tablet",
"terminal", and "scrap of hull" are different physical dressings for the same interaction
contract, so a placement site adds its own `Sprite2D` child and sets `message`/`prompt_text`.
`infiltration/`'s player is now in group `"player"` (`player.gd::_ready()`) and on
`collision_layer = 4` (`player.tscn`), matching what this interactable and every `PickupBase`
scene require to detect it — both were needed together; the group alone does not make the
Area2D's `body_entered` signal fire at all. `assault/scenes/levels/edelia/1/level_1.tscn` and
`infiltration/scenes/levels/TestIsometricScene.tscn` each place one `InfoLogInteractable`
(node name `LogRecord`) as a static scene child, proving both placements — see
`tests/integration/test_log_record_mission_placement.gd`. `open_space/scenes/levels/sector_hub.tscn`
places two more (`InfoLogHubTerminal`, `InfoLogVoeterWreck`, each with its own `message`) — see
[`../open_space.md`](../open_space.md) → 3.1 and `tests/integration/test_hub_log_placement.gd`.

**Unlocker pickups are the only unlock source in the game.** Neither `ShipModuleState` nor `UpgradeState` is written from anywhere else, so a module or weapon mode with no unlocker placed in the world is content the player can see and never reach. Both benches live in `open_space/scenes/levels/sector_hub.tscn`, and both pairings are invariant-tested — `tests/integration/test_module_unlock_sources.gd` and `tests/integration/test_weapon_unlock_sources.gd`. The weapon exception is `UpgradeState.STARTING_IDS` (`[&"default"]`), seeded on a fresh profile.

### Resources (`global/resources/`)
Pure-data `Resource` types (shareable `.tres` assets; runtime state is kept out of them so multiple ships can share one asset).

- **attack/** — `AttackPatternResource` (base; `fire_interval = 0.8`, `start_delay = 0.0`, abstract `fire(ship, pool)`). Subtypes: `forward_attack_pattern` (straight up, exports `bullet_damage`, `spawn_offset`), `aimed_attack_pattern`, `gatling_attack_pattern`, `radial_attack_pattern`. Usually driven at runtime by `AttackController` (holds the per-ship timer), but a pattern is just a `fire(ship, pool)` call — `StationGunnery` owns its own `Timer`s and calls `fire()` directly.
  - `radial_attack_pattern.gd` (`RadialAttackPattern`) fires `bullet_count` bullets spread around `base_angle` in one shot, and covers both boss shapes in one resource: **`arc >= TAU` is a full ring** (spacing `TAU / count`, no duplicate at the seam) and **`arc < TAU` is a fan** of that width *centred* on the base direction (spacing `arc / (count - 1)`). `aim_at_player` adds the angle to the player (`Vector2.DOWN` fallback); `spawn_radius` offsets each bullet **along its own angle**, so a ring emerges from the hull rim and a fan from the barrel mouth. `bullet_count <= 0` fires nothing.
    ⚠️ Unlike its two siblings it **deliberately ignores `ship.rotation`** — `base_angle` is absolute world space and the caller owns any precession. `StationLaserPhase` spins the station at 0.5 rad/s during exactly the phase the core ring fires in, so folding in the hull rotation would add ~1.6 ring spacings of uncontrolled drift per ring. Pinned by `tests/integration/test_radial_attack_pattern.gd`.
- **movement/** — `MovementResource` (base; `sample(t) -> Vector2` displacement from spawn, `total_duration()`). Subtypes: `straight`, `sine`, `arc`, `curve`, `hold`, `u_sweep`, `player_focus`, `sequence`. Consumed by `EnemyPathMover`.
- **formation/** — `FormationResource` (base; `compute_slots() -> Array[FormationSlot]`, each slot an `offset` + `delay`). Subtypes: `line`, `v`, `wedge`, `diagonal`, `cluster`. `WaveManager` spawns one ship per slot.
- **waves/** — `LevelResource` (`level_name` + ordered `waves`), `WaveResource` (`trigger_time` + `entries`), `SpawnEntryResource` (one ship/formation: `ship_scene`, `base_offset`, `spawn_delay`, `movement`, `exit_mode`, `look_*`, optional `formation`, `initial_props`).
- **levels/** — `LevelSection` (one timed segment: `background_phase`, `transition_in_duration`, section-relative `waves`, `end_condition` ∈ {DURATION, WAVES_COMPLETE, ENEMIES_CLEARED}, `duration`) and `BackgroundPhase` (target alphas/scales/timings for the background renderer to tween toward).
- **logs/** — `LogEntryResource` (`id`, `title`, `body`, `sequence`). One `.tres` per lore-log
  entry; the catalogue is whatever sits in `entries/` at runtime — `LogState` sweeps the directory
  rather than reading a hand-written list, so a new entry needs no registration anywhere else.
- Top-level: `ship_config.gd`, `score_config.gd`, `skill_challenge_resource.gd` configure ship stats, scoring tuning, and skill-challenge windows respectively.

#### `ShipConfig` and per-instance config resources

`ShipConfig` (`global/resources/ship_config.gd`) is the base of all ten entity configs
(`max_health`, `collision_damage`, `score_value`, `counts_toward_wave_clear`,
`counts_as_escape`). Every entity declares
`@export var config: XConfig = load("res://.../x_config.tres")`, and `ResourceLoader` caches by
path — so without help, **every entity of a type in the process would hold the same object**, and it
would be the same object a test's `preload()` returns. Writing one enemy's `config.max_health` then
rewrote the shipped balance data for every other live enemy of that type and for the rest of the
process.

`ShipConfig.privatise(node)` swaps a node's `config` for a `duplicate()` of it, and is called from
**both** `_init()` and `_enter_tree()` on `BaseEnemy` (`assault/scenes/enemies/base_enemy.gd`) and
`AllyFighter` (`assault/scenes/allies/ally_fighter/ally_fighter.gd`). Both hooks are needed:

- `_init()` runs before `instantiate()` returns, so `config` is private for writes made **before**
  the entity enters the tree — which is where `wave_manager.gd:177-181` applies `initial_props`,
  deliberately. An `_enter_tree()`-only copy would leave the project's own spawn-override idiom
  writing to the shared resource.
- `_enter_tree()` catches a `config` that a `.tscn` override or `initial_props` substituted in after
  the constructor, and still runs before any **child's** `_ready()` — which the space station depends
  on, since its four child nodes read `_station.config` in their own `_ready()`.

They compose because `duplicate()` blanks `resource_path`, so a blank path *is* the marker of an
already-private copy and the second call is a no-op.

**The copy is shallow**, which is complete only while every config class stays flat — a `Resource`
inside an `Array`/`Dictionary` is never duplicated, not even by `duplicate(true)`.
`tests/integration/test_config_instance_isolation.gd` asserts the isolation, the value-identity
against each shipped `.tres`, and that flatness, and it finds entities by directory sweep so a new
enemy cannot escape it. **The object `load()`/`preload()` returns is still process-wide** — read it,
never write to it. Two windows stay open and are written up in that test's header:
`Node.duplicate()` hands two nodes one private copy, and `entity.config = load(...)` on an entity
already in the tree fires neither hook. Neither is reachable from non-addon code today.
