# `infiltration/` Module

> Isometric ground-combat infiltration mode. See the [project structure overview](../../game-structure.md) for how `infiltration/` sits beside `assault/` and the race mode, and the [`global/` module doc](./global.md) for the shared components it builds on.

## 1. Overview

`infiltration/` is the game's **isometric, on-foot ground-combat mission** mode. Where `assault/` is a top-down vehicle/ship shooter, infiltration puts a single character on a faux-isometric ground plane and lets them walk, dash, and jump through an enemy-base environment.

The mode is currently an **early prototype centered on the player controller**. The shipping content is:

- A fully featured **player movement rig** (isometric walk, dash with afterimage particles, and a multi-mode vertical jump with double-jump / hover upgrades).
- A **height/elevation model** that fakes the third axis in 2D: a `z_position` (jump height) plus an `environment_height` (terrain elevation) offset the sprite upward while the shadow stays on the ground.
- A **stair-assist system** that smoothly ramps the player's environment elevation as they cross a ramp `Area2D`.
- A **test isometric level** that stages the player against a base-entrance backdrop and reuses the shared pause menu.

`effects/` and `entities/props/explosive_barrel/` exist as empty placeholder directories for planned content (afterimage/impact effects and destructible props) — there is no code in them yet.

The player is **not** built on the shared `global/entities/player_base.gd`; it is a standalone `CharacterBody2D` with its own composition of plain-`RefCounted`/`Resource` modules (see [Mechanics](#3-mechanics)). It reuses `global/` mainly through the shared **pause menu** and the **input map actions** defined at the project level.

## 2. Directory map

```
infiltration/
├── assets/
│   └── upgrades/                            # authored upgrade .tres resources
│       ├── double_jump_upgrade.tres         # DoubleJumpUpgrade instance
│       ├── hover_jump_upgrade.tres          # HoverJumpUpgrade instance
│       └── player_upgrade_loadout.tres      # default loadout (equips a hover upgrade)
├── scenes/
│   ├── effects/                             # (empty) placeholder for VFX scenes
│   ├── entities/
│   │   ├── player/
│   │   │   ├── player.gd                    # Player controller (CharacterBody2D) — orchestrator
│   │   │   ├── player.tscn                  # Player scene: sprite, shadow, camera, dash particles
│   │   │   ├── player.png / shadow.png      # sprite + ground-shadow textures
│   │   │   └── *.import / *.uid
│   │   └── props/
│   │       └── explosive_barrel/            # (empty) placeholder for a destructible prop
│   ├── levels/
│   │   ├── TestIsometricScene.tscn          # test mission: backdrop + Player + PauseMenu
│   │   └── enemy_base_entrance__template.png# isometric base-entrance backdrop art
│   └── systems/
│       └── stairs/
│           ├── stairs.gd                    # StairAssist (Area2D, @tool) — ramps elevation
│           └── stairs.tscn                  # StairAssist scene (CollisionPolygon2D)
└── scripts/
    └── player/                              # player logic split from the scene
        ├── config/                          # tunable @export Resource settings
        │   ├── player_movement_settings.gd  # PlayerMovementSettings (speed, iso Y scale)
        │   ├── player_dash_settings.gd      # PlayerDashSettings (speed, duration, cooldown…)
        │   └── player_jump_settings.gd      # PlayerJumpSettings (forces, gravity, hover…)
        ├── runtime/                         # per-frame stateful behaviour (RefCounted)
        │   ├── player_input_frame.gd        # PlayerInputFrame — one frame of input intent
        │   ├── player_locomotion.gd         # PlayerLocomotion — isometric velocity math
        │   ├── player_dash_state.gd         # PlayerDashState — dash timers/cooldown
        │   ├── player_jump_state.gd         # PlayerJumpState — vertical (z) physics + hover
        │   └── player_visual_controller.gd  # PlayerVisualController — sprite/shadow/particles
        └── upgrades/                        # data-driven player upgrades
            ├── player_upgrade.gd            # PlayerUpgrade (Resource) — base marker type
            ├── player_upgrade_loadout.gd    # PlayerUpgradeLoadout — equipped-upgrade set
            └── jump/
                ├── player_jump_upgrade.gd   # PlayerJumpUpgrade — base; mutates jump settings
                ├── double_jump_upgrade.gd   # DoubleJumpUpgrade — raises max_jumps
                └── hover_jump_upgrade.gd    # HoverJumpUpgrade — enables hover float
```

## 3. Mechanics

### 3.1 Player controller

The player is a `CharacterBody2D` defined by `infiltration/scenes/entities/player/player.gd` and its scene `player.tscn`. The scene tree is a sprite (`$Player`), a ground `$player_shadow`, a `$Camera2D`, a `$DashParticles` `GPUParticles2D`, and a flat collision box.

`player.gd` is a thin **orchestrator**: it owns the tunable settings resources and delegates all per-frame logic to four runtime modules that it builds in `refresh_modules()`:

| Module | File | Responsibility |
| --- | --- | --- |
| `PlayerLocomotion` | `scripts/player/runtime/player_locomotion.gd` | Converts input intent into world velocity, applying the isometric diagonal squash. |
| `PlayerDashState` | `scripts/player/runtime/player_dash_state.gd` | Tracks dash duration, cooldown, and afterimage-emission timers. |
| `PlayerJumpState` | `scripts/player/runtime/player_jump_state.gd` | Simulates the fake vertical axis (`z_position`/`z_velocity`), grounded/airborne, multi-jump and hover. |
| `PlayerVisualController` | `scripts/player/runtime/player_visual_controller.gd` | Offsets sprite/shadow by height, scales the shadow, and drives the dash particle direction/position. |

The frame loop in `_physics_process(delta)`:

1. `_read_input()` builds a `PlayerInputFrame` from the `move_left/right/up/down`, `jump`, and `dash` input-map actions (these actions are defined globally in `project.godot`, shared with the other modes).
2. `_update_move_memory()` remembers `last_move_dir` so a dash with no held direction fires along the last movement.
3. Dash and jump states are advanced; velocity comes from the dash direction while dashing, otherwise from the move vector.
4. `move_and_slide()` resolves horizontal motion, then `visuals.apply_height(...)` applies the combined elevation.

**Isometric movement** lives in `PlayerLocomotion.get_isometric_direction()`: pure cardinal input is unchanged, but diagonals have their `y` multiplied by `movement_settings.iso_diagonal_y_scale` (default `0.5`) before normalizing, so diagonal travel matches the 2:1 isometric tile slope. Walk speed is `PlayerMovementSettings.move_speed`.

**Dash** (`PlayerDashState`): `try_start()` snapshots a direction, starts `dash_duration`, and arms `dash_cooldown`. While `is_active()`, velocity is `dash_speed` along the dash direction. `should_emit_dash_effect()` gates afterimage spawning by `afterimage_interval` (the dash settings also reserve unused `grants_invulnerability` / `damages_targets_on_contact` flags for future combat work).

**Jump / vertical axis** (`PlayerJumpState`): there is no real Z in 2D, so the module integrates a `z_position` against `gravity`. `handle_input()` resolves a press into one of three outcomes — a grounded jump (`jump_force`), an air jump up to `max_jumps` (`air_jump_force`), or starting a **hover** when `hover_enabled` and not yet used. `update()` integrates gravity (scaled down by `hover_gravity_scale` while hovering), clamps to `hover_max_height_gain`, and calls `land()` when `z_position` returns to `0`. The resulting `z_position` is read back by the player to raise the sprite.

**Visuals** (`PlayerVisualController`): `apply_height(environment_height, z_position)` raises the player sprite by `environment_height + z_position`, raises the shadow only by `environment_height` (so it stays on the ground), and shrinks the shadow as jump height grows. Dash particles are pointed opposite the dash direction and parented at the sprite's current height.

#### Tunable settings (`scripts/player/config/`)

These are `@export` `Resource` types so they can be tuned per-scene in the inspector and reused as `.tres`:

- `PlayerMovementSettings` — `move_speed`, `iso_diagonal_y_scale`.
- `PlayerDashSettings` — `enabled`, `dash_speed`, `dash_duration`, `dash_cooldown`, `afterimage_interval`, plus the reserved combat flags.
- `PlayerJumpSettings` — `jump_force`, `air_jump_force`, `gravity`, `max_jumps`, and the hover block (`hover_enabled`, `hover_duration`, `hover_jump_force`, `hover_max_height_gain`, `hover_gravity_scale`).

#### Upgrades (`scripts/player/upgrades/`)

A small data-driven upgrade system reshapes the jump settings without touching the controller:

- `PlayerUpgrade` is a bare `Resource` marker base type.
- `PlayerUpgradeLoadout` holds an `applied_upgrades` array. `equip_upgrade()` replaces any existing upgrade of the same family (only one jump upgrade at a time), and `get_jump_upgrade()` returns the active one.
- `PlayerJumpUpgrade` exposes `apply_to_jump_settings(settings)`; subtypes override it: `DoubleJumpUpgrade` raises `max_jumps`/`air_jump_force` (and disables hover), `HoverJumpUpgrade` enables the hover float and tunes its parameters.

At runtime, `player.gd._build_jump_settings()` **duplicates** the base `PlayerJumpSettings` and lets the equipped jump upgrade mutate the copy, so the authored resource is never modified. `apply_upgrade()` / `clear_jump_upgrade()` re-equip and call `refresh_modules()` to rebuild the jump state live. Authored loadouts live in `infiltration/assets/upgrades/*.tres` (the default `player_upgrade_loadout.tres` ships with a hover upgrade equipped and is referenced by `player.tscn`).

### 3.2 Entities / enemies

The only implemented entity is the **player** (above). `scenes/entities/props/explosive_barrel/` is an empty placeholder — no enemies or destructible props are coded yet. When combat lands, the natural path is to reuse `global/` composition components (`HealthComponent`, `HurtBox`, `HitBox`, etc.) the same way `assault/` does — see the [`global/` module doc](./global.md).

### 3.3 Levels & systems

**Level** — `scenes/levels/TestIsometricScene.tscn` is the playable test mission: a `Node2D` root with the `enemy_base_entrance__template.png` backdrop, an instanced `Player`, and an instanced **`global/ui/pause_menu/pause_menu.tscn`** (cross-mode reuse from `global/`, documented in the [`global/` module doc](./global.md)).

**Stair-assist system** — `scenes/systems/stairs/stairs.gd` defines `StairAssist`, an `@tool` `Area2D`. It maps a body's position along a `bottom_local_point → top_local_point` axis to a 0–1 progress value and `lerp`s between `bottom_height` and `top_height`. Each `_physics_process` it pushes that height to any overlapping body via duck-typed calls to `set_environment_elevation(source, height)` / `clear_environment_elevation(source)`. The player implements those methods, storing each source's height in `elevation_sources` and taking the **max** as `environment_height` — so multiple overlapping ramps compose and the sprite floats up the stairs while the shadow stays grounded. Being `@tool`, it also draws debug UP/DOWN markers in the editor and can auto-guess its endpoints from the collision polygon.

### 3.4 Effects

`scenes/effects/` is an empty placeholder. The only effect currently realized is the **dash afterimage**, produced by the `$DashParticles` `GPUParticles2D` in `player.tscn` and driven by `PlayerVisualController` — not by a separate effect scene.

### 3.5 Reuse of `global/`

| Shared piece | Where used | Notes |
| --- | --- | --- |
| `global/ui/pause_menu/pause_menu.tscn` | `TestIsometricScene.tscn` | Instanced directly into the level. |
| Global input-map actions (`move_*`, `jump`, `dash`) | `player.gd._read_input()` | Defined in `project.godot`, shared across modes. |
| `global/` composition components (`HealthComponent`, `HurtBox`, …) | *not yet* | Available for future enemies/combat; see [`global/` doc](./global.md). |
| `global/entities/player_base.gd` | *not used* | Infiltration's player is a standalone rig, not derived from the shared base. |

## 4. Links

- [`global/` module](./global.md) — shared components, autoloads, pause menu, and input the infiltration mode builds on.
- [Project structure overview](../../game-structure.md) — how `infiltration/` relates to `assault/` and the other modes.
