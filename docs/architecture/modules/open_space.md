# Open Space Module

> The persistent hub world that ties the game's three play modes together. See the [game structure overview](../../game-structure.md) for where this sits relative to the assault and infiltration modes it launches into, and [`./global.md`](./global.md) for the shared components, autoloads, and resources it composes.

## 1. Overview

`open_space/` is the **free-flight hub** the player returns to between missions. It is a single `Node2D` level (`SectorHub`) in which the player pilots a ship through 2D space, drifts up to **planets** (and other mission-trigger objects), and dwells near one to open a **mission-select menu**. Picking a mission plays a short dive cinematic and then `change_scene_to_file`s into the actual mission scene — which may be an **assault** level (vertical shmup) or an **infiltration** level (isometric ground op). In this way open space is the connective tissue between the three modes documented in [`../../game-structure.md`](../../game-structure.md): the hub itself, plus the assault and infiltration missions it hands off to.

The hub is **fully data-driven**. A planet is just a `MissionTrigger` (`Area2D`) with a `PlanetConfigResource` assigned in the Inspector; that resource supplies the planet sprite, the mission list, and the on-map point layout. Each mission in the list is a `MissionConfigResource` (`AssaultMissionResource` or `InfiltrationMissionResource`) that names the scene to launch and how the mission is gated/scored. No hub code changes are needed to add a planet or a mission — you author `.tres` files.

Progression is read from and written to the global autoloads documented in [`./global.md`](./global.md): the menu reads **`MissionState`** to lock rows, draw stars, and gate by high score; the player ship reads **`ShipModuleState`** to re-apply equipped modules and **`SessionState`** (via `PlayerBase`) to restore cross-level temp buffs. The hub does not write progress itself — that happens inside missions on win; the hub only consumes it to decide what is unlocked.

## 2. Directory map

```
open_space/scenes/
├── entities/
│   ├── player/
│   │   ├── player_ship.gd        # OpenSpacePlayerShip (extends PlayerBase) — free-flight controller + ship modules
│   │   └── player_ship.tscn       # ship scene: components, attack state machine, animated sprite
│   └── enemies/
│       ├── patrol_drone.gd        # PatrolDrone — ambient hub enemy that drifts in a straight line
│       └── patrol_drone.tscn
├── gui/
│   └── hud.tscn                   # OpenSpaceHUD (CanvasLayer) — reuses global/ui/mission_hud.gd + shared HUD parts
├── levels/
│   ├── sector_hub.gd              # SectorHub (Node2D) — the hub level; spawns drones, holds planets + pickups
│   └── sector_hub.tscn            # composed scene: parallax bg, two planets, player+camera, HUD, pickups
├── mission_data/                  # per-mission data resources (the "what to launch" layer)
│   ├── mission_config_resource.gd        # MissionConfigResource (base): name, scene_path, gating, scoring hook
│   ├── assault_mission_resource.gd       # AssaultMissionResource — adds 2★/3★ score thresholds
│   ├── infiltration_mission_resource.gd  # InfiltrationMissionResource — marker subtype for ground ops
│   └── planets/
│       ├── edelia/*.tres                 # 3 mission resources for planet Edelia
│       └── voeter_k05m/*.tres            # 4 mission resources for planet Voeter K05M
├── mission_select_hubs/           # the trigger objects (planets) + their config resources
│   ├── mission_select_hub.gd             # MissionTrigger (@tool Area2D): dwell detection, opens menu, dive
│   ├── mission_select_hub.tscn           # Planet scene (Area2D + Sprite2D + CollisionShape2D)
│   ├── mission_select_hub_config_resource.gd  # PlanetConfigResource: sprite, mission list, point layout
│   └── planets/
│       ├── edelia.tres                   # Edelia config (3 missions)
│       └── voeter_k05m.tres              # Voeter K05M config (4 missions)
└── mission_select_ui/             # the in-world mission-select overlay
    ├── mission_select_menu.gd            # MissionSelectMenu (CanvasLayer) — full-screen selector + cinematic
    ├── mission_select_menu.tscn
    ├── mission_list_item.gd              # MissionListItem (Node2D) — one row (icon, name, stars, locked)
    ├── mission_list_item.tscn
    └── planet_motion_blur.gdshader       # directional blur applied to planet/points while panning
```

> Naming note: several scripts carry a header comment with a different (legacy) `global/resources/...` path — e.g. `mission_select_hub.gd` calls itself `class_name MissionTrigger`, and `mission_select_hub_config_resource.gd` declares `class_name PlanetConfigResource`. The `class_name` is authoritative; the header path is stale. This doc uses the `class_name`.

