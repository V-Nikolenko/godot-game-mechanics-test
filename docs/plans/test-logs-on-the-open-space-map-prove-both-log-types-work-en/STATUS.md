# STATUS — Test logs on the open-space map

**Track:** Escalated (medium complexity, `prepDir: null`)
**Task:** test-logs-on-the-open-space-map-prove-both-log-types-work-en (epic: log-records-discoverable-lore-and-info-logs-across-all-three)
**Item:** Test logs on the open-space map prove both log types work end to end
**Started:** 2026-09-09

- [x] 1. Context gathered → `1-context.md`
- [x] 2. Plan written → `3-plan.md`
- [x] 3. Reviewed and APPROVED → `4-review.md` (round 1: CHANGES_REQUESTED, fixed; round 2: APPROVED)
- [ ] 4. Implemented → `5-progress.md`
- [ ] 5. Gate green
- [ ] 6. Docs updated, task ticked

**Important scope note:** `LoreLogPickup` — the pickup class this task needs to place lore logs
— does not exist yet. It was the sole deliverable of the sibling task
`flying-into-a-log-record-in-open-space-picks-it-up-and-tells`, which stopped after two review
rounds on a test-leak issue in its **test case 4 only** (see that task's `STATUS.md` and
`4-review.md`) — the pickup's design (`3-plan.md`) itself was never in question, and the
reviewer's second round ends with a precise, named fix for the test. This task's plan below
carries that design forward unchanged (attributed, not re-litigated) with the reviewer's own
recommended fix applied, because building it is a hard prerequisite for placing any lore log in
the hub. On completion this task also closes out that sibling task's `STATUS.md` and backlog
state, since its entire scope ships here.

**Next action:** dispatch independent review of `3-plan.md`.
