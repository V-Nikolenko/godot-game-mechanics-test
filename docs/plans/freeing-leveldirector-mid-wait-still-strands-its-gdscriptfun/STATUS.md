# STATUS — LevelDirector cancel seam for suspended waits

**Track:** Escalated
**Task:** freeing-leveldirector-mid-wait-still-strands-its-gdscriptfun (epic: code-health-backlog)
**Item:** Freeing LevelDirector mid-wait still strands its GDScriptFunctionState
**Started:** 2026-09-08

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md`
- [x] 3. Reviewed and APPROVED → `4-review.md`
- [x] 4. Implemented → `5-progress.md`
- [x] 5. Gate green
- [x] 6. Docs updated, task ticked

**Done.** Implementation (cancel seam in `level_director.gd`, tests 4-6 in
`test_level_director_polling.gd`) landed in a prior cycle (commit `ed3dd29`) but that cycle's
`agent: cycle` commit message and unfinished bookkeeping (`STATUS.md`, `tests/README.md`'s "Two
traps" section, backlog state) left the task looking incomplete. This cycle finished the
bookkeeping: corrected `tests/README.md` (the "no amount of care... can resume it afterwards" claim
was made false by the fix), verified `bash /agent/verify.sh` and `scripts/check-test-leaks.sh` both
pass, and closed the task.
