# Gunship Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder Gunship enemy with a heavy, slow unit that enters from the top, holds position while firing aimed dual-barrel bursts at the player, swaps to a damaged sprite at 50% HP, and retreats at 30% HP.

**Architecture:** Four files are rewritten in order — config first (new fields), then script (Phase enum + burst coroutine + sprite swap), then the `.tres` defaults, then the scene (AnimatedSprite2D → Sprite2D, updated animation paths). A test wave entry in the level director is added last.

**Tech Stack:** Godot 4.3+, GDScript with static typing, CharacterBody2D, child Timer for burst cadence, `await get_tree().create_timer()` for burst gap, HealthComponent `amount_changed` signal for sprite swap.

---

## File Map

| File | Change |
|------|--------|
| `assault/scenes/enemies/gunship/gunship_config.gd` | Replace single `fire_interval` field with 9 tuning fields |
| `assault/scenes/enemies/gunship/gunship_config.tres` | Update stored values to match new fields |
| `assault/scenes/enemies/gunship/gunship.gd` | Full rewrite: Phase enum, burst fire, sprite swap, tracking |
| `assault/scenes/enemies/gunship/gunship.tscn` | Replace AnimatedSprite2D with Sprite2D; fix animation track paths |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Add gunship test wave |

---

## Task 1: Expand GunshipConfig

**Files:**
- Modify: `assault/scenes/enemies/gunship/gunship_config.gd`

- [ ] **Step 1: Replace the file contents**

Replace the entire file with:

```gdscript
## GunshipConfig — tuning for the reworked Gunship.
## Gunship manages its own ENTER/HOLD/RETREAT movement via AI.
class_name GunshipConfig
extends ShipConfig

## Seconds between burst pairs.
@export var burst_interval: float = 1.0
## Delay between left and right shot within a burst (seconds).
@export var burst_gap: float = 0.12
## Damage per bullet.
@export var bullet_damage: int = 15
## Bullet travel speed in px/s.
@export var bullet_speed: float = 260.0
## Entry and retreat speed in px/s.
@export var entry_speed: float = 60.0
## Pixels below viewport top edge where the ship holds position.
@export var hold_y_offset: float = 55.0
## Maximum horizontal tracking speed in px/s.
@export var track_speed: float = 70.0
## Enable/disable horizontal player tracking during HOLD.
@export var track_player: bool = true
## HP fraction (0–1) at which the ship transitions to RETREAT.
@export var retreat_hp_ratio: float = 0.3
```

- [ ] **Step 2: Verify file saved correctly**

Open `assault/scenes/enemies/gunship/gunship_config.gd` and confirm it has 9 `@export` fields and no `fire_interval`.

---

## Task 2: Update GunshipConfig Resource

**Files:**
- Modify: `assault/scenes/enemies/gunship/gunship_config.tres`

- [ ] **Step 1: Replace the file contents**

Replace the entire `.tres` file with:

```
[gd_resource type="Resource" script_class="GunshipConfig" format=3]

[ext_resource type="Script" path="res://assault/scenes/enemies/gunship/gunship_config.gd" id="1"]

[resource]
script = ExtResource("1")
max_health = 200
collision_damage = 30
score_value = 200
burst_interval = 1.0
burst_gap = 0.12
bullet_damage = 15
bullet_speed = 260.0
entry_speed = 60.0
hold_y_offset = 55.0
track_speed = 70.0
track_player = true
retreat_hp_ratio = 0.3
```

- [ ] **Step 2: Verify resource values**

Confirm `gunship_config.tres` has no `fire_interval` key and all 9 new fields appear.

---

## Task 3: Rewrite gunship.gd

**Files:**
- Modify: `assault/scenes/enemies/gunship/gunship.gd`

- [ ] **Step 1: Replace the file contents**

Replace the entire file with:

```gdscript
class_name Gunship
extends BaseEnemy

@export var config: GunshipConfig = load("res://assault/scenes/enemies/gunship/gunship_config.tres")

enum Phase { ENTER, HOLD, RETREAT }

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
const _TEXTURE_FULL    := preload("res://assault/assets/sprites/enemies/heave_gunship.png")
const _TEXTURE_DAMAGED := preload("res://assault/assets/sprites/enemies/heavy_gunship_non_shielded.png")

var _phase: Phase = Phase.ENTER
var _hold_y: float = 0.0
var _burst_interval: float = 1.0
var _burst_gap: float = 0.12
var _bullet_damage: int = 15
var _bullet_speed: float = 260.0
var _entry_speed: float = 60.0
var _track_speed: float = 70.0
var _track_player: bool = true
var _retreat_hp_ratio: float = 0.3

var _bullet_pool: BulletPool
var _burst_timer: Timer
var _sprite: Sprite2D


func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	_sprite = $Sprite2D as Sprite2D

	if config:
		health.max_health      = config.max_health
		health.current_health  = config.max_health
		_burst_interval        = config.burst_interval
		_burst_gap             = config.burst_gap
		_bullet_damage         = config.bullet_damage
		_bullet_speed          = config.bullet_speed
		_entry_speed           = config.entry_speed
		_track_speed           = config.track_speed
		_track_player          = config.track_player
		_retreat_hp_ratio      = config.retreat_hp_ratio

	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + (config.hold_y_offset if config else 55.0)

	_bullet_pool              = BulletPool.new()
	_bullet_pool.bullet_scene = _BULLET_SCENE
	_bullet_pool.pool_size    = 15
	add_child(_bullet_pool)

	_burst_timer             = Timer.new()
	_burst_timer.wait_time   = _burst_interval
	_burst_timer.autostart   = false
	_burst_timer.one_shot    = false
	_burst_timer.timeout.connect(_fire_burst)
	add_child(_burst_timer)

	# Separate signal connection so we don't interfere with BaseEnemy's hit flash.
	health.amount_changed.connect(_on_health_changed_gunship)


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.ENTER:
			_phase_enter()
		Phase.HOLD:
			_phase_hold(delta)
		Phase.RETREAT:
			_phase_retreat()


func _phase_enter() -> void:
	if global_position.y < _hold_y:
		velocity = Vector2(0.0, _entry_speed)
		move_and_slide()
	else:
		velocity = Vector2.ZERO
		_phase = Phase.HOLD
		_burst_timer.start()


func _phase_hold(delta: float) -> void:
	velocity.y = 0.0

	if _track_player:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var diff := (players[0] as Node2D).global_position.x - global_position.x
			velocity.x = sign(diff) * minf(absf(diff) * 2.0, _track_speed)
		else:
			velocity.x = 0.0
	else:
		velocity.x = 0.0

	move_and_slide()

	if health.current_health <= int(health.max_health * _retreat_hp_ratio):
		_burst_timer.stop()
		_phase = Phase.RETREAT


func _phase_retreat() -> void:
	velocity = Vector2(0.0, -_entry_speed * 1.5)
	move_and_slide()
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if cam and global_position.y < cam.global_position.y - viewport_size.y * 0.5 - 50.0:
		queue_free()


func _fire_burst() -> void:
	if _phase != Phase.HOLD:
		return
	_shoot_from_barrel(Vector2(-12.0, 8.0))
	await get_tree().create_timer(_burst_gap).timeout
	if not is_instance_valid(self):
		return
	if _phase != Phase.HOLD:
		return
	_shoot_from_barrel(Vector2(12.0, 8.0))


func _shoot_from_barrel(barrel_offset: Vector2) -> void:
	var barrel_world := global_position + barrel_offset
	var direction := Vector2.DOWN
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		direction = ((players[0] as Node2D).global_position - barrel_world).normalized()

	var bullet := _bullet_pool.acquire(barrel_world) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = _bullet_damage
	bullet.speed = _bullet_speed
	bullet.set_direction(direction)


func _on_health_changed_gunship(current: int) -> void:
	if _sprite and current <= health.max_health / 2:
		_sprite.texture = _TEXTURE_DAMAGED
```

- [ ] **Step 2: Verify no references to removed fields**

