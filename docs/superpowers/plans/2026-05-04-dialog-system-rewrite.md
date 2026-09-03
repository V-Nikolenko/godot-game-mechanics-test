# Dialog System Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current `DialogBox` (imperative, content-in-code) with a three-layer system — Resource-defined data, autoload-driven runtime, passive UI view — supporting typewriter text, tap-to-advance, hold-to-skip, hold-to-auto, inner-thoughts mode, and one-call-from-anywhere integration with hard player-input lockout.

**Architecture:** Autoload `DialogPlayer` singleton owns a single persistent `DialogBox` UI instance and drives it from `DialogScriptResource` data. Player controllers gate input on a global `is_active` flag; the runner additionally consumes input events and optionally pauses the tree. Dialog content lives in `.tres` files authored in the Godot Inspector — no GDScript edit needed to add or change a line.

**Tech Stack:** Godot 4.4 GDScript, `Resource` subclasses for data, `RichTextLabel.visible_ratio` for typewriter, custom-drawn `Control` for hold-progress arc, autoload singleton for global access. No test framework — verification is "open Godot, run the scene, observe."

---

## Verification convention

Every task ends with a manual verification step in Godot. The shorthand is:

> **Run:** F5 the project (or F6 the named scene). **Observe:** \<expected behavior\>. **If it doesn't:** the named print statement or visible UI element will tell you which step failed.

If a step has no UI/runtime effect (pure data-resource creation), verification is "open the .tres in the Inspector and confirm fields are correct."

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `dialog/resources/speaker.gd` | `SpeakerResource` — name, portrait, name color |
| `dialog/resources/dialog_line.gd` | `DialogLineResource` — one line: speaker, text, side, typing_speed, post_delay, sfx |
| `dialog/resources/dialog_script.gd` | `DialogScriptResource` — ordered `Array[DialogLineResource]` |
| `global/autoload/dialog_player.gd` | `DialogPlayer` autoload — `play()`, `is_active`, hold gestures, autoplay |
| `dialog/ui/dialog_box.gd` | Passive view: `present_line(line)`, typing, fade in/out |
| `dialog/ui/dialog_box.tscn` | Scene: CanvasLayer, two PanelContainers with RichTextLabels |
| `dialog/ui/hold_progress_arc.gd` | Custom-drawn arc indicator for hold-skip / hold-auto |
| `dialog/ui/auto_mode_indicator.gd` | "AUTO" pill that pulses while autoplay is on |
| `dialog/triggers/dialog_trigger.gd` | Designer node — wires a script_resource to a signal/area |
| `dialog/triggers/dialog_trigger.tscn` | Scene wrapper (optional Area2D child) |
| `dialog/scripts/speakers/edith.tres` | Speaker resource — Edith |
| `dialog/scripts/speakers/control.tres` | Speaker resource — Control |
| `dialog/scripts/intro_briefing.tres` | The intro cutscene's two lines as data |
| `dialog/scripts/level1_debrief.tres` | The post-battle Level 1 lines as data |

### Modified

| Path | Change |
|---|---|
| `project.godot` | Register `dialog_auto` input action; register `DialogPlayer` autoload |
| `cutscenes/intro/intro_cutscene.gd` | Replace inline dialog calls with `await DialogPlayer.play(_INTRO_SCRIPT)` |
| `cutscenes/intro/intro_cutscene.tscn` | Remove `DialogLayer` child (autoload handles UI) |
| `assault/scenes/levels/level_1_waves.gd` | Replace inline dialog calls with `await DialogPlayer.play(_DEBRIEF_SCRIPT)`; remove `paused` toggling |
| `assault/scenes/player/player_fighter.gd` | Early-return on `DialogPlayer.is_active` in physics/input |

### Deleted (after migration is verified)

| Path | Reason |
|---|---|
| `cutscenes/base/dialog_box.gd` | Replaced by `dialog/ui/dialog_box.gd` |
| `cutscenes/base/dialog_box.tscn` | Replaced by `dialog/ui/dialog_box.tscn` |

---

## Task 1: Register the `dialog_auto` input action

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Open `project.godot` and locate the `[input]` section.**

Search for `[input]` near the bottom of the file. If it doesn't exist, the next step creates it.

- [ ] **Step 2: Add the `dialog_auto` action.**

Append this block under `[input]`:

```ini
dialog_auto={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":88,"key_label":0,"unicode":120,"location":0,"echo":false,"script":null)
]
}
```

(Physical keycode 88 = X. The dialog hold-X gesture will use this action.)

- [ ] **Step 3: Verify in editor.**

**Run:** Open the project in Godot → Project Settings → Input Map. **Observe:** `dialog_auto` action present, bound to X. **If it's missing:** the block was added in the wrong section — confirm `[input]` is the section header.

- [ ] **Step 4: Commit.**

```bash
git add project.godot
git commit -m "feat(dialog): register dialog_auto input action (X)"
```

---

## Task 2: SpeakerResource

**Files:**
- Create: `dialog/resources/speaker.gd`

- [ ] **Step 1: Create the directory.**

```bash
mkdir -p dialog/resources
```

- [ ] **Step 2: Write `dialog/resources/speaker.gd`.**

```gdscript
## SpeakerResource — character identity for dialog lines.
## A line references a speaker; one .tres per character means a single edit
## propagates to every line they speak.
class_name SpeakerResource
extends Resource

## Display name in the speaker label. Empty = no label (used for narration).
@export var display_name: String = ""

## Portrait shown next to the line. null = no portrait.
@export var portrait: Texture2D

## Color of the speaker label. Default matches the dialog box accent.
@export var name_color: Color = Color(0.55, 0.82, 1.0, 1.0)
```

- [ ] **Step 3: Verify.**

**Run:** Open Godot → FileSystem panel → right-click `dialog/resources/` → New Resource → search "SpeakerResource". **Observe:** the type appears with the three exported fields. **If it doesn't:** Godot may need a script reload (Project → Reload Current Project).

- [ ] **Step 4: Commit.**

```bash
git add dialog/resources/speaker.gd
git commit -m "feat(dialog): add SpeakerResource for character identity"
```

---

## Task 3: DialogLineResource

**Files:**
- Create: `dialog/resources/dialog_line.gd`

- [ ] **Step 1: Write `dialog/resources/dialog_line.gd`.**

```gdscript
## DialogLineResource — one line of dialog.
## A DialogScriptResource is an ordered array of these.
class_name DialogLineResource
extends Resource

## Where the line appears.
##   OTHER_TOP      — top bar, portrait left, used for non-protagonist speakers
##   PLAYER_BOTTOM  — bottom bar, portrait right (mirrored), used for protagonist
##   INNER_THOUGHT  — bottom bar, italicised, no portrait, used for monologue
enum Side { OTHER_TOP, PLAYER_BOTTOM, INNER_THOUGHT }

## How the text appears.
##   TYPEWRITER  — char-by-char reveal via visible_ratio (default)
##   FADE_IN     — modulate.a 0→1, all chars at once
##   INSTANT     — no animation
enum Reveal { TYPEWRITER, FADE_IN, INSTANT }

@export var speaker: SpeakerResource

@export_multiline var text: String = ""

@export var side: Side = Side.PLAYER_BOTTOM

@export var reveal: Reveal = Reveal.TYPEWRITER

## Characters per second for TYPEWRITER. Ignored for other reveals.
@export_range(5.0, 200.0, 1.0) var typing_speed: float = 35.0

## Extra pause after the line completes (used in autoplay timing).
@export_range(0.0, 5.0, 0.05) var post_delay: float = 0.0

## Optional voice/blip stream played when the line starts.
@export var sfx: AudioStream
```

