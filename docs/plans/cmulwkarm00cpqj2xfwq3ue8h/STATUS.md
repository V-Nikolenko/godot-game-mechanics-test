# STATUS — Level 1 deep_space / planet_approach fighters and Gatlings off rails

**Track:** Escalated
**Task:** cmulwkarm00cpqj2xfwq3ue8h (epic: cmufs7ekv000lnm2x7nbswijy)
**Item:** In level 1's deep-space and planet-approach sections, fighters and the Gatling pair arrive at the same moments and places as before, then fight as squads inside the corridor and leave
**Started:** 2026-10-06

- [x] 1. Context gathered → `1-context.md` (includes the measurements)
- [ ] 2. Plan written → `3-plan.md` — not written: escalated before planning, see below
- [ ] 3. Reviewed and APPROVED → `4-review.md`
- [ ] 4. Implemented → `5-progress.md`
- [ ] 5. Gate green
- [ ] 6. Docs updated

**ESCALATED (2026-10-06) → `5-escalation.md`.** The epic's shots/s density gate (≤ 1.25 × the frozen legacy
constant, plan numerator) fails in both sections (1.86× / 1.90×), and none of the three pre-approved levers can fix
deep_space. The epic says any other change needs the owner. A real run shows the AI fires 11–22 % of the legacy shots.

**Next action:** Owner picks an option in `5-escalation.md` (A recommended). Then: apply
`prototype/level1_duration_rails_off.patch`, write `3-plan.md` for the chosen gate, independent review, implement.
