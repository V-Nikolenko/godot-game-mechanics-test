# STATUS — Lore-log pickup

**Track:** Escalated (medium complexity, `prepDir: null`)
**Task:** flying-into-a-log-record-in-open-space-picks-it-up-and-tells (epic: log-records-discoverable-lore-and-info-logs-across-all-three)
**Item:** Flying into a log record in open space picks it up and tells me what I found
**Started:** 2026-09-09

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md`
- [ ] 3. Reviewed and APPROVED → `4-review.md` — **BLOCKED, see below**
- [ ] 4. Implemented → `5-progress.md`
- [ ] 5. Gate green
- [ ] 6. Docs updated, task ticked

## Blocked — two review rounds, neither approved

Round 1 (`4-review.md`): `VERDICT: CHANGES_REQUESTED` — test case 4 (driving the real
`_on_body_entered()` end-to-end) starts a real `DialogPlayer.play()` coroutine that awaits
`_box.line_finished`, which nothing in the test resolves — a permanently-suspended-coroutine
leak (the same class the gate's `test_level_director_polling.gd` and `check-test-leaks.sh` exist
to catch), invisible to the gate's `FATAL` regex.

Revised `3-plan.md` case 4 to call `DialogPlayer.skip_dialog()` right after `_on_body_entered()`
returns, asserting `is_active == false`.

Round 2 (`4-review.md`): `VERDICT: CHANGES_REQUESTED` again — the fix is based on a false timing
premise. By the time `_on_body_entered()` returns, `play()`'s coroutine is parked on an *earlier*
await (`present_line()`'s `await _fade_in_tween.finished`, ~0.22s fade-in), not on
`await _box.line_finished` yet. Calling `skip_dialog()` there kills the fade-in tween, which per
`dialog_box.gd`'s own documented Godot-4 behavior ("`kill()` does NOT emit `finished`") leaves that
await **permanently** stuck — worse than round 1, and the test's own new assertion
(`is_active == false`) would fail outright rather than merely leak silently.

**The reviewer's own recommended fix for the next round:** don't drive the real `play()` coroutine
in case 4 at all. Either (a) pre-set `DialogPlayer.is_active = true` before calling
`_on_body_entered()` so `_show_notification()`'s existing guard (`pickup_base.gd` — skips
`play()` when a dialog is already active) short-circuits and no coroutine ever starts, while
still exercising the real `_on_body_entered` → `_collect` → `queue_free` wiring; or (b) drop case
4 back to asserting via `_collect()` + `_get_dialog_text()` only, matching
`test_weapon_unlock_sources.gd`'s precedent, since `PickupBase._on_body_entered`'s generic
plumbing is already covered elsewhere in the suite.

Per `feature-workflow`'s "maximum two rounds" rule, this task stops here rather than attempting a
third revision in this iteration — `set-badge stuck` applied.

**Next action:** apply fix (a) or (b) above to `3-plan.md` case 4, dispatch **one fresh** reviewer
round (this resets the counter since it addresses a wholly new, now-precisely-diagnosed defect
rather than iterating blindly), then proceed to implementation on approval.
