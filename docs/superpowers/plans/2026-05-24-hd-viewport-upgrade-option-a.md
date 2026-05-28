# HD Viewport Upgrade — Option A: 1280×720 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the assault-mission design resolution from 640×360 to 1280×720 so that native 64×64 sprites display at full quality, the arena is twice as spacious, and all positions/speeds scale automatically.

**Architecture:** A `WORLD_SCALE = 2.0` constant is added to `arena_camera.gd`. `WaveManager` multiplies spawn offsets by it; `EnemyPathMover` multiplies movement samples by it. All viewport-relative boundary code (`get_visible_rect().size * 0.5`) adapts automatically once the project resolution doubles. Only hardcoded constants (camera position, player position, arena bounds) need manual updates.

**Tech Stack:** Godot 4.3+, GDScript, `project.godot` display settings, `Camera2D`.

**Scope note:** `project.godot` affects ALL scenes. Non-assault scenes (menus, open_space) should be checked after this change — UI anchors and containers may need adjustment. This plan only covers assault-mission files.

**Speed note:** This plan scales spawn positions and EnemyPathMover movements by 2×. Speeds that use direct `velocity =` assignment are NOT automatically scaled:
- Player movement speed (`move_state.gd`)
- Enemy bullet / player bullet speeds
- Self-managed enemy speeds (gunship `entry_speed`, ram `speed`, etc.)

These remain at their old px/s values and will feel visually halved after the upgrade. A separate speed-tuning pass (doubling all `float` speed values in player and enemy configs) is needed for fully proportional gameplay. The game is playable in the interim.

---

## File Map

| File | Change |
|------|--------|
| `project.godot` | Viewport 640×360 → 1280×720 |
| `assault/scenes/levels/edelia/1/level_1.tscn` | Camera position + player start position ×2 |
| `assault/scenes/systems/arena_camera.gd` | Double all constants; add `WORLD_SCALE = 2.0`; double deadzone |
| `assault/scenes/player/states/move_state.gd` | Player bounds ×2; `move_speed` 180→360 |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` | Arena constants ×2 |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | Arena constants ×2 |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Multiply spawn offset by `ArenaCamera.WORLD_SCALE` |
| `assault/scenes/enemies/enemy_path_mover.gd` | Multiply `movement.sample()` by `ArenaCamera.WORLD_SCALE` |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Bonus drone `camera_offset` ×2 (2 constants only) |

---

## Task 1: Update project.godot viewport resolution

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Find and update the viewport size lines**

Find:
```
window/size/viewport_width=640
window/size/viewport_height=360
```

Replace with:
```
window/size/viewport_width=1280
window/size/viewport_height=720
```

- [ ] **Step 2: Verify no other resolution references exist**

Search for `640` and `360` in `project.godot` to confirm no other size-related settings reference the old resolution.

---

## Task 2: Update Camera2D and player start position in level_1.tscn

**Files:**
- Modify: `assault/scenes/levels/edelia/1/level_1.tscn`

The Camera2D must sit at the centre of the new 1280×720 viewport. The player start position must also scale proportionally.

- [ ] **Step 1: Update Camera2D position**

Find:
```
[node name="Camera2D" type="Camera2D" parent="." unique_id=671845157]
position = Vector2(320, 180)
```

Replace with:
```
[node name="Camera2D" type="Camera2D" parent="." unique_id=671845157]
position = Vector2(640, 360)
```

- [ ] **Step 2: Update PlayerFighter start position**

Find:
```
[node name="PlayerFighter" parent="." unique_id=1634176334 instance=ExtResource("3_60rwg")]
position = Vector2(302, 271)
```

Replace with:
```
[node name="PlayerFighter" parent="." unique_id=1634176334 instance=ExtResource("3_60rwg")]
position = Vector2(604, 542)
```

---

## Task 3: Update arena_camera.gd constants

**Files:**
- Modify: `assault/scenes/systems/arena_camera.gd`

- [ ] **Step 1: Double all constants and add WORLD_SCALE**

Find:
```gdscript
const SCREEN_W : float = 640.0
const SCREEN_H : float = 360.0
const H_LIMIT  : float = 50.0    ## Max horizontal offset (= horizontal buffer width).
const V_LIMIT  : float = 190.0   ## Max vertical offset   (= vertical buffer depth).
```

Replace with:
```gdscript
## Scale factor applied to all spawn offsets and EnemyPathMover movements.
## Keeps level_director spawn numbers in 640×360 "design units" that auto-scale.
const WORLD_SCALE : float = 2.0
const SCREEN_W : float = 1280.0
const SCREEN_H : float = 720.0
const H_LIMIT  : float = 100.0   ## Max horizontal offset (= horizontal buffer width).
const V_LIMIT  : float = 380.0   ## Max vertical offset   (= vertical buffer depth).
```

- [ ] **Step 2: Double the deadzone export default**

Find:
```gdscript
@export var deadzone_half_size : Vector2 = Vector2(20.0, 15.0)
```

Replace with:
```gdscript
@export var deadzone_half_size : Vector2 = Vector2(40.0, 30.0)
```

- [ ] **Step 3: Verify comment accuracy**

Update the file-level comment line that says `740 × 740` to say `1480 × 1480`, and `640×360` to `1280×720`, and `320, 180` to `640, 360`:

Find:
```gdscript
## Camera2D follow script for the 740 × 740 assault-mission play area.
```

Replace with:
```gdscript
## Camera2D follow script for the 1480 × 1480 assault-mission play area.
```

Find:
```gdscript
##   global_position stays permanently at the level origin (320, 180).
```

Replace with:
```gdscript
##   global_position stays permanently at the level origin (640, 360).
```

Find:
```gdscript
##   Horizontal ± 50 px  →  world x reachable: [-50, 690]
##   Vertical  ±190 px  →  world y reachable: [-190, 550]
```

Replace with:
```gdscript
##   Horizontal ± 100 px  →  world x reachable: [-100, 1380]
##   Vertical  ± 380 px  →  world y reachable: [-380, 1100]
```

---

## Task 4: Update player world bounds and move speed

**Files:**
- Modify: `assault/scenes/player/states/move_state.gd`

- [ ] **Step 1: Double the clamp bounds**

Find:
```gdscript
	## Hard world bounds: 740 x 740 play area centred on the normal 640 x 360 screen.
	## x [-50, 690]  /  y [-190, 550]
	actor.global_position.x = clamp(actor.global_position.x, -50.0, 690.0)
	actor.global_position.y = clamp(actor.global_position.y, -190.0, 550.0)