## 3. Mechanics

### 3.1 The hub level — `SectorHub`

`open_space/scenes/levels/sector_hub.gd` (`extends Node2D`) is the root of the hub. The `.tscn` (`open_space/scenes/levels/sector_hub.tscn`) composes everything:

- A solid-colour `Background` plus a two-layer `ParallaxBackground` of stars (motion scales `0.15` / `0.5`) for depth as the ship flies.
- Two `MissionTrigger` instances of `mission_select_hub.tscn` named `edelia` and `voeter_k05m`, each with a different `PlanetConfigResource` (`planets/edelia.tres`, `planets/voeter_k05m.tres`) and per-instance `arc_*` overrides positioning the dwell-progress ring on the visible planet.
- The `PlayerShip` instance, with a child `Camera2D` that itself carries a `CameraDirector` node (the shared camera arbitrator from [`./global.md`](./global.md)).
- The `OpenSpaceHUD` (`gui/hud.tscn`).
- An `EnemyContainer` (drones are added here at runtime) and a row of every shared pickup from `global/pickups/scenes/` (armor/health, module unlocker, temp buffs) so the hub doubles as a test/equip bench.
- Above that row, **two further rows of `ShipModuleUnlockerPickup` instances (y = -315 and y = -415)** — one per ship module, 15 in total counting the `trajectory_calc` unlocker on the original bench row. Since `ShipModuleState.equip()` gained its unlock gate these are the game's only way to make a module installable, so the bench is currently the unlock *source*, not just a test convenience. `tests/integration/test_module_unlock_sources.gd` asserts the coverage stays complete. Distributing unlockers through missions instead is not done yet.

The script's only logic is `_spawn_initial_drones()`: in `_ready()` it instantiates `drone_count` (`3`) `PatrolDrone`s at random angles/distances within `spawn_radius` (`600`) and gives each a random `initial_direction`.

### 3.2 Player entity — `OpenSpacePlayerShip`

`open_space/scenes/entities/player/player_ship.gd` (`class_name OpenSpacePlayerShip extends PlayerBase`). It inherits all the shared health/shield/overheat/temp-HP plumbing and `EventBus` emission from `PlayerBase` (see [`./global.md`](./global.md) → PlayerBase) and adds free-flight specifics:

- **Movement** (`_physics_process` → `_handle_rotation` + `_handle_thrust` + `move_and_slide`): rotate with `move_left`/`move_right`, thrust forward/back with `move_up`/`move_down`, with damping and a `max_speed` cap. A "flip boost" redirects momentum when you reverse-thrust above `boost_speed_threshold`. Thruster particle state is driven each frame.
- **Camera feel** (`_update_camera_feel`): pushes a combined speed-zoom + lead-offset target into the child `Camera2D`'s `CameraDirector` under effect name `&"speed_feel"` at priority `0`. The planet dwell (below) overrides this at priority `10`, so approaching a planet smoothly takes over the camera.
- **Ship modules**: on `_ready()` it re-applies every module already equipped in `ShipModuleState` (reads `ShipModuleState.SLOTS` / `get_equipped`) and connects `module_equipped` / `module_unequipped` for live equip/unequip. Each frame it ticks all active modules. The `use_ability` action (H-key) is offered to modules first via `_input`. This is the same module system described in [`./global.md`](./global.md).
- **Death**: `_on_health_changed(0)` plays the explosion, shakes the camera, waits, and `reload_current_scene()` — i.e. respawn in the hub.

The ship scene (`player_ship.tscn`) is built by composition: `HealthComponent`, `ShieldComponent`, `OverheatComponent`, `TempHealthComponent`, a `HurtBox`, an `AttackStateMachine` (`WeaponState` + `WarheadMissileShootingState`), and a `MovementController` — all shared classes from `global/` and `assault/`.

### 3.3 Ambient enemy — `PatrolDrone`

`open_space/scenes/entities/enemies/patrol_drone.gd` (`class_name PatrolDrone extends CharacterBody2D`). Minimal hub flavour enemy: adds itself to group `"enemies"`, drifts at `move_speed` along `initial_direction` forever, routes `HurtBox` damage into its `HealthComponent`, and `queue_free`s (emitting `died`) at 0 HP. No AI beyond straight-line drift.

### 3.4 Mission-select trigger (the "planet") — `MissionTrigger`

