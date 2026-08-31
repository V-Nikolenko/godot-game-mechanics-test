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
│   └── upgrade_state.gd       # UpgradeState: unlocked weapon upgrade ids
├── components/                # composable child-node behaviours
│   ├── health_component.gd        # Health (Node)
│   ├── temp_health_component.gd   # TempHealth (Node) — drains before Health
│   ├── hurtbox_component.gd       # HurtBox (Area2D) — receives hits
│   ├── hitbox_component.gd        # HitBox (Area2D) — deals hits, DamageType enum
│   ├── shield_component.gd        # Shield (Node) — discrete-charge shield
│   ├── damage_reaction.gd         # DamageReaction (Node) — generic "take a hit" router
│   ├── overheat_component.gd      # Overheat (Node) — weapon heat
│   ├── attack_controller.gd       # AttackController (Node) — drives an AttackPatternResource
│   ├── bullet_pool.gd             # BulletPool — bullet object pool
│   ├── bubble_shield.gd/.tscn     # BubbleShield (AnimatedSprite2D) — shield visual
│   ├── shield_icon*.gd/.tscn      # ShieldIconStrip / ShieldIcon — shield HUD
│   ├── hit_effect.gd              # HitEffect — per-hit particle burst
│   ├── explosion_effect.gd        # ExplosionEffect — death burst
│   ├── thruster_effect.gd         # ThrusterEffect — engine flame
│   ├── rocket_trail.gd            # RocketTrail — missile trail
│   └── low_health_smoke.gd        # LowHealthSmoke — smoke below an HP threshold
├── entities/
│   └── player_base.gd         # PlayerBase (CharacterBody2D) — shared player base class
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
│   └── background_controller.gd # BackgroundController — abstract level-bg base
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

All eight are registered in `project.godot` under `[autoload]`. The `*` prefix means the script is the singleton root. Note the path quirk: most live in `global/autoloads/` (plural), `DialogPlayer` lives in `global/autoload/` (singular), and `EventBus`/`CameraShake` live in `global/systems/`.

| Autoload | File | State it owns | Read / written |
|---|---|---|---|
| `MissionState` | `global/autoloads/mission_state.gd` | Per-mission `completed` / `stars` / `high_score`, plus cutscene-seen flags. Persists to `user://mission_state.cfg`. | Written on mission win (`complete`, `record_score`) and when a cutscene plays (`mark_cutscene_seen`); read by the mission-select hub and HUD. |
| `DialogPlayer` | `global/autoload/dialog_player.gd` | Active dialog run state (`is_active`, `auto_mode`, current script/line). Owns a `DialogBox` instance. | Written by callers via `play(script)` / `skip_dialog()`; read by player controllers to gate input while `is_active`. |
| `UpgradeState` | `global/autoloads/upgrade_state.gd` | Set of unlocked weapon-upgrade ids (`default`, `sniper_shot`, `spread`, `gatling`, `mining_laser`). Persists to `user://upgrades.cfg`. | Written by `unlock(id)`; read by weapon-selection UI via `is_unlocked` / `unlocked_ids`. Emits `unlocked_changed`. |
| `EventBus` | `global/systems/event_bus.gd` | No state — pure signal hub (health, overheat, weapon, mission, scoring signals). | Emitted by gameplay (e.g. `PlayerBase` emits `player_health_changed`); subscribed by HUD/UI instead of polling nodes. |
| `ShipModuleState` | `global/autoloads/ship_module_state.gd` | Equipped + unlocked module id per slot (`cockpit`/`armor`/`weapons`/`engines`). Persists to `user://ship_modules.cfg`. | Written by `equip` / `unlock`; read by the ship menu and player ship on spawn. Emits `module_equipped` / `module_unequipped` / `module_unlocked`. |
| `ShipProgressionState` | `global/autoloads/ship_progression_state.gd` | Permanent shield slot count (clamped 1..5). Persists to `user://ship_progression.cfg`. | Written by `add_permanent_shield` / `set_permanent_shield_count`; read by `Shield._ready()` when `bind_progression == true`. Emits `permanent_shield_count_changed`. |
| `SessionState` | `global/autoloads/session_state.gd` | Cross-level temporary buffs: temp shield count, temp HP pool, timed damage buff (saved as Unix expiry). Persists to `user://session.cfg`. | `apply_to(player)` called from `PlayerBase._setup_components()`; auto-saved when shield/temp-HP/damage-buff state changes. |
| `CameraShake` | `global/systems/camera_shake.gd` | A single `_trauma` float (0..1) that decays each frame. | Written by any system via `add(amount)`; read each frame by cameras via `get_offset()` (used inside `CameraDirector`). |

## 4. Shared systems (`global/systems/`)

### `event_bus.gd` — `EventBus`
Autoload signal hub for decoupling gameplay from UI. Declares typed signals only (no logic): player health/overheat/weapon/rocket/death, ability activate/deselect, mission wave/complete/failed, and scoring (`score_changed`, `combo_changed`, `score_event`, `skill_challenge_completed`, `enemy_spawned_orphan`). Subscribe here instead of `get_nodes_in_group()`.

