# Race Hazard Gauntlet — Phase 2 (Lasers + Throttle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline). Steps use checkbox (`- [ ]`).

**Goal:** Add pulsing, telegraphed laser hazards (horizontal timing gates + vertical lateral bands) on the hazard backbone, a player brake/throttle to time them, and AI laser timing (brake-and-cross).

**Architecture:** A new self-contained `RaceLaser` (Node2D, `Line2D` beam, WARN→ACTIVE→OFF cycle) implements the Phase-1 hazard contract (`danger_rect()`, `is_lethal_now()`) plus timing accessors (`lethal_eta()`, `active_remaining()`). It reuses the existing `HazardSystem` (lethal contact) and `Sensors`/`race_ship` dodge reflex unchanged for **vertical** lasers (a lateral band). **Horizontal** lasers (full-width) add a timing branch: the player brakes via a new `race_brake` input feeding the player's `cruise_factor`; AI brake-and-cross via `sensors.laser_should_brake()`.

**Tech Stack:** Godot 4.6 / GDScript. Verification: in-editor parse + play-observation (no race test harness).

**Constraints:** NEVER commit (leave unstaged). Lane world-X = 128–1152. Laser lethal contact is shield-bypassing (already handled by `HazardSystem`). Builds on Phase 1 (`race_hazards` group, `HazardSystem`, `sensors.race_hazard_ahead/safe_x`, `race_ship` reflex).

**Reference spec:** `docs/superpowers/specs/2026-06-14-race-hazard-gauntlet-design.md` (Phase 2 of 4).

---

## File Structure

```
NEW  assault/scenes/race/track/race_laser.gd     RaceLaser: pulsing beam + contract + timing
NEW  assault/scenes/race/track/race_laser.tscn    scene (Line2D beam)
EDIT project.godot                                + race_brake input action
EDIT assault/scenes/race/core/race_participant.gd apply cruise_factor to the player too
EDIT assault/scenes/race/player_race_controller.gd read race_brake → player throttle
EDIT assault/scenes/race/core/sensors.gd          + laser timing helpers
EDIT assault/scenes/race/core/race_ship.gd        reflex: horizontal-laser brake/cross branch
EDIT assault/scenes/levels/race/race_level_1.tscn  author sample lasers (1 horizontal, 1 vertical)
EDIT assault/scenes/race/track/RACE_HAZARDS.md     document RaceLaser (via updating-project-docs)
```

**Contract additions (RaceLaser; walls/asteroids keep returning lethal-now/0):**
- `func lethal_eta() -> float` — seconds until the beam next becomes lethal (`0.0` if lethal now).
- `func active_remaining() -> float` — seconds left in the current lethal phase (`0.0` if not lethal).

---

## Task 1: `RaceLaser` script

**Files:** Create `assault/scenes/race/track/race_laser.gd`

- [ ] **Step 1: Write the script**

