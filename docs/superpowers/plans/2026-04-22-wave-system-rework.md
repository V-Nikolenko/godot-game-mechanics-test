# Wave System Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded 4-enum path system and Dictionary-based wave definitions with a polymorphic `MovementResource` hierarchy, composable `FormationResource` types, data-driven `AttackPatternResource`, and `WaveResource`/`LevelResource` assets — preserving all existing gameplay behaviour.

**Architecture:** Five independent phases: (1) movement as polymorphic Resources replacing the `PathType` enum in `EnemyPathMover`; (2) composition types (Sequence, Curve, Hold); (3) formation abstraction eliminating copy-pasted offsets; (4) attack-pattern Resources replacing per-ship `_fire()` timers; (5) wave + level Resources replacing `level_1_waves.gd`. Each phase leaves the game fully playable.

**Tech Stack:** Godot 4.3+, GDScript with static typing, `.tres` Resource files, `@tool` EditorScript for wave migration.

---

## Codebase Reference

Key files touched by this plan:

| File | Role |
|---|---|
| `assault/scenes/enemies/enemy_path_mover.gd` | Movement controller — gutted in Phase 1 |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Spawner — extended each phase |
| `assault/scenes/levels/level_1_waves.gd` | Wave definitions — migrated in Phase 5 |
| `assault/scenes/enemies/light_assault_ship/light_assault_ship.gd` | Shooting ship — refactored Phase 4 |
| `assault/scenes/enemies/light_assault_ship/states/approach_state.gd` | BUG: instantiates bullets directly without pool; fixed Phase 4 |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd` | Shooting ally — refactored Phase 4 |
| `assault/scenes/enemies/gunship/gunship.gd` | Untouched (alternating logic too specific for generic pattern) |
| `assault/scenes/enemies/sniper_skimmer/sniper_skimmer.gd` | Untouched (once-at-midpoint logic stays) |
| `assault/scenes/enemies/bomber/bomber.gd` | Untouched (bomb drop is not bullet pool) |

New directories created by this plan:
- `global/resources/movement/` — Phase 1+2
- `global/resources/formation/` — Phase 3
- `global/resources/attack/` — Phase 4
- `global/resources/waves/` — Phase 5
- `assault/data/attack/` — Phase 4 `.tres` assets
- `assault/data/waves/level_1/` — Phase 5 `.tres` assets (auto-created by migration script)
- `assault/data/levels/` — Phase 5 level asset

---

## PHASE 1 — Movement as Resources

**Goal:** Replace the 4-value `PathType` enum and `_get_screen_offset()` match block in `EnemyPathMover` with a polymorphic `MovementResource` class hierarchy. Zero gameplay change — all ships travel identical paths after this phase.

---

### Task 1: Create MovementResource Base Class and Four Concrete Types

**Files:**
- Create: `global/resources/movement/movement_resource.gd`
- Create: `global/resources/movement/straight_movement.gd`
- Create: `global/resources/movement/arc_movement.gd`
- Create: `global/resources/movement/sine_movement.gd`
- Create: `global/resources/movement/hold_movement.gd`

- [ ] **Step 1: Create the base class**

Write `global/resources/movement/movement_resource.gd`:

```gdscript
## MovementResource — abstract base for all enemy movement patterns.
##
## Subclasses implement sample(t) to return the screen-space offset from the
## ship's spawn position at time t seconds. +X = right, +Y = down.
## EnemyPathMover calls sample() each physics frame and sets actor.global_position.
class_name MovementResource
extends Resource

## Returns screen-space offset from spawn position at time t seconds.
## +X = right, +Y = down (matches Godot 2D coordinate system).
func sample(_t: float) -> Vector2:
	return Vector2.ZERO

## Lifetime in seconds. INF = no natural expiry (freed on screen exit).
func total_duration() -> float:
	return INF
```

- [ ] **Step 2: Create StraightMovement**

Write `global/resources/movement/straight_movement.gd`:

```gdscript
## StraightMovement — constant-velocity linear travel at a fixed screen angle.
##
## angle is in radians from straight-down:
##   0.0     = straight down        PI/2  = right
##   PI/-PI  = straight up         -PI/2  = left
##   PI/4    = down-right diagonal  -PI/4 = down-left diagonal
class_name StraightMovement
extends MovementResource

@export var speed: float = 100.0
## Radians from straight-down. 0 = down, PI/2 = right, -PI/2 = left, PI = up.
@export var angle: float = 0.0

func sample(t: float) -> Vector2:
	return Vector2(sin(angle), cos(angle)) * speed * t

func total_duration() -> float:
	return INF
```

- [ ] **Step 3: Create ArcMovement**

Write `global/resources/movement/arc_movement.gd`:

```gdscript
## ArcMovement — semicircular arc. Replaces PathType.U_L and PathType.U_R.
##
## LEFT bows to the left; RIGHT bows to the right.
## total_duration() returns `duration` so EnemyPathMover can auto-free
## the actor when the arc completes (ExitMode.FREE_ON_DURATION).
class_name ArcMovement
extends MovementResource

enum ArcDirection { LEFT, RIGHT }

@export var direction: ArcDirection = ArcDirection.LEFT
@export var amplitude: float = 150.0   ## Radius of the arc in pixels.
@export var duration: float = 4.0      ## Total seconds to complete the arc.

func sample(t: float) -> Vector2:
	var p: float = clampf(t / duration, 0.0, 1.0)
	if direction == ArcDirection.LEFT:
		return Vector2(amplitude * (cos(p * PI) - 1.0), amplitude * sin(p * PI))
	else:
		return Vector2(amplitude * (1.0 - cos(p * PI)), amplitude * sin(p * PI))

func total_duration() -> float:
	return duration
```

- [ ] **Step 4: Create SineMovement**

Write `global/resources/movement/sine_movement.gd`:

```gdscript
## SineMovement — descends while weaving left-right. Replaces PathType.SINE.
## No natural expiry — freed when ship leaves the viewport.
class_name SineMovement
extends MovementResource

@export var base_speed: float = 140.0   ## Downward travel speed in px/s.
@export var amplitude: float = 45.0     ## Lateral swing width in pixels.
@export var frequency: float = 2.5      ## Oscillations per second.

func sample(t: float) -> Vector2:
	return Vector2(amplitude * sin(t * frequency), base_speed * t)

func total_duration() -> float:
	return INF
```

- [ ] **Step 5: Create HoldMovement**

Write `global/resources/movement/hold_movement.gd`:

```gdscript
## HoldMovement — ship stays at spawn position for `duration` seconds.
## Use as a step inside SequenceMovement (Phase 2): approach → hold → exit.
class_name HoldMovement
extends MovementResource

@export var duration: float = 2.0

func sample(_t: float) -> Vector2:
	return Vector2.ZERO

func total_duration() -> float:
	return duration
```

- [ ] **Step 6: Commit**

```bash
git add global/resources/movement/
git commit -m "feat: add MovementResource base class and Straight/Arc/Sine/Hold types"
```

---

### Task 2: Refactor EnemyPathMover to Use MovementResource

**Files:**
- Modify: `assault/scenes/enemies/enemy_path_mover.gd`

The current file has a `PathType` enum and a `match` block with 4 branches. Replace all of that with a single `@export var movement: MovementResource`. `ExitMode` stays (used in wave spawn dicts). `speed`, `amplitude`, `path_angle`, and `duration` exports are removed (those now live on the resource).

- [ ] **Step 1: Replace enemy_path_mover.gd entirely**

Write `assault/scenes/enemies/enemy_path_mover.gd`:

```gdscript
## EnemyPathMover — attaches to any ship and drives it along a MovementResource path.
## Responsibility: MOVEMENT ONLY. Shooting, health, and all other behaviour
## belong to the ship itself.
##
## Add as a child of any CharacterBody2D. Assign a MovementResource to `movement`.
## This node takes over physics_process and updates actor.global_position each frame
## using movement.sample(elapsed_time) + camera scroll offset.
class_name EnemyPathMover
extends Node

enum ExitMode {
	FREE_ON_SCREEN_EXIT, ## queue_free when ship leaves viewport (default)
	FREE_ON_DURATION,    ## queue_free when movement.total_duration() elapses
}

@export var movement: MovementResource
@export var exit_mode: ExitMode = ExitMode.FREE_ON_SCREEN_EXIT
@export var look_in_moving_direction: bool = true  ## Rotate actor to face direction of travel.

var _elapsed: float = 0.0
var _actor: CharacterBody2D
var _initial_world_pos: Vector2
var _initial_cam_y: float

func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	if not _actor:
		push_error("[EnemyPathMover] Parent must be a CharacterBody2D. Freeing self.")
		queue_free()
		return

	_initial_world_pos = _actor.global_position

	var cam := _actor.get_viewport().get_camera_2d()
	_initial_cam_y = cam.global_position.y if cam else 0.0

	# Suspend the ship's own movement AI — we own position each frame.
	# Timer-based shooting in the ship continues unaffected.
	_actor.set_physics_process(false)
	var state_machine: Node = _actor.get_node_or_null("AIStateMachine")
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(delta: float) -> void:
	if not is_instance_valid(movement):
		return

	_elapsed += delta

	var cam := _actor.get_viewport().get_camera_2d()
	var cam_scroll_y: float = (cam.global_position.y - _initial_cam_y) if cam else 0.0

	_actor.global_position = _initial_world_pos + movement.sample(_elapsed) + Vector2(0.0, cam_scroll_y)

	if look_in_moving_direction:
		var vel: Vector2 = movement.sample(_elapsed) - movement.sample(_elapsed - delta)
		if vel.length_squared() > 0.0001:
			_actor.rotation = atan2(-vel.x, vel.y)

	if exit_mode == ExitMode.FREE_ON_DURATION and _elapsed >= movement.total_duration():
		_actor.queue_free()
		return

	_check_off_screen(cam)