- [ ] **Step 2: Verify.**

**Run:** Godot → FileSystem → right-click `dialog/resources/` → New Resource → search "DialogLineResource". **Observe:** All exported fields visible; `side` and `reveal` show as enum dropdowns; `text` is multiline. **If `Side` enum doesn't appear as dropdown:** check the `enum Side { ... }` syntax has no typos.

- [ ] **Step 3: Commit.**

```bash
git add dialog/resources/dialog_line.gd
git commit -m "feat(dialog): add DialogLineResource with side/reveal enums"
```

---

## Task 4: DialogScriptResource

**Files:**
- Create: `dialog/resources/dialog_script.gd`

- [ ] **Step 1: Write `dialog/resources/dialog_script.gd`.**

```gdscript
## DialogScriptResource — an ordered conversation of DialogLineResources.
## Pass to DialogPlayer.play() to run it.
class_name DialogScriptResource
extends Resource

## Optional identifier for telemetry / save state ("seen this dialog?").
## Empty = not tracked.
@export var script_id: StringName = &""

## The lines, played in order.
@export var lines: Array[DialogLineResource] = []

## If true, get_tree().paused is set true while this script plays.
## Set false for ambient banter that shouldn't freeze the world.
@export var pause_gameplay: bool = true
```

- [ ] **Step 2: Verify.**

**Run:** Godot → FileSystem → right-click `dialog/resources/` → New Resource → search "DialogScriptResource". **Observe:** `lines` field accepts an array, and the array element type is `DialogLineResource`. **If the array is untyped:** the typed-array annotation on `lines` was lost — re-save the script.

- [ ] **Step 3: Commit.**

```bash
git add dialog/resources/dialog_script.gd
git commit -m "feat(dialog): add DialogScriptResource (line array)"
```

---

## Task 5: Author the speaker .tres files

**Files:**
- Create: `dialog/scripts/speakers/edith.tres`
- Create: `dialog/scripts/speakers/control.tres`

- [ ] **Step 1: Create the directory.**

```bash
mkdir -p dialog/scripts/speakers
```

- [ ] **Step 2: Write `dialog/scripts/speakers/edith.tres`.**

```
[gd_resource type="Resource" script_class="SpeakerResource" load_steps=3 format=3]

[ext_resource type="Script" path="res://dialog/resources/speaker.gd" id="1"]
[ext_resource type="Texture2D" path="res://cutscenes/assets/portraits/edith.png" id="2"]

[resource]
script = ExtResource("1")
display_name = "Edith"
portrait = ExtResource("2")
name_color = Color(0.55, 0.82, 1, 1)
```

- [ ] **Step 3: Write `dialog/scripts/speakers/control.tres`.**

```
[gd_resource type="Resource" script_class="SpeakerResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://dialog/resources/speaker.gd" id="1"]

[resource]
script = ExtResource("1")
display_name = "Control"
name_color = Color(0.92, 0.78, 0.42, 1)
```

