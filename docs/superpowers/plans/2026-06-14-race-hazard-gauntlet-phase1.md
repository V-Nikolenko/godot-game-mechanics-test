# Race Hazard Gauntlet — Phase 1 (Core Gauntlet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lethal, authored, rocket-breakable track hazards (walls + asteroids) to the race: contact one-shots any ship (player → instant race fail; AI → eliminated), and AI steer to the always-present clear gap (dying via attrition when boxed in).

**Architecture:** A duck-typed **hazard contract** (`danger_rect()`, `is_lethal_now()`, group `race_hazards`) lets one central `HazardSystem` poll ship-vs-hazard overlap and route a shield-bypassing kill, while `Sensors` reads the same hazards so `RaceShip` can run a pre-FSM lateral-dodge reflex. Hazards are placed as `Track` children (scroll like dash panels). The breakable wall reuses the `AsteroidBase` rocket-break pattern (HurtBox layer 512 / mask 32, damage_type 1).

**Tech Stack:** Godot 4.6 / GDScript. No automated test harness exists for race logic; verification is GDScript-parse + play-observation (matching existing race work).

**Constraints:**
- **NEVER commit.** The user handles all git. Every task ends "leave unstaged." No `git` steps.
- Reference real layers: player **missiles** = HitBox layer 32, damage_type 1; ship/asteroid HurtBox = layer 512, mask 32. Lane spans world X **128–1152**.
- After structural changes, the final task invokes the `updating-project-docs` skill.

**Reference spec:** `docs/superpowers/specs/2026-06-14-race-hazard-gauntlet-design.md` (this is **Phase 1** of 4).

**Optional parse check (use if the Godot CLI is on PATH; skip silently if not):**
`godot --headless --path . --quit` — boots the project; a clean exit means all scripts/scenes parsed.

---

## File Structure (Phase 1)

```
NEW  assault/scenes/race/track/race_wall.gd        RaceWall: breakable partial wall, hazard contract
NEW  assault/scenes/race/track/race_wall.tscn      RaceWall scene (Sprite2D wall_1.png + Health + HurtBox)
NEW  assault/scenes/race/track/race_asteroid.gd    RaceAsteroid extends AsteroidBase: static-on-track hazard
NEW  assault/scenes/race/core/hazard_system.gd     HazardSystem: central lethal-contact poll
EDIT assault/scenes/race/core/race_director.gd     + fail_race()
EDIT assault/scenes/race/core/sensors.gd           + race_hazard_ahead(), + safe_x()
EDIT assault/scenes/race/core/race_ship.gd         + avoidance reflex, + apply_lethal_hazard()
EDIT assault/scenes/race/core/race_participant.gd  guard: skip economy once finished/dead (kill safety)
EDIT assault/scenes/levels/race/race_level_1.tscn  + HazardSystem node, + sample walls under Track
```

**Contract (duck-typed; every hazard implements these and joins group `"race_hazards"`):**
- `func danger_rect() -> Rect2` — world-space lethal rectangle.
- `func is_lethal_now() -> bool` — Phase 1 hazards always return `true`.

(No shared base class in Phase 1 — YAGNI. A `track_hazard.gd` base is introduced in Phase 2 when lasers add shared timing logic.)

---

## Task 1: Breakable wall script (`race_wall.gd`)

**Files:**
- Create: `assault/scenes/race/track/race_wall.gd`

- [ ] **Step 1: Write the script**

```gdscript
## RaceWall — a breakable, lethal, partial-width track wall placed as a child of Track
## (authored at negative Y; scrolls with the world). Contact one-shots any ship (handled
## centrally by HazardSystem). Player rockets (missiles, HitBox layer 32, damage_type 1)
## damage its HurtBox and break it — exactly like an asteroid. Always narrower than the
## 128–1152 lane, so a lateral gap always exists (dodgeable); rocketing it opens a cleaner
## line, except when authored right behind a dash panel (a "trap" — Phase 3).
class_name RaceWall
extends Node2D

## Lethal/visual footprint in px (partial — keep narrower than the ~1024 px lane).
@export var wall_size: Vector2 = Vector2(180, 96)
## Rocket hits needed to break it (warhead deals a large hit; ~1–2 rockets).
@export var health_amount: int = 60

@onready var _health: Health = $Health
@onready var _hurt_box: HurtBox = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D

var _explosion: ExplosionEffect
var _dead: bool = false

func _ready() -> void:
	add_to_group("race_hazards")
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	_health.set_health(health_amount)
	_hurt_box.received_damage.connect(_on_received_damage)
	_health.amount_changed.connect(_on_health_changed)

## Hazard contract — world-space lethal rect, centred on this node.
func danger_rect() -> Rect2:
	return Rect2(global_position - wall_size * 0.5, wall_size)

## Hazard contract — a wall is always lethal on contact.
func is_lethal_now() -> bool:
	return not _dead

func _on_received_damage(amount: int) -> void:
	_health.decrease(amount)

func _on_health_changed(current: int) -> void:
	if current <= 0 and not _dead:
		_dead = true
		remove_from_group("race_hazards")
		_explosion.explode()
		_sprite.visible = false
		_hurt_box.set_deferred("monitoring", false)
		## Free after the explosion particles finish (matches asteroid death feel).
		await get_tree().create_timer(0.7).timeout
		queue_free()
```

