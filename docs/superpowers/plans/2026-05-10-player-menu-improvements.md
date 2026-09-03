# Player Menu Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify WeaponOption to a single texture with pink modulate for the selected state, introduce a reusable WeaponFrame component that owns its own list, and make menu confirm (Space/F) select without closing.

**Architecture:** WeaponOption stops swapping textures and instead tints `_bg_sprite.modulate` pink when selected. WeaponFrame (Node2D + Sprite2D background + dynamically-added WeaponOption children) encapsulates a weapon list column. PlayerMenu swaps its two bare `Array[WeaponOption]` for two `WeaponFrame` onready references and removes the auto-close from `_confirm_selection`.

**Tech Stack:** Godot 4.6, GDScript, CanvasLayer-based PlayerMenu, existing `weapon_option.tscn` scene, `weapong_list_frame.png` texture already referenced in `player_menu.tscn`.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `dialog/ui/playermenu/weapon_option.gd` | Remove dual textures; manage selected/cursor state via `modulate` only |
| Create | `dialog/ui/playermenu/weapon_frame.gd` | Populate up to 8 WeaponOption children; expose cursor/selection API |
| Create | `dialog/ui/playermenu/weapon_frame.tscn` | Node2D root + `FrameBackground` Sprite2D with `weapong_list_frame.png` |
| Modify | `dialog/ui/playermenu/player_menu.gd` | Use `WeaponFrame` onready vars; remove `_toggle()` from confirm |
| Modify | `dialog/ui/playermenu/player_menu.tscn` | Replace two `Sprite2D` frame nodes with two `WeaponFrame` instances |

---

### Task 1: Simplify WeaponOption — single texture, modulate-based states

**Files:**
- Modify: `dialog/ui/playermenu/weapon_option.gd`

No scene changes needed — `weapon_option.tscn` already uses `weapon_list_item.png` as the single texture on `SelectionBG`.

- [ ] **Step 1: Write the updated weapon_option.gd**

Replace the entire file with:

```gdscript
# dialog/ui/playermenu/weapon_option.gd
class_name WeaponOption
extends Control

## Pink tint applied to the background sprite when this item is the active selection.
const _SELECTED_MODULATE := Color(2.0, 0.5, 1.2)
## Yellow tint applied to the whole control when the keyboard cursor is here.
const _CURSOR_MODULATE := Color(1.4, 1.4, 1.0)
const _NORMAL_MODULATE := Color.WHITE

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $SelectionBG/WeaponName

var _is_selected: bool = false
var _is_cursor: bool = false

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Tint the background sprite pink when selected, or restore it to white.
func set_selected(value: bool) -> void:
	_is_selected = value
	_update_modulate()

## Highlight the whole row yellow when the keyboard cursor is here.
func set_cursor(value: bool) -> void:
	_is_cursor = value
	_update_modulate()

func _update_modulate() -> void:
	if _is_cursor:
		modulate = _CURSOR_MODULATE
		_bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
	else:
		modulate = _NORMAL_MODULATE
		_bg_sprite.modulate = _SELECTED_MODULATE if _is_selected else _NORMAL_MODULATE
```

- [ ] **Step 2: Verify no old texture constants remain**

Open `weapon_option.gd` and confirm there are no references to `_TEX_UNSELECTED`, `_TEX_SELECTED`, `weapon_list_item_select_option.png`, or `weapon_list_item_selected_option.png`.

- [ ] **Step 3: Commit**

```bash
git add dialog/ui/playermenu/weapon_option.gd
git commit -m "refactor: WeaponOption uses single texture with modulate for selected/cursor states"
```

---

### Task 2: Create WeaponFrame component

**Files:**
- Create: `dialog/ui/playermenu/weapon_frame.gd`
- Create: `dialog/ui/playermenu/weapon_frame.tscn`

- [ ] **Step 1: Write weapon_frame.gd**

Create `dialog/ui/playermenu/weapon_frame.gd`:

```gdscript
# dialog/ui/playermenu/weapon_frame.gd
class_name WeaponFrame
extends Node2D

const _WEAPON_OPTION_SCENE: PackedScene = preload("res://dialog/ui/playermenu/weapon_option.tscn")
const _ROW_HEIGHT: float = 30.0
const MAX_ITEMS: int = 8

## Local-space origin for the first list item relative to this node's position.
## Tune in the Inspector if items don't align with the frame background.
@export var item_origin: Vector2 = Vector2(0.0, -45.0)

var _options: Array[WeaponOption] = []

## Populate the list from parallel arrays of names and icons.
## Excess items beyond MAX_ITEMS are silently ignored.
## Clears any previously created options first.
func populate(display_names: Array[String], icons: Array[Texture2D]) -> void:
	for opt: WeaponOption in _options:
		opt.queue_free()
	_options.clear()

	var count: int = mini(display_names.size(), MAX_ITEMS)
	for i: int in count:
		var opt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(opt)
		opt.position = item_origin + Vector2(0.0, i * _ROW_HEIGHT)
		var icon: Texture2D = icons[i] if i < icons.size() else null
		opt.configure(display_names[i], icon)
		_options.append(opt)

## Move the cursor highlight to the item at idx. Pass -1 to clear all.
func set_cursor(idx: int) -> void:
	for i: int in _options.size():
		_options[i].set_cursor(i == idx)

## Mark the item at idx as selected (pink). Pass -1 to clear all.
func set_selected(idx: int) -> void:
	for i: int in _options.size():
		_options[i].set_selected(i == idx)

## Number of items currently in this frame.
func get_count() -> int:
	return _options.size()
```

- [ ] **Step 2: Create weapon_frame.tscn**

Create `dialog/ui/playermenu/weapon_frame.tscn` with this content (Godot will assign real UIDs when the file is opened in the editor; use the editor's "Create New Scene" workflow or write the file then open it in Godot to let it auto-assign UIDs):

```
[gd_scene format=3 uid="uid://wframe_placeholder"]

[ext_resource type="Script" path="res://dialog/ui/playermenu/weapon_frame.gd" id="1_wframe"]
[ext_resource type="Texture2D" uid="uid://dvxe4wg23n83j" path="res://assault/assets/sprites/ui/weapong_list_frame.png" id="2_wframe"]

[node name="WeaponFrame" type="Node2D"]
script = ExtResource("1_wframe")

[node name="FrameBackground" type="Sprite2D" parent="."]
texture = ExtResource("2_wframe")
```

> **Note on UIDs:** The UID `uid://dvxe4wg23n83j` for `weapong_list_frame.png` is taken directly from `player_menu.tscn` where the same texture is already registered. The root scene UID `uid://wframe_placeholder` is a placeholder — Godot will replace it with a real UID on first save. If writing the file directly, open the scene in Godot once and re-save to normalise it.

- [ ] **Step 3: Open weapon_frame.tscn in Godot and confirm FrameBackground displays the frame sprite**

The FrameBackground Sprite2D should show `weapong_list_frame.png` centered at the node origin. If the UID placeholder causes an error, open the file in a text editor, remove the `uid="uid://wframe_placeholder"` attribute from the `[gd_scene]` line, then reopen in Godot — it will auto-assign a valid UID.

- [ ] **Step 4: Commit**

```bash
git add dialog/ui/playermenu/weapon_frame.gd dialog/ui/playermenu/weapon_frame.tscn
git commit -m "feat: add WeaponFrame component with frame background and dynamic option list"
```

---

### Task 3: Update PlayerMenu script to use WeaponFrame

**Files:**
- Modify: `dialog/ui/playermenu/player_menu.gd`

The scene nodes `MainWeaponFrame` and `SubWeaponFrame` don't exist yet (they're added in Task 4), but we write the script first so Task 4 can validate the names match.

- [ ] **Step 1: Write the updated player_menu.gd**

Replace the entire file with:

```gdscript
# dialog/ui/playermenu/player_menu.gd
class_name PlayerMenu
extends CanvasLayer

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

const _WEAPON_ICONS: Dictionary = {
	&"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"long_range":   preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"piercing":     preload("res://assault/assets/sprites/ui/icon_ship_weapon_pierce.png"),
	&"spread":       preload("res://assault/assets/sprites/ui/icon_ship_weapon_spread.png"),
	&"gatling":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_gatling.png"),
	&"mining_laser": preload("res://assault/assets/sprites/ui/icon_ship_weapon_mining_laser.png"),
}

const _SUB_WEAPON_ICONS: Array[Texture2D] = [
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_missiles_barage.png"),
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_homming_misile.png"),
]
const _SUB_WEAPON_NAMES: Array[String] = ["Missiles Barrage", "Homing Missile"]

@onready var _main_frame: WeaponFrame = $ShipLayout/MainWeaponFrame
@onready var _sub_frame: WeaponFrame = $ShipLayout/SubWeaponFrame

var _weapon_state: WeaponState = null
var _rocket_state: RocketState = null
var _was_paused_by_us: bool = false

## Cursor position: col 0 = main weapons, col 1 = sub weapons.
var _cursor_col: int = 0
var _cursor_row: int = 0

func _ready() -> void:
	visible = false
	## ALWAYS so _input fires even when SceneTree.paused = true.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called by hud.gd once the player state nodes are known.
## Pass null for either argument if the state does not exist in this scene.
func connect_states(weapon: WeaponState, rocket: RocketState) -> void:
	_weapon_state = weapon
	_rocket_state = rocket
	_populate_lists()
	_refresh_selection()

func _input(event: InputEvent) -> void:
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
		var col_size: int = _current_frame().get_count()
		_cursor_row = mini(_cursor_row + 1, col_size - 1)
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_cursor_col = 0
		_cursor_row = clampi(_cursor_row, 0, maxi(_main_frame.get_count() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cursor_col = 1
		_cursor_row = clampi(_cursor_row, 0, maxi(_sub_frame.get_count() - 1, 0))
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
	_main_frame.set_cursor(_cursor_row if _cursor_col == 0 else -1)
	_sub_frame.set_cursor(_cursor_row if _cursor_col == 1 else -1)

## Commit the highlighted option WITHOUT closing the menu.
## The menu is closed only by toggle_player_menu (Tab).
func _confirm_selection() -> void:
	if _cursor_col == 0:
		var ids := UpgradeState.unlocked_ids()
		if _cursor_row < ids.size():
			_on_main_weapon_pressed(ids[_cursor_row])
	else:
		_on_sub_weapon_pressed(_cursor_row)

## Returns the WeaponFrame for the currently focused column.
func _current_frame() -> WeaponFrame:
	return _main_frame if _cursor_col == 0 else _sub_frame

func _populate_lists() -> void:
	## Main weapons — only the ones currently unlocked in UpgradeState.
	var ids := UpgradeState.unlocked_ids()
	var main_names: Array[String] = []
	var main_icons: Array[Texture2D] = []
	for id: StringName in ids:
		var mode := _load_mode(id)
		main_names.append(mode.display_name if mode != null else String(id))
		main_icons.append(_WEAPON_ICONS.get(id, null) as Texture2D)
	_main_frame.populate(main_names, main_icons)

	## Sub weapons — always both options, regardless of unlock state.
	var sub_icons: Array[Texture2D] = []
	for tex: Texture2D in _SUB_WEAPON_ICONS:
		sub_icons.append(tex)
	_sub_frame.populate(_SUB_WEAPON_NAMES, sub_icons)

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
	var selected_main: int = -1
	for i: int in ids.size():
		if ids[i] == active_id:
			selected_main = i
			break
	_main_frame.set_selected(selected_main)

	var active_type: int = -1
	if _rocket_state != null:
		active_type = _rocket_state.get_type()
	_sub_frame.set_selected(active_type)

func _on_main_weapon_pressed(id: StringName) -> void:
	if _weapon_state != null:
		_weapon_state.select_weapon(id)
	_refresh_selection()

func _on_sub_weapon_pressed(type: int) -> void:
	if _rocket_state != null:
		_rocket_state.select_sub_weapon(type)
	_refresh_selection()
```

- [ ] **Step 2: Commit**

```bash
git add dialog/ui/playermenu/player_menu.gd
git commit -m "refactor: PlayerMenu uses WeaponFrame instances; confirm no longer closes menu"
```

---

### Task 4: Update PlayerMenu scene — replace Sprite2D frames with WeaponFrame instances

**Files:**
- Modify: `dialog/ui/playermenu/player_menu.tscn`

The `weapong_list_frame.png` texture is now owned by `weapon_frame.tscn`, so we remove it from `player_menu.tscn`'s ext_resource list and replace the two Sprite2D frame nodes with WeaponFrame instances.

