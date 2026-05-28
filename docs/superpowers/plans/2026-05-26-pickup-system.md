# Pickup System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add collectible pickup actors (Area2D scenes) for health, shields, temp buffs, and ship module unlocks, with optional one-line notification dialog.

**Architecture:** PickupBase (Area2D) detects player body_entered, calls overridden `_collect()`, optionally fires a dynamically-built dialog via DialogPlayer, then queue_frees. TempHealth is a new Node component on the player. TempDamage is fields+Timer on PlayerBase.

**Tech Stack:** GDScript 4.x with static types, existing DialogPlayer autoload, ShipModuleState autoload, ShipProgressionState autoload, Shield component.

---

## Task 1: TempHealth component + PlayerBase wiring

**Files:**
- Create: `res://global/components/temp_health_component.gd`
- Modify: `res://global/entities/player_base.gd`
- Modify: `res://assault/scenes/player/player_fighter.tscn`
- Modify: `res://open_space/scenes/entities/player/player_ship.tscn`

### Context

`PlayerBase` already has `health_component: Health` and `shield_component: Shield`. `_apply_damage` currently drains shield first, then health. We're adding a temp HP pool that sits between shield and regular health.

`max_health = 50` for both player ships. One temp stack = `50 / 2 = 25` HP. Cap = 5 stacks = 125 HP.

- [ ] **Step 1: Create `temp_health_component.gd`**

Create `res://global/components/temp_health_component.gd`:

```gdscript
# global/components/temp_health_component.gd
class_name TempHealth
extends Node

## Temporary HP pool. Sits between shield and regular health in the damage chain.
## Each "stack" adds base_health/2 HP, capped at MAX_STACKS stacks.
## Drains before regular health. Not regenerated.

const MAX_STACKS: int = 5

signal amount_changed(current: int, maximum: int)

var current_temp: int = 0
var _stack_hp: int = 0        ## value of one stack; set on first add_stack call

## Computed cap for external readers (HUD).
var max_temp: int:
	get: return MAX_STACKS * _stack_hp if _stack_hp > 0 else 0


## Add one temp stack of +base_health/2 HP. Returns false if already at cap.
func add_stack(base_health: int) -> bool:
	_stack_hp = maxi(1, base_health / 2)
	var cap: int = MAX_STACKS * _stack_hp
	if current_temp >= cap:
		return false
	current_temp = mini(current_temp + _stack_hp, cap)
	amount_changed.emit(current_temp, cap)
	return true


## Drains current_temp by amount. Returns overflow (damage that passes through to health).
func take_damage(amount: int) -> int:
	if current_temp <= 0:
		return amount
	var absorbed: int = mini(amount, current_temp)
	current_temp -= absorbed
	amount_changed.emit(current_temp, max_temp)
	return amount - absorbed
```

- [ ] **Step 2: Modify `player_base.gd` — add temp_health_component + temp damage buff**

Read `res://global/entities/player_base.gd` first.

Add after `var _thruster_right: ThrusterEffect = null`:
```gdscript
var temp_health_component: TempHealth = null

## Temporary damage boost (applied by temporary_damage_up pickup).
var _temp_damage_bonus: float = 0.0
var _temp_damage_timer: Timer = null
```

In `_setup_components()`, after the existing component assignments, add:
```gdscript
	temp_health_component = get_node_or_null("TempHealthComponent") as TempHealth
	_temp_damage_timer = Timer.new()
	_temp_damage_timer.one_shot = true
	_temp_damage_timer.timeout.connect(_on_temp_damage_expired)
	add_child(_temp_damage_timer)
```

Replace the existing `_apply_damage` function:
```gdscript
## damage_reduction intentionally applies ONLY when health takes the hit.
## Shields are binary (1 hit = 1 charge, regardless of damage), so reducing
## "damage" against a shield has no meaningful effect in the new model.
func _apply_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	if shield_component.consume_one():
		return                            ## one charge absorbed
	if temp_health_component and temp_health_component.current_temp > 0:
		effective = temp_health_component.take_damage(effective)
		if effective <= 0:
			return                        ## fully absorbed by temp HP
	health_component.decrease(effective)
```

