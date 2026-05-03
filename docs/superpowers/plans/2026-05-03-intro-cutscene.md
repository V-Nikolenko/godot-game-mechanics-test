# Intro Cutscene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first-launch-only cinematic — ship flies bottom-left → top-right while the camera zooms in, then rotates to top-down — that auto-launches the Assault mission. Subsequent launches skip the cutscene and go straight to the Open Space hub. The system must be ergonomic for adding future cutscenes, dialog, and particle FX.

**Architecture:** A tiny `Boot` scene becomes the project's `main_scene`; in `_ready()` it queries `MissionState.has_cutscene_been_seen("intro_to_assault")` and routes either to the cutscene or the hub. A reusable `CutsceneBase` Node2D class supplies await-driven helpers (`wait_secs`, `tween_property`, `parallel_tween`, dialog) plus skip handling, persistence, and a `finished` signal that triggers a `next_scene_path` transition. Concrete cutscenes (starting with `IntroCutscene`) extend the base and define their beat sequence in `_run_cutscene()`. A `DialogPresenter` CanvasLayer stub renders subtitles today and can be wholesale-replaced later without changing call sites.

**Tech Stack:** Godot 4.4, GDScript with static types, `Tween` for animation, `ConfigFile` for persistence (already in `MissionState`), `CPUParticles2D` for environmental FX (matches existing `ThrusterEffect` / `RocketTrail` pattern).

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `global/autoloads/mission_state.gd` | Add `mark_cutscene_seen` + `has_cutscene_been_seen`; persist under `[__cutscenes__]` section |
| Create | `cutscenes/base/cutscene_base.gd` | Shared base class for all cutscenes — await helpers, skip, persistence, finished signal, scene transition |
| Create | `cutscenes/base/dialog_presenter.gd` | Async `present(speaker, text, duration)` — fade-in subtitle stub |
| Create | `cutscenes/base/dialog_presenter.tscn` | CanvasLayer + PanelContainer + 2 Labels |
| Create | `cutscenes/intro/intro_cutscene.gd` | First cutscene — defines 4 beats via `_run_cutscene()` |
| Create | `cutscenes/intro/intro_cutscene.tscn` | Camera, ship visual, starfield, dialog presenter |
| Create | `boot/boot.gd` | Routes to cutscene or hub on `_ready()` |
| Create | `boot/boot.tscn` | Empty Node holding `boot.gd` |
| Modify | `project.godot` | `run/main_scene = "res://boot/boot.tscn"` |

Total: 5 new files, 2 modified.

---

## Task 1: MissionState — cutscene flag persistence

**Files:**
- Modify: `global/autoloads/mission_state.gd`

The current `MissionState` autoload writes one ConfigFile section per `mission_id` with keys `completed` + `stars`. Cutscene flags are a separate concern — booleans keyed by cutscene id — so we'll store them in a single reserved section `[__cutscenes__]` with one boolean key per cutscene id. The double-underscore name guarantees it cannot collide with a real mission id.

- [ ] **Step 1: Add cutscene state and constants**

Open `global/autoloads/mission_state.gd`. Just below the existing `const SAVE_PATH := "user://mission_state.cfg"` line, add:

```gdscript
## Reserved ConfigFile section name for cutscene flags. The double-underscore
## prefix is namespaced to never collide with a mission id.
const _CUTSCENE_SECTION := "__cutscenes__"
```

Just below `var _data: Dictionary = {}`, add:

```gdscript
## Internal cache of cutscene flags: { cutscene_id: bool }
var _cutscenes: Dictionary = {}
```

- [ ] **Step 2: Add the public cutscene API**

Add these two functions just below `get_stars()`:

```gdscript
## Mark a cutscene as having been viewed at least once. Persists to disk.
func mark_cutscene_seen(cutscene_id: String) -> void:
	_cutscenes[cutscene_id] = true
	_save()

## True if `mark_cutscene_seen(cutscene_id)` was ever called (in this run or
## any previous run).
func has_cutscene_been_seen(cutscene_id: String) -> bool:
	return _cutscenes.get(cutscene_id, false)
```

- [ ] **Step 3: Update `_save` to write cutscene flags**

Replace the existing `_save()` function with:

```gdscript
func _save() -> void:
	var cfg := ConfigFile.new()
	for mission_id: String in _data:
		var entry: Dictionary = _data[mission_id]
		cfg.set_value(mission_id, "completed", entry.get("completed", false))
		cfg.set_value(mission_id, "stars", entry.get("stars", 0))
	for cutscene_id: String in _cutscenes:
		cfg.set_value(_CUTSCENE_SECTION, cutscene_id, _cutscenes[cutscene_id])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("MissionState: failed to save '%s' (error %d)" % [SAVE_PATH, err])
```

- [ ] **Step 4: Update `_load` to read cutscene flags**

Replace the existing `_load()` function with:

```gdscript
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no save file yet — fresh start
	for section: String in cfg.get_sections():
		if section == _CUTSCENE_SECTION:
			for key: String in cfg.get_section_keys(section):
				_cutscenes[key] = cfg.get_value(section, key, false)
		else:
			_data[section] = {
				"completed": cfg.get_value(section, "completed", false),
				"stars": cfg.get_value(section, "stars", 0),
			}
```

- [ ] **Step 5: Verify the autoload still parses**

Open the project in Godot. The Output panel should show no errors. Existing missions still complete and persist correctly because the `[__cutscenes__]` section name does not match any real mission id.

- [ ] **Step 6: Commit**

```bash
git add global/autoloads/mission_state.gd
git commit -m "feat: extend MissionState with cutscene-seen flag persistence"
```

---

## Task 2: DialogPresenter — subtitle stub

**Files:**
- Create: `cutscenes/base/dialog_presenter.gd`
- Create: `cutscenes/base/dialog_presenter.tscn`

A minimal CanvasLayer + PanelContainer with two Labels (speaker + text) that fades in, holds, and fades out. Cutscenes call `await dialog.present("Captain", "We've reached the sector.", 2.5)`. Future replacement (full dialog system, voice lines, choices) only needs to keep that signature.

- [ ] **Step 1: Write `dialog_presenter.gd`**

Create `cutscenes/base/dialog_presenter.gd`:

```gdscript
## DialogPresenter — minimal subtitle UI for cutscenes.
## Fades a panel in, holds the text for `duration` seconds, fades it out.
## Future dialog systems (voice, choices, portraits) can replace the internals
## without changing the `present()` signature — every cutscene awaits this API.
class_name DialogPresenter
extends CanvasLayer

@onready var _panel: PanelContainer = $Panel
@onready var _speaker_label: Label = $Panel/Margin/VBox/SpeakerLabel
@onready var _text_label: Label = $Panel/Margin/VBox/TextLabel

const _FADE_SEC := 0.3

func _ready() -> void:
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.visible = false

## Show one line. Awaitable — completes after fade-out finishes.
## `speaker` may be empty (in which case the speaker line is hidden).
func present(speaker: String, text: String, duration: float = 2.5) -> void:
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_text_label.text = text
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.visible = true

	var fade_in := create_tween()
	fade_in.tween_property(_panel, "modulate:a", 1.0, _FADE_SEC)
	await fade_in.finished

	await get_tree().create_timer(duration).timeout

	var fade_out := create_tween()
	fade_out.tween_property(_panel, "modulate:a", 0.0, _FADE_SEC)
	await fade_out.finished
	_panel.visible = false
```

- [ ] **Step 2: Write `dialog_presenter.tscn`**

Create `cutscenes/base/dialog_presenter.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://b8h6n2q5m4y9j"]

[ext_resource type="Script" path="res://cutscenes/base/dialog_presenter.gd" id="1_dialog"]

[node name="DialogPresenter" type="CanvasLayer"]
layer = 100
script = ExtResource("1_dialog")

[node name="Panel" type="PanelContainer" parent="."]
anchors_preset = 12
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 80.0
offset_top = -160.0
offset_right = -80.0
offset_bottom = -40.0
grow_horizontal = 2
grow_vertical = 0

[node name="Margin" type="MarginContainer" parent="Panel"]
layout_mode = 2
theme_override_constants/margin_left = 16
theme_override_constants/margin_top = 12
theme_override_constants/margin_right = 16
theme_override_constants/margin_bottom = 12

[node name="VBox" type="VBoxContainer" parent="Panel/Margin"]
layout_mode = 2

[node name="SpeakerLabel" type="Label" parent="Panel/Margin/VBox"]
layout_mode = 2
theme_override_colors/font_color = Color(0.8, 0.95, 1, 1)
text = "Speaker"

[node name="TextLabel" type="Label" parent="Panel/Margin/VBox"]
layout_mode = 2
text = "Dialog text"
autowrap_mode = 3
```