- [ ] **Step 2: Verify it parses**

Open `assault/scenes/race/track/race_wall.gd` in the Godot editor (or run the optional headless boot). Expected: no parse errors; `class_name RaceWall` registers.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 2: Breakable wall scene (`race_wall.tscn`)

**Files:**
- Create: `assault/scenes/race/track/race_wall.tscn`

- [ ] **Step 1: Write the scene file**

Mirror the asteroid wiring: a `Node2D` root with the script, a `Sprite2D` using `wall_1.png`, a `Health` node, and a `HurtBox` (Area2D, layer 512 / mask 32) with a rectangle shape sized to `wall_size`. Use the existing UIDs (`Health` = `hurtbox`/`health` component scripts).

```
[gd_scene load_steps=5 format=3 uid="uid://racewall0001"]

[ext_resource type="Script" path="res://assault/scenes/race/track/race_wall.gd" id="1"]
[ext_resource type="Texture2D" path="res://assault/assets/sprites/racers/race_track/walls/wall_1.png" id="2"]
[ext_resource type="Script" path="res://global/components/health_component.gd" id="3"]
[ext_resource type="Script" path="res://global/components/hurtbox_component.gd" id="4"]

[sub_resource type="RectangleShape2D" id="rect"]
size = Vector2(180, 96)

[node name="RaceWall" type="Node2D"]
script = ExtResource("1")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2")

[node name="Health" type="Node" parent="."]
script = ExtResource("3")
max_health = 60
current_health = 60

[node name="HurtBox" type="Area2D" parent="."]
collision_layer = 512
collision_mask = 32
script = ExtResource("4")

[node name="CollisionShape2D" type="CollisionShape2D" parent="HurtBox"]
shape = SubResource("rect")
```

(If `wall_1.png` differs from 180×96, scale the `Sprite2D` or adjust `wall_size`/`rect` to match in Task 8 authoring.)

- [ ] **Step 2: Verify**

Open `race_wall.tscn` in the editor. Expected: it loads, shows the wall sprite, has `Health` + `HurtBox/CollisionShape2D`. Confirm `HurtBox.collision_layer = 512`, `collision_mask = 32`.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 3: `RaceDirector.fail_race()`

**Files:**
- Modify: `assault/scenes/race/core/race_director.gd`

- [ ] **Step 1: Add the method** (after `notify_finished`, before `_physics_process`)

```gdscript
## Force the race to fail immediately (e.g. a one-shot hazard killed the player).
## Bypasses the health path so it doesn't trigger the assault game-over overlay —
## just emits race_failed, which RaceLevelConfig reloads the scene on.
func fail_race() -> void:
	if not _race_over:
		_race_over = true
		race_failed.emit()
```

- [ ] **Step 2: Verify**

Editor reload of `race_director.gd`. Expected: no parse error; `fail_race()` callable.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 4: `RaceShip.apply_lethal_hazard()` (AI elimination)

**Files:**
- Modify: `assault/scenes/race/core/race_ship.gd`

- [ ] **Step 1: Add a guard field** — add next to the other vars (after line `var _prev_hp: int = 0`):

```gdscript
var _eliminated: bool = false
```

- [ ] **Step 2: Add the method** (place after `_play_hit_flash()`):

```gdscript
## Called by HazardSystem when this AI racer touches a lethal hazard. A hazard one-shot
## bypasses shields/HP entirely — the racer is removed from the race (attrition). The
## RaceParticipant unregisters from the director in its _exit_tree, so standings update.
func apply_lethal_hazard() -> void:
	if _eliminated:
		return
	_eliminated = true
	participant.finished = true        ## stop track_y advancing this frame
	var boom := ExplosionEffect.new()
	get_parent().add_child(boom)
	boom.global_position = global_position
	boom.explode()
	queue_free()
```