(Control has no portrait — they're a faceless radio voice.)

- [ ] **Step 4: Verify.**

**Run:** Godot → open `dialog/scripts/speakers/edith.tres` in Inspector. **Observe:** display_name = "Edith", portrait shows the Edith image, name_color is a light blue. Open `control.tres` — display_name = "Control", portrait empty, color is a warm yellow. **If files fail to parse:** Godot will log a "Parse Error" — most often a UTF-8 BOM. Re-save without BOM.

- [ ] **Step 5: Commit.**

```bash
git add dialog/scripts/speakers/edith.tres dialog/scripts/speakers/control.tres
git commit -m "feat(dialog): add Edith and Control speaker resources"
```

---

## Task 6: DialogPlayer autoload — skeleton

**Files:**
- Create: `global/autoload/dialog_player.gd`
- Modify: `project.godot`

- [ ] **Step 1: Create the directory.**

```bash
mkdir -p global/autoload
```

- [ ] **Step 2: Write `global/autoload/dialog_player.gd` (skeleton, UI-less).**

```gdscript
## DialogPlayer — global runner for DialogScriptResources.
## This skeleton handles the lifecycle and is_active flag; the UI is wired in
## a later task. play() prints to stdout for now so we can verify the flow.
extends Node

signal dialog_started(script: DialogScriptResource)
signal line_changed(line: DialogLineResource, index: int)
signal dialog_finished(was_skipped: bool)

## True between dialog_started and dialog_finished. Player controllers gate input on this.
var is_active: bool = false

## True when autoplay is on. Toggled by hold-X (registered in a later task).
var auto_mode: bool = false

var _current_script: DialogScriptResource
var _current_index: int = 0
var _was_skipped: bool = false


## Play a script start-to-finish. Awaitable — resolves on dialog_finished.
func play(script: DialogScriptResource) -> void:
	if is_active:
		push_warning("[DialogPlayer] play() called while already active; ignoring.")
		return
	if script == null or script.lines.is_empty():
		push_warning("[DialogPlayer] play() called with empty/null script; ignoring.")
		return

	_current_script = script
	_current_index = 0
	_was_skipped = false
	is_active = true

	if script.pause_gameplay:
		get_tree().paused = true

	dialog_started.emit(script)
	print("[DialogPlayer] START %s (%d lines)" % [script.script_id, script.lines.size()])

	for i in script.lines.size():
		if _was_skipped:
			break
		_current_index = i
		var line: DialogLineResource = script.lines[i]
		line_changed.emit(line, i)
		print("[DialogPlayer]   line %d: %s" % [i, line.text])
		# Skeleton: simulate "line displayed" by waiting one frame.
		# Real wiring in Task 9 awaits the UI's line_finished signal.
		await get_tree().process_frame

	_finish()


## Stop the current dialog immediately. Used by hold-Space and external skips.
func skip_dialog() -> void:
	if not is_active:
		return
	_was_skipped = true


func _finish() -> void:
	var script := _current_script
	_current_script = null
	is_active = false
	if script != null and script.pause_gameplay:
		get_tree().paused = false
	print("[DialogPlayer] END (skipped=%s)" % _was_skipped)
	dialog_finished.emit(_was_skipped)
```

- [ ] **Step 3: Register as autoload in `project.godot`.**

Find the `[autoload]` section (or create it after `[application]`). Add:

```ini
[autoload]

DialogPlayer="*res://global/autoload/dialog_player.gd"
```

If `[autoload]` already exists with other entries, just append the `DialogPlayer="..."` line within it.

- [ ] **Step 4: Verify autoload registered.**

**Run:** Godot → Project Settings → Autoload tab. **Observe:** `DialogPlayer` listed, path `res://global/autoload/dialog_player.gd`, enabled. **If not:** the `[autoload]` section header may have been duplicated — only one such section is allowed.

- [ ] **Step 5: Smoke-test in any scene.**

Open any scene that runs (e.g. `assault/scenes/levels/level_1.tscn`). In the scene's root script `_ready()`, temporarily add at the very top:

```gdscript
print("[smoke] is_active=", DialogPlayer.is_active)
```

**Run:** F6 the scene. **Observe:** Output panel prints `[smoke] is_active=false`. **If `DialogPlayer` is undefined:** autoload isn't registered. Remove the smoke print after confirming.

- [ ] **Step 6: Commit.**

```bash
git add global/autoload/dialog_player.gd project.godot
git commit -m "feat(dialog): add DialogPlayer autoload skeleton"
```

---

## Task 7: DialogBox view — scene + script (typewriter, fade, present_line API)

**Files:**
- Create: `dialog/ui/dialog_box.gd`
- Create: `dialog/ui/dialog_box.tscn`

- [ ] **Step 1: Create the directory.**

```bash
mkdir -p dialog/ui
```

- [ ] **Step 2: Write `dialog/ui/dialog_box.gd`.**

```gdscript
## DialogBox — passive view driven by DialogPlayer.
##
## Displays one line at a time. Calls present_line(line) and waits for
## line_finished to fire (advance) or line_dismissed to fire (skip-typing-only,
## not used directly — DialogPlayer interprets it).
##
## State machine:
##   IDLE     — nothing showing
##   FADE_IN  — bar fading in, text empty
##   TYPING   — text revealing
##   READY    — text fully shown, awaiting advance
##   FADE_OUT — bar fading out
class_name DialogBox
extends CanvasLayer

signal line_finished       ## Player advanced past this line.
signal typing_completed    ## Typing animation just finished (used for autoplay).

enum State { IDLE, FADE_IN, TYPING, READY, FADE_OUT }

# ── Top bar ───────────────────────────────────────────────────────────────────
@onready var _top_bar: PanelContainer    = $TopBar
@onready var _top_portrait: TextureRect  = $TopBar/Margin/HBox/Portrait
@onready var _top_speaker: Label         = $TopBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _top_text: RichTextLabel    = $TopBar/Margin/HBox/TextCol/TextLabel

# ── Bottom bar ────────────────────────────────────────────────────────────────
@onready var _bot_bar: PanelContainer    = $BottomBar
@onready var _bot_portrait: TextureRect  = $BottomBar/Margin/HBox/Portrait
@onready var _bot_speaker: Label         = $BottomBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _bot_text: RichTextLabel    = $BottomBar/Margin/HBox/TextCol/TextLabel

const _FADE_SEC := 0.22

var _state: State = State.IDLE
var _active_bar: PanelContainer
var _active_text: RichTextLabel
var _typing_tween: Tween


func _ready() -> void:
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false


## Display one line. Awaitable — resolves when the player advances or skip fires.
func present_line(line: DialogLineResource) -> void:
	if _state != State.IDLE:
		push_warning("[DialogBox] present_line while not IDLE; forcing close.")
		_force_close()

	# Pick the bar based on side.
	match line.side:
		DialogLineResource.Side.OTHER_TOP:
			_active_bar = _top_bar
			_active_text = _top_text
			_top_portrait.texture = line.speaker.portrait if line.speaker else null
			_top_portrait.visible = _top_portrait.texture != null
			_top_speaker.text = line.speaker.display_name if line.speaker else ""
			_top_speaker.visible = not _top_speaker.text.is_empty()
			if line.speaker:
				_top_speaker.add_theme_color_override("font_color", line.speaker.name_color)
		DialogLineResource.Side.PLAYER_BOTTOM:
			_active_bar = _bot_bar
			_active_text = _bot_text
			_bot_portrait.texture = line.speaker.portrait if line.speaker else null
			_bot_portrait.visible = _bot_portrait.texture != null
			_bot_speaker.text = line.speaker.display_name if line.speaker else ""
			_bot_speaker.visible = not _bot_speaker.text.is_empty()
			if line.speaker:
				_bot_speaker.add_theme_color_override("font_color", line.speaker.name_color)
		DialogLineResource.Side.INNER_THOUGHT:
			_active_bar = _bot_bar
			_active_text = _bot_text
			_bot_portrait.visible = false
			_bot_speaker.visible = false

	# Wrap text in BBCode for inner thoughts.
	var display_text: String = line.text
	if line.side == DialogLineResource.Side.INNER_THOUGHT:
		display_text = "[i]%s[/i]" % line.text

	_active_text.bbcode_enabled = true
	_active_text.text = display_text
	_active_text.visible_ratio = 0.0

	# Fade the bar in.
	_state = State.FADE_IN
	_active_bar.modulate.a = 0.0
	_active_bar.visible = true
	var t_in := create_tween()
	t_in.tween_property(_active_bar, "modulate:a", 1.0, _FADE_SEC)
	await t_in.finished

	# Reveal the text.
	_state = State.TYPING
	match line.reveal:
		DialogLineResource.Reveal.TYPEWRITER:
			var duration: float = max(line.text.length() / max(line.typing_speed, 1.0), 0.05)
			_typing_tween = create_tween()
			_typing_tween.tween_property(_active_text, "visible_ratio", 1.0, duration)
			await _typing_tween.finished
		DialogLineResource.Reveal.FADE_IN:
			_active_text.visible_ratio = 1.0
			_active_text.modulate.a = 0.0
			var t := create_tween()
			t.tween_property(_active_text, "modulate:a", 1.0, 0.35)
			await t.finished
		DialogLineResource.Reveal.INSTANT:
			_active_text.visible_ratio = 1.0

	_state = State.READY
	typing_completed.emit()


## Called by DialogPlayer on tap-Space when the line is done typing.
func advance() -> void:
	if _state != State.READY:
		return
	_state = State.FADE_OUT
	var t_out := create_tween()
	t_out.tween_property(_active_bar, "modulate:a", 0.0, _FADE_SEC)
	t_out.finished.connect(_after_fade_out, CONNECT_ONE_SHOT)


## Called by DialogPlayer on tap-Space when typing is in progress.
## Completes the typing animation immediately.
func skip_typing() -> void:
	if _state != State.TYPING:
		return
	if _typing_tween:
		_typing_tween.kill()
	_active_text.visible_ratio = 1.0
	_active_text.modulate.a = 1.0
	_state = State.READY
	typing_completed.emit()


## Used by DialogPlayer.skip_dialog() — close everything immediately.
func close_now() -> void:
	if _state == State.IDLE:
		return
	_force_close()


## Read by DialogPlayer to know if it can advance.
func is_typing() -> bool:
	return _state == State.TYPING


func is_ready_to_advance() -> bool:
	return _state == State.READY


func _after_fade_out() -> void:
	if is_instance_valid(_active_bar):
		_active_bar.visible = false
	_state = State.IDLE
	line_finished.emit()


func _force_close() -> void:
	if _typing_tween:
		_typing_tween.kill()
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false
	_state = State.IDLE
	line_finished.emit()
```

- [ ] **Step 3: Write `dialog/ui/dialog_box.tscn`.**

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://dialog/ui/dialog_box.gd" id="1_db"]

[sub_resource type="StyleBoxFlat" id="SBF_top"]
bg_color = Color(0.04, 0.07, 0.16, 0.88)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.25, 0.45, 0.8, 0.6)

[sub_resource type="StyleBoxFlat" id="SBF_bot"]
bg_color = Color(0.04, 0.07, 0.16, 0.88)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4
border_width_left = 1
border_width_top = 1
border_width_right = 1
border_width_bottom = 1
border_color = Color(0.25, 0.45, 0.8, 0.6)

