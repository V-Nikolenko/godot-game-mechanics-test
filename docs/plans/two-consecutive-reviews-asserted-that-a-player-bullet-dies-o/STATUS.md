# STATUS — Player bullet lifetime and piercing

**Track:** A
**Task:** two-consecutive-reviews-asserted-that-a-player-bullet-dies-o (epic: code-health-backlog)
**Backlog item:** **Two consecutive reviews asserted that a player bullet dies on its first hurtbox overlap.
**Started:** 2026-09-06

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md`
- [x] 4. Reviewed and APPROVED → `4-review.md`
- [x] 5. Implemented → `5-progress.md`
- [x] 6. Gate green
- [x] 7. Docs updated, backlog ticked

**Next action:** COMPLETE. Gate green (319/319), leak check clean, backlog ticked done.

**Review outcome:** round 1 `CHANGES_REQUESTED` (F1-F7), round 2 `VERDICT: APPROVED` after Revision 2.
Round 2 added non-blocking notes to apply while building: test 3 must `assert_gt(bullets.size(), 0)`
per branch or it passes vacuously (a scriptless `Node.new()` never yields an `actor`), and the stub
actor must expose a real `velocity` property.
