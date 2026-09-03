# STATUS — Station and turrets as a destructible entity (EPIC sub-item 1)

**Track:** A
**Backlog item:** **1. Station and turrets exist as a destructible entity.** Generate the station and turret
sprites via PixelLab. Assemble the station scene with N turrets as child entities, each
individually damageable. The station core takes no damage while any turret is alive.
*Done when:* a GUT test destroys turrets one at a time and proves the core is invulnerable
until the last turret dies, then becomes damageable.
**Started:** 2026-09-01

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md`
- [x] 4. Reviewed and APPROVED (round 2; round 1 = CHANGES_REQUESTED, F1-F12 folded in) → `4-review.md`
- [x] 5. Implemented → `5-progress.md`
- [x] 6. Gate green — 165 tests / 527 asserts, 18 scripts, GATE PASS
- [x] 7. Docs updated, backlog ticked

**COMPLETE.** All stages done. Next session: EPIC sub-item 2 (`station_assault` LevelSection). Read `3-plan.md`'s closing note and `ENEMY.md`'s Spawn notes first — they record the two constraints sub-item 2 needs (`enemy_container` child, not the `enemies` group; and `BaseEnemy` frees in the same frame as `died`).
