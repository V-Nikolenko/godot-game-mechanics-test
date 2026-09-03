# Abilities, Health & Shield System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a modular active-ability system (H key, save-file-selected), a shield component that absorbs damage before HP, and health+shield HUD bars to both assault and open-space missions.

**Architecture:** Each ability is a `Node` subclass of `AbilityBase`. A single `AbilityController` node on each player owns the currently-selected ability, handles input via `_unhandled_input("use_ability")`, and forwards `activate(ctx)` calls. A new `AbilityState` autoload persists which ability is selected. `ShieldComponent` absorbs incoming damage first; overflow goes to `Health`. Both players start with HP 50, Shield 100.

**Tech Stack:** Godot 4.6 GDScript, ConfigFile persistence, existing `Health`/`HurtBox`/`HitBox` components, existing `Overheat` component, existing `MovementController`/`WeaponState`.

---

## File Structure

### New files
| Path | Responsibility |
|------|---------------|
| `global/autoloads/ability_state.gd` | Persist + retrieve selected ability id |
| `global/components/shield_component.gd` | `class_name Shield` — absorb damage, emit signals |
| `global/abilities/ability_base.gd` | Abstract `class_name AbilityBase extends Node` |
| `global/abilities/ability_controller.gd` | `class_name AbilityController` — owns active ability, handles `use_ability` input |
| `global/abilities/parry_ability.gd` | Port of ReflectState — redirect enemy bullets |
| `global/abilities/shockwave_ability.gd` | Push + damage enemies in radius |
| `global/abilities/overdrive_ability.gd` | Fire rate + speed boost, uncapped heat, player damage on expiry |
| `global/abilities/teleport_ability.gd` | Short-range teleport in move-input direction; contact damage |
| `global/abilities/armor_plating_ability.gd` | Temporary 50% damage reduction buff |
| `global/abilities/overheat_nullifier_ability.gd` | Instantly zero the heat meter |
| `global/abilities/final_resort_ability.gd` | Toggle: 1 HP, no shield, ×3 weapon damage |
| `global/abilities/emp_blast_ability.gd` | Pause all non-asteroid/non-ram enemies for 5 s |
| `global/abilities/plasma_nova_ability.gd` | Deal 50 damage to all on-screen enemies |
| `global/abilities/shield_overload_ability.gd` | Expend shield as area explosion |
| `global/abilities/shield_recharge_ability.gd` | Restore full shield instantly |
| `global/abilities/trajectory_calc_ability.gd` | Slow Engine.time_scale to 0.3 for 5 s |
| `assault/scenes/gui/health_shield_bar.gd` | HUD widget: two stacked bars (HP red, shield cyan) |
| `assault/scenes/gui/health_shield_bar.tscn` | Scene for the widget |
| `assault/scenes/gui/ability_chip.gd` | HUD widget: ability icon + cooldown arc |
| `assault/scenes/gui/ability_chip.tscn` | Scene for the widget |
| `open_space/scenes/gui/hud.gd` | Open-space HUD: health+shield bar |
| `open_space/scenes/gui/hud.tscn` | Scene for open-space HUD |

### Modified files
| Path | Change |
|------|--------|
| `project.godot` | Add `use_ability` input action (H key); add AbilityState autoload; remove `reflect` action |
| `global/autoloads/upgrade_state.gd` | Remove `&"reflect"` from ALL_IDS (parry is now an ability, not an upgrade) |
| `assault/scenes/player/movement_controller.gd` | Remove `"reflect"` from SINGLE_PRESS_ACTIONS |
| `assault/scenes/player/player_fighter.gd` | Add `shield_component`, reroute damage through shield, expose `damage_multiplier` + `fire_rate_multiplier` |
| `assault/scenes/player/player_fighter.tscn` | Add ShieldComponent; replace ReflectState with AbilityController; set HP=50 |
| `assault/scenes/player/states/weapon_state.gd` | Read `actor.fire_rate_multiplier` on cooldown; read `actor.damage_multiplier` when firing |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd` | Read `actor.damage_multiplier` for beam DPS |
| `assault/scenes/gui/hud.tscn` | Replace HealthBar with HealthShieldBar instance; add AbilityChip instance |
| `assault/scenes/gui/hud.gd` | Connect HealthShieldBar to health+shield; connect AbilityChip to AbilityController |
| `open_space/scenes/entities/player/player_ship.gd` | Add `shield_component`, reroute damage, expose multipliers |
| `open_space/scenes/entities/player/player_ship.tscn` | Add ShieldComponent; add AbilityController; set HP=50 |
| `open_space/scenes/levels/sector_hub.tscn` | Add open-space HUD as CanvasLayer child |

---

## Task 1: AbilityState autoload + `use_ability` input action

**Files:**
- Create: `global/autoloads/ability_state.gd`
- Modify: `project.godot`
- Modify: `assault/scenes/player/movement_controller.gd`
- Modify: `global/autoloads/upgrade_state.gd`

- [ ] **Step 1: Create AbilityState autoload**

```gdscript
# global/autoloads/ability_state.gd
extends Node

## Persists which ability is currently equipped.
## Set via: AbilityState.set_selected(&"shockwave")
## Read via: AbilityState.selected_id

const SAVE_PATH := "user://ability_state.cfg"
const SECTION := "ability"
const KEY := "selected"

## All valid ability IDs in display order.
const ALL_IDS: Array[StringName] = [
	&"parry", &"shockwave", &"overdrive", &"teleport",
	&"armor_plating", &"overheat_nullifier", &"final_resort",
	&"emp_blast", &"plasma_nova", &"shield_overload",
	&"shield_recharge", &"trajectory_calc",
]

signal ability_changed(id: StringName)

var selected_id: StringName = &"parry"

func _ready() -> void:
	_load()

func set_selected(id: StringName) -> void:
	if id not in ALL_IDS:
		push_warning("AbilityState: unknown id '%s'" % id)
		return
	selected_id = id
	_save()
	ability_changed.emit(id)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY, String(selected_id))
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var raw: String = cfg.get_value(SECTION, KEY, "parry")
	var id := StringName(raw)
	if id in ALL_IDS:
		selected_id = id
```

- [ ] **Step 2: Register AbilityState in project.godot**

Open `project.godot` in a text editor. In the `[autoload]` section, add:
```
AbilityState="*res://global/autoloads/ability_state.gd"
```

- [ ] **Step 3: Replace `reflect` input with `use_ability` in project.godot**

In `project.godot` under `[input]`, replace the entire `reflect={...}` block with:
```
use_ability={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":72,"key_label":0,"unicode":104,"location":0,"echo":false,"script":null)
]
}
```
(physical_keycode 72 = H key — same as the old `reflect` binding)

- [ ] **Step 4: Remove `"reflect"` from MovementController.SINGLE_PRESS_ACTIONS**

File: `assault/scenes/player/movement_controller.gd`, change:
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
to:
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

- [ ] **Step 5: Remove `&"reflect"` from UpgradeState.ALL_IDS**

File: `global/autoloads/upgrade_state.gd`, change:
```gdscript
const ALL_IDS: Array[StringName] = [
	&"default", &"long_range", &"piercing", &"spread", &"reflect"
]
```
to:
```gdscript
const ALL_IDS: Array[StringName] = [
	&"default", &"long_range", &"piercing", &"spread"
]
```

- [ ] **Step 6: Verify — open Godot, confirm no errors in Output on startup, H key no longer triggers anything**

- [ ] **Step 7: Commit**
```bash
git add global/autoloads/ability_state.gd project.godot assault/scenes/player/movement_controller.gd global/autoloads/upgrade_state.gd
git commit -m "feat: add AbilityState autoload and use_ability input action"
```

---

## Task 2: Shield component

**Files:**
- Create: `global/components/shield_component.gd`

- [ ] **Step 1: Create ShieldComponent**

```gdscript
# global/components/shield_component.gd
class_name Shield
extends Node

