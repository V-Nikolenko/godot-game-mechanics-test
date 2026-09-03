# Assault Race Mode — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the race-mode framework and a playable race level (reusing Level 1's
background) where the player races generic AI rivals to a finish line, with dash panels,
asteroids, and lasers — all spawned via WaveManager.

**Architecture:** Relative-progress race model on the existing pinned-camera vertical
shmup. A `RaceParticipant` component (on the player *and* every AI racer) owns abstract
`progress`; a `RaceDirector` sorts standings and maps each rival's `progress` delta vs the
player to an on-screen Y. The player's throttle is its screen-Y (top = faster); dash panels
boost progress (and, for the player, background scroll speed). AI racers (`RacerBase`)
self-drive X via a steering node and read Y from the director.

**Tech stack:** Godot 4.6, GDScript (static typing), CharacterBody2D/Area2D, existing
WaveManager / WaveBuilder / Shield / Health / bubble-shield / laser / asteroid systems.

**Conventions for this plan:**
- **No automated tests / no commit steps** (per project decision: there is no test
  framework, and the user handles all git commits). Each task ends when the file(s) compile
  and the described wiring is in place; the user playtests.
- All new race code lives under `assault/scenes/race/` and `assault/scenes/levels/race/`.
- All scripts use full static typing and `class_name` where a type is referenced elsewhere.

**Deviations from the spec (deliberate, discovered while reading the code):**
1. `RacerBase` extends `CharacterBody2D` directly (NOT `BaseEnemy`) — `BaseEnemy` hardcodes
   a shader-`HitFlashAnimationPlayer` and `ShipConfig` coupling we don't want on rivals.
   Racers get their own `Health` + `HurtBox` + a simple modulate hit-flash.
2. `RacerShield extends Shield`, overriding `_ready()` so it uses an exported fixed charge
   count instead of `ShipProgressionState` (which is player-only). This keeps the reused
   `bubble_shield.tscn` visual working (its `setup()` is typed to `Shield`).
3. The three steering subsystems are consolidated into one `RacerSteering` node (obstacle
   avoidance + bullet dodge + dash seek) for a faster vertical slice.
4. **Rival-vs-rival** bullet/ram damage and the per-racer signature behaviors are **Phase 2**.
   Phase-1 generic racers shoot the *player* (existing `enemy_bullet`) to prove "racers
   shoot," take damage from the player/obstacles, and can be eliminated.

---

## Tuning Constants (single source of truth)

Use these exact values; they keep the math consistent across tasks. All are exported so
they can be retuned in-editor.

| Constant | Value | Where |
|---|---|---|
| `min_speed` | `60.0` | `RaceParticipant` |
| `max_speed` | `220.0` | `RaceParticipant` |
| `track_length` | `10000.0` | `RaceDirector` |
| `screen_y_scale` | `1.0` (px per progress unit) | `RaceDirector` |
| `player_anchor_y` | `360.0` | `RaceDirector` |
| `max_offset_y` | `420.0` | `RaceDirector` |
| player throttle `top_y` / `bottom_y` | `80.0` / `640.0` | `PlayerThrottleAdapter` |
| racer resting throttle | `0.62` | `GenericRacerBehavior` |
| dash `boost_mult` / `boost_duration` | `1.8` / `2.0` s | `DashPanel` |
| dash background scroll mult | `2.0` | `DashPanel`/adapter |
| damage setback (progress lost) | `400.0` | `RacerBase` / `PlayerThrottleAdapter` |
| racer HP | `60` | racer scene |
| racer shield charges | `2` | racer scene |

**Collision layers (existing):** player body 4, player_hurtbox 128, enemy_hitbox 256,
enemy_hurtbox 512, bullets 64, rockets 32, asteroid-contact 1024.
**Racer HurtBox:** layer **512**, mask **64 | 1024 = 1088** (player bullets + asteroid
contact). The laser hazard already scans layer 512, so lasers kill racers with no extra mask.

**Groups:** `player` (existing), `racers`, `race_director`, `dash_panels`.

---

## Task 1: Background scroll-speed multiplier hook

**Files:**
- Modify: `global/systems/background_controller.gd`
- Modify: `assault/scenes/levels/edelia/1/level_1_background.gd`

- [ ] **Step 1: Add a virtual `set_scroll_multiplier` to the base controller**

In `global/systems/background_controller.gd`, add after `transition_to()`:

```gdscript
## Multiply all scrolling-layer speeds by [m] (1.0 = normal). Default is a no-op;
## subclasses that scroll layers override this. Used by dash panels to speed up
## the world while the player is boosting.
func set_scroll_multiplier(m: float) -> void:
	pass
```

- [ ] **Step 2: Apply the multiplier in `Level1Background`**

In `assault/scenes/levels/edelia/1/level_1_background.gd`:

Add a member near the scroll accumulators (after line ~217):

```gdscript
## Global multiplier on every per-layer scroll speed (dash-panel boost).
var _scroll_multiplier: float = 1.0
```

Add the override (anywhere at top level, e.g. just before `_process`):

