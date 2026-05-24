# DroneInterceptor + Interceptor Gatling Rework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a kamikaze `DroneInterceptor` enemy and rework `Interceptor` into a fast-firing Gatling gunship driven purely by `EnemyPathMover`.

**Architecture:** `GatlingAttackPattern` and `PlayerFocusMovement` are new standalone resources that plug into the existing `AttackController` / `EnemyPathMover` infrastructure. `DroneInterceptor` re-implements the orbit+dash AI (moved from `Interceptor`) with a one-way kamikaze DASH. `Interceptor` is stripped of its state machine and becomes a shooting platform.

**Tech Stack:** GDScript 4, Godot 4.3+, existing `AttackPatternResource`, `MovementResource`, `EnemyPathMover`, `BaseEnemy`, `BulletPool`, `AttackController`.

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `global/resources/attack/gatling_attack_pattern.gd` | Fast fire rate, small damage, scatter |
| Create | `global/resources/movement/player_focus_movement.gd` | Aim-and-fly-through movement resource |
| Modify | `assault/scenes/enemies/enemy_path_mover.gd` | Inject player direction for `PlayerFocusMovement` |
| Create | `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.gd` | Tuning resource class |
| Create | `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres` | Default values |
| Create | `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd` | Orbit+kamikaze AI |
| Create | `assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn` | Scene with Sprite2D, HurtBox, Health, HitFlash |
| Modify | `assault/scenes/enemies/interceptor/interceptor_config.gd` | Replace orbit/dash fields with Gatling fields |
| Modify | `assault/scenes/enemies/interceptor/interceptor_config.tres` | Update stored values |
| Modify | `assault/scenes/enemies/interceptor/interceptor.gd` | Remove state machine; add GatlingAttackPattern |
| Modify | `assault/scenes/systems/wave_builder.gd` | Add `drone_interceptor()` and `player_focus()` helpers |
| Modify | `assault/scenes/levels/edelia/1/level_1_director.gd` | Update wave 0 test spawns |

---

## Task 1: GatlingAttackPattern

**Files:**
- Create: `global/resources/attack/gatling_attack_pattern.gd`

- [ ] **Create the file**

```gdscript
## GatlingAttackPattern — high-cadence weapon with slight random scatter.
## Designed for Interceptor: fast fire rate, low damage, moderate range.
## fire_interval is inherited from AttackPatternResource (default 0.8 — override per ship).
class_name GatlingAttackPattern
extends AttackPatternResource

## Damage dealt per bullet.
@export var bullet_damage: int = 4
## Travel speed of each bullet (px/s). Lower speed = shorter effective range.
@export var bullet_speed: float = 220.0
## Max random rotation offset per shot (radians). 0.08 ≈ ±4.5°.
@export var spread_angle: float = 0.08
## true = aim each shot at the nearest player; false = fire in ship's facing direction.
@export var aim_at_player: bool = true
## Spawn offset relative to the ship's position.
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	bullet.speed = bullet_speed

	var base_dir: Vector2
	if aim_at_player:
		var players := ship.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			base_dir = ((players[0] as Node2D).global_position - ship.global_position).normalized()
		else:
			base_dir = Vector2.DOWN
	else:
		base_dir = Vector2.DOWN.rotated(ship.rotation)

	bullet.set_direction(base_dir.rotated(randf_range(-spread_angle, spread_angle)))
```

- [ ] **Commit**

```
git add global/resources/attack/gatling_attack_pattern.gd
git commit -m "Add GatlingAttackPattern resource"
```

---

## Task 2: PlayerFocusMovement

**Files:**
- Create: `global/resources/movement/player_focus_movement.gd`

- [ ] **Create the file**

```gdscript
## PlayerFocusMovement — makes a ship fly straight toward the player's position
## at spawn time, then continue in that direction until it exits the screen.
##
## `direction` is injected by EnemyPathMover._ready() after duplicating the resource.
## Do NOT export `direction` — each ship must get its own instance with its own direction.
class_name PlayerFocusMovement
extends MovementResource

## Fly speed in px/s.
@export var speed: float = 220.0
## Set at runtime by EnemyPathMover. Not exported — never shared between ships.
var direction: Vector2 = Vector2.DOWN

func sample(t: float) -> Vector2:
	return direction * speed * t
```

- [ ] **Commit**

```
git add global/resources/movement/player_focus_movement.gd
git commit -m "Add PlayerFocusMovement resource"
```

---

## Task 3: EnemyPathMover — inject focus direction

