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

**Superseded scope note (2026-09-15):** the paragraph below described the state as of this task's
last cycle — it no longer holds. The sibling task
`flying-into-a-log-record-in-open-space-picks-it-up-and-tells` got its own stuck review
unblocked in its own cycle and shipped `global/pickups/lore_log_pickup.gd`,
`global/pickups/scenes/lore_log_pickup.tscn`, `global/assets/sprites/lore_log.png`, and
`tests/unit/test_lore_log_pickup.gd` itself, then closed its own `STATUS.md`/backlog state. **This
task must not rebuild those files or attempt to close out that task** — see `5-progress.md`,
steps 1-5 are already done. Resume at step 6 (author the 3 `LogEntryResource` `.tres` files) using
the pickup as shipped.

~~**Important scope note:** `LoreLogPickup` — the pickup class this task needs to place lore logs
— does not exist yet. It was the sole deliverable of the sibling task
`flying-into-a-log-record-in-open-space-picks-it-up-and-tells`, which stopped after two review
rounds on a test-leak issue in its **test case 4 only** (see that task's `STATUS.md` and
`4-review.md`) — the pickup's design (`3-plan.md`) itself was never in question, and the
reviewer's second round ends with a precise, named fix for the test. This task's plan below
carries that design forward unchanged (attributed, not re-litigated) with the reviewer's own
recommended fix applied, because building it is a hard prerequisite for placing any lore log in
the hub. On completion this task also closes out that sibling task's `STATUS.md` and backlog
state, since its entire scope ships here.~~

**Next action:** implement step 6 onward per `3-plan.md` (catalogue `.tres` files, hub placement,
`tests/integration/test_hub_log_placement.gd`), skipping the plan's steps 1-5, which are done.