```gdscript
func set_scroll_multiplier(m: float) -> void:
	_scroll_multiplier = maxf(0.0, m)
```

Then multiply each scroll accumulation in `_process(delta)` by `_scroll_multiplier`.
Replace the existing block:

```gdscript
	_scroll_stars_base    += delta * speed_stars_base
	_scroll_stars_overlay += delta * speed_stars_overlay
	_scroll_nebula        += delta * speed_nebula
	_scroll_cloud_1       += delta * speed_cloud_1
	_scroll_cloud_2       += delta * speed_cloud_2
	_scroll_cloud_3       += delta * speed_cloud_3
	_scroll_cloud_4       += delta * speed_cloud_4
	_scroll_surface       += delta * speed_surface
```

with:

```gdscript
	var m: float = _scroll_multiplier
	_scroll_stars_base    += delta * speed_stars_base    * m
	_scroll_stars_overlay += delta * speed_stars_overlay * m
	_scroll_nebula        += delta * speed_nebula        * m
	_scroll_cloud_1       += delta * speed_cloud_1       * m
	_scroll_cloud_2       += delta * speed_cloud_2       * m
	_scroll_cloud_3       += delta * speed_cloud_3       * m
	_scroll_cloud_4       += delta * speed_cloud_4       * m
	_scroll_surface       += delta * speed_surface       * m
```

(Asteroid-layer scroll speeds are left unmultiplied — they're one-shot passes, irrelevant
to the race.)

---

## Task 2: `RaceParticipant` component

**Files:**
- Create: `assault/scenes/race/race_participant.gd`

- [ ] **Step 1: Write the component**

```gdscript
## RaceParticipant — attached to EVERY race ship (player and AI rivals).
## Owns the abstract race `progress` and converts a 0..1 throttle into forward speed.
## Registers with the RaceDirector (found via the "race_director" group) on ready.
class_name RaceParticipant
extends Node

signal finished_race(participant: RaceParticipant)

## Throttle range. current_speed = lerp(min_speed, max_speed, throttle) * dash boost.
@export var min_speed: float = 60.0
@export var max_speed: float = 220.0
## True on the player's participant — the director maps every rival's Y relative to it.
@export var is_player: bool = false

var progress: float = 0.0
var throttle: float = 0.5
var current_speed: float = 0.0
var finished: bool = false

var _boost_mult: float = 1.0
var _boost_timer: Timer = null
var _director: RaceDirector = null

func _ready() -> void:
	_boost_timer = Timer.new()
	_boost_timer.one_shot = true
	_boost_timer.timeout.connect(func() -> void: _boost_mult = 1.0)
	add_child(_boost_timer)

	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	if _director:
		_director.register(self)
	else:
		push_warning("[RaceParticipant] No RaceDirector found in group 'race_director'.")

func set_throttle(t: float) -> void:
	throttle = clampf(t, 0.0, 1.0)

## Timed multiplicative boost on speed (dash panel).
func apply_dash_boost(mult: float, duration: float) -> void:
	_boost_mult = maxf(_boost_mult, mult)
	_boost_timer.start(duration)

## Knock the ship back along the track (damage setback). Clamped at 0.
func apply_setback(amount: float) -> void:
	progress = maxf(0.0, progress - amount)

func _physics_process(delta: float) -> void:
	if finished:
		return
	current_speed = lerpf(min_speed, max_speed, throttle) * _boost_mult
	progress += current_speed * delta
	if _director and progress >= _director.track_length:
		progress = _director.track_length
		finished = true
		finished_race.emit(self)
		_director.notify_finished(self)

func _exit_tree() -> void:
	if _director:
		_director.unregister(self)
```

---

## Task 3: `RaceDirector`

**Files:**
- Create: `assault/scenes/race/race_director.gd`

- [ ] **Step 1: Write the director**