```gdscript
## RaceLaser — a pulsing, telegraphed laser hazard placed as a child of Track. Cycles
## WARN (telegraph, safe) → ACTIVE (lethal) → OFF (safe) forever while on the track.
## Implements the Phase-1 hazard contract (danger_rect/is_lethal_now) so HazardSystem
## one-shots ships and Sensors can avoid it, plus timing accessors for AI/laser planning.
##
## Orientation:
##   HORIZONTAL — beam spans the lane left↔right at this node's Y. A full-width TIMING gate:
##                cross while OFF (boost through, or brake and wait).
##   VERTICAL   — beam runs up↔down along the track at this node's X. A lateral no-go band:
##                steer out of it (handled by the existing dodge reflex).
class_name RaceLaser
extends Node2D

enum Orientation { HORIZONTAL, VERTICAL }
enum _Phase { WARN, ACTIVE, OFF }

@export var orientation: Orientation = Orientation.HORIZONTAL
## Beam length in px. HORIZONTAL: across the lane (default ~lane width). VERTICAL: along track.
@export var length: float = 1024.0
## Lethal beam thickness in px.
@export var thickness: float = 44.0
## Telegraph seconds before the beam becomes lethal.
@export var warn_time: float = 1.1
## Seconds the beam stays lethal.
@export var active_time: float = 1.2
## Safe seconds after a lethal phase before the next telegraph.
@export var off_time: float = 1.6
## Phase offset (seconds) so multiple lasers desync. Applied once at start.
@export var phase_offset: float = 0.0

@onready var _line: Line2D = $Line2D

var _phase: int = _Phase.OFF
var _t: float = 0.0   ## seconds remaining in the current phase

const _COL_WARN := Color(1.0, 0.85, 0.2, 0.5)
const _COL_ACTIVE := Color(1.0, 0.2, 0.15, 1.0)

func _ready() -> void:
	add_to_group("race_hazards")
	_build_beam()
	## Start in OFF, then bias by phase_offset so a row of lasers desyncs.
	_phase = _Phase.OFF
	_t = maxf(0.01, off_time - phase_offset)
	_apply_visual()

func _build_beam() -> void:
	var half := length * 0.5
	if orientation == Orientation.HORIZONTAL:
		_line.points = PackedVector2Array([Vector2(-half, 0), Vector2(half, 0)])
	else:
		_line.points = PackedVector2Array([Vector2(0, -half), Vector2(0, half)])
	_line.width = thickness

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	match _phase:
		_Phase.OFF:
			_phase = _Phase.WARN
			_t = warn_time
		_Phase.WARN:
			_phase = _Phase.ACTIVE
			_t = active_time
		_Phase.ACTIVE:
			_phase = _Phase.OFF
			_t = off_time
	_apply_visual()

func _apply_visual() -> void:
	match _phase:
		_Phase.ACTIVE:
			_line.visible = true
			_line.default_color = _COL_ACTIVE
			_line.width = thickness
		_Phase.WARN:
			_line.visible = true
			_line.default_color = _COL_WARN
			_line.width = thickness * 0.35
		_Phase.OFF:
			_line.visible = false

# ── Hazard contract ───────────────────────────────────────────────────────────
func danger_rect() -> Rect2:
	var half := length * 0.5
	if orientation == Orientation.HORIZONTAL:
		return Rect2(global_position + Vector2(-half, -thickness * 0.5), Vector2(length, thickness))
	return Rect2(global_position + Vector2(-thickness * 0.5, -half), Vector2(thickness, length))

func is_lethal_now() -> bool:
	return _phase == _Phase.ACTIVE

func is_full_width() -> bool:
	return orientation == Orientation.HORIZONTAL

## Seconds until the beam next becomes lethal (0 if lethal now).
func lethal_eta() -> float:
	match _phase:
		_Phase.ACTIVE: return 0.0
		_Phase.WARN:   return _t
		_:             return _t + warn_time   ## OFF: wait out off, then warn

## Seconds the current lethal phase has left (0 if not lethal).
func active_remaining() -> float:
	return _t if _phase == _Phase.ACTIVE else 0.0
```

- [ ] **Step 2: Verify** — open in editor; `class_name RaceLaser` registers; no parse error.
- [ ] **Step 3: Leave unstaged.**

---

## Task 2: `RaceLaser` scene

**Files:** Create `assault/scenes/race/track/race_laser.tscn`

- [ ] **Step 1: Write the scene** (a `Line2D` child; the script sets its points/width):

```
[gd_scene load_steps=2 format=3 uid="uid://braceslaser001"]

[ext_resource type="Script" path="res://assault/scenes/race/track/race_laser.gd" id="1_laser"]

[node name="RaceLaser" type="Node2D"]
script = ExtResource("1_laser")

[node name="Line2D" type="Line2D" parent="."]
width = 44.0
default_color = Color(1, 0.2, 0.15, 1)
begin_cap_mode = 2
end_cap_mode = 2
```

- [ ] **Step 2: Verify** — opens in editor; shows a `Line2D` child.
- [ ] **Step 3: Leave unstaged.**

---

## Task 3: `race_brake` input action

**Files:** Modify `project.godot` (the `[input]` section)

