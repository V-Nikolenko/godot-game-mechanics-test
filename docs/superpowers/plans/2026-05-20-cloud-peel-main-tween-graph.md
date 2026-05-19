# Cloud Peel Into Main Tween Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move cloud peel and surface-appear animations from independent `get_tree().create_timer()` schedulers into the main `_transition_tween` graph, so they get killed when `transition_to()` is called again.

**Architecture:** Godot's `Tween.tween_property().set_delay()` already supports per-step delays. Currently peels are scheduled via standalone timers that fire `_run_peel()`, which creates a fresh tween outside the cancelable graph. Replace timers with delayed tweens added directly to `_transition_tween`.

**Tech Stack:** Godot 4.3 GDScript, Godot Tween API with `set_delay()`, `set_ease()`, `set_trans()`.

**Constraints:**
- No git commits.
- Visual behavior must be identical (or visually indistinguishable) from current.

---

## Architecture Overview

### Current State
```
transition_to(phase, duration)
  └─ create_tween() → _transition_tween   ← cancelable
     ├─ tween alphas, planet scale, etc.
     └─ ...
  └─ _schedule_peel_timers(phase)         ← escapes the tween
     ├─ create_timer(10s).timeout → _run_peel(4, 3.0, 4.0)
     │                              └─ create_tween() [SEPARATE]
     ├─ create_timer(25s).timeout → _run_peel(3, 5.0, 4.0)
     └─ create_timer(12s).timeout → _run_surface_appear(10.0)
                                    └─ create_tween() [SEPARATE]
```

**Problem:** If `transition_to()` is called again before peels fire, the standalone timers still fire and start independent tweens that fight the new state.

### Target State
```
transition_to(phase, duration)
  └─ create_tween() → _transition_tween   ← cancelable, includes peels
     ├─ tween alphas, planet scale, etc.
     ├─ tween_property(_alpha_cloud_4, 0.0, 3.0).set_delay(10.0)
     ├─ tween_property(_scale_cloud_4, 4.0, 3.0).set_delay(10.0).set_ease(...)
     ├─ tween_property(_alpha_cloud_3, 0.0, 5.0).set_delay(25.0)
     ├─ ...
     └─ tween_property(_alpha_surface, 1.0, 10.0).set_delay(12.0)
```

When `_transition_tween.kill()` runs at the start of the next `transition_to()`, ALL scheduled animations stop.

---

## File Structure

- **Modify:** `assault/scenes/levels/level_1_background.gd`
  - Replace `_schedule_peel_timers()` body with inline tween additions in `transition_to()`
  - Delete `_run_peel()` and `_run_surface_appear()` methods (no longer needed)

---

## Task 1: Inline Cloud Peel Tweens

**Files:**
- Modify: `assault/scenes/levels/level_1_background.gd`

- [ ] **Step 1: Add a helper to add one peel layer's tweens to the main graph**

Add this method near the other helpers (before `_apply_cloud_layer`):

```gdscript
## Add a single layer's peel tweens (alpha→0 + scale→target) to the main
## transition tween, scheduled to begin [delay] seconds into the transition.
## Layer is one of 1, 2, 3, 4. Uses the same property name convention used
## elsewhere in this file.
func _add_peel_to_tween(layer: int, delay: float, duration: float, target_scale: float) -> void:
	if not _transition_tween or not _transition_tween.is_valid():
		return
	var alpha_prop := "_alpha_cloud_%d" % layer
	var scale_prop := "_scale_cloud_%d" % layer
	_transition_tween.tween_property(self, alpha_prop, 0.0, duration).set_delay(delay)
	_transition_tween.tween_property(self, scale_prop, target_scale, duration)\
		.set_delay(delay)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
```

- [ ] **Step 2: Replace `_schedule_peel_timers()` call with inline tween additions**

In `transition_to()`, find this block at the end:

```gdscript
# Surface
if phase.surface_appear_start < 0.0:
    _transition_tween.tween_property(self, "_alpha_surface", phase.surface_alpha, duration)

_schedule_peel_timers(phase)
```

Replace with:

```gdscript
# Cloud peels — schedule on the main tween instead of separate timers so
# kill() cancels them when transition_to() is called again.
if phase.cloud_4_peel_start >= 0.0:
    _add_peel_to_tween(4, phase.cloud_4_peel_start, phase.cloud_4_peel_duration, phase.cloud_peel_scale)
if phase.cloud_3_peel_start >= 0.0:
    _add_peel_to_tween(3, phase.cloud_3_peel_start, phase.cloud_3_peel_duration, phase.cloud_peel_scale)
if phase.cloud_2_peel_start >= 0.0:
    _add_peel_to_tween(2, phase.cloud_2_peel_start, phase.cloud_2_peel_duration, phase.cloud_peel_scale)
if phase.cloud_1_peel_start >= 0.0:
    _add_peel_to_tween(1, phase.cloud_1_peel_start, phase.cloud_1_peel_duration, phase.cloud_peel_scale)

# Surface appear (delayed) — same treatment.
# Note: the surface tween in the block above only runs when phase.surface_appear_start
# is negative (i.e. no delayed appear). When start >= 0, the delayed appear below replaces it.
if phase.surface_appear_start >= 0.0:
    _transition_tween.tween_property(self, "_alpha_surface", 1.0, phase.surface_appear_duration)\
        .set_delay(phase.surface_appear_start)
```