```gdscript
## RaceDirector — one per race level. Owns standings (sorted by progress), maps each
## AI rival's on-screen Y from its progress delta vs the player, and fires finish/fail.
## Add this node to the "race_director" group in the scene so participants can find it.
class_name RaceDirector
extends Node

signal standings_changed(standings: Array)      ## Array[RaceParticipant], leader first
signal race_finished(results: Array)            ## Array[RaceParticipant], finish order
signal race_failed                              ## player destroyed

## Distance (progress units) to the finish line.
@export var track_length: float = 10000.0
## Pixels of on-screen Y per unit of progress difference vs the player.
@export var screen_y_scale: float = 1.0
## Screen-Y a rival converges to when level with the player on progress.
@export var player_anchor_y: float = 360.0
## Max pixels a rival's Y can deviate from the anchor (clamps far ships on/near screen).
@export var max_offset_y: float = 420.0

var _participants: Array[RaceParticipant] = []
var _player: RaceParticipant = null
var _results: Array[RaceParticipant] = []
var _race_over: bool = false

func register(p: RaceParticipant) -> void:
	if p not in _participants:
		_participants.append(p)
	if p.is_player:
		_player = p

func unregister(p: RaceParticipant) -> void:
	_participants.erase(p)

## Connect the player ship's Health so destruction fails the race.
## Called by RaceLevel1Config after the player's RaceParticipant exists.
func bind_player_health(health: Health) -> void:
	if health and not health.amount_changed.is_connected(_on_player_health_changed):
		health.amount_changed.connect(_on_player_health_changed)

func get_player() -> RaceParticipant:
	return _player

## On-screen Y for a rival: ahead (more progress) → higher up (smaller y).
func get_screen_y(p: RaceParticipant) -> float:
	if _player == null or p == _player:
		return player_anchor_y
	var delta: float = p.progress - _player.progress
	var offset: float = clampf(delta * screen_y_scale, -max_offset_y, max_offset_y)
	return player_anchor_y - offset

## Standings sorted leader-first (highest progress first).
func get_standings() -> Array:
	var sorted: Array = _participants.duplicate()
	sorted.sort_custom(func(a: RaceParticipant, b: RaceParticipant) -> bool:
		return a.progress > b.progress)
	return sorted

## The participant directly ahead of [p] in standings (null if leader).
func get_ahead(p: RaceParticipant) -> RaceParticipant:
	var s: Array = get_standings()
	var i: int = s.find(p)
	return s[i - 1] if i > 0 else null

## The participant directly behind [p] in standings (null if last).
func get_behind(p: RaceParticipant) -> RaceParticipant:
	var s: Array = get_standings()
	var i: int = s.find(p)
	return s[i + 1] if i >= 0 and i < s.size() - 1 else null

func notify_finished(p: RaceParticipant) -> void:
	if p not in _results:
		_results.append(p)
	if p == _player and not _race_over:
		_race_over = true
		race_finished.emit(_results.duplicate())

func _process(_delta: float) -> void:
	if _race_over:
		return
	standings_changed.emit(get_standings())

func _on_player_health_changed(current: int) -> void:
	if current <= 0 and not _race_over:
		_race_over = true
		race_failed.emit()
```

---

## Task 4: `RacerShield`

**Files:**
- Create: `assault/scenes/race/racer_shield.gd`

- [ ] **Step 1: Write a fixed-charge shield that reuses the player's `Shield` interface**

```gdscript
## RacerShield — a fixed-charge bubble shield for AI racers. Extends Shield so the
## reused bubble_shield.tscn visual (setup(shield: Shield)) works unchanged, but drops
## the player-only ShipProgressionState coupling by overriding _ready().
class_name RacerShield
extends Shield

## How many hits this racer can absorb before HP damage.
@export var charges: int = 2

func _ready() -> void:
	permanent_max = charges
	permanent_active = charges
	temporary_count = 0
	is_hacked = false

	_regen_timer = Timer.new()
	_regen_timer.one_shot = true
	_regen_timer.wait_time = REGEN_INTERVAL_SEC
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)
	_emit_snapshot()
```

(`consume_one()`, `_on_regen_tick()`, `_emit_snapshot()` and the signals are inherited
from `Shield`. The override simply skips the `ShipProgressionState` lookup and its
`permanent_shield_count_changed` connection.)

---

## Task 5: `RacerSteering` (obstacle avoidance + bullet dodge + dash seek)

**Files:**
- Create: `assault/scenes/race/racer_steering.gd`

- [ ] **Step 1: Write the consolidated steering node**

