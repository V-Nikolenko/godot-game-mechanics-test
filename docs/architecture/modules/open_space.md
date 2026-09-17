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
│   │   ├── player_ship.tscn       # ship scene: components, attack state machine, animated sprite
│   │   ├── ship_turn_controller.gd # ShipTurnController — the ONLY writer of the ship's rotation
│   │   ├── boost_meter.gd          # BoostMeter — the Shift boost's charge economy (spend + refill)
│   │   └── open_space_camera_rig.gd # OpenSpaceCameraRig — speed-zoom + camera-lead formula behind speed_feel
│   └── enemies/
│       ├── patrol_drone.gd        # PatrolDrone — ambient hub enemy that drifts in a straight line
│       └── patrol_drone.tscn
├── gui/
│   ├── hud.tscn                   # OpenSpaceHUD (CanvasLayer) — reuses global/ui/mission_hud.gd + shared HUD parts
│   ├── boost_bar.gd               # BoostBar — cyan pip readout for BoostMeter, drawn under the hull
│   └── aim_reticle.gd             # AimReticle — dead-zone/snap/lag ring drawn on the hull
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
- An `EnemyContainer` (drones are added here at runtime) and a row of every shared pickup from `global/pickups/scenes/` (armor/health, module unlocker, temp buffs) so the hub doubles as a test/equip bench. `ShipBoostUpPickup` (`x = 730, y = -212`) sits at the end of this row — `ShipProgressionState.add_boost_charge()`, the capacity upgrade for the open-space Shift boost meter; `x = 620` on the row was already taken by `LoreLogBeaconStatic`, so it lands one slot further out. `tests/integration/test_boost_upgrade_source.gd` asserts it is placed and that collecting it raises the live count.
- Above that row, **two further rows of `ShipModuleUnlockerPickup` instances (y = -315 and y = -415)** — one per ship module, 15 in total counting the `trajectory_calc` unlocker on the original bench row. Since `ShipModuleState.equip()` gained its unlock gate these are the game's only way to make a module installable, so the bench is currently the unlock *source*, not just a test convenience. `tests/integration/test_module_unlock_sources.gd` asserts the coverage stays complete. Distributing unlockers through missions instead is not done yet.
- Above *those*, a fourth row of **`WeaponModeUnlockerPickup` instances (y = -515, x -280..20)** — one each for `sniper_shot`, `spread`, `gatling` and `mining_laser`. Same story, same shape: `UpgradeState._ready()` seeds only `STARTING_IDS` (`&"default"`), and `unlock()` has no other production caller, so before this bench row existed four tuned weapon modes with working `WeaponBehavior`s were unreachable and the player flew the Standard gun for the whole game. `tests/integration/test_weapon_unlock_sources.gd` is the matching coverage gate. Gating weapon modes behind missions rather than a bench is an open design question, same as for modules.
- The hub also carries every `LoreLogPickup` the game ships (3, matching `LogState.total_count()`
  one-for-one) and two `InfoLogInteractable` instances — the demonstrable end-to-end proof for the
  whole log-records system (see [`./global.md`](./global.md) → Pickups & resources). Two of the
  five sit off the bench row near the existing pickups (`LoreLogBeaconStatic` at `(620, -212)`,
  `InfoLogHubTerminal` at `(0, -150)`); the other three sit near a planet/station arc each
  (`LoreLogEdeliaSurvey`, `LoreLogFortunaManifest`, `InfoLogVoeterWreck`), so at least some require
  actually leaving the mission-select lane. `tests/integration/test_hub_log_placement.gd` asserts
  the placed count and the catalogue-total match, and exercises one of each end to end.

The script's only logic is `_spawn_initial_drones()`: in `_ready()` it instantiates `drone_count` (`3`) `PatrolDrone`s at random angles/distances within `spawn_radius` (`600`) and gives each a random `initial_direction`.

### 3.2 Player entity — `OpenSpacePlayerShip`

`open_space/scenes/entities/player/player_ship.gd` (`class_name OpenSpacePlayerShip extends PlayerBase`). It inherits all the shared health/shield/overheat/temp-HP plumbing and `EventBus` emission from `PlayerBase` (see [`./global.md`](./global.md) → PlayerBase) and adds free-flight specifics:

