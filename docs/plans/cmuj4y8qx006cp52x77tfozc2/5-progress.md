# Progress
- [x] Step 1 — tests: `tests/unit/test_contact_profile.gd`, `tests/integration/test_contact_blast_damage.gd`, new
  cases in `tests/integration/test_base_enemy.gd`, fixture `tests/helpers/contact_fixture.gd`.
- [x] Step 2 — `global/components/contact_blast.gd`.
- [x] Step 3 — `global/components/contact_profile.gd`.
- [x] Step 4 — `BaseEnemy` wiring (`contact_profile`, `_resolve_contact_profile()`, `suspend_ai()` arms).
  Mutation check: synchronous parenting, a blast left at the origin, and detonating on unarmed death each turn the
  new tests red.
- [x] Step 5 — verify.sh GATE PASS (916/916), check-test-leaks.sh PASS.
- [x] Step 6 — global.md, assault.md, DECISIONS.md.

**Resume at:** done.
**Deviations from plan:** none beyond the review-driven `_attach` (in `3-plan.md`). The lifetime case measures the
blast's own `tree_entered`/`tree_exiting` frames (exact 4), stricter than the planned "within a frame".
