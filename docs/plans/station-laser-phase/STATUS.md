# STATUS — Station laser phase (EPIC sub-item 3)

**Track:** A
**Backlog item:** **3. Laser phase.** Once all turrets are destroyed, the station rotates and fires
`LaserRay` beams at varying positions, forcing the player to keep moving. Beams must
telegraph before they damage (`warn_duration`) — an instant-kill beam with no tell is
unfair, and research should set the actual timing.
*Done when:* a test proves the phase only starts after the last turret dies, and that a
beam damages the player only during its active window, not its warning window.
**Started:** 2026-09-01

## ⛔ BLOCKED at stage 4 — two review rounds spent, not approved

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md` *(revision 2)*
- [ ] 4. Reviewed and APPROVED → `4-review.md` — **round 1 CHANGES_REQUESTED, round 2
      CHANGES_REQUESTED. The `feature-workflow` gate allows a maximum of two rounds, so
      implementation did NOT start.**
- [ ] 5. Implemented → `5-progress.md`
- [ ] 6. Gate green
- [ ] 7. Docs updated, backlog ticked

**No code was written this cycle.** The working tree contains documentation only.

### Why it is blocked, and why that was the right outcome

The reviewer reproduced its findings at runtime on Godot 4.6.3 rather than reading the plan, and
found real defects both rounds. The two that mattered most would each have cost a whole
unattended session:

- **Round 1, finding 2** — the *headline* regression test (the one proving the boss does not kill
  itself with its own beam) **could not fail as specified**. At `emitter_radius = 140`, only the
  diagonal volley angles overlap the core hurtbox; volley 0 is axis-aligned and misses by 20 px.
  The test would have gone green with the fix reverted.
- **Round 2, D1** — `SpaceStation.config` is a **process-wide shared resource**
  (`space_station.gd:24` `load()`s it, `ResourceLoader` caches). The test plan told tests to
  shorten the timings "on the instance", which would have permanently rewritten the shipped
  `.tres` values in memory — and test 10 is the test that asserts those values, running last in
  the same file. A guaranteed red gate at the very end of a session.

Both are now fixed in `3-plan.md` revision 2, along with the corrected time-to-lethal formula
(`warn + 0.56 s`, not `0.2 + warn + 0.56`) which was also propagated back into `1-context.md`
spike 1 and `2-research.md` Q1 so no artifact still carries the wrong arithmetic.

**Round 2 closed with:** *"All four round-1 blocking findings are genuinely fixed... The design is
settled; I have no further objection to the shape of the change... Round 3 needs only D1, D2 and
the nits — no new research, no design change."* Revision 2 addresses exactly D1, D2, D3, D4, D5
and the two restatements, and nothing else.

**Next action:** run **one** review round (round 3) on `3-plan.md` revision 2 — it should be a
short verification, not a fresh review; point the reviewer at the revision-2 header block, which
lists precisely what changed. On `VERDICT: APPROVED`, implement stages 5–7 straight through; the
build sequence is five steps and the test plan is ten tests, sized for one window.

**Decision the next cycle should NOT relitigate:** the design (a `StationLaserPhase` child node, an
`armor_broken` signal, an additive `LaserRay.hit_mask_override`, deterministic volley angles,
timings in the `.tres` copied into the phase at `_ready()`). Two rounds of adversarial review
signed off on the shape; only the test-harness details were ever contested.
