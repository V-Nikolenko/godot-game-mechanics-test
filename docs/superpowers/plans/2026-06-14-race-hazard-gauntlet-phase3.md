# Race Hazard Gauntlet — Phase 3 (Trapped Panels + Route Refusal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline).

**Goal:** Make a wall placed just ahead of a dash panel a "rocket-or-die" trap (the panel's `+650` lunge commits you into it), and have AI racers refuse trapped panels.

**Architecture:** No new node — the trap is emergent from authoring. `Sensors.panel_is_trapped()` detects a non-laser lethal hazard within `panel_lunge` ahead of a panel in its lane; the existing `nearest_panel_ahead()` skips trapped panels, so all 8 panel-seeking states refuse them with one change (DRY). A sample trap is authored in the level.

**Tech Stack:** Godot 4.6 / GDScript. Verification: in-editor parse + play-observation.

**Constraints:** NEVER commit (leave unstaged). Builds on Phase 1–2 (`race_hazards`, `RaceWall`, `LaserRay`). Lane tolerance ≈150px; lunge = `RaceParticipant.panel_lunge` (650).

**Reference spec:** `docs/superpowers/specs/2026-06-14-race-hazard-gauntlet-design.md` (Phase 3 of 4).

---

## File Structure

```
EDIT assault/scenes/race/core/sensors.gd          + panel_is_trapped(); nearest_panel_ahead() skips trapped
EDIT assault/scenes/levels/race/race_level_1.tscn  author a sample trapped panel (panel + wall ahead, same lane)
EDIT assault/scenes/race/track/RACE_HAZARDS.md     + trap note (via updating-project-docs, with Phase 2 laser/throttle)
EDIT docs/architecture/modules/assault.md          + trapped-panel route refusal (same skill pass)
```

---

## Task 1: `Sensors.panel_is_trapped()` + filter

**Files:** Modify `assault/scenes/race/core/sensors.gd`

- [ ] **Step 1: Add a lane-tolerance const** near the top exports/consts:

```gdscript
## Lateral tolerance (px) for "a hazard is in the same lane as this panel" (trap check).
const _TRAP_LANE_TOL: float = 150.0
```

- [ ] **Step 2: Add `panel_is_trapped()`** directly above `nearest_panel_ahead()`:

```gdscript
## True if crossing this dash panel would lunge the ship (+panel_lunge track_y) into a
## non-laser lethal hazard (wall/asteroid) sitting just ahead in the panel's lane. Such a
## panel is rocket-or-die for the player; AI refuse it (nearest_panel_ahead skips it).
## Lasers are excluded — they pulse, and the laser timing reflex handles them separately.
func panel_is_trapped(panel: Node2D) -> bool:
	if panel == null:
		return false
	var lunge: float = _part.panel_lunge if _part else 650.0
	var px := panel.global_position.x
	var py := panel.global_position.y
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h) or h is LaserRay:
			continue
		if not h.has_method("danger_rect"):
			continue
		var c: Vector2 = h.danger_rect().get_center()
		var ahead := py - c.y                  ## >0 = hazard ahead (above the panel)
		if ahead <= 0.0 or ahead > lunge:
			continue
		if absf(c.x - px) < _TRAP_LANE_TOL:
			return true
	return false
```

- [ ] **Step 3: Skip trapped panels in `nearest_panel_ahead()`** — add the guard right after the null check:

```gdscript
		var p := n as Node2D
		if p == null:
			continue
		if panel_is_trapped(p):
			continue
```

- [ ] **Step 4: Verify** — editor reload; no parse error.
- [ ] **Step 5: Leave unstaged.**

---

## Task 2: Author a sample trapped panel

**Files:** Modify `assault/scenes/levels/race/race_level_1.tscn`

- [ ] **Step 1: Add a dash panel + a wall ~450 px ahead in the same lane**, under `Track/RaceTrack`, in a clear zone (between the `-10458` and `-12249` panels):

```
[node name="TrapPanel" parent="Track/RaceTrack" instance=ExtResource("panel")]
position = Vector2(760, -11200)

[node name="TrapWall" parent="Track/RaceTrack" instance=ExtResource("racewall")]
position = Vector2(760, -11650)
```

(Wall at `-11650` is 450 px ahead of the panel at `-11200` — within the 650 lunge — at the same X=760, so the lunge commits you into it.)

- [ ] **Step 2: Verify in play** — approach `TrapPanel`:
  - cross it **without firing** → the lunge slams you into `TrapWall` → race fail;
  - **rocket** the wall first → it breaks, you lunge through safely;
  - **skip** the panel (cross at a different X) → safe.
  - Watch AI: panel-seekers (Booster Gold, Pacer, Bogomol, …) should **not** dive for `TrapPanel` — they ignore it and take other panels.
- [ ] **Step 3: Leave unstaged.**

---

## Task 3: Update the knowledge base (covers Phase 2 + Phase 3)

**Files:** `assault/scenes/race/track/RACE_HAZARDS.md`, `docs/architecture/modules/assault.md`

- [ ] **Step 1: Invoke `updating-project-docs`** — document the Phase-2 `RaceLaser` (inherited `LaserRay` pulse/timing mode, horizontal/vertical, contract) + the player throttle (`race_brake`), and the Phase-3 trapped-panel mechanic + AI route refusal. No `PROJECT.md`/`CLAUDE.md` change (no module/autoload/convention change).
- [ ] **Step 2: Leave unstaged.**

---

## Self-Review

**Spec coverage:** trapped panel rocket-or-die (Tasks 1–2) ✓; AI route refusal via one `nearest_panel_ahead` filter (Task 1, all 8 seekers) ✓; lasers excluded from trap logic (pulse — handled by Phase-2 timing) ✓. Out of scope: speed FX (Phase 4).

**Placeholder scan:** none. **Type/name consistency:** `panel_is_trapped`, `_TRAP_LANE_TOL`, `danger_rect()` (Phase-1 contract), `LaserRay` (Phase-2) used consistently; `_part.panel_lunge` matches `RaceParticipant`.