**Files:**
- Modify: `assault/scenes/enemies/enemy_path_mover.gd`

The insertion goes in `_ready()`, after `_initial_cam_y` is set and before `_actor.set_physics_process(false)`. The full updated `_ready()` function is:

- [ ] **Replace `_ready()` in `assault/scenes/enemies/enemy_path_mover.gd`**

Find the existing `_ready()` function (lines 34–52) and replace it entirely:

```gdscript
func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	if not _actor:
		push_error("[EnemyPathMover] Parent must be a CharacterBody2D. Freeing self.")
		queue_free()
		return

	_initial_world_pos = _actor.global_position

	_cam = _actor.get_viewport().get_camera_2d()
	if not _cam:
		push_warning("[EnemyPathMover] No active Camera2D found. Screen-exit culling will be skipped.")
	_initial_cam_y = _cam.global_position.y if _cam else 0.0

	# PlayerFocusMovement needs a per-ship direction computed from this ship's spawn
	# position. Duplicate the resource so ships in the same formation each get their
	# own instance (formations share the same resource reference via shallow dict copy).
	if movement is PlayerFocusMovement:
		movement = movement.duplicate() as PlayerFocusMovement
		var players := _actor.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			(movement as PlayerFocusMovement).direction = \
					((players[0] as Node2D).global_position - _actor.global_position).normalized()
		else:
			(movement as PlayerFocusMovement).direction = Vector2.DOWN

	# Suspend the ship's own movement AI — we own position each frame.
	# Timer-based shooting in the ship continues unaffected.
	_actor.set_physics_process(false)
	var state_machine: Node = _actor.get_node_or_null("AIStateMachine")
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED
```

- [ ] **Commit**

```
git add assault/scenes/enemies/enemy_path_mover.gd
git commit -m "EnemyPathMover: inject player direction for PlayerFocusMovement"
```

---

## Task 4: DroneInterceptorConfig

**Files:**
- Create: `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.gd`
- Create: `assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres`

- [ ] **Create `drone_interceptor_config.gd`**

```gdscript
## DroneInterceptorConfig — tuning resource for the DroneInterceptor enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
class_name DroneInterceptorConfig
extends ShipConfig

## Preferred distance from the player while orbiting (px).
@export var orbit_radius         : float = 130.0
## Angular velocity of the orbit anchor (rad/s). Positive = counter-clockwise.
@export var orbit_speed          : float = 1.8
## Movement speed during ENTER phase (px/s).
@export var approach_speed       : float = 200.0
## Maximum speed when correcting orbit position (px/s).
@export var orbit_correct_speed  : float = 160.0
## Burst speed during the kamikaze dash (px/s).
@export var dash_speed           : float = 480.0
## How far ahead to predict the player position for the dash target (seconds).
@export var dash_prediction_time : float = 0.2
```

- [ ] **Create `drone_interceptor_config.tres`**

```
[gd_resource type="Resource" script_class="DroneInterceptorConfig" format=3]

[ext_resource type="Script" path="res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.gd" id="1"]

[resource]
script = ExtResource("1")
max_health = 25
collision_damage = 30
score_value = 40
counts_toward_wave_clear = true
orbit_radius = 130.0
orbit_speed = 1.8
approach_speed = 200.0
orbit_correct_speed = 160.0
dash_speed = 480.0
dash_prediction_time = 0.2
```

- [ ] **Commit**

```
git add assault/scenes/enemies/drone_interceptor/
git commit -m "Add DroneInterceptorConfig resource"
```

---

## Task 5: DroneInterceptor script + scene

**Files:**
- Create: `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd`
- Create: `assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn`

- [ ] **Create `drone_interceptor.gd`**