- [ ] **Step 3: Verify**

Editor reload of `race_ship.gd`. Expected: no parse error. (`ExplosionEffect` is already used elsewhere in the project, so the type resolves.)

- [ ] **Step 4: Leave unstaged.** Do NOT commit.

---

## Task 5: `HazardSystem` — central lethal contact

**Files:**
- Create: `assault/scenes/race/core/hazard_system.gd`

- [ ] **Step 1: Write the script**

```gdscript
## HazardSystem — one per race level (sibling of RaceLevelConfig). Each physics frame it
## checks every ship (player + AI racers) against every currently-lethal track hazard
## (group "race_hazards", duck-typed danger_rect()/is_lethal_now()). On overlap it applies
## a shield-bypassing one-shot: the player fails the race, an AI racer is eliminated.
## Centralising contact here keeps "where is lethal" identical to what the AI reads for
## avoidance (Sensors), so what the AI dodges is exactly what kills it.
class_name HazardSystem
extends Node

## Grows each hazard rect slightly so a ship touching the edge still registers.
const CONTACT_MARGIN: float = 6.0

var _director: RaceDirector = null
var _killed: Dictionary = {}   ## instance_id -> true (avoid double-processing a dying ship)

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector

func _physics_process(_delta: float) -> void:
	var hazards := get_tree().get_nodes_in_group("race_hazards")
	if hazards.is_empty():
		return
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var ship := n as Node2D
			if ship == null or not is_instance_valid(ship):
				continue
			if _killed.has(ship.get_instance_id()):
				continue
			var pos := ship.global_position
			for h in hazards:
				var hz := h as Node2D
				if hz == null or not is_instance_valid(hz):
					continue
				if not hz.has_method("is_lethal_now") or not hz.is_lethal_now():
					continue
				if not hz.has_method("danger_rect"):
					continue
				var rect: Rect2 = hz.danger_rect().grow(CONTACT_MARGIN)
				if rect.has_point(pos):
					_kill(ship)
					break

func _kill(ship: Node2D) -> void:
	_killed[ship.get_instance_id()] = true
	if ship.is_in_group("player"):
		if _director:
			_director.fail_race()
	elif ship.has_method("apply_lethal_hazard"):
		ship.apply_lethal_hazard()
```

- [ ] **Step 2: Verify** — open in editor; no parse error; `class_name HazardSystem` registers.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 6: Sensors — hazard scan + safe lane

**Files:**
- Modify: `assault/scenes/race/core/sensors.gd`

- [ ] **Step 1: Add `race_hazard_ahead()`** (place after the existing `hazard_ahead()` method, ~line 114):

```gdscript
## Nearest currently-lethal track hazard (group "race_hazards") ahead within lookahead px
## whose lethal rect overlaps my current X. Used by the RaceShip avoidance reflex.
func race_hazard_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_dy := lookahead
	var x := _pos().x
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if not h.has_method("is_lethal_now") or not h.is_lethal_now():
			continue
		if not h.has_method("danger_rect"):
			continue
		var rect: Rect2 = h.danger_rect()
		var dy := _pos().y - rect.get_center().y   ## >0 = ahead (above me on screen)
		if dy <= 0.0 or dy > lookahead:
			continue
		## Only care if it blocks my current X lane.
		if x < rect.position.x or x > rect.position.x + rect.size.x:
			continue
		if dy < best_dy:
			best_dy = dy
			best = h
	return best

## Nearest X within the lane [lane_min, lane_max] that clears every lethal hazard rect
## within lookahead px ahead. Steps outward from current X to the closest free side.
func safe_x(current_x: float, lookahead: float, lane_min: float = 128.0, lane_max: float = 1152.0) -> float:
	var blocks: Array[Vector2] = []   ## each = (min_x, max_x)
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if not h.has_method("is_lethal_now") or not h.is_lethal_now():
			continue
		if not h.has_method("danger_rect"):
			continue
		var rect: Rect2 = h.danger_rect()
		var dy := _pos().y - rect.get_center().y
		if dy <= 0.0 or dy > lookahead:
			continue
		blocks.append(Vector2(rect.position.x, rect.position.x + rect.size.x))
	if blocks.is_empty():
		return current_x
	## If current_x is clear, keep it.
	if _x_is_clear(current_x, blocks):
		return current_x
	## Search outward in 16 px steps for the nearest clear X inside the lane.
	for step in range(16, 1100, 16):
		var left := current_x - step
		if left >= lane_min and _x_is_clear(left, blocks):
			return left
		var right := current_x + step
		if right <= lane_max and _x_is_clear(right, blocks):
			return right
	return current_x   ## boxed in — no clear X (attrition: HazardSystem will kill us)

func _x_is_clear(x: float, blocks: Array[Vector2]) -> bool:
	for b in blocks:
		if x >= b.x and x <= b.y:
			return false
	return true
```

