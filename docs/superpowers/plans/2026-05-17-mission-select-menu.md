# Mission Select Menu — Data-Driven Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully inspector-configurable mission select system where planets, space stations, and giant ships are all the same generic `MissionTrigger` node driven by a `.tres` Resource — swap the resource, swap everything (sprite, name, background, missions, point positions, descriptions).

**Architecture:** Two Resources drive the system — `PlanetConfigResource` (one per trigger object: holds sprite, name, background, missions list, point positions) and `MissionConfigResource` (one per mission: holds scene path, type icon, preview image, description). A generic `MissionTrigger` Area2D reads from its assigned `PlanetConfigResource` and applies `@tool` so the sprite updates live in the editor when you change the resource. The `MissionSelectMenu` CanvasLayer renders everything from the resource data — planet map image with draggable point markers, scrollable mission list, info panel. No code changes are needed to add a new planet or mission — create a `.tres`, fill in the Inspector, drag it onto the node.

**Tech Stack:** Godot 4 GDScript, `@tool` scripts, `@export` Resource arrays, CanvasLayer (process_mode=Always for pause-safe input), `ConfigFile`-backed MissionState autoload.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `global/resources/mission_config_resource.gd` | Add `description`, keep `mission_type` + `mission_image` |
| **Create** | `global/resources/planet_config_resource.gd` | Holds ALL data for one trigger: name, class, threat, background, sprite, missions[], point_positions[] |
| **Create** | `global/resources/planet_configs/edelia.tres` | Edelia planet data (created in editor) |
| **Create** | `open_space/scenes/gui/mission_list_item.gd` | Single row: background sprite + type icon + name + stars |
| **Create** | `open_space/scenes/gui/mission_list_item.tscn` | Scene for one list row |
| **Create** | `open_space/scenes/gui/mission_select_menu.gd` | Menu logic: open/close, W/S/Space, planet map + points, signals |
| **Create** | `open_space/scenes/gui/mission_select_menu.tscn` | CanvasLayer — background, overlay, list, planet map, points, info |
| **Rewrite** | `open_space/scenes/entities/interactables/planet.gd` | Generic `MissionTrigger`: @tool, dwell arc, opens menu |
| Modify | `open_space/scenes/entities/interactables/planet.tscn` | Remove MissionLabel |
| Modify | `open_space/scenes/levels/sector_hub.gd` | Export `PlanetConfigResource`, assign to trigger — no more inline mission building |

---

## How to add a new planet / station / ship (after implementation)

1. Right-click in `global/resources/planet_configs/` → New Resource → `PlanetConfigResource`
2. Fill in Inspector: name, class, threat level, background texture, sprite texture, missions array, point positions
3. Place a `MissionTrigger` node in the level scene (or reuse an existing one)
4. Drag the `.tres` onto its `Config` export — sprite updates live in the editor
5. Done. Zero code changes.

---

### Task 1: Update MissionConfigResource — add description

**Files:**
- Modify: `global/resources/mission_config_resource.gd`

- [ ] **Step 1: Add `description` and `mission_type` fields**

Replace the full file with:

```gdscript
## global/resources/mission_config_resource.gd
class_name MissionConfigResource
extends Resource

## Per-mission data. Create one .tres per mission, add to PlanetConfigResource.missions[].

## Displayed in the mission list and info panel.
@export var display_name: String = ""
## Full res:// path to the scene to load when this mission is launched.
@export var scene_path: String = ""
## Unique key used by MissionState to track completion.
@export var mission_id: String = ""
## If non-empty, this mission is locked until the named mission_id is completed.
@export var required_mission: String = ""
## Determines the icon shown in the list row. "assault" | "infiltration"
@export_enum("assault", "infiltration") var mission_type: String = "assault"
## Texture shown in the preview image panel when this row is selected in the menu.
@export var mission_image: Texture2D = null
## One- or two-sentence description shown in the info panel when this mission is selected.
@export_multiline var description: String = ""
```