Add at the bottom of the file:
```gdscript
## Called by temporary_damage_up pickup.
## bonus is the fractional increase (0.5 = +50%). duration is seconds.
## If a buff is already running, the old bonus is removed before applying the new one.
func apply_temp_damage_buff(bonus: float, duration: float) -> void:
	if _temp_damage_timer and not _temp_damage_timer.is_stopped():
		damage_multiplier -= _temp_damage_bonus
	_temp_damage_bonus = bonus
	damage_multiplier += bonus
	_temp_damage_timer.start(duration)


func _on_temp_damage_expired() -> void:
	damage_multiplier -= _temp_damage_bonus
	_temp_damage_bonus = 0.0
```

- [ ] **Step 3: Add TempHealthComponent node to `player_fighter.tscn`**

Read `res://assault/scenes/player/player_fighter.tscn`.

Add a new `[ext_resource]` entry for the TempHealth script. Add it after the last existing ext_resource. Example:

```
[ext_resource type="Script" path="res://global/components/temp_health_component.gd" id="16_tmphp"]
```

Add the node block after `[node name="OverheatComponent" ...]`:
```
[node name="TempHealthComponent" type="Node" parent="." unique_id=UNIQUE_ID]
script = ExtResource("16_tmphp")
```

Replace `UNIQUE_ID` with a random large integer (e.g. `1234567890`).

- [ ] **Step 4: Add TempHealthComponent node to `player_ship.tscn`**

Read `res://open_space/scenes/entities/player/player_ship.tscn`.

Add `[ext_resource]` entry for the TempHealth script:
```
[ext_resource type="Script" path="res://global/components/temp_health_component.gd" id="12_tmphp"]
```

Add the node block after `[node name="OverheatComponent" ...]`:
```
[node name="TempHealthComponent" type="Node" parent="." unique_id=UNIQUE_ID2]
script = ExtResource("12_tmphp")
```

Replace `UNIQUE_ID2` with a different random large integer (e.g. `9876543210`).

- [ ] **Step 5: Manual verification**

Run the game. Open Godot console. Add this to `player_fighter.gd`'s `_ready()` temporarily:
```gdscript
## TEMP TEST — remove after verifying
print("[TEST] temp_health_component: ", temp_health_component)
print("[TEST] max_health: ", health_component.max_health)
temp_health_component.add_stack(health_component.max_health)
print("[TEST] current_temp after 1 stack: ", temp_health_component.current_temp)
```

Expected output:
```
[TEST] temp_health_component: <TempHealth#...>
[TEST] max_health: 50
[TEST] current_temp after 1 stack: 25
```

Remove the temp test code. Confirm no errors in output.

- [ ] **Step 6: Commit**

Do NOT commit (user handles git).

---

## Task 2: PickupBase + silent pickups (health_tank, armor_tank)

**Files:**
- Create: `res://global/pickups/pickup_base.gd`
- Create: `res://global/pickups/health_tank_pickup.gd`
- Create: `res://global/pickups/armor_tank_pickup.gd`
- Create: `res://global/pickups/scenes/health_tank_pickup.tscn`
- Create: `res://global/pickups/scenes/armor_tank_pickup.tscn`

### Context

- Player CharacterBody2D is on `collision_layer = 4`.
- Pickup Area2D uses `collision_mask = 4` so `body_entered` fires when the player body enters.
- Player is in group `"player"`.
- `DialogPlayer` is a global autoload — call `DialogPlayer.play(script_res)` to show a notification.
- `pause_gameplay = false` so missions don't pause on pickup.
- No dialog for health_tank or armor_tank.

Sprite textures live in `res://global/assets/sprites/`. They are 2D pixel art — use `texture_filter = 1` (Nearest) on the Sprite2D.

- [ ] **Step 1: Create `pickup_base.gd`**

Create `res://global/pickups/pickup_base.gd`:

```gdscript
# global/pickups/pickup_base.gd
class_name PickupBase
extends Area2D

## Base class for all collectible pickups.
## Subclasses override _collect(player) and optionally _get_dialog_text().
## On body_entered: find player, collect, show dialog if text non-empty, queue_free.

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var player := body as PlayerBase
	if player == null:
		return
	_collect(player)
	var text: String = _get_dialog_text()
	if not text.is_empty():
		_show_notification(text)
	queue_free()


## Override: apply pickup effect to player.
func _collect(_player: PlayerBase) -> void:
	pass


## Override: return notification text, or "" for no dialog.
func _get_dialog_text() -> String:
	return ""


func _show_notification(text: String) -> void:
	var line := DialogLineResource.new()
	line.text = text
	line.side = DialogLineResource.Side.INNER_THOUGHT
	line.reveal = DialogLineResource.Reveal.INSTANT
	line.post_delay = 0.4
	var script_res := DialogScriptResource.new()
	script_res.lines = [line]
	script_res.pause_gameplay = false
	DialogPlayer.play(script_res)
```

