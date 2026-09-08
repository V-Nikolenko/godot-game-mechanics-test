# LevelDirector cancel seam for suspended waits

## Problem

Today, freeing a `LevelDirector` while `_wait_for_child_exit_or_timeout()`, `_wait_seconds()`, or
`_wait_enemies_cleared()` is suspended on `await get_tree().process_frame` strands the coroutine's
`GDScriptFunctionState` permanently — Godot has no way to resume a function bound to a deallocated
object. This is invisible to the player (nothing gameplay-visible changes) but costs three leaked
objects (`GDScriptFunctionState` / `GDScript` / the `Resource still in use` it holds open) per
level teardown where a wait is in flight, and forces every test that ends mid-wait to manually
drain the coroutine first — see `test_station_assault_section.gd`'s
`test_section_does_not_advance_while_an_enemy_lives` (lines 87-109), which frees its live enemy and
sleeps 0.5s purely to let `_wait_enemies_cleared()` run to completion before `add_child_autofree`
tears the director down.

`is_instance_valid(self)` checks after each `await` cannot fix this: they only run once the
coroutine actually resumes, and a coroutine stranded by object deallocation never resumes at all.

## Design

Add a director-owned cancel seam:

1. A new zero-argument signal `_wait_tick`, fed once per frame from `get_tree().process_frame`
   while the director is inside the tree.
