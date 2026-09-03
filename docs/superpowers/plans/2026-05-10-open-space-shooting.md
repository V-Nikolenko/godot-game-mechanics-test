# Open-Space Shooting System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the full assault shooting pipeline (WeaponState + RocketState + all weapon modes + overheat) into the open-space player ship, with a matching HUD weapon display.

**Architecture:** Re-use assault's `WeaponState`, `RocketState`, `MovementController`, and all behavior/mode scripts verbatim — they have no assault-scene coupling. The open-space player tscn gets the same `AttackStateMachine → WeaponState / WarheadMissileShootingState` subtree and a `MovementController` node. `player_ship.gd` loses its inline `_handle_shoot()` and gains `can_attack` wired to a new `OverheatComponent`. The open-space HUD gets `WeaponContainer` (sub-weapon icon + cooldown) and `WeaponChip` (current main weapon display) nodes, and its script is updated to mirror the assault HUD.

**Tech Stack:** Godot 4.6 · GDScript · existing `WeaponState` / `RocketState` / `MovementController` scripts · existing assault projectile scenes

---

## File Map

| File | Change |
|------|--------|
| `open_space/scenes/entities/player/player_ship.tscn` | Add `OverheatComponent`, `AttackStateMachine` subtree, `MovementController` subtree; update `AbilityController` exports |
| `open_space/scenes/entities/player/player_ship.gd` | Add `can_attack` + overheat wiring; remove inline `_handle_shoot()` and its vars |
| `open_space/scenes/gui/hud.tscn` | Add `WeaponContainer` subtree and `WeaponChip` instance |
| `open_space/scenes/gui/hud.gd` | Mirror assault HUD: wire `RocketState`, `WeaponState`, cooldown overlay |

**Scripts used as-is (no changes needed):**
- `assault/scenes/player/states/weapon_state.gd`
- `assault/scenes/player/states/warhead_missile_shooting_state.gd`
- `assault/scenes/player/movement_controller.gd`
- `assault/scenes/player/weapons/behaviors/*.gd` (all five)
- `assault/scenes/player/weapons/modes/*.tres` (all six)
- `global/statemachine/state_machine.gd`
- `global/components/overheat_component.gd`

---

### Task 1: Wire combat nodes into player_ship.tscn

**Files:**
- Rewrite: `open_space/scenes/entities/player/player_ship.tscn`

**Context:** The assault player (player_fighter.tscn) has this combat subtree:
- `OverheatComponent` — `global/components/overheat_component.gd`
- `AttackStateMachine` — `global/statemachine/state_machine.gd`, `initial_state = WeaponState`
  - `WeaponState` — `assault/scenes/player/states/weapon_state.gd`, exports: `actor`, `weapon_muzzles`, `movement_controller`, `heat_component`
  - `WarheadMissileShootingState` — `assault/scenes/player/states/warhead_missile_shooting_state.gd`, exports: `actor`, `movement_controller`
    - `CooldownTimer` — Timer, `wait_time=5.0`, `one_shot=true`
- `MovementController` — `assault/scenes/player/movement_controller.gd`
  - `DoubleClickThreshold` — Timer, `wait_time=0.3`, `one_shot=true`
  - `MovementLockTimer` — Timer, `one_shot=true`

The open-space ship already has `SpriteAnchor/MuzzleLeft` and `SpriteAnchor/MuzzleRight` at the same positions as the assault fighter — they are usable directly as `weapon_muzzles`.

- [ ] **Step 1: Write the complete new player_ship.tscn**

Write this exact content to `open_space/scenes/entities/player/player_ship.tscn`:

```
[gd_scene load_steps=16 format=3]

[ext_resource type="Script" path="res://open_space/scenes/entities/player/player_ship.gd" id="1_ship"]
[ext_resource type="Texture2D" uid="uid://dbd7dsu05uan4" path="res://assault/assets/sprites/player/h_assault_fighter.png" id="2_atlas"]
[ext_resource type="Script" path="res://global/components/health_component.gd" id="3_health"]
[ext_resource type="Script" path="res://global/components/hurtbox_component.gd" id="4_hurt"]
[ext_resource type="Script" path="res://global/components/shield_component.gd" id="5_shld"]
[ext_resource type="Script" path="res://global/abilities/ability_controller.gd" id="6_abctl"]
[ext_resource type="Script" uid="uid://coqfv3aco6d8i" path="res://global/components/overheat_component.gd" id="7_oheat"]
[ext_resource type="Script" uid="uid://c5678cxr4wb7q" path="res://global/statemachine/state_machine.gd" id="8_sm"]
[ext_resource type="Script" path="res://assault/scenes/player/states/weapon_state.gd" id="9_ws"]
[ext_resource type="Script" uid="uid://biyvn45plxdd2" path="res://assault/scenes/player/states/warhead_missile_shooting_state.gd" id="10_rs"]
[ext_resource type="Script" uid="uid://cdfmqrq3idtak" path="res://assault/scenes/player/movement_controller.gd" id="11_mc"]

[sub_resource type="AtlasTexture" id="AtlasTexture_idle"]
atlas = ExtResource("2_atlas")
region = Rect2(1, 1, 32, 32)

[sub_resource type="SpriteFrames" id="SpriteFrames_ship"]
animations = [{
"frames": [{
"duration": 1.0,
"texture": SubResource("AtlasTexture_idle")
}],
"loop": true,
"name": &"idle",
"speed": 5.0
}]

[sub_resource type="CircleShape2D" id="CircleShape2D_body"]
radius = 5.5

[sub_resource type="CircleShape2D" id="CircleShape2D_hurt"]
radius = 5.0

[node name="PlayerShip" type="CharacterBody2D"]
collision_layer = 4
collision_mask = 1
script = ExtResource("1_ship")

[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("3_health")
max_health = 50
current_health = 50

[node name="ShieldComponent" type="Node" parent="."]
script = ExtResource("5_shld")
max_shield = 100
current_shield = 100

[node name="OverheatComponent" type="Node" parent="."]
script = ExtResource("7_oheat")

[node name="SpriteAnchor" type="Node2D" parent="."]

[node name="ShipSprite2D" type="AnimatedSprite2D" parent="SpriteAnchor"]
texture_filter = 1
sprite_frames = SubResource("SpriteFrames_ship")
animation = &"idle"

[node name="MuzzleLeft" type="Marker2D" parent="SpriteAnchor"]
position = Vector2(-11, 0)

[node name="MuzzleRight" type="Marker2D" parent="SpriteAnchor"]
position = Vector2(11, 0)

[node name="Collision" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_body")

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 128
collision_mask = 1281
script = ExtResource("4_hurt")

[node name="HurtBoxCollision" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("CircleShape2D_hurt")

[node name="AttackStateMachine" type="Node" parent="." node_paths=PackedStringArray("initial_state")]
script = ExtResource("8_sm")
initial_state = NodePath("WeaponState")

[node name="WeaponState" type="Node" parent="AttackStateMachine" node_paths=PackedStringArray("actor", "weapon_muzzles", "movement_controller", "heat_component")]
script = ExtResource("9_ws")
actor = NodePath("../..")
weapon_muzzles = [NodePath("../../SpriteAnchor/MuzzleLeft"), NodePath("../../SpriteAnchor/MuzzleRight")]
movement_controller = NodePath("../../MovementController")
heat_component = NodePath("../../OverheatComponent")

[node name="WarheadMissileShootingState" type="Node" parent="AttackStateMachine" node_paths=PackedStringArray("actor", "movement_controller")]
script = ExtResource("10_rs")
actor = NodePath("../..")
movement_controller = NodePath("../../MovementController")

[node name="CooldownTimer" type="Timer" parent="AttackStateMachine/WarheadMissileShootingState"]
wait_time = 5.0
one_shot = true

[node name="MovementController" type="Node" parent="."]
script = ExtResource("11_mc")

[node name="DoubleClickThreshold" type="Timer" parent="MovementController"]
wait_time = 0.3
one_shot = true

[node name="MovementLockTimer" type="Timer" parent="MovementController"]
one_shot = true

[node name="AbilityController" type="Node" parent="." node_paths=PackedStringArray("actor", "health", "shield", "overheat")]
script = ExtResource("6_abctl")
actor = NodePath("..")
health = NodePath("../HealthComponent")
shield = NodePath("../ShieldComponent")
overheat = NodePath("../OverheatComponent")

[connection signal="received_damage" from="HurtBox" to="." method="_on_received_damage"]
[connection signal="timeout" from="AttackStateMachine/WarheadMissileShootingState/CooldownTimer" to="AttackStateMachine/WarheadMissileShootingState" method="_on_cooldown_timer_timeout"]
[connection signal="timeout" from="MovementController/DoubleClickThreshold" to="MovementController" method="_on_double_click_threshold_timeout"]
[connection signal="timeout" from="MovementController/MovementLockTimer" to="MovementController" method="_on_movement_lock_timer_timeout"]
```