- [ ] **Step 3: Verify the scene opens cleanly**

Open `dialog_presenter.tscn` in Godot. Confirm the tree has CanvasLayer → Panel → Margin → VBox → SpeakerLabel + TextLabel. The panel should be docked at the bottom of the viewport in the editor preview.

- [ ] **Step 4: Commit**

```bash
git add cutscenes/base/dialog_presenter.gd cutscenes/base/dialog_presenter.tscn
git commit -m "feat: add DialogPresenter stub with awaitable present() API"
```

---

## Task 3: CutsceneBase — shared base class

**Files:**
- Create: `cutscenes/base/cutscene_base.gd`

`CutsceneBase` is the contract every cutscene scene satisfies. Subclasses override `_run_cutscene()` and call helper methods. Skip support, persistence, and the `next_scene_path` hand-off live here so subclasses stay focused on the visual sequence.

- [ ] **Step 1: Write `cutscene_base.gd`**

Create `cutscenes/base/cutscene_base.gd`:

```gdscript
## CutsceneBase — base class for cinematic cutscenes.
##
## Subclasses override `_run_cutscene()` and use the helpers below to compose
## a sequence with `await`. Common features handled here:
##   - Skip via `skip_action` (default "ui_cancel")
##   - Persistence: when `persistence_id` is non-empty, marks the cutscene as
##     seen via MissionState on finish (skipped or natural completion both count)
##   - Scene transition: when `next_scene_path` is non-empty, loads it on finish
##   - `finished` signal so external code can react if needed
##
## Subclasses should check `is_skipped()` between awaitable calls and return
## early — this is what makes the skip feel responsive.
class_name CutsceneBase
extends Node2D

signal finished

@export var skip_action: String = "ui_cancel"
## Scene loaded automatically when the cutscene finishes (skipped or naturally).
## Leave empty to do nothing.
@export_file("*.tscn") var next_scene_path: String = ""
## Persistence key passed to MissionState.mark_cutscene_seen() on finish.
## Leave empty for cutscenes that should always replay (debug/menu).
@export var persistence_id: String = ""

var _skipped: bool = false
var _finished: bool = false

func _ready() -> void:
	_run_cutscene()

func _unhandled_input(event: InputEvent) -> void:
	if not _finished and event.is_action_pressed(skip_action):
		skip()

## Override in subclass — define the cutscene's beat sequence here.
func _run_cutscene() -> void:
	push_warning("CutsceneBase._run_cutscene() not overridden — finishing immediately")
	_on_finish()

## End the cutscene right now. Pending awaits in the subclass should detect this
## via `is_skipped()` and return early.
func skip() -> void:
	if _skipped or _finished:
		return
	_skipped = true
	_on_finish()

func is_skipped() -> bool:
	return _skipped

# ── Awaitable helpers ───────────────────────────────────────────────────

## Wait for `seconds`. Use between beats.
func wait_secs(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Tween a single property to `final_value` over `seconds`. Returns when done.
## If `seconds` <= 0 the value is set instantly without creating a Tween.
func tween_property(node: Object, property: String, final_value: Variant,
		seconds: float, transition: int = Tween.TRANS_QUAD,
		ease_type: int = Tween.EASE_IN_OUT) -> void:
	if seconds <= 0.0:
		node.set(property, final_value)
		return
	var t := create_tween()
	t.set_trans(transition).set_ease(ease_type)
	t.tween_property(node, property, final_value, seconds)
	await t.finished

## Build a parallel Tween. Caller stacks tween_property calls on it then awaits
## the returned Tween's `.finished`.
##
## Example:
##   var t := parallel_tween()
##   t.tween_property(camera, "zoom", Vector2(2,2), 3.0)
##   t.tween_property(camera, "position", Vector2.ZERO, 3.0)
##   await t.finished
func parallel_tween() -> Tween:
	var t := create_tween()
	t.set_parallel(true)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return t

# ── Lifecycle ───────────────────────────────────────────────────────────

func _on_finish() -> void:
	if _finished:
		return
	_finished = true
	if not persistence_id.is_empty():
		MissionState.mark_cutscene_seen(persistence_id)
	finished.emit()
	if not next_scene_path.is_empty():
		get_tree().change_scene_to_file(next_scene_path)
```

