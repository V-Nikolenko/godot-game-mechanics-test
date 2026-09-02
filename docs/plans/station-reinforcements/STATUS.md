# STATUS — Station reinforcements (EPIC sub-item 4b)

**Track:** A
**Backlog item:** **4b. Reinforcements.** During the fight, existing enemy ships fly in from the sides, top and bottom. *Done when:* reinforcement waves spawn from at least three screen edges and a headless run of the section produces no errors. Starting points: the station is spawned as a single zero-delay wave with no `.delay()` and no `.move()` (both load-bearing — see `enemy-roster.md`), so reinforcements need to come from somewhere other than that wave; and `LevelSection.ENEMIES_CLEARED` polls the container's child count, so a reinforcement still alive holds the section open after the boss dies.
**Started:** 2026-09-02

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Research done → `2-research.md`
- [x] 3. Plan written → `3-plan.md`
- [ ] 4. Reviewed and APPROVED → `4-review.md`
- [ ] 5. Implemented → `5-progress.md`
- [ ] 6. Gate green
- [ ] 7. Docs updated, backlog ticked

**Next action:** Independent subagent review (stage 4).
