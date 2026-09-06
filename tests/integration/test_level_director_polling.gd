## Tests for `LevelDirector._wait_for_child_exit_or_timeout()`, the poll that gates every
## ENEMIES_CLEARED section.
##
## NOT characterization — these assert intent. Both helpers used to be built on
## `SceneTree.create_timer()`, and `_wait_for_child_exit_or_timeout()` in particular abandoned its
## timer on every early return: the child exits after ~1 frame, the helper returns, and a
## `SceneTreeTimer` keeps ticking for the rest of the poll window with nobody awaiting it. Anything
## that ended the tree inside that window strands it, and Godot only reports that at *process exit*
## as `ObjectDB instances leaked` / `resources still in use` — neither of which matches
## `/agent/verify.sh`'s fatal-error regex. So the gate stayed green while leaking.
##
## Test 3 is the one that would have caught it. It cannot observe a single stranded timer directly
## (there is no SceneTree API for the pending-timer list), so it amplifies: 100 early-returning
## polls with a 30 s fallback window. Measured on the pre-fix code that read as +101 live objects;
## post-fix it reads +1, against a per-frame drift of about +1. Do not lower `N` — the margin is
## the whole point.
extends GutTest

## Enough polls that a one-object-per-call leak clears the engine's own object-count drift by an
## order of magnitude.
const N := 100

var _container: Node2D
var _director: LevelDirector


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)

	_director = LevelDirector.new()
	add_child_autofree(_director)


# ── 1-2. The poll itself ──────────────────────────────────────────────────────

## A child leaving must end the wait on the next frame, not at the end of the fallback window.
## `_wait_enemies_cleared()` re-checks its own deadline only between polls, so a helper that
## ignored `child_exiting_tree` would round every section's timeout up to the poll interval.
func test_poll_ends_on_child_exit_not_at_the_fallback_deadline() -> void:
	var child := Node2D.new()
	_container.add_child(child)

	var start_ms := Time.get_ticks_msec()
	child.queue_free()
	await _director._wait_for_child_exit_or_timeout(_container, 30.0)
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_lt(elapsed_ms, 1000,
		"child_exiting_tree must end the wait immediately, not after the 30 s fallback — took %d ms"
			% elapsed_ms)


## Boundary: nothing ever exits, so the fallback deadline is the only thing that can end the wait.
## The window is deliberately short and the upper bound generous — the assertion that matters is
## that the helper returns *at all* and not before its deadline.
func test_poll_returns_after_the_fallback_window_when_nothing_exits() -> void:
	var child := Node2D.new()
	_container.add_child(child)

	var start_ms := Time.get_ticks_msec()
	await _director._wait_for_child_exit_or_timeout(_container, 0.4)
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_between(elapsed_ms, 350, 2000,
		"an unfired poll must burn its whole 0.4 s window and then return — took %d ms"
			% elapsed_ms)
	assert_eq(_container.get_child_count(), 1, "the helper must not touch the container")


# ── 3. The leak ───────────────────────────────────────────────────────────────

## The regression test for the abandoned `SceneTreeTimer`. Each poll returns on the frame after it
## starts, so a fallback window of 30 s means anything the helper left behind is still live when
## the count is read.
func test_early_returning_polls_leave_nothing_ticking() -> void:
	await get_tree().process_frame
	var before := Performance.get_monitor(Performance.OBJECT_COUNT)

	for _i in N:
		var child := Node2D.new()
		_container.add_child(child)
		## Fire and forget: the coroutine runs to its first await, then resumes and returns on the
		## next frame because the child has already gone.
		_director.call("_wait_for_child_exit_or_timeout", _container, 30.0)
		child.free()

	await get_tree().process_frame
	await get_tree().process_frame
	var leaked := Performance.get_monitor(Performance.OBJECT_COUNT) - before

	assert_lt(leaked, 20.0,
		"%d polls must not leave ~%d objects alive; %d survived (pre-fix this was %d)"
			% [N, N, leaked, N + 1])
	assert_eq(_container.get_child_count(), 0, "every probe child should be gone")