func _check_off_screen(cam: Camera2D) -> void:
	if not cam:
		return
	var vp: Vector2 = _actor.get_viewport().get_visible_rect().size
	var margin: float = 80.0
	if _actor.global_position.y > cam.global_position.y + vp.y * 0.5 + margin \
			or _actor.global_position.y < cam.global_position.y - vp.y * 0.5 - margin \
			or _actor.global_position.x > cam.global_position.x + vp.x * 0.5 + margin \
			or _actor.global_position.x < cam.global_position.x - vp.x * 0.5 - margin:
		_actor.queue_free()
```

- [ ] **Step 2: Commit**

```bash
git add assault/scenes/enemies/enemy_path_mover.gd
git commit -m "refactor: EnemyPathMover driven by MovementResource instead of PathType enum"
```

---

### Task 3: Update WaveManager and level_1_waves.gd

`WaveManager` currently reads a `"path"` Dictionary key and manually sets `EnemyPathMover` fields. Replace that block with a `"movement"` key that takes a `MovementResource` directly. Update `level_1_waves.gd` to supply resource instances via helper functions.

**Files:**
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`
- Modify: `assault/scenes/levels/level_1_waves.gd`

- [ ] **Step 1: Update WaveManager._spawn_ship()**

Replace the `if spawn.has("path"):` block in `wave_manager.gd` with the following. This is the complete updated `_spawn_ship()` method (replaces lines 68–107):

```gdscript
func _spawn_ship(spawn: Dictionary) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var ship_dict: Dictionary = spawn.get("ship", {})
	var scene: PackedScene = ship_dict.get("scene") as PackedScene
	if not scene:
		return

	var spawn_pos: Vector2 = cam.global_position + (spawn.get("offset", Vector2.ZERO) as Vector2)

	var entity: Node = scene.instantiate()
	entity.global_position = spawn_pos
	enemy_container.add_child(entity)
	print("[Spawn] %s at (%.0f, %.0f)" % [scene.resource_path.get_file(), spawn_pos.x, spawn_pos.y])

	if spawn.has("on_spawned"):
		spawn.on_spawned.call(entity)

	# Attach movement controller if a MovementResource is provided.
	if spawn.has("movement"):
		var mover := EnemyPathMover.new()
		mover.movement = spawn["movement"] as MovementResource
		if spawn.has("exit_mode"):
			mover.exit_mode = spawn["exit_mode"] as EnemyPathMover.ExitMode
		if spawn.has("look_in_moving_direction"):
			mover.look_in_moving_direction = spawn["look_in_moving_direction"] as bool
		entity.add_child(mover)
```

- [ ] **Step 2: Replace level_1_waves.gd with the resource-based version**

Write `assault/scenes/levels/level_1_waves.gd`:

```gdscript
extends Node

# GDD Phase 1 — Wave-based aerial combat
# Movement is now expressed as MovementResource instances (Phase 1 refactor).
# Helper functions _s(), _arc(), _sine() construct resources inline.
# (Phase 5 will replace this file with a thin LevelResource loader.)

@export var wave_manager: WaveManager

# ── Ship scene references ─────────────────────────────────────────────────────
const FIGHTER:  Dictionary = {"scene": preload("res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn")}
const DRONE:    Dictionary = {"scene": preload("res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn")}
const RAM_SHIP: Dictionary = {"scene": preload("res://assault/scenes/enemies/ram_ship/ram_ship.tscn")}
const SNIPER:   Dictionary = {"scene": preload("res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn")}
const GUNSHIP:  Dictionary = {"scene": preload("res://assault/scenes/enemies/gunship/gunship.tscn")}
const BOMBER:   Dictionary = {"scene": preload("res://assault/scenes/enemies/bomber/bomber.tscn")}
const ALLY:     Dictionary = {"scene": preload("res://assault/scenes/allies/ally_fighter/ally_fighter.tscn")}

# ── Exit mode shorthand ───────────────────────────────────────────────────────
const DURATION := EnemyPathMover.ExitMode.FREE_ON_DURATION

# ── Movement helpers (create resource instances inline) ───────────────────────

static func _s(speed: float, angle: float = 0.0) -> StraightMovement:
	var m := StraightMovement.new()
	m.speed = speed
	m.angle = angle
	return m

static func _arc(dir: ArcMovement.ArcDirection, amplitude: float, duration: float) -> ArcMovement:
	var m := ArcMovement.new()
	m.direction = dir
	m.amplitude = amplitude
	m.duration = duration
	return m

static func _sine(base_speed: float, amplitude: float, frequency: float = 2.5) -> SineMovement:
	var m := SineMovement.new()
	m.base_speed = base_speed
	m.amplitude = amplitude
	m.frequency = frequency
	return m

func _ready() -> void:
	print("[LEVEL] Level 1 started — time-based waves enabled")
	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate())

	_register_waves()


func _register_waves() -> void:
	var L := ArcMovement.ArcDirection.LEFT
	var R := ArcMovement.ArcDirection.RIGHT

	# ── Wave 1 ── V of 5 fighters, straight down ──────────────────────────────
	wave_manager.register_wave(2.0, [
		{"ship": FIGHTER, "offset": Vector2(  0, -180), "delay": 0.0,  "movement": _s(100)},
		{"ship": FIGHTER, "offset": Vector2(-40, -192), "delay": 0.10, "movement": _s(100)},
		{"ship": FIGHTER, "offset": Vector2( 40, -192), "delay": 0.10, "movement": _s(100)},
		{"ship": FIGHTER, "offset": Vector2(-80, -204), "delay": 0.20, "movement": _s(100)},
		{"ship": FIGHTER, "offset": Vector2( 80, -204), "delay": 0.20, "movement": _s(100)},
	])

	# ── Ally Wave A ── 2 wingmen rise at mission start ────────────────────────
	wave_manager.register_wave(3.0, [
		{"ship": ALLY, "offset": Vector2( 45, 180), "delay": 0.0, "movement": _s(130, PI)},
		{"ship": ALLY, "offset": Vector2(-35, 180), "delay": 0.3, "movement": _s(170, PI)},
	])

	# ── Wave 2 ── Diagonal line, top-right to down-left ──────────────────────
	wave_manager.register_wave(6.0, [
		{"ship": FIGHTER, "offset": Vector2(100, -56),  "delay": 0.0, "movement": _s(160, -PI/3.6)},
		{"ship": FIGHTER, "offset": Vector2(140, -42),  "delay": 0.1, "movement": _s(160, -PI/3.6)},
		{"ship": FIGHTER, "offset": Vector2(180, -28),  "delay": 0.2, "movement": _s(160, -PI/3.6)},
		{"ship": FIGHTER, "offset": Vector2(220, -14),  "delay": 0.3, "movement": _s(160, -PI/3.6)},
		{"ship": FIGHTER, "offset": Vector2(260,   0),  "delay": 0.4, "movement": _s(160, -PI/3.6)},
	])

	# ── Ally Wave ── 1 ally ───────────────────────────────────────────────────
	wave_manager.register_wave(7.0, [
		{"ship": ALLY, "offset": Vector2(-180, 180), "delay": 0.0, "movement": _s(130, PI)},
	])

	# ── Wave 2b ── Kamikaze surprise cluster, sine weave ─────────────────────
	wave_manager.register_wave(22.0, [
		{"ship": DRONE, "offset": Vector2(-50, -180), "delay": 0.0, "movement": _sine(140, 45)},
		{"ship": DRONE, "offset": Vector2(  0, -180), "delay": 0.0, "movement": _sine(140, 45)},
		{"ship": DRONE, "offset": Vector2( 50, -180), "delay": 0.0, "movement": _sine(140, 45)},
		{"ship": DRONE, "offset": Vector2( 25, -165), "delay": 0.2, "movement": _sine(140, 45)},
	])

	# ── Wave 3 ── Suppression: gunship holds, 4 fighters U-arc ───────────────
	wave_manager.register_wave(38.0, [
		{"ship": GUNSHIP, "offset": Vector2(  0, -180), "delay": 0.0, "movement": _s(50)},
		{"ship": FIGHTER, "offset": Vector2(-60, 20), "delay": 0.4, "movement": _arc(L, 130, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(-20, 20), "delay": 0.4, "movement": _arc(R, 130, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2( 20, 20), "delay": 0.4, "movement": _arc(L, 130, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2( 60, 20), "delay": 0.4, "movement": _arc(R, 130, 3.5), "exit_mode": DURATION},
	])

	# ── Wave 4 ── Diagonal line, down-left ───────────────────────────────────
	wave_manager.register_wave(55.0, [
		{"ship": FIGHTER, "offset": Vector2(-80,  0), "delay": 0.00, "movement": _s(110, -PI/4)},
		{"ship": FIGHTER, "offset": Vector2(-40, 14), "delay": 0.15, "movement": _s(110, -PI/4)},
		{"ship": FIGHTER, "offset": Vector2(  0, 28), "delay": 0.30, "movement": _s(110, -PI/4)},
		{"ship": FIGHTER, "offset": Vector2( 40, 42), "delay": 0.45, "movement": _s(110, -PI/4)},
		{"ship": FIGHTER, "offset": Vector2( 80, 56), "delay": 0.60, "movement": _s(110, -PI/4)},
	])

	# ── Wave 4b ── Ram ship introduction ─────────────────────────────────────
	wave_manager.register_wave(68.0, [
		{"ship": RAM_SHIP, "offset": Vector2(  0,  0), "delay": 0.0, "movement": _s(100)},
		{"ship": FIGHTER,  "offset": Vector2(-50, 10), "delay": 0.3, "movement": _s(110,  PI/4)},
		{"ship": FIGHTER,  "offset": Vector2( 50, 10), "delay": 0.3, "movement": _s(110, -PI/4)},
	])

	# ── Ally Wave B ── 3 wingmen before sniper pass ───────────────────────────
	wave_manager.register_wave(76.0, [
		{"ship": ALLY, "offset": Vector2(-50, 180), "delay": 0.0, "movement": _s(120, PI - 0.25)},
		{"ship": ALLY, "offset": Vector2(  0, 180), "delay": 0.2, "movement": _s(140, PI)},
		{"ship": ALLY, "offset": Vector2( 50, 180), "delay": 0.4, "movement": _s(120, PI + 0.25)},
	])

	# ── Wave 5 ── Sniper pass: 2 skimmers + 3 fighters ───────────────────────
	wave_manager.register_wave(85.0, [
		{
			"ship": SNIPER, "offset": Vector2(-320, -20), "delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as SniperSkimmer).direction = 1.0,
			"movement": _s(130, PI/2),
		},
		{
			"ship": SNIPER, "offset": Vector2(320, 20), "delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as SniperSkimmer).direction = -1.0,
			"movement": _s(130, -PI/2),
		},
		{"ship": FIGHTER, "offset": Vector2(-40, -180), "delay": 0.6, "movement": _s(100,  PI/4)},
		{"ship": FIGHTER, "offset": Vector2(  0,   0),  "delay": 0.6, "movement": _s(100)},
		{"ship": FIGHTER, "offset": Vector2( 40, -180), "delay": 0.6, "movement": _s(100, -PI/4)},
	])

	# ── Wave 6 ── Bomber crossing + covering fighters U-arcs ─────────────────
	wave_manager.register_wave(103.0, [
		{
			"ship": BOMBER, "offset": Vector2(-320, -10), "delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = 1.0,
			"movement": _s(80, PI/2),
		},
		{"ship": FIGHTER, "offset": Vector2(-50,    0), "delay": 0.5, "movement": _arc(L, 120, 3.8), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(  0, -180), "delay": 0.5, "movement": _s(95)},
		{"ship": FIGHTER, "offset": Vector2( 50,    0), "delay": 0.5, "movement": _arc(R, 120, 3.8), "exit_mode": DURATION},
	])

	# ── Wave 7 ── Pincer: U arcs from flanks + SINE drones ───────────────────
	wave_manager.register_wave(120.0, [
		{"ship": FIGHTER, "offset": Vector2(-120,  0), "delay": 0.0, "movement": _arc(L, 140, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2( -80, 12), "delay": 0.0, "movement": _arc(L, 110, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2( -40, 24), "delay": 0.0, "movement": _arc(L,  80, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2( 120,  0), "delay": 0.0, "movement": _arc(R, 140, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(  80, 12), "delay": 0.0, "movement": _arc(R, 110, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(  40, 24), "delay": 0.0, "movement": _arc(R,  80, 3.5), "exit_mode": DURATION},
		{"ship": DRONE, "offset": Vector2(-30, -180), "delay": 0.8, "movement": _sine(150, 50)},
		{"ship": DRONE, "offset": Vector2(  0, -180), "delay": 0.8, "movement": _sine(150, 50)},
		{"ship": DRONE, "offset": Vector2( 30, -180), "delay": 0.8, "movement": _sine(150, 50)},
	])

	# ── Ally Wave C ── 4 wingmen for heavy suppression ───────────────────────
	wave_manager.register_wave(136.0, [
		{"ship": ALLY, "offset": Vector2(-60, 180), "delay": 0.00, "movement": _s(150, PI - 0.2)},
		{"ship": ALLY, "offset": Vector2(-20, 180), "delay": 0.15, "movement": _s(110, PI - 0.05)},
		{"ship": ALLY, "offset": Vector2( 20, 180), "delay": 0.30, "movement": _s(110, PI + 0.05)},
		{"ship": ALLY, "offset": Vector2( 60, 180), "delay": 0.45, "movement": _s(150, PI + 0.2)},
	])

	# ── Wave 8 ── 2 gunships + 2 ram ships + converging fighters ─────────────
	wave_manager.register_wave(148.0, [
		{"ship": GUNSHIP,  "offset": Vector2(-55, -180), "delay": 0.0, "movement": _s(50)},
		{"ship": GUNSHIP,  "offset": Vector2( 55, -180), "delay": 0.0, "movement": _s(50)},
		{"ship": RAM_SHIP, "offset": Vector2(-30,   10), "delay": 0.6, "movement": _s(110)},
		{"ship": RAM_SHIP, "offset": Vector2( 30,   10), "delay": 0.6, "movement": _s(110)},
		{"ship": FIGHTER,  "offset": Vector2(-80,   20), "delay": 1.0, "movement": _s(110,  PI/4)},
		{"ship": FIGHTER,  "offset": Vector2(  0,   20), "delay": 1.0, "movement": _s(100)},
		{"ship": FIGHTER,  "offset": Vector2( 80,   20), "delay": 1.0, "movement": _s(110, -PI/4)},
	])

	# ── Wave 9 ── Asymmetric pincer: bombers crossing + U fighters + SINE drones
	wave_manager.register_wave(166.0, [
		{
			"ship": BOMBER, "offset": Vector2(-320, -15), "delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = 1.0,
			"movement": _s(80, PI/2),
		},
		{
			"ship": BOMBER, "offset": Vector2(320, 15), "delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = -1.0,
			"movement": _s(80, -PI/2),
		},
		{"ship": FIGHTER, "offset": Vector2(-40, -180), "delay": 0.3, "movement": _arc(L, 110, 3.5), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(  0,    0), "delay": 0.3, "movement": _s(95)},
		{"ship": FIGHTER, "offset": Vector2( 40, -180), "delay": 0.3, "movement": _arc(R, 110, 3.5), "exit_mode": DURATION},
		{"ship": DRONE,   "offset": Vector2(-20, -180), "delay": 0.9, "movement": _sine(150, 55)},
		{"ship": DRONE,   "offset": Vector2( 20, -180), "delay": 0.9, "movement": _sine(150, 55)},
	])

	# ── Ally Wave D ── 5 wingmen arrowhead ───────────────────────────────────
	wave_manager.register_wave(180.0, [
		{"ship": ALLY, "offset": Vector2(  0, 180), "delay": 0.0, "movement": _s(160, PI)},
		{"ship": ALLY, "offset": Vector2(-40,   0), "delay": 0.2, "movement": _s(140, PI - 0.18)},
		{"ship": ALLY, "offset": Vector2( 40,   0), "delay": 0.2, "movement": _s(140, PI + 0.18)},
		{"ship": ALLY, "offset": Vector2(-80, 180), "delay": 0.4, "movement": _s(125, PI - 0.32)},
		{"ship": ALLY, "offset": Vector2( 80, 180), "delay": 0.4, "movement": _s(125, PI + 0.32)},
	])

	# ── Wave 10 ── Elite encounter ────────────────────────────────────────────
	wave_manager.register_wave(190.0, [
		{"ship": GUNSHIP, "offset": Vector2(  0,   0), "delay": 0.0, "movement": _s(35)},
		{"ship": FIGHTER, "offset": Vector2(-50,  22), "delay": 0.8, "movement": _arc(L, 120, 4.0), "exit_mode": DURATION},
		{"ship": FIGHTER, "offset": Vector2(  0,  22), "delay": 0.8, "movement": _s(80)},
		{"ship": FIGHTER, "offset": Vector2( 50,  22), "delay": 0.8, "movement": _arc(R, 120, 4.0), "exit_mode": DURATION},
	])
```

- [ ] **Step 3: Verify Phase 1 in Godot**

