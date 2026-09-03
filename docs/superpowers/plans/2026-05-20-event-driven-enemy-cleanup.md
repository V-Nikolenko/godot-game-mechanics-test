# Event-Driven Enemy Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 150ms polling loop in `LevelDirector._wait_enemies_cleared()` with a signal-driven wait that resumes immediately when the enemy container empties.

**Architecture:** Use `Node.child_exiting_tree` on `wave_manager.enemy_container`. Await the signal in a loop, re-checking child count on each emission. Keeps a fallback wall-clock timeout for safety.

**Tech Stack:** Godot 4.3 GDScript, `Signal.await`, `Time.get_ticks_msec()`.

**Constraints:**
- No git commits.
- Must handle pending `_spawn_with_delay()` coroutines in WaveManager (waves complete signal fires when waves are *triggered*, not when all delayed spawns have actually instantiated).
- Must keep a fallback timeout (current code caps at 10s — keep this behavior).

---

## Architecture Overview

### Current State
```gdscript
func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var waited := 0.0
	while container.get_child_count() > 0 and waited < 10.0:
		await get_tree().create_timer(0.15).timeout    # POLL every 150ms
		if not is_instance_valid(self):
			return
		waited += 0.15
	# ...
	_advance()
```

**Problems:**
- Polls every 150ms even when nothing changes
- 150ms latency between last enemy dying and section advancing
- `waited += 0.15` accumulates drift relative to real elapsed time

### Target State
```gdscript
func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var deadline_ms: int = Time.get_ticks_msec() + 10_000   # 10s wall clock

	while container.get_child_count() > 0:
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning("[LevelDirector] enemy cleanup timeout — forcing advance")
			break
		# Wait for ANY child to leave OR a short fallback poll
		await _wait_for_child_exit_or_timeout(container, 1.0)
		if not is_instance_valid(self):
			return
	# ...
	_advance()
```

The fallback poll is now 1 second (not 150ms) — used only to occasionally re-check in case a spawn-delay coroutine drops a child mid-wait that we'd otherwise miss seeing.

---

## File Structure

- **Modify:** `assault/scenes/systems/level_director/level_director.gd`
  - Rewrite `_wait_enemies_cleared()` to be signal-driven
  - Add helper `_wait_for_child_exit_or_timeout()`

---

## Edge Case: Pending Spawn Delays

`WaveManager._spawn_with_delay()` is a coroutine that awaits `get_tree().create_timer(delay).timeout` before spawning. When `waves_complete` fires, these coroutines can still be in flight — meaning new children may appear in `enemy_container` AFTER the signal.

The polling loop catches this incidentally (it re-checks count repeatedly). The signal-driven version must also handle it.

**Solution:** Loop on `container.get_child_count() > 0`, awaiting either a `child_exiting_tree` signal OR a 1-second fallback (which gives time for any pending spawn-delay to complete and add a child).

---

## Task 1: Add the Signal/Timeout Race Helper

**Files:**
- Modify: `assault/scenes/systems/level_director/level_director.gd`

- [ ] **Step 1: Add the helper near the bottom of the file**

Add this method just before `_wait_enemies_cleared()`:

```gdscript
## Awaits either [container]'s next child_exiting_tree signal OR a fallback
## timeout of [poll_seconds] — whichever happens first. Used by
## _wait_enemies_cleared so the wait wakes immediately on enemy removal but
## still polls occasionally to catch enemies that may spawn via delayed
## coroutines after waves_complete has fired.
func _wait_for_child_exit_or_timeout(container: Node, poll_seconds: float) -> void:
	var timer := get_tree().create_timer(poll_seconds)
	# Race: first to fire wins. Godot 4 has no built-in race primitive, so we
	# await both signals via a Callable wrapper that flags completion.
	var done := [false]
	var on_exit := func(_n: Node) -> void:
		done[0] = true
	var on_timeout := func() -> void:
		done[0] = true

	# CONNECT_ONE_SHOT so connections auto-disconnect when one fires.
	container.child_exiting_tree.connect(on_exit, CONNECT_ONE_SHOT)
	timer.timeout.connect(on_timeout, CONNECT_ONE_SHOT)

	# Yield until either fires. Use process_frame for cheap waits.
	while not done[0]:
		await get_tree().process_frame
		if not is_instance_valid(self):
			return

	# Disconnect the loser to prevent stale signal fires later.
	if container.child_exiting_tree.is_connected(on_exit):
		container.child_exiting_tree.disconnect(on_exit)
	# (timer is one-shot SceneTreeTimer; it cannot fire twice — no cleanup needed.)
```

**Why the `done` array wrapper?** Lambdas in GDScript 4 capture by reference for objects but by value for primitives. To mutate a flag from inside both lambdas, wrap it in a single-element Array (or Dictionary). This is the standard Godot pattern.

