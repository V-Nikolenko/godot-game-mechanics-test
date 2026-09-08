VERDICT: APPROVED

## What I checked

Read `1-context.md`, `3-plan.md`, the current
`assault/scenes/systems/level_director/level_director.gd`,
`tests/integration/test_level_director_polling.gd`,
`tests/integration/test_station_assault_section.gd` (lines 85-165, esp. the drain comment at
100-109), `tests/README.md` (lines 370-405), `tests/integration/test_signal_emit_arity.gd`,
`tests/integration/test_level_1_sequence.gd` (the other file that touches
`_wait_enemies_cleared()`), `assault/scenes/enemies/base_enemy.gd:32-45` (the `_enter_tree()`
reset pattern the plan cites), `addons/gut/autofree.gd` (`free_all()`), and the task body in
`BACKLOG.json` (`freeing-leveldirector-mid-wait-still-strands-its-gdscriptfun`).

## Does the fix actually work?

Yes. `_exit_tree()` runs synchronously and while `self` is still a fully valid, non-deallocated
object, for both `free()` (immediately, before the object is actually freed) and `queue_free()`
(deferred to end of frame, but still synchronous within that deferred call, before deallocation).
Godot's `await <signal>` resume is synchronous inside the `emit()` call that fires it, and this
chains correctly through nested `await`s on function calls (`_wait_enemies_cleared()` awaiting
`_wait_for_child_exit_or_timeout()` awaiting `_wait_tick`): when `_exit_tree()` emits `_wait_tick`
once, every suspended coroutine — however deeply nested — resumes and runs to completion or its
next `await` entirely within that one synchronous `emit()` call, before `_exit_tree()` returns and
before the object is deallocated. Checking `_cancelled` (set before the resuming emit) rather than
`is_instance_valid(self)` is correct: `self` reads valid throughout `_exit_tree()`, so the old
guard would have re-awaited a tick that never comes again — the plan's own stated reasoning for
this substitution is right.

Traced each of the three call sites against the plan's described changes:
- `_wait_for_child_exit_or_timeout` (level_director.gd:94-108): loop condition gains `and not
  _cancelled`; the disconnect cleanup after the loop only touches `container` (not `self`), so it
  is correctly safe to run unconditionally, cancelled or not.
- `_wait_seconds` (level_director.gd:112-117): same shape, no cleanup to worry about.
- `_wait_enemies_cleared` (level_director.gd:120-162): the plan's `if _cancelled: return` after
  each of the two awaits is placed correctly to prevent `_advance()` (which touches
  `background`, `wave_manager`, `_sections`) from ever running during a teardown resume.

No contradiction with the `_enter_tree()`-for-reset convention `base_enemy.gd:44-45` already
establishes, and no existing signal in the project is prefixed with `_` (`grep -rn "^\s*signal _"`
project-wide, addons excluded, returns nothing) — the plan's private-signal naming call is
consistent with that and doesn't collide with any convention. `test_signal_emit_arity.gd`'s regexes
(`^\s*signal\s+(\w+)...` and `(^|[^.\w])(\w+)\.emit\s*\(`) both match a leading-underscore
identifier fine, so `signal _wait_tick` / `_wait_tick.emit()` (both zero-arity) will be picked up
and pass, not skipped.

Re-entrancy (node exits and re-enters tree without being freed): `_enter_tree()` resets
`_cancelled = false` and reconnects (guarded by `is_connected`), `_exit_tree()` disconnects. Any
coroutine suspended at the point of the first `_exit_tree()` already got flushed by that call, so
there's no stale state to worry about on re-entry. Not observed anywhere in the codebase today, as
the plan notes, but handled correctly regardless.

`WaveManager.waves_complete` connections in `_advance()`/`start()`: unaffected. The
`CONNECT_ONE_SHOT` connection to `_wait_enemies_cleared` has already fired and auto-disconnected by
the time that coroutine is running/suspended, so there's nothing left on `wave_manager` for the fix
to interact with.

Double-free safety for the new tests: `add_child_autofree()` registers the node with GUT's
`AutoFree`, whose `free_all()` (`addons/gut/autofree.gd:65-71`) guards every entry with
`is_instance_valid()` before calling `.free()`. A test that manually frees `_director` mid-test
(as the new tests must) will not double-free at teardown. This same pattern (`child.free()` inside
a test body, with the node also under `add_child_autofree`) is already used in
`test_level_director_polling.gd:86`.

## Findings

1. **(minor, non-blocking) Test-amplification mechanics need the implementer's judgment, and the
   plan doesn't spell out the one workable shape.** `3-plan.md` lines 101-109 say to start the wait
   "on `_director`," free `_director` once, and "amplify with a small `N` (e.g. 20) the same way
   test 3 amplifies with 100." But test 3's amplification loop (`test_level_director_polling.gd:80-86`)
   repeats *calls* on one long-lived director; here the triggering action is freeing the director
   itself, which is a one-time operation — you cannot call `_director.free()` twenty times. The
   only shape that actually amplifies under this constraint is: call `.call("_wait_for_child_exit_or_timeout", ...)`
   on the *same* `_director` N times (N independent suspended coroutines, all awaiting the same
   `_wait_tick`), then free `_director` exactly once so the single cancelling emit has to flush all
   N at once. That's a sound design and consistent with the rest of the plan's reasoning, but the
   plan doesn't say so explicitly, and a literal reading of "start the wait... then free... amplify
   with N" could lead an implementer toward something that doesn't type-check (freeing an
   already-freed node). Worth a one-line clarification, but low risk in practice — this is direct
   implementation with failing-test-first verification, so a broken attempt would surface
   immediately during `verify.sh` rather than ship silently.

2. **(non-blocking observation)** The fix also incidentally closes a smaller pre-existing gap: in
   today's code, if `self` is freed while `_wait_for_child_exit_or_timeout` is suspended, the
   `on_exit` closure connected to `container.child_exiting_tree` (level_director.gd:98) is never
   disconnected either — it has no reference to `self`, so it isn't itself unresumable, but it sits
   connected on `container` (a node that isn't being freed) until `container` happens to emit
   `child_exiting_tree` once or is freed itself. The plan's unconditional cleanup-after-the-loop
   fixes this too, as a side effect. Not a defect in the plan — just worth knowing it's a strict
   improvement over today, not only a wash.

## Scope

Touches only `level_director.gd`, `test_level_director_polling.gd`, and the `tests/README.md`
correction — matches the task's stated scope. The plan correctly declines to touch
`station_death_sequence.gd` / `station_gunnery.gd` (no shared pattern today) and correctly leaves
the now-unnecessary drain in `test_station_assault_section.gd` in place rather than churning an
already-green test.