Open the Godot editor. Run the level scene. Confirm:
- All 13 waves spawn at their correct trigger times (watch the Output panel for `[Wave N] TRIGGERED`)
- Ships travel visually identical paths to before this refactor
- Arcing ships (waves 3, 6, 7, 10) still disappear after completing their arcs
- Sine-weaving drones (waves 2b, 7, 9) still weave correctly
- No GDScript errors or warnings in the Output panel

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/systems/wave_manager/wave_manager.gd
git add assault/scenes/levels/level_1_waves.gd
git commit -m "refactor: waves use MovementResource instances instead of PathType dicts"
```

---

## PHASE 2 — Movement Composition

**Goal:** Add `SequenceMovement` (chains multiple movements end-to-end) and `CurveMovement` (follows a `Curve2D` drawn in the Godot editor). Add one demo wave proving `SequenceMovement` works — an approach/hold/strafe pattern that was impossible with the old enum.

---

### Task 4: Create SequenceMovement and CurveMovement

**Files:**
- Create: `global/resources/movement/sequence_movement.gd`
- Create: `global/resources/movement/curve_movement.gd`

- [ ] **Step 1: Create SequenceMovement**

Write `global/resources/movement/sequence_movement.gd`:

```gdscript
## SequenceMovement — chains multiple MovementResources end-to-end.
##
## Each step runs for its total_duration(). When a step finishes, the next
## begins. Position is accumulated so transitions are seamless.
##
## Example — approach, pause, strafe left:
##   var seq := SequenceMovement.new()
##   seq.steps = [straight_down_60, hold_1_5s, straight_left_150]
##
## Put infinite-duration steps (StraightMovement, SineMovement) LAST — they
## consume all remaining time. total_duration() returns INF if the final step
## is infinite (ship freed on screen exit); otherwise returns the sum of all
## finite step durations.
class_name SequenceMovement
extends MovementResource

@export var steps: Array[MovementResource] = []

func sample(t: float) -> Vector2:
	if steps.is_empty():
		return Vector2.ZERO

	var accumulated_pos: Vector2 = Vector2.ZERO
	var time_remaining: float = t

	for i: int in steps.size():
		var step: MovementResource = steps[i]
		var step_dur: float = step.total_duration()

		if time_remaining <= step_dur or i == steps.size() - 1:
			# We are inside this step. sample at local time and add accumulated offset.
			return accumulated_pos + step.sample(time_remaining)

		# This step has completed. Record its final position and advance time.
		accumulated_pos += step.sample(step_dur)
		time_remaining -= step_dur

	return accumulated_pos

func total_duration() -> float:
	var total: float = 0.0
	for step: MovementResource in steps:
		var d: float = step.total_duration()
		if d == INF:
			return INF
		total += d
	return total
```

- [ ] **Step 2: Create CurveMovement**

Write `global/resources/movement/curve_movement.gd`:

```gdscript
## CurveMovement — follows a Curve2D drawn in the Godot editor.
##
## Usage:
##   1. In the FileSystem dock: right-click → New Resource → Curve2D.
##      Edit waypoints in the Godot curve editor.
##   2. Create a CurveMovement .tres and assign the Curve2D to `path`.
##   3. Set `duration` to control total travel time over the curve's full length.
##
## Curve coordinates are in screen space (+Y = down).
## The curve's origin (0,0) maps to the ship's spawn position.
## Set `loop = true` for patrol paths that repeat indefinitely.
class_name CurveMovement
extends MovementResource

@export var path: Curve2D
@export var duration: float = 4.0
@export var loop: bool = false

func sample(t: float) -> Vector2:
	if not is_instance_valid(path) or path.point_count < 2:
		return Vector2.ZERO
	var effective_t: float = fmod(t, duration) if loop else t
	var progress: float = clampf(effective_t / duration, 0.0, 1.0)
	return path.sample_baked(path.get_baked_length() * progress)

func total_duration() -> float:
	return INF if loop else duration
```

- [ ] **Step 3: Commit**

```bash
git add global/resources/movement/sequence_movement.gd
git add global/resources/movement/curve_movement.gd
git commit -m "feat: add SequenceMovement and CurveMovement composition types"
```

---

### Task 5: Add Demo Wave Using SequenceMovement

Prove `SequenceMovement` works by inserting one demo wave at t=12.0s: two fighters that glide down slowly, hover for 1.5 seconds, then strafe to opposite sides. This approach/hold/exit pattern was impossible with the old `PathType` enum.

**Files:**
- Modify: `assault/scenes/levels/level_1_waves.gd`

- [ ] **Step 1: Add _hold() and _seq() helpers to level_1_waves.gd**

After the `_sine()` static function, add:

```gdscript
static func _hold(duration: float) -> HoldMovement:
	var m := HoldMovement.new()
	m.duration = duration
	return m

static func _seq(steps: Array[MovementResource]) -> SequenceMovement:
	var m := SequenceMovement.new()
	m.steps = steps
	return m
```

- [ ] **Step 2: Insert demo wave between Ally Wave A (t=3.0) and Wave 2 (t=6.0)**

Inside `_register_waves()`, after the `register_wave(3.0, ...)` call and before `register_wave(6.0, ...)`, add:

```gdscript
	# ── Demo Wave (t=12s) ── SequenceMovement: approach → hold → strafe ──────
	# Two fighters glide down slowly, pause briefly, then strafe to opposite sides.
	# This approach/hold/exit pattern was impossible with the old PathType enum.
	wave_manager.register_wave(12.0, [
		{
			"ship": FIGHTER, "offset": Vector2(-40, -180), "delay": 0.0,
			"movement": _seq([_s(60), _hold(1.5), _s(150, -PI/2)]),
		},
		{
			"ship": FIGHTER, "offset": Vector2( 40, -180), "delay": 0.2,
			"movement": _seq([_s(60), _hold(1.5), _s(150,  PI/2)]),
		},
	])
```

- [ ] **Step 3: Verify in Godot**

Run the level. At t≈12s, two fighters should:
1. Glide down from the top slowly (speed=60 for ~3s, reaching roughly mid-screen)
2. Stop and hover for ~1.5s
3. Strafe out to opposite sides at speed=150

No GDScript errors in the Output panel.

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/levels/level_1_waves.gd
git commit -m "feat: add SequenceMovement demo wave (approach-hold-strafe)"
```

---

## PHASE 3 — Formations

**Goal:** Eliminate manually copy-pasted positional offsets. `WaveManager` expands a single spawn entry with a `FormationResource` into N individual spawn entries.

---

### Task 6: Create FormationResource Base and Four Subtypes

**Files:**
- Create: `global/resources/formation/formation_resource.gd`
- Create: `global/resources/formation/v_formation.gd`
- Create: `global/resources/formation/line_formation.gd`
- Create: `global/resources/formation/diagonal_formation.gd`
- Create: `global/resources/formation/cluster_formation.gd`

- [ ] **Step 1: Create FormationResource base**

Write `global/resources/formation/formation_resource.gd`:

```gdscript
## FormationResource — abstract base for all formation patterns.
##
## compute_slots() returns one FormationSlot per ship. WaveManager calls this
## and spawns one ship per slot, adding slot.offset to the spawn entry's
## base_offset and adding slot.delay to the entry's base delay.
class_name FormationResource
extends Resource

## A single ship position within a formation.
class FormationSlot:
	var offset: Vector2   ## Screen-space displacement from the formation anchor.
	var delay: float      ## Additional spawn delay for this slot (seconds).

	func _init(o: Vector2, d: float = 0.0) -> void:
		offset = o
		delay = d

## Returns one FormationSlot per ship. Override in each subtype.
func compute_slots() -> Array:  ## Array[FormationSlot]
	return []
```

- [ ] **Step 2: Create VFormation**

Write `global/resources/formation/v_formation.gd`:

```gdscript
## VFormation — classic V (chevron) with one lead ship and symmetric wing pairs.
##
## count=5, spread=40, row_gap=12 produces:
##   slot 0: (  0,   0) — lead
##   slot 1: (-40,  12) — wing rank 1
##   slot 2: ( 40,  12)
##   slot 3: (-80,  24) — wing rank 2
##   slot 4: ( 80,  24)
class_name VFormation
extends FormationResource

@export var count: int = 5
@export var spread: float = 40.0      ## Lateral pixels between adjacent ships.
@export var row_gap: float = 12.0     ## Downward offset per rank.
@export var stagger_delay: float = 0.1  ## Seconds between each wing-pair spawn.

func compute_slots() -> Array:
	var slots: Array = []
	slots.append(FormationResource.FormationSlot.new(Vector2.ZERO, 0.0))
	var rank: int = 1
	var delay: float = stagger_delay
	while slots.size() < count:
		var x: float = spread * rank
		var y: float = row_gap * rank
		slots.append(FormationResource.FormationSlot.new(Vector2(-x, y), delay))
		if slots.size() < count:
			slots.append(FormationResource.FormationSlot.new(Vector2( x, y), delay))
		rank += 1
		delay += stagger_delay
	return slots
```

- [ ] **Step 3: Create LineFormation**

Write `global/resources/formation/line_formation.gd`:

```gdscript
## LineFormation — ships in a straight horizontal or vertical line, centered.
class_name LineFormation
extends FormationResource

enum Axis { HORIZONTAL, VERTICAL }

@export var count: int = 5
@export var spacing: float = 40.0
@export var axis: Axis = Axis.HORIZONTAL
@export var stagger_delay: float = 0.1

func compute_slots() -> Array:
	var slots: Array = []
	var total_span: float = spacing * (count - 1)
	for i: int in count:
		var offset: Vector2
		if axis == Axis.HORIZONTAL:
			offset = Vector2(-total_span * 0.5 + spacing * i, 0.0)
		else:
			offset = Vector2(0.0, -total_span * 0.5 + spacing * i)
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
```

- [ ] **Step 4: Create DiagonalFormation**

Write `global/resources/formation/diagonal_formation.gd`:

```gdscript
## DiagonalFormation — ships placed diagonally, each offset by (step_x, step_y)
## from the previous. The anchor is the center ship.
##
## count=5, step_x=40, step_y=14 reproduces Wave 2 and Wave 4's diagonal lines.
class_name DiagonalFormation
extends FormationResource

@export var count: int = 5
@export var step_x: float = 40.0    ## X offset per rank relative to center.
@export var step_y: float = 14.0    ## Y offset per rank relative to center.
@export var stagger_delay: float = 0.15

func compute_slots() -> Array:
	var slots: Array = []
	var mid: int = count / 2
	for i: int in count:
		var rank: int = i - mid
		var offset: Vector2 = Vector2(step_x * rank, step_y * rank)
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
```

- [ ] **Step 5: Create ClusterFormation**

Write `global/resources/formation/cluster_formation.gd`:

```gdscript
## ClusterFormation — ships randomly scattered within a radius.
## Fixed random_seed ensures deterministic placement every run.
class_name ClusterFormation
extends FormationResource

@export var count: int = 4
@export var radius: float = 30.0
@export var random_seed: int = 42
@export var stagger_delay: float = 0.0

func compute_slots() -> Array:
	var slots: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for i: int in count:
		var angle: float = rng.randf() * TAU
		var dist: float = rng.randf() * radius
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
```

- [ ] **Step 6: Commit**

```bash
git add global/resources/formation/
git commit -m "feat: add FormationResource base and V/Line/Diagonal/Cluster subtypes"
```

---

### Task 7: Update WaveManager to Expand Formations

**Files:**
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`

- [ ] **Step 1: Update _trigger_wave() and add _expand_formation()**

Replace `_trigger_wave()` and `_spawn_with_delay()` in `wave_manager.gd`:

```gdscript
func _trigger_wave(wave: Dictionary, index: int) -> void:
	print("[Wave %d] TRIGGERED at %.1fs — %d spawns" % [index, _time_elapsed, wave.spawns.size()])
	wave_triggered.emit(index)
	for spawn in wave.spawns:
		for entry in _expand_formation(spawn):
			_spawn_with_delay(entry)

## Expands a spawn dict that has a "formation" key into one dict per slot.
## Slots add their offset to the entry's base offset and their delay to the base delay.
## If no formation is present, returns [spawn] unchanged.
func _expand_formation(spawn: Dictionary) -> Array:
	if not spawn.has("formation"):
		return [spawn]
	var formation: FormationResource = spawn["formation"] as FormationResource
	if not formation:
		return [spawn]
	var slots: Array = formation.compute_slots()
	var base_offset: Vector2 = spawn.get("offset", Vector2.ZERO) as Vector2
	var base_delay: float = spawn.get("delay", 0.0) as float
	var expanded: Array = []
	for slot: FormationResource.FormationSlot in slots:
		var entry: Dictionary = spawn.duplicate()
		entry["offset"] = base_offset + slot.offset
		entry["delay"] = base_delay + slot.delay
		entry.erase("formation")
		expanded.append(entry)
	return expanded

func _spawn_with_delay(spawn: Dictionary) -> void:
	var delay: float = spawn.get("delay", 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_ship(spawn)
```

- [ ] **Step 2: Commit**

```bash
git add assault/scenes/systems/wave_manager/wave_manager.gd
git commit -m "feat: WaveManager expands FormationResource entries into per-ship spawns"
```

---

### Task 8: Migrate Four Waves to Use Formations

**Files:**
- Modify: `assault/scenes/levels/level_1_waves.gd`

- [ ] **Step 1: Add formation helpers to level_1_waves.gd**

After `_seq()`, add:

```gdscript
static func _v(count: int, spread: float = 40.0, row_gap: float = 12.0, stagger: float = 0.1) -> VFormation:
	var f := VFormation.new()
	f.count = count
	f.spread = spread
	f.row_gap = row_gap
	f.stagger_delay = stagger
	return f

static func _diag(count: int, step_x: float, step_y: float, stagger: float = 0.15) -> DiagonalFormation:
	var f := DiagonalFormation.new()
	f.count = count
	f.step_x = step_x
	f.step_y = step_y
	f.stagger_delay = stagger
	return f
```

- [ ] **Step 2: Replace Wave 1 with VFormation (5 lines → 1 entry)**

```gdscript
	# ── Wave 1 ── V of 5 fighters, straight down ──────────────────────────────
	wave_manager.register_wave(2.0, [
		{"ship": FIGHTER, "offset": Vector2(0, -180), "formation": _v(5), "movement": _s(100)},
	])
```

- [ ] **Step 3: Replace Wave 2 with DiagonalFormation**

The anchor for the diagonal is the center ship's offset. The original center ship was `Vector2(180, -28)`:

```gdscript
	# ── Wave 2 ── Diagonal line, top-right to down-left ──────────────────────
	wave_manager.register_wave(6.0, [
		{"ship": FIGHTER, "offset": Vector2(180, -28), "formation": _diag(5, 40, 14), "movement": _s(160, -PI/3.6)},
	])
```

- [ ] **Step 4: Replace Wave 4 with DiagonalFormation**

The original center ship was `Vector2(0, 28)`:

```gdscript
	# ── Wave 4 ── Diagonal line, down-left ───────────────────────────────────
	wave_manager.register_wave(55.0, [
		{"ship": FIGHTER, "offset": Vector2(0, 28), "formation": _diag(5, 40, 14), "movement": _s(110, -PI/4)},
	])
```

- [ ] **Step 5: Simplify Wave 7's pincer using two diagonal half-formations**

The original 6 fighters in Wave 7 had amplitudes 140/110/80 per side. Using DiagonalFormation with negative step_x creates the left pincer and positive creates the right. Anchor at the outermost ship position:

```gdscript
	# ── Wave 7 ── Pincer: U arcs from flanks + SINE drones ───────────────────
	wave_manager.register_wave(120.0, [
		# Left pincer — 3 fighters arc left with increasing amplitude inward
		{"ship": FIGHTER, "offset": Vector2(-120, 0), "formation": _diag(3, 40, 12, 0.0), "movement": _arc(L, 140, 3.5), "exit_mode": DURATION},
		# Right pincer — 3 fighters arc right with increasing amplitude inward
		{"ship": FIGHTER, "offset": Vector2( 120, 0), "formation": _diag(3, -40, 12, 0.0), "movement": _arc(R, 140, 3.5), "exit_mode": DURATION},
		{"ship": DRONE, "offset": Vector2(-30, -180), "delay": 0.8, "movement": _sine(150, 50)},
		{"ship": DRONE, "offset": Vector2(  0, -180), "delay": 0.8, "movement": _sine(150, 50)},
		{"ship": DRONE, "offset": Vector2( 30, -180), "delay": 0.8, "movement": _sine(150, 50)},
	])
```

- [ ] **Step 6: Verify in Godot**

Run the level. Confirm:
- Wave 1 (t=2s): V of 5 fighters in the correct V shape
- Wave 2 (t=6s): 5 fighters in diagonal line from top-right to lower-left
- Wave 4 (t=55s): 5 fighters in diagonal line going down-left
- Wave 7 (t=120s): 3 fighters arc left, 3 arc right, 3 drones follow
- All other waves unchanged
- No GDScript errors

- [ ] **Step 7: Commit**

```bash
git add assault/scenes/levels/level_1_waves.gd
git commit -m "refactor: Waves 1, 2, 4, 7 use FormationResource instead of hand-placed offsets"
```

---

## PHASE 4 — Attack Patterns

**Goal:** Extract per-ship firing logic into reusable `AttackPatternResource` + `AttackController`. Refactor `LightAssaultShip` and `AllyFighter`. Fix the critical bug in `approach_state.gd` that instantiates bullets directly without using the bullet pool.

---

### Task 9: Create AttackPatternResource and AttackController

**Files:**
- Create: `global/resources/attack/attack_pattern_resource.gd`
- Create: `global/resources/attack/aimed_attack_pattern.gd`
- Create: `global/resources/attack/forward_attack_pattern.gd`
- Create: `global/components/attack_controller.gd`

- [ ] **Step 1: Create AttackPatternResource base**

Write `global/resources/attack/attack_pattern_resource.gd`:

```gdscript
## AttackPatternResource — pure data describing how a ship fires.
##
## Contains configuration only (no runtime timer state). Runtime state lives in
## AttackController, so multiple ships can safely share the same .tres asset.
## Subclasses override fire() to implement bullet acquisition and configuration.
class_name AttackPatternResource
extends Resource

@export var fire_interval: float = 0.8   ## Seconds between shots.
@export var start_delay: float = 0.0     ## Initial delay before first shot.

## Called by AttackController when the interval timer fires.
## ship: the Node2D that owns the AttackController
## pool: the BulletPool to call acquire() on
func fire(_ship: Node2D, _pool: BulletPool) -> void:
	pass
```

- [ ] **Step 2: Create AimedAttackPattern**

Write `global/resources/attack/aimed_attack_pattern.gd`:

```gdscript
## AimedAttackPattern — fires one bullet aimed at the nearest player.
## Falls back to straight-down (Vector2.DOWN) if no player is in the scene tree.
class_name AimedAttackPattern
extends AttackPatternResource

@export var bullet_damage: int = 10
@export var aim_at_player: bool = true
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)  ## Offset from ship position.

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	if aim_at_player:
		var players := ship.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var dir := ((players[0] as Node2D).global_position - ship.global_position).normalized()
			bullet.set_direction(dir)
		# else: default direction (Vector2.DOWN) is fine