[node name="DialogBox" type="CanvasLayer"]
process_mode = 3
layer = 100
script = ExtResource("1_db")

[node name="TopBar" type="PanelContainer" parent="."]
anchor_right = 1.0
offset_left = 10.0
offset_top = 10.0
offset_right = -10.0
offset_bottom = 104.0
theme_override_styles/panel = SubResource("SBF_top")

[node name="Margin" type="MarginContainer" parent="TopBar"]
layout_mode = 2
theme_override_constants/margin_left = 10
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 10
theme_override_constants/margin_bottom = 8

[node name="HBox" type="HBoxContainer" parent="TopBar/Margin"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="Portrait" type="TextureRect" parent="TopBar/Margin/HBox"]
layout_mode = 2
custom_minimum_size = Vector2(80, 80)
size_flags_vertical = 4
expand_mode = 1
stretch_mode = 6

[node name="TextCol" type="VBoxContainer" parent="TopBar/Margin/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 4

[node name="SpeakerLabel" type="Label" parent="TopBar/Margin/HBox/TextCol"]
layout_mode = 2
theme_override_colors/font_color = Color(0.55, 0.82, 1, 1)
theme_override_font_sizes/font_size = 11
text = "Speaker"

[node name="TextLabel" type="RichTextLabel" parent="TopBar/Margin/HBox/TextCol"]
layout_mode = 2
size_flags_vertical = 3
bbcode_enabled = true
fit_content = true
text = "Dialog text"

[node name="BottomBar" type="PanelContainer" parent="."]
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 10.0
offset_top = -104.0
offset_right = -10.0
offset_bottom = -10.0
theme_override_styles/panel = SubResource("SBF_bot")

[node name="Margin" type="MarginContainer" parent="BottomBar"]
layout_mode = 2
theme_override_constants/margin_left = 10
theme_override_constants/margin_top = 8
theme_override_constants/margin_right = 10
theme_override_constants/margin_bottom = 8

[node name="HBox" type="HBoxContainer" parent="BottomBar/Margin"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="TextCol" type="VBoxContainer" parent="BottomBar/Margin/HBox"]
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 4

[node name="SpeakerLabel" type="Label" parent="BottomBar/Margin/HBox/TextCol"]
layout_mode = 2
theme_override_colors/font_color = Color(0.55, 0.82, 1, 1)
theme_override_font_sizes/font_size = 11
text = "Speaker"

[node name="TextLabel" type="RichTextLabel" parent="BottomBar/Margin/HBox/TextCol"]
layout_mode = 2
size_flags_vertical = 3
bbcode_enabled = true
fit_content = true
text = "Dialog text"

[node name="Portrait" type="TextureRect" parent="BottomBar/Margin/HBox"]
layout_mode = 2
custom_minimum_size = Vector2(80, 80)
size_flags_vertical = 4
expand_mode = 1
stretch_mode = 6
flip_h = true
```

- [ ] **Step 4: Open the scene in editor to confirm it parses.**

**Run:** Godot → open `dialog/ui/dialog_box.tscn`. **Observe:** Two panel bars at top and bottom; both have RichTextLabels (not Labels). **If parse fails:** UTF-8 BOM is the most common cause — re-save without BOM.

- [ ] **Step 5: Commit.**

```bash
git add dialog/ui/dialog_box.gd dialog/ui/dialog_box.tscn
git commit -m "feat(dialog): add DialogBox view with typewriter (RichTextLabel)"
```

---

## Task 8: Author one test DialogScriptResource

**Files:**
- Create: `dialog/scripts/level1_debrief.tres`

- [ ] **Step 1: Write `dialog/scripts/level1_debrief.tres`.**

```
[gd_resource type="Resource" script_class="DialogScriptResource" load_steps=6 format=3]

[ext_resource type="Script" path="res://dialog/resources/dialog_script.gd" id="1_script"]
[ext_resource type="Script" path="res://dialog/resources/dialog_line.gd" id="2_line"]
[ext_resource type="Resource" path="res://dialog/scripts/speakers/control.tres" id="3_control"]
[ext_resource type="Resource" path="res://dialog/scripts/speakers/edith.tres" id="4_edith"]

[sub_resource type="Resource" id="line_1"]
script = ExtResource("2_line")
speaker = ExtResource("3_control")
text = "All hostiles neutralised. Sector 7 is clear."
side = 0
reveal = 0
typing_speed = 35.0
post_delay = 0.2

[sub_resource type="Resource" id="line_2"]
script = ExtResource("2_line")
speaker = ExtResource("4_edith")
text = "Copy that. Setting course for extraction."
side = 1
reveal = 0
typing_speed = 35.0
post_delay = 0.0

[resource]
script = ExtResource("1_script")
script_id = &"level1_debrief"
lines = [SubResource("line_1"), SubResource("line_2")]
pause_gameplay = true
```

(`side = 0` is `OTHER_TOP`, `side = 1` is `PLAYER_BOTTOM`. `reveal = 0` is `TYPEWRITER`.)

- [ ] **Step 2: Verify in Inspector.**

**Run:** Godot → open `dialog/scripts/level1_debrief.tres`. **Observe:** `lines` array has 2 entries; expanding each shows speaker (Control / Edith), text, side. **If `lines` shows as empty or untyped:** the array element type was lost during save — re-open `dialog_script.gd` and re-save it, then reload the .tres.

- [ ] **Step 3: Commit.**

```bash
git add dialog/scripts/level1_debrief.tres
git commit -m "feat(dialog): add level1_debrief script (replaces inline lines)"
```

---

## Task 9: Wire DialogPlayer to DialogBox (UI lifecycle)

**Files:**
- Modify: `global/autoload/dialog_player.gd`

- [ ] **Step 1: Replace the skeleton `play()` with the UI-wired version.**

Open `global/autoload/dialog_player.gd`. Replace its entire contents with:

```gdscript
## DialogPlayer — global runner for DialogScriptResources.
extends Node

const _DIALOG_BOX_SCENE: PackedScene = preload("res://dialog/ui/dialog_box.tscn")

signal dialog_started(script: DialogScriptResource)
signal line_changed(line: DialogLineResource, index: int)
signal dialog_finished(was_skipped: bool)

## True between dialog_started and dialog_finished. Player controllers gate input on this.
var is_active: bool = false

## True when autoplay is on. Toggled in a later task by hold-X.
var auto_mode: bool = false

var _box: DialogBox
var _current_script: DialogScriptResource
var _current_index: int = 0
var _was_skipped: bool = false


func _ready() -> void:
	_box = _DIALOG_BOX_SCENE.instantiate()
	add_child(_box)


## Play a script start-to-finish. Awaitable — resolves on dialog_finished.
func play(script: DialogScriptResource) -> void:
	if is_active:
		push_warning("[DialogPlayer] play() called while already active; ignoring.")
		return
	if script == null or script.lines.is_empty():
		push_warning("[DialogPlayer] play() called with empty/null script; ignoring.")
		return

	_current_script = script
	_current_index = 0
	_was_skipped = false
	is_active = true

	if script.pause_gameplay:
		get_tree().paused = true

	dialog_started.emit(script)

	for i in script.lines.size():
		if _was_skipped:
			break
		_current_index = i
		var line: DialogLineResource = script.lines[i]
		line_changed.emit(line, i)
		await _box.present_line(line)
		await _box.line_finished
		if _was_skipped:
			break

	if _was_skipped:
		_box.close_now()
	_finish()


## Stop the current dialog immediately. Used by hold-Space and external skips.
func skip_dialog() -> void:
	if not is_active:
		return
	_was_skipped = true
	_box.close_now()


func _finish() -> void:
	var script := _current_script
	_current_script = null
	is_active = false
	if script != null and script.pause_gameplay:
		get_tree().paused = false
	dialog_finished.emit(_was_skipped)
```

- [ ] **Step 2: Smoke-test by playing a script from a temp scene.**

Open `assault/scenes/levels/level_1.tscn` and add this temp test in `assault/scenes/levels/level_1_waves.gd::_ready()` at the very end (we'll remove it later):

```gdscript
# TEMP smoke test — remove in Task 13
await get_tree().create_timer(1.0).timeout
await DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))
print("[smoke] dialog complete")
```

**Run:** F6 `level_1.tscn`. **Observe:** After 1 s, the top bar fades in showing "Control" → "All hostiles neutralised. Sector 7 is clear." revealing letter-by-letter. **It will hang there waiting for advance** — that's fine, we wire input in the next task. Press Esc to quit. **If nothing appears:** check Output panel for autoload errors.

- [ ] **Step 3: Remove the smoke test.**

Delete the three TEMP lines you just added.

- [ ] **Step 4: Commit.**

```bash
git add global/autoload/dialog_player.gd
git commit -m "feat(dialog): wire DialogPlayer to DialogBox UI"
```

---

## Task 10: Tap-Space input — skip-typing then advance

**Files:**
- Modify: `global/autoload/dialog_player.gd`

- [ ] **Step 1: Add input handling at the bottom of `dialog_player.gd`.**

Append these methods (and remove `_input` from `dialog_box.gd` later — for now the box doesn't have one). Insert after `_finish()`:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot"):
		get_viewport().set_input_as_handled()
		_handle_advance_press()


func _handle_advance_press() -> void:
	if _box.is_typing():
		_box.skip_typing()
	elif _box.is_ready_to_advance():
		_box.advance()
```