- [ ] **Step 2: Open Godot and verify no scene errors**

Open the Godot editor. Open the player_ship.tscn scene. Verify:
- No "node not found" errors in the Output panel
- The scene tree shows: `PlayerShip → OverheatComponent`, `AttackStateMachine → WeaponState, WarheadMissileShootingState → CooldownTimer`, `MovementController → DoubleClickThreshold, MovementLockTimer`
- Inspector for WeaponState shows actor, weapon_muzzles (2 entries), movement_controller, heat_component all assigned

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/entities/player/player_ship.tscn
git commit -m "feat: add AttackStateMachine + MovementController to open-space player"
```

---

### Task 2: Update player_ship.gd — remove inline shoot, add can_attack + overheat

**Files:**
- Modify: `open_space/scenes/entities/player/player_ship.gd`

**Context:** The inline `_handle_shoot()` method and its variables (`shoot_cooldown_sec`, `bullet_scene`, `_shoot_cooldown`, `_gun_index`) are no longer needed — `WeaponState` handles all firing. The `muzzle_left` / `muzzle_right` onready vars are only used by `_handle_shoot()` so they can be removed from the script too (the nodes stay in the scene and are referenced by WeaponState via NodePath). `can_attack` must be added as a `bool` variable so `WeaponState` can gate firing. `OverheatComponent` must be wired so it drives `can_attack`.

- [ ] **Step 1: Rewrite player_ship.gd**

Write this exact content to `open_space/scenes/entities/player/player_ship.gd`:

```gdscript
class_name OpenSpacePlayerShip
extends CharacterBody2D

@export_category("Movement")
@export var rotation_speed_deg: float = 220.0
@export var thrust_acceleration: float = 380.0
@export var reverse_acceleration: float = 220.0
@export var max_speed: float = 420.0
@export var damping: float = 0.6

@export_category("Boost")
@export var boost_redirect_speed: float = 200.0
@export var boost_duration_sec: float = 0.3
@export var boost_speed_threshold: float = 180.0

@onready var health_component: Health = $HealthComponent
@onready var shield_component: Shield = $ShieldComponent
@onready var overheat_component: Overheat = $OverheatComponent

## Multipliers written by AbilityController / abilities.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
var overdrive_active: bool = false
## 0.0 = no reduction; 0.5 = take 50% damage. Written by ArmorPlatingAbility.
var damage_reduction: float = 0.0

## Gated by OverheatComponent — false when heat reaches 100%, restored below 80%.
var can_attack: bool = true

var _boost_timer: float = 0.0

var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect
var _thruster: ThrusterEffect

func _ready() -> void:
	add_to_group("player")
	health_component.amount_changed.connect(_on_health_changed)
	overheat_component.overheat.connect(_on_overheat_updated)
	_setup_effects()
	rotation = 0.0

func _setup_effects() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_thrust(delta)
	move_and_slide()

func _handle_rotation(delta: float) -> void:
	var turn: float = 0.0
	if Input.is_action_pressed("move_left"):
		turn -= 1.0
	if Input.is_action_pressed("move_right"):
		turn += 1.0
	rotation += deg_to_rad(rotation_speed_deg) * turn * delta

