# STATUS — Station core hurtbox: narrow to 88x240, or keep it hull-sized?

**Track:** A
**Task:** should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a- (epic: code-health-backlog)
**Backlog item:** Should the station's core hurtbox be narrowed to 88 x 240? — a design question, not a bug.
**Started:** 2026-09-06

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md`
- [x] 4. Reviewed and APPROVED → `4-review.md`
- [x] 5. Implemented → `5-progress.md`
- [x] 6. Gate green
- [x] 7. Docs updated, backlog ticked

**Next action:** None — complete. Round 2 review returned `VERDICT: APPROVED`. Answer to the
backlog question: **no, do not narrow the station core hurtbox**, and the decision is now pinned by
`tests/integration/test_enemy_hurtbox_geometry.gd` (6 tests) and two real-bullet physics tests in
`tests/integration/test_space_station.gd`. `bash /agent/verify.sh` -> GATE PASS (313/313);
`bash scripts/check-test-leaks.sh` -> LEAK CHECK PASS. No production code or scene changed.