- [ ] **Step 1: Confirm weapon_frame.tscn UID**

Open `dialog/ui/playermenu/weapon_frame.tscn` in a text editor and note the actual UID on the `[gd_scene]` line (it should now be a real Godot UID, e.g. `uid://abc123xyz`). You'll need this for the `[ext_resource]` entry in `player_menu.tscn`.

- [ ] **Step 2: Write the updated player_menu.tscn**

Replace the file content with the version below, substituting `WEAPON_FRAME_UID` with the actual UID from Step 1.

```
[gd_scene format=3 uid="uid://d3w5o2bii2h1"]

[ext_resource type="Script" uid="uid://lthfqw7ta0fk" path="res://dialog/ui/playermenu/player_menu.gd" id="1_pmscr"]
[ext_resource type="Texture2D" uid="uid://bkeo4jt6bn8id" path="res://assault/assets/sprites/ui/menu_background.png" id="2_prlwd"]
[ext_resource type="Texture2D" uid="uid://d4frnoy54445x" path="res://assault/assets/sprites/ui/menu_overlay.png" id="3_kttvs"]
[ext_resource type="PackedScene" uid="WEAPON_FRAME_UID" path="res://dialog/ui/playermenu/weapon_frame.tscn" id="4_wframe"]

[node name="PlayerMenu" type="CanvasLayer" unique_id=1746219549]
layer = 10
script = ExtResource("1_pmscr")

[node name="MenuBackground" type="Sprite2D" parent="." unique_id=1166869381]
position = Vector2(320.37283, 179.89725)
scale = Vector2(1.0005707, 1.0005709)
texture = ExtResource("2_prlwd")

[node name="MenuOverlay" type="Sprite2D" parent="." unique_id=1026570547]
position = Vector2(320, 180)
texture = ExtResource("3_kttvs")

[node name="ShipLayout" type="Node2D" parent="." unique_id=1492636392]

[node name="MainWeaponFrame" parent="ShipLayout" instance=ExtResource("4_wframe") unique_id=614383502]
position = Vector2(92, 148)

[node name="SubWeaponFrame" parent="ShipLayout" instance=ExtResource("4_wframe") unique_id=1961283415]
position = Vector2(261, 148)
```

> **Why these positions?** The original `ShipWeaponSelectionBlock` and `ShipSubWeaponSelectionBlock` sprites were at (92, 148) and (261, 148). The new WeaponFrame instances sit at the same positions so the frame backgrounds appear in the same place. Item positions within the frame are controlled by `WeaponFrame.item_origin`.

- [ ] **Step 3: Open the scene in Godot and verify**

1. `PlayerMenu` scene opens without errors.
2. Two `WeaponFrame` instances appear under `ShipLayout`, each showing the `weapong_list_frame.png` background sprite.
3. No orphan `ShipWeaponSelectionBlock` or `ShipSubWeaponSelectionBlock` nodes remain.

- [ ] **Step 4: Tune item_origin if needed**

Run the game, open the player menu (Tab), and check that the weapon option rows appear inside the frame backgrounds. If they're misaligned, select each `WeaponFrame` instance in the Godot editor and adjust its `item_origin` export property until the items sit inside the frame sprite.

- [ ] **Step 5: Commit**

```bash
git add dialog/ui/playermenu/player_menu.tscn
git commit -m "feat: replace frame Sprite2D nodes with WeaponFrame scene instances in PlayerMenu"
```

---

## Manual Verification Checklist

After all four tasks are complete, verify in-game:

- [ ] Opening the menu (Tab) shows both weapon lists inside their frame backgrounds.
- [ ] The currently-active main weapon has a **pink** background tint.
- [ ] The currently-active sub-weapon has a **pink** background tint.
- [ ] Moving the keyboard cursor (W/S) shows a **yellow** row highlight that moves independently of selection.
- [ ] Moving left/right (A/D) switches between the two columns.
- [ ] Pressing confirm (Space/F) changes the active weapon (pink moves) but the menu **stays open**.
- [ ] Pressing Tab closes the menu and resumes gameplay.
- [ ] The menu cannot be opened while a dialog is active (tree already paused).
- [ ] No more than 8 items appear in either column regardless of unlock count.