```gdscript
## RacerSteering — produces a target X for the racer by combining:
##   • obstacle avoidance (groups "asteroids", "mines", active laser columns)
##   • dash-panel seeking (group "dash_panels")
##   • bullet dodge (an Area2D sensor masked to bullet layers 64|256)
## Returns a desired world-X via get_target_x(current_x). Pure lateral steering;
## the racer owns its actual movement.
class_name RacerSteering
extends Node

## How far ahead (smaller Y = ahead) to look for hazards, in world px.
@export var lookahead_y: float = 260.0
## Lateral danger radius for group-scanned hazards.
@export var avoid_radius: float = 120.0
## How strongly to seek a reachable dash panel (0..1 blend weight).
@export var dash_seek_weight: float = 0.6
## World-X clamp (arena horizontal bounds).
@export var min_x: float = -80.0
@export var max_x: float = 1360.0

var _actor: Node2D = null
var _bullet_sensor: Area2D = null

func _ready() -> void:
	_actor = get_parent() as Node2D
	_bullet_sensor = Area2D.new()
	_bullet_sensor.collision_layer = 0
	_bullet_sensor.collision_mask = 64 | 256   ## player bullets + enemy/rival bullets
	_bullet_sensor.monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 90.0
	shape.shape = circle
	_bullet_sensor.add_child(shape)
	add_child(_bullet_sensor)

## Compute the desired world-X for this frame given the racer's current X.
func get_target_x(current_x: float) -> float:
	if _actor == null:
		return current_x
	var pos: Vector2 = _actor.global_position
	var target_x: float = current_x

	# 1) Dash-panel seeking — steer toward the nearest reachable panel ahead.
	var panel := _nearest_ahead("dash_panels", pos)
	if panel != null:
		target_x = lerpf(current_x, panel.global_position.x, dash_seek_weight)

	# 2) Obstacle avoidance — push away from nearby hazards ahead.
	var avoid := _avoidance_push(pos, ["asteroids", "mines"])
	target_x += avoid

	# 3) Bullet dodge — sidestep overlapping incoming bullets.
	target_x += _bullet_dodge_push(pos)

	return clampf(target_x, min_x, max_x)

func _nearest_ahead(group: String, pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = lookahead_y
	for n in get_tree().get_nodes_in_group(group):
		var n2d := n as Node2D
		if n2d == null:
			continue
		var dy: float = pos.y - n2d.global_position.y   ## >0 means the node is ahead (above)
		if dy > 0.0 and dy < best_d:
			best_d = dy
			best = n2d
	return best

func _avoidance_push(pos: Vector2, groups: Array) -> float:
	var push: float = 0.0
	for group in groups:
		for n in get_tree().get_nodes_in_group(group):
			var n2d := n as Node2D
			if n2d == null:
				continue
			var diff: Vector2 = pos - n2d.global_position
			if absf(diff.y) > lookahead_y or absf(diff.x) > avoid_radius:
				continue
			var away: float = signf(diff.x) if absf(diff.x) > 0.5 else 1.0
			var strength: float = (avoid_radius - absf(diff.x)) / avoid_radius
			push += away * strength * avoid_radius
	return push

func _bullet_dodge_push(pos: Vector2) -> float:
	var push: float = 0.0
	for area in _bullet_sensor.get_overlapping_areas():
		var a2d := area as Node2D
		if a2d == null:
			continue
		var dx: float = pos.x - a2d.global_position.x
		var away: float = signf(dx) if absf(dx) > 0.5 else 1.0
		push += away * 60.0
	return push
```

---

## Task 6: `RacerBehavior` base + `GenericRacerBehavior`

**Files:**
- Create: `assault/scenes/race/behaviors/racer_behavior.gd`
- Create: `assault/scenes/race/behaviors/generic_racer_behavior.gd`

- [ ] **Step 1: Write the behavior base**

```gdscript
## RacerBehavior — base "brain" for a racer. Phase-2 racers subclass this to add
## signature abilities. The base provides references and harmless defaults.
class_name RacerBehavior
extends Node

var racer: RacerBase = null
var participant: RaceParticipant = null
var director: RaceDirector = null

func setup(p_racer: RacerBase, p_participant: RaceParticipant, p_director: RaceDirector) -> void:
	racer = p_racer
	participant = p_participant
	director = p_director

## Resting throttle (0..1). Override to modulate (e.g. boost to outrun).
func get_throttle() -> float:
	return 0.5

## Called each physics frame (e.g. to decide shooting). Default no-op.
func process_behavior(_delta: float) -> void:
	pass
```

- [ ] **Step 2: Write the generic Phase-1 brain**

```gdscript
## GenericRacerBehavior — proves the Phase-1 loop: hold a slightly-above-player pace,
## and occasionally fire a forward bullet at the player so rivals apply pressure.
class_name GenericRacerBehavior
extends RacerBehavior

## Resting throttle, intentionally above the player's mid-box 0.5 for constant pressure.
@export var resting_throttle: float = 0.62
@export var fire_interval: float = 1.6
@export var bullet_damage: int = 10
@export var bullet_speed: float = 240.0

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _pool: BulletPool = null
var _fire_timer: Timer = null

func _ready() -> void:
	_pool = BulletPool.new()
	_pool.bullet_scene = _BULLET_SCENE
	_pool.pool_size = 8
	add_child(_pool)

	_fire_timer = Timer.new()
	_fire_timer.wait_time = fire_interval
	_fire_timer.one_shot = false
	_fire_timer.timeout.connect(_fire_at_player)
	add_child(_fire_timer)
	_fire_timer.start()

func get_throttle() -> float:
	return resting_throttle

func _fire_at_player() -> void:
	if racer == null or not is_instance_valid(racer):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var muzzle: Vector2 = racer.global_position + Vector2(0.0, -24.0)  ## just ahead (up)
	var dir: Vector2 = ((players[0] as Node2D).global_position - muzzle).normalized()
	var bullet := _pool.acquire(muzzle) as EnemyBullet
	if bullet == null:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	bullet.speed = bullet_speed
	bullet.set_direction(dir)
```

---

## Task 7: `RacerBase` script

**Files:**
- Create: `assault/scenes/race/racer_base.gd`

- [ ] **Step 1: Write the racer body script**