```

- [ ] **Step 3: Create ForwardAttackPattern**

Write `global/resources/attack/forward_attack_pattern.gd`:

```gdscript
## ForwardAttackPattern — fires one bullet straight ahead (upward, rotation=0).
## Used by ally fighters whose bullets travel toward the top of the screen.
class_name ForwardAttackPattern
extends AttackPatternResource

@export var bullet_damage: int = 10
@export var spawn_offset: Vector2 = Vector2(0.0, -10.0)

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as Bullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	bullet.rotation = 0.0
```

- [ ] **Step 4: Create AttackController Node**

Write `global/components/attack_controller.gd`:

```gdscript
## AttackController — Node that drives an AttackPatternResource on a timer.
##
## Add as a child of any ship. Set `pattern` and `bullet_pool`.
## This node owns the timer state so multiple ships sharing the same pattern
## .tres don't share state (each gets its own AttackController instance).
class_name AttackController
extends Node

@export var pattern: AttackPatternResource
@export var bullet_pool: BulletPool

var _timer: float = 0.0
var _ship: Node2D

func _ready() -> void:
	_ship = get_parent() as Node2D
	if not _ship:
		push_error("[AttackController] Parent must be a Node2D. Disabling.")
		set_process(false)
		return
	# Negative initial timer honours start_delay before the first shot.
	_timer = -(pattern.start_delay if is_instance_valid(pattern) else 0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(pattern) or not is_instance_valid(bullet_pool):
		return
	_timer += delta
	if _timer >= pattern.fire_interval:
		_timer = 0.0
		pattern.fire(_ship, bullet_pool)
```

- [ ] **Step 5: Commit**

```bash
git add global/resources/attack/ global/components/attack_controller.gd
git commit -m "feat: add AttackPatternResource, AimedAttackPattern, ForwardAttackPattern, AttackController"
```

---

### Task 10: Refactor LightAssaultShip and Fix approach_state.gd

`LightAssaultShip` currently creates a `Timer` node and has a `_fire()` method. Remove both; replace with an `AttackController` child node.

`approach_state.gd` has a critical bug: it instantiates `EnemyBullet` directly (`enemy_bullet_scene.instantiate()`) instead of calling `bullet_pool.acquire()`. This completely bypasses the pool. The fix: the approach state no longer fires at all — the ship's `AttackController` fires continuously, covering the approach phase automatically.

**Files:**
- Modify: `assault/scenes/enemies/light_assault_ship/light_assault_ship.gd`
- Modify: `assault/scenes/enemies/light_assault_ship/states/approach_state.gd`

- [ ] **Step 1: Rewrite light_assault_ship.gd**

Write `assault/scenes/enemies/light_assault_ship/light_assault_ship.gd`:

```gdscript
class_name LightAssaultShip
extends BaseEnemy

@export var config: FighterConfig = load("res://assault/scenes/enemies/light_assault_ship/fighter_config.tres")

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var bullet_pool: BulletPool

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	# Bullet pool
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 10
	add_child(bullet_pool)

	# Attack pattern built from config values
	var pattern := AimedAttackPattern.new()
	pattern.fire_interval = config.fire_interval if config else 0.8
	pattern.bullet_damage = config.bullet_damage if config else 8
	pattern.aim_at_player = (config.aim_mode == "PLAYER") if config else true
	pattern.spawn_offset = Vector2(0.0, 10.0)

	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = bullet_pool
	add_child(controller)
```

- [ ] **Step 2: Fix approach_state.gd — remove the direct bullet instantiation**

Write `assault/scenes/enemies/light_assault_ship/states/approach_state.gd`:

```gdscript
## FighterApproachState — moves the ship downward until it reaches the hold line,
## then transitions to FighterStrafeExitState.
##
## Firing is handled by the ship's AttackController (added in LightAssaultShip._ready()).
## This state previously fired bullets directly without the pool — that bug is now fixed.
class_name FighterApproachState
extends State

@export var actor: LightAssaultShip
@export var speed: float = 80.0
@export var hold_y_offset: float = 80.0
@export var strafe_state: State

var _hold_y: float = 0.0

func enter() -> void:
	var viewport_size := actor.get_viewport().get_visible_rect().size
	var cam := actor.get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset

func process_physics(_delta: float) -> void:
	if actor.global_position.y < _hold_y:
		actor.velocity = Vector2(0, speed)
		actor.move_and_slide()
	else:
		state_transition.emit(strafe_state)
```

- [ ] **Step 3: Verify in Godot**

Run the level. `LightAssaultShip` enemies should:
- Still fire aimed bullets at the player at roughly the same cadence
- No direct `EnemyBullet` instantiation (no `[BulletPool]` bypassed)
- Approach state still transitions to strafe exit correctly
- No GDScript errors in the Output panel

- [ ] **Step 4: Commit**

```bash
git add assault/scenes/enemies/light_assault_ship/light_assault_ship.gd
git add assault/scenes/enemies/light_assault_ship/states/approach_state.gd
git commit -m "refactor: LightAssaultShip uses AttackController; fix approach_state bullet pool bypass"
```

---

### Task 11: Refactor AllyFighter to Use AttackController

**Files:**
- Modify: `assault/scenes/allies/ally_fighter/ally_fighter.gd`

- [ ] **Step 1: Rewrite ally_fighter.gd**

Write `assault/scenes/allies/ally_fighter/ally_fighter.gd`:

```gdscript
class_name AllyFighter
extends CharacterBody2D

@export var config: AllyFighterConfig = load("res://assault/scenes/allies/ally_fighter/ally_config.tres")

@export var speed: float = 100.0

@onready var _health: Health = $Health
@onready var _hurt_box: Area2D = $HurtBox

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

var bullet_pool: BulletPool
var _explosion_effect: ExplosionEffect

func _ready() -> void:
	add_to_group("allies")
	_health.amount_changed.connect(_on_health_changed)
	_add_contact_hitbox()

	# Bullet pool
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 8
	add_child(bullet_pool)

	# Attack pattern from config
	var pattern := ForwardAttackPattern.new()
	pattern.fire_interval = config.fire_interval if config else 0.75
	pattern.bullet_damage = config.bullet_damage if config else 10
	pattern.spawn_offset = Vector2(0.0, -10.0)

	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = bullet_pool
	add_child(controller)

	_explosion_effect = ExplosionEffect.new()
	add_child(_explosion_effect)

	if config:
		_health.max_health = config.max_health
		_health.current_health = config.max_health
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

func _physics_process(_delta: float) -> void:
	velocity = Vector2(0.0, -speed)
	move_and_slide()

	var cam := get_viewport().get_camera_2d()
	if cam:
		var vp := get_viewport().get_visible_rect().size
		if global_position.y < cam.global_position.y - vp.y * 0.5 - 80.0:
			print("[Ally] %s DESPAWNED (off-screen) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
			queue_free()

func _on_hurt_box_received_damage(damage: int) -> void:
	_health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current == 0:
		print("[Ally] %s DESPAWNED (died) at position %.0f, %.0f" % [name, global_position.x, global_position.y])
		_explosion_effect.explode()
		queue_free()

func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	var hb := HitBox.new()
	hb.collision_layer = 64
	hb.collision_mask = 0
	hb.damage = 25
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	add_child(hb)
```

- [ ] **Step 2: Verify in Godot**

Run the level. Ally fighters (ally waves at t=3, 7, 76, 136, 180s) should:
- Fire upward bullets at the correct interval from `ForwardAttackPattern`
- No `_fire_timer_node` or inline `_fire()` method references remain
- No GDScript errors

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/allies/ally_fighter/ally_fighter.gd
git commit -m "refactor: AllyFighter uses AttackController; remove inline _fire() timer"
```

---

## PHASE 5 — Waves as Resources

**Goal:** Replace `level_1_waves.gd` (imperative code) with `WaveResource` and `SpawnEntryResource` assets (pure data). A `@tool` EditorScript migrates all waves. The level is defined by a `LevelResource` `.tres` file.

---

### Task 12: Create WaveResource, SpawnEntryResource, and LevelResource

**Files:**
- Create: `global/resources/waves/spawn_entry_resource.gd`
- Create: `global/resources/waves/wave_resource.gd`
- Create: `global/resources/waves/level_resource.gd`

- [ ] **Step 1: Create SpawnEntryResource**

Write `global/resources/waves/spawn_entry_resource.gd`:

```gdscript
## SpawnEntryResource — data for one ship (or formation) in a wave.
## WaveManager reads these when loading a LevelResource.
class_name SpawnEntryResource
extends Resource

@export var ship_scene: PackedScene
@export var base_offset: Vector2 = Vector2.ZERO
@export var spawn_delay: float = 0.0
@export var movement: MovementResource
@export var exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
@export var look_in_moving_direction: bool = true
@export var formation: FormationResource        ## Optional — expands into N ships.
## Properties to set on the spawned entity via entity.set(key, value) at spawn time.
## Replaces the on_spawned Callable pattern. Example: {"direction": 1.0}
@export var initial_props: Dictionary = {}
```

- [ ] **Step 2: Create WaveResource**

Write `global/resources/waves/wave_resource.gd`:

```gdscript
## WaveResource — all spawn entries for one wave, with its trigger time.
class_name WaveResource
extends Resource

@export var trigger_time: float = 0.0
@export var entries: Array[SpawnEntryResource] = []
```

- [ ] **Step 3: Create LevelResource**

Write `global/resources/waves/level_resource.gd`:

```gdscript
## LevelResource — ordered list of waves defining a complete level.
## Pass to WaveManager.load_level() instead of calling register_wave() manually.
class_name LevelResource
extends Resource

@export var level_name: String = "Unnamed Level"
@export var waves: Array[WaveResource] = []
```

- [ ] **Step 4: Commit**

```bash
git add global/resources/waves/
git commit -m "feat: add SpawnEntryResource, WaveResource, LevelResource data classes"
```

---

### Task 13: Add load_level() to WaveManager and Write Migration Script

**Files:**
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`
- Create: `assault/tools/migrate_level1_waves.gd`

- [ ] **Step 1: Add load_level() to WaveManager**

Add these two methods to `wave_manager.gd` (after `register_wave()`):

```gdscript
## Loads all waves from a LevelResource. Call this from a level node's _ready()
## as a replacement for manual register_wave() calls.
func load_level(level: LevelResource) -> void:
	for wave: WaveResource in level.waves:
		var spawns: Array = []
		for entry: SpawnEntryResource in wave.entries:
			spawns.append(_entry_to_dict(entry))
		register_wave(wave.trigger_time, spawns)
	print("[WaveManager] Loaded '%s' — %d waves" % [level.level_name, level.waves.size()])

## Converts a SpawnEntryResource to the Dictionary format _spawn_ship() understands.
func _entry_to_dict(entry: SpawnEntryResource) -> Dictionary:
	var d: Dictionary = {
		"ship": {"scene": entry.ship_scene},
		"offset": entry.base_offset,
		"delay": entry.spawn_delay,
		"movement": entry.movement,
		"exit_mode": entry.exit_mode,
		"look_in_moving_direction": entry.look_in_moving_direction,
	}
	if entry.formation:
		d["formation"] = entry.formation
	if not entry.initial_props.is_empty():
		# Convert initial_props dict to on_spawned Callable
		var props: Dictionary = entry.initial_props.duplicate()
		d["on_spawned"] = func(e: Node) -> void:
			for key: String in props:
				e.set(key, props[key])
	return d
```

- [ ] **Step 2: Create the migration EditorScript**

Write `assault/tools/migrate_level1_waves.gd`. Run once from Script → Run in the Godot editor. Creates all wave `.tres` files and `level_1.tres`.

```gdscript
@tool
extends EditorScript

# ── Helpers ───────────────────────────────────────────────────────────────────

func _s(speed: float, angle: float = 0.0) -> StraightMovement:
	var m := StraightMovement.new(); m.speed = speed; m.angle = angle; return m

func _arc(dir: ArcMovement.ArcDirection, amplitude: float, duration: float) -> ArcMovement:
	var m := ArcMovement.new(); m.direction = dir; m.amplitude = amplitude; m.duration = duration; return m

func _sine(base_speed: float, amplitude: float, frequency: float = 2.5) -> SineMovement:
	var m := SineMovement.new(); m.base_speed = base_speed; m.amplitude = amplitude; m.frequency = frequency; return m

func _hold(dur: float) -> HoldMovement:
	var m := HoldMovement.new(); m.duration = dur; return m

func _seq(steps: Array) -> SequenceMovement:
	var m := SequenceMovement.new(); m.steps = steps; return m

func _v(count: int, spread: float = 40.0, row_gap: float = 12.0, stagger: float = 0.1) -> VFormation:
	var f := VFormation.new(); f.count = count; f.spread = spread; f.row_gap = row_gap; f.stagger_delay = stagger; return f

func _diag(count: int, step_x: float, step_y: float, stagger: float = 0.15) -> DiagonalFormation:
	var f := DiagonalFormation.new(); f.count = count; f.step_x = step_x; f.step_y = step_y; f.stagger_delay = stagger; return f

const FIGHTER  := "res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn"
const DRONE    := "res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn"
const RAM      := "res://assault/scenes/enemies/ram_ship/ram_ship.tscn"
const SNIPER   := "res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn"
const GUNSHIP  := "res://assault/scenes/enemies/gunship/gunship.tscn"
const BOMBER   := "res://assault/scenes/enemies/bomber/bomber.tscn"
const ALLY     := "res://assault/scenes/allies/ally_fighter/ally_fighter.tscn"

const L := ArcMovement.ArcDirection.LEFT
const R := ArcMovement.ArcDirection.RIGHT
const SCREEN_EXIT := EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT
const DURATION    := EnemyPathMover.ExitMode.FREE_ON_DURATION

func _entry(scene_path: String, offset: Vector2, mov: MovementResource,
		delay: float = 0.0,
		exit_mode: EnemyPathMover.ExitMode = EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT,
		formation: FormationResource = null,
		initial_props: Dictionary = {}) -> SpawnEntryResource:
	var e := SpawnEntryResource.new()
	e.ship_scene = load(scene_path) as PackedScene
	e.base_offset = offset
	e.movement = mov
	e.spawn_delay = delay
	e.exit_mode = exit_mode
	if formation: e.formation = formation
	e.initial_props = initial_props
	return e

func _wave(trigger: float, entries: Array) -> WaveResource:
	var w := WaveResource.new(); w.trigger_time = trigger; w.entries = entries; return w

func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("[Migration] FAILED to save %s (error %d)" % [path, err])
	else:
		print("[Migration] Saved: %s" % path)

func _run() -> void:
	print("[Migration] Starting Level 1 wave asset creation...")

	var waves: Array = [
		_wave(2.0,  [_entry(FIGHTER, Vector2(0,-180),    _s(100),     0.0, SCREEN_EXIT, _v(5))]),
		_wave(3.0,  [_entry(ALLY,    Vector2( 45,180),   _s(130,PI),  0.0),
					 _entry(ALLY,    Vector2(-35,180),   _s(170,PI),  0.3)]),
		_wave(6.0,  [_entry(FIGHTER, Vector2(180,-28),   _s(160,-PI/3.6), 0.0, SCREEN_EXIT, _diag(5,40,14))]),
		_wave(7.0,  [_entry(ALLY,    Vector2(-180,180),  _s(130,PI),  0.0)]),
		_wave(12.0, [_entry(FIGHTER, Vector2(-40,-180),  _seq([_s(60),_hold(1.5),_s(150,-PI/2)]),  0.0),
					 _entry(FIGHTER, Vector2( 40,-180),  _seq([_s(60),_hold(1.5),_s(150, PI/2)]),  0.2)]),
		_wave(22.0, [_entry(DRONE,   Vector2(-50,-180),  _sine(140,45), 0.0),
					 _entry(DRONE,   Vector2(  0,-180),  _sine(140,45), 0.0),
					 _entry(DRONE,   Vector2( 50,-180),  _sine(140,45), 0.0),
					 _entry(DRONE,   Vector2( 25,-165),  _sine(140,45), 0.2)]),
		_wave(38.0, [_entry(GUNSHIP, Vector2(  0,-180),  _s(50),        0.0),
					 _entry(FIGHTER, Vector2(-60,20),    _arc(L,130,3.5), 0.4, DURATION),
					 _entry(FIGHTER, Vector2(-20,20),    _arc(R,130,3.5), 0.4, DURATION),
					 _entry(FIGHTER, Vector2( 20,20),    _arc(L,130,3.5), 0.4, DURATION),
					 _entry(FIGHTER, Vector2( 60,20),    _arc(R,130,3.5), 0.4, DURATION)]),
		_wave(55.0, [_entry(FIGHTER, Vector2(0,28),      _s(110,-PI/4), 0.0, SCREEN_EXIT, _diag(5,40,14))]),
		_wave(68.0, [_entry(RAM,     Vector2(  0,  0),   _s(100),       0.0),
					 _entry(FIGHTER, Vector2(-50, 10),   _s(110, PI/4), 0.3),
					 _entry(FIGHTER, Vector2( 50, 10),   _s(110,-PI/4), 0.3)]),
		_wave(76.0, [_entry(ALLY,    Vector2(-50,180),   _s(120,PI-0.25), 0.0),
					 _entry(ALLY,    Vector2(  0,180),   _s(140,PI),      0.2),
					 _entry(ALLY,    Vector2( 50,180),   _s(120,PI+0.25), 0.4)]),
		_wave(85.0, [_entry(SNIPER,  Vector2(-320,-20),  _s(130, PI/2), 0.0, SCREEN_EXIT, null, {"direction": 1.0}),
					 _entry(SNIPER,  Vector2( 320, 20),  _s(130,-PI/2), 0.0, SCREEN_EXIT, null, {"direction":-1.0}),
					 _entry(FIGHTER, Vector2(-40,-180),  _s(100, PI/4), 0.6),
					 _entry(FIGHTER, Vector2(  0,  0),   _s(100),       0.6),
					 _entry(FIGHTER, Vector2( 40,-180),  _s(100,-PI/4), 0.6)]),
		_wave(103.0,[_entry(BOMBER,  Vector2(-320,-10),  _s(80, PI/2),  0.0, SCREEN_EXIT, null, {"direction": 1.0}),
					 _entry(FIGHTER, Vector2(-50,   0),  _arc(L,120,3.8), 0.5, DURATION),
					 _entry(FIGHTER, Vector2(  0,-180),  _s(95),          0.5),
					 _entry(FIGHTER, Vector2( 50,   0),  _arc(R,120,3.8), 0.5, DURATION)]),
		_wave(120.0,[_entry(FIGHTER, Vector2(-120,0),    _arc(L,140,3.5), 0.0, DURATION, _diag(3,40,12,0.0)),
					 _entry(FIGHTER, Vector2( 120,0),    _arc(R,140,3.5), 0.0, DURATION, _diag(3,-40,12,0.0)),
					 _entry(DRONE,   Vector2(-30,-180),  _sine(150,50),   0.8),
					 _entry(DRONE,   Vector2(  0,-180),  _sine(150,50),   0.8),
					 _entry(DRONE,   Vector2( 30,-180),  _sine(150,50),   0.8)]),
		_wave(136.0,[_entry(ALLY,    Vector2(-60,180),   _s(150,PI-0.2),  0.00),
					 _entry(ALLY,    Vector2(-20,180),   _s(110,PI-0.05), 0.15),
					 _entry(ALLY,    Vector2( 20,180),   _s(110,PI+0.05), 0.30),
					 _entry(ALLY,    Vector2( 60,180),   _s(150,PI+0.2),  0.45)]),
		_wave(148.0,[_entry(GUNSHIP, Vector2(-55,-180),  _s(50),          0.0),
					 _entry(GUNSHIP, Vector2( 55,-180),  _s(50),          0.0),
					 _entry(RAM,     Vector2(-30,  10),  _s(110),         0.6),
					 _entry(RAM,     Vector2( 30,  10),  _s(110),         0.6),
					 _entry(FIGHTER, Vector2(-80,  20),  _s(110, PI/4),   1.0),
					 _entry(FIGHTER, Vector2(  0,  20),  _s(100),         1.0),
					 _entry(FIGHTER, Vector2( 80,  20),  _s(110,-PI/4),   1.0)]),
		_wave(166.0,[_entry(BOMBER,  Vector2(-320,-15),  _s(80, PI/2),    0.0, SCREEN_EXIT, null, {"direction": 1.0}),
					 _entry(BOMBER,  Vector2( 320, 15),  _s(80,-PI/2),    0.0, SCREEN_EXIT, null, {"direction":-1.0}),
					 _entry(FIGHTER, Vector2(-40,-180),  _arc(L,110,3.5), 0.3, DURATION),
					 _entry(FIGHTER, Vector2(  0,   0),  _s(95),          0.3),
					 _entry(FIGHTER, Vector2( 40,-180),  _arc(R,110,3.5), 0.3, DURATION),
					 _entry(DRONE,   Vector2(-20,-180),  _sine(150,55),   0.9),
					 _entry(DRONE,   Vector2( 20,-180),  _sine(150,55),   0.9)]),
		_wave(180.0,[_entry(ALLY,    Vector2(  0,180),   _s(160,PI),      0.0),
					 _entry(ALLY,    Vector2(-40,  0),   _s(140,PI-0.18), 0.2),
					 _entry(ALLY,    Vector2( 40,  0),   _s(140,PI+0.18), 0.2),
					 _entry(ALLY,    Vector2(-80,180),   _s(125,PI-0.32), 0.4),
					 _entry(ALLY,    Vector2( 80,180),   _s(125,PI+0.32), 0.4)]),
		_wave(190.0,[_entry(GUNSHIP, Vector2(  0,  0),   _s(35),          0.0),
					 _entry(FIGHTER, Vector2(-50, 22),   _arc(L,120,4.0), 0.8, DURATION),
					 _entry(FIGHTER, Vector2(  0, 22),   _s(80),          0.8),
					 _entry(FIGHTER, Vector2( 50, 22),   _arc(R,120,4.0), 0.8, DURATION)]),
	]

	for i: int in waves.size():
		_save(waves[i], "res://assault/data/waves/level_1/wave_%02d.tres" % (i + 1))

	var level := LevelResource.new()
	level.level_name = "Level 1"
	level.waves = waves
	_save(level, "res://assault/data/levels/level_1.tres")

	print("[Migration] Complete — %d waves saved." % waves.size())
```

- [ ] **Step 3: Run the migration script in Godot**

1. Open `assault/tools/migrate_level1_waves.gd` in the Godot Script editor
2. Click **Script → Run** (top menu)
3. In the Output panel, verify you see exactly 19 `[Migration] Saved:` lines (18 waves + 1 level) followed by `[Migration] Complete`
4. In the FileSystem dock, confirm `assault/data/waves/level_1/wave_01.tres` through `wave_18.tres` and `assault/data/levels/level_1.tres` all exist

- [ ] **Step 4: Commit migration script and generated assets**

```bash
git add assault/tools/migrate_level1_waves.gd
git add assault/data/
git commit -m "feat: wave migration script + generated LevelResource and WaveResource .tres assets"
```

---

### Task 14: Wire Up LevelResource and Replace level_1_waves.gd

**Files:**
- Modify: `assault/scenes/levels/level_1_waves.gd`
- Modify: `assault/scenes/systems/wave_manager/wave_manager.gd`

- [ ] **Step 1: Replace level_1_waves.gd with a thin LevelResource loader**

Write `assault/scenes/levels/level_1_waves.gd`:

```gdscript
## Level 1 — loads wave data from a LevelResource .tres asset.
## Previously contained inline Dictionary wave definitions; now purely a loader.
## Edit wave timing and composition in assault/data/waves/level_1/ .tres files.
extends Node

@export var wave_manager: WaveManager

const _LEVEL: LevelResource = preload("res://assault/data/levels/level_1.tres")

func _ready() -> void:
	print("[LEVEL] Level 1 started — loading from LevelResource")
	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate())
	wave_manager.load_level(_LEVEL)
```

- [ ] **Step 2: Verify full level in Godot**

Run the level. Check the Output panel for all expected wave triggers:
```
[LEVEL] Level 1 started — loading from LevelResource
[WaveManager] Loaded 'Level 1' — 18 waves
[Wave 0] TRIGGERED at 2.0s — 1 spawns    ← V formation expands to 5 ships
[Wave 1] TRIGGERED at 3.0s — 2 spawns
...
[Wave 17] TRIGGERED at 190.0s — 4 spawns
```

Confirm visually:
- All wave timings match the original
- Ship formations and paths are identical to before Phase 5
- SequenceMovement demo wave at t=12s still works
- No GDScript errors

- [ ] **Step 3: Commit**

```bash
git add assault/scenes/levels/level_1_waves.gd
git commit -m "feat: Level 1 loads from LevelResource .tres — wave definitions are now pure data"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|---|---|
| MovementResource base + 4 concrete types | Task 1 |
| EnemyPathMover uses MovementResource | Task 2 |
| level_1_waves.gd uses resource instances | Task 3 |
| SequenceMovement (approach→hold→exit) | Task 4 |
| CurveMovement (editor-drawn paths) | Task 4 |
| Demo wave proving SequenceMovement | Task 5 |
| FormationResource base + V/Line/Diagonal/Cluster | Task 6 |
| WaveManager expands formations | Task 7 |
| 4 waves migrated to FormationResource | Task 8 |
| AttackPatternResource + AttackController | Task 9 |
| LightAssaultShip refactored (no _fire Timer) | Task 10 |
| approach_state.gd pool bypass bug fixed | Task 10 |
| AllyFighter refactored (no _fire Timer) | Task 11 |
| WaveResource + SpawnEntryResource + LevelResource | Task 12 |
| WaveManager.load_level() | Task 13 |
| Migration script creates all 18 wave .tres files | Task 13 |
| level_1_waves.gd replaced by thin loader | Task 14 |

### Type Consistency Check

- `MovementResource.sample(t: float) -> Vector2` — defined Task 1, consumed identically in Task 2 (`EnemyPathMover`) and Task 4 (`SequenceMovement.sample()`)
- `MovementResource.total_duration() -> float` — defined Task 1, consumed in Task 2 (`FREE_ON_DURATION` check) and Task 4 (`SequenceMovement.total_duration()`)
- `FormationResource.FormationSlot` inner class — defined Task 6 base, instantiated in all 4 subtypes (Tasks 6), iterated in Task 7 (`_expand_formation`)
- `FormationResource.compute_slots() -> Array` — defined Task 6 base, called in Task 7, implemented in all subtypes
- `AttackPatternResource.fire(ship: Node2D, pool: BulletPool) -> void` — defined Task 9 base, called in Task 9 (`AttackController._process`), implemented in `AimedAttackPattern` and `ForwardAttackPattern`
- `SpawnEntryResource.movement: MovementResource` — defined Task 12, consumed in Task 13 `_entry_to_dict()` as `"movement"` dict key
- `WaveResource.entries: Array[SpawnEntryResource]` — defined Task 12, iterated in Task 13 `load_level()`
- `WaveManager.load_level(level: LevelResource)` — defined Task 13, called in Task 14 `level_1_waves.gd`