Confirm there is no reference to `fire_interval`, `_entered`, `_retreating`, `_gun_side`, `_fire_timer_node`, `bullet_pool` (exported), or `_hold_and_fire` in the saved file.

---

## Task 4: Update gunship.tscn

**Files:**
- Modify: `assault/scenes/enemies/gunship/gunship.tscn`

- [ ] **Step 1: Replace the file contents**

Replace the entire `.tscn` file with:

```
[gd_scene load_steps=11 format=3 uid="uid://gunship001assault"]

[ext_resource type="Shader" uid="uid://d3tncaxe8rph" path="res://assault/assets/shader/hit_flash_vs.tres" id="1_gs"]
[ext_resource type="Script" path="res://assault/scenes/enemies/gunship/gunship.gd" id="2_gs"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/enemies/heave_gunship.png" id="3_gs"]
[ext_resource type="Script" uid="uid://ba3eox7gg0mqf" path="res://global/components/hurtbox_component.gd" id="4_gs"]
[ext_resource type="Script" uid="uid://bmvlejhrl0dfy" path="res://global/components/health_component.gd" id="5_gs"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_gs"]
resource_local_to_scene = true
shader = ExtResource("1_gs")
shader_parameter/enabled = false
shader_parameter/flash_color = Color(1, 1, 1, 1)

[sub_resource type="CircleShape2D" id="CircleShape2D_gs"]
radius = 18.0

[sub_resource type="Animation" id="Animation_reset_gs"]
length = 0.001
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("Sprite2D:material:shader_parameter/enabled")
tracks/0/interp = 1
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0),
"transitions": PackedFloat32Array(1),
"update": 1,
"values": [false]
}

[sub_resource type="Animation" id="Animation_hit_gs"]
resource_name = "hit"
length = 0.2
tracks/0/type = "value"
tracks/0/imported = false
tracks/0/enabled = true
tracks/0/path = NodePath("Sprite2D:material:shader_parameter/enabled")
tracks/0/interp = 1
tracks/0/loop_wrap = true
tracks/0/keys = {
"times": PackedFloat32Array(0, 0.2),
"transitions": PackedFloat32Array(1, 1),
"update": 1,
"values": [true, false]
}

[sub_resource type="AnimationLibrary" id="AnimationLibrary_gs"]
_data = {
&"RESET": SubResource("Animation_reset_gs"),
&"hit": SubResource("Animation_hit_gs")
}

[node name="Gunship" type="CharacterBody2D"]
script = ExtResource("2_gs")

[node name="Sprite2D" type="Sprite2D" parent="."]
material = SubResource("ShaderMaterial_gs")
scale = Vector2(2, 2)
rotation_degrees = 180
texture = ExtResource("3_gs")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_gs")

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 512
collision_mask = 65
script = ExtResource("4_gs")
metadata/_custom_type_script = "uid://ba3eox7gg0mqf"

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("CircleShape2D_gs")
debug_color = Color(0.7, 0, 0, 0.419608)

[node name="Health" type="Node" parent="."]
script = ExtResource("5_gs")
max_health = 200
current_health = 200
metadata/_custom_type_script = "uid://bmvlejhrl0dfy"

[node name="HitFlashAnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {
&"": SubResource("AnimationLibrary_gs")
}
```

- [ ] **Step 2: Verify animation path change**

Confirm both animation track paths say `NodePath("Sprite2D:material:shader_parameter/enabled")` — not `AnimatedSprite2D`.

- [ ] **Step 3: Verify sprite node name**

Confirm the scene has a `[node name="Sprite2D" type="Sprite2D" parent="."]` node with `rotation_degrees = 180` and `scale = Vector2(2, 2)`, and there is no `AnimatedSprite2D` node.

---

## Task 5: Add Gunship Test Wave to Level 1

**Files:**
- Modify: `assault/scenes/levels/edelia/1/level_1_director.gd`

- [ ] **Step 1: Locate the drone interceptor wave (around line 206)**

Find the block:

```gdscript
		# 1.5 s — drone interceptor pair for testing; self-managed AI, no .move() needed
		b.wave(1.5, [
			b.drone_interceptor().at(-160, -420),
			b.drone_interceptor().at( 160, -420).delay(0.35),
		]),
```