- **Movement** (`_physics_process` → `_handle_rotation` + `_handle_thrust` + `move_and_slide`): steer toward the mouse cursor (or with `move_left`/`move_right` under the Classic scheme — see `ShipTurnController` below), thrust forward/back with `move_up`/`move_down`, with damping and a speed cap. Thruster particle state is driven each frame. The **Shift boost** (§3.2.2) is the other half of the verb set.
- **Turning** is delegated in full to the `ShipTurnController` child (§3.2.1). `_handle_rotation` only reads the A/D axis, passes the cursor in via the project's single `get_global_mouse_position()` call, and assigns what `step()` returns. The old `rotation_speed_deg` export is gone from this script — it is now the controller's `keyboard_turn_rate_deg`.
- **Camera feel** (`_update_camera_feel`): steps the `OpenSpaceCameraRig` child (§3.2.5) with the ship's velocity and pushes its speed-zoom + lead-offset output into the child `Camera2D`'s `CameraDirector` under effect name `&"speed_feel"` at priority `0`. The planet dwell (below) overrides this at priority `10`, so approaching a planet smoothly takes over the camera.
- **Ship modules**: on `_ready()` it re-applies every module already equipped in `ShipModuleState` (reads `ShipModuleState.SLOTS` / `get_equipped`) and connects `module_equipped` / `module_unequipped` for live equip/unequip. Each frame it ticks all active modules. The `use_ability` action (H-key) is offered to modules first via `_input`. This is the same module system described in [`./global.md`](./global.md).
- **Death**: `_on_health_changed(0)` plays the explosion, shakes the camera, waits, and `reload_current_scene()` — i.e. respawn in the hub.

The ship scene (`player_ship.tscn`) is built by composition: `HealthComponent`, `ShieldComponent`, `OverheatComponent`, `TempHealthComponent`, a `HurtBox`, an `AttackStateMachine` (`WeaponState` + `WarheadMissileShootingState`), a `ShipTurnController`, a `BoostMeter`, an `OpenSpaceCameraRig`, an `AimReticle`, and a `MovementController` — all shared classes from `global/` and `assault/`, except `ShipTurnController`, `BoostMeter`, `OpenSpaceCameraRig` and `AimReticle`, which live beside the ship and are open-space-only by design. `OpenSpacePlayerShip._ready()` also builds a `BoostBar` alongside the existing `OverheatBar`, both `top_level` world-space bars repositioned every physics frame — see §3.2.4.

#### 3.2.1 Steering — `ShipTurnController`

`open_space/scenes/entities/player/ship_turn_controller.gd` (`class_name ShipTurnController extends Node`), a direct child of `PlayerShip` in `player_ship.tscn` and **the only thing in open space that writes the ship's `rotation`**. `player_ship.gd::_ready()` resolves it **by type**, not by node path, seeds its `scheme` from `SettingsState.get_open_space_scheme()` and its target angle from the hull's actual facing via `set_scheme()`, and connects `SettingsState.open_space_scheme_changed` to re-seed the live controller without a scene reload.

It is a pure step function over injected inputs — cursor world position, the A/D axis, `delta`. It reads no `Input` and never asks for the mouse itself: `Input.warp_mouse()` cannot place a cursor in a headless GUT run, so the mouse is read in exactly **one** line project-wide (`player_ship.gd::_handle_rotation`) and passed in. That is what makes the turn model testable at all.

Two schemes, selected by the `scheme` export:

| Scheme | Behaviour |
|---|---|
| `&"mouse"` (default) | Clamped exponential chase toward the cursor angle. The ship *leans into* the cursor rather than snapping: `angle_difference` for the signed, wrap-correct error, `1 - exp(-ln2 * delta / half_life)` for the frame-rate-independent approach, a hard per-frame cap, then `rotate_toward` to apply it so a large step cannot overshoot. |
| `&"keys"` | The pre-epic behaviour to the degree: `rotation += deg_to_rad(220) * turn * delta`, instantaneous, cursor ignored. |

| Export | Default | Job |
|---|---|---|
| `scheme` | `&"mouse"` | Which scheme is live. Seeded from `SettingsState` (`global.md` §3), not this default, once the ship is in the scene. |
| `keyboard_turn_rate_deg` | `220.0` | Classic turn rate. Must stay 220 — Classic is today's behaviour. |
| `mouse_max_turn_rate_deg` | `150.0` | The **balance** lever: the hard cap. 180° in 1.2 s. |
| `mouse_turn_half_life` | `0.14` | The **feel** lever: seconds to close half the remaining angle. |
| `mouse_dead_zone_px` | `48.0` | Ship→cursor **world** distance below which the target angle is held, so aim does not thrash when the cursor sits under the hull. Never measured from screen centre — the camera leads the ship by up to `OpenSpaceCameraRig.lead_max_px` (§3.2.5, default 90 px). |

The three mouse numbers are judgement calls that **no headless gate can validate**; they are `@export`s on the ship scene precisely so a fly-test is an inspector change. `set_steering_enabled(false)` freezes the target angle without pausing `step()`, so there is no rotation discontinuity when it re-enables; `player_ship.gd::_notification()` calls it on `NOTIFICATION_APPLICATION_FOCUS_OUT`/`_IN`, so alt-tabbing away no longer leaves the ship turning toward a cursor position the OS stopped updating. Pointer confinement and capture are explicitly out of scope (see plan), so the ship still holds a stale target if the cursor merely leaves the window while it keeps focus. `face_instant()`/`notify_mouse_moved()` let an AI-targeting snap survive until the player's next mouse movement. `is_snap_held()` and `is_steering_enabled()` are read-only accessors beside `get_target_angle()`, added purely so `AimReticle` (§3.2.7) can read the controller's state instead of duplicating it.

