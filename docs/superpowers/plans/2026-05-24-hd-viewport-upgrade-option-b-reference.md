# HD Viewport Upgrade — Option B: Camera Zoom Reference Plan

> **Status:** Reference only — not implemented. Kept as an alternative to Option A.
> Option A (1280×720 viewport) was chosen instead. See `2026-05-24-hd-viewport-upgrade-option-a.md`.

---

## What This Approach Does

Keep the viewport at **640×360**. Set `Camera2D.zoom = Vector2(2, 2)`. The camera now shows only a 320×180 world-unit slice of the scene, but renders it at 640×360 pixels — each world pixel becomes 2×2 screen pixels. New 64×64 sprites at `scale=(1,1)` appear at 128 screen pixels (same visual proportion as old 32×32 at scale=(2,2)).

## Why Option A Was Chosen Instead

`get_visible_rect().size` returns screen pixels (always 640×360) regardless of zoom. Every file in the codebase that computes "top/bottom/edge of screen" using `vp.size * 0.5` gets the wrong world-space value under zoom=2. That's ~10 enemy scripts, enemy_path_mover, 2 projectile files — all needing a `/ cam.zoom` fix. The total file count is similar to Option A but the changes are scattered logic edits rather than clean constant swaps.

## When to Reconsider This Approach

- If a future scene-by-scene zoom control is needed (Option A's viewport change is global)
- If non-assault scenes can't be adapted to 1280×720
- If runtime zoom transitions (pause menu zoom animation) already use Camera2D.zoom and a cleaner separation is needed

---

## Full Change List

### 1. Camera zoom — `assault/scenes/levels/edelia/1/level_1.tscn`

```
[node name="Camera2D" type="Camera2D" parent="." unique_id=671845157]
position = Vector2(320, 180)
zoom = Vector2(2, 2)        ← add this line
script = ExtResource("18_arcam")
```

### 2. Arena camera constants — `assault/scenes/systems/arena_camera.gd`

Halve SCREEN_W/H (the "design" viewport now shows only 320×180 world units):

```gdscript
const SCREEN_W : float = 320.0   # was 640
const SCREEN_H : float = 180.0   # was 360
const H_LIMIT  : float = 25.0    # was 50
const V_LIMIT  : float = 95.0    # was 190
```

Also halve the deadzone default:
```gdscript
@export var deadzone_half_size : Vector2 = Vector2(10.0, 7.5)  # was (20, 15)
```

### 3. Fix all viewport-size world math

**Root cause:** `get_visible_rect().size` returns screen pixels. Under zoom=2, world-visible half-height = `vp.y * 0.5 / zoom.y`, not `vp.y * 0.5`. Every file computing "screen edge in world space" needs this fix.

Replace pattern: `vp.y * 0.5` → `vp.y * 0.5 / cam.zoom.y`  (and `.x` variant for horizontal)

**Files to update:**

| File | Lines to fix |
|------|-------------|
| `assault/scenes/enemies/enemy_path_mover.gd` | `_check_off_screen`: `vp.y * 0.5` → `vp.y * 0.5 / cam.zoom.y` (×2), `vp.x * 0.5` → `vp.x * 0.5 / cam.zoom.x` (×2) |
| `assault/scenes/enemies/gunship/gunship.gd` | `_hold_y` calc + `_phase_retreat` queue_free check |
| `assault/scenes/enemies/ram_ship/ram_ship.gd` | off-screen bottom check |
| `assault/scenes/enemies/bomber/bomber.gd` | `half_w` calc |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd` | off-screen check (4 edges) |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.gd` | off-screen bottom check |
| `assault/scenes/enemies/sniper_skimmer/sniper_skimmer.gd` | `half_w` calc |
| `assault/scenes/enemies/light_assault_ship/states/approach_state.gd` | `hold_y` calc |
| `assault/scenes/enemies/light_assault_ship/states/strafe_exit_state.gd` | left/right edge calc |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` | arena constants (keep in world units; no zoom factor needed — these are world bounds) |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | same |

For the projectile arena bounds: since zoom doesn't change world space, the arena constants stay as-is. Bullets expire at the same world coordinates. ✓

For player bounds in `move_state.gd`: with zoom=2 and camera at (320,180), the player can reach world x ∈ [320 - (160+25), 320 + (160+25)] = [135, 505], y ∈ [180 - (90+95), 180 + (90+95)] = [-5, 365].

```gdscript
actor.global_position.x = clamp(actor.global_position.x, 135.0, 505.0)
actor.global_position.y = clamp(actor.global_position.y, -5.0, 365.0)
```

### 4. Change all existing 32×32 sprite scales — enemy scenes

All existing enemies use `scale = Vector2(2, 2)` on 32×32 sprites. With zoom=2, they'd appear at 128×128 screen pixels (too large). Change to `scale = Vector2(1, 1)`:

| Scene | Current scale |
|-------|--------------|
| `assault/scenes/enemies/fighter/fighter.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/bomber/bomber.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/ram_ship/ram_ship.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/interceptor/interceptor.tscn` | check and set (1,1) |
| `assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn` | (2,2) → (1,1) |
| `assault/scenes/enemies/bonus_drone/bonus_drone.tscn` | check and set (1,1) |
| `assault/scenes/player/player_fighter.tscn` | check and set (1,1) |
| All projectile scenes | check and set (1,1) |

New 64×64 sprites already use `scale = Vector2(1, 1)` — no change needed.

### 5. Player start position

With zoom=2, the visible world area is [160,480]×[90,270] (centered on cam at 320,180). The player should start near center-bottom of visible area: approximately `Vector2(302, 240)`.

### 6. No changes to wave spawn offsets or movement speeds

Under zoom=2, spawn offsets relative to cam.global_position stay valid — they're still in the same world space. Movement speeds (px/s) stay valid — the world size hasn't changed, only the zoom level. This is the main advantage over Option A.

---

## Summary: Option A vs Option B

| | Option A (viewport 1280×720) | Option B (zoom 2×) |
|--|--|--|
| Viewport change | Yes — affects all scenes | No |
| Files touched | ~9 (mostly constant swaps) | ~20 (logic edits + scene scales) |
| level_1_director changes | None (WORLD_SCALE handles it) | None |
| Spawn positions/speeds auto-scale | Via WORLD_SCALE constant | N/A (world size unchanged) |
| Enemy sprite scale changes | None needed | All enemy scenes need (2,2)→(1,1) |
| Viewport math fixes | None needed | ~10 files need `/ cam.zoom` |
| Design resolution going forward | 1280×720 (HD) | 640×360 (upscaled) |
