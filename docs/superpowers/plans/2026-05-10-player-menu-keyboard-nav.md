# Player Menu Keyboard Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mouse-click weapon selection in the Player Menu with WASD cursor navigation and F/Space confirmation, removing Button nodes entirely.

**Architecture:** A cursor (col, row) pair tracks the highlighted option; `_unhandled_input` handles all menu actions while paused; WeaponOption gains a `set_cursor(bool)` method that modulates its colour. Mouse interaction (Button / `option_pressed` signal) is deleted.

**Tech Stack:** Godot 4.6 · GDScript · existing `process_mode = ALWAYS` menu · project.godot input actions

---

## File Map

| File | Change |
|------|--------|
| `project.godot` | Add `menu_up`, `menu_down`, `menu_left`, `menu_right`, `menu_confirm` input actions |
| `dialog/ui/playermenu/weapon_option.gd` | Remove `option_pressed` signal, `_button` onready, `_ready()`; add `set_cursor(bool)` |
| `dialog/ui/playermenu/weapon_option.tscn` | Remove `ClickArea` Button node |
| `dialog/ui/playermenu/player_menu.gd` | Add cursor state vars + navigation + confirm; remove `option_pressed.connect` calls |

---

### Task 1: Add menu input actions to project.godot

**Files:**
- Modify: `project.godot` (input section)

- [ ] **Step 1: Open project.godot and locate the `[input]` section**

The section begins at the line `[input]` and ends before `[layer_names]`. We will append five new actions after the existing `interact` action block and before the `dialog_auto` block. Insert the following text between `interact={...}` and `dialog_auto={...}`:

```
menu_up={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
]
}
menu_down={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
]
}
menu_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
]
}
menu_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
]
}
menu_confirm={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":70,"key_label":0,"unicode":102,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Verify the actions exist**

Open the Godot editor → Project → Project Settings → Input Map. Confirm `menu_up`, `menu_down`, `menu_left`, `menu_right`, `menu_confirm` appear in the list with the correct keys (W, S, A, D, F+Space).

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "feat: add menu navigation input actions (WASD + F/Space confirm)"
```

---

### Task 2: Remove mouse interaction from WeaponOption; add cursor visual

**Files:**
- Modify: `dialog/ui/playermenu/weapon_option.gd`
- Modify: `dialog/ui/playermenu/weapon_option.tscn`

**Context:** `weapon_option.gd` currently has a `signal option_pressed`, an `@onready var _button: Button = $ClickArea`, and a `_ready()` that wires the button. The `.tscn` has a `ClickArea` Button child node. Both must be cleaned up and a `set_cursor` method added.

- [ ] **Step 1: Rewrite weapon_option.gd**

Replace the entire file with:

```gdscript
# dialog/ui/playermenu/weapon_option.gd
class_name WeaponOption
extends Control

const _TEX_UNSELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_select_option.png")
const _TEX_SELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_selected_option.png")

## Colour applied to this control when the keyboard cursor is on it.
const _CURSOR_MODULATE := Color(1.4, 1.4, 1.0)
const _NORMAL_MODULATE := Color.WHITE

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $WeaponName

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Swap the background sprite between unselected and selected state.
func set_selected(value: bool) -> void:
	var tex := _TEX_SELECTED if value else _TEX_UNSELECTED
	if _bg_sprite.texture == tex:
		return
	_bg_sprite.texture = tex

## Highlight this row when the keyboard cursor is positioned here.
func set_cursor(value: bool) -> void:
	modulate = _CURSOR_MODULATE if value else _NORMAL_MODULATE
```

- [ ] **Step 2: Remove the ClickArea node from weapon_option.tscn**

Replace the entire file with (the ClickArea node is simply omitted):

```
[gd_scene format=3 uid="uid://b8e2nn88icol6"]

[ext_resource type="Script" path="res://dialog/ui/playermenu/weapon_option.gd" id="1_wopt"]
[ext_resource type="Texture2D" uid="uid://cx5sucmpr1gju" path="res://assault/assets/sprites/ui/weapon_list_item_select_option.png" id="2_62mbo"]

[node name="WeaponOption" type="Control" unique_id=318341931]
custom_minimum_size = Vector2(210, 30)
size = Vector2(210, 30)
script = ExtResource("1_wopt")

[node name="WeaponIcon" type="Sprite2D" parent="." unique_id=2044088980]
position = Vector2(15, 15)
scale = Vector2(0.32666668, 0.32666665)

[node name="SelectionBG" type="Sprite2D" parent="." unique_id=1804324106]
position = Vector2(70, 15)
scale = Vector2(0.3266667, 0.32666668)
texture = ExtResource("2_62mbo")

[node name="WeaponName" type="Label" parent="." unique_id=234567890]
offset_left = 100.0
offset_top = 5.0
offset_right = 210.0
offset_bottom = 25.0
text = "Weapon"
```

- [ ] **Step 3: Verify no compile errors**