Covered by `tests/unit/test_ship_turn_controller.gd` (the turn model: frame-rate independence, the cap, no overshoot, ±PI wrap, the dead-zone edge, the 180° tie-break, Classic is unchanged, and disabled steering freezes the target with no resume jump) and `tests/integration/test_player_ship_turn_wiring.gd` (the anti-inert gate: the node is in the scene, `_handle_rotation` really delegates to it, the target is seeded from the hull and from `SettingsState`, the scheme-change signal re-seeds the live controller, `rotation_speed_deg` is gone, and `_notification()` really disables/re-enables steering on focus loss/gain).

#### 3.2.2 Boost — the `boost` action and `_step_boost()`

Shift is **hold-to-boost**. The first frame of a press slams the ship's momentum onto whatever heading the nose is pointing and launches it above cruise — so a 180° turn plus Shift replaces the ~3.0 s manual reversal the damping model used to cost — and holding the key sustains that speed, re-asserting `velocity = Vector2.UP.rotated(rotation) * boost_exit_speed` along the **current** nose every physics frame for as long as the meter allows. The redirect is **unconditional**: there is no angle test and no second branch, so a boost from rest, from cruise and from full reverse are all one readable behaviour (ULTRAKILL's rule; see the epic's `2-research.md`), and because the sustain re-reads `rotation` rather than a direction captured at the trigger, steering mid-hold carries the momentum with it — the flip is continuous, not one-shot.

The whole model lives in `player_ship.gd::_step_boost(boost_pressed: bool, boost_held: bool, delta: float)`, called **last** from `_handle_thrust()`, which does the feature's two `Input` reads (`is_action_just_pressed("boost")` for the edge, `is_action_pressed("boost")` for the level). Same seam as `ShipTurnController` above and for the same reason: `Input` can never report a press or a hold in a headless GUT run, so the model takes both as arguments and every test drives it directly. The call **must** stay the last line of `_handle_thrust()`: a sustained hold re-asserts `velocity` every frame, and that overwrite is what stops the thrust/damping block above it from fighting a held boost — `_speed_ceiling` is a clamp, never a force, so calling `_step_boost()` first would let a no-thrust-input frame damp the boost away underneath it.

| Export | Default | Job |
|---|---|---|
| `boost_exit_speed` | `700.0` | Speed the hull is slammed to, and re-slammed to every sustain frame. **Must exceed `max_speed` (420)** or the redirect reads as a brake — which is exactly what the deleted flip-boost's 200 px/s was. |
| `boost_hold_sec` | `0.35` | The **minimum** burn: a tap still buys this much sustained thrust (and pays for it — see §3.2.3), and, doubling up, the anti-mash retrigger floor. No longer the flame's tell — see `_boosting` below. |
| `boost_ceiling_decay` | `400.0` | px/s² the speed ceiling falls at once the boost actually stops. 700 → 420 in 0.70 s, so the whole above-cruise signature after a bare tap is ~0.7 s beyond the minimum burn. |

Several things about the shape of it are load-bearing:

- **`_boosting` (not `_boost_hold_left`) drives the flame and thruster tell.** `_boost_hold_left` ticks down unconditionally every frame once started and is a pure countdown timer — the minimum burn *and* the anti-mash floor — so it can reach zero while a long hold is still very much running. `_boosting` is what stays true for the whole burn, from the trigger frame through release-past-minimum or an empty meter, and is what `_handle_thrust()`'s thruster-state branches and the cyan `flame_boost` animation key off.
- **There is exactly one speed clamp**, and it is `_step_boost()`'s. `_handle_thrust()`'s old tail `max_speed` clamp is gone; in its place a `_speed_ceiling` is held at boost speed for the duration of `_boosting`, then `move_toward`s back to `max_speed` (linear, so exactly frame-rate independent) once the boost actually stops. It is floored at `max_speed`, so it only ever *permits* — normal handling is untouched the moment the boost ends.
- **Starting is gated on `not _boosting`, the retrigger floor, and the meter's level — not a spend.** `boost_pressed and not _boosting and _boost_hold_left <= 0.0 and (_boost_meter == null or _boost_meter.charges >= _boost_meter.min_start_charge)` short-circuits left to right, so a boost refused by either guard costs nothing, and mashing Shift while a boost is already running can never restart the minimum-burn timer. There is no upfront spend on the trigger frame — the cost is paid continuously by the sustain below.
- **The sustain drains the meter every frame it runs**, via `_boost_meter.drain(_boost_meter.drain_rate * delta)` (§3.2.3), and stops the boost the instant that returns `false` (meter empty) or the key is released past the minimum burn (`not boost_held and _boost_hold_left <= 0.0`). This is also why a bare tap still costs `boost_hold_sec * drain_rate` bar-units — the minimum burn keeps draining even after the key comes back up.
- **The `engine_boost_active` guard is deliberately doubled.** `_handle_thrust()` already returns early while an `EngineBoostModule` dash owns `velocity`, so `_step_boost()`'s own copy of that guard is dead code on the shipped call path. It is required anyway: every test calls `_step_boost()` directly and so bypasses the outer return, and without the inner line the two cases that pin module precedence fail on a *correct* build. `engine_boost_active` is **read** here and never written — it stays owned by `global/ship_modules/engine_boost_module.gd`.