## Shield absorbs damage before Health.
## Usage:
##   var overflow := shield.absorb(damage)   # returns leftover damage to Health
##   shield.increase(amount)                 # recharge
##   shield.set_shield(value)               # hard set

signal shield_changed(current: int, maximum: int)
signal shield_depleted
signal shield_restored   ## emitted when shield goes from 0 → any positive value

@export_category("Shield")
@export var max_shield: int = 100
@export var current_shield: int = 100

func _ready() -> void:
	current_shield = clampi(current_shield, 0, max_shield)

## Absorb `damage` points. Returns leftover damage that bypasses shield.
func absorb(damage: int) -> int:
	if current_shield <= 0:
		return damage
	var absorbed: int = mini(damage, current_shield)
	var overflow: int = damage - absorbed
	var was_zero := current_shield == 0
	current_shield -= absorbed
	shield_changed.emit(current_shield, max_shield)
	if current_shield == 0:
		shield_depleted.emit()
	return overflow

## Restore `amount` shield points, clamped to max_shield.
func increase(amount: int) -> void:
	var was_empty := current_shield == 0
	current_shield = clampi(current_shield + amount, 0, max_shield)
	shield_changed.emit(current_shield, max_shield)
	if was_empty and current_shield > 0:
		shield_restored.emit()

## Hard-set shield to `value`.
func set_shield(value: int) -> void:
	var was_empty := current_shield == 0
	current_shield = clampi(value, 0, max_shield)
	shield_changed.emit(current_shield, max_shield)
	if was_empty and current_shield > 0:
		shield_restored.emit()
	elif current_shield == 0 and not was_empty:
		shield_depleted.emit()

func is_empty() -> bool:
	return current_shield <= 0
```

- [ ] **Step 2: Verify — open Godot, no parse errors shown**

- [ ] **Step 3: Commit**
```bash
git add global/components/shield_component.gd
git commit -m "feat: add Shield component with absorb/increase/set_shield"
```

---

## Task 3: Assault player — shield integration + stat changes

**Files:**
- Modify: `assault/scenes/player/player_fighter.gd`
- Modify: `assault/scenes/player/player_fighter.tscn`

- [ ] **Step 1: Update player_fighter.gd**

Replace the full content of `assault/scenes/player/player_fighter.gd` with:

```gdscript
extends CharacterBody2D

@onready var hurt_box: HurtBox = $HurtBox
@onready var health_component: Health = $HealthComponent
@onready var shield_component: Shield = $ShieldComponent
@onready var overheat_component: Overheat = $OverheatComponent

var can_attack: bool = true

## Multipliers written by AbilityController / abilities.
## WeaponState reads these when computing damage and cooldowns.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0

## When true, overheat can exceed heat_limit without capping.
var overdrive_active: bool = false

@onready var game_over_scene: PackedScene = preload("res://assault/scenes/gui/game_over.tscn")

# ── Particle effect components ────────────────────────────────────────────────
var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect
var _low_health_smoke: LowHealthSmoke
var _thruster: ThrusterEffect

const _DASH_SPEED_THRESHOLD: float = 280.0
const _MOVE_SPEED_THRESHOLD: float = 10.0

func _ready() -> void:
	add_to_group("player")
	overheat_component.overheat.connect(handle_overheat)
	health_component.amount_changed.connect(_on_health_changed)

	var bar := OverheatBar.new()
	bar.position = Vector2(0, 22)
	add_child(bar)
	bar.setup(overheat_component)

	_setup_effect_components()

func _setup_effect_components() -> void:
	_hit_effect = HitEffect.new()
	_hit_effect.amount = 10
	_hit_effect.lifetime = 0.25
	_hit_effect.color = Color(1.0, 0.35, 0.1)
	_hit_effect.min_velocity = 40.0
	_hit_effect.max_velocity = 100.0
	add_child(_hit_effect)

	_explosion_effect = ExplosionEffect.new()
	_explosion_effect.amount = 30
	_explosion_effect.lifetime = 0.7
	_explosion_effect.color = Color(1.0, 0.4, 0.05)
	_explosion_effect.min_velocity = 80.0
	_explosion_effect.max_velocity = 240.0
	_explosion_effect.min_scale = 2.0
	_explosion_effect.max_scale = 5.5
	_explosion_effect.always_process = true
	add_child(_explosion_effect)

	_low_health_smoke = LowHealthSmoke.new()
	_low_health_smoke.threshold = 0.3
	add_child(_low_health_smoke)
	_low_health_smoke.setup(health_component)

	_thruster = ThrusterEffect.new()
	_thruster.position = Vector2(0.0, 14.0)
	add_child(_thruster)

func _physics_process(_delta: float) -> void:
	if DialogPlayer.is_active:
		velocity = Vector2.ZERO
		return
	var speed := velocity.length()
	var forward_speed  := -velocity.y
	var backward_speed :=  velocity.y
	if forward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.BOOST)
	elif backward_speed >= _DASH_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.IDLE)
	elif speed >= _MOVE_SPEED_THRESHOLD:
		_thruster.set_state(ThrusterEffect.State.THRUST)
	else:
		_thruster.set_state(ThrusterEffect.State.IDLE)

func _on_health_changed(current: int) -> void:
	_hit_effect.burst()
	if current == 0:
		_explosion_effect.explode()
		get_tree().paused = true
		var go := game_over_scene.instantiate()
		get_tree().root.add_child(go)
		get_tree().paused = false

func _on_hurt_box_received_damage(damage: int) -> void:
	## Route through shield first; overflow goes to health.
	var overflow := shield_component.absorb(damage)
	if overflow > 0:
		health_component.decrease(overflow)

func handle_overheat(overheat_percentage: float) -> void:
	if overdrive_active:
		## Overdrive: allow heat beyond limit, never lock weapons.
		can_attack = true
		return
	if overheat_percentage >= 100:
		can_attack = false
		return
	if overheat_percentage >= 80 and not can_attack:
		return
	if overheat_percentage < 80 and not can_attack:
		can_attack = true
