# Weapon Modes & Reflect Shield Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single primary-fire bullet with 5 selectable weapon modes (default / long_range / piercing / spread / auto_aim) plus a separate Reflect shield upgrade on `H`, with persistent unlocks via a new `UpgradeState` autoload.

**Architecture:** A `WeaponModeResource` describes each mode (range, fire interval, damage, heat, behavior enum). A renamed `WeaponState` (was `ShootingState`) holds the active mode id and dispatches to one of five `WeaponBehavior` strategy helpers per shot. Reflect is its own state node with a 0.15 s window + 1 s cooldown that flips overlapping enemy bullets back at their senders. Unlocks live in a `ConfigFile`-backed autoload (matching the existing `MissionState` pattern) under `user://upgrades.cfg`.

**Tech Stack:** Godot 4.6 GDScript, Resources, Area2D / RayCast2D, ConfigFile, autoloads. No external libraries. Tests are manual smoke tests in the editor (no GUT/gdUnit installed).

**Spec:** [`docs/superpowers/specs/2026-05-05-weapon-modes-design.md`](../specs/2026-05-05-weapon-modes-design.md)

**Branch policy:** Per user memory, work on `main` directly. Each task ends with a commit on `main`.

---

## File Map

### Created
- `global/autoloads/upgrade_state.gd` — persistent unlock store
- `assault/scenes/player/weapons/weapon_mode.gd` — `WeaponModeResource` class
- `assault/scenes/player/weapons/modes/default.tres`
- `assault/scenes/player/weapons/modes/long_range.tres`
- `assault/scenes/player/weapons/modes/piercing.tres`
- `assault/scenes/player/weapons/modes/spread.tres`
- `assault/scenes/player/weapons/modes/auto_aim.tres`
- `assault/scenes/player/weapons/behaviors/weapon_behavior.gd` — base
- `assault/scenes/player/weapons/behaviors/straight_behavior.gd`
- `assault/scenes/player/weapons/behaviors/long_range_behavior.gd`
- `assault/scenes/player/weapons/behaviors/spread_behavior.gd`
- `assault/scenes/player/weapons/behaviors/homing_behavior.gd`
- `assault/scenes/player/weapons/behaviors/beam_behavior.gd`
- `assault/scenes/projectiles/primary_homing/primary_homing.gd`
- `assault/scenes/projectiles/primary_homing/primary_homing.tscn`
- `assault/scenes/projectiles/piercing_beam/piercing_beam.gd`
- `assault/scenes/projectiles/piercing_beam/piercing_beam.tscn`
- `assault/scenes/player/states/reflect_state.gd`
- `assault/scenes/player/states/reflect_area.gd`
- `assault/scenes/gui/weapon_chip.gd`
- `assault/scenes/gui/weapon_chip.tscn`
- `assault/scenes/player/debug_unlock_all.gd` (debug-only)

### Modified
- `project.godot` (input map: rebind 3 actions, add 2 new)
- `assault/scenes/projectiles/bullets/bullet.gd` (add `range_px`, `damage`)
- `assault/scenes/projectiles/bullets/bullet.tscn` (HitBox damage sourced from script at runtime)
- `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` (add `become_friendly()`)
- `assault/scenes/player/states/shooting_state.gd` → renamed to `weapon_state.gd` and refactored
- `assault/scenes/player/player_fighter.tscn` (replace ShootingState child node with WeaponState; add ReflectState; add WeaponChip to HUD)
- `assault/scenes/enemies/ram_ship/ram_ship.gd` (add `is_laser_blocking()`)
- `assault/scenes/gui/hud.tscn` (host weapon_chip)

### Deleted
- `assault/scenes/player/states/shooting_state.gd` (after rename to weapon_state.gd is committed)

---

## Manual Test Convention

Godot has no automated test rig in this project. Each task ends with a **Smoke** step listing exact in-editor verification. Treat the smoke step as the "test passes" gate. The user runs F5 (or the level scene) and confirms.

---

## Task 1: Input map — rebind 3 actions, add 2 new

**Files:**
- Modify: `project.godot` (input section)

- [ ] **Step 1: Rebind `interact` from E (69) to F (70)**

In `project.godot`, find the `interact` action and change `physical_keycode:69` → `physical_keycode:70`. The `unicode` should change from `101` to `102`.

```ini
interact={
"deadzone": 0.2,
"events": [Object(InputEventKey,...,physical_keycode:70,...,unicode:102,...)]
}
```

- [ ] **Step 2: Rebind `special_weapon` from X (88) to K (75)**

```ini
special_weapon={
"deadzone": 0.2,
"events": [Object(InputEventKey,...,physical_keycode:75,...,unicode:107,...)]
}
```

- [ ] **Step 3: Rebind `switch_weapon` from Z (90) to Q (81)**

```ini
switch_weapon={
"deadzone": 0.2,
"events": [Object(InputEventKey,...,physical_keycode:81,...,unicode:113,...)]
}
```

- [ ] **Step 4: Add `cycle_weapon` action on E (69)**

Append after `switch_weapon`:

```ini
cycle_weapon={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 5: Add `reflect` action on H (72)**

```ini
reflect={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":72,"key_label":0,"unicode":104,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 6: Smoke**

Open Godot. Project → Project Settings → Input Map. Confirm:
- `interact` = F
- `special_weapon` = K
- `switch_weapon` = Q
- `cycle_weapon` = E (new)
- `reflect` = H (new)

- [ ] **Step 7: Commit**

```bash
git add project.godot
git commit -m "feat(input): rebind interact/rocket keys + add cycle_weapon/reflect actions"
```

---

## Task 2: UpgradeState autoload

**Files:**
- Create: `global/autoloads/upgrade_state.gd`
- Modify: `project.godot` (autoload section)

- [ ] **Step 1: Write `upgrade_state.gd`**

```gdscript
# global/autoloads/upgrade_state.gd
extends Node

## Persistent unlock store for ship upgrades.
## Access anywhere: UpgradeState.unlock(&"piercing")
##                  UpgradeState.is_unlocked(&"reflect")
##                  UpgradeState.unlocked_ids()

const SAVE_PATH := "user://upgrades.cfg"
const SECTION := "upgrades"

const ALL_IDS: Array[StringName] = [
    &"default", &"long_range", &"piercing", &"spread", &"auto_aim", &"reflect"
]

signal unlocked_changed(id: StringName)

var _unlocked: Dictionary = {}  # { StringName: bool }

func _ready() -> void:
    _load()
    if _unlocked.is_empty():
        _unlocked[&"default"] = true
        _save()

func is_unlocked(id: StringName) -> bool:
    return _unlocked.get(id, false)

func unlock(id: StringName) -> void:
    if _unlocked.get(id, false):
        return
    _unlocked[id] = true
    _save()
    unlocked_changed.emit(id)

func unlocked_ids() -> Array[StringName]:
    var out: Array[StringName] = []
    for id in ALL_IDS:
        if _unlocked.get(id, false):
            out.append(id)
    return out

func unlock_all() -> void:
    for id in ALL_IDS:
        unlock(id)

func _save() -> void:
    var cfg := ConfigFile.new()
    for id: StringName in _unlocked.keys():
        cfg.set_value(SECTION, String(id), _unlocked[id])
    var err := cfg.save(SAVE_PATH)
    if err != OK:
        push_error("UpgradeState: failed to save '%s' (error %d)" % [SAVE_PATH, err])

func _load() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return
    if not cfg.has_section(SECTION):
        return
    for key: String in cfg.get_section_keys(SECTION):
        _unlocked[StringName(key)] = cfg.get_value(SECTION, key, false)
```

- [ ] **Step 2: Register autoload**

In `project.godot`, under `[autoload]`:

```ini
MissionState="*res://global/autoloads/mission_state.gd"
DialogPlayer="*res://global/autoload/dialog_player.gd"
UpgradeState="*res://global/autoloads/upgrade_state.gd"
```

- [ ] **Step 3: Smoke**

Run any scene (F5). In the Output panel, no errors. Open the Remote inspector → /root/UpgradeState — confirm `_unlocked` contains `&"default": true`.

Then open `%APPDATA%/Godot/app_userdata/<project>/upgrades.cfg` and confirm:
```ini
[upgrades]
default=true
```

- [ ] **Step 4: Commit**

```bash
git add global/autoloads/upgrade_state.gd project.godot
git commit -m "feat(upgrades): add UpgradeState autoload with ConfigFile persistence"
```

---

## Task 3: WeaponModeResource class

**Files:**
- Create: `assault/scenes/player/weapons/weapon_mode.gd`

- [ ] **Step 1: Write the resource class**

```gdscript
# assault/scenes/player/weapons/weapon_mode.gd
class_name WeaponModeResource
extends Resource

enum Behavior { STRAIGHT, LONG, BEAM, SPREAD, HOMING }

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D
@export var behavior: WeaponModeResource.Behavior = WeaponModeResource.Behavior.STRAIGHT

## Projectile scene used by STRAIGHT / LONG / SPREAD / HOMING. Ignored for BEAM.
@export var projectile_scene: PackedScene

## Per-shot range cap in pixels. 0 = no cap (off-screen exits).
@export var range_px: float = 0.0

## Seconds between shots. Ignored for BEAM (continuous while held).
@export_range(0.02, 2.0, 0.01) var fire_interval: float = 0.18

@export var damage: int = 10

## For STRAIGHT/LONG/SPREAD/HOMING: heat per shot. For BEAM: heat per second.
@export_range(0.0, 20.0, 0.1) var heat_per_shot: float = 1.0

## SPREAD only: number of pellets per shot.
@export_range(1, 12) var pellet_count: int = 1

## SPREAD only: total fan width in degrees.
@export_range(0.0, 180.0, 1.0) var pellet_spread_deg: float = 60.0

## HOMING only.
@export_range(0.0, 720.0, 5.0) var homing_turn_rate_deg_per_sec: float = 90.0
@export_range(0.1, 6.0, 0.05) var homing_lifetime_sec: float = 1.6

## BEAM only.
@export_range(0.0, 500.0, 1.0) var beam_dps: float = 30.0
```

- [ ] **Step 2: Smoke**

In Godot, FileSystem panel → right-click the new `weapon_mode.gd` → Reload. Then right-click any folder → New Resource → search "WeaponModeResource" — it must appear in the list.

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/player/weapons/weapon_mode.gd
git commit -m "feat(weapons): add WeaponModeResource data class"
```

---

## Task 4: Bullet — range_px + damage propagation

**Files:**
- Modify: `assault/scenes/projectiles/bullets/bullet.gd`

The current bullet has hard-coded HitBox damage in the .tscn (50). We add a `damage` script field that overrides the child HitBox's damage at runtime, and a `range_px` cap.

- [ ] **Step 1: Update `bullet.gd`**

Replace the file contents:

```gdscript
class_name Bullet
extends Area2D

signal expired

@export var speed: float = 500.0
## 0 = no cap (despawn only when off-screen).
@export var range_px: float = 0.0
## Damage applied via the child HitBox. Pushed in _ready().
@export var damage: int = 50

var _traveled: float = 0.0

func _ready() -> void:
    var hb := get_node_or_null("HitBox") as HitBox
    if hb:
        hb.damage = damage

func reset() -> void:
    rotation = 0.0
    _traveled = 0.0

func _physics_process(delta: float) -> void:
    var step := speed * delta
    var forward := Vector2.UP.rotated(rotation)
    global_position += forward * step
    if range_px > 0.0:
        _traveled += step
        if _traveled >= range_px:
            expired.emit()
            queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
    expired.emit()

func _on_hit_box_area_entered(_area: Area2D) -> void:
    expired.emit()
```

- [ ] **Step 2: Smoke**

Run Level 1 (F5 the project). Bullet visuals/firing must look identical to before this task (regression check). Default damage 50 still applied.

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/projectiles/bullets/bullet.gd
git commit -m "feat(bullet): add range_px cap and runtime damage push to HitBox"
```

---

## Task 5: Author 5 mode .tres files

**Files:**
- Create: `assault/scenes/player/weapons/modes/default.tres`
- Create: `assault/scenes/player/weapons/modes/long_range.tres`
- Create: `assault/scenes/player/weapons/modes/spread.tres`
- Create: `assault/scenes/player/weapons/modes/auto_aim.tres`
- Create: `assault/scenes/player/weapons/modes/piercing.tres`

- [ ] **Step 1: Look up the bullet UID**

Read `assault/scenes/projectiles/bullets/bullet.tscn` line 1. Note the `uid="uid://bvyhnlpuw5rcv"`.

- [ ] **Step 2: Look up `weapon_mode.gd` UID**

Read `assault/scenes/player/weapons/weapon_mode.gd.uid` (Godot generates after import). Use the value below as `<MODE_UID>` placeholder; **read the actual file** in the editor and substitute.

- [ ] **Step 3: Write `default.tres`**

```ini
[gd_resource type="Resource" script_class="WeaponModeResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/player/weapons/weapon_mode.gd" id="1_script"]

[sub_resource type="PackedScene" id="ps_bullet"]
[ext_resource type="PackedScene" uid="uid://bvyhnlpuw5rcv" path="res://assault/scenes/projectiles/bullets/bullet.tscn" id="2_bullet"]

[resource]
script = ExtResource("1_script")
id = &"default"
display_name = "Standard"
behavior = 0
projectile_scene = ExtResource("2_bullet")
range_px = 180.0
fire_interval = 0.18
damage = 50
heat_per_shot = 1.0
```

(Note: the cleanest .tres is authored by creating one in the editor — right-click → New Resource → WeaponModeResource → fill the Inspector → Save As `default.tres`. The text above is the expected resulting file. **Recommended:** use the editor to author all 5; don't hand-roll `.tres`.)

- [ ] **Step 4: Author the other four in the editor**

Right-click `assault/scenes/player/weapons/modes/` → New Resource → WeaponModeResource. Fill these values:

| File | id | display_name | behavior | projectile | range_px | fire_interval | damage | heat | extras |
|---|---|---|---|---|---|---|---|---|---|
| `long_range.tres` | `&"long_range"` | Long Range | LONG (1) | bullet.tscn | 0 | 0.45 | 75 | 2.0 | — |
| `spread.tres` | `&"spread"` | Spread | SPREAD (3) | bullet.tscn | 120 | 0.18 | 25 | 1.5 | pellet_count=5, pellet_spread_deg=60 |
| `auto_aim.tres` | `&"auto_aim"` | Auto-Aim | HOMING (4) | primary_homing.tscn (Task 10) | 0 | 0.26 | 50 | 1.5 | turn_rate=90, lifetime=1.6 |
| `piercing.tres` | `&"piercing"` | Piercing | BEAM (2) | (leave empty) | 0 | 0.0 | 0 | 3.0 | beam_dps=30 |

- [ ] **Step 5: Smoke**

Open each `.tres` in the Inspector. All fields render correctly. No "missing script" errors in Output.

- [ ] **Step 6: Commit**

```bash
git add assault/scenes/player/weapons/modes/
git commit -m "feat(weapons): author 5 weapon mode resources"
```

---

## Task 6: WeaponBehavior base + StraightBehavior

**Files:**
- Create: `assault/scenes/player/weapons/behaviors/weapon_behavior.gd`
- Create: `assault/scenes/player/weapons/behaviors/straight_behavior.gd`

- [ ] **Step 1: Write the base class**

```gdscript
# assault/scenes/player/weapons/behaviors/weapon_behavior.gd
class_name WeaponBehavior
extends RefCounted

## Strategy interface for firing a single shot. Subclasses override `fire()`.
## `state` is the WeaponState node — used for adding child projectiles and
## for accessing the actor (player) rotation. `mode` is the active resource.
## `muzzle` is the Marker2D the projectile spawns from.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
    push_error("WeaponBehavior.fire() not implemented")
```

- [ ] **Step 2: Write `straight_behavior.gd`**

```gdscript
# assault/scenes/player/weapons/behaviors/straight_behavior.gd
class_name StraightBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
    var actor: Node2D = state.get("actor")
    if actor == null or mode.projectile_scene == null:
        return
    var bullet: Bullet = mode.projectile_scene.instantiate()
    bullet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
    bullet.rotation = actor.rotation
    bullet.range_px = mode.range_px
    bullet.damage = mode.damage
    state.add_child(bullet)
```

- [ ] **Step 3: Smoke**

Compile-only check: open Godot, no parse errors in the Output panel.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/player/weapons/behaviors/weapon_behavior.gd assault/scenes/player/weapons/behaviors/straight_behavior.gd
git commit -m "feat(weapons): WeaponBehavior base + StraightBehavior"
```

---

## Task 7: LongRange + Spread behaviors

**Files:**
- Create: `assault/scenes/player/weapons/behaviors/long_range_behavior.gd`
- Create: `assault/scenes/player/weapons/behaviors/spread_behavior.gd`

- [ ] **Step 1: Write `long_range_behavior.gd`**

Long range is identical to straight except `range_px` is 0 (no cap). Reuse:

```gdscript
# assault/scenes/player/weapons/behaviors/long_range_behavior.gd
class_name LongRangeBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
    var actor: Node2D = state.get("actor")
    if actor == null or mode.projectile_scene == null:
        return
    var bullet: Bullet = mode.projectile_scene.instantiate()
    bullet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
    bullet.rotation = actor.rotation
    bullet.range_px = mode.range_px  # 0 from .tres
    bullet.damage = mode.damage
    state.add_child(bullet)
```

(Yes it's nearly identical. Kept separate for behavior-enum dispatch clarity; if duplication grows, refactor later.)

- [ ] **Step 2: Write `spread_behavior.gd`**

```gdscript
# assault/scenes/player/weapons/behaviors/spread_behavior.gd
class_name SpreadBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
    var actor: Node2D = state.get("actor")
    if actor == null or mode.projectile_scene == null or mode.pellet_count <= 0:
        return
    var spread_rad := deg_to_rad(mode.pellet_spread_deg)
    var step := 0.0 if mode.pellet_count == 1 else spread_rad / float(mode.pellet_count - 1)
    var start_angle := -spread_rad * 0.5
    for i in mode.pellet_count:
        var pellet: Bullet = mode.projectile_scene.instantiate()
        pellet.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
        pellet.rotation = actor.rotation + start_angle + step * i
        pellet.range_px = mode.range_px
        pellet.damage = mode.damage
        state.add_child(pellet)
```

- [ ] **Step 3: Smoke**

Compile-only check; no parse errors.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/player/weapons/behaviors/
git commit -m "feat(weapons): LongRange + Spread behaviors"
```

---

## Task 8: PrimaryHoming projectile

**Files:**
- Create: `assault/scenes/projectiles/primary_homing/primary_homing.gd`
- Create: `assault/scenes/projectiles/primary_homing/primary_homing.tscn`

- [ ] **Step 1: Write `primary_homing.gd`**

```gdscript
# assault/scenes/projectiles/primary_homing/primary_homing.gd
class_name PrimaryHoming
extends Area2D

signal expired

@export var speed: float = 480.0
## Maximum turn rate, degrees per second.
@export var turn_rate_deg_per_sec: float = 90.0
@export var lifetime_sec: float = 1.6
@export var damage: int = 50
@export var range_px: float = 0.0

var locked_target: Node = null
var _age: float = 0.0

func _ready() -> void:
    var hb := get_node_or_null("HitBox") as HitBox
    if hb:
        hb.damage = damage

func _physics_process(delta: float) -> void:
    _age += delta
    if _age >= lifetime_sec:
        expired.emit()
        queue_free()
        return

    if locked_target and is_instance_valid(locked_target) and (locked_target as Node2D).is_inside_tree():
        var to_target: Vector2 = (locked_target as Node2D).global_position - global_position
        var desired_angle := to_target.angle() + PI / 2.0  # +PI/2 because UP is forward
        var max_step := deg_to_rad(turn_rate_deg_per_sec) * delta
        rotation = rotate_toward(rotation, desired_angle, max_step)

    var forward := Vector2.UP.rotated(rotation)
    global_position += forward * speed * delta

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
    expired.emit()
    queue_free()

func _on_hit_box_area_entered(_area: Area2D) -> void:
    expired.emit()
    queue_free()
```

Helper: GDScript provides `rotate_toward()` as a built-in (Godot 4.4+).

- [ ] **Step 2: Author the scene**

In Godot:
1. New Scene → Other Node → Area2D → rename `PrimaryHoming` → attach `primary_homing.gd`.
2. Add child `Sprite2D` — use the same texture as `bullet.tscn`'s Beam (cyan capsule), or `assault/assets/sprites/rocket.png` scaled down (0.5).
3. Add child `CollisionShape2D` with a CapsuleShape2D 8×16.
4. Add child `HitBox` (script `hitbox_component.gd`), `collision_layer=64`, `collision_mask=513`, `damage_type=0` (LASER). Add a `CollisionShape2D` matching the parent capsule.
5. Add child `VisibleOnScreenNotifier2D`. Connect `screen_exited` → `_on_visible_on_screen_notifier_2d_screen_exited`.
6. Connect HitBox `area_entered` → `_on_hit_box_area_entered`.
7. Save as `primary_homing.tscn`.

- [ ] **Step 3: Smoke**

Drop the scene into Level 1 root via the editor temporarily; rotate it `0`; press play. Confirm: it flies straight up, despawns at screen exit. Drag it into the level near a fighter and assign a `locked_target` via Inspector; confirm it curves toward the target.

Remove the temporary instance.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/projectiles/primary_homing/
git commit -m "feat(projectiles): add PrimaryHoming for auto-aim weapon mode"
```

---

## Task 9: HomingBehavior (auto-aim)

**Files:**
- Create: `assault/scenes/player/weapons/behaviors/homing_behavior.gd`

- [ ] **Step 1: Write `homing_behavior.gd`**

```gdscript
# assault/scenes/player/weapons/behaviors/homing_behavior.gd
class_name HomingBehavior
extends WeaponBehavior

func fire(state: Node, mode: WeaponModeResource, muzzle: Marker2D) -> void:
    var actor: Node2D = state.get("actor")
    if actor == null or mode.projectile_scene == null:
        return
    var p: PrimaryHoming = mode.projectile_scene.instantiate()
    p.global_position = muzzle.global_position + Vector2.UP.rotated(actor.rotation)
    p.rotation = actor.rotation
    p.turn_rate_deg_per_sec = mode.homing_turn_rate_deg_per_sec
    p.lifetime_sec = mode.homing_lifetime_sec
    p.damage = mode.damage
    p.locked_target = _pick_target(actor)
    state.add_child(p)

## Picks the nearest enemy whose direction from `actor` falls within a 90° forward cone.
func _pick_target(actor: Node2D) -> Node:
    var enemies := actor.get_tree().get_nodes_in_group("enemies")
    var forward := Vector2.UP.rotated(actor.rotation)
    var best: Node = null
    var best_dist := INF
    for e in enemies:
        var n := e as Node2D
        if n == null or not n.is_inside_tree():
            continue
        var to: Vector2 = n.global_position - actor.global_position
        if to.length() < 1.0:
            continue
        if forward.angle_to(to) > PI / 4.0 or forward.angle_to(to) < -PI / 4.0:
            continue  # outside 90° cone
        var d := to.length()
        if d < best_dist:
            best_dist = d
            best = n
    return best
```

- [ ] **Step 2: Smoke**

Compile-only check; no parse errors.

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/player/weapons/behaviors/homing_behavior.gd
git commit -m "feat(weapons): HomingBehavior with forward-cone target selection"
```

---

## Task 10: PiercingBeam visual

**Files:**
- Create: `assault/scenes/projectiles/piercing_beam/piercing_beam.gd`
- Create: `assault/scenes/projectiles/piercing_beam/piercing_beam.tscn`

The beam is purely a visual line. Damage is applied by `BeamBehavior` directly.

- [ ] **Step 1: Write `piercing_beam.gd`**

```gdscript
# assault/scenes/projectiles/piercing_beam/piercing_beam.gd
class_name PiercingBeam
extends Node2D

@onready var _line: Line2D = $Line2D

func set_endpoints(world_from: Vector2, world_to: Vector2) -> void:
    if _line == null:
        return
    _line.global_position = Vector2.ZERO
    _line.points = PackedVector2Array([world_from, world_to])
```

- [ ] **Step 2: Author scene**

1. New Scene → Node2D → rename `PiercingBeam` → attach `piercing_beam.gd`.
2. Add child `Line2D`. width = 4, default_color = `Color(0.4, 1.0, 1.0, 0.85)`, begin_cap_mode = 2, end_cap_mode = 2. Empty points.
3. Save as `piercing_beam.tscn`.

- [ ] **Step 3: Smoke**

Open `piercing_beam.tscn` — call `set_endpoints(Vector2.ZERO, Vector2(0, -200))` from a temp script or edit the Line2D points in editor: confirm a cyan line renders.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/projectiles/piercing_beam/
git commit -m "feat(projectiles): PiercingBeam visual node"
```

---

## Task 11: RamShip — is_laser_blocking()

**Files:**
- Modify: `assault/scenes/enemies/ram_ship/ram_ship.gd`

- [ ] **Step 1: Add the method**

After `_enter_damaged_state()` (around line 49), add:

```gdscript
## Returns true while this ram ship blocks the piercing laser.
## Cleared by `_enter_damaged_state()` (first missile hit).
func is_laser_blocking() -> bool:
    return not _damaged
```

- [ ] **Step 2: Smoke**

Compile-only — no parse errors. (Functional smoke is in Task 12.)

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/enemies/ram_ship/ram_ship.gd
git commit -m "feat(ram_ship): expose is_laser_blocking() for piercing beam"
```

---

## Task 12: BeamBehavior

**Files:**
- Create: `assault/scenes/player/weapons/behaviors/beam_behavior.gd`

The beam works differently from the per-shot behaviors: it's continuous while held. It owns a single `PiercingBeam` instance (created lazily) and a per-enemy damage accumulator so DPS is fractional-frame-safe. We expose `tick(delta)` and `release()` separately from `fire()`.

- [ ] **Step 1: Write `beam_behavior.gd`**

```gdscript
# assault/scenes/player/weapons/behaviors/beam_behavior.gd
class_name BeamBehavior
extends WeaponBehavior

const _BEAM_SCENE: PackedScene = preload("res://assault/scenes/projectiles/piercing_beam/piercing_beam.tscn")
## How far the ray reaches (covers the screen comfortably from any player Y).
const _RAY_LENGTH: float = 1200.0

## Collision mask for the ray: layer 1 (environment, including asteroids 1024)
## + 4 (enemy hurt — TBD; we use intersect_shape on hurt-box areas instead).
## We keep the ray lean: layer 1 (asteroids) + 1024 just to be sure.
const _RAY_BLOCK_MASK: int = 1 | 1024

var _beam: PiercingBeam = null

## `fire()` is unused for BEAM (per-shot). Use `tick()` and `release()`.
func fire(_state: Node, _mode: WeaponModeResource, _muzzle: Marker2D) -> void:
    pass

## Called every physics frame while shoot is held.
func tick(state: Node, mode: WeaponModeResource, muzzle: Marker2D, delta: float) -> void:
    var actor: Node2D = state.get("actor")
    if actor == null:
        return

    if _beam == null or not is_instance_valid(_beam):
        _beam = _BEAM_SCENE.instantiate()
        state.add_child(_beam)

    var from: Vector2 = muzzle.global_position
    var dir: Vector2 = Vector2.UP.rotated(actor.rotation)
    var to: Vector2 = from + dir * _RAY_LENGTH

    # 1) Find blocker via raycast (asteroid layer or undamaged ram ship).
    var space := actor.get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(from, to)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    query.collision_mask = _RAY_BLOCK_MASK
    var blocker_point: Vector2 = to
    var blocker_collider: Object = null
    var hit: Dictionary = space.intersect_ray(query)
    if not hit.is_empty():
        var coll := hit.get("collider", null)
        var is_block := true
        if coll != null and coll.has_method("is_laser_blocking"):
            is_block = coll.is_laser_blocking()
        if is_block:
            blocker_point = hit.get("position", to)
            blocker_collider = coll

    # 2) Damage every enemy whose hurtbox intersects the segment from→blocker_point.
    var enemies := actor.get_tree().get_nodes_in_group("enemies")
    var seg_dir: Vector2 = blocker_point - from
    var seg_len: float = seg_dir.length()
    if seg_len > 0.0:
        var seg_unit: Vector2 = seg_dir / seg_len
        var dmg_this_frame: float = mode.beam_dps * delta
        for e in enemies:
            var n := e as Node2D
            if n == null or n == blocker_collider:
                continue
            # Project enemy center onto the beam segment; check distance from the line.
            var rel: Vector2 = n.global_position - from
            var t: float = rel.dot(seg_unit)
            if t < 0.0 or t > seg_len:
                continue
            var perp: float = abs(rel.dot(seg_unit.rotated(PI / 2.0)))
            if perp > 12.0:  # within ~12 px of the beam line
                continue
            var hb := n.get_node_or_null("HurtBox") as HurtBox
            if hb == null:
                continue
            # Accumulate fractional damage and emit when ≥ 1.
            _accumulate_and_apply(hb, dmg_this_frame)

    _beam.set_endpoints(from, blocker_point)

func release(_state: Node) -> void:
    if _beam != null and is_instance_valid(_beam):
        _beam.queue_free()
    _beam = null

# Per-target accumulator so 30 DPS at 60 FPS deals 0.5/frame and emits an int every other frame.
var _accum: Dictionary = {}  # { instance_id: float }

func _accumulate_and_apply(hb: HurtBox, amount: float) -> void:
    var key := hb.get_instance_id()
    var v: float = _accum.get(key, 0.0) + amount
    var whole: int = int(v)
    if whole > 0:
        hb.received_damage.emit(whole)
        v -= whole
    _accum[key] = v
```

- [ ] **Step 2: Smoke**

Compile-only check.

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/player/weapons/behaviors/beam_behavior.gd
git commit -m "feat(weapons): BeamBehavior with raycast blocker + segment damage"
```

---

## Task 13: WeaponState — refactor ShootingState

**Files:**
- Rename: `assault/scenes/player/states/shooting_state.gd` → `assault/scenes/player/states/weapon_state.gd`
- Modify: `assault/scenes/player/player_fighter.tscn` (script reference + node name)

The new state holds a mode registry (loaded from disk), an active id, and dispatches per-shot to the right behavior. It also handles the held-fire loop for BEAM.

- [ ] **Step 1: Rename the file and update class_name**

Move `shooting_state.gd` → `weapon_state.gd`. Replace contents:

```gdscript
# assault/scenes/player/states/weapon_state.gd
class_name WeaponState
extends State

signal weapon_changed(mode: WeaponModeResource)

@export_category("State Dependencies")
@export var actor: CharacterBody2D
@export var weapon_muzzles: Array[Marker2D]
@export var movement_controller: MovementController

@export_category("Heat Component")
@export var heat_component: Overheat

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

var _modes: Dictionary = {}  # { StringName: WeaponModeResource }
var _active_id: StringName = &"default"
var _cooldown: float = 0.0  # seconds remaining until next shot
var _gun_index: int = 0
var _behaviors: Dictionary = {}  # { Behavior: WeaponBehavior }

func _ready() -> void:
    _load_modes()
    _build_behaviors()
    movement_controller.action_single_press.connect(_on_action)
    if not UpgradeState.is_unlocked(_active_id):
        _active_id = _first_unlocked_id()
    _emit_changed()

func _load_modes() -> void:
    for id in UpgradeState.ALL_IDS:
        var path := _MODES_DIR + String(id) + ".tres"
        if not ResourceLoader.exists(path):
            continue
        var res := load(path) as WeaponModeResource
        if res:
            _modes[id] = res

func _build_behaviors() -> void:
    _behaviors[WeaponModeResource.Behavior.STRAIGHT] = StraightBehavior.new()
    _behaviors[WeaponModeResource.Behavior.LONG]     = LongRangeBehavior.new()
    _behaviors[WeaponModeResource.Behavior.SPREAD]   = SpreadBehavior.new()
    _behaviors[WeaponModeResource.Behavior.HOMING]   = HomingBehavior.new()
    _behaviors[WeaponModeResource.Behavior.BEAM]     = BeamBehavior.new()

func _first_unlocked_id() -> StringName:
    var unlocked := UpgradeState.unlocked_ids()
    return unlocked[0] if not unlocked.is_empty() else &"default"

func _on_action(key_name: String) -> void:
    if key_name == "cycle_weapon":
        _cycle()
    elif key_name == "shoot":
        _try_fire_once()

## Single-press fire path (STRAIGHT/LONG/SPREAD/HOMING).
func _try_fire_once() -> void:
    if not actor.can_attack:
        return
    var mode: WeaponModeResource = _modes.get(_active_id)
    if mode == null:
        return
    if mode.behavior == WeaponModeResource.Behavior.BEAM:
        return  # beam is held, handled in _physics_process
    if _cooldown > 0.0:
        return
    _fire(mode)
    _cooldown = mode.fire_interval

func _fire(mode: WeaponModeResource) -> void:
    if weapon_muzzles.is_empty():
        return
    _gun_index = (_gun_index + 1) % weapon_muzzles.size()
    var muzzle: Marker2D = weapon_muzzles[_gun_index]
    var beh: WeaponBehavior = _behaviors.get(mode.behavior)
    if beh == null:
        return
    beh.fire(self, mode, muzzle)
    heat_component.increase_heat(mode.heat_per_shot)

func _physics_process(delta: float) -> void:
    if _cooldown > 0.0:
        _cooldown = max(0.0, _cooldown - delta)

    var mode: WeaponModeResource = _modes.get(_active_id)
    if mode == null:
        return

    # Beam is continuous: tick while shoot is held, release on let-go.
    if mode.behavior == WeaponModeResource.Behavior.BEAM:
        var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
        if Input.is_action_pressed("shoot") and actor.can_attack:
            if weapon_muzzles.is_empty():
                return
            var muzzle: Marker2D = weapon_muzzles[0]
            beam.tick(self, mode, muzzle, delta)
            heat_component.increase_heat(mode.heat_per_shot * delta)
        else:
            beam.release(self)

func _cycle() -> void:
    var unlocked := UpgradeState.unlocked_ids()
    if unlocked.is_empty():
        return
    var i := unlocked.find(_active_id)
    var next_i := 0 if i < 0 else (i + 1) % unlocked.size()
    var prev_id := _active_id
    _active_id = unlocked[next_i]
    if prev_id != _active_id:
        # Make sure the beam visual goes away when switching off piercing.
        var beam: BeamBehavior = _behaviors[WeaponModeResource.Behavior.BEAM]
        beam.release(self)
        _cooldown = 0.0
        _emit_changed()

func _emit_changed() -> void:
    var mode: WeaponModeResource = _modes.get(_active_id)
    if mode:
        weapon_changed.emit(mode)
```

- [ ] **Step 2: Update `movement_controller.gd` SINGLE_PRESS_ACTIONS**

In `assault/scenes/player/movement_controller.gd`, add `"cycle_weapon"`:

```gdscript
var SINGLE_PRESS_ACTIONS: Array = [
    "move_left",
    "move_right",
    "move_up",
    "move_down",
    "shoot",
    "special_weapon",
    "switch_weapon",
    "cycle_weapon",
]
```

- [ ] **Step 3: Update `player_fighter.tscn`**

Open the scene. Find the `ShootingState` child node (or whatever it was named — the script field will mismatch). Update:
- Script: `weapon_state.gd`
- Node name: `WeaponState`
- Inspector exports remain the same (`actor`, `weapon_muzzles`, `movement_controller`, `heat_component`).
- Remove the `shooting_speed` and `heat_per_shot` exports — they're now per-mode.
- Remove `bullet_scene` preload — no longer needed.

- [ ] **Step 4: Smoke**

Run Level 1. With only `&"default"` unlocked, fire (`J`). Bullets should fire at the same rate, same damage, but **auto-expire after ~180 px** (before reaching far enemies). This confirms the new range cap.

Press `E` — nothing should change (only one mode unlocked).

- [ ] **Step 5: Commit**

```bash
git add -A  # picks up rename + tscn + movement_controller
git commit -m "refactor(weapons): replace ShootingState with mode-driven WeaponState"
```

---

## Task 14: HUD weapon chip

**Files:**
- Create: `assault/scenes/gui/weapon_chip.gd`
- Create: `assault/scenes/gui/weapon_chip.tscn`
- Modify: `assault/scenes/gui/hud.tscn` (add WeaponChip child)
- Modify: `assault/scenes/player/player_fighter.tscn` (connect weapon_changed signal — or do it in `hud.gd` via group lookup)

Connecting the signal cleanly across HUD/Player is the tricky bit. Simplest: the chip polls/listens via the player group on `_ready`.

- [ ] **Step 1: Write `weapon_chip.gd`**

```gdscript
# assault/scenes/gui/weapon_chip.gd
class_name WeaponChip
extends Control

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

func _ready() -> void:
    # Wait one frame so the player has been added to the tree.
    await get_tree().process_frame
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return
    var player := players[0]
    var ws: WeaponState = player.find_child("WeaponState", true, false) as WeaponState
    if ws == null:
        return
    ws.weapon_changed.connect(_on_weapon_changed)
    # The state emitted on its own _ready() before we connected, so ask it
    # to re-emit so the chip renders the initial mode.
    ws._emit_changed()

func _on_weapon_changed(mode: WeaponModeResource) -> void:
    _icon.texture = mode.icon
    _label.text = mode.display_name
```

- [ ] **Step 2: Author scene**

1. New Scene → Control → rename `WeaponChip` → attach script.
2. Set anchor: top-left, position offset 8, 8.
3. Child: `HBoxContainer` named `HBox`.
4. Child of HBox: `TextureRect` named `Icon`, custom_minimum_size 24×24, expand_mode 1, stretch_mode 5.
5. Child of HBox: `Label` named `Label`. theme_font_size 12.
6. Save as `weapon_chip.tscn`.

- [ ] **Step 3: Add to HUD**

Open `assault/scenes/gui/hud.tscn`. Instance `weapon_chip.tscn` as a child. Position appropriately.

- [ ] **Step 4: Smoke**

Run Level 1. The chip should show "Standard" with no icon (default.tres has no icon assigned — that's fine for now). Fire — chip stays put.

- [ ] **Step 5: Commit**

```bash
git add assault/scenes/gui/weapon_chip.gd assault/scenes/gui/weapon_chip.tscn assault/scenes/gui/hud.tscn
git commit -m "feat(hud): add weapon chip showing active mode"
```

---

## Task 15: Debug — Ctrl+U unlocks all

**Files:**
- Create: `assault/scenes/player/debug_unlock_all.gd`
- Modify: `assault/scenes/player/player_fighter.tscn` (add child node with this script)

- [ ] **Step 1: Write the debug script**

```gdscript
# assault/scenes/player/debug_unlock_all.gd
extends Node

func _unhandled_input(event: InputEvent) -> void:
    if not OS.is_debug_build():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var k := event as InputEventKey
        if k.ctrl_pressed and k.physical_keycode == KEY_U:
            UpgradeState.unlock_all()
            print("[DEBUG] All weapon upgrades unlocked.")
```

- [ ] **Step 2: Add to player scene**

Open `player_fighter.tscn`. Add a child `Node` → rename `DebugUnlockAll` → attach the script.

- [ ] **Step 3: Smoke**

Run Level 1. Press `Ctrl+U`. Output: `[DEBUG] All weapon upgrades unlocked.` Press `E`: weapon chip cycles through all 5 names. Each fire produces visibly different behavior (you'll prove this in Task 19's full smoke).

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/player/debug_unlock_all.gd assault/scenes/player/player_fighter.tscn
git commit -m "feat(debug): Ctrl+U unlocks all weapon upgrades (debug builds only)"
```

---

## Task 16: EnemyBullet — become_friendly()

**Files:**
- Modify: `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`

- [ ] **Step 1: Examine the .tscn**

Open `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` and find the HitBox child. Note its `collision_layer` (likely 128 = enemy projectile) and `collision_mask` (player hurt bits).

- [ ] **Step 2: Add `become_friendly()`**

Append to `enemy_bullet.gd`:

```gdscript
## Reflect-mode flip: this enemy bullet becomes a friendly projectile.
## Layers/mask are swapped to player-projectile (64) hitting enemy hurt (513).
func become_friendly() -> void:
    _direction = -_direction
    rotation += PI
    var hb := get_node_or_null("HitBox") as HitBox
    if hb:
        hb.collision_layer = 64
        hb.collision_mask = 513
        # Damage type already LASER by default — leave as-is.
```

- [ ] **Step 3: Smoke**

Compile-only.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd
git commit -m "feat(enemy_bullet): become_friendly() for reflect mode"
```

---

## Task 17: ReflectArea + ReflectState

**Files:**
- Create: `assault/scenes/player/states/reflect_state.gd`
- Modify: `assault/scenes/player/player_fighter.tscn` (add ReflectState child)
- Modify: `assault/scenes/player/movement_controller.gd` (add `reflect` to SINGLE_PRESS_ACTIONS)

- [ ] **Step 1: Add `reflect` to SINGLE_PRESS_ACTIONS**

```gdscript
var SINGLE_PRESS_ACTIONS: Array = [
    "move_left",
    "move_right",
    "move_up",
    "move_down",
    "shoot",
    "special_weapon",
    "switch_weapon",
    "cycle_weapon",
    "reflect",
]
```

- [ ] **Step 2: Write `reflect_state.gd`**

```gdscript
# assault/scenes/player/states/reflect_state.gd
class_name ReflectState
extends State

@export var actor: CharacterBody2D
@export var movement_controller: MovementController
@export_range(0.05, 0.5, 0.01) var window_sec: float = 0.15
@export_range(0.1, 5.0, 0.05) var cooldown_sec: float = 1.0
@export var reflect_radius: float = 24.0

var _cooldown_left: float = 0.0
var _window_left: float = 0.0
var _area: Area2D = null

func _ready() -> void:
    movement_controller.action_single_press.connect(_on_action)

func _physics_process(delta: float) -> void:
    if _cooldown_left > 0.0:
        _cooldown_left = max(0.0, _cooldown_left - delta)
    if _window_left > 0.0:
        _window_left -= delta
        if _window_left <= 0.0:
            _close_window()

func _on_action(key_name: String) -> void:
    if key_name != "reflect":
        return
    if not UpgradeState.is_unlocked(&"reflect"):
        return
    if _cooldown_left > 0.0 or _window_left > 0.0:
        return
    _open_window()

func _open_window() -> void:
    _window_left = window_sec
    _cooldown_left = cooldown_sec

    _area = Area2D.new()
    _area.collision_layer = 0
    _area.collision_mask = 128  # enemy bullet layer; verify against project layers
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = reflect_radius
    shape.shape = circle
    _area.add_child(shape)
    _area.area_entered.connect(_on_area_entered)
    actor.add_child(_area)

    # Visual flash — cyan modulate on the player sprite for the window duration.
    var sprite := actor.get_node_or_null("Sprite2D") as CanvasItem
    if sprite:
        sprite.modulate = Color(0.4, 1.0, 1.0, 1.0)
        var t := actor.create_tween()
        t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), window_sec)

