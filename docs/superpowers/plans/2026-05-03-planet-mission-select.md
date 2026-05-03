# Planet Mission-Select Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-target planet launch with a 2-mission select menu (Assault + Infiltration) featuring W/S navigation, star ratings, locked/completed status, a circular arc progress fill around the planet on hold-E, and correct first-time-vs-replay scene routing that persists across game sessions.

**Architecture:** `MissionState` autoload (singleton) persists completion and star data to `user://mission_state.cfg` via `ConfigFile`. `MissionConfigResource` is a typed `Resource` holding per-mission metadata. `Planet` is fully rewritten to manage the menu in `_process` and draw the arc via `_draw()`. Missions are injected at runtime from `sector_hub.gd` so the planet scene stays data-agnostic. `level_1_waves.gd` reads `MissionState` to route first-timers to Infiltration and replayers back to the Hub.

**Tech Stack:** Godot 4.4, GDScript with static types, `ConfigFile` (built-in), `draw_arc()` canvas API, Godot autoloads

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `open_space/scenes/entities/interactables/mission_config_resource.gd` | Data class: name, scene_path, mission_id, required_mission |
| Create | `global/autoloads/mission_state.gd` | Singleton: load/save/query mission completion + stars |
| Modify | `project.godot` | Register MissionState autoload |
| Rewrite | `open_space/scenes/entities/interactables/planet.gd` | Menu logic, hold-E arc, W/S nav, locked check, launch |
| Modify | `open_space/scenes/entities/interactables/planet.tscn` | Remove ProgressBar + PromptLabel; add MissionLabel |
| Modify | `open_space/scenes/levels/sector_hub.gd` | Build and inject missions array into Planet node |
| Modify | `assault/scenes/levels/level_1_waves.gd` | Mark assault complete; route first-time → Infiltration, replay → Hub |

---

## Task 1: MissionConfigResource data class

**Files:**
- Create: `open_space/scenes/entities/interactables/mission_config_resource.gd`

- [ ] **Step 1: Create the resource script**

```gdscript
# open_space/scenes/entities/interactables/mission_config_resource.gd
class_name MissionConfigResource
extends Resource

## Per-mission configuration injected into Planet at runtime.

@export var display_name: String = "Mission"
## Full res:// path to the target scene, e.g. "res://assault/scenes/levels/level_1.tscn"
@export var scene_path: String = ""
## Unique string key used to read/write progress in MissionState.
@export var mission_id: String = ""
## If non-empty, this mission is locked until the named mission_id is complete.
@export var required_mission: String = ""
```

- [ ] **Step 2: Verify parse (no errors in Godot output)**

Open the Godot editor (or check the Output panel after it auto-reloads). The file should parse with zero errors. If there is a `class_name` conflict the editor will show it in the script errors panel.

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/entities/interactables/mission_config_resource.gd
git commit -m "feat: add MissionConfigResource data class"
```

---

## Task 2: MissionState autoload + registration

**Files:**
- Create: `global/autoloads/mission_state.gd`
- Modify: `project.godot`

- [ ] **Step 1: Write the autoload script**

```gdscript
# global/autoloads/mission_state.gd
extends Node

## Persistent mission progress singleton.
## Access anywhere: MissionState.complete("assault", 1)
##                  MissionState.is_complete("assault")
##                  MissionState.get_stars("assault")

const SAVE_PATH := "user://mission_state.cfg"

## Internal cache: { mission_id: { "completed": bool, "stars": int } }
var _data: Dictionary = {}

func _ready() -> void:
	_load()

## Mark a mission as complete and record its star count (1–3).
## If the mission was already complete with MORE stars, keeps the higher count.
func complete(mission_id: String, stars: int = 1) -> void:
	var entry: Dictionary = _data.get(mission_id, {})
	entry["completed"] = true
	entry["stars"] = max(entry.get("stars", 0), clampi(stars, 1, 3))
	_data[mission_id] = entry
	_save()

## Returns true if the mission has been beaten at least once.
func is_complete(mission_id: String) -> bool:
	return _data.get(mission_id, {}).get("completed", false)

## Returns 0 if the mission has never been completed.
func get_stars(mission_id: String) -> int:
	return _data.get(mission_id, {}).get("stars", 0)

func _save() -> void:
	var cfg := ConfigFile.new()
	for mission_id: String in _data:
		var entry: Dictionary = _data[mission_id]
		cfg.set_value(mission_id, "completed", entry.get("completed", false))
		cfg.set_value(mission_id, "stars", entry.get("stars", 0))
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no save file yet — fresh start
	for mission_id: String in cfg.get_sections():
		_data[mission_id] = {
			"completed": cfg.get_value(mission_id, "completed", false),
			"stars": cfg.get_value(mission_id, "stars", 0),
		}