```

- [ ] **Step 2: Add ShieldComponent to player_fighter.tscn and set HP=50**

Open `assault/scenes/player/player_fighter.tscn` in a text editor.

**a)** In the `[ext_resource]` section, add after the existing health script line:
```
[ext_resource type="Script" path="res://global/components/shield_component.gd" id="15_shld"]
```

**b)** Change the HealthComponent node to set max_health and current_health to 50:
```
[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("10_s7bsb")
metadata/_custom_type_script = "uid://bmvlejhrl0dfy"
max_health = 50
current_health = 50
```

**c)** Add the ShieldComponent node immediately after HealthComponent:
```
[node name="ShieldComponent" type="Node" parent="."]
script = ExtResource("15_shld")
max_shield = 100
current_shield = 100
```

**d)** Remove the entire `[node name="ReflectState" ...]` block (it will be replaced by AbilityController in Task 6).

- [ ] **Step 3: Verify — run assault scene, player has 50 HP shown in HUD health bar (it will still show 50/100 scale until HUD is updated in Task 8); no errors**

- [ ] **Step 4: Commit**
```bash
git add assault/scenes/player/player_fighter.gd assault/scenes/player/player_fighter.tscn
git commit -m "feat: add ShieldComponent to assault player, reroute damage, HP→50"
```

---

## Task 4: Open-space player — shield integration + stat changes

**Files:**
- Modify: `open_space/scenes/entities/player/player_ship.gd`
- Modify: `open_space/scenes/entities/player/player_ship.tscn`

- [ ] **Step 1: Update player_ship.gd**

Replace the full content of `open_space/scenes/entities/player/player_ship.gd`:

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

@export_category("Combat")
@export var shoot_cooldown_sec: float = 0.18
@export var bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

@onready var muzzle_left: Marker2D = $SpriteAnchor/MuzzleLeft
@onready var muzzle_right: Marker2D = $SpriteAnchor/MuzzleRight
@onready var health_component: Health = $HealthComponent
@onready var shield_component: Shield = $ShieldComponent
@onready var hurt_box: HurtBox = $HurtBox

## Multipliers written by AbilityController / abilities.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
var overdrive_active: bool = false

var _shoot_cooldown: float = 0.0
var _gun_index: int = 0
var _boost_timer: float = 0.0

var _hit_effect: HitEffect
var _explosion_effect: ExplosionEffect
var _thruster: ThrusterEffect

func _ready() -> void:
	add_to_group("player")
	health_component.amount_changed.connect(_on_health_changed)
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
	_handle_shoot(delta)
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

func _handle_shoot(delta: float) -> void:
	_shoot_cooldown = max(_shoot_cooldown - delta, 0.0)
	if _shoot_cooldown > 0.0:
		return
	if not Input.is_action_pressed("shoot"):
		return

	var muzzles: Array[Marker2D] = [muzzle_left, muzzle_right]
	_gun_index = (_gun_index + 1) % muzzles.size()
	var muzzle: Marker2D = muzzles[_gun_index]

	var bullet: Area2D = bullet_scene.instantiate()
	bullet.global_position = muzzle.global_position + Vector2.UP.rotated(global_rotation) * 4.0
	bullet.rotation = global_rotation
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(bullet)
		bullet.expired.connect(bullet.queue_free)

	_shoot_cooldown = shoot_cooldown_sec * (1.0 / fire_rate_multiplier)

func _on_received_damage(damage: int) -> void:
	## Route through shield first; overflow goes to health.
	var overflow := shield_component.absorb(damage)
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

- [ ] **Step 2: Update player_ship.tscn — add ShieldComponent, set HP=50**

In `open_space/scenes/entities/player/player_ship.tscn`:

**a)** Add ext_resource for shield script (increment load_steps from 9 to 10):
```
[gd_scene load_steps=10 format=3]
```
Add at end of ext_resource block:
```
[ext_resource type="Script" path="res://global/components/shield_component.gd" id="5_shld"]
```

**b)** Change HealthComponent stats:
```
[node name="HealthComponent" type="Node" parent="."]
script = ExtResource("3_health")
max_health = 50
current_health = 50
```

**c)** Add ShieldComponent node after HealthComponent:
```
[node name="ShieldComponent" type="Node" parent="."]
script = ExtResource("5_shld")
max_shield = 100
current_shield = 100
```

- [ ] **Step 3: Verify — run open space scene, no errors; player takes damage that goes to shield first**

- [ ] **Step 4: Commit**
```bash
git add open_space/scenes/entities/player/player_ship.gd open_space/scenes/entities/player/player_ship.tscn
git commit -m "feat: add ShieldComponent to open-space player, reroute damage, HP→50"
```

---

## Task 5: AbilityBase + AbilityController

**Files:**
- Create: `global/abilities/ability_base.gd`
- Create: `global/abilities/ability_controller.gd`

- [ ] **Step 1: Create AbilityBase**

```gdscript
# global/abilities/ability_base.gd
class_name AbilityBase
extends Node

## Override in subclass. Called when the player presses use_ability.
## `ctx` provides access to actor, health, shield, overheat, etc.
## Returns true if the ability was successfully activated (starts cooldown).
func activate(ctx: AbilityController) -> bool:
	return false

## Override if the ability needs per-frame logic while active.
## Called by AbilityController._physics_process while this ability is the selected one.
func tick(_ctx: AbilityController, _delta: float) -> void:
	pass

## Called when this ability is deselected or the level ends.
## Clean up any active effects.
func deactivate(_ctx: AbilityController) -> void:
	pass

## Human-readable name for HUD display.
func get_display_name() -> String:
	return "Ability"

## Icon texture for HUD. Return null to show a placeholder.
func get_icon() -> Texture2D:
	return null

## Cooldown duration in seconds.
func get_cooldown() -> float:
	return 5.0
```

- [ ] **Step 2: Create AbilityController**

```gdscript
# global/abilities/ability_controller.gd
class_name AbilityController
extends Node

## Owns the currently-selected ability, handles H-key input,
## tracks cooldown, and exposes modifier properties for abilities to write.

@export var actor: CharacterBody2D
@export var health: Health
@export var shield: Shield        ## may be null in contexts without a shield
@export var overheat: Overheat    ## may be null in open-space

## Written by abilities (e.g. Overdrive writes 2.0, Final Resort writes 3.0).
## Read by WeaponState and player scripts when dealing/receiving damage.
var damage_multiplier: float = 1.0
var fire_rate_multiplier: float = 1.0
## True while Overdrive is active — tells player to skip heat capping.
var overdrive_active: bool = false

var cooldown_left: float = 0.0
var _ability: AbilityBase = null

## Maps ability id → instance. Built lazily on first selection.
var _pool: Dictionary = {}  # { StringName: AbilityBase }

func _ready() -> void:
	_swap_ability(AbilityState.selected_id)
	AbilityState.ability_changed.connect(_swap_ability)

func _physics_process(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left = max(0.0, cooldown_left - delta)
	if _ability != null:
		_ability.tick(self, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("use_ability"):
		_try_activate()
		get_viewport().set_input_as_handled()

func _try_activate() -> void:
	if _ability == null:
		return
	if cooldown_left > 0.0:
		return
	var triggered: bool = _ability.activate(self)
	if triggered:
		cooldown_left = _ability.get_cooldown()

func _swap_ability(id: StringName) -> void:
	## Deactivate old ability.
	if _ability != null:
		_ability.deactivate(self)

	## Reset all modifiers to defaults when switching.
	damage_multiplier = 1.0
	fire_rate_multiplier = 1.0
	overdrive_active = false
	if actor:
		actor.set("damage_multiplier", 1.0)
		actor.set("fire_rate_multiplier", 1.0)
		actor.set("overdrive_active", false)

	## Get-or-create ability instance.
	if not _pool.has(id):
		var inst := _create_ability(id)
		if inst != null:
			_pool[id] = inst
			add_child(inst)

	_ability = _pool.get(id, null)
	cooldown_left = 0.0

func _create_ability(id: StringName) -> AbilityBase:
	match id:
		&"parry":           return preload("res://global/abilities/parry_ability.gd").new()
		&"shockwave":       return preload("res://global/abilities/shockwave_ability.gd").new()
		&"overdrive":       return preload("res://global/abilities/overdrive_ability.gd").new()
		&"teleport":        return preload("res://global/abilities/teleport_ability.gd").new()
		&"armor_plating":   return preload("res://global/abilities/armor_plating_ability.gd").new()
		&"overheat_nullifier": return preload("res://global/abilities/overheat_nullifier_ability.gd").new()
		&"final_resort":    return preload("res://global/abilities/final_resort_ability.gd").new()
		&"emp_blast":       return preload("res://global/abilities/emp_blast_ability.gd").new()
		&"plasma_nova":     return preload("res://global/abilities/plasma_nova_ability.gd").new()
		&"shield_overload": return preload("res://global/abilities/shield_overload_ability.gd").new()
		&"shield_recharge": return preload("res://global/abilities/shield_recharge_ability.gd").new()
		&"trajectory_calc": return preload("res://global/abilities/trajectory_calc_ability.gd").new()
		_:
			push_warning("AbilityController: no class for id '%s'" % id)
			return null

## Convenience: current ability display name (for HUD).
func get_ability_name() -> String:
	return _ability.get_display_name() if _ability else "—"

## Convenience: current ability icon (for HUD).
func get_ability_icon() -> Texture2D:
	return _ability.get_icon() if _ability else null

## Convenience: cooldown fraction 0..1 (for HUD cooldown arc).
func get_cooldown_ratio() -> float:
	if _ability == null or _ability.get_cooldown() <= 0.0:
		return 0.0
	return cooldown_left / _ability.get_cooldown()
```

- [ ] **Step 3: Verify — open Godot, no parse errors**

- [ ] **Step 4: Commit**
```bash
git add global/abilities/ability_base.gd global/abilities/ability_controller.gd
git commit -m "feat: add AbilityBase and AbilityController framework"
```

---

## Task 6: Wire AbilityController to assault player

**Files:**
- Modify: `assault/scenes/player/player_fighter.tscn`
- Modify: `assault/scenes/player/player_fighter.gd`
- Modify: `assault/scenes/player/states/weapon_state.gd`
- Modify: `assault/scenes/player/weapons/behaviors/beam_behavior.gd`

- [ ] **Step 1: Add AbilityController script as ext_resource in player_fighter.tscn**

In `assault/scenes/player/player_fighter.tscn`, add to ext_resource block:
```
[ext_resource type="Script" path="res://global/abilities/ability_controller.gd" id="16_abctl"]
```
Increment load_steps by 1 (or 2 if adding both shield and ability in this task).

- [ ] **Step 2: Add AbilityController node at end of player_fighter.tscn**

After all existing nodes (and after removing the old ReflectState block from Task 3):
```
[node name="AbilityController" type="Node" parent="." node_paths=PackedStringArray("actor", "health", "shield", "overheat")]
script = ExtResource("16_abctl")
actor = NodePath("..")
health = NodePath("../HealthComponent")
shield = NodePath("../ShieldComponent")
overheat = NodePath("../OverheatComponent")
```

- [ ] **Step 3: Make WeaponState respect fire_rate_multiplier and damage_multiplier**

In `assault/scenes/player/states/weapon_state.gd`, modify `_try_fire_once()`:
```gdscript
func _try_fire_once() -> void:
	if not actor.can_attack:
		return
	var mode: WeaponModeResource = _modes.get(_active_id)
	if mode == null:
		return
	if mode.behavior == WeaponModeResource.Behavior.BEAM:
		return
	if _cooldown > 0.0:
		return
	_fire(mode)
	## Shorter cooldown with fire_rate_multiplier > 1.0 (e.g. Overdrive sets 2.0).
	var multiplier: float = actor.get("fire_rate_multiplier") if actor.get("fire_rate_multiplier") != null else 1.0
	_cooldown = mode.fire_interval / maxf(multiplier, 0.01)
```

And modify the `_fire()` method to apply damage_multiplier when spawning a projectile. Since actual damage lives on the HitBox of each projectile scene, the cleanest approach is to apply the multiplier after instantiation. Add a helper in WeaponState:

```gdscript
func _apply_damage_multiplier(projectile: Node) -> void:
	var multiplier: float = actor.get("damage_multiplier") if actor.get("damage_multiplier") != null else 1.0
	if is_equal_approx(multiplier, 1.0):
		return
	var hb := projectile.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = roundi(hb.damage * multiplier)
```

Call `_apply_damage_multiplier(projectile)` in each behavior's `fire()` right after instantiating the projectile (see behavior files). For now, document this as needed — behaviors are modified in individual ability tasks as needed. The multiplier property on `actor` is enough; behaviors can read it directly.

For the beam behavior, in `beam_behavior.gd` modify `tick()` where `dmg_this_frame` is computed:
```gdscript
var actor_multiplier: float = actor.get("damage_multiplier") if actor != null else 1.0
var dmg_this_frame: float = mode.beam_dps * delta * actor_multiplier
```

- [ ] **Step 4: Update player_fighter.gd to sync AbilityController modifiers**

The `damage_multiplier`, `fire_rate_multiplier`, and `overdrive_active` properties are already declared on `player_fighter.gd` (added in Task 3). AbilityController sets them via `actor.set("damage_multiplier", value)` in `_swap_ability`. Individual abilities set them too via `ctx.actor.set(...)`. No additional changes needed here.

- [ ] **Step 5: Verify — run assault level. H key does nothing yet (no abilities implemented). No errors. Game plays normally.**

- [ ] **Step 6: Commit**
```bash
git add assault/scenes/player/player_fighter.tscn assault/scenes/player/states/weapon_state.gd assault/scenes/player/weapons/behaviors/beam_behavior.gd
git commit -m "feat: wire AbilityController to assault player, multiplier hooks in WeaponState"
```

---

## Task 7: Wire AbilityController to open-space player

**Files:**
- Modify: `open_space/scenes/entities/player/player_ship.tscn`

- [ ] **Step 1: Add AbilityController to player_ship.tscn**

In `open_space/scenes/entities/player/player_ship.tscn`:

Add ext_resource (increment load_steps by 1):
```
[ext_resource type="Script" path="res://global/abilities/ability_controller.gd" id="6_abctl"]
```

Add at end of nodes:
```
[node name="AbilityController" type="Node" parent="." node_paths=PackedStringArray("actor", "health", "shield")]
script = ExtResource("6_abctl")
actor = NodePath("..")
health = NodePath("../HealthComponent")
shield = NodePath("../ShieldComponent")
```
(overheat is intentionally not set — open space has no overheat)

- [ ] **Step 2: Verify — run open space scene. H key available. No errors.**

- [ ] **Step 3: Commit**
```bash
git add open_space/scenes/entities/player/player_ship.tscn
git commit -m "feat: wire AbilityController to open-space player"
```

---

## Task 8: Health + shield HUD bars

**Files:**
- Create: `assault/scenes/gui/health_shield_bar.gd`
- Create: `assault/scenes/gui/health_shield_bar.tscn`
- Modify: `assault/scenes/gui/hud.tscn`
- Modify: `assault/scenes/gui/hud.gd`

- [ ] **Step 1: Create HealthShieldBar script**

```gdscript
# assault/scenes/gui/health_shield_bar.gd
class_name HealthShieldBar
extends Control

## Displays stacked health (red) and shield (cyan) bars.
## Call setup(health, shield) to connect to player components.
## Shield bar sits on top; health bar below.

@onready var _shield_bar: ProgressBar = $ShieldBar
@onready var _health_bar: ProgressBar = $HealthBar

func setup(health: Health, shield: Shield) -> void:
	_health_bar.max_value = health.max_health
	_health_bar.value     = health.current_health
	health.amount_changed.connect(_on_health_changed)

	_shield_bar.max_value = shield.max_shield
	_shield_bar.value     = shield.current_shield
	shield.shield_changed.connect(_on_shield_changed)

func _on_health_changed(current: int) -> void:
	_health_bar.value = current

func _on_shield_changed(current: int, _maximum: int) -> void:
	_shield_bar.value = current
```

- [ ] **Step 2: Create health_shield_bar.tscn**

Create `assault/scenes/gui/health_shield_bar.tscn` with this structure:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/gui/health_shield_bar.gd" id="1_hsbar"]

[node name="HealthShieldBar" type="Control"]
custom_minimum_size = Vector2(150, 28)
script = ExtResource("1_hsbar")

[node name="ShieldBar" type="ProgressBar" parent="."]
anchor_right = 1.0
offset_top = 0.0
offset_bottom = 12.0
min_value = 0.0
max_value = 100.0
value = 100.0

[node name="HealthBar" type="ProgressBar" parent="."]
anchor_right = 1.0
offset_top = 14.0
offset_bottom = 28.0
min_value = 0.0
max_value = 50.0
value = 50.0
```

Then open the scene in Godot editor to style the bars:
- ShieldBar: `theme_override_styles/fill` → new StyleBoxFlat, color `Color(0.1, 0.85, 1.0)` (cyan)
- HealthBar: `theme_override_styles/fill` → new StyleBoxFlat, color `Color(0.9, 0.15, 0.15)` (red)

- [ ] **Step 3: Update hud.tscn — replace HealthBar with HealthShieldBar**

In `assault/scenes/gui/hud.tscn`:

**a)** Add HealthShieldBar scene as ext_resource:
```
[ext_resource type="PackedScene" path="res://assault/scenes/gui/health_shield_bar.tscn" id="4_hsbar"]
```

**b)** Remove the existing `[node name="HealthBar" ...]` node.

**c)** Add HealthShieldBar instance:
```
[node name="HealthShieldBar" parent="." instance=ExtResource("4_hsbar")]
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = -36.0
offset_right = 158.0
offset_bottom = -8.0
```