```gdscript
## RacerBase — an AI race ship. Standalone CharacterBody2D (not BaseEnemy) so it avoids
## the shader hit-flash + ShipConfig coupling. Composes Health, HurtBox, a RacerShield,
## a RaceParticipant, a RacerSteering node, and a RacerBehavior. Owns its full transform:
## X from steering, Y from RaceDirector.get_screen_y(participant).
class_name RacerBase
extends CharacterBody2D

## Damage knocks the racer back along the track by this many progress units.
@export var setback_on_hit: float = 400.0
## How fast the racer slides toward its steering target X (px/s).
@export var lateral_speed: float = 420.0

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var shield: RacerShield = $RacerShield
@onready var participant: RaceParticipant = $RaceParticipant
@onready var steering: RacerSteering = $RacerSteering
@onready var behavior: RacerBehavior = $Behavior
@onready var _sprite: Sprite2D = $Sprite2D

var _director: RaceDirector = null
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("racers")
	hurt_box.collision_layer = 512
	hurt_box.collision_mask = 64 | 1024   ## player bullets + asteroid contact
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)

	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	behavior.setup(self, participant, _director)

func _physics_process(delta: float) -> void:
	# Throttle from the brain.
	participant.set_throttle(behavior.get_throttle())
	behavior.process_behavior(delta)

	# X: slide toward the steering target.
	var target_x: float = steering.get_target_x(global_position.x)
	var new_x: float = move_toward(global_position.x, target_x, lateral_speed * delta)

	# Y: dictated by race standing.
	var new_y: float = _director.get_screen_y(participant) if _director else global_position.y

	global_position = Vector2(new_x, new_y)

func _on_received_damage(damage: int) -> void:
	# Shield absorbs one hit; otherwise HP takes it. Either way, setback + flash.
	participant.apply_setback(setback_on_hit)
	_flash()
	if shield.consume_one():
		return
	health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current <= 0:
		queue_free()   ## eliminated; _exit_tree on RaceParticipant unregisters it

func _flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.modulate = Color(1.0, 0.4, 0.4, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)
```

---

## Task 8: `racer_base.tscn` (generic racer scene)

**Files:**
- Create: `assault/scenes/race/racer_base.tscn`

- [ ] **Step 1: Author the scene**

This scene is the Phase-1 generic racer (uses `fang.png` as a placeholder visual and the
`GenericRacerBehavior` brain). The bubble-shield visual is added in code is NOT required
for Phase 1 functionality, so it is omitted here (the `RacerShield` data layer is what
matters); a visual can be added in Phase 2.

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/racer_base.gd" id="1_racer"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/racers/fang.png" id="2_tex"]
[ext_resource type="Script" path="res://global/components/hurtbox_component.gd" id="3_hurt"]
[ext_resource type="Script" path="res://global/components/health_component.gd" id="4_health"]
[ext_resource type="Script" path="res://assault/scenes/race/racer_shield.gd" id="5_shield"]
[ext_resource type="Script" path="res://assault/scenes/race/race_participant.gd" id="6_part"]
[ext_resource type="Script" path="res://assault/scenes/race/racer_steering.gd" id="7_steer"]
[ext_resource type="Script" path="res://assault/scenes/race/behaviors/generic_racer_behavior.gd" id="8_brain"]

[sub_resource type="CircleShape2D" id="Circle_body"]
radius = 18.0

[sub_resource type="CircleShape2D" id="Circle_hurt"]
radius = 18.0

[node name="RacerBase" type="CharacterBody2D"]
script = ExtResource("1_racer")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_tex")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("Circle_body")

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 512
collision_mask = 1088
script = ExtResource("3_hurt")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("Circle_hurt")

[node name="Health" type="Node" parent="."]
script = ExtResource("4_health")
max_health = 60
current_health = 60

[node name="RacerShield" type="Node" parent="."]
script = ExtResource("5_shield")
charges = 2

[node name="RaceParticipant" type="Node" parent="."]
script = ExtResource("6_part")

[node name="RacerSteering" type="Node" parent="."]
script = ExtResource("7_steer")

[node name="Behavior" type="Node" parent="."]
script = ExtResource("8_brain")
```

Note: the script `@onready var behavior: RacerBehavior = $Behavior` resolves because
`GenericRacerBehavior extends RacerBehavior`.

> **Important — load_steps:** the count above (`6`) is illustrative; when you author the
> file, let Godot recompute it, or set `load_steps` to `(number of ext_resource +
> sub_resource lines) + 1`. An exact value isn't required for the scene to load.

---

## Task 9: `DashPanel`

**Files:**
- Create: `assault/scenes/race/dash_panel.gd`
- Create: `assault/scenes/race/dash_panel.tscn`

- [ ] **Step 1: Write the script**

```gdscript
## DashPanel — a screen-space speed pad. When a race ship overlaps, it boosts that ship's
## RaceParticipant; for the player it also speeds up the background scroll for the boost
## duration. Per-ship re-trigger cooldown prevents repeat triggers while overlapping.
class_name DashPanel
extends Area2D

@export var boost_mult: float = 1.8
@export var boost_duration: float = 2.0
@export var scroll_mult: float = 2.0   ## player-only background speed-up
@export var retrigger_cooldown: float = 1.0

var _cooldowns: Dictionary = {}   ## RaceParticipant -> remaining cooldown seconds