```

- [ ] **Step 2: Register in project.godot**

Open `project.godot` and find the `[autoload]` section. If it does not exist, add it. Add this line inside the section:

```ini
[autoload]

MissionState="*res://global/autoloads/mission_state.gd"
```

The `*` prefix tells Godot to instantiate it as a Node (required for autoloads that extend Node).

- [ ] **Step 3: Verify the autoload loads**

Run the project. In the Output panel you should see no errors related to MissionState. Open the Remote scene tree (Debug → Remote Scene Tree while playing) and confirm `MissionState` appears as a child of root.

- [ ] **Step 4: Commit**

```bash
git add global/autoloads/mission_state.gd project.godot
git commit -m "feat: add MissionState autoload with ConfigFile persistence"
```

---

## Task 3: Rewrite planet.gd

**Files:**
- Rewrite: `open_space/scenes/entities/interactables/planet.gd`

The planet must:
- Show a 2-line menu with cursor (`> `) when the player is in range
- Allow W/S (`move_up`/`move_down`) to change selection, resetting hold progress each time
- Draw a thin grey background arc + a coloured fill arc via `_draw()` on the same radius as the planet circle
- Fill the arc while E (`interact`) is held; reset if released before full
- On completion, call `get_tree().change_scene_to_file(mission.scene_path)`
- Not accept input or show arc when player is out of range

- [ ] **Step 1: Write the rewritten planet.gd**

```gdscript
# open_space/scenes/entities/interactables/planet.gd
class_name Planet
extends Area2D

## Mission-select hub planet. The missions array is populated at runtime
## by the parent level (sector_hub.gd). When the player enters the Area2D
## overlap and holds [E] on an unlocked mission, the arc fills and the
## scene transitions to that mission's scene_path.

@export var arc_radius: float = 100.0
@export var hold_duration_sec: float = 1.2

## Injected by sector_hub.gd after the scene tree is ready.
var missions: Array[MissionConfigResource] = []

@onready var mission_label: Label = $MissionLabel

var _player_in_range: bool = false
var _selected_index: int = 0
var _hold_time: float = 0.0
var _launching: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	mission_label.visible = false

func _process(delta: float) -> void:
	if _launching or missions.is_empty():
		return

	if not _player_in_range:
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()
		return

	_handle_navigation()
	_handle_hold(delta)

func _handle_navigation() -> void:
	var changed := false
	if Input.is_action_just_pressed("move_up"):
		_selected_index = wrapi(_selected_index - 1, 0, missions.size())
		changed = true
	if Input.is_action_just_pressed("move_down"):
		_selected_index = wrapi(_selected_index + 1, 0, missions.size())
		changed = true
	if changed:
		_hold_time = 0.0
		_refresh_display()
		queue_redraw()

func _handle_hold(delta: float) -> void:
	var mission: MissionConfigResource = missions[_selected_index]
	if _is_locked(mission):
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()
		return

	if Input.is_action_pressed("interact"):
		_hold_time = min(_hold_time + delta, hold_duration_sec)
		queue_redraw()
		if _hold_time >= hold_duration_sec:
			_start_launch(mission)
	else:
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()

func _draw() -> void:
	if not _player_in_range or missions.is_empty():
		return

	var mission: MissionConfigResource = missions[_selected_index]
	var locked := _is_locked(mission)

	# Background ring (full circle)
	draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, -PI / 2.0 + TAU,
			64, Color(1.0, 1.0, 1.0, 0.18), 4.0, true)

	# Fill arc clockwise from top
	if _hold_time > 0.0 and not locked:
		var progress := _hold_time / hold_duration_sec
		var end_angle := -PI / 2.0 + TAU * progress
		draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, end_angle,
				64, Color(0.2, 0.85, 1.0, 0.95), 6.0, true)

func _is_locked(mission: MissionConfigResource) -> bool:
	if mission.required_mission.is_empty():
		return false
	return not MissionState.is_complete(mission.required_mission)

func _refresh_display() -> void:
	if missions.is_empty():
		mission_label.text = ""
		return

	var lines: PackedStringArray = []
	for i: int in missions.size():
		var m: MissionConfigResource = missions[i]
		var prefix := "> " if i == _selected_index else "  "
		var stars := _stars_text(MissionState.get_stars(m.mission_id))
		var status := ""
		if _is_locked(m):
			status = "  [LOCKED]"
		elif MissionState.is_complete(m.mission_id):
			status = "  [DONE]"
		lines.append("%s%s  %s%s" % [prefix, m.display_name, stars, status])

	var selected: MissionConfigResource = missions[_selected_index]
	if _is_locked(selected):
		lines.append("   (Complete Assault first)")
	else:
		lines.append("   Hold [E] to launch")

	mission_label.text = "\n".join(lines)

