# Player Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Tab-toggled player menu that pauses the game and lets the player select from unlocked main weapons and sub-weapons, available in both assault and open-space missions.

**Architecture:** The existing `player_menu.tscn` (currently sprites-only) gets a new `player_menu.gd` script and is instantiated as a child of each scene's HUD CanvasLayer. `weapon_option.tscn` is rebuilt from a Node2D-root scene to a Control-root scene so that Button click events work correctly inside a CanvasLayer during pause. `player_menu.gd` handles Tab toggle, game pause via `SceneTree.paused`, and delegates weapon selection to `WeaponState.select_weapon()` and `RocketState.select_sub_weapon()`.

**Tech Stack:** Godot 4.6 GDScript, CanvasLayer, Control/Button nodes, SceneTree.paused.

---

## File Map

**Create:**
- `assault/scenes/player/weapons/modes/gatling.tres`
- `assault/scenes/player/weapons/modes/mining_laser.tres`
- `dialog/ui/playermenu/weapon_option.gd`
- `dialog/ui/playermenu/player_menu.gd`

**Rewrite:**
- `dialog/ui/playermenu/weapon_option.tscn` — change root to Control, add Label and transparent Button
- `dialog/ui/playermenu/player_menu.tscn` — add script reference

**Modify:**
- `project.godot` — add `toggle_player_menu` input action (Tab key, physical_keycode=4194306)
- `global/autoloads/upgrade_state.gd` — add `&"gatling"` and `&"mining_laser"` to `ALL_IDS`
- `assault/scenes/player/states/weapon_state.gd` — add `select_weapon()` and `get_active_id()`
- `assault/scenes/player/states/warhead_missile_shooting_state.gd` — add `select_sub_weapon()` and `get_type()`
- `assault/scenes/gui/hud.tscn` — add PlayerMenu instance, bump load_steps from 7 to 8
- `assault/scenes/gui/hud.gd` — wire PlayerMenu to WeaponState and RocketState
- `open_space/scenes/gui/hud.tscn` — add PlayerMenu instance, bump load_steps from 3 to 4
- `open_space/scenes/gui/hud.gd` — wire PlayerMenu (null states — open-space has no WeaponState)

---

## Key References

**Weapon Behavior enum** (in `assault/scenes/player/weapons/weapon_mode.gd`):
```
STRAIGHT = 0, LONG = 1, BEAM = 2, SPREAD = 3
```

**Existing weapon IDs and their .tres behavior values:**
- `default` → STRAIGHT (0), fire_interval=0.18, damage=50
- `long_range` → LONG (1), fire_interval=0.45, damage=75
- `piercing` → BEAM (2), beam_dps=30.0
- `spread` → SPREAD (3), fire_interval=0.18, damage=25, pellet_count=5

**WeaponState node path in assault player:** `AttackStateMachine/WeaponState`
**RocketState node path in assault player:** `AttackStateMachine/WarheadMissileShootingState`

**player_menu.tscn UID:** `uid://d3w5o2bii2h1` — must be preserved when adding script reference.