Open Godot. The project should have zero GDScript errors in the Output panel. In particular, confirm `weapon_option.gd` shows no parse errors.

- [ ] **Step 4: Commit**

```bash
git add dialog/ui/playermenu/weapon_option.gd dialog/ui/playermenu/weapon_option.tscn
git commit -m "refactor: remove mouse click from WeaponOption, add keyboard cursor visual"
```

---

### Task 3: Add WASD + F/Space keyboard navigation to PlayerMenu

**Files:**
- Modify: `dialog/ui/playermenu/player_menu.gd`

**Context — what changes:**
1. Remove `option_pressed.connect(...)` calls in `_populate_lists()` (signal no longer exists).
2. Add `_cursor_col: int` (0 = main weapons, 1 = sub weapons) and `_cursor_row: int`.
3. Call `_init_cursor()` inside `_toggle()` when opening so cursor starts at the currently active option.
4. Handle `menu_up/down/left/right/menu_confirm` in `_unhandled_input` when visible.
5. Add `_refresh_cursor()` to apply `set_cursor` to every option.
6. Add `_confirm_selection()` to commit the highlighted choice and close the menu.
7. Add `_current_col_options()` helper that returns the correct Array based on `_cursor_col`.

- [ ] **Step 1: Rewrite player_menu.gd**

Replace the entire file with:

```gdscript
# dialog/ui/playermenu/player_menu.gd
class_name PlayerMenu
extends Node2D

const _WEAPON_OPTION_SCENE: PackedScene = preload("res://dialog/ui/playermenu/weapon_option.tscn")
const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

## Starting position of the main weapon list (within the weapon selection block).
## Tune these if the items appear in the wrong place.
const _WEAPON_LIST_ORIGIN := Vector2(48.0, 115.0)
const _SUB_LIST_ORIGIN := Vector2(215.0, 115.0)
const _ROW_HEIGHT: float = 30.0

const _WEAPON_ICONS: Dictionary = {
	&"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"long_range":   preload("res://assault/assets/sprites/ui/icon_ship_weapon_pierce.png"),
	&"piercing":     preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"spread":       preload("res://assault/assets/sprites/ui/icon_ship_weapon_spread.png"),
	&"gatling":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_gatling.png"),
	&"mining_laser": preload("res://assault/assets/sprites/ui/icon_ship_weapon_mining_laser.png"),
}

const _SUB_WEAPON_ICONS: Array[Texture2D] = [
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_missiles_barage.png"),
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_homming_misile.png"),
]
const _SUB_WEAPON_NAMES: Array[String] = ["Missiles Barrage", "Homing Missile"]

var _weapon_state: WeaponState = null
var _rocket_state: RocketState = null
var _weapon_options: Array[WeaponOption] = []
var _sub_options: Array[WeaponOption] = []
var _was_paused_by_us: bool = false

## Cursor position: col 0 = main weapons, col 1 = sub weapons.
var _cursor_col: int = 0
var _cursor_row: int = 0

func _ready() -> void:
	visible = false
	## ALWAYS so _unhandled_input fires even when SceneTree.paused = true.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called by hud.gd once the player state nodes are known.
## Pass null for either argument if the state does not exist in this scene.
func connect_states(weapon: WeaponState, rocket: RocketState) -> void:
	_weapon_state = weapon
	_rocket_state = rocket
	_populate_lists()
	_refresh_selection()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_player_menu"):
		_toggle()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed("menu_up"):
		_cursor_row = maxi(_cursor_row - 1, 0)
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		var col_size: int = _current_col_options().size()
		_cursor_row = mini(_cursor_row + 1, col_size - 1)
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_cursor_col = 0
		_cursor_row = clampi(_cursor_row, 0, maxi(_weapon_options.size() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cursor_col = 1
		_cursor_row = clampi(_cursor_row, 0, maxi(_sub_options.size() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		_confirm_selection()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if not visible:
		## Do not open over an already-paused scene (e.g. DialogPlayer active).
		if get_tree().paused:
			return
		visible = true
		get_tree().paused = true
		_was_paused_by_us = true
		_init_cursor()
		_refresh_cursor()
	else:
		visible = false
		if _was_paused_by_us:
			get_tree().paused = false
			_was_paused_by_us = false

## Place the cursor on the currently active weapon/sub-weapon when the menu opens.
func _init_cursor() -> void:
	var ids := UpgradeState.unlocked_ids()
	var active_id: StringName = &""
	if _weapon_state != null:
		active_id = _weapon_state.get_active_id()
	var found_row: int = 0
	for i: int in ids.size():
		if ids[i] == active_id:
			found_row = i
			break
	_cursor_col = 0
	_cursor_row = found_row

## Apply cursor highlight to the option at (_cursor_col, _cursor_row),
## clear highlight from all others.
func _refresh_cursor() -> void:
	for i: int in _weapon_options.size():
		_weapon_options[i].set_cursor(_cursor_col == 0 and i == _cursor_row)
	for j: int in _sub_options.size():
		_sub_options[j].set_cursor(_cursor_col == 1 and j == _cursor_row)

## Commit the highlighted option and close the menu.
func _confirm_selection() -> void:
	if _cursor_col == 0:
		var ids := UpgradeState.unlocked_ids()
		if _cursor_row < ids.size():
			_on_main_weapon_pressed(ids[_cursor_row])
	else:
		_on_sub_weapon_pressed(_cursor_row)
	_toggle()

## Returns the option array for the currently focused column.
func _current_col_options() -> Array[WeaponOption]:
	return _weapon_options if _cursor_col == 0 else _sub_options

func _populate_lists() -> void:
	## Clear previously created options (safe to call more than once).
	for opt: WeaponOption in _weapon_options:
		opt.queue_free()
	_weapon_options.clear()
	for sopt: WeaponOption in _sub_options:
		sopt.queue_free()
	_sub_options.clear()

	## Main weapons — only the ones currently unlocked in UpgradeState.
	var ids := UpgradeState.unlocked_ids()
	for i: int in ids.size():
		var id := ids[i]
		var opt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(opt)
		opt.position = _WEAPON_LIST_ORIGIN + Vector2(0.0, i * _ROW_HEIGHT)
		var icon: Texture2D = _WEAPON_ICONS.get(id, null) as Texture2D
		var mode := _load_mode(id)
		var dname: String = mode.display_name if mode != null else String(id)
		opt.configure(dname, icon)
		_weapon_options.append(opt)

	## Sub weapons — always both options, regardless of unlock state.
	for j: int in 2:
		var sopt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(sopt)
		sopt.position = _SUB_LIST_ORIGIN + Vector2(0.0, j * _ROW_HEIGHT)
		sopt.configure(_SUB_WEAPON_NAMES[j], _SUB_WEAPON_ICONS[j])
		_sub_options.append(sopt)

func _load_mode(id: StringName) -> WeaponModeResource:
	var path := _MODES_DIR + String(id) + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as WeaponModeResource
	return null

func _refresh_selection() -> void:
	var active_id: StringName = &""
	if _weapon_state != null:
		active_id = _weapon_state.get_active_id()
	var ids := UpgradeState.unlocked_ids()
	for i: int in _weapon_options.size():
		_weapon_options[i].set_selected(i < ids.size() and ids[i] == active_id)

	var active_type: int = 0
	if _rocket_state != null:
		active_type = _rocket_state.get_type()
	for j: int in _sub_options.size():
		_sub_options[j].set_selected(j == active_type)

func _on_main_weapon_pressed(id: StringName) -> void:
	if _weapon_state != null:
		_weapon_state.select_weapon(id)
	_refresh_selection()

func _on_sub_weapon_pressed(type: int) -> void:
	if _rocket_state != null:
		_rocket_state.select_sub_weapon(type)
	_refresh_selection()
```