func _handle_thrust(delta: float) -> void:
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	var thrust_input: float = 0.0
	if Input.is_action_pressed("move_up"):
		thrust_input += 1.0
	if Input.is_action_pressed("move_down"):
		thrust_input -= 1.0

	_boost_timer = max(_boost_timer - delta, 0.0)

	if Input.is_action_just_pressed("move_up") and _boost_timer <= 0.0:
		var backward_speed := -velocity.dot(forward)
		if backward_speed >= boost_speed_threshold:
			_trigger_flip_boost(forward)

	if thrust_input > 0.0:
		velocity += forward * thrust_acceleration * delta
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.THRUST)
	elif thrust_input < 0.0:
		velocity -= forward * reverse_acceleration * delta
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
		_thruster.set_state(
				ThrusterEffect.State.BOOST if _boost_timer > 0.0
				else ThrusterEffect.State.IDLE)

	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed

func _trigger_flip_boost(forward: Vector2) -> void:
	velocity = forward * boost_redirect_speed
	_boost_timer = boost_duration_sec

## Called by OverheatComponent every 0.1 s with the current heat percentage (0–100).
func _on_overheat_updated(pct: float) -> void:
	can_attack = pct < 100.0

func _on_received_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	var overflow := shield_component.absorb(effective)
	if overflow > 0:
		health_component.decrease(overflow)
	_hit_effect.burst()

func _on_health_changed(current: int) -> void:
	if current == 0:
		_explosion_effect.explode()
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			get_tree().reload_current_scene()
```

- [ ] **Step 2: Open Godot and verify no script errors**

Open Godot. The Output panel should show zero GDScript errors for `player_ship.gd`. In particular, confirm `OverheatComponent` resolves correctly (it's now an onready).

- [ ] **Step 3: Commit**

```bash
git add open_space/scenes/entities/player/player_ship.gd
git commit -m "feat: wire WeaponState/overheat into open-space player, remove inline shoot"
```

---

### Task 3: Add weapon display to open-space HUD

**Files:**
- Modify: `open_space/scenes/gui/hud.tscn`
- Modify: `open_space/scenes/gui/hud.gd`

**Context:** The assault HUD (`assault/scenes/gui/hud.tscn` / `hud.gd`) has:
- `WeaponContainer` (Control, bottom-left anchor) — shows the currently selected **sub-weapon** icon with a cooldown fill overlay and a decorative frame
- `WeaponChip` (instance of `assault/scenes/gui/weapon_chip.tscn`) — shows the current **main weapon** name/icon chip

The open-space HUD currently has only `HealthShieldBar` and `PlayerMenu`. Both WeaponContainer and WeaponChip must be added. The hud.gd must be rewritten to mirror the assault version: find the player, get `AttackStateMachine/WeaponState` and `AttackStateMachine/WarheadMissileShootingState`, wire weapon icon + cooldown overlay + PlayerMenu.

- [ ] **Step 1: Read the current open_space HUD tscn to understand its structure**

Read `open_space/scenes/gui/hud.tscn` and `assault/scenes/gui/hud.tscn` fully. Note the exact UIDs and resource IDs used in the assault HUD for: `frame_center.png`, `weapon_chip.tscn`, the `WeaponContainer` node properties (anchor values, offsets).

- [ ] **Step 2: Rewrite open_space/scenes/gui/hud.tscn**

Write the following content to `open_space/scenes/gui/hud.tscn`. This mirrors the assault HUD structure: adds `WeaponContainer` subtree and `WeaponChip` instance. Copy exact UIDs from the assault hud.tscn for shared resources.

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://open_space/scenes/gui/hud.gd" id="1_oshud"]
[ext_resource type="PackedScene" path="res://assault/scenes/gui/health_shield_bar.tscn" id="2_hsbar"]
[ext_resource type="PackedScene" uid="uid://d3w5o2bii2h1" path="res://dialog/ui/playermenu/player_menu.tscn" id="3_pmenu"]
[ext_resource type="Texture2D" uid="uid://cnap6cceg8u6t" path="res://assault/assets/gui/weaponselector/frame_center.png" id="4_frame"]
[ext_resource type="PackedScene" path="res://assault/scenes/gui/weapon_chip.tscn" id="5_wchip"]

[node name="OpenSpaceHUD" type="CanvasLayer"]
script = ExtResource("1_oshud")

[node name="WeaponContainer" type="Control" parent="."]
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 10.0
offset_top = -76.0
offset_right = 50.0
offset_bottom = -36.0
clip_contents = true

[node name="WeaponIcon" type="TextureRect" parent="WeaponContainer"]
anchor_right = 1.0
anchor_bottom = 1.0
stretch_mode = 5

[node name="CooldownOverlay" type="ColorRect" parent="WeaponContainer"]
color = Color(0.15, 0.15, 0.15, 0.65)
size = Vector2(40, 40)
visible = false

[node name="WeaponFrame" type="TextureRect" parent="WeaponContainer"]
anchor_right = 1.0
anchor_bottom = 1.0
texture = ExtResource("4_frame")
stretch_mode = 5

[node name="HealthShieldBar" parent="." instance=ExtResource("2_hsbar")]
offset_left = 8.0
offset_top = 8.0

[node name="WeaponChip" parent="." instance=ExtResource("5_wchip")]
offset_left = 8.0
offset_top = 48.0

[node name="PlayerMenu" parent="." instance=ExtResource("3_pmenu")]
```