**Available weapon icons** (all in `assault/assets/sprites/ui/`):
- `icon_ship_weapon_laser.png` (uid://dbh2oxtyrkd3u) — used for `default`
- `icon_ship_weapon_pierce.png` (uid://yu1cwveum40p) — used for `long_range`
- `icon_ship_weapon_spread.png` (uid://c2waqxkhyyo54) — used for `spread`
- `icon_ship_weapon_gatling.png` (uid://c0msodcjbtq7p) — used for `gatling`
- `icon_ship_weapon_mining_laser.png` (uid://deogcxosko76o) — used for `mining_laser`
- `icon_ship_weapon_laser.png` — also used for `piercing` (it's a beam weapon)
- `icon_ship_subweapon_missiles_barage.png` (uid://crbh7jjbnp4kl) — sub-weapon 0
- `icon_ship_subweapon_homming_misile.png` (uid://b3gfp6l7tv04o) — sub-weapon 1

---

### Task 1: Add toggle_player_menu input action to project.godot

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Find the `[input]` section in project.godot**

It's around line 60. It contains blocks like `shoot=`, `cycle_weapon=`, `use_ability=`.

- [ ] **Step 2: Insert the toggle_player_menu action after the `use_ability` block**

Tab key: physical_keycode=4194306, unicode=9. Add this block immediately after the closing `}` of `use_ability`:

```
toggle_player_menu={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194306,"key_label":0,"unicode":9,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 3: Verify the action is present**

```bash
grep "toggle_player_menu" project.godot
```

Expected output: `toggle_player_menu={`

- [ ] **Step 4: Commit**

```bash
git add project.godot
git commit -m "feat: add toggle_player_menu input action (Tab key)"
```

---

### Task 2: Add Gatling and Mining Laser weapon data

**Files:**
- Modify: `global/autoloads/upgrade_state.gd`
- Create: `assault/scenes/player/weapons/modes/gatling.tres`
- Create: `assault/scenes/player/weapons/modes/mining_laser.tres`

- [ ] **Step 1: Add the two new IDs to UpgradeState.ALL_IDS**

In `global/autoloads/upgrade_state.gd`, change:

```gdscript
const ALL_IDS: Array[StringName] = [
	&"default", &"long_range", &"piercing", &"spread"
]
```

to:

```gdscript
const ALL_IDS: Array[StringName] = [
	&"default", &"long_range", &"piercing", &"spread", &"gatling", &"mining_laser"
]
```

- [ ] **Step 2: Create `assault/scenes/player/weapons/modes/gatling.tres`**

STRAIGHT behavior (behavior=0), rapid fire (fire_interval=0.06), lower damage per shot (18). Reuses the same bullet.tscn as `default`. The UID `uid://bvyhnlpuw5rcv` is the existing bullet.tscn — verify with:
```bash
grep "bvyhnlpuw5rcv" assault/scenes/player/weapons/modes/default.tres
```

Create the file:

```
[gd_resource type="Resource" script_class="WeaponModeResource" load_steps=3 format=3]

[ext_resource type="Script" path="res://assault/scenes/player/weapons/weapon_mode.gd" id="1_script"]
[ext_resource type="PackedScene" uid="uid://bvyhnlpuw5rcv" path="res://assault/scenes/projectiles/bullets/bullet.tscn" id="2_bullet"]

[resource]
script = ExtResource("1_script")
id = &"gatling"
display_name = "Gatling"
behavior = 0
projectile_scene = ExtResource("2_bullet")
range_px = 150.0
fire_interval = 0.06
damage = 18
heat_per_shot = 0.4
pellet_count = 1
pellet_spread_deg = 60.0
homing_turn_rate_deg_per_sec = 90.0
homing_lifetime_sec = 1.6
beam_dps = 30.0
```

- [ ] **Step 3: Create `assault/scenes/player/weapons/modes/mining_laser.tres`**

BEAM behavior (behavior=2), slow DPS (beam_dps=12.0) — gentler burn than the existing `piercing` beam (30.0). No projectile_scene needed for BEAM.

```
[gd_resource type="Resource" script_class="WeaponModeResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/player/weapons/weapon_mode.gd" id="1_script"]

[resource]
script = ExtResource("1_script")
id = &"mining_laser"
display_name = "Mining Laser"
behavior = 2
range_px = 0.0
fire_interval = 0.18
damage = 0
heat_per_shot = 2.5
pellet_count = 1
pellet_spread_deg = 60.0
homing_turn_rate_deg_per_sec = 90.0
homing_lifetime_sec = 1.6
beam_dps = 12.0
```

- [ ] **Step 4: Verify all 6 mode files exist**

```bash
ls assault/scenes/player/weapons/modes/
```

Expected: `default.tres  gatling.tres  long_range.tres  mining_laser.tres  piercing.tres  spread.tres`

**Testing note:** `UpgradeState` starts with only `default` unlocked (first-run default). Gatling and Mining Laser won't appear in the menu until unlocked. To test them, temporarily add to `_ready()` in upgrade_state.gd:
```gdscript
unlock_all()
```
or call `UpgradeState.unlock_all()` from the GDScript REPL after starting a scene. Remove the debug line before shipping.

- [ ] **Step 5: Commit**

```bash
git add global/autoloads/upgrade_state.gd assault/scenes/player/weapons/modes/gatling.tres assault/scenes/player/weapons/modes/mining_laser.tres
git commit -m "feat: add Gatling and Mining Laser weapon modes"
```

---

### Task 3: Add public weapon selection and query APIs

**Files:**
- Modify: `assault/scenes/player/states/weapon_state.gd`
- Modify: `assault/scenes/player/states/warhead_missile_shooting_state.gd`

- [ ] **Step 1: Add `get_active_id()` and `select_weapon()` to weapon_state.gd**

Open `assault/scenes/player/states/weapon_state.gd`. Find the `emit_current_mode()` method (around line 116). Add these two methods directly after it:

```gdscript
## Public: return the currently active weapon ID.
func get_active_id() -> StringName:
	return _active_id

## Public: switch to a specific weapon by ID. No-op if ID is not unlocked.
## Mirrors _cycle() behaviour: releases beam, resets cooldown, emits changed signal.
func select_weapon(id: StringName) -> void:
	if not UpgradeState.is_unlocked(id):
		return
	if id == _active_id:
		return
	var prev_id := _active_id
	_active_id = id
	if prev_id != _active_id:
		var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
		beam.release(self)
		_cooldown = 0.0
		_emit_changed()
```

- [ ] **Step 2: Add `get_type()` and `select_sub_weapon()` to warhead_missile_shooting_state.gd**

Open `assault/scenes/player/states/warhead_missile_shooting_state.gd`. Find `get_current_icon()` (around line 22). Add these two methods directly after it:

```gdscript
## Public: return the current sub-weapon type (0=warhead, 1=homing).
func get_type() -> int:
	return _type

## Public: switch to sub-weapon type (0=warhead, 1=homing). Emits weapon_changed.
func select_sub_weapon(type: int) -> void:
	var clamped: int = clampi(type, 0, 1)
	if clamped == _type:
		return
	_type = clamped
	weapon_changed.emit(get_current_icon())
```

- [ ] **Step 3: Verify the new methods are present**

```bash
grep -n "select_weapon\|get_active_id" assault/scenes/player/states/weapon_state.gd
grep -n "select_sub_weapon\|get_type" assault/scenes/player/states/warhead_missile_shooting_state.gd
```

Expected: both greps return two matching lines each.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/player/states/weapon_state.gd assault/scenes/player/states/warhead_missile_shooting_state.gd
git commit -m "feat: expose select_weapon, get_active_id, select_sub_weapon, get_type"
```

---

### Task 4: Rebuild weapon_option.tscn and create weapon_option.gd

**Files:**
- Create: `dialog/ui/playermenu/weapon_option.gd`
- Rewrite: `dialog/ui/playermenu/weapon_option.tscn`

The current `weapon_option.tscn` root is `Node2D`. We're changing it to `Control` so that the `Button` child receives mouse input correctly inside a paused CanvasLayer. The existing Sprite2D children and their `unique_id` values are preserved to avoid breaking any editor references.

- [ ] **Step 1: Create `dialog/ui/playermenu/weapon_option.gd`**

```gdscript
# dialog/ui/playermenu/weapon_option.gd
class_name WeaponOption
extends Control

signal option_pressed

const _TEX_UNSELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_select_option.png")
const _TEX_SELECTED: Texture2D = preload("res://assault/assets/sprites/ui/weapon_list_item_selected_option.png")

@onready var _icon_sprite: Sprite2D = $WeaponIcon
@onready var _bg_sprite: Sprite2D = $SelectionBG
@onready var _label: Label = $WeaponName
@onready var _button: Button = $ClickArea

func _ready() -> void:
	_button.pressed.connect(func() -> void: option_pressed.emit())

## Set the display name and icon texture. Call this after instantiating the scene.
func configure(display_name: String, icon: Texture2D) -> void:
	_label.text = display_name
	if icon != null:
		_icon_sprite.texture = icon

## Swap the background sprite between unselected and selected state.
func set_selected(value: bool) -> void:
	_bg_sprite.texture = _TEX_SELECTED if value else _TEX_UNSELECTED
```

- [ ] **Step 2: Rewrite `dialog/ui/playermenu/weapon_option.tscn`**

The scene's top-level UID (`uid://b8e2nn88icol6`) **must stay the same**. Existing `unique_id` values for the two Sprite2D nodes are also preserved. New nodes (Label, Button) get new unique_id values. `WeaponIcon` starts with no texture — `configure()` sets it at runtime. `SelectionBG` starts with the unselected texture.

Replace the entire file content with:

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

[node name="ClickArea" type="Button" parent="." unique_id=345678901]
anchor_right = 1.0
anchor_bottom = 1.0
flat = true
focus_mode = 0
```

- [ ] **Step 3: Verify the root type and child nodes**

```bash
grep "type=" dialog/ui/playermenu/weapon_option.tscn
```

Expected:
```
[node name="WeaponOption" type="Control" unique_id=318341931]
[node name="WeaponIcon" type="Sprite2D" parent="." unique_id=2044088980]
[node name="SelectionBG" type="Sprite2D" parent="." unique_id=1804324106]
[node name="WeaponName" type="Label" parent="." unique_id=234567890]
[node name="ClickArea" type="Button" parent="." unique_id=345678901]
```

- [ ] **Step 4: Commit**

```bash
git add dialog/ui/playermenu/weapon_option.tscn dialog/ui/playermenu/weapon_option.gd
git commit -m "feat: rebuild weapon_option as Control with Label and click Button"
```

---

### Task 5: Create player_menu.gd and attach it to player_menu.tscn

**Files:**
- Create: `dialog/ui/playermenu/player_menu.gd`
- Rewrite: `dialog/ui/playermenu/player_menu.tscn`

`player_menu.gd` is the central controller: Tab toggle → show/hide + pause/unpause, populate weapon option lists from UpgradeState, delegate selection to WeaponState/RocketState. `process_mode = ALWAYS` is set in `_ready()` so input still works while the tree is paused. Children inherit ALWAYS from the parent via INHERIT mode.

- [ ] **Step 1: Create `dialog/ui/playermenu/player_menu.gd`**

```gdscript
# dialog/ui/playermenu/player_menu.gd
class_name PlayerMenu
extends Node2D

const _WEAPON_OPTION_SCENE: PackedScene = preload("res://dialog/ui/playermenu/weapon_option.tscn")
const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

## Starting Y coordinate and row height for the main weapon list.
## These place items inside the ShipWeaponSelectionBlock area (block is at x=85, y=141).
## Adjust if items appear misaligned after opening the menu in-game.
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

func _toggle() -> void:
	visible = not visible
	get_tree().paused = visible

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
		opt.option_pressed.connect(_on_main_weapon_pressed.bind(id))
		_weapon_options.append(opt)

	## Sub weapons — always both options, regardless of unlock state.
	for j: int in 2:
		var sopt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(sopt)
		sopt.position = _SUB_LIST_ORIGIN + Vector2(0.0, j * _ROW_HEIGHT)
		sopt.configure(_SUB_WEAPON_NAMES[j], _SUB_WEAPON_ICONS[j])
		sopt.option_pressed.connect(_on_sub_weapon_pressed.bind(j))
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

- [ ] **Step 2: Rewrite `dialog/ui/playermenu/player_menu.tscn` to attach the script**

The top-level UID `uid://d3w5o2bii2h1` **must stay the same**. All existing `unique_id` values and texture UIDs are preserved. A new script ext_resource is added as the first entry (`id="1_pmscr"`); the texture ext_resources are renumbered from `"1_prlwd"–"5_tbghm"` to `"2_prlwd"–"6_tbghm"`.

Replace the entire file with:

```
[gd_scene format=3 uid="uid://d3w5o2bii2h1"]

[ext_resource type="Script" path="res://dialog/ui/playermenu/player_menu.gd" id="1_pmscr"]
[ext_resource type="Texture2D" uid="uid://bkeo4jt6bn8id" path="res://assault/assets/sprites/ui/menu_background.png" id="2_prlwd"]
[ext_resource type="Texture2D" uid="uid://ce6ve5oijfnwa" path="res://assault/assets/sprites/ui/ship_menu_footer.png" id="3_1vlef"]
[ext_resource type="Texture2D" uid="uid://c2k6frhqlydy8" path="res://assault/assets/sprites/ui/ship_weapon_selection_block.png" id="4_3owwf"]
[ext_resource type="Texture2D" uid="uid://vrfm0gs8j3je" path="res://assault/assets/sprites/ui/ship_sub_weapon_selection_block.png" id="5_pmgbo"]
[ext_resource type="Texture2D" uid="uid://cy3cjqj11td6u" path="res://assault/assets/sprites/ui/menu_ship_module_upgrade_sectopm.png" id="6_tbghm"]

[node name="PlayerMenu" type="Node2D" unique_id=1746219549]
script = ExtResource("1_pmscr")

[node name="MenuBackground" type="Sprite2D" parent="." unique_id=1166869381]
position = Vector2(319, 181.00002)
scale = Vector2(0.34003058, 0.34003064)
texture = ExtResource("2_prlwd")
metadata/_edit_lock_ = true

[node name="ShipMenuFooter" type="Sprite2D" parent="MenuBackground" unique_id=164608310]
position = Vector2(2.940918, 485.25043)
scale = Vector2(1.0006719, 1.0006717)
texture = ExtResource("3_1vlef")

[node name="ShipLayout" type="Node2D" parent="." unique_id=1492636392]

[node name="ShipWeaponSelectionBlock" type="Sprite2D" parent="ShipLayout" unique_id=614383501]
position = Vector2(85, 141)
scale = Vector2(0.31798244, 0.31798244)
texture = ExtResource("4_3owwf")

[node name="ShipSubWeaponSelectionBlock" type="Sprite2D" parent="ShipLayout" unique_id=1961283414]
position = Vector2(251.00002, 141)
scale = Vector2(0.31798244, 0.31798247)
texture = ExtResource("5_pmgbo")

[node name="MenuShipModuleUpgradeSectopm" type="Sprite2D" parent="ShipLayout" unique_id=467040080]
position = Vector2(482, 142)
scale = Vector2(0.32213315, 0.32213315)
texture = ExtResource("6_tbghm")
```

- [ ] **Step 3: Verify the script is attached to the root node**

```bash
grep "script\|player_menu" dialog/ui/playermenu/player_menu.tscn
```

Expected output includes:
```
[ext_resource type="Script" path="res://dialog/ui/playermenu/player_menu.gd" id="1_pmscr"]
script = ExtResource("1_pmscr")
```

- [ ] **Step 4: Commit**

```bash
git add dialog/ui/playermenu/player_menu.gd dialog/ui/playermenu/player_menu.tscn
git commit -m "feat: create player_menu.gd and attach script to player_menu.tscn"
```

---

### Task 6: Wire PlayerMenu into assault HUD

**Files:**
- Modify: `assault/scenes/gui/hud.tscn`
- Modify: `assault/scenes/gui/hud.gd`

The assault HUD CanvasLayer already holds WeaponContainer, HealthShieldBar, AbilityChip, and WeaponChip. We add the PlayerMenu as a sixth child. `hud.gd` gets the player's WeaponState and RocketState and passes them to `player_menu.connect_states()`.

- [ ] **Step 1: Add PlayerMenu ext_resource and node to `assault/scenes/gui/hud.tscn`**

Current first line: `[gd_scene load_steps=7 format=3]`

Make the following two changes:

**Change 1** — bump load_steps from 7 to 8 (first line):
```
[gd_scene load_steps=8 format=3]
```

**Change 2** — add the ext_resource after the last existing one (after line 7, the `"5_achip"` line):
```
[ext_resource type="PackedScene" uid="uid://d3w5o2bii2h1" path="res://dialog/ui/playermenu/player_menu.tscn" id="6_pmenu"]
```

**Change 3** — add the instance node at the very end of the file (after the WeaponChip node):
```
[node name="PlayerMenu" parent="." instance=ExtResource("6_pmenu")]
```

- [ ] **Step 2: Update `assault/scenes/gui/hud.gd`**

Replace the entire file with:

```gdscript
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay
@onready var player_menu: PlayerMenu = $PlayerMenu

var _cooldown_timer: Timer = null

func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		player_menu.connect_states(null, null)
		return
	var p := players[0]

	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)

	var rocket_state := p.get_node_or_null("AttackStateMachine/WarheadMissileShootingState") as RocketState
	if rocket_state:
		weapon_icon.texture = rocket_state.get_current_icon()
		rocket_state.weapon_changed.connect(_on_weapon_changed)
		_cooldown_timer = rocket_state.get_node("CooldownTimer") as Timer

	var weapon_state := p.get_node_or_null("AttackStateMachine/WeaponState") as WeaponState
	player_menu.connect_states(weapon_state, rocket_state)

func _process(_delta: float) -> void:
	if _cooldown_timer == null or _cooldown_timer.is_stopped():
		cooldown_overlay.visible = false
		return
	var progress := 1.0 - _cooldown_timer.time_left / _cooldown_timer.wait_time
	var container := cooldown_overlay.get_parent() as Control
	var h: float = container.size.y
	cooldown_overlay.position.y = progress * h
	cooldown_overlay.size = Vector2(container.size.x, (1.0 - progress) * h)
	cooldown_overlay.visible = true

func _on_weapon_changed(icon: Texture2D) -> void:
	weapon_icon.texture = icon
```

- [ ] **Step 3: Verify the PlayerMenu node was added**

```bash
grep "PlayerMenu" assault/scenes/gui/hud.tscn
```

Expected:
```
[ext_resource type="PackedScene" uid="uid://d3w5o2bii2h1" path="res://dialog/ui/playermenu/player_menu.tscn" id="6_pmenu"]
[node name="PlayerMenu" parent="." instance=ExtResource("6_pmenu")]
```

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/gui/hud.tscn assault/scenes/gui/hud.gd
git commit -m "feat: wire PlayerMenu into assault HUD"
```

---

### Task 7: Wire PlayerMenu into open-space HUD

**Files:**
- Modify: `open_space/scenes/gui/hud.tscn`
- Modify: `open_space/scenes/gui/hud.gd`

The open-space player has no `WeaponState` or `RocketState`. `connect_states(null, null)` is passed so the menu opens/closes with Tab and pauses the game, but weapon-selection callbacks are no-ops (guarded by null checks in `player_menu.gd`).

- [ ] **Step 1: Rewrite `open_space/scenes/gui/hud.tscn`**

Current file has `load_steps=3`. After adding the PlayerMenu ext_resource it becomes 4. Replace the entire file with:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://open_space/scenes/gui/hud.gd" id="1_oshud"]
[ext_resource type="PackedScene" path="res://assault/scenes/gui/health_shield_bar.tscn" id="2_hsbar"]
[ext_resource type="PackedScene" uid="uid://d3w5o2bii2h1" path="res://dialog/ui/playermenu/player_menu.tscn" id="3_pmenu"]

[node name="OpenSpaceHUD" type="CanvasLayer"]
script = ExtResource("1_oshud")

[node name="HealthShieldBar" parent="." instance=ExtResource("2_hsbar")]
offset_left = 8.0
offset_top = 8.0

[node name="PlayerMenu" parent="." instance=ExtResource("3_pmenu")]
```

- [ ] **Step 2: Rewrite `open_space/scenes/gui/hud.gd`**

```gdscript
# open_space/scenes/gui/hud.gd
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var player_menu: PlayerMenu = $PlayerMenu

func _ready() -> void:
	## Wait one frame for the player to be ready.
	await get_tree().process_frame
	if not is_inside_tree():
		player_menu.connect_states(null, null)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		player_menu.connect_states(null, null)
		return
	var p := players[0]
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)
	## Open-space player has no WeaponState or RocketState.
	## Menu opens/closes with Tab but weapon selection is a no-op.
	player_menu.connect_states(null, null)
```

- [ ] **Step 3: Verify the PlayerMenu node was added**

```bash
grep "PlayerMenu" open_space/scenes/gui/hud.tscn
```

Expected:
```
[ext_resource type="PackedScene" uid="uid://d3w5o2bii2h1" path="res://dialog/ui/playermenu/player_menu.tscn" id="3_pmenu"]
[node name="PlayerMenu" parent="." instance=ExtResource("3_pmenu")]
```

- [ ] **Step 4: Commit**

```bash
git add open_space/scenes/gui/hud.tscn open_space/scenes/gui/hud.gd
git commit -m "feat: wire PlayerMenu into open-space HUD"
```
