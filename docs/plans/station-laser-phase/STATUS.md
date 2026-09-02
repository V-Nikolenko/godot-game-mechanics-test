# STATUS — Station laser phase (EPIC sub-item 3)

**Track:** A
**Backlog item:** **3. Laser phase.** Once all turrets are destroyed, the station rotates and fires
`LaserRay` beams at varying positions, forcing the player to keep moving. Beams must
telegraph before they damage (`warn_duration`) — an instant-kill beam with no tell is
unfair, and research should set the actual timing.
*Done when:* a test proves the phase only starts after the last turret dies, and that a
beam damages the player only during its active window, not its warning window.
**Started:** 2026-09-01

## ✅ COMPLETE — all seven stages done, gate green

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md` *(revision 2)*
- [x] 4. Reviewed and APPROVED → `4-review.md` — round 1 CHANGES_REQUESTED, round 2
      CHANGES_REQUESTED, **round 3 APPROVED**. Round 3 was a verification round on revision 2:
      the reviewer reproduced D1 and D2 as fixed on Godot 4.6.3 and raised four non-blocking
      notes, N1–N4, to honour during implementation.
- [x] 5. Implemented → `5-progress.md`
- [x] 6. Gate green — 21 scripts / 188 tests / 605 asserts, GATE PASS
- [x] 7. Docs updated, backlog ticked

**COMPLETE (2026-09-02).** Next session picks up EPIC sub-item 4 (bullet hell + reinforcements).
Read `5-progress.md`'s "Deviations from plan" and the *Laser phase* section of the station's
`ENEMY.md` first — between them they record the three things sub-item 4 will trip over: hang new
fire off `armor_broken` rather than a second turret fan-out; any beam or projectile the station
emits needs a narrowed hit mask or it damages the station itself; and the turrets are still
authored at `rotation = 0` with barrels pointing away from the player, which now also spin with
the hull.

### Review history (do NOT relitigate)

Three rounds. Rounds 1 and 2 were CHANGES_REQUESTED and found real defects that would each have
cost a whole unattended session:

- **Round 1, finding 2** — the *headline* regression test (the one proving the boss does not kill
  itself with its own beam) **could not fail as specified**. At `emitter_radius = 140`, only the
  diagonal volley angles overlap the core hurtbox; volley 0 is axis-aligned and misses by 20 px.
  The test would have gone green with the fix reverted.
- **Round 2, D1** — `SpaceStation.config` is a **process-wide shared resource**
  (`space_station.gd:24` `load()`s it, `ResourceLoader` caches). The test plan told tests to
  shorten the timings "on the instance", which would have permanently rewritten the shipped
  `.tres` values in memory — and test 10 is the test that asserts those values, running last in
  the same file. A guaranteed red gate at the very end of a session.

Both were fixed in `3-plan.md` revision 2, along with the corrected time-to-lethal formula
(`warn + 0.56 s`, not `0.2 + warn + 0.56`), propagated back into `1-context.md` spike 1 and
`2-research.md` Q1 so no artifact still carries the wrong arithmetic.

**Round 3 (2026-09-02) — `VERDICT: APPROVED`.** A verification round on revision 2. The reviewer
re-measured D1 and D2 on Godot 4.6.3 and confirmed both fixed: the config really is one shared
instance and §3a's copy-in-`_ready()` closes it; children `_ready()` before parents, so the copy
is safe; and `interval 2.5` clears the measured 1891–1904 ms test-timing beam lifetime with ~0.6 s
margin. It raised **four non-blocking notes for the implementer** — N1 (the shipped-timing figures
are a 1.89–1.97 s *range*, not the plan's single 1891 ms; a step-5 docs correction only), N2 (write
test 10 against the **phase node's copied fields**, not `station.config`, or it is identity-vacuous),
N3 (give the phase fields real defaults, or bail, when `config == null` — `volley_interval = 0` is
an error path), N4 (test 8 costs ~20 s of wall clock; sampling by `_volley_index` is allowed).

**Settled design — do not reopen:** a `StationLaserPhase` child node, an `armor_broken` signal, an
additive `LaserRay.hit_mask_override`, deterministic volley angles, and timings in the `.tres`
copied into the phase at `_ready()`.