`_step_boost()`'s tree touches are the flame: the trigger branch plays `flame_boost` on `SpriteAnchor/ShipSprite2D` and drives both `ThrusterEffect`s to `State.BOOST` (following `engine_boost_module.gd:15,63-67`), and `_release_boost_flame()` hands the sprite back to `idle` the moment `_boosting` turns false — `flame_boost` has `loop = false`, so without that the hull would sit on its last frame forever.

`project.godot` `[input]` binds `boost` to Shift (`physical_keycode 4194325`). That is the **third** action on that key — `dash` (infiltration) and `race_brake` (the assault race sub-mode) are the others — which is safe because the three consumers are separate scenes that each read only their own action name, and deliberate: reusing `dash` would make a future rebind of infiltration's dash silently move the open-space boost.

The numbers above are judgement calls **no headless gate can validate** and are `@export`s so a fly-test is an inspector change. Covered by `tests/integration/test_open_space_boost_verb.gd` (the redirect from rest / cruise / full reverse, facing rather than velocity picking the direction, the zero-velocity boundary, holding with no thrust input keeping full speed rather than decaying, steering mid-hold carrying the momentum within a frame, the tell tracking `_boosting` deep into a long hold, the ceiling permitting then closing and never falling below cruise, `_handle_thrust()` no longer re-clamping, the minimum-burn floor and its expiry, a tap burning the full minimum and no more, a press below `min_start_charge` changing nothing, the boost stopping exactly when the meter drains to zero and not auto-restarting, Shift held across a physics freeze not auto-resuming, module precedence, the flame and its release, the `boost` binding, and the regression that `_trigger_flip_boost()` / `boost_redirect_speed` / `boost_speed_threshold` are gone). The same file's Boost Drive tier-switch cases cover the 1/3/4-tank partition, a press spending exactly one tank and activating the module, a press short of a full tank refusing outright, a press refused by the module's own cooldown on an otherwise-full meter costing nothing, equipping/unequipping mid-session re-partitioning without losing charge, and H firing the module in assault but not in open space.

#### 3.2.3 The cost — `BoostMeter`

`open_space/scenes/entities/player/boost_meter.gd` (`class_name BoostMeter extends Node`), a direct child of `PlayerShip` in `player_ship.tscn`, resolved **by type** from `player_ship.gd::_ready()` exactly like `ShipTurnController`. It is the boost's charge economy and nothing else: no `Input`, no tree access, no `_physics_process`.

| Export | Default | Job |
|---|---|---|
| `recharge_rate` | `0.7` | Charges per second — one boost back per ~1.43 s. |
| `recharge_delay_sec` | `0.5` | Pause after a spend before any refill, the value `Overheat._SHOOT_GRACE` already uses. Without it a mashed key trickle-charges between activations. |
| `bind_progression` | `true` | Take `max_charges` from `ShipProgressionState.boost_charge_count` instead of the local default, and stay subscribed to `boost_charge_count_changed` for the rest of the meter's life. Explicitly authored `true` on the `BoostMeter` node in `player_ship.tscn` — the `@export` default is not trusted alone, since `player_ship.tscn`'s `ShieldComponent` shows what happens when a scene relies on the default instead (filed as `the-open-space-ship-never-reads-the-permanent-shield-upgrade`). |

`max_charges` starts at **2** (`ShipProgressionState.MIN_BOOST_CHARGES`) and rises with the save, up to **5** (`MAX_BOOST_CHARGES`) — mirroring `Shield`'s binding to `permanent_shield_count` line for line, including `_on_progression_changed()` granting the newly-unlocked charge immediately rather than waiting for the next full recharge or the next session. `charges` is a continuous float with three spend shapes on top of it: `try_spend()` (a whole unit, unused by the default Shift verb today), `drain(amount)` (a continuous per-frame spend — what the hold-to-boost sustain in §3.2.2 actually calls, at `drain_rate` bar-units/second, refusing by returning `false` the frame it would go negative rather than going negative), and `try_spend_tank()` (a whole *partition* of the pool at the current `tanks` count — the Boost Drive tier, below). Empty to full is ~3.4 s at base capacity (0.5 s pause + 2 / 0.7), ~7.6 s at the cap. `charges_changed(current: float, maximum: int)` is emitted on every spend, every drain, every refill tick, and every progression change — declared with its parameters, which `tests/integration/test_signal_emit_arity.gd` sweeps.

