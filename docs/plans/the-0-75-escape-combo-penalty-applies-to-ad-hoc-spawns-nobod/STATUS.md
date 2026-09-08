# STATUS — Escape-combo penalty on ad-hoc spawns

**Track:** Escalated
**Task:** the-0-75-escape-combo-penalty-applies-to-ad-hoc-spawns-nobod (epic: code-health-backlog)
**Item:** The 0.75× escape-combo penalty applies to ad-hoc spawns nobody expects to kill.
**Started:** 2026-09-08

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md`
- [x] 3. Reviewed and APPROVED → `4-review.md`
- [x] 4. Implemented → `5-progress.md`
- [x] 5. Gate green
- [x] 6. Docs updated, task ticked

**Next action:** None — complete. `VERDICT: APPROVED` (see `4-review.md`). Fix shipped: a new
independent `counts_as_escape` flag (mirroring `counts_toward_wave_clear`) lets ScoreTracker skip
the escape-combo penalty per-enemy-type. Set to `false` only for the bonus drone, whose own header
comment already promised "no penalty for missing it" but whose code didn't honour it. Station
reinforcements' deliberate double penalty (commit `9079a20`,
`test_station_reinforcements.gd`) is explicitly left untouched — that call is not this task's to
make. `bash /agent/verify.sh` -> GATE PASS (361/361); `bash scripts/check-test-leaks.sh` -> LEAK
CHECK PASS.
