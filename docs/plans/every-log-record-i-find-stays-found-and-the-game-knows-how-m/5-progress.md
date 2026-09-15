# Progress

- [x] Step 1 — `global/resources/logs/log_entry_resource.gd` (LogEntryResource Resource subtype).
- [x] Step 2 — Fixture catalogue: `tests/unit/fixtures/log_entries/{entry_a,entry_b,entry_c}.tres`
      (sequences 2, 0, 1 — deliberately out of filename order) and
      `tests/unit/fixtures/log_entries_duplicate/{dup_one,dup_two}.tres` (both `id = &"dup_entry"`).
- [x] Step 3 — `global/autoloads/log_state.gd` (LogState autoload), including the duplicate-id
      guard added after plan review round 1.
- [x] Step 4 — Registered `LogState="*res://global/autoloads/log_state.gd"` in `project.godot`.
- [x] Step 5 — Added `"user://log_state.cfg"` to `tests/helpers/save_sandbox.gd` `PATHS` and its
      doc comment.
- [x] Step 6 — `tests/unit/test_log_state.gd`: 9 tests covering derived total, sort-by-sequence,
      collect/report, idempotent-once-fully-collected (boundary), save round-trip,
      unknown-id-in-save, get_entry, and duplicate-id-not-double-counted (boundary).
- [x] Step 7 — `bash /agent/verify.sh` → GATE PASS, 399/399 tests passing (was 391 before this
      task; +8 in `test_log_state.gd`).

**Resume at:** done — proceed to docs update and commit.
**Deviations from plan:** one implementation fix not anticipated by the plan: GDScript cannot
infer the type of `x := ls.collect_next()` when `ls` is statically typed `Node` (the tree-less
`_fresh()` helper's return type, matching `test_upgrade_state.gd`'s idiom) — the call resolves
dynamically so `:=` has nothing to infer from. Fixed by explicitly typing those three locals as
`StringName` instead of using `:=`. No behavioral change, no plan change needed.
