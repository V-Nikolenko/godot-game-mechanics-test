# Shield Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the continuous-pool shield with a discrete-charge model (permanent regenerating + temporary stack), exposed via an animated icon strip in the HUD.

**Architecture:** A new `ShipProgressionState` autoload owns the permanent shield count and persists it across runs. The existing `Shield` component (`global/components/shield_component.gd`) is rewritten internally to track two counters (`permanent_active`, `temporary_count`) and emit `shield_state_changed(snapshot)`. `PlayerBase._apply_damage` calls `shield.consume_one()` — one charge absorbs one hit. A new `ShieldIconStrip` (HBoxContainer) of `ShieldIcon` (AnimatedSprite2D) nodes lives above the trimmed health bar in both HUDs, animating destroy/recharge/hacked states from a single shared `SpriteFrames` resource.

**Tech Stack:** Godot 4.3+ GDScript (fully typed), `ConfigFile` persistence under `user://`, scene-based UI (`HBoxContainer`, `AnimatedSprite2D`). No new dependencies.

**Project conventions:**
- Project root is `C:\Users\Lonli\Desktop\game-test-mechanics`. All paths are repo-relative.
- The user handles all git commits — never run `git commit` from this plan. End-of-task "Commit checkpoint" steps just stop and let the user commit.
- The project has no automated test framework. Each task's verification is manual: launch the Godot editor, open the indicated scene, perform the listed actions, observe console / inspector output. Verification prints are formatted `[Shield] …` to match the project's `[Enemy] …` / `[LEVEL] …` convention.
- Work directly on `main`. No worktrees or branches unless the user asks.

**Spec:** `docs/superpowers/specs/2026-05-25-shield-rework-design.md` (read once before starting).

---

## File map

**New:**
- `global/autoloads/ship_progression_state.gd` — persistence autoload (Task 1)
- `global/components/shield_animations.tres` — shared SpriteFrames (Task 3)
- `global/components/shield_icon.gd` + `shield_icon.tscn` (Task 4)
- `global/components/shield_icon_strip.gd` + `shield_icon_strip.tscn` (Task 5)

**Modified:**
- `project.godot` (Task 1 — autoload registration)
- `global/components/shield_component.gd` (Task 2 — full rewrite)
- `global/entities/player_base.gd` (Task 2 — damage flow + remove shield signal handlers)
- `global/systems/event_bus.gd` (Task 2 — remove three deprecated signals)
- `global/ship_modules/shield_overload_module.gd` (Task 2 — `try_activate` rewrite)
- `assault/scenes/gui/health_shield_bar.gd` (Task 2 — trim to health-only)
- `assault/scenes/gui/health_shield_bar.tscn` (Task 2 — delete `ShieldBar`)
- `global/ui/mission_hud.gd` (Tasks 2 & 6 — setup signature + strip wiring)
- `assault/scenes/gui/hud.tscn` (Task 6 — add `ShieldIconStrip`)
- `open_space/scenes/gui/hud.tscn` (Task 6 — add `ShieldIconStrip`, shift health bar)
- `assault/scenes/player/debug_unlock_all.gd` (Task 7 — debug shortcuts)

---

## Task 1: `ShipProgressionState` autoload

**Files:**
- Create: `global/autoloads/ship_progression_state.gd`
- Modify: `project.godot` (add autoload entry)

- [ ] **Step 1.1: Create the autoload script**

Create file `global/autoloads/ship_progression_state.gd` with content:

```gdscript
# global/autoloads/ship_progression_state.gd
## Persists permanent ship upgrades that survive across runs.
## Currently tracks: permanent shield slot count.
## Registered as autoload "ShipProgressionState" in project.godot.
extends Node

const SAVE_PATH := "user://ship_progression.cfg"
const SECTION := "progression"
const KEY_SHIELDS := "permanent_shield_count"
const MIN_SHIELDS: int = 1
const MAX_SHIELDS: int = 5

signal permanent_shield_count_changed(new_count: int)

var permanent_shield_count: int = MIN_SHIELDS

func _ready() -> void:
	_load()

func set_permanent_shield_count(n: int) -> void:
	var clamped: int = clampi(n, MIN_SHIELDS, MAX_SHIELDS)
	if clamped == permanent_shield_count:
		return
	permanent_shield_count = clamped
	_save()
	permanent_shield_count_changed.emit(clamped)

## Convenience for the future shield-up pickup. Returns false if already at cap.
func add_permanent_shield() -> bool:
	if permanent_shield_count >= MAX_SHIELDS:
		return false
	set_permanent_shield_count(permanent_shield_count + 1)
	return true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_SHIELDS, permanent_shield_count)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("ShipProgressionState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var raw: int = int(cfg.get_value(SECTION, KEY_SHIELDS, MIN_SHIELDS))
	permanent_shield_count = clampi(raw, MIN_SHIELDS, MAX_SHIELDS)
```

- [ ] **Step 1.2: Register the autoload in `project.godot`**

Find the `[autoload]` block. The current end of the block is:
```
ShipModuleState="*res://global/autoloads/ship_module_state.gd"
```

Add immediately below that line:
```
ShipProgressionState="*res://global/autoloads/ship_progression_state.gd"
```

- [ ] **Step 1.3: Verify the autoload loads cleanly**

In the Godot editor, press **F5** to launch the game.