func _ready() -> void:
	add_to_group("dash_panels")
	collision_layer = 0
	collision_mask = 1 | 4   ## enemy/racer bodies (1) + player body (4)
	monitoring = true
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	for p in _cooldowns.keys():
		_cooldowns[p] -= delta
	for p in _cooldowns.keys().filter(func(k): return _cooldowns[k] <= 0.0):
		_cooldowns.erase(p)

func _on_body_entered(body: Node) -> void:
	var participant := body.get_node_or_null("RaceParticipant") as RaceParticipant
	if participant == null:
		return
	if _cooldowns.has(participant):
		return
	_cooldowns[participant] = retrigger_cooldown
	participant.apply_dash_boost(boost_mult, boost_duration)
	if participant.is_player:
		_boost_background(body)

func _boost_background(player_body: Node) -> void:
	var bg := player_body.get_tree().get_first_node_in_group("background") as BackgroundController
	if bg:
		bg.set_scroll_multiplier(scroll_mult)
		await get_tree().create_timer(boost_duration).timeout
		if is_instance_valid(bg):
			bg.set_scroll_multiplier(1.0)
```

- [ ] **Step 2: Author the scene**

Use a simple colored rectangle as the placeholder visual (no art dependency).

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/dash_panel.gd" id="1_dash"]

[sub_resource type="RectangleShape2D" id="Rect_dash"]
size = Vector2(120, 60)

[node name="DashPanel" type="Area2D"]
script = ExtResource("1_dash")

[node name="Visual" type="ColorRect" parent="."]
offset_left = -60.0
offset_top = -30.0
offset_right = 60.0
offset_bottom = 30.0
color = Color(0.2, 0.8, 1, 0.55)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("Rect_dash")
```

---

## Task 10: `PlayerThrottleAdapter`

**Files:**
- Create: `assault/scenes/race/player_throttle_adapter.gd`

- [ ] **Step 1: Write the adapter**

```gdscript
## PlayerThrottleAdapter — attached to the player ship at race start by RaceLevel1Config.
## Maps the player's screen-Y to a 0..1 throttle (top = fast) and feeds it to the player's
## RaceParticipant. Also applies a progress setback when the player takes damage so getting
## hit costs race position, matching the rivals.
class_name PlayerThrottleAdapter
extends Node

## Screen-Y mapped to throttle 1.0 (top, fastest) and 0.0 (bottom, slowest).
@export var top_y: float = 80.0
@export var bottom_y: float = 640.0
## Progress lost when the player is hit.
@export var setback_on_hit: float = 400.0

var _ship: Node2D = null
var _participant: RaceParticipant = null
var _last_health: int = -1

func setup(ship: Node2D, participant: RaceParticipant, health: Health) -> void:
	_ship = ship
	_participant = participant
	if health:
		_last_health = health.current_health
		health.amount_changed.connect(_on_health_changed)

func _physics_process(_delta: float) -> void:
	if _ship == null or _participant == null:
		return
	var t: float = clampf(inverse_lerp(bottom_y, top_y, _ship.global_position.y), 0.0, 1.0)
	_participant.set_throttle(t)

func _on_health_changed(current: int) -> void:
	if _last_health >= 0 and current < _last_health and _participant:
		_participant.apply_setback(setback_on_hit)
	_last_health = current
```

---

## Task 11: `RaceHUD`

**Files:**
- Create: `assault/scenes/race/race_hud.gd`
- Create: `assault/scenes/race/race_hud.tscn`

- [ ] **Step 1: Write the HUD script**

```gdscript
## RaceHUD — shows live standings (leader first), the player's place highlighted, and a
## progress-to-finish bar. Subscribes to RaceDirector.standings_changed.
class_name RaceHUD
extends CanvasLayer

@export var director: RaceDirector

@onready var _standings_label: Label = $Panel/StandingsLabel
@onready var _progress_bar: ProgressBar = $Panel/ProgressBar

func _ready() -> void:
	if director:
		director.standings_changed.connect(_on_standings_changed)
		director.race_finished.connect(_on_race_finished)
		director.race_failed.connect(_on_race_failed)
		_progress_bar.max_value = director.track_length

func _on_standings_changed(standings: Array) -> void:
	var lines: Array[String] = []
	var place: int = 1
	for p in standings:
		var part := p as RaceParticipant
		var tag: String = "YOU" if part.is_player else "CPU"
		var marker: String = ">" if part.is_player else " "
		lines.append("%s %d. %s" % [marker, place, tag])
		if part.is_player:
			_progress_bar.value = part.progress
		place += 1
	_standings_label.text = "\n".join(lines)

func _on_race_finished(results: Array) -> void:
	var player_place: int = 1
	for i in results.size():
		if (results[i] as RaceParticipant).is_player:
			player_place = i + 1
	_standings_label.text = "FINISHED!\nYour place: %d" % player_place

func _on_race_failed() -> void:
	_standings_label.text = "DESTROYED — race failed.\nRestarting..."
```

- [ ] **Step 2: Author the HUD scene**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://assault/scenes/race/race_hud.gd" id="1_hud"]

[node name="RaceHUD" type="CanvasLayer"]
script = ExtResource("1_hud")

