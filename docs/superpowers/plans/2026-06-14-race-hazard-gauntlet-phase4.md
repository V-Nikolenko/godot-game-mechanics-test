# Race Hazard Gauntlet — Phase 4 (Speed Feel) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline).

**Goal:** Make the race *feel* fast — a speed-reactive streak overlay and a camera zoom-punch on dash-panel boosts.

**Architecture:** A `SpeedStreaks` CanvasLayer overlay draws vertical streaks whose speed + alpha scale with the player's `top_speed_fraction()`. `PlayerRaceController._on_panel_boosted()` adds a quick self-restoring `Camera2D.zoom` kick (ArenaCamera only defers offset tracking while zoom ≠ ONE, so restoring to ONE is safe).

**Tech Stack:** Godot 4.6 / GDScript. Verification: in-editor parse + play-observation.

**Constraints:** NEVER commit (leave unstaged). Lane visible X ≈128–1152. Builds on the existing race speed economy (`RaceParticipant.top_speed_fraction()`, `panel_boosted`).

**Reference spec:** `docs/superpowers/specs/2026-06-14-race-hazard-gauntlet-design.md` (Phase 4 of 4).

---

## File Structure

```
NEW  assault/scenes/race/ui/speed_streaks.gd     SpeedStreaks: speed-reactive streak overlay
NEW  assault/scenes/race/ui/speed_streaks.tscn    CanvasLayer + Draw (Node2D) scene
EDIT assault/scenes/race/player_race_controller.gd  + camera zoom-punch on panel boost
EDIT assault/scenes/levels/race/race_level_1.tscn   instance SpeedStreaks
EDIT assault/scenes/race/track/RACE_HAZARDS.md / docs/architecture/modules/assault.md  (doc note)
```

---

## Task 1: SpeedStreaks script

**Files:** Create `assault/scenes/race/ui/speed_streaks.gd`

- [ ] **Step 1: Write the script**

```gdscript
## SpeedStreaks — a screen overlay that draws vertical streaks scrolling downward, with
## speed and opacity scaled by the player's top-speed fraction. Subtle/near-invisible at
## base speed, vivid near max. Attach to the Draw (Node2D) child of a CanvasLayer.
extends Node2D

@export var streak_count: int = 28
@export var color: Color = Color(0.7, 0.85, 1.0)
@export var max_alpha: float = 0.45        ## opacity at full speed (0 at base)
@export var streak_len_min: float = 20.0
@export var streak_len_max: float = 90.0
@export var slow_speed: float = 220.0      ## scroll px/s at base top speed
@export var fast_speed: float = 1500.0     ## scroll px/s at max top speed
@export var lane_min: float = 150.0
@export var lane_max: float = 1130.0
@export var screen_height: float = 720.0

var _ys: PackedFloat32Array = PackedFloat32Array()
var _xs: PackedFloat32Array = PackedFloat32Array()
var _len: PackedFloat32Array = PackedFloat32Array()
var _director: RaceDirector = null
var _frac: float = 0.0

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_ys.resize(streak_count)
	_xs.resize(streak_count)
	_len.resize(streak_count)
	for i in streak_count:
		_xs[i] = randf_range(lane_min, lane_max)
		_ys[i] = randf() * screen_height
		_len[i] = randf_range(streak_len_min, streak_len_max)

func _process(delta: float) -> void:
	var p := _director.get_player() if _director else null
	_frac = clampf(p.top_speed_fraction(), 0.0, 1.0) if p else 0.0
	var spd := lerpf(slow_speed, fast_speed, _frac)
	for i in streak_count:
		_ys[i] += spd * delta
		if _ys[i] > screen_height + _len[i]:
			_ys[i] = -_len[i]
			_xs[i] = randf_range(lane_min, lane_max)
	queue_redraw()

func _draw() -> void:
	var a := max_alpha * _frac
	if a <= 0.01:
		return
	var c := Color(color.r, color.g, color.b, a)
	for i in streak_count:
		draw_line(Vector2(_xs[i], _ys[i]), Vector2(_xs[i], _ys[i] + _len[i]), c, 2.0)
```