- [ ] **Step 2: Verify the script parses**

Save the file. Godot Output panel must show no errors. The script will not be exercised until Task 4 instantiates a subclass.

- [ ] **Step 3: Commit**

```bash
git add cutscenes/base/cutscene_base.gd
git commit -m "feat: add CutsceneBase with await helpers, skip support, and finish routing"
```

---

## Task 4: IntroCutscene script

**Files:**
- Create: `cutscenes/intro/intro_cutscene.gd`

The concrete cutscene. All beat tunables are exported so the sequence can be tweaked from the Inspector without editing code — same pattern as the planet's arc tunables.

- [ ] **Step 1: Write `intro_cutscene.gd`**

Create `cutscenes/intro/intro_cutscene.gd`:

```gdscript
## IntroCutscene — the first-launch cinematic.
##
## Beat plan:
##   0. Setup: camera zoomed out, ship at start position pointing toward
##      the top-right at `ship_heading_deg`.
##   1. Ship flies in from start_pos toward mid_pos while the camera
##      simultaneously zooms to gameplay zoom and recenters on the ship.
##   2. Brief pause for narrative breathing room (and future dialog).
##   3. Camera rotates so the ship's heading aligns with screen-up.
##   4. Ship drifts forward in its new (now visually-up) heading and the
##      cutscene transitions to the assault mission.
##
## All distances/times are exported so a designer can re-time the sequence
## from the editor.
class_name IntroCutscene
extends CutsceneBase

@onready var ship: Node2D = $Ship
@onready var thruster: ThrusterEffect = $Ship/Thruster
@onready var camera: Camera2D = $Camera2D
@onready var dialog: DialogPresenter = $DialogLayer

@export_category("Cutscene Beats")
## Camera zoom while the ship is "small in the distance" at beat 0.
@export var start_zoom: Vector2 = Vector2(0.6, 0.6)
## Camera zoom that matches gameplay (player_ship's Camera2D uses Vector2(2,2)).
@export var end_zoom: Vector2 = Vector2(2.0, 2.0)
## Ship's world position at beat 0 (off-screen bottom-left).
@export var ship_start_pos: Vector2 = Vector2(-500.0, 400.0)
## Ship's world position at the end of beat 1 (mid-screen).
@export var ship_mid_pos: Vector2 = Vector2(0.0, 0.0)
## Ship's heading. -45° = pointing toward the top-right (UP rotated -45°).
@export var ship_heading_deg: float = -45.0
## Distance the ship drifts forward during beat 4.
@export var final_drift_distance: float = 350.0

@export_category("Cutscene Timing")
@export var beat1_duration: float = 4.0          ## fly-in + zoom-in
@export var pause_duration: float = 1.0          ## narrative pause
@export var camera_rotation_duration: float = 1.5
@export var final_drift_duration: float = 1.5

func _run_cutscene() -> void:
	# ── Beat 0: setup (instant) ─────────────────────────────────────────
	camera.zoom = start_zoom
	camera.position = (ship_start_pos + ship_mid_pos) * 0.5
	camera.rotation = 0.0
	ship.position = ship_start_pos
	ship.rotation = deg_to_rad(ship_heading_deg)
	thruster.set_state(ThrusterEffect.State.THRUST)

	# ── Beat 1: ship flies in + camera zooms to gameplay zoom ───────────
	var t1 := parallel_tween()
	t1.tween_property(ship, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "position", ship_mid_pos, beat1_duration)
	t1.tween_property(camera, "zoom", end_zoom, beat1_duration)
	await t1.finished
	if is_skipped(): return

	# ── Beat 2: narrative pause + future dialog hook ────────────────────
	# Replace this stub call with actual lines once the dialog system
	# has portraits/voice. The await contract is already in place.
	# await dialog.present("Captain", "We've reached the target sector.", pause_duration)
	await wait_secs(pause_duration)
	if is_skipped(): return

	# ── Beat 3: camera rotates so ship heading aligns with screen-up ────
	# Camera rotation == ship rotation makes the ship's local +Up appear
	# as screen +Up — i.e. the gameplay top-down orientation.
	thruster.set_state(ThrusterEffect.State.BOOST)
	await tween_property(camera, "rotation", ship.rotation,
			camera_rotation_duration, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	if is_skipped(): return

	# ── Beat 4: ship drifts forward into the next mission ───────────────
	var forward := Vector2.UP.rotated(ship.rotation)
	var ship_end := ship.position + forward * final_drift_distance
	var t4 := parallel_tween()
	t4.tween_property(ship, "position", ship_end, final_drift_duration)
	t4.tween_property(camera, "position", ship_end, final_drift_duration)
	await t4.finished

	_on_finish()
```