- [ ] **Step 4: Update hud.gd**

Replace the full content of `assault/scenes/gui/hud.gd`:

```gdscript
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar
@onready var weapon_icon: TextureRect  = $WeaponContainer/WeaponIcon
@onready var cooldown_overlay: ColorRect = $WeaponContainer/CooldownOverlay

var _cooldown_timer: Timer = null

func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
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

- [ ] **Step 5: Verify — run assault level. Top-left shows two bars (cyan shield full, red health at 50/50). Taking damage drains shield bar first, then health.**

- [ ] **Step 6: Commit**
```bash
git add assault/scenes/gui/health_shield_bar.gd assault/scenes/gui/health_shield_bar.tscn assault/scenes/gui/hud.tscn assault/scenes/gui/hud.gd
git commit -m "feat: replace HealthBar with stacked HealthShieldBar in assault HUD"
```

---

## Task 9: Open-space HUD (health + shield bars)

**Files:**
- Create: `open_space/scenes/gui/hud.gd`
- Create: `open_space/scenes/gui/hud.tscn`
- Modify: `open_space/scenes/levels/sector_hub.tscn`

- [ ] **Step 1: Create open-space HUD script**

```gdscript
# open_space/scenes/gui/hud.gd
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar

func _ready() -> void:
	## Wait one frame for the player to be ready.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0]
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)
```

- [ ] **Step 2: Create open_space/scenes/gui/hud.tscn**

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://open_space/scenes/gui/hud.gd" id="1_oshud"]
[ext_resource type="PackedScene" path="res://assault/scenes/gui/health_shield_bar.tscn" id="2_hsbar"]

[node name="OpenSpaceHUD" type="CanvasLayer"]
script = ExtResource("1_oshud")

[node name="HealthShieldBar" parent="." instance=ExtResource("2_hsbar")]
offset_left = 8.0
offset_top = 8.0
```

