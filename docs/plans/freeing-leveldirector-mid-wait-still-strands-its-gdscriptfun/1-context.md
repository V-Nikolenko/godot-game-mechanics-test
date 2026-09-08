# Context

## Problem, precisely

`LevelDirector` (`assault/scenes/systems/level_director/level_director.gd`) has three coroutines
that suspend on `await get_tree().process_frame`:

- `_wait_for_child_exit_or_timeout(container, poll_seconds)` — polls until a container child exits
  or a fallback timeout elapses.
- `_wait_seconds(seconds)` — a frame-polled sleep.
- `_wait_enemies_cleared()` — the ENEMIES_CLEARED gate; calls the first helper in a loop and the
  second once before advancing.

All three already guard `if not is_instance_valid(self): return` after every `await`. That guard
stops an early return from leaving anything *behind* it dangling (the SceneTreeTimer bug this
task follows up on), but it cannot help with the failure this task is about: if `self` (the
`LevelDirector` node) is freed **while a coroutine is suspended inside the `await`**, the
`GDScriptFunctionState` backing that coroutine can never be resumed — nothing will ever call
`resume()` on it again, because the only thing that would have (the next `process_frame` tick,
via the engine's internal await-resume machinery bound to `self`) no longer has a live object to
resume. Freeing `self` while suspended, not returning while `self` is still valid, is the failure
mode. The `is_instance_valid` checks run *after* the coroutines already resumed — they never get
that chance in this failure mode.

Confirmed live in the test suite today: `tests/integration/test_station_assault_section.gd` test
`test_section_does_not_advance_while_an_enemy_lives` (line 87) has to manually drain
`_wait_enemies_cleared()` before `add_child_autofree(_director)` tears down — freeing the enemy and
awaiting 0.5s so the coroutine runs to completion — specifically because letting the director be
freed while still suspended leaks. Its own comment (lines 102-107) says so directly.

## Why `is_instance_valid` cannot fix this

Godot's `await <signal>` suspends the calling function by creating a `GDScriptFunctionState` and
connecting a one-shot callable to the signal that, when fired, calls `resume()` on that state.
`get_tree().process_frame` is a `SceneTree` signal, not a `LevelDirector` signal, so the tree does
not know or care whether the awaiting node's object is still alive when it next fires — Godot
connects/disconnects that per-await internally and will simply drop a connection whose target
object no longer exists, silently, without ever calling `resume()`. The suspended function state is
now unreachable and unresumable: leaked forever, along with the `GDScript` resource it keeps open
(this is the exact `GDScriptFunctionState` / `GDScript` / `Resource still in use` triple named in
the task body).

Because the object is gone, there is no code that runs "after" this point to check anything — the
`is_instance_valid(self)` line was never reached and never will be. The only way to avoid the leak
is to make sure the coroutine gets a chance to run **before** the object is actually deallocated,
which for a Godot `Node` means during `_exit_tree()` — the object is still fully valid at that
point; only after `_exit_tree()` returns is the memory released (immediately for `free()`, at end
of frame for `queue_free()`).

## Design direction, matching the task body

Give the director a director-owned "tick" signal that every wait awaits *instead of*
`get_tree().process_frame`, plus a `_cancelled` flag:

- `_enter_tree()` resets `_cancelled = false` and connects to `get_tree().process_frame` to
  re-emit the tick each frame (mirrors `base_enemy.gd`'s existing use of `_enter_tree()` for
  per-instance setup that must survive re-parenting).
- `_exit_tree()` sets `_cancelled = true` **then** emits the tick signal once, synchronously. Every
  coroutine suspended on `await _wait_tick` resumes immediately, *while `self` is still a valid
  object* (still inside `_exit_tree()`), observes `_cancelled` and returns, releasing its
  `GDScriptFunctionState`.
- Every loop condition and post-await check switches from `is_instance_valid(self)` to
  `_cancelled` — checking `is_instance_valid(self)` from inside the resumed frame would still read
  `true` (the object is not deallocated yet) and let the loop re-await a tick that will never come
  again, trading one stranding point for another one line later.

## Files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/systems/level_director/level_director.gd` | The three coroutines and `_advance()`/`start()` sequencing | The only file that needs to change |
| `tests/integration/test_level_director_polling.gd` | Regression test for the SceneTreeTimer leak this task follows up on | Pattern to follow for the new regression test (uses `Performance.get_monitor(Performance.OBJECT_COUNT)`) |
| `tests/integration/test_station_assault_section.gd` | Test 5 (`test_section_does_not_advance_while_an_enemy_lives`, line 87) manually drains the director before teardown specifically to avoid this leak | After the fix, that drain should no longer be *necessary* — a good manual sanity check, though the plan does not require deleting the drain (removing safety padding from an existing green test is optional, not required) |
| `scripts/check-test-leaks.sh` | Runs the GUT suite and fails if Godot reports a leak at exit (`ObjectDB instances leaked`, `resources still in use`, `Resource still in use`) | The actual verification tool for this task — a leak here is otherwise invisible to `/agent/verify.sh`'s FATAL regex |

## Conventions that constrain this

- Signal arity: `tests/integration/test_signal_emit_arity.gd` sweeps every `name.emit(...)` against
  its `signal` declaration in the same file. The new tick signal must be declared and emitted with
  the same (zero) arity.
- `_enter_tree()` reset pattern already exists in this codebase for exactly this
  reset-on-reparent reason: `base_enemy.gd:44-45` calls `ShipConfig.privatise(self)` from
  `_enter_tree()` specifically because it "must run before any CHILD's `_ready()`" and survive
  re-parenting. No existing file combines `_enter_tree()`/`_exit_tree()` for a cancel seam — this
  is new, not a pattern to copy verbatim.
- No existing signal in the codebase is named with a leading underscore (checked via grep). Since
  this signal is purely a private implementation seam never referenced outside this script, that
  naming still reads clearly and matches this file's existing convention of leading-underscore
  private members (`_sections`, `_current_index`, `_wait_for_child_exit_or_timeout`, etc).
- `tests/README.md`'s `LevelDirector` coroutine-leak trap section should be read before writing the
  new test — it documents the `user://` sandbox and existing traps this suite already knows about.