- [ ] **Step 2: Verify no compile errors**

Open Godot. The Output panel should show zero script errors. In particular:
- `weapon_option.gd` no longer references `ClickArea`
- `player_menu.gd` no longer references `option_pressed`

- [ ] **Step 3: Manual smoke test**

Run the game, enter the Assault mission:
1. Press **Tab** → menu opens, first weapon row brightens (cursor highlight visible).
2. Press **S** → cursor moves down one row; previous row returns to normal colour.
3. Press **W** → cursor moves back up.
4. Press **D** → cursor jumps to the sub-weapons column (Missiles Barrage brightens).
5. Press **S** → cursor moves to Homing Missile.
6. Press **F** (or **Space**) → sub-weapon switches, menu closes, game unpauses.
7. Press **Tab** again → menu reopens with new selection highlighted in the selected state (white background sprite).
8. Press **Tab** to close without confirming → game resumes unchanged.

- [ ] **Step 4: Commit**

```bash
git add dialog/ui/playermenu/player_menu.gd
git commit -m "feat: WASD + F/Space keyboard navigation for player menu"
```

---

## Self-Review

**Spec coverage:**
- W/S moves cursor up/down within focused column ✅ (`menu_up`/`menu_down` in `_unhandled_input`)
- A/D switches column ✅ (`menu_left`/`menu_right`)
- F/Space confirms selection ✅ (`menu_confirm` maps both keys; `_confirm_selection` closes menu)
- Cursor visual is separate from selection state ✅ (`set_cursor` modulates colour; `set_selected` changes `_bg_sprite.texture`)
- Mouse click removed ✅ (Button node deleted, `option_pressed` signal deleted)

**Placeholder scan:** No TBDs, no "similar to Task N" references, all code blocks complete.

**Type consistency:**
- `_current_col_options()` returns `Array[WeaponOption]` — matches the typed array fields `_weapon_options` and `_sub_options`.
- `_confirm_selection()` reads `ids[_cursor_row]` guarded by bounds check — matches `_on_main_weapon_pressed(id: StringName)`.
- `set_cursor(bool)` defined in Task 2, called in Task 3 — signature matches.