```

Replace with:
```gdscript
	## Hard world bounds: 1480 x 1480 play area centred on the 1280 x 720 screen.
	## x [-100, 1380]  /  y [-380, 1100]
	actor.global_position.x = clamp(actor.global_position.x, -100.0, 1380.0)
	actor.global_position.y = clamp(actor.global_position.y, -380.0, 1100.0)
```

- [ ] **Step 2: Double the move speed default**

Find:
```gdscript
@export var move_speed: float = 180.0
@export var max_move_speed: float = 200.0
```

Replace with:
```gdscript
@export var move_speed: float = 360.0
@export var max_move_speed: float = 400.0
```

---

## Task 5: Update projectile arena bounds

**Files:**
- Modify: `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`
- Modify: `assault/scenes/projectiles/missiles/homing/homing_missile.gd`

The arena bounds match the player's world area. Both files use identical constants.

- [ ] **Step 1: Update enemy_bullet.gd**

Find:
```gdscript
## Arena bounds matching arena_camera.gd (cam.global_position=(320,180),
## H_LIMIT=50, V_LIMIT=190, viewport 640×360):
##   x ∈ [-50, 690]   (640 + 2×50)
##   y ∈ [-190, 550]  (360 + 2×190)
## A small margin (32 px) lets bullets travel just past the edge before
## expiring, matching the visual boundary cleanly.
const _ARENA_MARGIN : float = 32.0
const _ARENA_LEFT   : float = -50.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float =  690.0 + _ARENA_MARGIN
const _ARENA_TOP    : float = -190.0 - _ARENA_MARGIN
const _ARENA_BOTTOM : float =  550.0 + _ARENA_MARGIN
```

Replace with:
```gdscript
## Arena bounds matching arena_camera.gd (cam.global_position=(640,360),
## H_LIMIT=100, V_LIMIT=380, viewport 1280×720):
##   x ∈ [-100, 1380]  (1280 + 2×100)
##   y ∈ [-380, 1100]  (720 + 2×380)
## A small margin (64 px) lets bullets travel just past the edge before
## expiring, matching the visual boundary cleanly.
const _ARENA_MARGIN : float = 64.0
const _ARENA_LEFT   : float = -100.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float = 1380.0  + _ARENA_MARGIN
const _ARENA_TOP    : float = -380.0  - _ARENA_MARGIN
const _ARENA_BOTTOM : float = 1100.0  + _ARENA_MARGIN
```

- [ ] **Step 2: Update homing_missile.gd**

Find:
```gdscript
## Arena bounds matching arena_camera.gd — same constants as EnemyBullet.
## x ∈ [-50, 690], y ∈ [-190, 550] plus a 32 px margin.
const _ARENA_MARGIN : float = 32.0
const _ARENA_LEFT   : float = -50.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float =  690.0 + _ARENA_MARGIN
const _ARENA_TOP    : float = -190.0 - _ARENA_MARGIN
const _ARENA_BOTTOM : float =  550.0 + _ARENA_MARGIN
```

Replace with:
```gdscript
## Arena bounds matching arena_camera.gd — same constants as EnemyBullet.
## x ∈ [-100, 1380], y ∈ [-380, 1100] plus a 64 px margin.
const _ARENA_MARGIN : float = 64.0
const _ARENA_LEFT   : float = -100.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float = 1380.0  + _ARENA_MARGIN
const _ARENA_TOP    : float = -380.0  - _ARENA_MARGIN
const _ARENA_BOTTOM : float = 1100.0  + _ARENA_MARGIN
```

---

## Task 6: Scale spawn offsets in WaveManager

**Files:**
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`

