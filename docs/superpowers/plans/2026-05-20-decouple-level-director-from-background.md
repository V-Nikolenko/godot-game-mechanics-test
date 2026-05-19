# Decouple LevelDirector from Level1Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a `BackgroundController` base class so `LevelDirector` no longer hard-types its background reference to `Level1Background`, enabling level 2+ to ship its own background renderer.

**Architecture:** Add a thin abstract base class with the `transition_to(phase, duration)` virtual method. `Level1Background` extends it. `LevelDirector.background` is retyped to the base class. Polymorphism handles the rest.

**Tech Stack:** Godot 4.3 GDScript, full static typing.

**Constraints:**
- No git commits — leave changes uncommitted for the user to review.
- Scene files (`level_1.tscn`) must continue working without manual reassignment of the `background` export.

---

## Architecture Overview

### Current State
```
LevelDirector
  @export var background: Level1Background      ← hard-coupled
  background.transition_to(phase, duration)
```

If level 2 ships `Level2Background`, the export type rejects it. Designer must edit the script.

### Target State
```
BackgroundController (abstract base, extends Node)
  func transition_to(phase: BackgroundPhase, duration: float) -> void
	   ↑
	   ├── Level1Background
	   └── Level2Background (future)

LevelDirector
  @export var background: BackgroundController  ← polymorphic
```

---

## File Structure

- **Create:** `global/systems/background_controller.gd` — abstract base class
- **Modify:** `assault/scenes/levels/level_1_background.gd` — extend BackgroundController
- **Modify:** `assault/scenes/systems/level_director/level_director.gd` — retype `background` export

---

## Task 1: Create BackgroundController Base Class

**Files:**
- Create: `global/systems/background_controller.gd`

- [ ] **Step 1: Write the base class**

```gdscript
## BackgroundController — abstract base for level background renderers.
##
## Subclasses must override `transition_to()` to tween their visual state
## toward the values in a BackgroundPhase resource over the given duration.
##
## LevelDirector calls this on each section start. Sequencer code should
## reference this type rather than any concrete level-specific class.
class_name BackgroundController
extends Node

## Transition the background's visual state toward [phase] over [duration]
## seconds. A duration of 0 should snap instantly. A null phase is a no-op.
##
## Default implementation logs a warning and does nothing — subclasses MUST
## override.
func transition_to(phase: BackgroundPhase, duration: float) -> void:
	push_warning(
		"[BackgroundController] transition_to() not overridden on %s" %
		[get_script().resource_path if get_script() else "unknown"]
	)
```

- [ ] **Step 2: Verify the file parses**

Open Godot editor, confirm no parse errors in the Output panel.

---

## Task 2: Update Level1Background to Extend BackgroundController

**Files:**
- Modify: `assault/scenes/levels/level_1_background.gd` (line 23-24)

- [ ] **Step 1: Change the extends clause**

Find this line near the top:
```gdscript
class_name Level1Background
extends Node
```

Replace with:
```gdscript
class_name Level1Background
extends BackgroundController
```

- [ ] **Step 2: Verify `transition_to` signature still matches**

Confirm the existing `transition_to(phase: BackgroundPhase, duration: float) -> void` signature matches the base class. No code change needed — it already matches.

- [ ] **Step 3: Verify the scene still loads**

Open `assault/scenes/levels/level_1_background.tscn` in the Godot editor. Confirm no errors. The script should still attach correctly (subclass relationship doesn't break scene wiring).

---

## Task 3: Retype LevelDirector.background

**Files:**
- Modify: `assault/scenes/systems/level_director/level_director.gd` (line 14)

- [ ] **Step 1: Change the export type**

Find:
```gdscript
@export var background:   Level1Background
```

Replace with:
```gdscript
@export var background:   BackgroundController
```

- [ ] **Step 2: Verify _advance() call still type-checks**

Confirm line 60-61 still works without change:
```gdscript
if background:
	background.transition_to(s.background_phase, s.transition_in_duration)
```

`background` is now `BackgroundController`, which has `transition_to()`. This compiles.

- [ ] **Step 3: Verify level_1.tscn doesn't lose its assignment**

Open `assault/scenes/levels/level_1.tscn` in the editor. Inspect the `LevelDirector` node. The `background` property should still be wired to `NodePath("../Level1Background")` because:
- `Level1Background` now IS-A `BackgroundController`
- Godot resolves NodePaths by node, not by exact type — as long as the target node's script is a subclass of the declared type, assignment is preserved

If for some reason the assignment is cleared (rare but possible after type changes), re-set it via the Inspector.

---

## Task 4: Smoke Test the Refactor

**Files:** None modified.

- [ ] **Step 1: Run the game and play Level 1**

Boot the game → launch Level 1. Verify:
- Background renders at start (deep space)
- After 30s: planet approach transition begins
- After 140s total: cloud descent transition begins
- All transitions look identical to pre-refactor behavior

- [ ] **Step 2: Verify no Output panel warnings**

Confirm no `[BackgroundController] transition_to() not overridden` warnings in the Output panel. If any appear, the override on `Level1Background` isn't being recognized — check the extends clause.

- [ ] **Step 3: Visual diff against pre-refactor behavior**

Optional: record gameplay before and after; confirm identical visuals.

---

## Future Use (Reference Only — Not Part of This Plan)

When level 2 ships:

```gdscript
# level_2_background.gd
class_name Level2Background
extends BackgroundController

func transition_to(phase: BackgroundPhase, duration: float) -> void:
    # Level-2-specific animation logic
    ...
```

```gdscript
# level_2.tscn LevelDirector node:
background = NodePath("../Level2Background")  # type-compatible
```

No changes needed in `LevelDirector` itself.

---

## Files Changed Summary

| File | Action | Lines |
|---|---|---|
| `global/systems/background_controller.gd` | Create | ~15 |
| `assault/scenes/levels/level_1_background.gd` | Modify (extends clause) | 1 line changed |
| `assault/scenes/systems/level_director/level_director.gd` | Modify (export type) | 1 line changed |

**Total:** 3 files, ~17 lines, ~30 minutes.

---

## Rollback Plan

Revert the three line-level changes. The base class file can stay (unused).

---

## Success Criteria

- ✅ `BackgroundController` exists with `transition_to()` virtual method
- ✅ `Level1Background extends BackgroundController`
- ✅ `LevelDirector.background` is typed `BackgroundController`
- ✅ Level 1 plays identically to pre-refactor behavior
- ✅ Future levels can ship custom backgrounds without modifying `LevelDirector`