- [ ] **Step 2: Verify** — editor reload; no parse error; methods callable.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 7: RaceShip avoidance reflex

**Files:**
- Modify: `assault/scenes/race/core/race_ship.gd:81-85` (`_physics_process`)

- [ ] **Step 1: Add the reflex** — replace the existing `_physics_process` body:

```gdscript
func _physics_process(delta: float) -> void:
	brain.tick(delta)
	## Survival reflex: overrides the brain's desired_x when a lethal hazard blocks our
	## lane within lookahead. The authored guarantee that a gap always exists makes
	## safe_x() reliable; if we're boxed in (no clear X), safe_x returns our current x and
	## HazardSystem eliminates us next frame (attrition).
	if sensors.race_hazard_ahead(_HAZARD_LOOKAHEAD) != null:
		desired_x = sensors.safe_x(global_position.x, _HAZARD_LOOKAHEAD)
	var x := mover.step(global_position.x, desired_x, delta)
	var y := _world.get_screen_y(participant) if _world else global_position.y
	global_position = Vector2(x, y)
```

- [ ] **Step 2: Add the lookahead constant** — add near the other consts (after `_HIT_SHADER`):

```gdscript
## How far ahead (px, screen space) the survival reflex scans for lethal hazards.
const _HAZARD_LOOKAHEAD: float = 260.0
```

- [ ] **Step 3: Verify** — editor reload; no parse error.

- [ ] **Step 4: Leave unstaged.** Do NOT commit.

---

## Task 8: Asteroid-on-track adapter (`race_asteroid.gd`)

**Files:**
- Create: `assault/scenes/race/track/race_asteroid.gd`

- [ ] **Step 1: Write the adapter**

```gdscript
## RaceAsteroid — places an existing asteroid as a static track hazard. Extends AsteroidBase
## for the visuals + rocket-break (HurtBox layer 512 / mask 32, damage_type 1), but it does
## NOT self-move or self-cull: it is a child of Track and scrolls with the world, living
## until the wall of the track scrolls past. Joins "race_hazards" and exposes the lethal
## contract so HazardSystem one-shots ships on contact and Sensors can dodge it.
class_name RaceAsteroid
extends AsteroidBase

## Lethal footprint in px (roughly the asteroid's visible size).
@export var danger_size: Vector2 = Vector2(56, 56)

func _ready() -> void:
	super()                      ## AsteroidBase setup (sprite, Health, HurtBox, group "asteroids")
	add_to_group("race_hazards")
	set_physics_process(false)   ## no drift / path movement — it rides Track
	if has_node("ContactHitBox"):
		## Lethal contact is handled centrally by HazardSystem; disable the per-asteroid
		## ContactHitBox so damage isn't double-applied through the shield path.
		($ContactHitBox as Node).set("monitoring", false)

## Hazard contract.
func danger_rect() -> Rect2:
	return Rect2(global_position - danger_size * 0.5, danger_size)

func is_lethal_now() -> bool:
	return not was_killed
```

(If `AsteroidBase` drives movement in something other than `_physics_process`, or frees
itself off-screen via a `VisibleOnScreenNotifier2D`, also disable that notifier here. Check
`asteroid_base.gd` / `big_asteroid.gd` when implementing and disable whichever self-removal
path exists so a placed asteroid persists until scrolled past.)

- [ ] **Step 2: Verify** — editor reload; `class_name RaceAsteroid` registers; no parse error.

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 9: Wire HazardSystem into the level + author sample walls

**Files:**
- Modify: `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Add the HazardSystem node** — add it as a sibling of `RaceLevelConfig` (direct child of `RaceLevel1`). Add the ext_resource and node:

```
[ext_resource type="Script" path="res://assault/scenes/race/core/hazard_system.gd" id="hazardsys"]
```
```
[node name="HazardSystem" type="Node" parent="." unique_id=110000001]
script = ExtResource("hazardsys")
```

- [ ] **Step 2: Add two sample walls under the scrolling track** — add the wall scene as an ext_resource and place two instances as children of `Track/RaceTrack`, staggered so a gap always exists (one blocking the left side, one the right, at different Y). Use Track-local negative Y (deeper = further into the race), matching dash-panel placement:

```
[ext_resource type="PackedScene" path="res://assault/scenes/race/track/race_wall.tscn" id="racewall"]
```
```
[node name="WallTest1" parent="Track/RaceTrack" instance=ExtResource("racewall")]
position = Vector2(360, -4200)

