# STATUS — Contact HitBox drops the CollisionShape2D transform

**Track:** A
**Task:** baseenemy-gd-56-59-builds-the-contact-hitbox-from-col-shape- (epic: code-health-backlog)
**Backlog item:** **`base_enemy.gd:56-59` builds the contact HitBox from `col.shape` but drops the
**Started:** 2026-09-04

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md`
- [x] 4. Reviewed and APPROVED → `4-review.md`
- [x] 5. Implemented → `5-progress.md`
- [x] 6. Gate green
- [x] 7. Docs updated, backlog ticked

**Next action:** none — complete. Round 2 of review returned `VERDICT: APPROVED` (`4-review.md` →
"Review round 2"). Implemented, gate green (302/302, 33 scripts), docs updated, two follow-ups
filed: `code-built-contact-hitboxes-are-typed-as-laser-damage-not-co` and
`move-code-built-contact-hitboxes-into-the-scenes-as-the-aste`.

**Left for a human to eyeball** (headless tests cannot judge feel): `drone_interceptor`
self-destruct range (3.08× further out), ally-fighter fragility against the five enlarged enemy
boxes, and ally ram frequency (their own box grew 1.84×).