[node name="Panel" type="Panel" parent="."]
offset_left = 16.0
offset_top = 16.0
offset_right = 220.0
offset_bottom = 200.0

[node name="StandingsLabel" type="Label" parent="Panel"]
offset_left = 12.0
offset_top = 8.0
offset_right = 192.0
offset_bottom = 150.0
text = "RACE"

[node name="ProgressBar" type="ProgressBar" parent="Panel"]
offset_left = 12.0
offset_top = 156.0
offset_right = 192.0
offset_bottom = 176.0
max_value = 10000.0
```

(`director` is wired in `race_level_1.tscn` via the inspector / node_paths — see Task 14.)

---

## Task 12: WaveBuilder constructors for racers + dash panels

**Files:**
- Modify: `assault/scenes/systems/wave_builder.gd`

- [ ] **Step 1: Add scene-path constants**

In the "Scene path constants" block (near the bottom, after `BONUS_DRONE`), add:

```gdscript
const RACER       := "res://assault/scenes/race/racer_base.tscn"
const DASH_PANEL   := "res://assault/scenes/race/dash_panel.tscn"
const LASER_RAY    := "res://assault/scenes/hazards/laser_ray/laser_ray.tscn"
```

- [ ] **Step 2: Add ship/object constructors**

In the "Ship constructors" block (after `bonus_drone()`), add:

```gdscript
func racer()      -> SpawnConfig: return SpawnConfig.new(RACER)
func dash_panel() -> SpawnConfig: return SpawnConfig.new(DASH_PANEL)
func laser()      -> SpawnConfig: return SpawnConfig.new(LASER_RAY)
```

These reuse the existing `SpawnConfig` fluent API (`.at(x, y)`, `.delay(...)`). Racers,
dash panels, and lasers are spawned WITHOUT `.move()`, so WaveManager attaches no
`EnemyPathMover` — they self-drive (racers) or stay put (dash panels, lasers).

---

## Task 13: `RaceLevel1Config`

**Files:**
- Create: `assault/scenes/levels/race/race_level_1_config.gd`

- [ ] **Step 1: Write the level orchestrator**

```gdscript
## RaceLevel1Config — boots the race: attaches race components to the player, wires the
## RaceDirector + HUD, builds the spawn schedule (racers, dash panels, asteroids, lasers)
## via WaveBuilder, and hands it to WaveManager. Restarts the scene on race failure.
extends Node

@export var director: RaceDirector
@export var wave_manager: WaveManager
@export var background: BackgroundController

func _ready() -> void:
	# ── Attach race components to the shared player at runtime ────────────────
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player:
		var participant := RaceParticipant.new()
		participant.name = "RaceParticipant"
		participant.is_player = true
		player.add_child(participant)

		var adapter := PlayerThrottleAdapter.new()
		adapter.name = "PlayerThrottleAdapter"
		player.add_child(adapter)

		var health := player.get_node_or_null("HealthComponent") as Health
		adapter.setup(player, participant, health)
		if director and health:
			director.bind_player_health(health)

	# ── Restart on failure ────────────────────────────────────────────────────
	if director:
		director.race_failed.connect(_on_race_failed)

	# ── Build the race schedule and start it ──────────────────────────────────
	if wave_manager:
		wave_manager.load_section(_build_waves())

func _on_race_failed() -> void:
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func _build_waves() -> Array[WaveResource]:
	var b := WaveBuilder.new()

	var waves: Array = [
		# t=0 — three generic rivals spread across the start line (no movement; self-drive).
		b.wave(0.0, [
			b.racer().at(-360, 200),
			b.racer().at(   0, 200),
			b.racer().at( 360, 200),
		]),

		# Dash panels down the track (camera-relative offsets; the camera is pinned).
		b.wave(4.0,  [ b.dash_panel().at(-200, -100) ]),
		b.wave(10.0, [ b.dash_panel().at( 240, -100) ]),
		b.wave(16.0, [ b.dash_panel().at(   0, -100) ]),
		b.wave(26.0, [ b.dash_panel().at(-260, -100) ]),
		b.wave(34.0, [ b.dash_panel().at( 180, -100) ]),

		# Asteroid hazards (reuse existing scenes; they drift down past everyone).
		b.wave(8.0, [
			b.big_asteroid().at(-150, -400).move(b.straight(220)),
			b.small_asteroid().at(120, -400).move(b.straight(320)).delay(0.4),
		]),
		b.wave(20.0, [
			b.big_asteroid().at(200, -400).move(b.straight(230)),
			b.big_asteroid().at(-60, -400).move(b.straight(210)).delay(0.5),
		]),
		b.wave(30.0, [
			b.small_asteroid().at(-200, -400).move(b.straight(330)),
			b.big_asteroid().at(60, -400).move(b.straight(225)).delay(0.3),
		]),

		# Laser hazards (reuse laser_ray; vertical beams that telegraph then fire).
		b.wave(14.0, [ b.laser().at(-300, -380) ]),
		b.wave(24.0, [ b.laser().at( 300, -380) ]),
	]

	var typed: Array[WaveResource] = []
	for w in waves:
		typed.append(w as WaveResource)
	return typed
