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
##
## Tests 4-6 cover the follow-up leak: fixing the abandoned timer did not fix freeing the
## DIRECTOR itself while one of its own coroutines is suspended. That strands the coroutine's
## `GDScriptFunctionState` (and the `GDScript` resource it holds open) permanently — once the
## object backing the coroutine is deallocated nothing can ever resume it, so no in-coroutine
## guard can help. The fix is a director-owned cancel seam (`_wait_tick` + `_cancelled`,
## `level_director.gd`): `_exit_tree()` sets `_cancelled` and re-emits `_wait_tick` once,
## synchronously, while the object is still alive, so every suspended wait gets to run its
## cleanup and return before deallocation.
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


# ── 4-6. Freeing the director itself mid-wait ──────────────────────────────────
#
# The follow-up leak: nothing above frees the DIRECTOR while it is suspended. Doing that strands
# the coroutine's GDScriptFunctionState forever — once the object backing it is deallocated,
# nothing can ever call resume() on it again, so an early-return guard inside the coroutine never
# gets the chance to run. Confirmed live in test_station_assault_section.gd, whose
# test_section_does_not_advance_while_an_enemy_lives has to manually drain
# _wait_enemies_cleared() before its own director teardown for exactly this reason.
#
# Performance.OBJECT_COUNT, used above for the timer leak, does NOT detect this one: a suspended
# GDScriptFunctionState that can never resume does not grow the live object count once it exists,
# so a before/after delta reads 0 whether the coroutine is stranded forever or cleaned up
# immediately (confirmed empirically against the pre-fix code). The leak is only externally visible
# at process exit, as `ObjectDB instances leaked` / `resources still in use` — which is what
# scripts/check-test-leaks.sh greps for. So these tests instead prove the thing that actually
# matters: that the coroutine resumes and RETURNS once the director is freed, by observing a flag
# only the coroutine's own continuation can set.

## Regression test for the cancel seam: _exit_tree() must resume a suspended
## _wait_for_child_exit_or_timeout() call synchronously (via _wait_tick) and let it return, instead
## of stranding it forever the moment the director is deallocated.
func test_freeing_the_director_mid_wait_lets_the_coroutine_return() -> void:
	var finished := [false]
	var run := func() -> void:
		await _director._wait_for_child_exit_or_timeout(_container, 30.0)
		finished[0] = true
	run.call()
	await get_tree().process_frame
	assert_false(finished[0], "sanity: must still be suspended before the director is freed")

	## free(), not queue_free(): _exit_tree() must run synchronously within this same call, not
	## after a deferred deallocation on some later idle frame.
	_director.free()
	await get_tree().process_frame

	assert_true(finished[0],
		"freeing the director mid-wait must let _wait_for_child_exit_or_timeout() return, not strand it")
	assert_eq(_container.get_signal_connection_list("child_exiting_tree").size(), 0,
		"the cancelled wait must still disconnect its child_exiting_tree listener on the way out")


## Same regression, against the other wait helper — it has its own loop and its own cancellation
## check, so a fix to one does not guarantee the other.
func test_freeing_the_director_mid_wait_seconds_lets_the_coroutine_return() -> void:
	var finished := [false]
	var run := func() -> void:
		await _director._wait_seconds(30.0)
		finished[0] = true
	run.call()
	await get_tree().process_frame
	assert_false(finished[0], "sanity: must still be suspended before the director is freed")

	_director.free()
	await get_tree().process_frame

	assert_true(finished[0],
		"freeing the director mid-wait must let _wait_seconds() return, not strand it")


## Boundary: a wait that already ended normally, before the director is ever freed, must be
## unaffected by the new `not _cancelled` loop term — it must still end on child_exiting_tree and
## not regress into burning the fallback window.
func test_a_wait_that_already_ended_is_unaffected_by_a_later_free() -> void:
	var child := Node2D.new()
	_container.add_child(child)

	var start_ms := Time.get_ticks_msec()
	child.queue_free()
	await _director._wait_for_child_exit_or_timeout(_container, 30.0)
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_lt(elapsed_ms, 1000,
		"child_exiting_tree must still end the wait immediately after the cancel seam was added — took %d ms"
			% elapsed_ms)

	## Let the frame that just resumed the wait above finish unwinding before freeing the director.
	## The resume happened inside _wait_tick's own emit() (level_director.gd:52), so calling
	## free() before that call returns would hit Godot's "Attempted to free a locked object" —
	## true of any object mid-emission, not something this fix introduces, but easy to trip over
	## in a test that awaits a director call and then immediately frees the director.
	await get_tree().process_frame
	_director.free()
	await get_tree().process_frame