```gdscript
# assault/scenes/enemies/drone_interceptor/drone_interceptor.gd
class_name DroneInterceptor
extends BaseEnemy

## Kamikaze pursuit unit. Orbits the player briefly, then locks direction and
## commits to a one-way dash — exploding on contact with the player.
##
## State machine:
##   ENTER — fly toward player until within orbit_radius.
##   ORBIT — circle the player for 1–2 seconds, then trigger DASH.
##   DASH  — lock direction to predicted player position, fly at dash_speed
##            indefinitely. Freed by off-screen check. Kamikaze on contact.
##
## No EnemyPathMover — movement is fully self-managed in _physics_process.
## Spawn with b.drone_interceptor().at(x, y) — no .move() needed.

@export var config: DroneInterceptorConfig = preload(
		"res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres")

enum Phase { ENTER, ORBIT, DASH }

# ── Tuning — copied from config in _ready ────────────────────────────────────
var _orbit_radius         : float = 130.0
var _orbit_speed          : float = 1.8
var _approach_speed       : float = 200.0
var _orbit_correct_speed  : float = 160.0
var _dash_speed           : float = 480.0
var _dash_prediction_time : float = 0.2

# ── Runtime state ─────────────────────────────────────────────────────────────
var _phase        : Phase   = Phase.ENTER
var _orbit_angle  : float   = 0.0
var _dash_timer   : float   = 0.0
var _dash_direction: Vector2 = Vector2.ZERO

const ROTATION_LERP : float = 7.0

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		health.max_health        = config.max_health
		health.current_health    = config.max_health
		score_value              = config.score_value
		_orbit_radius            = config.orbit_radius
		_orbit_speed             = config.orbit_speed
		_approach_speed          = config.approach_speed
		_orbit_correct_speed     = config.orbit_correct_speed
		_dash_speed              = config.dash_speed
		_dash_prediction_time    = config.dash_prediction_time

	## Stagger orbit angle and first dash timer so groups don't behave identically.
	_orbit_angle = randf_range(0.0, TAU)
	_dash_timer  = randf_range(1.0, 2.0)

# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	var player := _get_player()

	match _phase:
		Phase.ENTER : _phase_enter(delta, player)
		Phase.ORBIT : _phase_orbit(delta, player)
		Phase.DASH  : _phase_dash(delta)

	match _phase:
		Phase.ENTER, Phase.ORBIT:
			if player:
				_face_target(delta, player.global_position)
		Phase.DASH:
			_face_direction(delta, _dash_direction)

	move_and_slide()

# ─── ENTER ────────────────────────────────────────────────────────────────────

func _phase_enter(_delta: float, player: Node2D) -> void:
	if not player:
		velocity = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	if to_player.length() <= _orbit_radius:
		_phase = Phase.ORBIT
		return
	velocity = to_player.normalized() * _approach_speed

# ─── ORBIT ────────────────────────────────────────────────────────────────────

func _phase_orbit(delta: float, player: Node2D) -> void:
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_begin_dash(player)
		return
	if not player:
		velocity = Vector2.ZERO
		return
	_orbit_angle += _orbit_speed * delta
	var orbit_target := player.global_position \
			+ Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
	var to_target    := orbit_target - global_position
	var dist         := to_target.length()
	var speed        := clampf(dist * 4.0, 60.0, _orbit_correct_speed)
	velocity = to_target.normalized() * speed

# ─── DASH ─────────────────────────────────────────────────────────────────────

func _begin_dash(player: Node2D) -> void:
	_phase = Phase.DASH
	var predicted_pos: Vector2
	if player and player is CharacterBody2D:
		predicted_pos = player.global_position \
				+ (player as CharacterBody2D).velocity * _dash_prediction_time
	elif player:
		predicted_pos = player.global_position
	else:
		predicted_pos = global_position + Vector2(0.0, 200.0)
	_dash_direction = (predicted_pos - global_position).normalized()

func _phase_dash(_delta: float) -> void:
	velocity = _dash_direction * _dash_speed
	_check_off_screen()

func _check_off_screen() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var vp     := get_viewport().get_visible_rect().size
	var margin := 80.0
	var pos    := global_position
	if pos.y > cam.global_position.y + vp.y * 0.5 + margin \
			or pos.y < cam.global_position.y - vp.y * 0.5 - margin \
			or pos.x > cam.global_position.x + vp.x * 0.5 + margin \
			or pos.x < cam.global_position.x - vp.x * 0.5 - margin:
		queue_free()

# ─── CONTACT KILL ─────────────────────────────────────────────────────────────

## Override: collision_mask = 128 (player HurtBox) so we detect contact and kamikaze.
func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	var hb := HitBox.new()
	hb.collision_layer = 256
	hb.collision_mask  = 128   # player HurtBox — fires area_entered on contact
	hb.damage = config.collision_damage if config else 30
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	hb.area_entered.connect(_on_contact_hit)
	add_child(hb)

func _on_contact_hit(_area: Area2D) -> void:
	## Guard against double-firing before queue_free processes.
	if health.current_health > 0:
		health.set_health(0)

# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D

func _face_target(delta: float, target_pos: Vector2) -> void:
	var dir        := (target_pos - global_position).normalized()
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)

func _face_direction(delta: float, dir: Vector2) -> void:
	if dir.length_squared() < 0.001:
		return
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
```