Expected: project launches with no parse errors or `push_error` warnings in the Output panel related to `ShipProgressionState`.

If you see `failed to save` errors, the path or `ConfigFile` API is wrong — fix before proceeding.

- [ ] **Step 1.4: Verify persistence round-trip**

With the game running, open the **Debugger** dock → **Remote** tab → expand `/root` → click `ShipProgressionState`. In the **Inspector** confirm `permanent_shield_count = 1`.

In the **Debugger** → **Stack Frames** → expression eval, run:
```
ShipProgressionState.set_permanent_shield_count(3)
```
Confirm the inspector value updates to 3.

Stop the game. Press **F5** again to relaunch. Open the Remote inspector again — confirm `permanent_shield_count` is still **3** (the change persisted).

Reset to clean state for the rest of the plan:
```
ShipProgressionState.set_permanent_shield_count(1)
```
Stop the game. Confirm `user://ship_progression.cfg` exists (in `%APPDATA%\Godot\app_userdata\<project name>\` on Windows) with one line `permanent_shield_count=1`.

- [ ] **Step 1.5: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: add ShipProgressionState autoload for permanent shield count`.

---

## Task 2: Shield data layer + integration refactor (atomic)

This is the largest task. It atomically swaps the data layer — the project will not compile midway through the steps. **Do not stop and verify after intermediate steps**; complete all file edits, then run the verification at Step 2.9.

**Files:**
- Modify: `global/components/shield_component.gd`
- Modify: `global/entities/player_base.gd`
- Modify: `global/systems/event_bus.gd`
- Modify: `global/ship_modules/shield_overload_module.gd`
- Modify: `assault/scenes/gui/health_shield_bar.gd`
- Modify: `assault/scenes/gui/health_shield_bar.tscn`
- Modify: `global/ui/mission_hud.gd`

- [ ] **Step 2.1: Rewrite `global/components/shield_component.gd`**

Replace the entire file content with:

```gdscript
# global/components/shield_component.gd
## Discrete-charge shield. Each charge absorbs ONE incoming hit in full.
## Permanent charges regenerate (1 per REGEN_INTERVAL_SEC of no damage).
## Temporary charges are consumed and not refilled.
##
## Damage flow lives in PlayerBase._apply_damage:
##   if shield_component.consume_one():
##       return                            # one mistake absorbed
##   health_component.decrease(damage)
##
## UI (ShieldIconStrip) subscribes to shield_state_changed and renders icons
## from snapshot keys: perm_active, perm_max, temp_count, hacked.
class_name Shield
extends Node

@export var max_temporary: int = 5            ## hard cap on temp stack — expected to be retuned later

const REGEN_INTERVAL_SEC: float = 5.0

signal shield_state_changed(snapshot: Dictionary)

var permanent_max: int = 1       ## set in _ready from ShipProgressionState (≤ MAX_SHIELDS)
var permanent_active: int = 0    ## ≤ permanent_max
var temporary_count: int = 0     ## ≤ max_temporary
var is_hacked: bool = false

var _regen_timer: Timer = null

func _ready() -> void:
	permanent_max = ShipProgressionState.permanent_shield_count
	permanent_active = permanent_max
	ShipProgressionState.permanent_shield_count_changed.connect(_on_progression_changed)

	_regen_timer = Timer.new()
	_regen_timer.one_shot = true
	_regen_timer.wait_time = REGEN_INTERVAL_SEC
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)
	_emit_snapshot()

## Pop one charge. Returns true if the hit was absorbed.
## Order: temporary first, then permanent.
## If hacked: drains ALL charges and returns true once.
func consume_one() -> bool:
	if is_hacked:
		if permanent_active <= 0 and temporary_count <= 0:
			return false
		permanent_active = 0
		temporary_count = 0
		_restart_regen()
		_emit_snapshot()
		return true

	if temporary_count > 0:
		temporary_count -= 1
		_restart_regen()
		_emit_snapshot()
		return true

	if permanent_active > 0:
		permanent_active -= 1
		_restart_regen()
		_emit_snapshot()
		return true

	return false

## Push +1 onto the temp stack. Returns false if already at cap.
func add_temporary() -> bool:
	if temporary_count >= max_temporary:
		return false
	temporary_count += 1
	_emit_snapshot()
	return true

## Refill all permanent shields (used by armor_tank pickup, future spec).
func restore_all_permanent() -> void:
	if permanent_active >= permanent_max:
		return
	permanent_active = permanent_max
	_emit_snapshot()

## Drain everything. Used by ShieldOverloadModule.
func set_all_zero() -> void:
	if permanent_active == 0 and temporary_count == 0:
		return
	permanent_active = 0
	temporary_count = 0
	_restart_regen()
	_emit_snapshot()

## API hook for the future hacked-state trigger (no caller yet).
func set_hacked(value: bool) -> void:
	if is_hacked == value:
		return
	is_hacked = value
	_emit_snapshot()

func _on_progression_changed(new_max: int) -> void:
	permanent_max = new_max
	## Auto-fill the new slot if the player has unlocked one (e.g. picked up shield_up mid-mission).
	if permanent_active < permanent_max:
		permanent_active = mini(permanent_active + 1, permanent_max)
	_emit_snapshot()

func _on_regen_tick() -> void:
	if permanent_active >= permanent_max:
		return
	permanent_active += 1
	_emit_snapshot()
	if permanent_active < permanent_max:
		_regen_timer.start()

func _restart_regen() -> void:
	if _regen_timer:
		_regen_timer.start()

func _emit_snapshot() -> void:
	var snap := {
		"perm_active": permanent_active,
		"perm_max": permanent_max,
		"temp_count": temporary_count,
		"hacked": is_hacked,
	}
	print("[Shield] %s" % str(snap))
	shield_state_changed.emit(snap)
```

- [ ] **Step 2.2: Update `global/entities/player_base.gd` damage flow + remove shield signal handlers**

Read the current content first (it's 84 lines). Two edits required:

**Edit A** — `_setup_components()`. Find and remove the shield signal connections. The current block reads:

```gdscript
	if shield_component:
		shield_component.shield_changed.connect(_on_shield_changed)
		shield_component.shield_depleted.connect(_on_shield_depleted)
	if overheat_component:
		overheat_component.overheat.connect(_on_overheat_updated)
```

Replace with (remove the entire `if shield_component:` block):

```gdscript
	if overheat_component:
		overheat_component.overheat.connect(_on_overheat_updated)
```

**Edit B** — `_apply_damage`. Find:

```gdscript
func _apply_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	var overflow := shield_component.absorb(effective)
	if overflow > 0:
		health_component.decrease(overflow)
```

Replace with:

```gdscript
func _apply_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	if shield_component.consume_one():
		return                            ## one mistake absorbed
	health_component.decrease(effective)
```

**Edit C** — Remove the two now-dead handler methods. Find and delete:

```gdscript
## Called when shield absorbs or restores. Emits EventBus signal.
func _on_shield_changed(current: int, maximum: int) -> void:
	EventBus.player_shield_changed.emit(current, maximum)

## Called when shield reaches zero. Emits EventBus signal.
func _on_shield_depleted() -> void:
	EventBus.player_shield_depleted.emit()
```

- [ ] **Step 2.3: Remove deprecated signals from `global/systems/event_bus.gd`**

Find the block:

```gdscript
## Emitted whenever the player's shield value changes.
signal player_shield_changed(current: int, maximum: int)

## Emitted when the player's shield reaches zero.
signal player_shield_depleted

## Emitted when the player's shield recovers from zero to any positive value.
signal player_shield_restored
```

Delete the entire block (six lines including the doc comments and blank lines between).

- [ ] **Step 2.4: Rewrite `try_activate` in `global/ship_modules/shield_overload_module.gd`**

Update the damage constant. Find:

```gdscript
const _DAMAGE_PER_SHIELD: float = 0.5
```

Replace with:

```gdscript
const _DAMAGE_PER_SHIELD: int = 25
```

Update the description string. Find:

```gdscript
func get_description() -> String:
	return "Press H to detonate your shield. Converts every point of shield into 0.5 damage against enemies within 100px and sends them flying. Also destroys nearby projectiles. Requires shield to activate."
```

Replace with:

```gdscript
func get_description() -> String:
	return "Press H to detonate your shield. Spends every active shield (permanent + temporary) and deals damage in a radius scaling with the number consumed. Also destroys nearby projectiles. Requires at least one shield."
```

Rewrite the body of `try_activate`. Find:

```gdscript
func try_activate(player: Node) -> bool:
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null or shield.current_shield <= 0:
		return false  ## Nothing to spend.

	var actor := player as Node2D
	var shield_spent: int = shield.current_shield

	## Drain shield.
	shield.set_shield(0)

	var damage: int = roundi(shield_spent * _DAMAGE_PER_SHIELD)
```

Replace with:

```gdscript
func try_activate(player: Node) -> bool:
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null:
		return false
	var spent: int = shield.permanent_active + shield.temporary_count
	if spent <= 0:
		return false  ## Nothing to detonate.

	var actor := player as Node2D

	## Drain everything.
	shield.set_all_zero()

	var damage: int = spent * _DAMAGE_PER_SHIELD
```

Leave the rest of `try_activate` (enemy loop, knockback, projectile clear, `_spawn_burst`) untouched.

- [ ] **Step 2.5: Trim `assault/scenes/gui/health_shield_bar.gd`**

Replace the entire file with:

```gdscript
# assault/scenes/gui/health_shield_bar.gd
class_name HealthShieldBar
extends Control

## Displays the player's health as a single ProgressBar.
## (Class name retained for backward compatibility with existing scene references.)

@onready var _health_bar: ProgressBar = $HealthBar

func setup(health: Health) -> void:
	_health_bar.max_value = health.max_health
	_health_bar.value     = health.current_health
	health.amount_changed.connect(_on_health_changed)

func _on_health_changed(current: int) -> void:
	_health_bar.value = current
```

- [ ] **Step 2.6: Delete the `ShieldBar` node from `assault/scenes/gui/health_shield_bar.tscn`**

Open the file. Find and delete the block:

```
[node name="ShieldBar" type="ProgressBar" parent="."]
anchor_right = 1.0
offset_top = 0.0
offset_bottom = 12.0
min_value = 0.0
max_value = 100.0
value = 100.0
```

Also update the `HealthBar` to occupy the full height since it no longer shares space with the shield. Find:

```
[node name="HealthBar" type="ProgressBar" parent="."]
anchor_right = 1.0
offset_top = 14.0
offset_bottom = 28.0
min_value = 0.0
max_value = 50.0
value = 50.0
```

Replace with:

```
[node name="HealthBar" type="ProgressBar" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
min_value = 0.0
max_value = 50.0
value = 50.0
```

Also shrink the parent control's minimum size from 28 to 14 (the new bar height). Find:

```
[node name="HealthShieldBar" type="Control"]
custom_minimum_size = Vector2(150, 28)
```

Replace with:

```
[node name="HealthShieldBar" type="Control"]
custom_minimum_size = Vector2(150, 14)
```

- [ ] **Step 2.7: Update `setup()` call signature in `global/ui/mission_hud.gd`**

Find:

```gdscript
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)
```

Replace with (the `shield` lookup stays — Task 6 needs it):

```gdscript
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health:
		health_shield_bar.setup(health)
	## Shield icon strip wiring lives in Task 6.
```

- [ ] **Step 2.8: Resize the HUD `HealthShieldBar` instance offsets**

Since the bar is now 14 px tall (was 28), update the assault HUD's anchor offsets so the bar still sits at the bottom edge.

Edit `assault/scenes/gui/hud.tscn`. Find:

```
[node name="HealthShieldBar" parent="." instance=ExtResource("4_hsbar")]
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = -36.0
offset_right = 158.0
offset_bottom = -8.0
```

Replace with:

```
[node name="HealthShieldBar" parent="." instance=ExtResource("4_hsbar")]
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = -22.0
offset_right = 158.0
offset_bottom = -8.0
```

(The open_space HUD's `HealthShieldBar` is top-anchored with only `offset_left = 8, offset_top = 8` — Task 6 will adjust that when adding the icon strip above it.)

- [ ] **Step 2.9: Verify the project compiles and the new damage flow works**

Open the Godot editor. Reload the project (Project → Reload Current Project) to force a full re-parse. Expected: no parse errors in the Output / Debugger panels.

Press **F5** to launch the game. Pick the assault scenario (Level 1). When the level starts, watch the **Output** panel — you should see one `[Shield] {"perm_active": 1, "perm_max": 1, "temp_count": 0, "hacked": false}` line shortly after the player spawns.

Move the player into an enemy bullet. Expected:
- One additional `[Shield] {"perm_active": 0, ...}` line in Output.
- The health bar at bottom-left does NOT decrease (one mistake absorbed).
- The cyan shield bar is gone — only the red health bar remains.

Wait 5 seconds without taking another hit. Expected:
- One `[Shield] {"perm_active": 1, ...}` line — shield regenerated.

Take two hits in quick succession. Expected:
- First hit: `perm_active 1→0` printed, no health loss.
- Second hit: no `[Shield]` line, health bar drops by the bullet's damage.

If the second hit's damage is consumed without health loss (or if the first hit drops health), the damage flow is wrong — re-check Step 2.2.

- [ ] **Step 2.10: Verify `ShieldOverloadModule` works with the new model**

In the running game, open the **Debugger** → **Remote** → find the player → call:

```
ShipModuleState.equip(&"armor", &"shield_overload")
```

Wait 5 seconds for the permanent shield to refill (watch Output). Press **H** while near enemies. Expected:
- One `[Shield] {"perm_active": 0, "temp_count": 0, ...}` line (drained).
- The blue burst-ring visual plays.
- Nearby enemies (within ~100 px) take 25 damage each (1 shield × 25).
- Nearby enemy projectiles are destroyed.

If pressing H with no shields fails silently — that is correct (the module returns false when `spent <= 0`).

- [ ] **Step 2.11: Commit checkpoint**

Stop and let the user commit. Suggested message: `refactor(shield): swap continuous-pool shield for discrete-charge model`.

---

## Task 3: Placeholder `shield_animations.tres` SpriteFrames

The artist will replace these frames with real cuts from `shields.png`, but the resource needs to exist with all 12 animation names before icon scripts can load it.

**Files:**
- Create: `global/components/shield_animations.tres`

- [ ] **Step 3.1: Create the SpriteFrames resource**

Create `global/components/shield_animations.tres` with content:

```
[gd_resource type="SpriteFrames" load_steps=3 format=3 uid="uid://shieldanims001"]

[ext_resource type="Texture2D" path="res://global/assets/sprites/shields.png" id="1_sheet"]

[sub_resource type="AtlasTexture" id="AtlasTexture_placeholder"]
atlas = ExtResource("1_sheet")
region = Rect2(0, 0, 16, 16)

[resource]
animations = [{
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": true,
"name": &"shield_idle",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"shield_destroy",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"shield_recharge",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": true,
"name": &"shield_hacked_idle",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"shield_hacked_interference",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"shield_restore_after_hacking",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": true,
"name": &"additional_shield_idle",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"additional_shield_destroy",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"additional_shield_recharge",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": true,
"name": &"additional_shield_hacked_idle",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"additional_shield_hacked",
"speed": 5.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("AtlasTexture_placeholder")}],
"loop": false,
"name": &"additional_shield_restore_after_hacking",
"speed": 5.0
}]
```

Note: `loop=false` on destroy/recharge/restore/interference animations is required — the icon script relies on `animation_finished` firing for these.

- [ ] **Step 3.2: Verify in the Godot editor**

In the FileSystem dock, double-click `global/components/shield_animations.tres`. Godot opens it in the SpriteFrames editor. Confirm all 12 animation names are present in the left-side list:

```
shield_idle, shield_destroy, shield_recharge, shield_hacked_idle,
shield_hacked_interference, shield_restore_after_hacking,
additional_shield_idle, additional_shield_destroy, additional_shield_recharge,
additional_shield_hacked_idle, additional_shield_hacked,
additional_shield_restore_after_hacking
```

The user (artist) will later replace the placeholder region with real per-animation cuts. The plan proceeds with placeholders.

- [ ] **Step 3.3: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: add shield_animations.tres placeholder SpriteFrames`.

---

## Task 4: `ShieldIcon` scene + script

**Files:**
- Create: `global/components/shield_icon.gd`
- Create: `global/components/shield_icon.tscn`

- [ ] **Step 4.1: Create the script `global/components/shield_icon.gd`**

```gdscript
# global/components/shield_icon.gd
## Single animated shield slot. PERMANENT and TEMPORARY tiers use different
## animation prefixes ("shield_*" vs "additional_shield_*") in the shared
## SpriteFrames resource at global/components/shield_animations.tres.
class_name ShieldIcon
extends AnimatedSprite2D

enum Tier { PERMANENT, TEMPORARY }

const _INTERFERENCE_MIN_SEC: float = 3.0
const _INTERFERENCE_MAX_SEC: float = 4.0

var tier: int = Tier.PERMANENT
var _is_empty: bool = false   ## true after destroy for PERMANENT; TEMPORARY queue_frees instead
var _interference_timer: Timer = null

func _ready() -> void:
	_interference_timer = Timer.new()
	_interference_timer.one_shot = true
	_interference_timer.timeout.connect(_on_interference_tick)
	add_child(_interference_timer)

func setup(t: int) -> void:
	tier = t
	_is_empty = false
	play("%s_idle" % _prefix())

func play_destroy() -> void:
	if _is_empty:
		return
	var done := animation_finished
	play("%s_destroy" % _prefix())
	await done
	if tier == Tier.TEMPORARY:
		queue_free()
		return
	_is_empty = true
	## The destroy animation's last frame is authored as the "empty slot" sprite,
	## so we stop here and leave it shown. Calling stop() would reset to frame 0.

func play_recharge() -> void:
	var done := animation_finished
	play("%s_recharge" % _prefix())
	await done
	_is_empty = false
	play("%s_idle" % _prefix())

func play_hacked() -> void:
	play("%s_hacked_idle" % _prefix())
	_schedule_next_interference()

func play_restore() -> void:
	_interference_timer.stop()
	var done := animation_finished
	play("%s_restore_after_hacking" % _prefix())
	await done
	play("%s_idle" % _prefix())

func _prefix() -> String:
	return "shield" if tier == Tier.PERMANENT else "additional_shield"

func _schedule_next_interference() -> void:
	var wait: float = randf_range(_INTERFERENCE_MIN_SEC, _INTERFERENCE_MAX_SEC)
	_interference_timer.start(wait)

func _on_interference_tick() -> void:
	if not is_inside_tree():
		return
	var done := animation_finished
	play("%s_hacked_interference" % _prefix() if tier == Tier.PERMANENT \
			else "%s_hacked" % _prefix())
	await done
	if not is_inside_tree():
		return
	play("%s_hacked_idle" % _prefix())
	_schedule_next_interference()
```

- [ ] **Step 4.2: Create the scene `global/components/shield_icon.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://shieldicon001"]

[ext_resource type="Script" path="res://global/components/shield_icon.gd" id="1_icon"]
[ext_resource type="SpriteFrames" path="res://global/components/shield_animations.tres" id="2_anim"]

[node name="ShieldIcon" type="AnimatedSprite2D"]
texture_filter = 1
sprite_frames = ExtResource("2_anim")
animation = &"shield_idle"
autoplay = "shield_idle"
script = ExtResource("1_icon")
```

- [ ] **Step 4.3: Verify the scene opens and plays the idle animation**

In Godot, double-click `global/components/shield_icon.tscn`. The 2D viewport should show the placeholder texture region from `shields.png`. No parse errors.

Open the **Remote** debugger after launching the scene in isolation (Ctrl+R from inside the scene): confirm `tier = 0` (PERMANENT), `animation = "shield_idle"`.

- [ ] **Step 4.4: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: add ShieldIcon scene for animated shield slots`.

---

## Task 5: `ShieldIconStrip` scene + script

**Files:**
- Create: `global/components/shield_icon_strip.gd`
- Create: `global/components/shield_icon_strip.tscn`

- [ ] **Step 5.1: Create the script `global/components/shield_icon_strip.gd`**

```gdscript
# global/components/shield_icon_strip.gd
## A horizontal row of ShieldIcon nodes, one per shield slot.
## Permanent icons are leftmost (always present, switch to "empty" visual when
## destroyed). Temporary icons are appended to the right and queue_free on destroy.
##
## Usage:
##   var strip := preload(".../shield_icon_strip.tscn").instantiate()
##   add_child(strip)
##   strip.setup(player.shield_component)
class_name ShieldIconStrip
extends HBoxContainer

const _ICON_SCENE: PackedScene = preload("res://global/components/shield_icon.tscn")

var _shield: Shield = null
var _perm_icons: Array[ShieldIcon] = []
var _temp_icons: Array[ShieldIcon] = []
var _last: Dictionary = {
	"perm_active": 0, "perm_max": 0, "temp_count": 0, "hacked": false,
}

func setup(shield: Shield) -> void:
	_shield = shield
	_rebuild_permanent(shield.permanent_max)
	shield.shield_state_changed.connect(_on_shield_state_changed)
	## Apply the initial state (the Shield emits its snapshot in _ready before
	## we connect — push the current state through manually).
	_on_shield_state_changed({
		"perm_active": shield.permanent_active,
		"perm_max": shield.permanent_max,
		"temp_count": shield.temporary_count,
		"hacked": shield.is_hacked,
	})

func _rebuild_permanent(count: int) -> void:
	for icon in _perm_icons:
		icon.queue_free()
	_perm_icons.clear()
	for i in count:
		var icon: ShieldIcon = _ICON_SCENE.instantiate()
		add_child(icon)
		move_child(icon, i)  ## keep perm icons leftmost
		icon.setup(ShieldIcon.Tier.PERMANENT)
		_perm_icons.append(icon)

func _on_shield_state_changed(snap: Dictionary) -> void:
	## --- Permanent max changed (e.g. shield-up pickup) ---
	if snap.perm_max != _last.perm_max:
		_rebuild_permanent(int(snap.perm_max))

	## --- Permanent active changed ---
	var perm_delta: int = int(snap.perm_active) - int(_last.perm_active)
	if perm_delta < 0:
		## Destroy the rightmost (perm_delta) active permanent icons.
		var to_destroy: int = -perm_delta
		var idx: int = int(_last.perm_active) - 1
		while to_destroy > 0 and idx >= 0:
			_perm_icons[idx].play_destroy()
			idx -= 1
			to_destroy -= 1
	elif perm_delta > 0:
		## Recharge the leftmost (perm_delta) empty permanent icons.
		var to_recharge: int = perm_delta
		var idx: int = int(_last.perm_active)
		while to_recharge > 0 and idx < _perm_icons.size():
			_perm_icons[idx].play_recharge()
			idx += 1
			to_recharge -= 1

	## --- Temporary count changed ---
	var temp_delta: int = int(snap.temp_count) - int(_last.temp_count)
	if temp_delta > 0:
		for _i in temp_delta:
			var icon: ShieldIcon = _ICON_SCENE.instantiate()
			add_child(icon)
			icon.setup(ShieldIcon.Tier.TEMPORARY)
			icon.play_recharge()
			_temp_icons.append(icon)
	elif temp_delta < 0:
		var to_remove: int = -temp_delta
		while to_remove > 0 and _temp_icons.size() > 0:
			var icon: ShieldIcon = _temp_icons.pop_back()
			icon.play_destroy()  ## icon queue_frees itself on animation_finished
			to_remove -= 1

	## --- Hacked toggle ---
	if bool(snap.hacked) != bool(_last.hacked):
		if snap.hacked:
			for icon in _perm_icons:
				icon.play_hacked()
			for icon in _temp_icons:
				icon.play_hacked()
		else:
			for icon in _perm_icons:
				icon.play_restore()
			for icon in _temp_icons:
				icon.play_restore()

	_last = snap.duplicate()
```

- [ ] **Step 5.2: Create the scene `global/components/shield_icon_strip.tscn`**

```
[gd_scene load_steps=2 format=3 uid="uid://shieldstrip001"]

[ext_resource type="Script" path="res://global/components/shield_icon_strip.gd" id="1_strip"]

[node name="ShieldIconStrip" type="HBoxContainer"]
custom_minimum_size = Vector2(180, 18)
theme_override_constants/separation = 2
script = ExtResource("1_strip")
```

- [ ] **Step 5.3: Smoke-test the strip in isolation**

Open `global/components/shield_icon_strip.tscn`. Press **Ctrl+R** to launch JUST this scene. The Output panel will show no errors. The scene renders an empty HBoxContainer (since `setup()` hasn't been called).

The real wiring happens in Task 6.

- [ ] **Step 5.4: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: add ShieldIconStrip HBox for shield icon row`.

---

## Task 6: HUD integration (both assault + open_space) + `mission_hud.gd` wiring

**Files:**
- Modify: `assault/scenes/gui/hud.tscn`
- Modify: `open_space/scenes/gui/hud.tscn`
- Modify: `global/ui/mission_hud.gd`

- [ ] **Step 6.1: Add `ShieldIconStrip` to `assault/scenes/gui/hud.tscn`**

Open the file. In the `[ext_resource]` block near the top, add (use any unused `id`, e.g. `10_strip`):

```
[ext_resource type="PackedScene" path="res://global/components/shield_icon_strip.tscn" id="10_strip"]
```

Then append a new node section after the `HealthShieldBar` node block (which currently ends with `offset_bottom = -8.0`):

```
[node name="ShieldIconStrip" parent="." instance=ExtResource("10_strip")]
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = -44.0
offset_right = 188.0
offset_bottom = -26.0
```

This places the strip 22 px above the health bar (health bar is at `offset_top = -22`, strip is at `offset_top = -44`).

- [ ] **Step 6.2: Add `ShieldIconStrip` to `open_space/scenes/gui/hud.tscn` AND shift the health bar down**

Open the file. In the `[ext_resource]` block, add:

```
[ext_resource type="PackedScene" path="res://global/components/shield_icon_strip.tscn" id="7_strip"]
```

Find the existing `HealthShieldBar` block:

```
[node name="HealthShieldBar" parent="." instance=ExtResource("2_hsbar")]
offset_left = 8.0
offset_top = 8.0
```

Replace with (shift it down to make room for the icon strip ABOVE it):

```
[node name="HealthShieldBar" parent="." instance=ExtResource("2_hsbar")]
offset_left = 8.0
offset_top = 28.0
```

Append a new node block (place it right after the `HealthShieldBar` block):

```
[node name="ShieldIconStrip" parent="." instance=ExtResource("7_strip")]
offset_left = 8.0
offset_top = 8.0
offset_right = 188.0
offset_bottom = 26.0
```

Now in open_space: strip at y=8..26, health bar at y=28..42.

- [ ] **Step 6.3: Wire `ShieldIconStrip` in `global/ui/mission_hud.gd`**

Add the `@onready` declaration. Find:

```gdscript
@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
```

Insert a new line directly below the first:

```gdscript
@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var shield_icon_strip: ShieldIconStrip = $ShieldIconStrip
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
```

Wire the setup call. Find the block left by Task 2.7:

```gdscript
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health:
		health_shield_bar.setup(health)
	## Shield icon strip wiring lives in Task 6.
```

Replace with:

```gdscript
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health:
		health_shield_bar.setup(health)
	if shield:
		shield_icon_strip.setup(shield)
```

- [ ] **Step 6.4: Verify icon strip appears and animates in the assault HUD**

Press **F5** and launch Level 1 (assault). Expected:
- One placeholder icon visible just above the health bar at bottom-left.
- Output panel shows the `[Shield] {"perm_active": 1, ...}` snapshot line at startup.

Move the player into an enemy bullet. Expected:
- The icon plays its `shield_destroy` animation (single frame with placeholder art) and stops on its last frame.
- Output: `[Shield] {"perm_active": 0, ...}`.
- No HP loss.

Wait 5 seconds clean. Expected:
- Output: `[Shield] {"perm_active": 1, ...}`.
- The icon plays `shield_recharge` then returns to `shield_idle`.

- [ ] **Step 6.5: Verify icon strip in the open_space HUD**

Stop and re-launch into the open-space scene (`open_space/scenes/levels/...` — pick whichever level loads cleanly). Confirm the icon appears at top-left, with the health bar directly below it. Take a hit (collide with an enemy or hazard if available); verify the same destroy animation behavior.

- [ ] **Step 6.6: Verify temp + permanent stacking**

While the assault game is running, open the **Debugger** → **Remote** → player → `ShieldComponent`. Use expression eval:

```
get_node("/root/Level1Scene/Player/ShieldComponent").add_temporary()
```
(Path may differ; use the Remote tree to find the exact path. Easier: select the `ShieldComponent` in Remote and use the Output's `RemoteCall` from inspector context.)

Expected: a second icon (using the `additional_shield_*` animation set) appears to the right of the permanent icon and plays its recharge animation.

Call `add_temporary()` four more times → five total icons (1 perm + 4 temp), with the most-recent temp on the right.

Call it once more (6th total). Expected: no new icon — `add_temporary()` returned false because `max_temporary = 5`.

Take a hit. Expected:
- The rightmost (most recent) temporary icon plays `additional_shield_destroy` and `queue_free`s.
- The permanent icon is untouched.
- Output: `[Shield] {"perm_active": 1, "temp_count": 4, ...}`.

This confirms consume order: temporary first.

- [ ] **Step 6.7: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: render shield icon strip in assault + open_space HUDs`.

---

## Task 7: Debug helpers + end-to-end persistence test

**Files:**
- Modify: `assault/scenes/player/debug_unlock_all.gd`

The existing `DebugUnlockAll` node lives on the player and is the conventional spot for ad-hoc dev hooks. Add three keyboard shortcuts: `Numpad+` adds a temporary shield, `Numpad-` consumes one (simulates a hit), `Numpad*` unlocks one more permanent shield slot. These are dev-only; we'll leave them in (gated by the same `DebugUnlockAll` node, which the user can remove from production scenes).

- [ ] **Step 7.1: Read `debug_unlock_all.gd` to understand the existing pattern**

Read `assault/scenes/player/debug_unlock_all.gd` in full. Note how it accesses the player (it's a child of `PlayerFighter`, so `get_parent()` gives the player). Adapt the new shortcuts to that pattern.

- [ ] **Step 7.2: Add shield debug shortcuts**

At the bottom of `debug_unlock_all.gd`, add an `_unhandled_input` handler if one doesn't already exist (otherwise extend the existing one). Insert:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var player := get_parent()
	var shield: Shield = player.get("shield_component") as Shield
	if shield == null:
		return
	match key.physical_keycode:
		KEY_KP_ADD:
			var added: bool = shield.add_temporary()
			print("[DebugUnlockAll] add_temporary() -> %s" % str(added))
		KEY_KP_SUBTRACT:
			var ate: bool = shield.consume_one()
			print("[DebugUnlockAll] consume_one() -> %s" % str(ate))
		KEY_KP_MULTIPLY:
			var added_perm: bool = ShipProgressionState.add_permanent_shield()
			print("[DebugUnlockAll] add_permanent_shield() -> %s (now %d)" \
					% [str(added_perm), ShipProgressionState.permanent_shield_count])
```

If `debug_unlock_all.gd` already has an `_unhandled_input` function, merge these `match` cases into the existing one rather than duplicating the function.

- [ ] **Step 7.3: Verify the shortcuts work end-to-end**

Press **F5** → assault Level 1. With focus on the game window:
- Press `Numpad+` → Output: `[DebugUnlockAll] add_temporary() -> true` and an additional-shield icon appears.
- Press `Numpad+` four more times → five additional icons.
- Press `Numpad+` once more → Output: `... -> false` and no new icon.
- Press `Numpad-` → Output: `[Shield] {"temp_count": 4, ...}` and the rightmost temp icon plays destroy.
- Press `Numpad-` four more times → all temps gone; one more press destroys the permanent.
- Wait 5 s clean → permanent regenerates.
- Press `Numpad*` → Output: `[DebugUnlockAll] add_permanent_shield() -> true (now 2)` and a new (empty-looking, since the existing perm icon represents slot 0) permanent slot is rebuilt with `_rebuild_permanent(2)`. Both slots animate the recharge as the active count fills in.

If the icon strip doesn't rebuild after `add_permanent_shield()`, verify `Shield._on_progression_changed` is connected (Task 2.1) and that `ShieldIconStrip._on_shield_state_changed` calls `_rebuild_permanent` when `perm_max` differs (Task 5.1).

- [ ] **Step 7.4: Persistence end-to-end**

With `permanent_shield_count` set to 2 from Step 7.3, stop the game. Press **F5** again. Expected: the strip starts with **two** permanent icons in idle (and zero temporaries). This confirms `ShipProgressionState` persisted through restart and `Shield._ready` honored the saved count.

Reset for the user via the debugger: `ShipProgressionState.set_permanent_shield_count(1)`. Stop. Confirm `user://ship_progression.cfg` shows the value `1`.

- [ ] **Step 7.5: ShieldOverloadModule full integration check**

In a fresh `F5` launch:
- Press `Numpad*` once → 2 permanent slots, both active after `_rebuild_permanent` + `_on_progression_changed` auto-fill.
- Press `Numpad+` twice → 2 temporary icons.
- Verify the strip shows: 2 permanents (left), 2 temporaries (right), 4 icons total in idle.
- Equip Shield Overload via the inspector: `ShipModuleState.equip(&"armor", &"shield_overload")`.
- Stand near (within 100 px of) an enemy. Press **H**.
- Expected: all four icons play destroy in unison; nearby enemy takes `4 × 25 = 100` damage; burst ring spawns.
- Output: ONE `[Shield] {"perm_active": 0, "temp_count": 0, ...}` line (snapshot is consolidated by `set_all_zero`, not four separate emits).

- [ ] **Step 7.6: Commit checkpoint**

Stop and let the user commit. Suggested message: `feat: add debug shortcuts for shield manual testing`.

---

## Final verification checklist

Run this once after all tasks complete:

- [ ] Project compiles with no warnings or errors (Project → Reload Current Project; check Output panel).
- [ ] `EventBus` no longer references `player_shield_changed`, `player_shield_depleted`, `player_shield_restored`.
- [ ] `Shield` no longer references `current_shield`, `max_shield`, `absorb`, `increase`, `set_shield`, `is_empty`, `shield_changed`, `shield_depleted`, `shield_restored`.
- [ ] `PlayerBase._on_shield_changed` and `_on_shield_depleted` are gone.
- [ ] `HealthShieldBar.tscn` has no `ShieldBar` node.
- [ ] `health_shield_bar.gd` `setup()` accepts only `Health`.
- [ ] Both assault and open_space HUDs show one placeholder shield icon at startup, positioned correctly (above health bar in assault, above health bar in open_space).
- [ ] Taking a hit consumes one shield charge instead of dropping HP.
- [ ] After 5 s of no damage, a permanent charge regenerates; the regen timer resets if a hit lands during the wait.
- [ ] `add_temporary()` is capped at 5; consume order is temporary-first; `set_all_zero()` drains everything in one snapshot.
- [ ] `ShipProgressionState.permanent_shield_count` survives an editor restart.
- [ ] Shield Overload module activates only when at least one shield is up, drains all, deals `count × 25` damage.

---

## Self-review notes

- **Spec coverage:** Section 1 (Shield rewrite) → Task 2. Section 2 (icons) → Tasks 3-5. Section 3 (HUD) → Tasks 2.5-2.8 + 6. Section 4 (Overload) → Task 2.4. Section 5 (autoload) → Task 1. Section 6 (file inventory) → File map at top. Section 7 (out of scope) → not implemented by design. Section 8 (testing) → manual steps in every task plus final checklist.
- **No placeholders:** every code-changing step shows the exact old → new diff or full file content.
- **Type/name consistency:** `consume_one`, `add_temporary`, `set_all_zero`, `restore_all_permanent`, `set_hacked`, snapshot keys (`perm_active`, `perm_max`, `temp_count`, `hacked`), `ShieldIcon.Tier.PERMANENT/TEMPORARY`, `Shield`, `ShieldIcon`, `ShieldIconStrip`, `ShipProgressionState` — all used identically across tasks.
- **Atomicity:** Task 2 is intentionally large because the data-layer swap can't be split without leaving the project uncompileable. Other tasks are independently testable.
