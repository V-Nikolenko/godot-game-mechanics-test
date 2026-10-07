# Progress
- [x] Step 1 — tests: pin rows regenerated (27 cloud_descent rows → AI rows), `_RAIL_SECTIONS` emptied + never-vacuous
  assertion, `MIGRATED_SECTIONS` + sanity counts 64 / 43 (`test_level1_fighter_spawns.gd`); cloud_descent measured case
  (`test_level1_fighter_fire_density.gd`); per-entry deadline rows, boundary rows and the real-scene exit-bound probe
  (`test_engagement_deadline.gd`); real-run exit test (`test_level1_fighter_exit.gd`).
- [x] Step 2 — level edit (`level_1_director.gd` `_build_section_3()`), from attempt 1's prototype, reviewed.
- [x] Step 3 — gate + `scripts/check-test-leaks.sh` (see STATUS).
- [x] Step 4 — DECISIONS ("Phase 3, built in t17").

**Resume at:** done.
**Deviations from plan:** Revision 2/3 per `4-review.md` — curved-exit bound (5.37 s) instead of the task's Razor-shaped
term, gated on the real scene; single `_deadline_rows()` check; exit test judges `waves_complete` on WaveManager's clock.