`open_space/scenes/mission_select_hubs/mission_select_hub.gd` (`@tool class_name MissionTrigger extends Area2D`). This is the interactable. It holds a `config: PlanetConfigResource` and `arc_*` exports for the dwell ring; `@tool` + the `config` setter make the planet sprite update live in the editor when you swap resources.

Interaction flow:

1. **Enter range** (`_on_body_entered`, body in group `"player"`): caches the player's `Camera2D` and starts the dwell timer.
2. **Dwell** (`_process`): while the player stays in range **and is slower than `_MAX_APPROACH_SPEED` (150 px/s)**, `_dwell_time` accumulates toward `dwell_duration_sec` (`2.0`). A progress arc is drawn (`_draw` → `draw_arc`) and the camera zooms in via `CameraDirector.set_effect(&"planet_dwell", …, priority 10)`. Flying through fast cancels the approach.
3. **Open** (`_open_menu` once dwell completes): freezes the player, plays the ship's `planet_dive` animation, instantiates `mission_select_menu.tscn`, connects `mission_confirmed` / `cancelled`, calls `menu.open(config)`, and sets `get_tree().paused = true`.
4. **Confirm** (`_on_mission_confirmed(scene_path)`): unpauses and `get_tree().change_scene_to_file(scene_path)` — this is the hand-off out of open space into the mission.
5. **Cancel / leave** (`_on_menu_cancelled`, `_on_body_exited`): closes the menu, unpauses, restores player processing and the `idle` animation, and clears the `planet_dwell` camera effect so the director blends back to the ship's speed-feel.

The trigger scene (`mission_select_hub.tscn`) is a generic `Area2D` (`collision_layer = 2`, `mask = 4` to detect the player) with a `Sprite2D` and a `CollisionShape2D` — it is named "Planet" but the script comments stress it works for stations/ships/any Area2D; only the assigned config differs.

### 3.5 Mission-select overlay — `MissionSelectMenu` + `MissionListItem`

`open_space/scenes/mission_select_ui/mission_select_menu.gd` (`class_name MissionSelectMenu extends CanvasLayer`) is the full-screen selector, driven entirely by the passed `PlanetConfigResource`. `open(config)`:

- Sets the planet sprite/name/description from the config.
- Builds one `MissionListItem` row per `config.missions[i]`, and one map **point** sprite + number label per mission at `config.point_positions[i]`, plus connecting `Line2D`s (skipped when `connect_line` is false or an endpoint is locked).
- Navigation (`_unhandled_input`): `move_up`/`move_down` wrap the cursor; `_refresh` pans the planet so the selected point centres (with directional motion blur via `planet_motion_blur.gdshader` and a cockpit micro-shake), updates the preview image and description (or `locked_description`), and highlights the selected point.
- **Locking** (`_is_locked`): a mission is locked if `required_mission != 0` and `MissionState.is_complete(required_mission)` is false, **or** if `required_score_mission != 0` and `MissionState.get_high_score(required_score_mission) < required_score`. Both gates compose via AND. Locked rows show `??` with an "unknown" icon.
- **Confirm** (`ui_accept` → `_try_confirm` → `_play_dive_cinematic`): if not locked, plays pilot-hand and ship-dive tweens (~2 s flash/scale/vignette cinematic), then emits `mission_confirmed(scene_path)` back to the trigger.
- **Cancel** (`ui_cancel`): `close()` + emit `cancelled`.

`open_space/scenes/mission_select_ui/mission_list_item.gd` (`class_name MissionListItem extends Node2D`) renders one row. `configure(mission, locked)` sets the number-prefixed name, picks the icon by mission type (`InfiltrationMissionResource` → land icon, else assault icon, locked → unknown), and reads `MissionState.get_stars(mission.mission_number)` to render `★`/`☆`. `set_hovered` brightens the selected row.

### 3.6 How a mission is *defined* — `mission_data/` resources

A mission is a `.tres` `MissionConfigResource` (`open_space/scenes/mission_data/mission_config_resource.gd`, `extends Resource`). Key fields:

- `display_name`, `description`, `mission_image` — shown in the list and preview.
- `scene_path` — **the `res://` scene to launch** (this is what the trigger feeds to `change_scene_to_file`).
- `mission_number` — global sequence number; the key under which `MissionState` stores completion/stars/high-score.
- `required_mission`, `required_score_mission` + `required_score`, `locked_description` — the unlock gates read by `MissionSelectMenu._is_locked`.
- `connect_line` — whether a map line is drawn into this point.
- `stars_for_score(score)` — scoring hook (base returns 1).