---

## Task 2: Rewrite `_wait_enemies_cleared()`

**Files:**
- Modify: `assault/scenes/systems/level_director/level_director.gd`

- [ ] **Step 1: Replace the polling implementation**

Find:

```gdscript
func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var waited := 0.0
	while container.get_child_count() > 0 and waited < 10.0:
		await get_tree().create_timer(0.15).timeout
		if not is_instance_valid(self):
			return
		waited += 0.15
	print("[LevelDirector] Enemies cleared (%.1f s) — %d remaining" % [
		waited, container.get_child_count()
	])
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	_advance()
```

Replace with:

```gdscript
func _wait_enemies_cleared() -> void:
	var container: Node = wave_manager.enemy_container
	var start_ms: int = Time.get_ticks_msec()
	var deadline_ms: int = start_ms + 10_000   # 10-second safety cap

	while container.get_child_count() > 0:
		if Time.get_ticks_msec() >= deadline_ms:
			push_warning("[LevelDirector] enemy cleanup timed out with %d remaining" % container.get_child_count())
			break
		await _wait_for_child_exit_or_timeout(container, 1.0)
		if not is_instance_valid(self):
			return

	var elapsed_ms: int = Time.get_ticks_msec() - start_ms
	print("[LevelDirector] Enemies cleared (%.2f s) — %d remaining" % [
		elapsed_ms / 1000.0, container.get_child_count()
	])

	# Brief settle delay before advancing — preserves the original 0.2s pause
	# that allowed death-effects to play out before the next section starts.
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	_advance()
```

**Key changes:**
- Wall-clock timing via `Time.get_ticks_msec()` — accurate independent of frame rate or signal latency
- 1-second fallback poll (was 150ms) — coarser because we now wake on the signal too
- Push warning instead of silent timeout

---

## Task 3: Verify Behavior

**Files:** None modified.

- [ ] **Step 1: Play through to the cloud descent section**

Boot Level 1, play through. The cloud descent section has `EndCondition.ENEMIES_CLEARED`, so the wait fires when the gunship + fighters at 50s are defeated.

- [ ] **Step 2: Verify section advance is responsive**

Kill the last enemy. The section should advance within ~1 frame (not 150ms). You should see the `[LevelDirector] Enemies cleared (X.XX s) — 0 remaining` log immediately after the last death.

- [ ] **Step 3: Verify the timeout still works**

To test the safety cap:
1. Temporarily reduce the timeout from 10_000 to 2_000 ms in `_wait_enemies_cleared()`
2. Don't kill the last enemy — let the timer expire
3. Verify the `[LevelDirector] enemy cleanup timed out` warning appears
4. Verify the section still advances (no soft-lock)

Restore timeout to 10_000 ms after testing.

- [ ] **Step 4: Verify the spawn-delay race is handled**

The cloud descent gunship wave at 50s has spawns with `.delay(0.8)`. If `waves_complete` fires before these delays resolve, the new code must still wait for them.

To verify: add a debug `print()` in `WaveManager._spawn_with_delay()` showing when each delayed spawn lands. Confirm the `[LevelDirector] Enemies cleared` log appears AFTER the last delayed spawn has both landed and died.

Remove the debug print after verifying.

---

## Files Changed Summary

| File | Action | Lines |
|---|---|---|
| `assault/scenes/systems/level_director/level_director.gd` | Modify | -10 (old poll), +30 (helper + new impl) |

**Total:** 1 file, ~30-45 minutes.

---

## Rollback Plan

The old polling implementation is fully self-contained. Restore the original `_wait_enemies_cleared()` and delete the helper.

---

## Known Trade-offs

- **Lambda-with-Array-wrapper pattern is awkward.** Alternative: subclass a tiny helper Object with a flag property. Not worth it for one usage site.
- **1-second fallback poll is conservative.** Could go lower (e.g. 0.5s) but the signal handles the common case — fallback only catches delayed-spawn cases which are sub-second already.
- **No handling for the container itself being freed mid-wait.** If `wave_manager.enemy_container` is queued for free while we're awaiting, signal connections become invalid. Mitigation: the existing `is_instance_valid(self)` check after each await catches this for the director, but not for the container specifically. Acceptable risk — this would only happen on scene change, which already tears everything down.

---

## Success Criteria

- ✅ `_wait_enemies_cleared()` no longer polls every 150ms
- ✅ Section advance fires within one frame of last enemy death
- ✅ 10-second safety timeout still works
- ✅ Pending spawn-delay coroutines that land enemies after `waves_complete` are still waited on
- ✅ Wall-clock elapsed time is accurate (no drift from `waited += 0.15`)