- [ ] **Step 2: Create `health_tank_pickup.gd`**

Create `res://global/pickups/health_tank_pickup.gd`:

```gdscript
# global/pickups/health_tank_pickup.gd
class_name HealthTankPickup
extends PickupBase

const HEAL_AMOUNT: int = 40

func _collect(player: PlayerBase) -> void:
	if player.health_component:
		player.health_component.increase(HEAL_AMOUNT)

func _get_dialog_text() -> String:
	return ""
```

- [ ] **Step 3: Create `armor_tank_pickup.gd`**

Create `res://global/pickups/armor_tank_pickup.gd`:

```gdscript
# global/pickups/armor_tank_pickup.gd
class_name ArmorTankPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.shield_component:
		player.shield_component.restore_all_permanent()

func _get_dialog_text() -> String:
	return ""
```

- [ ] **Step 4: Create `health_tank_pickup.tscn`**

Create `res://global/pickups/scenes/health_tank_pickup.tscn`:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/health_tank_pickup.gd" id="1_htp"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/health_tank.png" id="2_htp"]

[sub_resource type="CircleShape2D" id="CircleShape2D_htp"]
radius = 8.0

[node name="HealthTankPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_htp")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_htp")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_htp")
```

- [ ] **Step 5: Create `armor_tank_pickup.tscn`**

Create `res://global/pickups/scenes/armor_tank_pickup.tscn`:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/armor_tank_pickup.gd" id="1_atp"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/armor_tank.png" id="2_atp"]

[sub_resource type="CircleShape2D" id="CircleShape2D_atp"]
radius = 8.0

[node name="ArmorTankPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_atp")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_atp")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_atp")
```

- [ ] **Step 6: Drop pickup into level and test**

Open `res://assault/scenes/levels/level_1.tscn` (or equivalent test scene). Instance `health_tank_pickup.tscn` near the player start. Run the game. Fly into it. Verify:
- Health increases (check HUD health bar)
- Pickup disappears
- No dialog appears
- No errors in output

Do the same for `armor_tank_pickup.tscn` — fly into it with a depleted shield, verify shield bar refills, no dialog.

---

## Task 3: Dialog pickups (6 types)

**Files:**
- Create: `res://global/pickups/ship_shield_up_pickup.gd`
- Create: `res://global/pickups/temporary_shield_up_pickup.gd`
- Create: `res://global/pickups/armor_and_health_pickup.gd`
- Create: `res://global/pickups/temporary_health_up_pickup.gd`
- Create: `res://global/pickups/temporary_health_shield_up_pickup.gd`
- Create: `res://global/pickups/temporary_damage_up_pickup.gd`
- Create: `res://global/pickups/scenes/ship_shield_up_pickup.tscn`
- Create: `res://global/pickups/scenes/temporary_shield_up_pickup.tscn`
- Create: `res://global/pickups/scenes/armor_and_health_pickup.tscn`
- Create: `res://global/pickups/scenes/temporary_health_up_pickup.tscn`
- Create: `res://global/pickups/scenes/temporary_health_shield_up_pickup.tscn`
- Create: `res://global/pickups/scenes/temporary_damage_up_pickup.tscn`

### Context