- [ ] **Create `drone_interceptor.tscn`**

```
[gd_scene format=3 uid="uid://droneintrcptr1"]

[ext_resource type="Shader" uid="uid://d3tncaxe8rph" path="res://assault/assets/shader/hit_flash_vs.tres" id="1_dri"]
[ext_resource type="Script" path="res://assault/scenes/enemies/drone_interceptor/drone_interceptor.gd" id="2_dri"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/enemies/drone_2.png" id="3_dri"]
[ext_resource type="Script" uid="uid://ba3eox7gg0mqf" path="res://global/components/hurtbox_component.gd" id="4_dri"]
[ext_resource type="Script" uid="uid://bmvlejhrl0dfy" path="res://global/components/health_component.gd" id="5_dri"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_dri"]
resource_local_to_scene = true
shader = ExtResource("1_dri")
shader_parameter/enabled = false
shader_parameter/flash_color = Color(1, 1, 1, 1)

[sub_resource type="CircleShape2D" id="CircleShape2D_dri"]
radius = 10.0

[sub_resource type="Animation" id="Animation_reset_dri"]
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

[sub_resource type="Animation" id="Animation_hit_dri"]
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

[sub_resource type="AnimationLibrary" id="AnimationLibrary_dri"]
_data = {
&"RESET": SubResource("Animation_reset_dri"),
&"hit": SubResource("Animation_hit_dri")
}

[node name="DroneInterceptor" type="CharacterBody2D"]
script = ExtResource("2_dri")

[node name="Sprite2D" type="Sprite2D" parent="."]
material = SubResource("ShaderMaterial_dri")
texture = ExtResource("3_dri")
scale = Vector2(2, 2)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("CircleShape2D_dri")

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 512
collision_mask = 97
script = ExtResource("4_dri")
metadata/_custom_type_script = "uid://ba3eox7gg0mqf"

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("CircleShape2D_dri")
debug_color = Color(0.7, 0, 0, 0.42)

[node name="Health" type="Node" parent="."]
script = ExtResource("5_dri")
max_health = 25
current_health = 25
metadata/_custom_type_script = "uid://bmvlejhrl0dfy"

[node name="HitFlashAnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {
&"": SubResource("AnimationLibrary_dri")
}
```

- [ ] **Commit**

```
git add assault/scenes/enemies/drone_interceptor/
git commit -m "Add DroneInterceptor enemy (kamikaze orbit+dash)"
```

---

## Task 6: Interceptor rework

**Files:**
- Modify: `assault/scenes/enemies/interceptor/interceptor_config.gd`
- Modify: `assault/scenes/enemies/interceptor/interceptor_config.tres`
- Modify: `assault/scenes/enemies/interceptor/interceptor.gd`

The `.tscn` is **not modified** — it references the same script path.

- [ ] **Replace `interceptor_config.gd` entirely**

```gdscript
## InterceptorConfig — tuning resource for the Interceptor enemy.
## Extends ShipConfig (provides max_health, collision_damage, score_value).
class_name InterceptorConfig
extends ShipConfig

## Seconds between shots (fire rate = 1 / fire_interval).
@export var fire_interval : float = 0.09
## Damage dealt per bullet.
@export var bullet_damage : int   = 4
## Travel speed of each bullet (px/s). Lower = shorter effective range.
@export var bullet_speed  : float = 220.0
## Max random rotation scatter per shot (radians). 0.08 ≈ ±4.5°.
@export var spread_angle  : float = 0.08
```

- [ ] **Replace `interceptor_config.tres` entirely**

```
[gd_resource type="Resource" script_class="InterceptorConfig" format=3]

[ext_resource type="Script" path="res://assault/scenes/enemies/interceptor/interceptor_config.gd" id="1"]

[resource]
script = ExtResource("1")
max_health = 70
collision_damage = 20
score_value = 75
counts_toward_wave_clear = true
fire_interval = 0.09
bullet_damage = 4
bullet_speed = 220.0
spread_angle = 0.08
```

- [ ] **Replace `interceptor.gd` entirely**

