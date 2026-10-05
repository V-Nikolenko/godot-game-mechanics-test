# STATUS — Fighter squads (t9-fighter-squad)

**Track:** Escalated
**Task:** cmulwkar300bxqj2xgtk6jyu3 (epic: cmufs7ekv000lnm2x7nbswijy)
**Item:** Three fighters close as a pincer while a fourth comes head-on, extra fighters wait their turn, and a fallen fighter's place is taken at once
**Started:** 2026-09-30

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md` (Revision 2, 2026-10-05; Revision 1 is in git at `34984b6`)
- [ ] 3. Reviewed and APPROVED → `4-review.md` — round 1 (Rev 1): CHANGES_REQUESTED; **round 2 (Rev 2): CHANGES_REQUESTED**
      (B1: over a full two-pass cycle a W5 fails separation in 35/42 layouts, REAR dry-pass turns). Two rounds used.
- [ ] 4. Implemented — **not shipped**. Revision 2 is built and kept as `prototype/revision2_variant.patch` + its test.
- [ ] 5. Gate green
- [ ] 6. Docs updated

**State: BLOCKED (2026-10-05)** — not approved after two review rounds. The fighter code is at HEAD (t8b + t10).
The owner's decisions are in `5-escalation.md` → "Round 2": (1) separation over a full cycle (needs REAR/turn
separation design) or the first window only (ship the patch); (2) the Assault budget; (3) fighter body collision.

**Next action (after the owner decides):** `git apply prototype/revision2_variant.patch`, copy
`prototype/test_fighter_squad_rev2.gd.txt` to `tests/integration/test_fighter_squad.gd`, then:
- if 1(b): apply round-2 non-blocking N2–N9, set the decision in DECISIONS, gate, docs;
- if 1(a): design REAR/turn separation (Revision 3 of `3-plan.md`), extend `_cycle` to the LEAD's third RUN_IN with an
  end-point assertion (round-2 N3), measure with `prototype/sweep_harness.gd.txt`, and get a fresh review.