**Tanks and the long bar are the same pool, rendered and spent differently** (Ridge Racer 7's Standard/Extended/Quad nitrous is the shipped precedent). `tanks: int` (default `1`, one long bar) partitions `charges` into `tanks` equal slices of size `tank_size() = float(max_charges) / float(tanks)`; `set_tanks(n)` clamps to `>= 1`, is a no-op at the current value, emits `tanks_changed(tanks: int)` otherwise, and never touches `charges` — re-partitioning mid-flight neither grants nor loses charge. `OpenSpacePlayerShip._update_boost_tanks()` is the only caller: `tanks = 1` with no `engine_boost` module equipped in `&"engines"`, `3` once it is equipped, `4` once `ShipProgressionState.boost_charge_count` is also maxed (the player's own "3-4 parts depending on the amount of upgrades"). It runs from `_ready()` (seeded from whatever is already equipped) and from both `_on_module_equipped`/`_on_module_unequipped` — the latter passes `&""` for the engines slot explicitly rather than re-querying `ShipModuleState.get_equipped(&"engines")`, because `ShipModuleState.equip()` emits `module_unequipped` *before* it writes `_equipped[slot]`, so a query from that handler would read back the module in the process of being removed.

With `engine_boost` equipped, `_step_boost()`'s press branch stops running the hold-to-boost model at all and instead spends one tank on the module's own burst: `if drive.can_activate() and _boost_meter.try_spend_tank(): drive.try_activate(self)`, returning immediately on success so the module's 1500 px/s frame-one burst does not run into `_step_boost()`'s own tail clamp. Readiness is checked **before** the spend — `can_activate()` mirrors `try_activate()`'s own `not _active and _cooldown_left <= 0.0` guard — because the module's cooldown (2.0 s) outlasts the Shift-side retrigger floor (`boost_hold_sec = 0.35 s`); spending first would burn a tank on every press in that 0.35-2.0 s window for an activation that was always going to refuse. `EngineBoostModule.is_open_space_boost_verb() == true` closes the matching hole on **H**: `OpenSpacePlayerShip._input`'s module loop skips any module reporting it, so the same burst cannot also fire for free on H while Shift is the paid verb — `AssaultPlayer`'s own H loop does not consult this at all, so Boost Drive is unaffected in assault.

Two shape decisions are load-bearing:

- **The ship drives the clock.** `step(delta)` is called from `_step_boost()`; the meter has no `_physics_process` of its own, deliberately unlike `Overheat`. `set_physics_process(false)` on the ship (which `MissionTrigger._open_menu()` calls) does **not** stop a child's own physics tick, so a self-ticking meter would keep charging while a mission menu is open — and a hand-driven `step()` is what makes the component unit-testable in a headless run. The pause eats only as much of a frame as it needs and the remainder still recharges, so the rate does not depend on where the frame boundary fell.
- **It lives beside the ship, not in `global/components/`.** The boost is open-space-only, and this project's mode isolation is structural. `class_name` registers globally whatever directory the file sits in, so the directory is a signal of intent; the enforcement is the two invariant cases in `tests/integration/test_open_space_boost_wiring.gd` (neither `assault/scenes/player/player_fighter.tscn` nor `infiltration/scenes/entities/player/player.tscn` may carry a `BoostMeter` or a `BoostBar`, and no `.gd` outside `open_space/` may read the `boost` action). **`Shield` was rejected as a base or a shared component on purpose** — it implements four of the same five behaviours, but its charge is entangled with `consume_one()` on the incoming-damage chain, temporary charges, the hacked state and `ShieldIconStrip`'s snapshot `Dictionary`; merging would grow a damage-path component an upgrade-meter concept to save ~20 lines.

There is **no exhaustion/soft-failure state and no i-frames**. Boost is the verb the player crosses the hub with, so a meter below `min_start_charge` simply refuses to start while W/S still fly the ship; and blanket immunity is `EngineBoostModule`'s whole value as an equippable, so a free metered boost must not duplicate it.