- [ ] **Step 2: Commit**

```bash
git add cutscenes/intro/intro_cutscene.gd
git commit -m "feat: add IntroCutscene script with 4-beat sequence and tunable timings"
```

---

## Task 5: IntroCutscene scene

**Files:**
- Create: `cutscenes/intro/intro_cutscene.tscn`

Scene tree:

```
IntroCutscene (Node2D)              ← script: intro_cutscene.gd, persistence_id="intro_to_assault", next_scene_path=level_1.tscn
├── Background (ColorRect)           ← deep space backdrop
├── Camera2D                         ← current=true, anchor mode top-left
│   └── StarField (CPUParticles2D)   ← child of camera so it always fills the viewport
├── Ship (Node2D)
│   ├── Sprite2D                     ← reuses h_assault_fighter atlas Rect2(1,1,32,32)
│   └── Thruster (ThrusterEffect)    ← position (0, 14), same engine flame as gameplay
└── DialogLayer                      ← instance of dialog_presenter.tscn
```

- [ ] **Step 1: Write `intro_cutscene.tscn`**

Create `cutscenes/intro/intro_cutscene.tscn`:

```
[gd_scene load_steps=8 format=3 uid="uid://c4r7x9k3n8m2p"]

[ext_resource type="Script" path="res://cutscenes/intro/intro_cutscene.gd" id="1_intro"]
[ext_resource type="Texture2D" uid="uid://dbd7dsu05uan4" path="res://assault/assets/sprites/h_assault_fighter.png" id="2_atlas"]
[ext_resource type="Script" path="res://global/components/thruster_effect.gd" id="3_thruster"]
[ext_resource type="PackedScene" uid="uid://b8h6n2q5m4y9j" path="res://cutscenes/base/dialog_presenter.tscn" id="4_dialog"]

[sub_resource type="AtlasTexture" id="AtlasTexture_ship"]
atlas = ExtResource("2_atlas")
region = Rect2(1, 1, 32, 32)

[sub_resource type="Gradient" id="Gradient_star"]
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture1D_star"]
gradient = SubResource("Gradient_star")

[node name="IntroCutscene" type="Node2D"]
script = ExtResource("1_intro")
persistence_id = "intro_to_assault"
next_scene_path = "res://assault/scenes/levels/level_1.tscn"

[node name="Background" type="ColorRect" parent="."]
offset_left = -2000.0
offset_top = -2000.0
offset_right = 2000.0
offset_bottom = 2000.0
color = Color(0.02, 0.02, 0.05, 1)

[node name="Camera2D" type="Camera2D" parent="."]
zoom = Vector2(0.6, 0.6)

[node name="StarField" type="CPUParticles2D" parent="Camera2D"]
amount = 80
lifetime = 6.0
preprocess = 6.0
emission_shape = 3
emission_rect_extents = Vector2(640, 50)
direction = Vector2(0, 1)
spread = 0.0
gravity = Vector2(0, 0)
initial_velocity_min = 30.0
initial_velocity_max = 80.0
scale_amount_min = 1.0
scale_amount_max = 3.0
color_ramp = SubResource("GradientTexture1D_star")
position = Vector2(0, -400)

[node name="Ship" type="Node2D" parent="."]
position = Vector2(-500, 400)

[node name="Sprite2D" type="Sprite2D" parent="Ship"]
texture_filter = 1
texture = SubResource("AtlasTexture_ship")

[node name="Thruster" type="Node2D" parent="Ship"]
position = Vector2(0, 14)
script = ExtResource("3_thruster")

[node name="DialogLayer" parent="." instance=ExtResource("4_dialog")]
```