- [ ] **Step 1: Add the action** — append after the last input action (before the next section). Bind to **Left Shift** (physical_keycode 4194325):

```
race_brake={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194325,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Verify** — Project Settings → Input Map shows `race_brake` bound to Shift; no parse error on load.
- [ ] **Step 3: Leave unstaged.**

---

## Task 4: Apply `cruise_factor` to the player

**Files:** Modify `assault/scenes/race/core/race_participant.gd:92`

- [ ] **Step 1: Change the speed line** — the player currently ignores `cruise_factor`; make the throttle apply to everyone:

```gdscript
	current_speed = top_speed * cruise_factor
```

(Replaces `current_speed = top_speed * (cruise_factor if not is_player else 1.0)`. Default `cruise_factor` is `1.0`, so unbraked behaviour is unchanged; the player's brake now lowers it.)

- [ ] **Step 2: Verify** — editor reload; no parse error; AI still race normally.
- [ ] **Step 3: Leave unstaged.**

---

## Task 5: Player brake → throttle

**Files:** Modify `assault/scenes/race/player_race_controller.gd`

- [ ] **Step 1: Add a brake export + apply it** in `_physics_process` (after the band clamp):

Add the export near the top exports:
```gdscript
## Forward throttle while holding race_brake (1.0 = full speed). Lets the player slow to
## time a laser; the world scrolls slower and the player drops back in standings.
@export var brake_throttle: float = 0.3
```

In `_physics_process`, after the existing `_ship.global_position.y = clampf(...)` line, add:
```gdscript
	## Throttle: holding race_brake slows the player's forward advance (RaceParticipant
	## applies cruise_factor to the player as of Phase 2). Release = full speed.
	_participant.set_cruise_factor(brake_throttle if Input.is_action_pressed("race_brake") else 1.0)
```

- [ ] **Step 2: Verify in play** — hold Shift during a race → the world scroll visibly slows and the player drops back; release → recovers. (No laser needed yet.)
- [ ] **Step 3: Leave unstaged.**

---

## Task 6: Sensors — laser timing helpers

**Files:** Modify `assault/scenes/race/core/sensors.gd`

- [ ] **Step 1: Add the helpers** (after `safe_x` / `_x_is_clear`):

```gdscript
## Nearest full-width (horizontal) RaceLaser ahead within lookahead px — a timing gate the
## ship cannot dodge laterally. Returns null if none (vertical lasers are dodged via safe_x).
func blocking_laser_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_dy := lookahead
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var l := n as RaceLaser
		if l == null or not is_instance_valid(l) or not l.is_full_width():
			continue
		var dy := _pos().y - l.global_position.y   ## >0 = ahead (above me)
		if dy <= 0.0 or dy > lookahead:
			continue
		if dy < best_dy:
			best_dy = dy
			best = l
	return best

## Decide whether to brake before a horizontal laser. Brake to hold behind an active beam,
## or if crossing now would enter the beam before it clears. Otherwise cross (don't brake).
## approach_speed is the ship's unbraked track advance (use top_speed so braking can't
## freeze the decision into a stuck state).
func laser_should_brake(laser: RaceLaser, approach_speed: float) -> bool:
	var dist := _pos().y - laser.global_position.y      ## track gap ≈ on-screen gap
	if dist <= 0.0:
		return false                                    ## already across
	var eta := dist / maxf(approach_speed, 1.0)
	if laser.is_lethal_now():
		return true                                     ## never advance into an active beam
	## OFF/WARN: only cross if it stays safe until I clear it.
	return laser.lethal_eta() < eta