func _stars_text(stars: int) -> String:
	return "★".repeat(stars) + "☆".repeat(3 - stars)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_selected_index = 0
	_hold_time = 0.0
	mission_label.visible = true
	_refresh_display()
	queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	mission_label.visible = false
	_hold_time = 0.0
	_launching = false
	queue_redraw()

func _start_launch(mission: MissionConfigResource) -> void:
	_launching = true
	get_tree().change_scene_to_file(mission.scene_path)
```

- [ ] **Step 2: Verify parse**

Save the file. Godot should show no parse errors. The planet.tscn is still referencing the old nodes (ProgressBar, PromptLabel) so `@onready` errors will appear until Task 4 updates the scene — that is expected at this point.

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/entities/interactables/planet.gd
git commit -m "feat: rewrite Planet with mission-select menu and arc progress draw"
```

---

## Task 4: Update planet.tscn

**Files:**
- Modify: `open_space/scenes/entities/interactables/planet.tscn`

Remove `ProgressBar` and `PromptLabel`. Add a `MissionLabel` Label node positioned to the right of the planet with enough room for 4 lines of text.

- [ ] **Step 1: Rewrite planet.tscn**

Replace the entire file with this content:

```
[gd_scene load_steps=4 format=3 uid="uid://cu7qlu0h6p1fd"]

[ext_resource type="Script" uid="uid://ca007hf3gsvgc" path="res://open_space/scenes/entities/interactables/planet.gd" id="1_planet"]
[ext_resource type="Texture2D" uid="uid://4hr4a6ex43e7" path="res://open_space/assets/sprites/planet_stub.png" id="2_planet_tex"]

[sub_resource type="CircleShape2D" id="CircleShape2D_planet"]
radius = 80.0

[node name="Planet" type="Area2D"]
collision_layer = 2
collision_mask = 4
script = ExtResource("1_planet")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
position = Vector2(0, 4.76837e-07)
scale = Vector2(0.177734, 0.177734)
texture = ExtResource("2_planet_tex")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(0, -1)
shape = SubResource("CircleShape2D_planet")

[node name="MissionLabel" type="Label" parent="."]
offset_left = 110.0
offset_top = -60.0
offset_right = 310.0
offset_bottom = 80.0
```

Key points:
- `uid` values are preserved exactly so existing scene references (`sector_hub.tscn`) remain valid
- `ProgressBar` and `PromptLabel` are gone
- `MissionLabel` is 200×140 px, positioned 110 px to the right of planet centre

- [ ] **Step 2: Run the game and verify**

Launch the game. Fly the ship into the planet's Area2D. You should see:
- The MissionLabel appears (empty text for now — missions array is still empty until Task 5 wires it)
- No errors about missing ProgressBar or PromptLabel nodes
- The arc ring appears around the planet (even if no missions yet, the `_draw()` guard `if missions.is_empty()` keeps it hidden)

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/entities/interactables/planet.tscn
git commit -m "feat: update planet.tscn — replace ProgressBar/PromptLabel with MissionLabel"
```

---

## Task 5: Wire missions from sector_hub.gd

**Files:**
- Modify: `open_space/scenes/levels/sector_hub.gd`

Inject the two `MissionConfigResource` objects into the Planet node after the scene tree is ready. This keeps all mission data in one place and out of the .tscn format.

- [ ] **Step 1: Update sector_hub.gd**

```gdscript
# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns patrol drones and wires mission configs into
## the Planet node so it knows which scenes to launch.

const PATROL_DRONE := preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")

@export var drone_count: int = 3
@export var spawn_radius: float = 600.0

@onready var enemy_container: Node2D = $EnemyContainer
@onready var planet: Planet = $Planet

func _ready() -> void:
	_spawn_initial_drones()
	_configure_planet()

func _spawn_initial_drones() -> void:
	for i: int in drone_count:
		var drone := PATROL_DRONE.instantiate()
		var angle := randf() * TAU
		var distance := randf_range(spawn_radius * 0.5, spawn_radius)
		drone.global_position = Vector2(cos(angle), sin(angle)) * distance
		drone.initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		enemy_container.add_child(drone)

func _configure_planet() -> void:
	var assault := MissionConfigResource.new()
	assault.display_name = "Assault"
	assault.scene_path = "res://assault/scenes/levels/level_1.tscn"
	assault.mission_id = "assault"
	assault.required_mission = ""  # always available

	var infiltration := MissionConfigResource.new()
	infiltration.display_name = "Infiltration"
	infiltration.scene_path = "res://infiltration_mission/scenes/levels/TestIsometricScene.tscn"
	infiltration.mission_id = "infiltration"
	infiltration.required_mission = "assault"  # locked until assault is done

	planet.missions = [assault, infiltration]