Key points:
- The root node sets `persistence_id = "intro_to_assault"` and `next_scene_path = "res://assault/scenes/levels/level_1.tscn"` as property overrides — these read directly into `CutsceneBase`'s exported vars
- `StarField` is parented to `Camera2D` so it stays viewport-locked through camera moves; `direction = (0, 1)` (camera-local +Y) keeps stars drifting "down on screen" no matter how the camera rotates
- `emission_rect_extents = Vector2(640, 50)` and `position = (0, -400)` mean stars spawn in a 1280×100 strip above the camera and drift down through it
- `preprocess = 6.0` matches `lifetime` so the field is fully populated the moment the cutscene starts (no empty initial frames)
- `Thruster` is a `Node2D` with `ThrusterEffect`'s script attached — the same component player_ship.gd uses

- [ ] **Step 2: Open in Godot and verify the tree**

Open `intro_cutscene.tscn`. Confirm every node appears in the tree as listed above. The `Ship` node should display the assault fighter sprite. The `Camera2D` should have `current = true` (this is Godot's default for an isolated Camera2D in a scene, but verify in the Inspector).

- [ ] **Step 3: Commit**

```bash
git add cutscenes/intro/intro_cutscene.tscn
git commit -m "feat: add IntroCutscene scene with ship, camera, starfield, dialog layer"
```

---

## Task 6: Boot scene — entry router

**Files:**
- Create: `boot/boot.gd`
- Create: `boot/boot.tscn`

The Boot scene is the new `main_scene`. Its only job is to deferred-load either the intro cutscene or the hub. Keeping this as a thin router (rather than dropping the logic into the cutscene or the hub) means future entry-time decisions (login screens, language selection, save slots) have an obvious home.

- [ ] **Step 1: Write `boot.gd`**

Create `boot/boot.gd`:

```gdscript
## Boot — single-frame router that runs on game launch.
## Decides which scene the player actually starts in.
##
## Today: intro cutscene on first launch, hub on every launch after.
## Future hooks (save slot picker, login, splash) belong here too.
extends Node

const INTRO_CUTSCENE_ID := "intro_to_assault"
const INTRO_PATH := "res://cutscenes/intro/intro_cutscene.tscn"
const HUB_PATH := "res://open_space/scenes/levels/sector_hub.tscn"

func _ready() -> void:
	var path: String
	if MissionState.has_cutscene_been_seen(INTRO_CUTSCENE_ID):
		print("[BOOT] intro already seen — going to hub")
		path = HUB_PATH
	else:
		print("[BOOT] first launch — playing intro cutscene")
		path = INTRO_PATH
	get_tree().change_scene_to_file.call_deferred(path)
```

- [ ] **Step 2: Write `boot.tscn`**

Create `boot/boot.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://d3p9q1k7m5n2j"]

[ext_resource type="Script" path="res://boot/boot.gd" id="1_boot"]

[node name="Boot" type="Node"]
script = ExtResource("1_boot")
```

- [ ] **Step 3: Commit**

```bash
git add boot/boot.gd boot/boot.tscn
git commit -m "feat: add Boot router scene that picks intro cutscene vs hub on launch"
```

---

## Task 7: Wire Boot as `main_scene`

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Update `project.godot`**

Open `project.godot`. Find the `[application]` section. Replace the existing `run/main_scene=` line with:

```ini
run/main_scene="res://boot/boot.tscn"
```

If there is no `run/main_scene=` key in the section, add it.

- [ ] **Step 2: Verify the first-launch path**

1. Delete `C:\Users\Lonli\AppData\Roaming\Godot\app_userdata\game-test-mechanics\mission_state.cfg` (or rename it temporarily)
2. Run the project from Godot (F5)
3. Expected console output:
   `[BOOT] first launch — playing intro cutscene`
4. Expected visual: ship appears small at bottom-left, flies toward the centre while the camera zooms in. After ~1s pause the camera rotates so the ship now visually flies "up the screen". The scene transitions to assault Level 1.
5. After Level 1 completes, the game transitions to TestIsometricScene (existing flow — unchanged).

- [ ] **Step 3: Verify the replay path**

1. Quit and re-launch (without deleting the save file)
2. Expected console output:
   `[BOOT] intro already seen — going to hub`
3. Expected visual: hub loads directly with the planet menu — no cutscene plays.

- [ ] **Step 4: Verify skip works**

1. Delete `mission_state.cfg` again
2. Run the project — cutscene begins
3. Press `Esc` (default `ui_cancel` action) mid-cutscene
4. Expected: cutscene exits immediately and Level 1 loads. The cutscene is marked seen even when skipped (so skip-then-quit still skips the cutscene next launch).

- [ ] **Step 5: Commit**

```bash
git add project.godot
git commit -m "feat: set boot.tscn as main_scene — game launches via cutscene router"
```

---

## Self-Review Checklist

### Spec Coverage

| Requirement | Task that implements it |
|-------------|------------------------|
| Cutscene plays only on first launch | Task 1 (persistence) + Task 6 (Boot router) |
| Ship flies bottom-left → top-right | Task 4 (Beat 1, `ship_start_pos` → `ship_mid_pos`) |
| Camera zooms in to "normal size" | Task 4 (Beat 1, `start_zoom` → `end_zoom`) |
| Ship flies a bit at mid-screen | Task 4 (Beat 2, `pause_duration`) |
| Camera rotates to top-down orientation | Task 4 (Beat 3, `camera.rotation` → `ship.rotation`) |
| Ship flies "down to top" after rotation | Task 4 (Beat 4, drift along forward direction) |
| Auto-launches Assault | Task 4 (`_on_finish`) + Task 5 (`next_scene_path`) |
| Subsequent launches go to Open Space hub | Task 6 (Boot router checks `has_cutscene_been_seen`) |
| Easy to add dialog | Task 2 (DialogPresenter API) + Task 4 (commented hook in Beat 2) |
| Easy to add particles | Task 5 (StarField example as child of Camera2D) — same pattern (CPUParticles2D in scene) extends to any cutscene |
| Easy to rework / add new cutscenes | Task 3 (CutsceneBase) — new cutscene = new scene + script extending CutsceneBase, set `persistence_id` and `next_scene_path` in the .tscn |

### Type Consistency

- `MissionState.has_cutscene_been_seen(id)` / `MissionState.mark_cutscene_seen(id)` — defined in Task 1, called in Tasks 3 (`_on_finish`) and 6 (Boot router) ✓
- `CutsceneBase.persistence_id`, `next_scene_path`, `is_skipped()`, `parallel_tween()`, `tween_property()`, `wait_secs()` — defined in Task 3, used in Tasks 4 and 5 ✓
- `DialogPresenter.present(speaker, text, duration)` — defined in Task 2, referenced (commented) in Task 4 ✓
- `ThrusterEffect.set_state(int)` and `ThrusterEffect.State.{IDLE,THRUST,BOOST}` — already exist in `global/components/thruster_effect.gd`, used by IntroCutscene script in Task 4 and instanced in Task 5 ✓

### Adding A New Cutscene Later

The pattern after this plan lands:

1. Create `cutscenes/<name>/<name>.gd` extending `CutsceneBase` with a `_run_cutscene()` body
2. Create `cutscenes/<name>/<name>.tscn` with `Camera2D`, any actors, optional `DialogPresenter` instance, and `persistence_id` + `next_scene_path` set on the root
3. (If first-time) Add a route in `boot.gd` or trigger the cutscene from any scene via `get_tree().change_scene_to_file()`

No changes to `CutsceneBase`, `MissionState`, or `DialogPresenter` are required for additional cutscenes — they're additive.

### Adding Real Dialog Later

Replace the implementation of `DialogPresenter.present()` with a richer system (typewriter effect, voice playback, character portraits, choice prompts). The signature stays `func present(speaker: String, text: String, duration: float = 2.5) -> void` so every existing cutscene keeps working without modification.

### Adding More Particles Later

Add `CPUParticles2D` (or `GPUParticles2D`) nodes to any cutscene's `.tscn` — same pattern as the `StarField` in Task 5. For procedural FX (impacts, sparks during a beat), use the existing `HitEffect` / `ExplosionEffect` components (`global/components/`) — instantiate in code from `_run_cutscene()` and call `burst()` or `explode()`.