- [ ] **Step 2: Commit**

```
git add global/resources/mission_config_resource.gd
git commit -m "feat: add description and mission_type enum to MissionConfigResource"
```

---

### Task 2: Create PlanetConfigResource

**Files:**
- Create: `global/resources/planet_config_resource.gd`

This is the single source of truth for one mission trigger. Create one `.tres` per planet/station/ship in the editor.

- [ ] **Step 1: Write the resource script**

Create `global/resources/planet_config_resource.gd`:

```gdscript
## global/resources/planet_config_resource.gd
## All inspector-configurable data for one mission trigger (planet, space station, ship...).
## Create one .tres file per trigger object. Assign it to a MissionTrigger node.
## Change anything here and the in-game menu reflects it with zero code changes.
class_name PlanetConfigResource
extends Resource

## ── Identity (shown in the menu header) ───────────────────────────────────
@export var display_name: String = "UNKNOWN"
## Subtitle line, e.g. "TERRESTRIAL", "ORBITAL STATION", "DREADNOUGHT"
@export var planet_class: String = "TERRESTRIAL"
## e.g. "LOW", "MEDIUM", "HIGH", "EXTREME"
@export var threat_level: String = "MEDIUM"

## ── Visuals ───────────────────────────────────────────────────────────────
## Background rendered behind the overlay in the mission select menu.
@export var background_texture: Texture2D = null
## Texture used for two things:
##   1. The Sprite2D shown on the MissionTrigger node in the open-space world.
##   2. The "planet map" image rendered in the right panel of the menu.
## Swap this to turn a planet into a space station or ship.
@export var sprite_texture: Texture2D = null

## ── Missions ──────────────────────────────────────────────────────────────
## The ordered list of missions shown in the menu. Drag MissionConfigResource
## .tres files here. The first entry is always index 0 in the list.
@export var missions: Array[MissionConfigResource] = []

## ── Point positions ───────────────────────────────────────────────────────
## Pixel offsets from the planet map image centre for the mission point icons.
## Index 0 maps to missions[0], index 1 maps to missions[1], etc.
## Edit these in the Inspector to drag points around the planet map visually.
## Tip: open the MissionSelectMenu scene in @tool mode and tweak while watching
## the 2D preview to align points with planet surface features.
@export var point_positions: Array[Vector2] = [
	Vector2(-60.0, -30.0),
	Vector2(40.0, 50.0),
]
```

- [ ] **Step 2: Commit**

```
git add global/resources/planet_config_resource.gd
git commit -m "feat: add PlanetConfigResource — single .tres drives all mission trigger data"
```

---

### Task 3: Create the Edelia planet config .tres in the editor

**Files:**
- Create: `global/resources/planet_configs/edelia.tres`

This step is done entirely in the Godot editor with no code.

- [ ] **Step 1: Create the directory**

In the FileSystem panel, right-click `global/resources/` → Create Folder → name it `planet_configs`.

- [ ] **Step 2: Create the resource file**

Right-click `global/resources/planet_configs/` → New Resource → search for `PlanetConfigResource` → Create → save as `edelia.tres`.

- [ ] **Step 3: Fill in the Inspector**

With `edelia.tres` selected, set these fields:

| Field | Value |
|-------|-------|
| Display Name | `EDELIA` |
| Planet Class | `TERRESTRIAL` |
| Threat Level | `MEDIUM` |
| Background Texture | `res://assault/assets/sprites/ui/menu_mission_select_background_1.png` |
| Sprite Texture | *(drag the existing planet_stub.png or any planet art)* |
| Point Positions [0] | `Vector2(-60, -30)` |
| Point Positions [1] | `Vector2(40, 50)` |

- [ ] **Step 4: Create two MissionConfigResource .tres files**

Right-click `global/resources/planet_configs/` → New Resource → `MissionConfigResource` → save as `mission_assault.tres`.

Fill in:

