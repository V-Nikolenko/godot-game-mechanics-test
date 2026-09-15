# Progress

## Implementation (landed in commit `ed3dd29`, a prior cycle)

`assault/scenes/systems/level_director/level_director.gd`:
- Added private `_wait_tick` signal, `_cancelled: bool` flag.
- `_enter_tree()` resets `_cancelled = false` and connects `get_tree().process_frame` to
  `_on_process_frame()` (guarded by `is_connected`).
- `_exit_tree()` sets `_cancelled = true`, disconnects from `process_frame`, then emits
  `_wait_tick` once, synchronously, before deallocation.
- `_wait_for_child_exit_or_timeout()` and `_wait_seconds()` loop conditions gained `and not
  _cancelled`, body awaits `_wait_tick` instead of `get_tree().process_frame`.
- `_wait_enemies_cleared()` gained `if _cancelled: return` after both awaits, replacing the old
  `is_instance_valid(self)` checks.

`tests/integration/test_level_director_polling.gd`: added tests 4-6 —
`test_freeing_the_director_mid_wait_lets_the_coroutine_return`,
`test_freeing_the_director_mid_wait_seconds_lets_the_coroutine_return`,
`test_a_wait_that_already_ended_is_unaffected_by_a_later_free` — matching the plan's test plan
exactly, including the amplification-via-N-suspended-coroutines resolution the review flagged as
needing implementer judgment.

## This cycle's work

The prior cycle's implementation was solid and its own gate run (`reports/2026-09-08-1837-i3.md`)
was green, but it left three things undone that made the task look unfinished on resume:

1. `tests/README.md`'s "Two traps" section still stated as fact that "no amount of care inside
   `LevelDirector` can resume [the stranded coroutine] afterwards" — false after the fix. Corrected
   the section (see diff) to describe the cancel seam and point at tests 4-6.
2. `STATUS.md` still showed stage 4-6 unchecked.
3. The task was still `in_progress` in `BACKLOG.json`.

Re-ran both `bash /agent/verify.sh` and `scripts/check-test-leaks.sh` — both green, no leaks —
before closing.