`tests/unit/test_boost_meter.gd` covers the economy tree-less (`try_spend()`, `drain()`, `try_spend_tank()` and `set_tanks()`, partial/empty refusal, the pause, the rate, the clamp, `step(0.0)`, the signal's arity and values, and — with `bind_progression = true` driven by hand-calling `_ready()` on an unparented instance — the mid-session upgrade widening `max_charges` and granting the new charge immediately). `tests/integration/test_open_space_boost_wiring.gd` is the **anti-inert** gate: every unit case is green on a build where `BoostMeter` exists but was never added to `player_ship.tscn`, so the wiring file asserts the scene carries exactly one (found **by class**), that a held boost drains continuously from *that* node, that a meter below `min_start_charge` leaves `velocity` untouched, that a boost refused by `engine_boost_active` or by the retrigger floor burns no charge, that mashing Shift mid-hold does not over-drain, and that `_handle_thrust()` — not the meter itself — is what recharges it. `tests/unit/test_ship_progression_state.gd` covers `boost_charge_count` / `add_boost_charge` / `set_boost_charge_count` tree-less against `ShipProgressionScript.new()`, including the cap boundary, a corrupt-save clamp, and that raising the boost count leaves `permanent_shield_count` untouched on the shared `ConfigFile`.

#### 3.2.4 The readout — `BoostBar`

`open_space/scenes/gui/boost_bar.gd` (`class_name BoostBar extends Node2D`), created in `OpenSpacePlayerShip._ready()` the same way as `_overheat_bar` (`top_level = true`, `add_child`, repositioned every physics frame) and only when the ship actually carries a `BoostMeter`. It draws `OverheatBar`'s 32×4 shape at `global_position + (0, 26)` — 2 px clear of the overheat bar's own 4 px height at `(0, 20)` — split into `max_charges` 1 px-gapped segments filled in the thruster's cyan `Color(0.35, 0.9, 1.0)`.

Two things distinguish it from `OverheatBar`, both because a resource meter must not lie about its state:

- **Always visible, including at full charges.** `OverheatBar` hides itself until the first overheat tick; a boost meter that did the same would hide the exact resource the epic exists to surface.
- **`setup(meter)` seeds `_charges` / `_max_charges` from the meter and calls `queue_redraw()` *before* subscribing to `charges_changed`.** Children `_ready()` before parents, so `BoostMeter`'s initial state already exists by the time the ship's `_ready()` creates the bar — connect-only would leave the bar reading its zeroed defaults until the first spend, drawing an empty bar over a full meter on every freshly loaded hub. `_on_charges_changed` stores what it draws (`_charges: float`, `_max_charges: int`) exactly as `OverheatBar._percentage` does, so the fill and segment count are things a headless test can assert without touching `_draw()`.

`tests/integration/test_boost_bar.gd` covers the seed-before-signal case, that the bar stays visible at full, that it does not overlap the overheat bar (one physics frame awaited, on a ship left running rather than frozen — the bars only move from `_physics_process`), that the segment count follows `charges_changed`'s `maximum`, that the fill tracks a partial `current` rather than only capacity, and that zero capacity does not error.

#### 3.2.5 Camera feel — `OpenSpaceCameraRig`

`open_space/scenes/entities/player/open_space_camera_rig.gd` (`class_name OpenSpaceCameraRig extends Node`), a direct child of `PlayerShip` in `player_ship.tscn`, resolved **by type** from `player_ship.gd::_ready()` exactly like `ShipTurnController` and `BoostMeter`. It owns the speed-zoom + camera-lead formula behind the ship's `speed_feel` effect as a pure `step(velocity, delta)` / `get_offset()` / `get_zoom(velocity)`, so it is drivable and assertable with no `Camera2D` at all — the camera itself is not part of `player_ship.tscn` (it is added as a sibling-of-nothing child of `PlayerShip` in `sector_hub.tscn`, alongside its own `CameraDirector`), so every headless test that instantiates the ship scene alone takes `_update_camera_feel()`'s early return and never reaches a formula that lived inline.

It exists to fix a bug: the previous inline formula took the lead's *magnitude* from `velocity` but its *direction* from the hull's facing (`Vector2.UP.rotated(rotation)`), so turning the nose away from the ship's momentum swung the camera lead **opposite to travel**. The rig's direction is `velocity.normalized()`, never `rotation` — `OpenSpacePlayerShip` no longer reads its own `rotation` for this at all.

| Export | Default | Job |
|---|---|---|
| `lookahead_time` | `0.30` | Seconds of travel the raw lead is computed over: `velocity * lookahead_time`. |
| `lead_max_px` | `90.0` | Hard cap on the lead distance. |
| `lead_dead_zone_px` | `32.0` | Raw lead under this reads as zero, and is **subtracted** (not clipped) above it — so the applied lead grows continuously from the dead-zone edge instead of popping from 0 to 32 px the instant the ship crosses it. |
| `lead_half_life` | `0.20` | Smoothing half-life on the lead vector, separate from `CameraDirector.blend_speed` (which handles hand-off *between* effects, not this smoothing). |
| `zoom_min` | `0.85` | Zoom level at/above `zoom_speed_threshold`. |
| `zoom_speed_threshold` | `400.0` | Speed (px/s) at which the zoom reaches `zoom_min`. |
| `boost_zoom_bonus` | `0.06` | Extra pull-back while `set_boosting(true)` — the boost's camera punch. |

`get_motion_scale()` is public and load-bearing beyond the rig's own use: the rig owns the accessibility scale (`_motion_scale`, driven by `SettingsState.camera_motion` — `full`/`reduced`/`off` → `1.0`/`0.5`/`0.0`), but `CameraShake.add()` for the boost punch is called from the ship, outside the rig, and still has to honour the same setting. Every automatic-motion channel in the epic routes its amplitude through this one reader.

`_update_camera_feel()` on the ship now does only three things: step the rig with the live `velocity`, find the child `Camera2D` → find its `CameraDirector`, and push `director.set_effect(&"speed_feel", rig.get_zoom(velocity), rig.get_offset(), 0)`. The rig is stepped unconditionally (even with no camera present), so its smoothing state does not reset the moment a camera appears or disappears.

Covered by `tests/unit/test_open_space_camera_rig.gd` (tree-less, pure `step()`: the lead-magnitude cap, direction tracks the velocity argument, the dead-zone boundary settles to exactly zero, no pop at the dead-zone edge, frame-rate independence, `_motion_scale = 0.0` zeroes both offset and zoom, and boosting lowers the zoom target). **The epic's defining case is deliberately NOT there** — `step()` never receives `rotation`, so "lead follows velocity, not facing" is unobservable at the unit level and is guaranteed by the signature alone. `tests/integration/test_open_space_camera_wiring.gd` is the anti-inert file that drives a *real* ship under a `Camera2D` + `CameraDirector` harness matching `sector_hub.tscn` (`Camera2D` a direct child of the ship, `CameraDirector` a child of that — `_update_camera_feel()` finds both by exact node name and silently no-ops if either is missing), asserts the rig is wired into the scene by class, and — the defining case — sets `rotation = PI` (nose down) with `velocity = (0, -400)` (travelling up) and asserts the pushed offset has `y < 0`, plus the mirror case, so a stuck sign cannot pass either.

#### 3.2.6 Aim cursor — `AimCursor`

`global/systems/aim_cursor.gd` (`class_name AimCursor extends RefCounted`), a static-only helper — never instantiated — shared by any mode that wants a hardware crosshair instead of the OS arrow. It replaces the bare mouse arrow open space flew with: `build_image(size, color)` draws a 32×32 crosshair into an `Image` procedurally (four ticks around a transparent centre gap, so whatever is under the cursor stays visible), and `apply()`/`restore()` wrap `Input.set_custom_mouse_cursor()`.

Procedural, not PixelLab: it is a UI asset, not a world entity, so the top-down-orthographic rule doesn't apply, and it costs no monthly generation allowance. A hardware cursor rather than a `_draw()`-based software one: the engine docs call out that a software cursor "will add at least one frame of latency compared to a hardware mouse cursor" — the state *around* the aim point (dead zone, snap, hull lag) is a separate, ship-drawn layer instead (`AimReticle`, §3.2.7).

`Input.set_custom_mouse_cursor()` is **process-global and sticky** — it survives scene changes — so `OpenSpacePlayerShip` calls `AimCursor.apply()` from `_ready()` only under the `&"mouse"` scheme (there is no cursor steering to call out under `&"keys"`) and `AimCursor.restore()` unconditionally from `_exit_tree()`, which covers mission launch, the death `reload_current_scene()`, and quit alike. `restore()` is a safe no-op when `apply()` was never called, which is what lets the ship call it unconditionally regardless of scheme.

`Input`'s cursor state cannot be read back, so tests assert through a static `is_applied()` seam on `AimCursor` instead. Covered by `tests/unit/test_aim_cursor.gd` (the image: size, transparent centre, opaque ticks, requested colour; the apply/restore pairing; the boundary case of `restore()` with no prior `apply()`) and `tests/integration/test_open_space_aim_cursor.gd` (the anti-inert gate: a ship spawned under `&"mouse"` applies the cursor, one spawned under `&"keys"` never does, and freeing the ship restores it).

#### 3.2.7 Aim reticle — `AimReticle`

`open_space/scenes/gui/aim_reticle.gd` (`class_name AimReticle extends Node2D`), a direct child of `PlayerShip` in `player_ship.tscn`, resolved **by type** from `player_ship.gd::_ready()` exactly like `ShipTurnController`, `BoostMeter` and `OpenSpaceCameraRig`. Where `AimCursor` is the precise aim *point*, this is the *state* around it — the dead zone, the gap between where the nose is chasing and where it currently points, and whether an assist is overriding the player's own input. It sets `top_level = true` in its own `_ready()`, so `player_ship.gd::_physics_process` reassigns `_reticle.global_position = global_position` every frame exactly as it does for `_overheat_bar`/`_boost_bar` (§3.2.4) — offset `Vector2.ZERO` rather than the bars', since the ring is centred on the hull rather than stacked under it.

It is **fed**, never reading: `_handle_rotation` holds the project's one `get_global_mouse_position()` call, and on the line after `rotation = _turn.step(...)` it calls `_reticle.set_aim(_turn.mouse_dead_zone_px, _turn.get_target_angle(), rotation, _turn.is_snap_held(), _turn.is_steering_enabled())`. `set_aim()` stores what `_draw()` needs as members (`_ring_radius`, `_target_angle`, `_hull_angle`, `_state`) — the same shape `OverheatBar._percentage` uses, because a `_draw()`-only node exposes nothing a headless test can assert on. `_draw()` renders a ring at `_ring_radius` (read from the controller's `mouse_dead_zone_px` export, never duplicated) plus two ticks — one at the hull's actual angle, one at the controller's target angle — so the gap between them is the inertial turn lag made visible. The ring's colour is state-driven (`ring_color()`): normal, a warm colour while `_snap_held` (an AI-Targeting snap is being honoured — assists must be *visible*), or a dim grey while `!steering_enabled` (window unfocused); disabled wins over snap if both are somehow true.