| Field | Value |
|-------|-------|
| Display Name | `Assault` |
| Scene Path | `res://assault/scenes/levels/level_1.tscn` |
| Mission Id | `assault` |
| Required Mission | *(empty)* |
| Mission Type | `assault` |
| Mission Image | `res://assault/assets/sprites/ui/menu_mission_select_mission_image_1_1.png` |
| Description | `Destroy the enemy command unit and secure the outpost.` |

Repeat for `mission_infiltration.tres`:

| Field | Value |
|-------|-------|
| Display Name | `Infiltration` |
| Scene Path | `res://infiltration/scenes/levels/TestIsometricScene.tscn` |
| Mission Id | `infiltration` |
| Required Mission | `assault` |
| Mission Type | `infiltration` |
| Mission Image | `res://assault/assets/sprites/ui/menu_mission_select_mission_image_1_6.png` |
| Description | `Infiltrate the enemy base undetected and extract the data core.` |

- [ ] **Step 5: Assign the missions to edelia.tres**

Open `edelia.tres` → Missions array → Add Element × 2 → drag `mission_assault.tres` into [0] and `mission_infiltration.tres` into [1].

- [ ] **Step 6: Commit**

```
git add global/resources/planet_configs/
git commit -m "feat: add edelia.tres planet config with assault + infiltration missions"
```

---

### Task 4: Create MissionListItem script and scene

**Files:**
- Create: `open_space/scenes/gui/mission_list_item.gd`
- Create: `open_space/scenes/gui/mission_list_item.tscn`

- [ ] **Step 1: Write the script**

Create `open_space/scenes/gui/mission_list_item.gd`:

```gdscript
# open_space/scenes/gui/mission_list_item.gd
## One row in the mission list.
## Call configure() once after instantiating, then set_hovered() each frame the cursor moves.
class_name MissionListItem
extends Node2D

const _ICON_ASSAULT      := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_assault.png")
const _ICON_INFILTRATION := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_land.png")
const _ICON_UNKNOWN      := preload("res://assault/assets/sprites/ui/menu_mission_select_list_item_icon_unknown.png")

const _COLOR_NORMAL  := Color(1.0, 1.0, 1.0, 0.65)
const _COLOR_HOVERED := Color(1.0, 1.0, 1.0, 1.0)

@onready var _bg:    Sprite2D = $Background
@onready var _icon:  Sprite2D = $Icon
@onready var _label: Label    = $NameLabel
@onready var _stars: Label    = $StarsLabel  ## "★★☆" completion stars

func configure(mission: MissionConfigResource, locked: bool) -> void:
	_label.text = mission.display_name

	if locked:
		_icon.texture = _ICON_UNKNOWN
		_label.text = "??"
	elif mission.mission_type == "infiltration":
		_icon.texture = _ICON_INFILTRATION
	else:
		_icon.texture = _ICON_ASSAULT

	var stars: int = MissionState.get_stars(mission.mission_id)
	_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)

	modulate = _COLOR_NORMAL

func set_hovered(hovered: bool) -> void:
	modulate = _COLOR_HOVERED if hovered else _COLOR_NORMAL
```

- [ ] **Step 2: Build the scene in the Godot editor**

Create a new scene. Root: **Node2D**, rename `MissionListItem`, attach the script above.

Add these child nodes:

| Node | Name | Key settings |
|------|------|-------------|
| `Sprite2D` | `Background` | texture = `menu_mission_select_list_item.png`, centered = true |
| `Sprite2D` | `Icon` | centered = true, position ≈ `Vector2(-85, 0)` |
| `Label` | `NameLabel` | position ≈ `Vector2(-55, -9)`, font size 11, color white |
| `Label` | `StarsLabel` | position ≈ `Vector2(55, -9)`, font size 11, color `Color(1, 0.85, 0.1)` (yellow) |

Save as `res://open_space/scenes/gui/mission_list_item.tscn`.

- [ ] **Step 3: Commit**

```
git add open_space/scenes/gui/mission_list_item.gd open_space/scenes/gui/mission_list_item.tscn
git commit -m "feat: add MissionListItem scene and script"
```