### `camera_shake.gd` — `CameraShake`
Trauma-model screen shake (Eiserloh). Systems call `CameraShake.add(amount)` to inject trauma in `[0,1]` (saturating); trauma decays at `_DECAY = 1.5`/s. The visible offset is quadratic — `get_offset()` returns a random vector scaled by `trauma² * _MAX_OFFSET (8.0 px)`. Cameras add this to their own offset each frame.

### `camera_director.gd` — `CameraDirector`
Owns a `Camera2D` (default sibling at `camera_path = ".."`) and arbitrates competing zoom/offset drivers. Systems call `set_effect(name, zoom, offset, priority)`; each frame the highest-priority effect wins and the director blends toward it (`blend_speed = 6.0`) so hand-offs don't pop, then composes `CameraShake.get_offset()` on top. If an external animator writes `camera.zoom` directly (e.g. the pause menu tween), the director detects the mismatch, resyncs, and yields that frame.

### `background_controller.gd` — `BackgroundController`
Abstract base for level background renderers. Subclasses must override `transition_to(phase: BackgroundPhase, duration)` to tween toward a `BackgroundPhase` snapshot. Optional overrides `set_scroll_multiplier(m)` and `set_throttle_scroll(m)` (default no-ops) let dash panels / race throttle speed up scrolling. `LevelDirector` calls these per section.

## 5. Integration recipes — "How to add X to an entity"

> Entities compose behaviour by adding child nodes and wiring signals. The canonical wiring of all of this for the player is `PlayerBase` (`global/entities/player_base.gd`); generic ships use `DamageReaction` instead. Verify the API of each component (linked file) before copying a snippet.

### Health — `health_component.gd` (+ `temp_health_component.gd`)

Add a `Health` node (`class_name Health extends Node`) as a child named `HealthComponent`. Exports: `max_health: int = 100`, `current_health: int = 100`, `invincibility_frames_enabled: bool = false`, `invincibility_time_in_sec: float = 0.5`. API: `increase(amount)`, `decrease(amount)`, `set_health(v)`; signal `amount_changed(current)`. `decrease()` is ignored while its internal invincibility timer is running (only when `invincibility_frames_enabled`).

`TempHealth` (`class_name TempHealth extends Node`, child named `TempHealthComponent`) is an optional buffer that drains *before* `Health`. `add_stack(base_health)` adds one stack of `base_health/2` HP (cap `MAX_STACKS = 5`); `take_damage(amount)` drains and returns the overflow that should hit `Health`. Signal `amount_changed(current, maximum)`.

```gdscript
# Manual damage routing (TempHealth in front of Health):
var overflow := temp_health.take_damage(damage)   # returns leftover
if overflow > 0:
    health.decrease(overflow)
```

### Hurtbox / Hitbox — `hurtbox_component.gd`, `hitbox_component.gd`

`HitBox` (`extends Area2D`) is the *attacker* side: exports `damage: int = 1` and `damage_type: DamageType` (`enum DamageType { LASER, ROCKET, CONTACT }`). Put it on bullets, rockets, and ramming bodies.

`HurtBox` (`extends Area2D`) is the *target* side. In `_ready()` it connects `area_entered`; when an overlapping area is a `HitBox` (and passes the optional `accepted_damage_types` filter), it re-emits `received_damage(damage)`. Filtering by type is via the exported `accepted_damage_types: Array[HitBox.DamageType]` (empty = accept all).

Collision wiring: set the `HitBox`'s `collision_layer` to a "damage" layer and leave its mask empty; set the `HurtBox`'s `collision_mask` to scan that same layer. Only `Area2D`↔`Area2D` overlap is detected — `HurtBox` ignores non-`HitBox` areas. The damage path is **HitBox overlaps HurtBox → `HurtBox.received_damage` → your handler (or `DamageReaction`) → Shield/Health**.

```gdscript
# On the target entity:
@onready var hurtbox: HurtBox = $HurtBox
func _ready() -> void:
    hurtbox.received_damage.connect(_on_hit)
func _on_hit(damage: int) -> void:
    health.decrease(damage)   # or route through DamageReaction (below)
```

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

`State` (`class_name State extends Node`) is the base contract: override `enter()`, `process_physics(delta)`, `exit()`, and emit `state_transition(next_state)` to request a change. `StateMachine` (`class_name StateMachine extends Node`) holds an exported `initial_state: State`. In `_ready()` it connects every child `State`'s `state_transition` signal to `change_state`, then enters `initial_state`. Each `_process(delta)` it calls `current_state.process_physics(delta)`. `change_state` ignores a transition to the same/null state, else calls `exit()` on the old and `enter()` on the new.

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