[node name="WallTest2" parent="Track/RaceTrack" instance=ExtResource("racewall")]
position = Vector2(900, -6000)
```

(360 leaves the right side open; 900 leaves the left side open — a clear lane at each.)

- [ ] **Step 3: Verify in play** — run `race_level_1`. With debug collision shapes on, confirm the two walls scroll down with the track. Fly the player into a wall → **instant race fail → reload**. Dodge through the open side → pass. Fire a warhead/homing missile at a wall → it **breaks** (explosion, gone). Watch an AI racer approach a wall → it **steers to the open side**; box one in against a wall + another ship → it is **eliminated** (explosion) and drops out of the standings list.

- [ ] **Step 4: Leave unstaged.** Do NOT commit.

---

## Task 10: Safety guard on eliminated/finished participants

**Files:**
- Modify: `assault/scenes/race/core/race_participant.gd:80-83` (top of `_physics_process`)

- [ ] **Step 1: Confirm the existing guard suffices** — `_physics_process` already returns early when `finished`:

```gdscript
func _physics_process(delta: float) -> void:
	if finished or _director == null:
		return
```

`apply_lethal_hazard()` (Task 4) sets `participant.finished = true` before `queue_free()`, so an eliminated racer stops advancing immediately. **No code change needed** — this task is a verification checkpoint only.

- [ ] **Step 2: Verify** — in play, an eliminated AI does not keep advancing/finishing after death; the standings list shrinks by one. (Already covered by Task 9 Step 3; confirm no errors print when a racer dies near the finish.)

- [ ] **Step 3: Leave unstaged.** Do NOT commit.

---

## Task 11: Update the knowledge base

**Files:**
- Modify (via skill): `docs/architecture/modules/assault.md`, new per-entity doc(s), `CLAUDE.md` if needed

- [ ] **Step 1: Invoke the `updating-project-docs` skill** — Phase 1 added structural entities (`RaceWall`, `RaceAsteroid`, `HazardSystem`) and a race mechanic (lethal track hazards + AI avoidance). Follow the skill to:
  - Update the race section of `docs/architecture/modules/assault.md` (new hazard system + entities, AI avoidance reflex).
  - Add a `HAZARD.md` beside `race_wall` (`assault/scenes/race/track/`) describing the breakable wall, mirroring the existing hazard doc format.
  - Sync `CLAUDE.md` only if the module map / conventions changed (they don't — likely no change).

- [ ] **Step 2: Leave unstaged.** Do NOT commit.

---

## Self-Review (completed by plan author)

**Spec coverage (Phase 1 scope):**
- Track-hazard contract (group + `danger_rect`/`is_lethal_now`) → Tasks 1, 8 (duck-typed; base deferred to Phase 2) ✓
- Central lethal contact, shield-bypass, player fail / AI eliminate → Tasks 3, 4, 5 ✓
- Breakable wall (`wall_1.png`, asteroid pattern, partial width) → Tasks 1, 2 ✓
- Asteroid-on-track adapter → Task 8 ✓
- Sensors hazard scan + safe lane → Task 6 ✓
- AI lateral-dodge reflex + attrition → Tasks 7, 4 (attrition emergent: `safe_x` returns current x when boxed → HazardSystem kills) ✓
- Authoring (Track children, staggered gap) → Task 9 ✓
- Lasers, throttle, traps/route-refusal, speed FX → **out of Phase 1** (Phases 2–4, separate plans) ✓

**Placeholder scan:** No TBD/TODO. Parenthetical "if X, also do Y" notes in Tasks 2 & 8 are concrete contingencies (asset size / asteroid self-removal path), each naming the exact thing to check and do — not deferred work.

**Type/name consistency:** `danger_rect()`, `is_lethal_now()`, group `"race_hazards"`, `apply_lethal_hazard()`, `fail_race()`, `race_hazard_ahead()`, `safe_x()`, `_HAZARD_LOOKAHEAD`, HurtBox layer 512 / mask 32 — used identically across Tasks 1–9. `safe_x` signature matches its call in Task 7.