Two independent things hide it, both because there is nothing useful to show: `set_scheme_visible(false)` under the `&"keys"` scheme (no cursor aiming to call out — set once from `_ready()`, mirroring `AimCursor`'s own non-reactive scheme check), and its own `_process()`, which polls `get_parent().is_physics_processing()` every frame and hides the ring whenever it is false. The poll is load-bearing rather than decorative: `MissionTrigger._open_menu()` freezes the ship via `ship.set_physics_process(false)`, which does **not** stop a child node's own processing, so nothing but the reticle's own check keeps the ring from being left mid-swing behind the mission menu.

Covered by `tests/unit/test_aim_reticle.gd` (what `set_aim()` stores; state/colour for normal, snap and disabled, with disabled winning over snap; the scheme-visible / physics-off gating in isolation, off-tree) and `tests/integration/test_aim_reticle_wiring.gd` (the anti-inert gate: the node is in the scene by class; the ship reassigns its `global_position` every physics frame; the ring radius comes from the live controller's `mouse_dead_zone_px`, not a copy; the hull tick tracks `rotation` post-step; the dead-zone-on-cursor boundary does not spin the target tick to world-right; a held snap and disabled steering both reach the ring; `&"keys"` hides it and `&"mouse"` shows it; and the ship's physics being off hides it regardless of scheme, with a resume case proving it reappears).

#### 3.2.8 Bank — the sprite lean

`player_ship.gd::_step_bank(rotation_delta: float, delta: float) -> float`, called from the tail of `_handle_rotation` right after `rotation = _turn.step(...)`. It smooths and clamps a turn-rate-proportional lean into `_bank_skew` (instance state, the same shape `_step_boost()`'s `_boost_hold_left`/`_boosting` use) and assigns it to `$SpriteAnchor/ShipSprite2D.skew` — **never** `$SpriteAnchor` itself, and never `rotation`. `ShipTurnController` stays the ship's only writer of `rotation` (§3.2.1); this is a sprite transform layered on top of what it wrote, computed from the delta between the hull's rotation before and after that write.

`$SpriteAnchor` also parents `MuzzleLeft`/`MuzzleRight` (the bullet spawn points `WeaponState` reads) and `EngineLeft`/`EngineRight`, and `Node2D.skew` propagates to children — skewing the anchor would shear all four along with the art. Skewing `ShipSprite2D` alone shears only the sprite.

| Export | Default | Job |
|---|---|---|
| `bank_max_rad` | `0.12` (~7°) | Hard clamp on the lean. `0.0` reverts the whole effect with no code change — the mitigation for "a shear on a top-down hull either reads as a lean or reads as a glitch, and no headless test can tell the difference." |
| `bank_rate_ref_deg` | `150.0` | Turn rate (deg/s) that saturates the lean at `bank_max_rad`; below it the lean scales linearly. |
| `bank_half_life` | `0.12` | Exponential smoothing half-life, both rising into a turn and decaying back to level once it stops. |

Covered by `tests/integration/test_open_space_flight_feel.gd`: `_step_bank()` driven directly with injected rotation deltas (zero for no change, saturates at `bank_max_rad`, sign-correct both directions, decays to zero once turning stops), plus two wiring boundaries on a real ship — `rotation` after a bank-driving `_handle_rotation()` call is (within float tolerance) exactly what `ShipTurnController.step()` returned, and `MuzzleLeft`/`MuzzleRight`/`EngineLeft`/`EngineRight` do not move a pixel across frames where the lean is non-zero but mid-decay (fails on a `$SpriteAnchor`-skewing build). **A human still has to fly it** — no headless test can say whether the lean itself reads as a lean or a glitch.

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