---

### Task 5: Create MissionSelectMenu script

**Files:**
- Create: `open_space/scenes/gui/mission_select_menu.gd`

- [ ] **Step 1: Write the script**

Create `open_space/scenes/gui/mission_select_menu.gd`:

```gdscript
# open_space/scenes/gui/mission_select_menu.gd
## Full-screen mission select overlay driven entirely by a PlanetConfigResource.
## Pauses the scene tree while open. Emits signals back to MissionTrigger.
class_name MissionSelectMenu
extends CanvasLayer

signal mission_confirmed(scene_path: String)
signal cancelled
## Fires whenever the cursor row changes so MissionTrigger can sync point highlights.
signal cursor_changed(index: int)

const _ITEM_SCENE    := preload("res://open_space/scenes/gui/mission_list_item.tscn")
const _POINT_TEXTURE := preload("res://assault/assets/sprites/ui/menu_mission_select_point.png")

## Vertical gap between consecutive list item centres (pixels in ListContainer space).
const _ROW_STRIDE: float = 44.0

const _POINT_NORMAL   := Color(1.0, 1.0, 1.0, 0.5)
const _POINT_SELECTED := Color(0.2, 0.85, 1.0, 1.0)

@onready var _background:      Sprite2D = $Background
@onready var _planet_map:      Sprite2D = $PlanetMap
@onready var _points_container: Node2D  = $PlanetMap/PointsContainer
@onready var _mission_preview: Sprite2D = $MissionImagePreview
@onready var _list_container:  Node2D   = $ListContainer
@onready var _name_label:      Label    = $Header/NameLabel
@onready var _class_label:     Label    = $Header/ClassLabel
@onready var _threat_label:    Label    = $Header/ThreatLabel
@onready var _desc_label:      Label    = $InfoPanel/DescLabel

var _config:  PlanetConfigResource       = null
var _items:   Array[MissionListItem]     = []
var _points:  Array[Sprite2D]            = []
var _cursor:  int = 0

## Entry point. Called by MissionTrigger once the node is in the tree.
func open(config: PlanetConfigResource) -> void:
	_config = config

	## ── Header ────────────────────────────────────────────────────────────
	_background.texture   = config.background_texture
	_planet_map.texture   = config.sprite_texture
	_name_label.text      = config.display_name
	_class_label.text     = "PLANET CLASS: " + config.planet_class
	_threat_label.text    = "THREAT LEVEL: " + config.threat_level

	## ── List items ────────────────────────────────────────────────────────
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()

	for i: int in config.missions.size():
		var m: MissionConfigResource = config.missions[i]
		var locked: bool = _is_locked(m)
		var item := _ITEM_SCENE.instantiate() as MissionListItem
		_list_container.add_child(item)
		item.position = Vector2(0.0, i * _ROW_STRIDE)
		item.configure(m, locked)
		_items.append(item)

	## ── Planet map points ─────────────────────────────────────────────────
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()

	for i: int in config.missions.size():
		var sp := Sprite2D.new()
		sp.texture = _POINT_TEXTURE
		sp.modulate = _POINT_NORMAL
		## Positions are defined in the .tres relative to the planet map centre.
		sp.position = config.point_positions[i] \
				if i < config.point_positions.size() else Vector2.ZERO
		_points_container.add_child(sp)
		_points.append(sp)

	_cursor = 0
	_refresh()
	visible = true
	get_tree().paused = true

func close() -> void:
	get_tree().paused = false
	visible = false
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
	_config = null

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_up"):
		_cursor = wrapi(_cursor - 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_cursor = wrapi(_cursor + 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_try_confirm()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	cursor_changed.emit(_cursor)

	for i: int in _items.size():
		_items[i].set_hovered(i == _cursor)

	for i: int in _points.size():
		_points[i].modulate = _POINT_SELECTED if i == _cursor else _POINT_NORMAL

	var m: MissionConfigResource = _config.missions[_cursor]
	_mission_preview.texture = m.mission_image
	_desc_label.text = m.description if not _is_locked(m) else "Complete the previous mission to unlock."

func _try_confirm() -> void:
	var m: MissionConfigResource = _config.missions[_cursor]
	if _is_locked(m):
		return
	close()
	mission_confirmed.emit(m.scene_path)

func _is_locked(m: MissionConfigResource) -> bool:
	return not m.required_mission.is_empty() \
			and not MissionState.is_complete(m.required_mission)
```