Two subtypes:

- `AssaultMissionResource` (`assault_mission_resource.gd`) — for vertical-shmup missions; adds `star_2_score` / `star_3_score` and overrides `stars_for_score` with threshold logic. Its `scene_path` points into `assault/` (e.g. `res://assault/scenes/levels/edelia/1/level_1.tscn`).
- `InfiltrationMissionResource` (`infiltration_mission_resource.gd`) — marker subtype (no extra fields yet) for ground/isometric ops; selects the land icon and points `scene_path` into `infiltration/`.

Authored examples live under `mission_data/planets/<planet>/` — Edelia has 3 (`edelia_01…` assault, `edelia_02…`/`edelia_03…` infiltration); Voeter K05M has 4. Example: `edelia_01_…_resource.tres` is an `AssaultMissionResource` with `star_2_score = 6000`, `star_3_score = 11000`, `scene_path = res://assault/scenes/levels/edelia/1/level_1.tscn`, `mission_number = 1`; `edelia_02_…_resource.tres` is an `InfiltrationMissionResource` with `required_mission = 1` (locked until mission 1 is complete) and a `scene_path` into `infiltration/`.

### 3.7 How a planet is *defined* — `PlanetConfigResource`

`open_space/scenes/mission_select_hubs/mission_select_hub_config_resource.gd` (`class_name PlanetConfigResource extends Resource`) is the per-trigger config:

- `display_name`, `description`, `description_font_size` — menu header.
- `sprite_texture` — used **both** as the in-world planet `Sprite2D` and the menu's "planet map" image.
- `missions: Array[MissionConfigResource]` — the ordered mission list (index `i` ↔ `point_positions[i]`).
- `point_positions: Array[Vector2]` — pixel offsets for each mission point on the map.

The `planets/edelia.tres` and `planets/voeter_k05m.tres` assets wire `sprite_texture` + a missions array + point positions. (Note: both `.tres` files also set a `background_texture` value, but the current script declares no such `@export` — it is a vestigial/unused property; the menu derives its imagery from `sprite_texture`.)

### 3.8 How a mission is *launched* — and which autoloads are touched

End-to-end: **player dwells on a `MissionTrigger` → `MissionSelectMenu.open(config)` → player confirms a row → `mission_confirmed(scene_path)` → `MissionTrigger._on_mission_confirmed` unpauses and `get_tree().change_scene_to_file(scene_path)`**. The `scene_path` string comes straight from the chosen `MissionConfigResource`, so launching is just a scene swap into the assault or infiltration module.

Autoloads (defined and documented in [`./global.md`](./global.md)) used by this module:

| Autoload | Read by open_space | Written by open_space |
|---|---|---|
| `MissionState` | `MissionSelectMenu._is_locked` (`is_complete`, `get_high_score`) for lock gates; `MissionListItem.configure` (`get_stars`) for the star display. | Not written here — completion/score/stars are recorded **inside missions on win**; the hub only reads them. |
| `ShipModuleState` | `OpenSpacePlayerShip._ready` re-applies equipped modules (`SLOTS`, `get_equipped`) and listens to `module_equipped` / `module_unequipped`. | Via the `ShipModuleUnlockerPickup` instances in the hub (call `ShipModuleState.unlock`) — one per module, and the only unlock source in the game. |
| `SessionState` | Restored on spawn through `PlayerBase._setup_components()` → `SessionState.apply_to(player)` (cross-level temp buffs). | Indirectly via the hub's temp-buff pickups (which persist through `SessionState`). |
| `EventBus` | — | `OpenSpacePlayerShip` (via `PlayerBase`) emits `player_health_changed` / `player_overheat_changed`, consumed by `OpenSpaceHUD`. |
| `CameraShake` | `CameraDirector` composes its offset for speed/dwell/death shake. | `OpenSpacePlayerShip` adds trauma on hit/death. |

The HUD (`gui/hud.tscn`, `OpenSpaceHUD`) reuses the shared `global/ui/mission_hud.gd` plus the shared health/shield bar, shield-icon strip, weapon chip, player menu, and pause menu — see [`./global.md`](./global.md).

## 4. Links

- [`./global.md`](./global.md) — shared components, autoloads (`MissionState`, `SessionState`, `ShipModuleState`, `EventBus`, `CameraShake`), `PlayerBase`, `CameraDirector`, pickups, and resource base types this module composes.
- [`../../game-structure.md`](../../game-structure.md) — top-level game structure: how the open-space hub relates to the assault and infiltration mission modes it launches into.