2. A new `_cancelled: bool` flag.
3. `_enter_tree()`: reset `_cancelled = false`, connect `get_tree().process_frame` to a new
   `_on_process_frame()` that just does `_wait_tick.emit()` (guarded with `is_connected` so a
   re-entry doesn't double-connect).
4. `_exit_tree()`: set `_cancelled = true`, disconnect from `get_tree().process_frame` if
   connected, then `_wait_tick.emit()`. This emission happens synchronously, before the node is
   deallocated, so every coroutine suspended on `await _wait_tick` resumes **right there**, sees
   `_cancelled == true`, and returns — releasing its function state while `self` is still a valid
   object.
5. Every `await get_tree().process_frame` inside the three wait helpers becomes `await _wait_tick`.
6. Every `if not is_instance_valid(self): return` guard after those awaits becomes
   `if _cancelled: return` (or is folded into the loop condition — see build sequence). The
   `is_instance_valid(self)` check is wrong for this purpose even as a belt-and-braces addition: at
   the point the coroutine resumes inside `_exit_tree()`, `self` reads as *still valid* (we are
   mid-call, not yet deallocated), so an `is_instance_valid` check would pass and the loop would
   `await _wait_tick` again — a tick that will never come, since nothing emits it again after
   `_exit_tree()` returns. That trades today's leak for the identical leak one line later. Only
   `_cancelled`, set *before* the resuming emit, tells the coroutine correctly that this is a
   teardown, not an ordinary frame.

### Why not `await get_tree().process_frame` with a race against a cancel signal

GDScript's `await` takes one signal; there is no built-in "whichever fires first" combinator
short of manually connecting both to the same resume path, which is extra machinery for no benefit
over simply routing the normal per-frame case through the same signal the cancel path uses.
Funneling both the steady-state tick *and* the cancellation through one signal is simpler and is
exactly what the task description asks for.

### Why not just also disconnect in `_wait_for_child_exit_or_timeout`'s cleanup on cancel

That cleanup — disconnecting `on_exit` from `container.child_exiting_tree` — is unrelated to the
`self`-lifetime problem (`container` is `wave_manager.enemy_container`, a different node that is
not being freed) and already runs correctly as long as the function actually reaches that line.
The fix changes how it gets there (loop condition includes `_cancelled` alongside the deadline
check) but not what the cleanup does.

## Build sequence

1. **Add the seam** to `level_director.gd`: `_wait_tick` signal, `_cancelled` flag,
   `_enter_tree()`, `_exit_tree()`, `_on_process_frame()`.
2. **Rewrite the three wait helpers** to await `_wait_tick` and check `_cancelled` instead of
   `is_instance_valid(self)`:
   - `_wait_for_child_exit_or_timeout()`: loop condition becomes
     `while not exited[0] and Time.get_ticks_msec() < deadline_ms and not _cancelled:` with body
     `await _wait_tick` (no post-await check needed — the loop condition covers it on the next
     iteration, and the cleanup below the loop is unconditional and safe to run even when
     cancelled, since it only touches `container`, which is not being freed).
   - `_wait_seconds()`: loop condition becomes
     `while Time.get_ticks_msec() < deadline_ms and not _cancelled:` with body `await _wait_tick`.
   - `_wait_enemies_cleared()`: add `if _cancelled: return` immediately after
     `await _wait_for_child_exit_or_timeout(...)` and after `await _wait_seconds(0.2)`, replacing
     the existing `is_instance_valid(self)` checks in both spots. The outer `while
     container.get_child_count() > 0:` loop needs no additional check of its own — cancellation
     is only observable after an `await` returns, and both awaits inside that loop are already
     covered.
3. **Update `tests/integration/test_level_director_polling.gd`** — no changes needed to existing
   tests (they don't free the director mid-wait), but add a new test alongside test 3
   (`test_early_returning_polls_leave_nothing_ticking`) for the cancellation path: start a wait via
   `.call(...)`, free the director itself (not the container child) while it is suspended, and
   assert no `GDScriptFunctionState`/`GDScript` leak via `Performance.get_monitor(Performance.OBJECT_COUNT)`,
   the same technique test 3 already uses.
4. **Manual check (not required to change)**: after the fix, `test_station_assault_section.gd`'s
   `test_section_does_not_advance_while_an_enemy_lives` drain (lines 102-109) should no longer be
   load-bearing — freeing the director mid-wait should no longer leak. Leave the drain in place;
   removing safety padding from an already-green test is out of scope and the drain does no harm.
5. **Update `tests/README.md`** — the "Two traps" section (lines 384-404) states as fact that "no
   amount of care inside `LevelDirector` can resume it afterwards" about the stranded
   `GDScriptFunctionState`. That is no longer true after this change and needs a correction: the
   cancel seam lets the coroutine resume and return cleanly during `_exit_tree()`, so a test no
   longer *needs* to manually drain the wait before tearing the director down (though doing so
   remains harmless).

## Test plan

New tests in `tests/integration/test_level_director_polling.gd`:

- **`test_freeing_the_director_mid_wait_does_not_leak`** — the direct regression test named by
  this task. Start `_wait_for_child_exit_or_timeout(_container, 30.0)` on `_director` via
  `.call(...)` (fire-and-forget, matching test 3's style), let one frame pass so it suspends on
  `await _wait_tick`, then `_director.free()` (not `queue_free()` — the assertion needs the leak
  check to run in the same frame, and `_exit_tree()` fires synchronously on `free()`). Assert
  `Performance.get_monitor(Performance.OBJECT_COUNT)` shows no net growth from before the sequence
  to a couple of frames after, using the same "before/after with a small allowed drift" pattern as
  test 3. Amplify with a small `N` (e.g. 20) the same way test 3 amplifies with 100, since one
  leaked function state is small against normal per-frame object churn.
- **`test_wait_seconds_does_not_leak_when_the_director_is_freed_mid_wait`** — same shape, but
  against `_wait_seconds()`, to cover the second helper independently (it has its own loop and its
  own cancellation check).
- **Boundary case**: a wait that is **not** suspended when the director is freed (i.e. the
  container child already exited, or the timeout already elapsed) must not be affected — reuse
  `test_poll_ends_on_child_exit_not_at_the_fallback_deadline`'s style to confirm the normal
  completion path still returns promptly and doesn't regress from adding `_cancelled` to the loop
  condition.

## Risks

- **`_wait_tick` firing every frame for the lifetime of every `LevelDirector`**, including ones
  with no wait in flight, is a new per-frame connection where there was none before (previously
  `get_tree().process_frame` was awaited directly with no standing connection between awaits). This
  is one extra signal emission per director per frame — negligible (one `LevelDirector` exists per
  level) but worth naming as a real, if small, behavioural change from "no connection unless a
  wait is active" to "always connected while in the tree."
- **`free()` vs `queue_free()` in the new test**: `_exit_tree()` runs synchronously for both, but
  `free()` deallocates immediately after, which is what makes the leak observable in the same test
  run without waiting an extra idle frame. Must use `free()`, not `queue_free()`, in the new test's
  cancellation trigger, or the object-count assertion will race the deferred deallocation.
- **Re-entry (`_enter_tree()` called again after `_exit_tree()`)**: only relevant if a
  `LevelDirector` node is ever removed from the tree and re-added without being freed — not
  observed anywhere in this codebase today, but the `is_connected` guard in `_enter_tree()` and the
  flag reset make this safe regardless.

## Out of scope

- Any other file's `await` usage (station_death_sequence.gd, station_gunnery.gd, etc.) — none of
  them share this exact pattern today, and the task is scoped to `LevelDirector`.
- Removing the manual drain in `test_station_assault_section.gd` — leaving it is harmless and not
  required by this task.