- [ ] **Step 2: Commit**

```
git add open_space/scenes/gui/mission_select_menu.gd
git commit -m "feat: add MissionSelectMenu script — fully driven by PlanetConfigResource"
```

---

### Task 6: Create MissionSelectMenu scene in the editor

**Files:**
- Create: `open_space/scenes/gui/mission_select_menu.tscn`

- [ ] **Step 1: Create root CanvasLayer**

New scene → root type **CanvasLayer** → rename `MissionSelectMenu` → attach `mission_select_menu.gd`.

Set on the root:
- `process_mode` = **Always**
- `layer` = 10
- `visible` = false

- [ ] **Step 2: Add nodes in this hierarchy**

```
MissionSelectMenu (CanvasLayer)
├── Background (Sprite2D)         ← full-screen background; no texture set here, applied at runtime
├── Overlay (Sprite2D)            ← texture = menu_mission_select_overlay.png; centered = true; position = screen centre
├── Header (Node2D)               ← positioned at top-left of the left panel in the overlay
│   ├── NameLabel (Label)         ← big title, e.g. "EDELIA"; font size 16, color white
│   ├── ClassLabel (Label)        ← subtitle, font size 9, muted white
│   └── ThreatLabel (Label)       ← threat line, font size 9, muted yellow
├── PlanetMap (Sprite2D)          ← right-panel planet image; no texture set here, applied at runtime
│   └── PointsContainer (Node2D) ← mission point sprites are spawned here at runtime
├── MissionImageFrame (Sprite2D)  ← texture = menu_mission_select_mission_image.png (frame border)
├── MissionImagePreview (Sprite2D)← no texture; sits behind MissionImageFrame (z_index = -1)
├── ListContainer (Node2D)        ← top of the list area; items are added as children at runtime
└── InfoPanel (Node2D)            ← bottom of the left panel
    └── DescLabel (Label)         ← multi-line, wraps, font size 9, color white
```

- [ ] **Step 3: Position everything to match the overlay art**

Open the tscn in the 2D editor. Set Background and Overlay to your game's centre (e.g. `Vector2(640, 360)` for 1280×720). Turn on visibility. Use the overlay art as a guide to position:
- `Header` — top-left corner of the left column inside the overlay
- `ListContainer` — below the header, inside the left column
- `PlanetMap` — the right half where the planet globe sits
- `MissionImageFrame` — bottom-left below the list
- `InfoPanel/DescLabel` — the info box at the bottom of the left column