```

- [ ] **Step 2: Run and verify the menu**

Launch the game and fly into the planet. Verify:
1. The MissionLabel shows `> Assault  ☆☆☆` on the first line and `  Infiltration  ☆☆☆  [LOCKED]` on the second
2. `W` or `S` moves the `>` cursor between entries (cursor wraps from bottom back to top)
3. With Assault selected, the arc ring fills while E is held and resets when released
4. With Infiltration selected (which is locked), holding E has no effect and the label shows "(Complete Assault first)"
5. The arc ring appears while the player is in range and vanishes when they fly away

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/levels/sector_hub.gd
git commit -m "feat: inject Assault + Infiltration mission configs into Planet from sector_hub"
```

---

## Task 6: level_1_waves.gd — mission completion routing

**Files:**
- Modify: `assault/scenes/levels/level_1_waves.gd`

When Level 1 finishes:
- Record `assault` as complete (1 star) in `MissionState`
- **First playthrough** (assault was not yet complete before this run): go to Infiltration
- **Replay** (assault was already marked complete): return to Hub

- [ ] **Step 1: Update `_on_waves_complete` in level_1_waves.gd**

Replace the existing `_on_waves_complete` function (lines 134–138) with the following. Leave everything else in the file untouched.

```gdscript
func _on_waves_complete() -> void:
	print("[LEVEL] All waves triggered — checking mission state")
	var first_time := not MissionState.is_complete("assault")
	MissionState.complete("assault", 1)

	await get_tree().create_timer(3.0).timeout

	if first_time:
		print("[LEVEL] First clear — proceeding to Infiltration mission")
		get_tree().change_scene_to_file(
				"res://infiltration_mission/scenes/levels/TestIsometricScene.tscn")
	else:
		print("[LEVEL] Replay complete — returning to hub")
		get_tree().change_scene_to_file(
				"res://open_space/scenes/levels/sector_hub.tscn")
```

- [ ] **Step 2: Verify first-time flow**

If `user://mission_state.cfg` exists from testing, delete it first (find it under Godot's user data folder: `%APPDATA%\Godot\app_userdata\<project_name>\` on Windows). Then:

1. Launch the game
2. Enter the planet, select Assault, hold E until it launches
3. Play through Level 1 (comment out waves if needed for a quick test)
4. After waves complete, confirm the game transitions to `TestIsometricScene` (Infiltration)

- [ ] **Step 3: Verify replay flow**

Without deleting the save file (assault is now complete):

1. Launch the game and enter the hub
2. The Infiltration mission should now be unlocked in the planet menu (no `[LOCKED]` status)
3. Select Assault and launch it again
4. After Level 1 ends, confirm the game returns to `sector_hub.tscn`
5. Back in the hub, Infiltration shows `☆☆☆` (no stars yet — it was never completed through Level 1 this time, only visited once via auto-transition)

- [ ] **Step 4: Verify star display for completed mission**

In the hub with assault complete:
- The planet menu should show `  Assault  ★☆☆  [DONE]` (1 star, done)
- Infiltration locked until visited is the Infiltration mission `☆☆☆` (0 stars — never completed directly via hub)

- [ ] **Step 5: Commit**

```bash
git add assault/scenes/levels/level_1_waves.gd
git commit -m "feat: record assault completion and route first-time to Infiltration, replay to Hub"
```

---

## Self-Review Checklist

### Spec Coverage

| Requirement | Task that implements it |
|-------------|------------------------|
| One planet, no beacons | Task 5 (planet only, no extra nodes) |
| W/S menu navigation | Task 3 (`_handle_navigation`) |
| Mission name, stars, done/locked status | Task 3 (`_refresh_display`, `_stars_text`) |
| Circular arc around planet | Task 3 (`_draw` with `draw_arc`) |
| Hold E fills arc → launches | Task 3 (`_handle_hold`, `_start_launch`) |
| First playthrough: Hub → Assault → Infiltration | Task 6 (`first_time` branch) |
| Replay Assault → returns to Hub | Task 6 (`else` branch) |
| Can select Infiltration directly after unlock | Tasks 5+6 (`required_mission = "assault"`, `is_complete` check) |
| Progress persists across game exits | Task 2 (ConfigFile save on `complete()`) |
| Level 2 left untouched | ✅ No changes to level_2_waves.gd |

### Type Consistency

- `MissionConfigResource` fields (`display_name`, `scene_path`, `mission_id`, `required_mission`) — used identically in Tasks 1, 3, and 5
- `MissionState.complete(id, stars)`, `is_complete(id)`, `get_stars(id)` — signature matches across Tasks 2, 3, and 6
- `planet.missions: Array[MissionConfigResource]` — set in Task 3, written in Task 5

### No Placeholders

All code blocks are complete. All `git add` paths match the files defined at the top.