```

- [ ] **Step 2: Verify** — editor reload; no parse error.
- [ ] **Step 3: Leave unstaged.**

---

## Task 7: RaceShip reflex — laser timing branch

**Files:** Modify `assault/scenes/race/core/race_ship.gd` (`_physics_process`, the reflex block from Phase 1)

- [ ] **Step 1: Replace the reflex block** with a version that dodges when a gap exists and brakes/crosses a full-width laser otherwise:

```gdscript
	## Survival reflex (runs after the brain each frame, overriding its intent):
	##  • a lateral hazard with a gap (walls, asteroids, vertical lasers) → steer to safe_x;
	##  • a full-width horizontal laser (no gap) → brake to hold behind it, then cross when OFF.
	if sensors.race_hazard_ahead(_HAZARD_LOOKAHEAD) != null:
		var sx := sensors.safe_x(global_position.x, _HAZARD_LOOKAHEAD)
		if not is_equal_approx(sx, global_position.x):
			desired_x = sx
		else:
			var laser := sensors.blocking_laser_ahead(_HAZARD_LOOKAHEAD) as RaceLaser
			if laser != null and sensors.laser_should_brake(laser, participant.top_speed):
				participant.set_cruise_factor(0.0)
			else:
				participant.set_cruise_factor(1.0)
```

- [ ] **Step 2: Verify in play** — an AI approaching an active horizontal laser stops short and waits; when the beam turns OFF it advances and crosses; it does not die to the beam (unless genuinely boxed). Vertical lasers are dodged laterally as before.
- [ ] **Step 3: Leave unstaged.**

---

## Task 8: Author sample lasers in the level

**Files:** Modify `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Add the laser scene ext_resource** (next to the other hazard ext_resources near the top):

```
[ext_resource type="PackedScene" path="res://assault/scenes/race/track/race_laser.tscn" id="racelaser"]
```

- [ ] **Step 2: Place one horizontal (timing) + one vertical (lateral) laser** under `Track/RaceTrack`, staggered away from the test walls/asteroid:

```
[node name="LaserH1" parent="Track/RaceTrack" instance=ExtResource("racelaser")]
position = Vector2(640, -10000)

[node name="LaserV1" parent="Track/RaceTrack" instance=ExtResource("racelaser")]
position = Vector2(420, -12500)
orientation = 1
length = 900.0
```

(`LaserH1` is horizontal across the lane at the centre; `LaserV1` is vertical — `orientation = 1` = VERTICAL — a lateral band at X 420, leaving the right side clear.)

- [ ] **Step 3: Verify in play** — reach `LaserH1`: it telegraphs (thin amber) then fires (thick red); crossing during red = race fail; boosting through before it fires, or braking (Shift) to wait then crossing = safe. Reach `LaserV1`: staying right of it = safe; entering the band while lethal = fail. AI handle both.
- [ ] **Step 4: Leave unstaged.**

---

## Task 9: Update the knowledge base

**Files:** `assault/scenes/race/track/RACE_HAZARDS.md`, `docs/architecture/modules/assault.md`

- [ ] **Step 1: Invoke the `updating-project-docs` skill** — add `RaceLaser` (orientations, pulse cycle, timing contract) to `RACE_HAZARDS.md`; note the player throttle/brake (`race_brake`) and AI laser timing in the `assault.md` race section. No `PROJECT.md`/`CLAUDE.md` change (no module/autoload/convention change).
- [ ] **Step 2: Leave unstaged.**

---

## Self-Review (completed by plan author)

**Spec coverage (Phase 2 scope):** horizontal timing laser + vertical lateral laser (Tasks 1,2,8) ✓; telegraph/pulse (Task 1) ✓; player throttle/brake + `race_brake` action (Tasks 3,4,5) ✓; AI laser timing brake-and-cross (Tasks 6,7) ✓; vertical-laser dodge reuses Phase-1 reflex (Task 7) ✓. Out of scope: trapped panels/route-refusal (Phase 3), speed FX (Phase 4).

**Placeholder scan:** none — all code is complete; the input-action Object string is the real Godot 4 format.

**Type/name consistency:** `danger_rect()`/`is_lethal_now()` match the Phase-1 contract used by `HazardSystem`/`sensors`; new `lethal_eta()`, `active_remaining()`, `is_full_width()`, `blocking_laser_ahead()`, `laser_should_brake()` are defined in Task 1/6 and used consistently in Task 7; `cruise_factor` throttle path consistent across Tasks 4 (RaceParticipant), 5 (player), 7 (AI).
