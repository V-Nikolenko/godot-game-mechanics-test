# STATUS — Fighter squads (t9-fighter-squad)

**Track:** Escalated
**Task:** cmulwkar300bxqj2xgtk6jyu3 (epic: cmufs7ekv000lnm2x7nbswijy)
**Item:** Three fighters close as a pincer while a fourth comes head-on, extra fighters wait their turn, and a fallen fighter's place is taken at once
**Started:** 2026-09-30

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md` (Revision 1)
- [ ] 3. Reviewed and APPROVED → `4-review.md` — round 1: **CHANGES_REQUESTED** (B1: the D4 give-way is a scope
      change only the owner can approve; B2–B7)
- [ ] 4. Implemented — **not shipped**; both measured variants kept as patches in `prototype/`
- [ ] 5. Gate green
- [ ] 6. Docs updated

**State: ESCALATED to the owner (2026-09-30).** `5-escalation.md` holds the clean-harness measurements and three
decisions: the separation mechanism, the Assault budget, and fighter–fighter physics collision. The fighter code is at
HEAD (t8b).

**Next action (after the owner decides):** apply the chosen variant from `prototype/` (see its README), and apply the
decision. Then revise `3-plan.md` to Revision 2 answering `4-review.md` B1–B7 and N1–N9, and run review round 2.
Finally, commit `test_fighter_squad.gd` from the draft with the harness collision exceptions.