- [ ] **Step 3: Add HUD to sector_hub.tscn**

Open `open_space/scenes/levels/sector_hub.tscn` and add the HUD as a child:
- Add ext_resource for the HUD scene
- Add `[node name="OpenSpaceHUD" parent="." instance=ExtResource("...")]`

(Do this via the Godot editor: Scene → Instantiate Child Scene → select `open_space/scenes/gui/hud.tscn`)

- [ ] **Step 4: Verify — run open-space scene. Top-left shows health+shield bars.**

- [ ] **Step 5: Commit**
```bash
git add open_space/scenes/gui/ open_space/scenes/levels/sector_hub.tscn
git commit -m "feat: add health+shield HUD to open-space sector hub"
```

---

## Task 10: Ability chip HUD widget

**Files:**
- Create: `assault/scenes/gui/ability_chip.gd`
- Create: `assault/scenes/gui/ability_chip.tscn`
- Modify: `assault/scenes/gui/hud.tscn`
- Modify: `assault/scenes/gui/hud.gd`

- [ ] **Step 1: Create AbilityChip script**

```gdscript
# assault/scenes/gui/ability_chip.gd
class_name AbilityChip
extends Control

## Shows the active ability icon and a cooldown fill.
## Call setup(ability_controller) to connect.

@onready var _icon: TextureRect = $Icon
@onready var _cooldown_fill: ColorRect = $CooldownFill
@onready var _label: Label = $Label

var _controller: AbilityController = null

func _ready() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var ctrl := players[0].get_node_or_null("AbilityController") as AbilityController
	if ctrl == null:
		return
	_controller = ctrl
	_refresh()
	AbilityState.ability_changed.connect(func(_id: StringName) -> void: _refresh())

func _refresh() -> void:
	if _controller == null:
		return
	_icon.texture = _controller.get_ability_icon()
	_label.text   = _controller.get_ability_name()

func _process(_delta: float) -> void:
	if _controller == null:
		return
	## Shrink _cooldown_fill from top as cooldown expires.
	## ratio 1.0 = full cooldown remaining; 0.0 = ready.
	var ratio: float = _controller.get_cooldown_ratio()
	_cooldown_fill.visible = ratio > 0.0
	if ratio > 0.0:
		var h: float = _icon.size.y
		_cooldown_fill.size = Vector2(_icon.size.x, h * ratio)
		_cooldown_fill.position = Vector2(0.0, 0.0)
```

- [ ] **Step 2: Create ability_chip.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/gui/ability_chip.gd" id="1_achip"]

[node name="AbilityChip" type="Control"]
custom_minimum_size = Vector2(40, 56)
script = ExtResource("1_achip")

[node name="Icon" type="TextureRect" parent="."]
anchor_right = 1.0
custom_minimum_size = Vector2(40, 40)
expand_mode = 1
stretch_mode = 5

[node name="CooldownFill" type="ColorRect" parent="."]
color = Color(0.1, 0.1, 0.1, 0.7)
visible = false

[node name="Label" type="Label" parent="."]
anchor_top = 1.0
anchor_bottom = 1.0
offset_top = -14.0
offset_right = 40.0
theme_override_font_sizes/font_size = 9
horizontal_alignment = 1
```

- [ ] **Step 3: Add AbilityChip to hud.tscn**

In `assault/scenes/gui/hud.tscn`, add:
```
[ext_resource type="PackedScene" path="res://assault/scenes/gui/ability_chip.tscn" id="5_achip"]
```
And node:
```
[node name="AbilityChip" parent="." instance=ExtResource("5_achip")]
offset_left = 8.0
offset_top = 48.0
```

- [ ] **Step 4: Verify — run assault level. Top-left shows health/shield bars, below them a small ability chip (shows "—" or name if ability is loaded yet).**

- [ ] **Step 5: Commit**
```bash
git add assault/scenes/gui/ability_chip.gd assault/scenes/gui/ability_chip.tscn assault/scenes/gui/hud.tscn
git commit -m "feat: add AbilityChip HUD widget showing active ability and cooldown"
```

---

## Task 11: Parry ability (port of ReflectState)

**Files:**
- Create: `global/abilities/parry_ability.gd`

- [ ] **Step 1: Create parry_ability.gd**

```gdscript
# global/abilities/parry_ability.gd
class_name ParryAbility
extends AbilityBase

const _WINDOW_SEC: float = 0.15
const _RADIUS: float = 24.0

var _area: Area2D = null
var _window_left: float = 0.0

func get_display_name() -> String: return "Parry"
func get_cooldown() -> float: return 1.0

func activate(ctx: AbilityController) -> bool:
	if _window_left > 0.0:
		return false
	_open_window(ctx)
	return true

func tick(ctx: AbilityController, delta: float) -> void:
	if _window_left <= 0.0:
		return
	_window_left = max(0.0, _window_left - delta)
	if _window_left == 0.0:
		_close_window()

func deactivate(_ctx: AbilityController) -> void:
	_close_window()

func _open_window(ctx: AbilityController) -> void:
	_window_left = _WINDOW_SEC

	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 256  # enemy bullet HitBox layer
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = _RADIUS
	shape.shape = circle
	_area.add_child(shape)
	_area.area_entered.connect(_on_area_entered)
	ctx.actor.add_child(_area)

	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.4, 1.0, 1.0, 1.0)
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), _WINDOW_SEC)

func _close_window() -> void:
	if _area and is_instance_valid(_area):
		if _area.area_entered.is_connected(_on_area_entered):
			_area.area_entered.disconnect(_on_area_entered)
		_area.queue_free()
	_area = null