> **Tip:** Temporarily assign textures to Background and Overlay in the Inspector while positioning, then remove them (they're set at runtime from the PlanetConfigResource).

- [ ] **Step 4: Save**

Save as `res://open_space/scenes/gui/mission_select_menu.tscn`.

- [ ] **Step 5: Commit**

```
git add open_space/scenes/gui/mission_select_menu.tscn
git commit -m "feat: add MissionSelectMenu scene layout"
```

---

### Task 7: Rewrite MissionTrigger (planet.gd) — generic @tool node

**Files:**
- Rewrite: `open_space/scenes/entities/interactables/planet.gd`

The script is now `@tool` so swapping `config` in the Inspector updates the sprite immediately in the editor.

- [ ] **Step 1: Write the new script**

Replace the entire content of `open_space/scenes/entities/interactables/planet.gd`:

```gdscript
# open_space/scenes/entities/interactables/planet.gd
## Generic mission trigger — works for planets, space stations, giant ships,
## or any Area2D in the open-space world.
##
## Assign a PlanetConfigResource to `config` in the Inspector.
## The sprite, menu background, missions list, and point positions all
## come from that resource — change the resource, change everything.
##
## @tool lets the sprite update live when you swap the resource in the editor.
@tool
class_name MissionTrigger
extends Area2D

## ── Inspector exports ─────────────────────────────────────────────────────
@export var config: PlanetConfigResource = null:
	set(value):
		config = value
		_apply_sprite()   ## live preview in editor

@export_category("Arc")
@export var arc_radius: float       = 80.0
@export var arc_bg_width: float     = 10.0
@export var arc_fill_width: float   = 10.0
@export var arc_bg_color: Color     = Color(1.0, 1.0, 1.0, 0.18)
@export var arc_fill_color: Color   = Color(0.2, 0.85, 1.0, 0.95)

@export_category("Interaction")
@export var dwell_duration_sec: float = 2.0

## ── Internal ──────────────────────────────────────────────────────────────
const _MENU_SCENE := preload("res://open_space/scenes/gui/mission_select_menu.tscn")

@onready var _sprite: Sprite2D = $Sprite2D

var _player_in_range: bool        = false
var _dwell_time: float            = 0.0
var _menu_open: bool              = false
var _menu: MissionSelectMenu      = null

func _ready() -> void:
	_apply_sprite()
	if Engine.is_editor_hint():
		return   ## skip runtime setup in editor
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## Apply config.sprite_texture to the child Sprite2D.
## Called both from the setter (editor live update) and _ready() (runtime).
func _apply_sprite() -> void:
	if not is_node_ready():
		return
	if _sprite and config and config.sprite_texture:
		_sprite.texture = config.sprite_texture

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or config == null or config.missions.is_empty() or _menu_open:
		return

	if not _player_in_range:
		if _dwell_time > 0.0:
			_dwell_time = 0.0
			queue_redraw()
		return

	_dwell_time = min(_dwell_time + delta, dwell_duration_sec)
	queue_redraw()

	if _dwell_time >= dwell_duration_sec:
		_open_menu()

func _draw() -> void:
	if Engine.is_editor_hint() or not _player_in_range \
			or config == null or config.missions.is_empty() or _menu_open:
		return

	## Background ring.
	draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, -PI / 2.0 + TAU,
			64, arc_bg_color, arc_bg_width, true)

	## Dwell fill arc — grows automatically.
	if _dwell_time > 0.0:
		var progress := _dwell_time / dwell_duration_sec
		draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0,
				-PI / 2.0 + TAU * progress,
				64, arc_fill_color, arc_fill_width, true)

func _open_menu() -> void:
	if _menu_open or config == null or config.missions.is_empty():
		return
	_menu_open = true
	_dwell_time = 0.0
	queue_redraw()

	_menu = _MENU_SCENE.instantiate() as MissionSelectMenu
	get_tree().root.add_child(_menu)
	_menu.mission_confirmed.connect(_on_mission_confirmed)
	_menu.cancelled.connect(_on_menu_cancelled)
	_menu.open(config)

func _close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.close()
		_menu.queue_free()
		_menu = null
	_menu_open = false
	_dwell_time = 0.0
	queue_redraw()

func _on_mission_confirmed(scene_path: String) -> void:
	_menu = null
	_menu_open = false
	get_tree().change_scene_to_file(scene_path)

func _on_menu_cancelled() -> void:
	_close_menu()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_dwell_time = 0.0
	queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_close_menu()
	queue_redraw()
```

- [ ] **Step 2: Commit**

```
git add open_space/scenes/entities/interactables/planet.gd
git commit -m "feat: rewrite planet as generic @tool MissionTrigger driven by PlanetConfigResource"
```

---

### Task 8: Update planet.tscn — remove MissionLabel

**Files:**
- Modify: `open_space/scenes/entities/interactables/planet.tscn`

- [ ] **Step 1: Open planet.tscn in the editor**

- [ ] **Step 2: Delete MissionLabel**

Select `MissionLabel` → Delete. It is replaced by the CanvasLayer menu.

- [ ] **Step 3: Assign edelia.tres to the Config property**

Select the root `Planet` node → Inspector → Config → drag `global/resources/planet_configs/edelia.tres` into the slot. The planet sprite should immediately update in the 2D viewport.

- [ ] **Step 4: Save**

- [ ] **Step 5: Commit**

```
git add open_space/scenes/entities/interactables/planet.tscn
git commit -m "chore: remove MissionLabel from planet.tscn, assign edelia.tres config"
```

---

### Task 9: Simplify sector_hub.gd — no more inline mission building

**Files:**
- Modify: `open_space/scenes/levels/sector_hub.gd`

`sector_hub.gd` no longer builds `MissionConfigResource` objects in code. The planet reads everything from the `.tres` file assigned in the Inspector. This file becomes much simpler.

- [ ] **Step 1: Replace sector_hub.gd**

```gdscript
# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns patrol drones.
## Planet mission data is now fully configured in the PlanetConfigResource .tres file
## assigned to the Planet node in the Inspector — no code changes needed per planet.

const PATROL_DRONE := preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")

@export var drone_count: int    = 3
@export var spawn_radius: float = 600.0

@onready var enemy_container: Node2D       = $EnemyContainer
@onready var planet:          MissionTrigger = $Planet

func _ready() -> void:
	_spawn_initial_drones()

func _spawn_initial_drones() -> void:
	for i: int in drone_count:
		var drone := PATROL_DRONE.instantiate()
		var angle    := randf() * TAU
		var distance := randf_range(spawn_radius * 0.5, spawn_radius)
		drone.global_position = Vector2(cos(angle), sin(angle)) * distance
		drone.initial_direction = Vector2(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		enemy_container.add_child(drone)
```

- [ ] **Step 2: Commit**

```
git add open_space/scenes/levels/sector_hub.gd
git commit -m "refactor: remove inline mission config from sector_hub — data lives in .tres files"
```

---

## Verification Checklist

- [ ] Open `planet.tscn` in editor → assign `edelia.tres` → planet sprite updates live (no play needed)
- [ ] Play open space → fly near planet → arc fills over 2 seconds automatically
- [ ] Arc resets if you fly away before it completes
- [ ] After dwell → mission menu appears full-screen, ship stops moving
- [ ] Header shows "EDELIA / PLANET CLASS: TERRESTRIAL / THREAT LEVEL: MEDIUM"
- [ ] Two list rows visible: Assault (assault icon) + Infiltration (locked/unknown icon if assault not done)
- [ ] W/S moves cursor, list items highlight, preview image changes, description updates
- [ ] Point icons on the planet map highlight in sync with the cursor
- [ ] Space on locked mission → nothing happens
- [ ] Space on unlocked mission → menu closes, scene loads
- [ ] Leaving planet range → menu closes, ship resumes

---

## Adding a second planet / space station (zero code)

1. Duplicate `global/resources/planet_configs/edelia.tres` → rename e.g. `orbital_station.tres`
2. Fill in new name, class, threat, background texture, sprite texture, missions, point positions
3. In your level scene, add a new `MissionTrigger` node (or duplicate the Planet node)
4. Assign `orbital_station.tres` to its `Config` export
5. Done — no code changes

## Tuning reference

| What to change | Where |
|---------------|-------|
| Dwell speed | `MissionTrigger` Inspector → `Dwell Duration Sec` |
| Arc size / color | `MissionTrigger` Inspector → Arc category |
| Mission point positions on map | `edelia.tres` → `Point Positions` array |
| List row spacing | `mission_select_menu.gd` → `_ROW_STRIDE` constant |
| Preview image | `mission_assault.tres` → `Mission Image` |
| Mission description | `mission_assault.tres` → `Description` |
| Planet header text | `edelia.tres` → `Display Name`, `Planet Class`, `Threat Level` |