- `ShipProgressionState.add_permanent_shield()` returns false if already at max (5). The shield slot is unlocked AND active immediately (ShieldComponent's `_on_progression_changed` auto-fills new slots).
- `shield.add_temporary()` returns false if at cap (5).
- `temp_health_component.add_stack(base_health)` uses `player.health_component.max_health` as base.
- `apply_temp_damage_buff(0.5, 15.0)` → +50% damage for 15 seconds.
- `TEMP_DAMAGE_DURATION = 15.0` seconds.

- [ ] **Step 1: Create the 6 pickup scripts**

Create `res://global/pickups/ship_shield_up_pickup.gd`:
```gdscript
# global/pickups/ship_shield_up_pickup.gd
class_name ShipShieldUpPickup
extends PickupBase

func _collect(_player: PlayerBase) -> void:
	ShipProgressionState.add_permanent_shield()

func _get_dialog_text() -> String:
	return "Permanent shield slot unlocked!"
```

Create `res://global/pickups/temporary_shield_up_pickup.gd`:
```gdscript
# global/pickups/temporary_shield_up_pickup.gd
class_name TemporaryShieldUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.shield_component:
		player.shield_component.add_temporary()

func _get_dialog_text() -> String:
	return "Temporary shield restored!"
```

Create `res://global/pickups/armor_and_health_pickup.gd`:
```gdscript
# global/pickups/armor_and_health_pickup.gd
class_name ArmorAndHealthPickup
extends PickupBase

const HEAL_AMOUNT: int = 40

func _collect(player: PlayerBase) -> void:
	if player.health_component:
		player.health_component.increase(HEAL_AMOUNT)
	if player.shield_component:
		player.shield_component.restore_all_permanent()

func _get_dialog_text() -> String:
	return "Hull and shields restored!"
```

Create `res://global/pickups/temporary_health_up_pickup.gd`:
```gdscript
# global/pickups/temporary_health_up_pickup.gd
class_name TemporaryHealthUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.temp_health_component and player.health_component:
		player.temp_health_component.add_stack(player.health_component.max_health)

func _get_dialog_text() -> String:
	return "Emergency hull reinforcement active!"
```

Create `res://global/pickups/temporary_health_shield_up_pickup.gd`:
```gdscript
# global/pickups/temporary_health_shield_up_pickup.gd
class_name TemporaryHealthShieldUpPickup
extends PickupBase

func _collect(player: PlayerBase) -> void:
	if player.temp_health_component and player.health_component:
		player.temp_health_component.add_stack(player.health_component.max_health)
	if player.shield_component:
		player.shield_component.add_temporary()

func _get_dialog_text() -> String:
	return "Combat stims active! Hull and shields reinforced!"
```

Create `res://global/pickups/temporary_damage_up_pickup.gd`:
```gdscript
# global/pickups/temporary_damage_up_pickup.gd
class_name TemporaryDamageUpPickup
extends PickupBase

const DAMAGE_BONUS: float = 0.5
const DURATION_SEC: float = 15.0

func _collect(player: PlayerBase) -> void:
	player.apply_temp_damage_buff(DAMAGE_BONUS, DURATION_SEC)

func _get_dialog_text() -> String:
	return "Weapon output overcharged!"
```

- [ ] **Step 2: Create the 6 pickup scenes**

Create `res://global/pickups/scenes/ship_shield_up_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/ship_shield_up_pickup.gd" id="1_ssu"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/ship_shield_up.png" id="2_ssu"]

[sub_resource type="CircleShape2D" id="CircleShape2D_ssu"]
radius = 8.0

[node name="ShipShieldUpPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_ssu")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_ssu")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_ssu")
```

Create `res://global/pickups/scenes/temporary_shield_up_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/temporary_shield_up_pickup.gd" id="1_tsu"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/temporary_shield_up.png" id="2_tsu"]

[sub_resource type="CircleShape2D" id="CircleShape2D_tsu"]
radius = 8.0

[node name="TemporaryShieldUpPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_tsu")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_tsu")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_tsu")
```

Create `res://global/pickups/scenes/armor_and_health_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/armor_and_health_pickup.gd" id="1_aah"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/armor_and_health.png" id="2_aah"]

[sub_resource type="CircleShape2D" id="CircleShape2D_aah"]
radius = 8.0

[node name="ArmorAndHealthPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_aah")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_aah")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_aah")
```

Create `res://global/pickups/scenes/temporary_health_up_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/temporary_health_up_pickup.gd" id="1_thu"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/temporary_health_up.png" id="2_thu"]

[sub_resource type="CircleShape2D" id="CircleShape2D_thu"]
radius = 8.0

[node name="TemporaryHealthUpPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_thu")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_thu")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_thu")
```

Create `res://global/pickups/scenes/temporary_health_shield_up_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/temporary_health_shield_up_pickup.gd" id="1_ths"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/temporary_health_shield_up.png" id="2_ths"]

[sub_resource type="CircleShape2D" id="CircleShape2D_ths"]
radius = 8.0

[node name="TemporaryHealthShieldUpPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_ths")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_ths")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_ths")
```

Create `res://global/pickups/scenes/temporary_damage_up_pickup.tscn`:
```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/temporary_damage_up_pickup.gd" id="1_tdu"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/temporary_damage_up.png" id="2_tdu"]

[sub_resource type="CircleShape2D" id="CircleShape2D_tdu"]
radius = 8.0

[node name="TemporaryDamageUpPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_tdu")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_tdu")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_tdu")
```

- [ ] **Step 3: Test dialog pickups**

Drop one of each into the test level. Run and verify:

**ship_shield_up_pickup**: Fly into it when at max shields (5) — nothing happens, dialog still shows "Permanent shield slot unlocked!" (add_permanent_shield returns false silently). At fewer than 5 shields, shield count increases by 1.

**temporary_shield_up_pickup**: Fly into it — a temp shield icon appears in the HUD strip. Dialog shows "Temporary shield restored!". At cap (5 temp), nothing visible changes.

**armor_and_health_pickup**: Take 20 damage, drain a shield charge, then fly into it — both health and shield restore. Dialog shows "Hull and shields restored!".

**temporary_health_up_pickup**: Fly into it — temp health bar appears (see Task 5 for HUD). Dialog shows "Emergency hull reinforcement active!".

**temporary_damage_up_pickup**: Fly into it — shoot an enemy, damage numbers should be 50% higher. After 15 seconds, damage returns to normal. Dialog shows "Weapon output overcharged!".

---

## Task 4: Ship module unlocker pickup

**Files:**
- Create: `res://global/pickups/ship_module_unlocker_pickup.gd`
- Create: `res://global/pickups/scenes/ship_module_unlocker_pickup.tscn`

### Context

`ShipModuleState.equip(slot, module_id)` persists the equipped module to disk and emits `module_equipped`. `ShipModuleBase.create(id).get_display_name()` returns a human-readable name.

Module slots: `"cockpit"`, `"armor"`, `"weapons"`, `"engines"`.

Each module unlocker in a level is the same scene, just with different `module_slot` and `module_id` exports set in the editor inspector.

- [ ] **Step 1: Create `ship_module_unlocker_pickup.gd`**

Create `res://global/pickups/ship_module_unlocker_pickup.gd`:

```gdscript
# global/pickups/ship_module_unlocker_pickup.gd
class_name ShipModuleUnlockerPickup
extends PickupBase

## Set in the editor inspector for each placed pickup instance.
@export var module_slot: StringName = &""
@export var module_id: StringName = &""

func _collect(_player: PlayerBase) -> void:
	if module_slot.is_empty() or module_id.is_empty():
		push_warning("ShipModuleUnlockerPickup: module_slot or module_id not set.")
		return
	ShipModuleState.equip(module_slot, module_id)


func _get_dialog_text() -> String:
	if module_id.is_empty():
		return "Module acquired!"
	var module := ShipModuleBase.create(module_id)
	if module == null:
		return "Module acquired!"
	return "%s module acquired!" % module.get_display_name()
```

- [ ] **Step 2: Create `ship_module_unlocker_pickup.tscn`**

Create `res://global/pickups/scenes/ship_module_unlocker_pickup.tscn`:

```
[gd_scene format=3]

[ext_resource type="Script" path="res://global/pickups/ship_module_unlocker_pickup.gd" id="1_smu"]
[ext_resource type="Texture2D" path="res://global/assets/sprites/ship_module_unlocker.png" id="2_smu"]

[sub_resource type="CircleShape2D" id="CircleShape2D_smu"]
radius = 8.0

[node name="ShipModuleUnlockerPickup" type="Area2D"]
collision_layer = 16
collision_mask = 4
script = ExtResource("1_smu")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture_filter = 1
texture = ExtResource("2_smu")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_smu")
```

- [ ] **Step 3: Test module unlocker**

Instance `ship_module_unlocker_pickup.tscn` in the test level. In the inspector, set `module_slot = "armor"` and `module_id = "shield_overload"`.

Run the game. Fly into the pickup. Verify:
- Dialog shows: "Shield Overload module acquired!" (or whatever `ShieldOverloadModule.get_display_name()` returns)
- The module is now equipped in the armor slot (verify via `ShipModuleState.get_equipped("armor")` in console or player menu)
- Pickup disappears

Test with an unknown module_id — verify push_warning fires and pickup still disappears.

---

## Task 5: HUD — Temp Health Bar

**Files:**
- Modify: `res://assault/scenes/gui/health_shield_bar.gd`
- Modify: `res://assault/scenes/gui/health_shield_bar.tscn`
- Modify: `res://global/ui/mission_hud.gd`

### Context

Current `health_shield_bar.tscn` has one `ProgressBar` called `HealthBar`. We add a second `ProgressBar` called `TempHealthBar` stacked on top (same size, different color). It's hidden when `current_temp == 0`.

`mission_hud.gd` calls `health_shield_bar.setup(health)`. We extend it to also accept an optional `TempHealth` component.

`health_shield_bar.tscn` is used in both assault and open_space HUDs — both benefit automatically since they instance the same scene.

- [ ] **Step 1: Add TempHealthBar to `health_shield_bar.tscn`**

Read `res://assault/scenes/gui/health_shield_bar.tscn`.

The scene currently has: root `Control`, child `HealthBar ProgressBar`.

Replace the file with this content:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/gui/health_shield_bar.gd" id="1_hsbar"]

[node name="HealthShieldBar" type="Control"]
custom_minimum_size = Vector2(150, 14)
script = ExtResource("1_hsbar")

[node name="HealthBar" type="ProgressBar" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
min_value = 0.0
max_value = 50.0
value = 50.0

[node name="TempHealthBar" type="ProgressBar" parent="."]
anchor_right = 1.0
anchor_bottom = 1.0
min_value = 0.0
max_value = 125.0
value = 0.0
visible = false
modulate = Color(0.4, 0.9, 1.0, 0.85)
```

- [ ] **Step 2: Update `health_shield_bar.gd`**

Replace `res://assault/scenes/gui/health_shield_bar.gd` with:

```gdscript
# assault/scenes/gui/health_shield_bar.gd
class_name HealthShieldBar
extends Control

## Displays the player's health as a ProgressBar.
## Optionally shows a TempHealthBar overlay when temporary HP is present.

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _temp_bar: ProgressBar = $TempHealthBar


func setup(health: Health, temp_health: TempHealth = null) -> void:
	_health_bar.max_value = health.max_health
	_health_bar.value = health.current_health
	health.amount_changed.connect(_on_health_changed)

	if temp_health:
		_temp_bar.max_value = temp_health.max_temp if temp_health.max_temp > 0 else 1
		_temp_bar.value = temp_health.current_temp
		_temp_bar.visible = temp_health.current_temp > 0
		temp_health.amount_changed.connect(_on_temp_health_changed)


func _on_health_changed(current: int) -> void:
	_health_bar.value = current


func _on_temp_health_changed(current: int, maximum: int) -> void:
	_temp_bar.max_value = maximum if maximum > 0 else 1
	_temp_bar.value = current
	_temp_bar.visible = current > 0
```

- [ ] **Step 3: Update `mission_hud.gd`**

Read `res://global/ui/mission_hud.gd`.

Find the line that calls `health_shield_bar.setup(health)` and replace it with:

```gdscript
	var temp_health: TempHealth = player.get_node_or_null("TempHealthComponent") as TempHealth
	health_shield_bar.setup(health, temp_health)
```

- [ ] **Step 4: Test temp health HUD**

Drop a `temporary_health_up_pickup.tscn` into the test level. Run the game.

Before pickup: only the regular health bar is visible.
After pickup: a second bar appears in a blue/cyan tint above/overlapping the health bar.
Take damage: if temp HP > 0, it drains first (temp bar shrinks). Regular health bar stays full until temp depletes.
After all temp HP is gone: temp bar disappears.
Pick up a second stack: temp bar refills by 25.

---

## Task 6: Cleanup — remove `unlock_all()` from UpgradeState

**Files:**
- Modify: `res://global/autoloads/upgrade_state.gd`

### Context

`upgrade_state.gd` has a `TODO(dev)` in `_ready()` that calls `unlock_all()` on every startup, giving all weapons. Now that pickups are the unlock path, this debug call should be removed.

- [ ] **Step 1: Remove the unlock_all call from `_ready()`**

Read `res://global/autoloads/upgrade_state.gd`.

In `_ready()`, remove these lines:
```gdscript
	# ============================================================
	# TODO(dev): UNLOCK ALL — remove before shipping!
	# Gives every weapon immediately so the menu can be tested.
	# ============================================================
	unlock_all()
```

The final `_ready()` should be:
```gdscript
func _ready() -> void:
	_load()
	if _unlocked.is_empty():
		_unlocked[&"default"] = true
		_save()
```

- [ ] **Step 2: Verify**

Run the game. In the player menu, only the default weapon should be available (not all weapons). Confirm no errors.

Note: if the save file `user://upgrades.cfg` already has all weapons unlocked from previous sessions, clear it or test in a fresh user data directory.