func _on_area_entered(area: Area2D) -> void:
	var node: Node = area
	while node and not (node is EnemyBullet):
		node = node.get_parent()
	if node is EnemyBullet:
		_close_window()
		_window_left = 0.0
		(node as EnemyBullet).become_friendly()
```

- [ ] **Step 2: Verify — run assault. Press H near an enemy bullet. Bullet should be reflected.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/parry_ability.gd
git commit -m "feat: implement Parry ability (port of ReflectState)"
```

---

## Task 12: Instant simple abilities — Overheat Nullifier + Shield Recharge

**Files:**
- Create: `global/abilities/overheat_nullifier_ability.gd`
- Create: `global/abilities/shield_recharge_ability.gd`

- [ ] **Step 1: Create overheat_nullifier_ability.gd**

```gdscript
# global/abilities/overheat_nullifier_ability.gd
class_name OverheatNullifierAbility
extends AbilityBase

func get_display_name() -> String: return "Heat Flush"
func get_cooldown() -> float: return 15.0

func activate(ctx: AbilityController) -> bool:
	if ctx.overheat == null:
		return false  ## Not available without an overheat component (open space).
	ctx.overheat.heat = 0.0
	ctx.overheat._emit_heat()
	## Visual flash: blue-white modulate on ship.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(0.6, 0.9, 1.0, 1.0), 0.05)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.25)
	return true
```

- [ ] **Step 2: Create shield_recharge_ability.gd**

```gdscript
# global/abilities/shield_recharge_ability.gd
class_name ShieldRechargeAbility
extends AbilityBase

func get_display_name() -> String: return "Shield Up"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	if ctx.shield == null:
		return false
	ctx.shield.set_shield(ctx.shield.max_shield)
	## Visual flash: bright cyan.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(0.0, 1.0, 1.0, 1.0), 0.08)
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.4)
	return true
```

- [ ] **Step 3: Verify — equip each ability via `AbilityState.set_selected(&"overheat_nullifier")` in DebugUnlockAll or console. Verify H key triggers them.**

- [ ] **Step 4: Commit**
```bash
git add global/abilities/overheat_nullifier_ability.gd global/abilities/shield_recharge_ability.gd
git commit -m "feat: implement OverheatNullifier and ShieldRecharge abilities"
```

---

## Task 13: Armor Plating ability

**Files:**
- Create: `global/abilities/armor_plating_ability.gd`

Armor Plating: pressing H activates a 8-second buff that halves incoming damage by intercepting the `absorbed` call via a damage-reduction flag on the actor.

- [ ] **Step 1: Add `damage_reduction: float` to both player scripts**

In `assault/scenes/player/player_fighter.gd`, add property:
```gdscript
## 0.0 = no reduction; 0.5 = take 50% damage. Written by ArmorPlatingAbility.
var damage_reduction: float = 0.0
```

Modify `_on_hurt_box_received_damage`:
```gdscript
func _on_hurt_box_received_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	var overflow := shield_component.absorb(effective)
	if overflow > 0:
		health_component.decrease(overflow)
```

In `open_space/scenes/entities/player/player_ship.gd`, add same property and update `_on_received_damage`:
```gdscript
var damage_reduction: float = 0.0

func _on_received_damage(damage: int) -> void:
	var effective: int = roundi(damage * (1.0 - damage_reduction))
	var overflow := shield_component.absorb(effective)
	if overflow > 0:
		health_component.decrease(overflow)
	_hit_effect.burst()
```

- [ ] **Step 2: Create armor_plating_ability.gd**

```gdscript
# global/abilities/armor_plating_ability.gd
class_name ArmorPlatingAbility
extends AbilityBase

const _DURATION: float = 8.0
const _REDUCTION: float = 0.5

var _time_left: float = 0.0

func get_display_name() -> String: return "Armor"
func get_cooldown() -> float: return 20.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	ctx.actor.set("damage_reduction", _REDUCTION)
	## Orange-gold glow.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.75, 0.2, 1.0)
	return true

func tick(ctx: AbilityController, delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_end(ctx)

func deactivate(ctx: AbilityController) -> void:
	_end(ctx)

func _end(ctx: AbilityController) -> void:
	_time_left = 0.0
	ctx.actor.set("damage_reduction", 0.0)
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
```

- [ ] **Step 3: Verify — equip armor_plating, press H, take enemy fire — damage should be halved for 8 s.**

- [ ] **Step 4: Commit**
```bash
git add global/abilities/armor_plating_ability.gd assault/scenes/player/player_fighter.gd open_space/scenes/entities/player/player_ship.gd
git commit -m "feat: implement ArmorPlating ability with 50% damage reduction buff"
```

---

## Task 14: Shockwave ability

**Files:**
- Create: `global/abilities/shockwave_ability.gd`

- [ ] **Step 1: Create shockwave_ability.gd**

```gdscript
# global/abilities/shockwave_ability.gd
class_name ShockwaveAbility
extends AbilityBase

const _RADIUS: float = 90.0
const _DAMAGE: int = 20
const _KNOCKBACK: float = 280.0

func get_display_name() -> String: return "Shockwave"
func get_cooldown() -> float: return 8.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Visual ring: scale a temporary circle from 0 to _RADIUS.
	var ring := _spawn_ring(actor)

	## Find all enemies inside the radius.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var dist: float = n.global_position.distance_to(actor.global_position)
		if dist > _RADIUS:
			continue

		## Knockback: push enemy away from player.
		if n.has_method("apply_knockback"):
			var dir: Vector2 = (n.global_position - actor.global_position).normalized()
			n.apply_knockback(dir * _KNOCKBACK)

		## Damage via HurtBox.
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	return true

func _spawn_ring(actor: Node2D) -> Node2D:
	## Simple expanding circle drawn with a Line2D arc.
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position

	var line := Line2D.new()
	line.width = 3.0
	line.default_color = Color(0.4, 0.8, 1.0, 0.8)
	var pts: PackedVector2Array = PackedVector2Array()
	var steps: int = 32
	for i in steps + 1:
		var angle: float = TAU * i / steps
		pts.append(Vector2(cos(angle), sin(angle)) * 4.0)
	line.points = pts
	ring.add_child(line)

	var t := actor.create_tween()
	t.tween_property(ring, "scale", Vector2(_RADIUS / 4.0, _RADIUS / 4.0), 0.25) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.25)
	t.tween_callback(ring.queue_free)
	return ring
```

- [ ] **Step 2: Verify — equip shockwave, press H near enemies; they take damage and are pushed back; expanding ring appears.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/shockwave_ability.gd
git commit -m "feat: implement Shockwave ability — push + damage enemies in radius"
```

---

## Task 15: Overdrive ability

**Files:**
- Create: `global/abilities/overdrive_ability.gd`

Overdrive: 10 s of doubled fire rate and 1.5× speed. Heat accumulates uncapped. On expiry, deal 15 damage to the player.

- [ ] **Step 1: Create overdrive_ability.gd**

```gdscript
# global/abilities/overdrive_ability.gd
class_name OverdriveAbility
extends AbilityBase

const _DURATION: float = 10.0
const _FIRE_RATE_MULTIPLIER: float = 2.0
const _EXPIRY_DAMAGE: int = 15

var _time_left: float = 0.0

func get_display_name() -> String: return "Overdrive"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	ctx.fire_rate_multiplier = _FIRE_RATE_MULTIPLIER
	ctx.overdrive_active = true
	ctx.actor.set("fire_rate_multiplier", _FIRE_RATE_MULTIPLIER)
	ctx.actor.set("overdrive_active", true)
	## Red-orange pulsing glow.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.4, 0.1, 1.0)
	return true