A *module* is a `RefCounted` strategy object (not a node) that mutates the player on equip. `ShipModuleBase` defines the contract and a central `static func create(id) -> ShipModuleBase` registry. Override points: `get_display_name`, `get_description`, `get_icon`, `get_slot` (`cockpit`/`armor`/`weapons`/`engines`), `apply(player)` (on equip), `remove(player)` (on unequip/scene change), `try_activate(player) -> bool` (H-key for active modules), and `tick(player, delta)` (per-frame for the equipped active module, e.g. cooldown/expiry). Passive modules (e.g. `ArmorPlatingModule` adds +40 HP and +0.25 `damage_reduction`) only override `apply`/`remove`; active ones (e.g. `TrajectoryCalcModule`, `EMPBlastModule`) implement `try_activate`/`tick`.

`ShipModuleState` persists which module id is equipped/unlocked per slot (`SLOT_MODULES` lists the valid ids; the registered ids are: cockpit `trajectory_calc`/`emp_blast`/`ai_targeting`/`cockpit_heal`; armor `armor_plating`/`parry`/`shield_overload`/`final_resort`; weapons `overclock`/`plasma_nova`/`overheat_nullifier`/`pierce`/`shooting`; engines `warp`/`engine_boost`). All 15 module scripts are registered in `create()` (one class per id).

To add a new module:
1. Create `global/ship_modules/foo_module.gd` (`class_name FooModule extends ShipModuleBase`); override `get_slot`, names/icon, and `apply`/`remove` (+ `try_activate`/`tick` if active).
2. Add a `match` arm in `ShipModuleBase.create()`.
3. Add its id to the slot's list in `ShipModuleState.SLOT_MODULES` (and the `ShipModuleUnlockerPickup.Module` enum if a pickup should grant it).

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
- **`ExplosionEffect`** — bigger one-shot burst on death; call `explode()` just before `queue_free()`. Spawns particles into the *parent* container so they outlive the entity. `always_process: bool = false` lets the player death burst render while paused.
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
`PickupBase` (`class_name PickupBase extends Area2D`) connects `body_entered`; when a body in group `"player"` (cast to `PlayerBase`) enters, it calls `_collect(player)`, optionally shows a notification via `DialogPlayer` if `_get_dialog_text()` is non-empty, then `queue_free()`s. Subclasses override `_collect` / `_get_dialog_text`. Concrete pickups:

| Pickup | Effect |
|---|---|
| `health_tank_pickup.gd` | `health.increase(40)` |
| `armor_and_health_pickup.gd`, `armor_tank_pickup.gd` | restore armor (shields) and/or health |
| `ship_shield_up_pickup.gd` | `ShipProgressionState.add_permanent_shield()` (permanent slot) |
| `temporary_shield_up_pickup.gd`, `temporary_health_up_pickup.gd`, `temporary_health_shield_up_pickup.gd` | add temp shield charge / temp-HP stack (persisted by `SessionState`) |
| `temporary_damage_up_pickup.gd` | `player.apply_temp_damage_buff(0.5, 15.0)` |
| `ship_module_unlocker_pickup.gd` | `ShipModuleState.unlock(slot, module_id)`; inspector-selectable `module_slot` / `module_id` enums |

Each has a matching scene under `global/pickups/scenes/`.

### Resources (`global/resources/`)
Pure-data `Resource` types (shareable `.tres` assets; runtime state is kept out of them so multiple ships can share one asset).

- **attack/** — `AttackPatternResource` (base; `fire_interval = 0.8`, `start_delay = 0.0`, abstract `fire(ship, pool)`). Subtypes: `forward_attack_pattern` (straight up, exports `bullet_damage`, `spawn_offset`), `aimed_attack_pattern`, `gatling_attack_pattern`. Driven at runtime by `AttackController` (holds the per-ship timer).
- **movement/** — `MovementResource` (base; `sample(t) -> Vector2` displacement from spawn, `total_duration()`). Subtypes: `straight`, `sine`, `arc`, `curve`, `hold`, `u_sweep`, `player_focus`, `sequence`. Consumed by `EnemyPathMover`.
- **formation/** — `FormationResource` (base; `compute_slots() -> Array[FormationSlot]`, each slot an `offset` + `delay`). Subtypes: `line`, `v`, `wedge`, `diagonal`, `cluster`. `WaveManager` spawns one ship per slot.
- **waves/** — `LevelResource` (`level_name` + ordered `waves`), `WaveResource` (`trigger_time` + `entries`), `SpawnEntryResource` (one ship/formation: `ship_scene`, `base_offset`, `spawn_delay`, `movement`, `exit_mode`, `look_*`, optional `formation`, `initial_props`).
- **levels/** — `LevelSection` (one timed segment: `background_phase`, `transition_in_duration`, section-relative `waves`, `end_condition` ∈ {DURATION, WAVES_COMPLETE, ENEMIES_CLEARED}, `duration`) and `BackgroundPhase` (target alphas/scales/timings for the background renderer to tween toward).
- Top-level: `ship_config.gd`, `score_config.gd`, `skill_challenge_resource.gd` configure ship stats, scoring tuning, and skill-challenge windows respectively.