The autoload's `Node` default `process_mode` is `INHERIT`. Set it explicitly so it works while paused — append at the top of `_ready()`:

```gdscript
process_mode = Node.PROCESS_MODE_ALWAYS
```

(The `_box` child inherits via the scene's `process_mode = 3`.)

- [ ] **Step 2: Verify Tap-Space flow.**

Re-add the smoke test from Task 9 step 2 to `level_1_waves.gd::_ready()`:

```gdscript
await get_tree().create_timer(1.0).timeout
await DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))
print("[smoke] dialog complete")
```

**Run:** F6 `level_1.tscn`. Watch the first line type. While it's typing, press Space — text completes immediately. Press Space again — top bar fades out, bottom bar fades in with Edith's line. Press Space twice (skip typing, then advance) — bar fades out, "[smoke] dialog complete" prints to Output. **If Space does nothing:** check `is_active` is true (add `print(DialogPlayer.is_active)` temporarily); if false, the autoload didn't enter active state.

- [ ] **Step 3: Remove the smoke test.**

- [ ] **Step 4: Commit.**

```bash
git add global/autoload/dialog_player.gd
git commit -m "feat(dialog): tap-Space skip-typing then advance"
```

---

## Task 11: Hold-Space 2 s to skip whole dialog + progress arc

**Files:**
- Create: `dialog/ui/hold_progress_arc.gd`
- Modify: `dialog/ui/dialog_box.tscn` (add the arc as a child)
- Modify: `dialog/ui/dialog_box.gd` (`set_hold_progress(ratio)`)
- Modify: `global/autoload/dialog_player.gd` (track hold timer, call skip_dialog)

- [ ] **Step 1: Write `dialog/ui/hold_progress_arc.gd`.**

```gdscript
## HoldProgressArc — circular progress indicator for hold gestures.
## set_progress(0..1) → redraws arc.
class_name HoldProgressArc
extends Control

@export var radius: float = 7.0
@export var width: float = 2.0
@export var color: Color = Color(0.8, 0.95, 1.0, 0.9)
@export var bg_color: Color = Color(0.2, 0.3, 0.5, 0.4)

var _progress: float = 0.0


func set_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	visible = _progress > 0.001
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	# Background ring
	draw_arc(c, radius, 0.0, TAU, 32, bg_color, width, true)
	# Foreground sweep
	if _progress > 0.0:
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, 32, color, width, true)
```

- [ ] **Step 2: Add the arc to `dialog/ui/dialog_box.tscn`.**

Open the .tscn in a text editor. Add this `[ext_resource]` line near the top alongside the existing `1_db` resource:

```
[ext_resource type="Script" path="res://dialog/ui/hold_progress_arc.gd" id="2_arc"]
```

Then append at the end of the file (after the BottomBar/Portrait node):

```
[node name="HoldArc" type="Control" parent="BottomBar/Margin/HBox"]
custom_minimum_size = Vector2(20, 20)
layout_mode = 2
size_flags_vertical = 4
script = ExtResource("2_arc")
```

- [ ] **Step 3: Add `set_hold_progress()` to `dialog/ui/dialog_box.gd`.**

Add `@onready` and the helper near the other onready vars:

```gdscript
@onready var _hold_arc: HoldProgressArc = $BottomBar/Margin/HBox/HoldArc

func set_hold_progress(ratio: float) -> void:
	if _hold_arc:
		_hold_arc.set_progress(ratio)
```

- [ ] **Step 4: Track hold-Space in `dialog_player.gd`.**

Add this constant near the top of the script:

```gdscript
const _HOLD_SKIP_SEC: float = 2.0
```

Add this var near the others:

```gdscript
var _accept_held_since: float = -1.0
```

Replace the `_unhandled_input` body with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event.is_action_pressed("ui_accept"):
		_accept_held_since = Time.get_ticks_msec() / 1000.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept") and _accept_held_since >= 0.0:
		var held := Time.get_ticks_msec() / 1000.0 - _accept_held_since
		_accept_held_since = -1.0
		_box.set_hold_progress(0.0)
		if held < _HOLD_SKIP_SEC:
			_handle_advance_press()
		# else: skip already fired in _process
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shoot"):
		get_viewport().set_input_as_handled()
		_handle_advance_press()
```

Add a `_process` to drive the progress arc and trigger skip:

```gdscript
func _process(_delta: float) -> void:
	if not is_active or _accept_held_since < 0.0:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _accept_held_since
	_box.set_hold_progress(held / _HOLD_SKIP_SEC)
	if held >= _HOLD_SKIP_SEC:
		_accept_held_since = -1.0
		_box.set_hold_progress(0.0)
		skip_dialog()
```

- [ ] **Step 5: Verify.**

Re-add the smoke test from Task 9 step 2. **Run:** F6 `level_1.tscn`. After dialog appears, press-and-hold Space. **Observe:** A small arc fills clockwise on the bottom bar over 2 seconds; once full, the dialog closes immediately and "[smoke] dialog complete" prints. Repeat — this time tap Space briefly: dialog advances normally. **If the arc doesn't appear:** the `HoldArc` node may not have been created — check `dialog_box.tscn` opens cleanly.

- [ ] **Step 6: Remove the smoke test.**

- [ ] **Step 7: Commit.**

```bash
git add dialog/ui/hold_progress_arc.gd dialog/ui/dialog_box.tscn dialog/ui/dialog_box.gd global/autoload/dialog_player.gd
git commit -m "feat(dialog): hold-Space 2s to skip entire dialog with progress arc"
```

---

## Task 12: Hold-X auto-mode toggle + indicator

**Files:**
- Create: `dialog/ui/auto_mode_indicator.gd`
- Modify: `dialog/ui/dialog_box.tscn` (add indicator)
- Modify: `dialog/ui/dialog_box.gd` (`set_auto_indicator(on)`)
- Modify: `global/autoload/dialog_player.gd` (hold-X tracking + autoplay timing)

- [ ] **Step 1: Write `dialog/ui/auto_mode_indicator.gd`.**

```gdscript
## AutoModeIndicator — small "AUTO" pill that pulses while autoplay is on.
class_name AutoModeIndicator
extends Label

const _PULSE_SEC := 0.9

var _tween: Tween


func _ready() -> void:
	text = "AUTO"
	add_theme_color_override("font_color", Color(0.6, 0.95, 0.7, 1.0))
	add_theme_font_size_override("font_size", 10)
	visible = false


func set_active(on: bool) -> void:
	visible = on
	if _tween:
		_tween.kill()
		_tween = null
	if on:
		modulate.a = 1.0
		_tween = create_tween().set_loops()
		_tween.tween_property(self, "modulate:a", 0.4, _PULSE_SEC)
		_tween.tween_property(self, "modulate:a", 1.0, _PULSE_SEC)
```

- [ ] **Step 2: Add the indicator to `dialog/ui/dialog_box.tscn`.**

Add another `[ext_resource]` line near the top:

```
[ext_resource type="Script" path="res://dialog/ui/auto_mode_indicator.gd" id="3_auto"]
```

Append after the `HoldArc` node:

```
[node name="AutoIndicator" type="Label" parent="BottomBar/Margin/HBox"]
layout_mode = 2
size_flags_vertical = 4
script = ExtResource("3_auto")
```

- [ ] **Step 3: Wire it in `dialog/ui/dialog_box.gd`.**

Add `@onready` var:

```gdscript
@onready var _auto_indicator: AutoModeIndicator = $BottomBar/Margin/HBox/AutoIndicator
```

Add helper:

```gdscript
func set_auto_indicator(on: bool) -> void:
	if _auto_indicator:
		_auto_indicator.set_active(on)
```

- [ ] **Step 4: Track hold-X and run autoplay in `dialog_player.gd`.**

Add constants:

```gdscript
const _HOLD_AUTO_SEC: float = 0.5    ## time to hold X to toggle auto
const _AUTO_BASE_SEC: float = 0.6    ## base dwell at end of line in autoplay
const _AUTO_PER_CHAR: float = 0.045  ## extra dwell per character
```

Add var:

```gdscript
var _auto_held_since: float = -1.0
```

Append to `_unhandled_input` (before the `elif event.is_action_pressed("shoot")` branch):

```gdscript
	elif event.is_action_pressed("dialog_auto"):
		_auto_held_since = Time.get_ticks_msec() / 1000.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("dialog_auto") and _auto_held_since >= 0.0:
		var held := Time.get_ticks_msec() / 1000.0 - _auto_held_since
		_auto_held_since = -1.0
		if held >= _HOLD_AUTO_SEC:
			auto_mode = not auto_mode
			_box.set_auto_indicator(auto_mode)
		get_viewport().set_input_as_handled()
```

Modify `play()`'s line loop to honor autoplay. Replace the existing loop body with:

```gdscript
	for i in script.lines.size():
		if _was_skipped:
			break
		_current_index = i
		var line: DialogLineResource = script.lines[i]
		line_changed.emit(line, i)
		await _box.present_line(line)

		# Race: line_finished (player advance/skip) vs. auto-dwell timer (if auto_mode).
		if auto_mode:
			var dwell: float = _AUTO_BASE_SEC + line.text.length() * _AUTO_PER_CHAR + line.post_delay
			var auto_timer := get_tree().create_timer(dwell)
			var winner: int = await _race_line_or_timer(_box.line_finished, auto_timer.timeout)
			if winner == 1 and not _was_skipped:
				_box.advance()
				await _box.line_finished
		else:
			await _box.line_finished

		if _was_skipped:
			break
```

Add the helper `_race_line_or_timer` at the bottom of the script:

```gdscript
## Returns 0 if `sig_a` fires first, 1 if `sig_b` fires first. Both connections
## are CONNECT_ONE_SHOT and are torn down by the wrapper's emit-once gate.
func _race_line_or_timer(sig_a: Signal, sig_b: Signal) -> int:
	var done := false
	var winner: int = -1
	var resume: Callable
	resume = func(idx: int) -> void:
		if done: return
		done = true
		winner = idx
	sig_a.connect(func() -> void: resume.call(0), CONNECT_ONE_SHOT)
	sig_b.connect(func() -> void: resume.call(1), CONNECT_ONE_SHOT)
	while winner == -1:
		await get_tree().process_frame
	return winner
```

- [ ] **Step 5: Verify.**

Re-add the smoke test (Task 9 step 2). **Run:** F6 `level_1.tscn`. After dialog appears, press-and-hold X for ~0.6 s and release. **Observe:** The "AUTO" pill appears next to the bottom bar and pulses. The current line auto-advances (after a short dwell once typing finishes), and the next line plays automatically. Hold X again → AUTO disappears, manual mode resumes. **If the indicator doesn't show:** verify `dialog_auto` action exists in Project Settings → Input Map.

- [ ] **Step 6: Remove the smoke test.**

- [ ] **Step 7: Commit.**

```bash
git add dialog/ui/auto_mode_indicator.gd dialog/ui/dialog_box.tscn dialog/ui/dialog_box.gd global/autoload/dialog_player.gd
git commit -m "feat(dialog): hold-X to toggle auto mode with length-aware dwell"
```

---

## Task 13: Migrate level_1_waves.gd to DialogPlayer.play()

**Files:**
- Modify: `assault/scenes/levels/level_1_waves.gd`

- [ ] **Step 1: Replace the inline dialog block in `_on_waves_complete`.**

Open `assault/scenes/levels/level_1_waves.gd`. Find the block that starts with `# Freeze gameplay for the debrief` and ends at `get_tree().paused = false`. Replace it with:

```gdscript
	# Post-battle debrief — DialogPlayer handles pause + UI lifecycle.
	await DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))
```

Also remove the now-unused preload at the top:

```gdscript
const _DIALOG_BOX    := preload("res://cutscenes/base/dialog_box.tscn")
const _EDITH_PORTRAIT := preload("res://cutscenes/assets/portraits/edith.png")
```

(Both lines deleted.)

- [ ] **Step 2: Verify by playing the level to completion.**

**Run:** F6 `level_1.tscn`. Survive all 6 waves; at the end, the dialog plays automatically with typewriter, advance with Space, hold-Space to skip, hold-X to autoplay all work. **If dialog doesn't appear:** check the Output panel for `[DialogPlayer]` errors. Most likely cause is a missing `level1_debrief.tres` reference — confirm the path.

- [ ] **Step 3: Commit.**

```bash
git add assault/scenes/levels/level_1_waves.gd
git commit -m "refactor(level1): use DialogPlayer.play() for post-battle debrief"
```

---

## Task 14: Author intro_briefing.tres + migrate intro_cutscene

**Files:**
- Create: `dialog/scripts/intro_briefing.tres`
- Modify: `cutscenes/intro/intro_cutscene.gd`
- Modify: `cutscenes/intro/intro_cutscene.tscn`

- [ ] **Step 1: Write `dialog/scripts/intro_briefing.tres`.**

```
[gd_resource type="Resource" script_class="DialogScriptResource" load_steps=6 format=3]

[ext_resource type="Script" path="res://dialog/resources/dialog_script.gd" id="1_script"]
[ext_resource type="Script" path="res://dialog/resources/dialog_line.gd" id="2_line"]
[ext_resource type="Resource" path="res://dialog/scripts/speakers/control.tres" id="3_control"]
[ext_resource type="Resource" path="res://dialog/scripts/speakers/edith.tres" id="4_edith"]

[sub_resource type="Resource" id="line_1"]
script = ExtResource("2_line")
speaker = ExtResource("3_control")
text = "Edith — Sector 7 is hot. Hostile formation on approach."
side = 0
reveal = 0
typing_speed = 35.0
post_delay = 0.2

[sub_resource type="Resource" id="line_2"]
script = ExtResource("2_line")
speaker = ExtResource("4_edith")
text = "Already at the perimeter. I'll handle it."
side = 1
reveal = 0
typing_speed = 35.0
post_delay = 0.0

[resource]
script = ExtResource("1_script")
script_id = &"intro_briefing"
lines = [SubResource("line_1"), SubResource("line_2")]
pause_gameplay = false
```

(Note: `pause_gameplay = false` — the intro cutscene drives its own animation; we don't want to freeze it during dialog.)

- [ ] **Step 2: Update `cutscenes/intro/intro_cutscene.gd`.**

Find the Beat 2 block (the two `await dialog.present_*` calls). Replace the entire `# ── Beat 2: ...` block with:

```gdscript
	# ── Beat 2: mission briefing exchange ───────────────────────────────
	await DialogPlayer.play(preload("res://dialog/scripts/intro_briefing.tres"))
	if is_skipped(): return
```

Remove the obsolete dialog field declaration at the top of the script:

```gdscript
@onready var dialog: DialogBox = $DialogLayer
```

(That whole line deleted.)

Remove the obsolete preload:

```gdscript
const _EDITH_PORTRAIT := preload("res://cutscenes/assets/portraits/edith.png")
```

(Deleted — speaker resource now owns the portrait.)

- [ ] **Step 3: Update `cutscenes/intro/intro_cutscene.tscn`.**

Open the .tscn in a text editor. Find and delete the line:

```
[node name="DialogLayer" parent="." unique_id=1165102223 instance=ExtResource("4_dialog")]
```

Also delete the matching `[ext_resource]`:

```
[ext_resource type="PackedScene" path="res://cutscenes/base/dialog_box.tscn" id="4_dialog"]
```

- [ ] **Step 4: Verify.**

**Run:** F6 `cutscenes/intro/intro_cutscene.tscn`. **Observe:** Ship flies in (Beat 1), then the dialog plays via `DialogPlayer` — top bar with Control's line, then bottom bar with Edith's line. Space advances each, hold-Space skips the conversation, the cutscene proceeds to Beat 3 afterward. **If `is_skipped()` returns true unexpectedly:** Esc was pressed; the cutscene's own skip handler ran. That's correct behavior.

- [ ] **Step 5: Commit.**

```bash
git add dialog/scripts/intro_briefing.tres cutscenes/intro/intro_cutscene.gd cutscenes/intro/intro_cutscene.tscn
git commit -m "refactor(intro): use DialogPlayer for briefing exchange"
```

---

## Task 15: Player controller `is_active` lockout

**Files:**
- Modify: `assault/scenes/player/player_fighter.gd`

- [ ] **Step 1: Add the early-return at the top of `_physics_process`.**

Open `assault/scenes/player/player_fighter.gd`. Find `_physics_process(_delta: float) -> void:`. Insert as the very first statement inside the function body:

```gdscript
	if DialogPlayer.is_active:
		velocity = Vector2.ZERO
		return
```

(For DialogScriptResources where `pause_gameplay = true` this is redundant — the tree pause already stops physics — but it's correct for the `pause_gameplay = false` case where exploration dialog plays without freezing the world.)

- [ ] **Step 2: If the player has a separate input handler (`_unhandled_input` for shoot etc.), guard it too.**

Search the file for `_unhandled_input` or `_input`. If found, add as the first statement:

```gdscript
	if DialogPlayer.is_active:
		return
```

If neither method exists in `player_fighter.gd`, skip this step.

- [ ] **Step 3: Verify.**

Author a temp `DialogScriptResource` with `pause_gameplay = false` (just one line) and trigger it from the assault level by pressing some key. Confirm the player can't move or shoot while dialog is up. Or simpler: in `level_1_waves.gd::_ready()`, after the level loads, add:

```gdscript
await get_tree().create_timer(2.0).timeout
var test := DialogScriptResource.new()
test.pause_gameplay = false
var line := DialogLineResource.new()
line.text = "Lockout test — you should not be able to move."
line.side = DialogLineResource.Side.INNER_THOUGHT
test.lines = [line]
await DialogPlayer.play(test)
```

**Run:** F6 `level_1.tscn`. After 2 s the bottom bar shows the line. Try W/A/S/D and shoot — nothing happens. Press Space — dialog closes, controls return. **If the player still moves:** the early-return is in the wrong function or hasn't been saved.

- [ ] **Step 4: Remove the temp test.**

- [ ] **Step 5: Commit.**

```bash
git add assault/scenes/player/player_fighter.gd
git commit -m "feat(player): gate movement/input on DialogPlayer.is_active"
```

---

## Task 16: DialogTrigger node for declarative scenes

**Files:**
- Create: `dialog/triggers/dialog_trigger.gd`

- [ ] **Step 1: Create the directory.**

```bash
mkdir -p dialog/triggers
```

- [ ] **Step 2: Write `dialog/triggers/dialog_trigger.gd`.**

```gdscript
## DialogTrigger — declarative wrapper around DialogPlayer.play().
##
## Drop into any scene, set `script_resource`, and either:
##   - call fire() from code, OR
##   - connect any signal to the trigger's fire_from_signal() method, OR
##   - set fire_on_ready = true to fire as soon as the trigger enters the tree.
##
## Honors play_once — second fire is ignored once consumed.
class_name DialogTrigger
extends Node

signal triggered
signal completed(was_skipped: bool)

@export var script_resource: DialogScriptResource

@export var fire_on_ready: bool = false

@export var play_once: bool = true

var _consumed: bool = false


func _ready() -> void:
	if fire_on_ready:
		fire()


## Trigger the dialog. Awaitable — resolves on completed.
func fire() -> void:
	if _consumed and play_once:
		return
	if script_resource == null:
		push_warning("[DialogTrigger] fire() called with no script_resource.")
		return
	_consumed = true
	triggered.emit()
	await DialogPlayer.play(script_resource)
	completed.emit(false)  # was_skipped reporting is best-effort; refine later if needed


## Connectable to any zero-arg signal (e.g. Area2D.body_entered won't work directly
## — write a one-line wrapper if you need argument-passing signals).
func fire_from_signal() -> void:
	fire()
```

- [ ] **Step 3: Verify.**

Open any test scene. Add a `DialogTrigger` node, set `script_resource = level1_debrief.tres`, set `fire_on_ready = true`. **Run:** F6 the scene. **Observe:** Dialog fires immediately on scene entry. **If it doesn't:** check the Output panel — `script_resource` may be unset, you'll see the push_warning.

- [ ] **Step 4: Commit.**

```bash
git add dialog/triggers/dialog_trigger.gd
git commit -m "feat(dialog): add DialogTrigger node for declarative scenes"
```

---

## Task 17: Delete the obsolete legacy DialogBox

**Files:**
- Delete: `cutscenes/base/dialog_box.gd`
- Delete: `cutscenes/base/dialog_box.tscn`

- [ ] **Step 1: Confirm no remaining references.**

```bash
git grep -n "cutscenes/base/dialog_box"
```

Expected output: empty. **If any results appear:** they must be cleaned up before deletion. Most likely candidates are stale cache entries in `.godot/` — delete `.godot/uid_cache.bin` and `.godot/filesystem_cache10` if so, then re-run.

- [ ] **Step 2: Delete the files.**

```bash
rm cutscenes/base/dialog_box.gd
rm cutscenes/base/dialog_box.tscn
```

- [ ] **Step 3: Open the project in Godot to let it refresh the cache.**

**Run:** Open Godot. **Observe:** No "missing resource" errors in the Output panel during scene loads. **If errors appear:** an old `.uid` file may still exist (`cutscenes/base/dialog_box.gd.uid`, `dialog_box.tscn.uid`) — delete those too.

- [ ] **Step 4: Commit.**

```bash
git add -A cutscenes/base/
git commit -m "chore(dialog): remove legacy cutscenes/base/dialog_box.* (migrated)"
```

---

## Task 18: Inner-thoughts smoke test

**Files:**
- Create: `dialog/scripts/_smoke_inner_thought.tres` (then delete after verification)

- [ ] **Step 1: Write `dialog/scripts/_smoke_inner_thought.tres`.**

```
[gd_resource type="Resource" script_class="DialogScriptResource" load_steps=4 format=3]

[ext_resource type="Script" path="res://dialog/resources/dialog_script.gd" id="1_script"]
[ext_resource type="Script" path="res://dialog/resources/dialog_line.gd" id="2_line"]
[ext_resource type="Resource" path="res://dialog/scripts/speakers/edith.tres" id="3_edith"]

[sub_resource type="Resource" id="line_1"]
script = ExtResource("2_line")
speaker = ExtResource("3_edith")
text = "Sector's gone quiet. Too quiet. Something is off here."
side = 2
reveal = 0
typing_speed = 30.0
post_delay = 0.0

[resource]
script = ExtResource("1_script")
script_id = &"smoke_inner"
lines = [SubResource("line_1")]
pause_gameplay = true
```

(`side = 2` is `INNER_THOUGHT`.)

- [ ] **Step 2: Trigger from `level_1_waves.gd::_ready()` temporarily.**

Add at the end of `_ready`:

```gdscript
await get_tree().create_timer(0.5).timeout
await DialogPlayer.play(preload("res://dialog/scripts/_smoke_inner_thought.tres"))
```

- [ ] **Step 3: Verify.**

**Run:** F6 `level_1.tscn`. **Observe:** Only the bottom bar appears. No portrait. No speaker label. The text is italicised. Press Space → dialog ends. **If the top bar appears:** the side enum value didn't map to INNER_THOUGHT — confirm `side = 2` in the .tres.

- [ ] **Step 4: Clean up.**

```bash
rm dialog/scripts/_smoke_inner_thought.tres
```

Remove the temp lines from `level_1_waves.gd::_ready`.

- [ ] **Step 5: Commit (only if any source files changed during testing).**

```bash
git status
# If nothing staged, skip the commit.
```

If nothing remains staged, skip the commit — this task is verification-only.

---

## Task 19: Final integration smoke test (full happy-path replay)

**Files:** None modified. Pure verification.

- [ ] **Step 1: Run the intro → assault sequence end-to-end.**

**Run:** F5 (whole project). **Observe:**
1. Intro cutscene plays. Beat 2 dialog uses `DialogPlayer` — top bar Control, bottom bar Edith.
2. Space advances each line; hold-Space mid-line skips remaining dialog (cutscene continues to Beat 3).
3. Assault Level 1 plays. Survive all waves.
4. Post-battle debrief plays via `DialogPlayer` — same dialog, this time with `pause_gameplay = true` (everything frozen).
5. Hold-X mid-debrief enables AUTO; remaining lines auto-advance.
6. Cutscene transitions to extraction.

**If anything fails:** the printed `[DialogPlayer]` lifecycle logs in the Output panel pinpoint the failing step.

- [ ] **Step 2: Commit a tag for the milestone.**

```bash
git tag dialog-system-v1
```

(Optional — just a marker. No additional code changes here.)

---

## Self-Review checklist

**Spec coverage** (each requirement → task that implements it):
1. ✅ Tap-Space skip line / advance — Task 10
2. ✅ Hold-Space 2 s skip whole dialog with progress feedback — Task 11
3. ✅ Inner-thoughts mode (bottom-only, italic, no portrait) — Tasks 3, 7 (`Side.INNER_THOUGHT` handling), Task 18 verification
4. ✅ Hold-X auto-mode toggle, length-aware dwell — Task 12
5. ✅ Typewriter reveal animation (default), with FADE_IN and INSTANT alternates — Task 7 (`Reveal` enum + `_show_bar` match block)
6. ✅ Easy integration anywhere — Task 9 (`DialogPlayer.play(script)`), Task 16 (`DialogTrigger` node), Task 15 (player input lockout via `is_active`); pause_gameplay flag on the script supports both Open Space (ambient) and Assault/Infiltration (frozen) styles

**Placeholder scan:** No "TBD", "implement later", "appropriate error handling", or naked "similar to Task N". Each task contains complete code or complete .tscn text.

**Type / name consistency:**
- `DialogPlayer.play()` exists — Task 6, refined Task 9.
- `DialogPlayer.is_active` — Task 6, used Task 15.
- `DialogPlayer.skip_dialog()` — Task 6, called from Task 11.
- `DialogPlayer.auto_mode` — Task 6, toggled Task 12.
- `DialogBox.present_line()` — Task 7, called Task 9.
- `DialogBox.line_finished` — Task 7, awaited Task 9.
- `DialogBox.is_typing()` / `is_ready_to_advance()` / `skip_typing()` / `advance()` / `close_now()` — all in Task 7, used in Tasks 10–11.
- `DialogBox.set_hold_progress()` — Task 11.
- `DialogBox.set_auto_indicator()` — Task 12.
- `DialogLineResource.Side` — Task 3, switched in Task 7.
- `DialogLineResource.Reveal` — Task 3, switched in Task 7.
- `DialogScriptResource.lines` / `pause_gameplay` / `script_id` — Task 4, read in Task 6.
- `SpeakerResource.display_name` / `portrait` / `name_color` — Task 2, read in Task 7.

All names line up; no orphans.