func tick(ctx: AbilityController, delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_end(ctx)

func deactivate(ctx: AbilityController) -> void:
	_end(ctx)

func _end(ctx: AbilityController) -> void:
	_time_left = 0.0
	ctx.fire_rate_multiplier = 1.0
	ctx.overdrive_active = false
	ctx.actor.set("fire_rate_multiplier", 1.0)
	ctx.actor.set("overdrive_active", false)
	## Expiry damage — bypasses shield for dramatic effect.
	if ctx.health:
		ctx.health.decrease(_EXPIRY_DAMAGE)
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.4)
```

- [ ] **Step 2: Verify — equip overdrive, press H; fire rate doubles for 10 s; after 10 s player takes 15 damage directly to HP.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/overdrive_ability.gd
git commit -m "feat: implement Overdrive ability — 2× fire rate for 10 s, expiry damage"
```

---

## Task 16: Teleport ability

**Files:**
- Create: `global/abilities/teleport_ability.gd`

Teleport: on press, warp the player 120 px in the direction of held movement input (or forward in open space). If an enemy overlaps the landing position, emit damage to it.

- [ ] **Step 1: Create teleport_ability.gd**

```gdscript
# global/abilities/teleport_ability.gd
class_name TeleportAbility
extends AbilityBase

const _DISTANCE: float = 120.0
const _CONTACT_DAMAGE: int = 25
const _CONTACT_RADIUS: float = 16.0

func get_display_name() -> String: return "Teleport"
func get_cooldown() -> float: return 3.0

func activate(ctx: AbilityController) -> bool:
	var actor: CharacterBody2D = ctx.actor
	var dir: Vector2 = _get_direction(actor)
	if dir == Vector2.ZERO:
		return false

	var dest: Vector2 = actor.global_position + dir * _DISTANCE

	## Ghost flash at origin.
	_spawn_ghost(actor)

	## Move.
	actor.global_position = dest

	## Contact damage: any enemy within _CONTACT_RADIUS of landing point.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		if n.global_position.distance_to(dest) > _CONTACT_RADIUS:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_CONTACT_DAMAGE)

	return true

func _get_direction(actor: Node2D) -> Vector2:
	## Assault: use WASD movement input direction.
	var v := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if v != Vector2.ZERO:
		return v.normalized()
	## Open space / no input: teleport forward (facing direction).
	return Vector2.UP.rotated(actor.rotation)

func _spawn_ghost(actor: Node2D) -> void:
	## Brief translucent copy of the sprite at the origin.
	var ghost := Sprite2D.new()
	var sprite := actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	if sprite:
		ghost.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	ghost.global_position = actor.global_position
	ghost.modulate = Color(0.5, 0.8, 1.0, 0.6)
	ghost.scale = actor.scale
	actor.get_parent().add_child(ghost)
	var t := actor.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.3)
	t.tween_callback(ghost.queue_free)
```

- [ ] **Step 2: Verify — equip teleport, hold W, press H; player jumps 120 px forward. Teleporting into an enemy deals contact damage.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/teleport_ability.gd
git commit -m "feat: implement Teleport ability with contact damage on landing"
```

---

## Task 17: Final Resort ability

**Files:**
- Create: `global/abilities/final_resort_ability.gd`

Final Resort: toggle. ON → HP becomes 1, shield drops to 0, weapons deal ×3 damage. OFF → restore original HP (capped at current), shield stays 0 (must recharge separately), damage returns to ×1.

- [ ] **Step 1: Create final_resort_ability.gd**

```gdscript
# global/abilities/final_resort_ability.gd
class_name FinalResortAbility
extends AbilityBase

const _DAMAGE_MULTIPLIER: float = 3.0

var _active: bool = false
var _saved_hp: int = 0

func get_display_name() -> String: return "Final Resort"
func get_cooldown() -> float: return 0.0  ## Toggle — no cooldown between uses.

func activate(ctx: AbilityController) -> bool:
	if not _active:
		_engage(ctx)
	else:
		_disengage(ctx)
	return false  ## Don't trigger the cooldown system.

func deactivate(ctx: AbilityController) -> void:
	if _active:
		_disengage(ctx)

func _engage(ctx: AbilityController) -> void:
	_active = true
	_saved_hp = ctx.health.current_health

	## Collapse HP to 1, drain shield.
	ctx.health.set_health(1)
	if ctx.shield:
		ctx.shield.set_shield(0)

	## Triple damage.
	ctx.damage_multiplier = _DAMAGE_MULTIPLIER
	ctx.actor.set("damage_multiplier", _DAMAGE_MULTIPLIER)

	## Blood-red ship tint.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(1.0, 0.1, 0.1, 1.0)

func _disengage(ctx: AbilityController) -> void:
	_active = false

	## Restore HP to what it was when we engaged (can't gain HP from the mode).
	ctx.health.set_health(mini(_saved_hp, ctx.health.current_health))

	## Restore damage.
	ctx.damage_multiplier = 1.0
	ctx.actor.set("damage_multiplier", 1.0)

	## Remove tint.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
```

- [ ] **Step 2: Verify — equip final_resort, press H; HP drops to 1; weapon bullets deal ×3 damage. Press H again; HP restored to saved value.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/final_resort_ability.gd
git commit -m "feat: implement Final Resort toggle ability — 1HP, 3× damage"
```

---

## Task 18: EMP Blast ability

**Files:**
- Create: `global/abilities/emp_blast_ability.gd`

EMP Blast: pause movement and shooting for all enemies except asteroids and ram ships. Done by setting `process_mode = PROCESS_MODE_DISABLED` temporarily, then restoring after 5 s via a timer on the enemy.

- [ ] **Step 1: Create emp_blast_ability.gd**

```gdscript
# global/abilities/emp_blast_ability.gd
class_name EMPBlastAbility
extends AbilityBase

const _STUN_DURATION: float = 5.0

## Groups/class names that are NOT stunned.
const _IMMUNE_CLASSES: Array[String] = ["BigAsteroid", "SmallAsteroid", "Asteroid", "RamShip"]

func get_display_name() -> String: return "EMP Blast"
func get_cooldown() -> float: return 15.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Visual: bright white flash expanding outward.
	_spawn_emp_visual(actor)

	## Stun eligible enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node
		if n == null:
			continue
		if _is_immune(n):
			continue
		_stun_enemy(n, actor)

	return true

func _is_immune(node: Node) -> bool:
	for class_name_str in _IMMUNE_CLASSES:
		if node.is_class(class_name_str):
			return true
		if node.get_script() != null and node.get_script().get_global_name() == class_name_str:
			return true
	return false

func _stun_enemy(enemy: Node, actor: Node2D) -> void:
	## Disable processing for _STUN_DURATION seconds.
	enemy.set_process_mode(Node.PROCESS_MODE_DISABLED)

	## Re-enable after the stun expires.
	var timer := actor.get_tree().create_timer(_STUN_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(enemy):
			enemy.set_process_mode(Node.PROCESS_MODE_INHERIT)
	)

func _spawn_emp_visual(actor: Node2D) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(0.2, 1.0, 0.5, 0.9)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 10.0)
	line.points = pts
	ring.add_child(line)
	var t := actor.create_tween()
	t.tween_property(ring, "scale", Vector2(80.0, 80.0), 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.35)
	t.tween_callback(ring.queue_free)
```

- [ ] **Step 2: Verify — equip emp_blast, press H; enemy ships freeze for 5 s; asteroids continue moving.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/emp_blast_ability.gd
git commit -m "feat: implement EMP Blast ability — stun non-asteroid enemies for 5 s"
```

---

## Task 19: Plasma Nova ability

**Files:**
- Create: `global/abilities/plasma_nova_ability.gd`

Plasma Nova: deal 50 damage to every enemy currently on screen. Massive visual flash.

- [ ] **Step 1: Create plasma_nova_ability.gd**

```gdscript
# global/abilities/plasma_nova_ability.gd
class_name PlasmaNovа extends AbilityBase
# Note: class_name must be valid GDScript — use PlasmaNovaAbility below.
```

```gdscript
# global/abilities/plasma_nova_ability.gd
class_name PlasmaNovaAbility
extends AbilityBase