All `.at(x, y)` values in level directors are written in "design units" (the old 640×360 coordinate space). `WaveManager` must scale them up to the new 1280×720 world.

- [ ] **Step 1: Apply WORLD_SCALE to spawn offset**

Find:
```gdscript
	var spawn_pos: Vector2 = cam.global_position + spawn.get("offset", Vector2.ZERO)
```

Replace with:
```gdscript
	var spawn_pos: Vector2 = cam.global_position + spawn.get("offset", Vector2.ZERO) * ArenaCamera.WORLD_SCALE
```

- [ ] **Step 2: Verify the print log still uses spawn_pos (unchanged)**

Confirm line:
```gdscript
	print("[Spawn] %s at (%.0f, %.0f)" % [scene.resource_path.get_file(), spawn_pos.x, spawn_pos.y])
```
is still present and unchanged — it will now print the scaled world position, which is correct.

---

## Task 7: Scale movement samples in EnemyPathMover

**Files:**
- Modify: `assault/scenes/enemies/enemy_path_mover.gd`

`movement.sample(t)` returns a position offset in "design units." Multiplying by `WORLD_SCALE` converts it to the new world space. This handles all movement types (straight, sine, arc, u-sweep, sequence) automatically.

- [ ] **Step 1: Scale the position offset**

Find:
```gdscript
	var pos_offset: Vector2 = movement.sample(_elapsed)
	_actor.global_position = _initial_world_pos + pos_offset + Vector2(0.0, cam_scroll_y)
```

Replace with:
```gdscript
	var pos_offset: Vector2 = movement.sample(_elapsed) * ArenaCamera.WORLD_SCALE
	_actor.global_position = _initial_world_pos + pos_offset + Vector2(0.0, cam_scroll_y)
```

- [ ] **Step 2: Scale the velocity vector used for rotation**

Find:
```gdscript
		var vel: Vector2 = pos_offset - movement.sample(_elapsed - delta)
```

Replace with:
```gdscript
		var vel: Vector2 = pos_offset - movement.sample(_elapsed - delta) * ArenaCamera.WORLD_SCALE
```

---

## Task 8: Update bonus drone spawn offsets in level_1_director.gd

**Files:**
- Modify: `assault/scenes/levels/edelia/1/level_1_director.gd`

The bonus drone spawner bypasses `WaveManager` and sets `global_position` directly from `cam.global_position + camera_offset`. These two constants need manual doubling.

- [ ] **Step 1: Double the bonus drone camera offsets**

Find:
```gdscript
func _spawn_bonus_drone_left_to_right() -> void:
	_spawn_bonus_drone(Vector2(-340, 30), PI / 2)

func _spawn_bonus_drone_right_to_left() -> void:
	_spawn_bonus_drone(Vector2(340, 30), -PI / 2)
```

Replace with:
```gdscript
func _spawn_bonus_drone_left_to_right() -> void:
	_spawn_bonus_drone(Vector2(-680, 60), PI / 2)

func _spawn_bonus_drone_right_to_left() -> void:
	_spawn_bonus_drone(Vector2(680, 60), -PI / 2)
```

- [ ] **Step 2: Double the bonus drone movement speed**

Find:
```gdscript
	movement.speed = 280.0
```

Replace with:
```gdscript
	movement.speed = 560.0
```

---

## Self-Review

### Spec coverage

| Requirement | Task |
|-------------|------|
| Viewport 640×360 → 1280×720 | Task 1 |
| Camera at new viewport centre (640, 360) | Task 2 |
| Player start position proportional (604, 542) | Task 2 |
| `WORLD_SCALE = 2.0` constant defined | Task 3 |
| Arena camera follow constants ×2 | Task 3 |
| Player world bounds ×2 | Task 4 |
| Player move speed ×2 | Task 4 |
| Bullet/missile arena bounds ×2 | Task 5 |
| All wave spawn offsets auto-scaled via WaveManager | Task 6 |
| All EnemyPathMover movement distances auto-scaled | Task 7 |
| Bonus drone position and speed ×2 | Task 8 |

### Known follow-up work (out of scope)

After this plan is implemented and tested, a speed-tuning pass is needed:
- All enemy config `bullet_speed` values (e.g. `GunshipConfig.bullet_speed = 260`) → ×2
- All enemy config entry/movement speeds (self-managed AI: gunship, ram, etc.) → ×2
- Player weapon bullet speeds (in weapon config `.tres` files) → ×2
- Homing missile `speed` export → ×2
- All `hold_y_offset` values in enemy configs are now half their proportional distance from screen top — tune as needed
- Non-assault scenes (menus, open_space) may need UI/layout adjustments