- [ ] **Step 3: Handle the instant-snap branch**

The instant-snap branch (`if duration <= 0.0`) currently calls `_schedule_peel_timers(phase)`. After this refactor, that call would try to add tweens to a null `_transition_tween`. Replace the call:

Find in the `if duration <= 0.0:` block:
```gdscript
_schedule_peel_timers(phase)
return
```

Replace with: just `return`. (Instant snap means no animation, so no peel scheduling.)

If you want peels to still fire on an instant-snap section transition (e.g., the cloud_descent section starts with `transition_in_duration = 2.0` but if someone sets it to 0 the peels would be lost), create a one-shot tween just for the peels:

```gdscript
if phase.cloud_4_peel_start >= 0.0 or phase.cloud_3_peel_start >= 0.0 \
   or phase.cloud_2_peel_start >= 0.0 or phase.cloud_1_peel_start >= 0.0 \
   or phase.surface_appear_start >= 0.0:
    _transition_tween = create_tween().set_parallel(true)
    if phase.cloud_4_peel_start >= 0.0:
        _add_peel_to_tween(4, phase.cloud_4_peel_start, phase.cloud_4_peel_duration, phase.cloud_peel_scale)
    # ... etc for 3, 2, 1, surface
return
```

**Recommended:** Use the simpler version (just `return`) — if a level uses `transition_in_duration = 0`, they're explicitly saying "snap, no animation". Peels for cloud descent are part of the animation.

---

## Task 2: Delete Obsolete Methods

**Files:**
- Modify: `assault/scenes/levels/level_1_background.gd`

- [ ] **Step 1: Delete `_schedule_peel_timers()`**

Remove the entire function (currently around lines 348-366):

```gdscript
func _schedule_peel_timers(phase: BackgroundPhase) -> void:
	# ... entire body ...
```

- [ ] **Step 2: Delete `_run_peel()`**

Remove the entire function (currently around lines 369-387):

```gdscript
func _run_peel(layer: int, duration: float, target_scale: float) -> void:
	# ... entire body ...
```

- [ ] **Step 3: Delete `_run_surface_appear()`**

Remove the entire function (currently around lines 390-391):

```gdscript
func _run_surface_appear(duration: float) -> void:
	create_tween().tween_property(self, "_alpha_surface", 1.0, duration)
```

- [ ] **Step 4: Search for orphan references**

Use Grep to verify nothing else references these names:

```
Pattern: "_schedule_peel_timers|_run_peel|_run_surface_appear"
Glob: **/*.gd
```

Expected: zero matches. If any appear, those callers need updating too.

---

## Task 3: Verify Visual Behavior

**Files:** None modified.

- [ ] **Step 1: Run Level 1 to the cloud descent section**

Boot game → Level 1 → play through Deep Space (30s) and Planet Approach (110s) until Cloud Descent section begins.

- [ ] **Step 2: Verify peels fire at the correct times**

Cloud descent has these peel offsets relative to section start:
- 10s: cloud 4 peels (3s duration)
- 25s: cloud 3 peels (5s duration)
- 40s: cloud 2 peels (5s duration)
- 55s: cloud 1 peels (5s duration)
- 12s: surface appears (10s fade-in)

Use a stopwatch or in-game console (if present) to verify timings within ±0.5s.

- [ ] **Step 3: Test cancellation by triggering a re-transition**

Trigger an artificial re-transition mid-peel:
1. In `level_1_director.gd`, temporarily reduce `s3.transition_in_duration` and add a 4th section
2. OR: add a debug input in `level_1_background.gd` `_input()` that calls `transition_to(phase_deep_space.tres, 2.0)` on key press
3. Press the debug key during cloud descent

Expected: All in-flight peels stop immediately, deep space transition begins cleanly. No "ghost" alpha or scale animations continuing.

Remove the debug code after verifying.

---

## Files Changed Summary

| File | Action | Lines |
|---|---|---|
| `assault/scenes/levels/level_1_background.gd` | Modify | -45 (deleted methods), +20 (helper + inline calls) |

**Total:** 1 file, ~1 hour.

---

## Rollback Plan

The deleted methods (`_schedule_peel_timers`, `_run_peel`, `_run_surface_appear`) are the only logic loss. Restore them and revert the `transition_to()` block changes if the new approach causes timing issues.

---

## Success Criteria

- ✅ Cloud peel and surface-appear tweens are added to `_transition_tween`, not separate timers
- ✅ `_schedule_peel_timers`, `_run_peel`, `_run_surface_appear` are deleted
- ✅ Level 1 plays through to cloud descent and peels fire at correct times
- ✅ Calling `transition_to()` again during peels cleanly cancels them (no ghost animations)