const _DAMAGE: int = 50

func get_display_name() -> String: return "Plasma Nova"
func get_cooldown() -> float: return 30.0

func activate(ctx: AbilityController) -> bool:
	var actor: Node2D = ctx.actor

	## Screen-wide flash.
	_spawn_flash(actor)

	## Deal damage to all enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	return true

func _spawn_flash(actor: Node2D) -> void:
	## White ColorRect covering the viewport, fades out quickly.
	var overlay := ColorRect.new()
	overlay.color = Color(0.85, 0.5, 1.0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var canvas := CanvasLayer.new()
	canvas.layer = 128  # Above everything.
	canvas.add_child(overlay)
	actor.get_tree().root.add_child(canvas)

	var t := actor.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, 0.5)
	t.tween_callback(canvas.queue_free)
```

- [ ] **Step 2: Verify — equip plasma_nova, press H; all on-screen enemies take 50 damage; purple flash fills screen briefly.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/plasma_nova_ability.gd
git commit -m "feat: implement Plasma Nova — 50 damage to all on-screen enemies"
```

---

## Task 20: Shield Overload ability

**Files:**
- Create: `global/abilities/shield_overload_ability.gd`

Shield Overload: expend all remaining shield as energy. Destroy nearby bullets. Deal damage to nearby enemies proportional to shield spent. If shield is empty, activate does nothing.

- [ ] **Step 1: Create shield_overload_ability.gd**

```gdscript
# global/abilities/shield_overload_ability.gd
class_name ShieldOverloadAbility
extends AbilityBase

const _RADIUS: float = 100.0
const _DAMAGE_PER_SHIELD: float = 0.5  ## Each point of shield → 0.5 damage to enemies.

## Groups/classes of obstacles that are destroyed by the overload.
const _BULLET_GROUPS: Array[String] = ["enemy_bullets", "bullets"]

func get_display_name() -> String: return "Shield Overload"
func get_cooldown() -> float: return 0.0  ## Cost is the shield itself.

func activate(ctx: AbilityController) -> bool:
	if ctx.shield == null or ctx.shield.is_empty():
		return false  ## Nothing to expend.

	var actor: Node2D = ctx.actor
	var shield_spent: int = ctx.shield.current_shield

	## Drain shield to zero.
	ctx.shield.set_shield(0)

	var damage: int = roundi(shield_spent * _DAMAGE_PER_SHIELD)

	## Damage nearby enemies.
	var enemies := actor.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		var n := e as Node2D
		if n == null:
			continue
		if n.global_position.distance_to(actor.global_position) > _RADIUS:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(damage)

	## Destroy bullets/obstacles within radius.
	for group in _BULLET_GROUPS:
		for node in actor.get_tree().get_nodes_in_group(group):
			var n := node as Node2D
			if n == null:
				continue
			if n.global_position.distance_to(actor.global_position) <= _RADIUS:
				n.queue_free()

	## Visual: large electric burst.
	_spawn_burst(actor, shield_spent)
	return false  ## No standard cooldown (shield cost is the limiter).

func _spawn_burst(actor: Node2D, intensity: int) -> void:
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 5.0
	line.default_color = Color(0.1, 0.7, 1.0, 1.0)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 6.0)
	line.points = pts
	ring.add_child(line)
	var target_scale: float = _RADIUS / 6.0
	var t := actor.create_tween()
	t.tween_property(ring, "scale", Vector2(target_scale, target_scale), 0.2) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.2)
	t.tween_callback(ring.queue_free)
```

- [ ] **Step 2: Verify — equip shield_overload, take some damage to reduce shield, press H; shield depletes, nearby enemies take damage, nearby bullets destroyed.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/shield_overload_ability.gd
git commit -m "feat: implement Shield Overload — expend shield as area explosion"
```

---

## Task 21: Trajectory Calculation ability

**Files:**
- Create: `global/abilities/trajectory_calc_ability.gd`

Trajectory Calculation: slow `Engine.time_scale` to 0.3 for 5 seconds, then restore.

- [ ] **Step 1: Create trajectory_calc_ability.gd**

```gdscript
# global/abilities/trajectory_calc_ability.gd
class_name TrajectoryCalcAbility
extends AbilityBase

const _DURATION: float = 5.0
const _TIME_SCALE: float = 0.3

var _time_left: float = 0.0

func get_display_name() -> String: return "Trajectory"
func get_cooldown() -> float: return 20.0

func activate(ctx: AbilityController) -> bool:
	_time_left = _DURATION
	Engine.time_scale = _TIME_SCALE
	## Blue-tint visual.
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		sprite.modulate = Color(0.5, 0.7, 1.0, 1.0)
	return true

func tick(ctx: AbilityController, delta: float) -> void:
	if _time_left <= 0.0:
		return
	## `delta` is already scaled by Engine.time_scale, so divide it back.
	_time_left -= delta / Engine.time_scale
	if _time_left <= 0.0:
		_restore(ctx)

func deactivate(ctx: AbilityController) -> void:
	_restore(ctx)

func _restore(ctx: AbilityController) -> void:
	_time_left = 0.0
	Engine.time_scale = 1.0
	var sprite := ctx.actor.get_node_or_null("SpriteAnchor/ShipSprite2D") as CanvasItem
	if sprite:
		var t := ctx.actor.create_tween()
		t.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.3)
```

- [ ] **Step 2: Verify — equip trajectory_calc, press H; game visibly slows to ~30% speed for 5 real-time seconds, then resumes normal speed.**

- [ ] **Step 3: Commit**
```bash
git add global/abilities/trajectory_calc_ability.gd
git commit -m "feat: implement Trajectory Calculation — slow time to 0.3× for 5 s"
```

---

## Self-Review

### Spec coverage check

| Requirement | Covered by |
|------------|-----------|
| H key activates selected ability | Task 5 (AbilityController `_unhandled_input`) |
| Selected ability via save file | Task 1 (AbilityState, ConfigFile) |
| Parry (existing reflect → repurposed) | Tasks 1+11 |
| Shockwave | Task 14 |
| Overdrive | Task 15 |
| Teleport | Task 16 |
| Armor plating | Task 13 |
| Overheat nullifier | Task 12 |
| Final resort | Task 17 |
| EMP Blast | Task 18 |
| Plasma Nova | Task 19 |
| Shield Overload | Task 20 |
| Shield Recharge | Task 12 |
| Trajectory Calculation | Task 21 |
| HP 50, shield 100 base stats | Tasks 3+4 |
| Health + shield HUD — assault | Task 8 |
| Health + shield HUD — open space | Task 9 |
| Shield absorbs damage before HP | Tasks 3+4 |
| Works in both assault + open space | Tasks 6+7 (AbilityController on both players) |
| Easy to extend with new abilities | AbilityBase + AbilityController._create_ability() match — add new class + one match branch |

### Notes on extending the system

To add a new ability later:
1. Create `global/abilities/my_ability.gd` extending `AbilityBase`
2. Override `activate()`, `get_display_name()`, `get_cooldown()` (and optionally `tick()`, `deactivate()`)
3. Add `&"my_ability"` to `AbilityState.ALL_IDS`
4. Add a `&"my_ability": return preload(...).new()` branch in `AbilityController._create_ability()`
5. Done — no other files need touching

### Known limitations / future work
- Overdrive speed boost (1.5× movement speed) is not implemented — requires MoveState to read `fire_rate_multiplier` or a new `speed_multiplier` on actor. Mark as follow-up.
- Enemy `apply_knockback()` method (used by Shockwave) may not exist on all enemy types — check enemy scripts; add `func apply_knockback(impulse: Vector2): velocity += impulse` where missing.
- Shield bars need visual styling (colors) done in Godot editor after scene creation.
- AbilityChip icon requires each ability's `get_icon()` to return a real texture — placeholder is null/blank for now; add icons as art assets become available.