```

> **Note on laser placement:** `laser_ray.tscn` builds a vertical beam extending downward
> from its origin with `segment_count` tiles (default 12 → 1536 px), so a y-offset of
> `-380` (top of the play area) lets it span the screen. `b.laser().at(x, -380)` resolves
> to world `(640,360) + (x,-380)*2`; adjust offsets in-engine to taste during playtest.

---

## Task 14: `race_level_1.tscn`

**Files:**
- Create: `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Author the level scene (mirrors `level_1.tscn`, race wiring instead of enemy director)**

```
[gd_scene load_steps=8 format=3]

[ext_resource type="PackedScene" uid="uid://ty6a2vpnmrr5" path="res://assault/scenes/player/player_fighter.tscn" id="1_player"]
[ext_resource type="PackedScene" uid="uid://bsrr6ov5ery1u" path="res://assault/scenes/levels/edelia/1/level_1_background.tscn" id="2_bg"]
[ext_resource type="Script" uid="uid://dutkvjs1np4nd" path="res://assault/scenes/systems/wave_manager/wave_manager.gd" id="3_wave"]
[ext_resource type="Script" uid="uid://darena5cam001" path="res://assault/scenes/systems/arena_camera.gd" id="4_cam"]
[ext_resource type="Script" path="res://assault/scenes/race/race_director.gd" id="5_dir"]
[ext_resource type="Script" path="res://assault/scenes/race/race_hud.gd" id="6_hud"]
[ext_resource type="Script" path="res://assault/scenes/levels/race/race_level_1_config.gd" id="7_cfg"]

[node name="RaceLevel1" type="Node2D"]

[node name="Level1Background" parent="." groups=["background"] instance=ExtResource("2_bg")]
planet_y_anchor = -200.0
planet_scale_atmosphere = 14.0

[node name="Camera2D" type="Camera2D" parent="."]
position = Vector2(640, 360)
script = ExtResource("4_cam")

[node name="EnemyContainer" type="Node2D" parent="."]

[node name="WaveManager" type="Node" parent="." node_paths=PackedStringArray("enemy_container")]
script = ExtResource("3_wave")
enemy_container = NodePath("../EnemyContainer")

[node name="RaceDirector" type="Node" parent="." groups=["race_director"]]
script = ExtResource("5_dir")

[node name="RaceHUD" type="CanvasLayer" parent="." node_paths=PackedStringArray("director")]
script = ExtResource("6_hud")
director = NodePath("../RaceDirector")

[node name="RaceLevel1Config" type="Node" parent="." node_paths=PackedStringArray("director", "wave_manager", "background")]
script = ExtResource("7_cfg")
director = NodePath("../RaceDirector")
wave_manager = NodePath("../WaveManager")
background = NodePath("../Level1Background")

[node name="PlayerFighter" parent="." instance=ExtResource("1_player")]
position = Vector2(640, 540)
```

> **`RaceHUD` children:** the HUD script expects `$Panel/StandingsLabel` and
> `$Panel/ProgressBar`. Because this `race_level_1.tscn` instances the HUD as a bare
> `CanvasLayer` with the script (not the `race_hud.tscn` PackedScene), instead instance the
> **`race_hud.tscn`** here: replace the `RaceHUD` node block above with an instance:
> ```
> [ext_resource type="PackedScene" path="res://assault/scenes/race/race_hud.tscn" id="6_hud"]
> ...
> [node name="RaceHUD" parent="." node_paths=PackedStringArray("director") instance=ExtResource("6_hud")]
> director = NodePath("../RaceDirector")
> ```
> Use the PackedScene instance form so the Panel/Label/ProgressBar children exist.

- [ ] **Step 2: Run the scene**

Open `race_level_1.tscn` in Godot and press **F6** (Run Current Scene). Expected: the Level 1
background scrolls; three rival ships sit above the player and drift up/down as standings
change; flying to the top of the screen accelerates the player (rivals drift down); dash
panels give a visible boost + faster background; asteroids and lasers appear and the rivals
steer around them; shooting a rival enough times destroys it; dying restarts the scene.

---

## Self-Review Notes (coverage vs spec)

- Race model / relative-progress → Tasks 2, 3 (`get_screen_y`).
- Position-as-throttle (player) → Task 10; rivals faster baseline → Task 6 (`0.62`).
- Damage = setback; 0 HP = eliminated; player death = restart → Tasks 7, 9-restart in 13, 3.
- Dash panels + background coupling → Tasks 1, 9, 10.
- Obstacle reuse (asteroids, lasers) + avoidance → Tasks 5, 13.
- WaveManager spawns everything → Tasks 12, 13 (no WaveManager edits needed).
- Bubble shield reuse → deferred-visual; data layer via `RacerShield` (Task 4).
- HUD standings/progress → Task 11.
- Phase-2 items (5 named racers, mines, rival-vs-rival, bubble visual on racers) are
  intentionally out of scope here.