```gdscript
# assault/scenes/enemies/interceptor/interceptor.gd
class_name Interceptor
extends BaseEnemy

## Flying Gatling gunship. No self-managed movement AI.
## Movement is fully delegated to EnemyPathMover via WaveBuilder .move().
##
## Typical usages:
##   b.interceptor().at(x, y).move(b.straight(200))       — strafing run
##   b.interceptor().at(x, y).move(b.player_focus(240))   — locks on and flies through

@export var config: InterceptorConfig = preload(
		"res://assault/scenes/enemies/interceptor/interceptor_config.tres")

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _bullet_pool       : BulletPool
var _attack_controller : AttackController

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health     = config.max_health
		health.current_health = config.max_health
		score_value           = config.score_value

	_bullet_pool            = BulletPool.new()
	_bullet_pool.bullet_scene = _BULLET_SCENE
	## pool_size: at 0.09 s interval and ~1.5 s effective range → ceil(1.5/0.09)+buffer = 20.
	_bullet_pool.pool_size  = 20
	add_child(_bullet_pool)

	var pattern              := GatlingAttackPattern.new()
	pattern.fire_interval    = config.fire_interval if config else 0.09
	pattern.bullet_damage    = config.bullet_damage if config else 4
	pattern.bullet_speed     = config.bullet_speed  if config else 220.0
	pattern.spread_angle     = config.spread_angle  if config else 0.08

	_attack_controller             = AttackController.new()
	_attack_controller.pattern     = pattern
	_attack_controller.bullet_pool = _bullet_pool
	add_child(_attack_controller)
```

- [ ] **Commit**

```
git add assault/scenes/enemies/interceptor/
git commit -m "Rework Interceptor: Gatling weapon, remove orbit/dash AI"
```

---

## Task 7: WaveBuilder additions

**Files:**
- Modify: `assault/scenes/systems/wave_builder.gd`

Two additions needed: a new ship constructor method, a new movement helper, and a new scene path constant.

- [ ] **Add `drone_interceptor()` to the ship constructors block** (after the existing `interceptor()` line)

```gdscript
func drone_interceptor() -> SpawnConfig: return SpawnConfig.new(DRONE_INTERCEPTOR)
```

- [ ] **Add `player_focus()` to the movement helpers block** (after the existing `curve()` method)

```gdscript
## Fly straight toward the player's position at spawn time, then continue
## in that direction until the ship exits the screen.
func player_focus(speed: float = 220.0) -> PlayerFocusMovement:
	var m := PlayerFocusMovement.new()
	m.speed = speed
	return m
```

- [ ] **Add `DRONE_INTERCEPTOR` to the scene path constants block** (after the existing `INTERCEPTOR` line)

```gdscript
const DRONE_INTERCEPTOR := "res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn"
```

- [ ] **Commit**

```
git add assault/scenes/systems/wave_builder.gd
git commit -m "WaveBuilder: add drone_interceptor() and player_focus() helpers"
```

---

## Task 8: Level 1 Director — update test spawns

**Files:**
- Modify: `assault/scenes/levels/edelia/1/level_1_director.gd`

The wave at `0.0s` currently spawns interceptors without `.move()` (the old self-managed AI). Update it to use `player_focus`.

- [ ] **Replace the wave at `0.0s`** in `_build_section_1()`

Find:
```gdscript
		# 0.0 s — interceptor pair for early testing; self-managed movement, no .move() needed
		b.wave(0.0, [
			b.interceptor().at(-200, -420),
			b.interceptor().at( 200, -420).delay(0.4),
		]),
```

Replace with:
```gdscript
		# 0.0 s — interceptor pair: lock onto player and fly through with Gatling
		b.wave(0.0, [
			b.interceptor().at(-200, -420).move(b.player_focus(240)),
			b.interceptor().at( 200, -420).move(b.player_focus(240)).delay(0.4),
		]),
```

- [ ] **Commit**

```
git add assault/scenes/levels/edelia/1/level_1_director.gd
git commit -m "Level 1: update interceptor test wave to use player_focus movement"
```

---

## Verification

After all tasks are complete, open the game and load Level 1 Section 1 (deep_space). Confirm:

1. **Interceptors (0.0 s)**: Two interceptors fly from above toward where the player is standing, spraying fast scattered bullets. They continue in that direction after passing the player and exit the screen. No freezing at spawn position.

2. **Gatling feel**: Bullets are rapid (≈10/sec), small, with slight side-scatter. Not pinpoint accurate.

3. `PlayerFocusMovement` reuse: Interceptors spawned in formation should each independently target the player's position from their own spawn point (not both using the same direction).

4. **DroneInterceptor readiness** (add a test wave manually if desired):
   ```gdscript
   b.wave(5.0, [
       b.drone_interceptor().at(-100, -400),
       b.drone_interceptor().at( 100, -400).delay(0.3),
   ])
   ```
   Drones should orbit briefly (1–2 s) then make a one-way dash at the player. Contact should kill both drone and deal damage to the player.