- [ ] **Step 3: Rewrite open_space/scenes/gui/hud.gd**

Write this exact content to `open_space/scenes/gui/hud.gd`:

```gdscript
# open_space/scenes/gui/hud.gd
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var weapon_icon: TextureRect = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay
@onready var player_menu: PlayerMenu = $PlayerMenu

var _cooldown_timer: Timer = null

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

- [ ] **Step 4: Verify in Godot**

Open the Godot editor. Open `open_space/scenes/gui/hud.tscn`. Confirm:
- `WeaponContainer` and its three children appear in the scene tree
- `WeaponChip` instance resolves (no "can't instance" error)
- No GDScript errors in `hud.gd`

Run the open-space scene and confirm:
1. Pressing **J** (or left-click) fires bullets from the ship's current facing direction
2. Pressing **E** cycles through weapon modes (default → long_range → piercing → spread → gatling → mining_laser)
3. Pressing **Q** switches sub-weapon between Missiles Barrage and Homing Missile; the weapon icon in the HUD updates
4. Pressing **K** launches the selected sub-weapon (5-second cooldown; cooldown overlay animates)
5. Sustained firing eventually blocks shooting (overheat) and recovers automatically

- [ ] **Step 5: Commit**

```bash
git add open_space/scenes/gui/hud.tscn open_space/scenes/gui/hud.gd
git commit -m "feat: add weapon display to open-space HUD, wire WeaponState + RocketState"
```

---

## Self-Review

**Spec coverage:**
- Same weapon modes (6) via shared `weapon_state.gd` + mode .tres files ✅
- Weapon cycling with E ✅ (MovementController emits `cycle_weapon` → WeaponState._on_action)
- Sub-weapon switch with Q ✅ (MovementController emits `switch_weapon` → RocketState._on_action)
- Sub-weapon fire with K ✅ (MovementController emits `special_weapon` → RocketState._on_action)
- Beam weapon works (hold J) ✅ (WeaponState._physics_process polls Input.is_action_pressed("shoot"))
- Overheat blocks shooting ✅ (`can_attack` driven by OverheatComponent)
- Player menu shows all weapons and sub-weapons ✅ (hud.gd passes weapon_state + rocket_state)
- Sub-weapon icon + cooldown shown in HUD ✅ (WeaponContainer + _process cooldown fill)

**Placeholder scan:** No TBDs, no incomplete steps.

**Type consistency:**
- `weapon_state.gd` expects `actor: CharacterBody2D` — `OpenSpacePlayerShip` extends `CharacterBody2D` ✓
- `weapon_state.gd` expects `heat_component: Overheat` — `OverheatComponent` uses `overheat_component.gd` (`class_name Overheat`) ✓
- `weapon_state.gd` checks `actor.can_attack` — added to `player_ship.gd` ✓
- `weapon_state.gd` reads `actor.get("fire_rate_multiplier")` — exists in `player_ship.gd` ✓
- `weapon_state.gd` reads `actor.get("damage_multiplier")` via beam behavior — exists in `player_ship.gd` ✓
- `RocketState` expects `actor: CharacterBody2D` ✓, `movement_controller: MovementController` ✓