- [ ] **Step 2: Insert the gunship test wave immediately after it**

Add this wave directly after the `b.wave(1.5, [...])` block, before the `# 2.0 s` comment:

```gdscript
		# 3.5 s — gunship test; self-managed AI, no .move() needed
		b.wave(3.5, [
			b.gunship().at(0, -500),
		]),
```

The result should look like:

```gdscript
		# 1.5 s — drone interceptor pair for testing; self-managed AI, no .move() needed
		b.wave(1.5, [
			b.drone_interceptor().at(-160, -420),
			b.drone_interceptor().at( 160, -420).delay(0.35),
		]),

		# 3.5 s — gunship test; self-managed AI, no .move() needed
		b.wave(3.5, [
			b.gunship().at(0, -500),
		]),

		# 2.0 s — V of 5 fighters, straight down (+ side drone screen from above)
```

- [ ] **Step 3: Verify no `.move()` call on the gunship**

The gunship manages its own AI in `_physics_process`. Adding `.move()` would attach `EnemyPathMover`, which disables `_physics_process` and breaks the AI. Confirm the line reads `b.gunship().at(0, -500)` with no `.move()`.

---

## Self-Review

### Spec coverage

| Spec requirement | Covered by task |
|-----------------|-----------------|
| Phase enum ENTER / HOLD / RETREAT | Task 3 |
| Entry: moves down at `entry_speed` until `_hold_y` | Task 3 `_phase_enter()` |
| `_hold_y` computed from camera in `_ready()` | Task 3 |
| HOLD: fixed Y, proportional X tracking capped at `track_speed` | Task 3 `_phase_hold()` |
| HOLD: burst timer fires `_fire_burst()` | Task 3 |
| HOLD → RETREAT at `retreat_hp_ratio` | Task 3 `_phase_hold()` |
| RETREAT: moves up at `entry_speed * 1.5`, freed off-screen | Task 3 `_phase_retreat()` |
| Dual-barrel: left barrel `(-12, 8)` then right `(+12, 8)` | Task 3 `_fire_burst()` |
| Burst gap via `await create_timer(_burst_gap)` | Task 3 `_fire_burst()` |
| `is_instance_valid(self)` guard after await | Task 3 `_fire_burst()` |
| Aim direction = `(player_pos - barrel_world_pos).normalized()` | Task 3 `_shoot_from_barrel()` |
| Fallback to `Vector2.DOWN` when no player | Task 3 `_shoot_from_barrel()` |
| BulletPool pool_size = 15 | Task 3 |
| Burst timer stopped on RETREAT entry | Task 3 `_phase_hold()` |
| All 9 GunshipConfig fields with correct defaults | Tasks 1 + 2 |
| Separate `health.amount_changed.connect(_on_health_changed_gunship)` | Task 3 |
| Sprite swap at ≤50% HP — one-way, no reverse | Task 3 `_on_health_changed_gunship()` |
| Sprite2D node with `rotation_degrees=180`, `scale=(2,2)` | Task 4 |
| AnimatedSprite2D removed | Task 4 |
| Animation track paths updated to `Sprite2D:...` | Task 4 |
| Gunship added to test waves in level director | Task 5 |
| No `.move()` call on WaveBuilder gunship spawn | Task 5 |

### Placeholder scan

No TBDs, TODOs, "similar to Task N", or missing code blocks found.

### Type consistency

- `_burst_timer: Timer` created in Task 3, referenced only in Task 3 — consistent.
- `_sprite: Sprite2D` assigned via `$Sprite2D` in Task 3; `$Sprite2D` matches scene node name from Task 4 — consistent.
- `_bullet_pool: BulletPool` — type matches `BulletPool.acquire()` return cast to `EnemyBullet` — consistent.
- `config: GunshipConfig` with fields `burst_interval`, `burst_gap`, etc. match Task 1 field names exactly — consistent.
- `health.amount_changed` signal emits `(current: int)` — matches handler signature `_on_health_changed_gunship(current: int)` — consistent.