- [ ] **Step 2: Verify** — editor reload; no parse error.
- [ ] **Step 3: Leave unstaged.**

---

## Task 2: SpeedStreaks scene

**Files:** Create `assault/scenes/race/ui/speed_streaks.tscn`

- [ ] **Step 1: Write the scene** (CanvasLayer so it's screen-fixed; Draw child carries the script):

```
[gd_scene load_steps=2 format=3 uid="uid://bracestreaks01"]

[ext_resource type="Script" path="res://assault/scenes/race/ui/speed_streaks.gd" id="1_streaks"]

[node name="SpeedStreaks" type="CanvasLayer"]
layer = 1

[node name="Draw" type="Node2D" parent="."]
script = ExtResource("1_streaks")
```

- [ ] **Step 2: Verify** — opens in editor; has a `Draw` child with the script.
- [ ] **Step 3: Leave unstaged.**

---

## Task 3: Camera zoom-punch on panel boost

**Files:** Modify `assault/scenes/race/player_race_controller.gd`

- [ ] **Step 1: Add a tween field** near the other vars (after `var _last_health`):

```gdscript
var _zoom_tween: Tween = null
```

- [ ] **Step 2: Call the punch from `_on_panel_boosted()`** — add as the first line of the method:

```gdscript
func _on_panel_boosted() -> void:
	_punch_camera()
	if _ship and _ship.has_method("set_thruster_state"):
```

- [ ] **Step 3: Add the helper** (after `_on_panel_boosted`):

```gdscript
## Quick zoom-out kick on a dash-panel boost, then settle back to 1.0. ArenaCamera only
## defers its offset tracking while zoom ≠ (1,1), so restoring to ONE hands control back.
func _punch_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	cam.zoom = Vector2(0.94, 0.94)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(cam, "zoom", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
```

- [ ] **Step 4: Verify in play** — crossing a dash panel gives a quick zoom-out punch that settles; rapid panels restart cleanly (no stuck zoom).
- [ ] **Step 5: Leave unstaged.**

---

## Task 4: Instance SpeedStreaks in the level

**Files:** Modify `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Add the ext_resource** (near the other race ext_resources):

```
[ext_resource type="PackedScene" path="res://assault/scenes/race/ui/speed_streaks.tscn" id="streaks"]
```

- [ ] **Step 2: Instance it** as a child of `RaceLevel1` (e.g. right after the `HazardSystem` node):

```
[node name="SpeedStreaks" parent="." instance=ExtResource("streaks")]
```

- [ ] **Step 3: Verify in play** — at base speed the screen is clean; as top speed climbs (after panels) faint blue streaks appear and intensify/quicken, conveying speed; they fade as speed bleeds off.
- [ ] **Step 4: Leave unstaged.**

---

## Task 5: Update the knowledge base

**Files:** `docs/architecture/modules/assault.md` (+ `RACE_HAZARDS.md` if useful)

- [ ] **Step 1: Invoke `updating-project-docs`** — add a one-line "speed feel" note to the `assault.md` race section (speed-streak overlay + boost zoom-punch). No `PROJECT.md`/`CLAUDE.md` change.
- [ ] **Step 2: Leave unstaged.**

---

## Self-Review

**Spec coverage:** speed-streak overlay scaled by `top_speed_fraction()` (Tasks 1,2,4) ✓; boost zoom-punch on `panel_boosted` (Task 3) ✓. Completes Phase 4 / the gauntlet feature.

**Placeholder scan:** none. **Type consistency:** `top_speed_fraction()` (RaceParticipant), `panel_boosted`/`_on_panel_boosted` (existing), `get_camera_2d()` standard; `_zoom_tween` defined before use.