func _close_window() -> void:
    if _area and is_instance_valid(_area):
        _area.queue_free()
    _area = null

func _on_area_entered(area: Area2D) -> void:
    # The area_entered fires for the HitBox child of an EnemyBullet.
    # Walk up to find an EnemyBullet root.
    var node: Node = area
    while node and not (node is EnemyBullet):
        node = node.get_parent()
    if node is EnemyBullet:
        (node as EnemyBullet).become_friendly()
```

**Important: verify `collision_mask = 128`** matches your enemy bullet layer. Check `enemy_bullet.tscn` HitBox `collision_layer` and substitute. If it's something else (e.g., 256), use that.

- [ ] **Step 3: Add ReflectState to player scene**

In `player_fighter.tscn`, add a child `Node` → rename `ReflectState` → attach script. In Inspector, drag the player root into `actor` and the `MovementController` into `movement_controller`.

- [ ] **Step 4: Smoke**

Run Level 1. Press `Ctrl+U` (debug unlock) so reflect is unlocked. Fly close to a Gunship that's firing. Time `H` — when an enemy bullet is on you, it should flip back. (You may need a few attempts; the window is tight.)

- [ ] **Step 5: Commit**

```bash
git add assault/scenes/player/states/reflect_state.gd assault/scenes/player/player_fighter.tscn assault/scenes/player/movement_controller.gd
git commit -m "feat(reflect): H-button shield with 0.15s window + 1s cooldown"
```

---

## Task 18: Smoke — full integration

**Files:** _(none)_

- [ ] **Step 1: Fresh save, default mode only**

Delete `%APPDATA%/Godot/app_userdata/<project>/upgrades.cfg` (Windows). Run Level 1. Confirm:
- Weapon chip shows "Standard".
- `J` fires bullets that auto-expire ~180 px (do NOT reach the top fighters before vanishing).
- `E` does nothing (only default unlocked).
- `K` fires rockets (warhead fan, 3 rockets).
- `Q` toggles to homing rockets; chip for that is the existing rocket UI, not the weapon chip.
- `H` does nothing (reflect locked).
- `F` triggers `interact` (no in-mission effect, but no error).

- [ ] **Step 2: Unlock all and cycle**

Press `Ctrl+U`. Press `E` repeatedly — chip cycles: Standard → Long Range → Piercing → Spread → Auto-Aim → Standard.

For each mode:
- **Standard**: short range bullets (regression — should match Step 1).
- **Long Range**: slower rate, bullets travel off-screen.
- **Piercing**: hold `J` — cyan beam from muzzle to top of screen, blocked by asteroid (beam terminates at asteroid surface), passes through fighters which die after ~0.3s sustained.
- **Spread**: 5 pellets in 60° fan, all auto-expire ~120 px.
- **Auto-Aim**: each shot curves toward nearest forward enemy.

- [ ] **Step 3: Ram-ship + piercing interaction**

Wait for a ram-ship wave (level 1 doesn't currently have one — temporarily add one in `level_1_waves.gd` or run any level with ram ships). Confirm:
- Hitting ram-ship with piercing beam: beam terminates at ram-ship; fighters behind it are NOT damaged.
- Fire a warhead (`K`) at the ram-ship → ram-ship enters damaged state.
- Now hold piercing again → beam passes through, damaging the ram-ship and anything behind it.

- [ ] **Step 4: Reflect**

Switch to a level with Gunships (or any enemy that fires). Fly into bullet range. Time `H` against incoming fire. Confirm a flipped bullet kills the shooter or another nearby enemy.

- [ ] **Step 5: Persistence**

Quit. Re-run. Weapon chip still shows last selected mode? (Acceptable answer: no — we did not persist active id. Confirm `upgrades.cfg` retained the unlocked list.)

- [ ] **Step 6: Commit (smoke notes)**

If all steps pass: no commit needed. If smoke revealed bugs, fix inline and commit per-bug:

```bash
git commit -m "fix(weapons): <specific bug>"
```

---

## Spec Coverage Check

| Spec section | Implementing task |
|---|---|
| §2 Input map (5 changes) | Task 1 |
| §3 Weapon modes (5 modes) | Tasks 3, 5 |
| §3 WeaponModeResource schema | Task 3 |
| §4 UpgradeState autoload | Task 2 |
| §5 WeaponState refactor | Task 13 |
| §5 Bullet `range_px` + damage | Task 4 |
| §5 PrimaryHoming projectile | Task 8 |
| §5 PiercingBeam visual | Task 10 |
| §5 Behaviors (5) | Tasks 6, 7, 9, 12 |
| §6 Reflect shield | Task 17 |
| §6 EnemyBullet.become_friendly() | Task 16 |
| §7 RamShip.is_laser_blocking() | Task 11 |
| §8 HUD weapon chip | Task 14 |
| §9 Save format & Ctrl+U | Tasks 2, 15 |
| §11 Testing checklist | Task 18 |

All spec sections covered.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Beam DPS feels wrong (too weak/strong) at 30 dps | Smoke step in Task 18.2; tune `piercing.tres` `beam_dps` if needed |
| Reflect window feels too tight at 0.15s | Smoke step 18.4; tweak the export on `ReflectState` from Inspector |
| Auto-aim cone too narrow (90°) misses obvious targets | Tune `_pick_target` cone in Task 9 — flag for review during smoke |
| Bullet damage 50 default doesn't match new mode-driven 50 | They match; if regression appears, verify Task 4's `_ready` push |
| HitBox damage push timing — child not ready at parent `_ready()` | Bullet's `_ready` runs before children only if scene tree order matters; for safety, use `call_deferred("_ready")` if needed; smoke step 4.2 catches this |
| Layer mismatch on reflect (`mask=128` may be wrong) | Task 17 step 2 explicitly tells the implementer to verify against the actual enemy bullet layer |
