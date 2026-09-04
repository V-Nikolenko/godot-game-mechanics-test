# Progress

- [x] Step 1 — tests first. Rewrote `tests/unit/test_ship_module_state.gd`: five INTENT tests
      added (`test_equipping_requires_unlocking` replacing
      `test_equipping_does_not_require_unlocking`, `test_equipping_works_after_unlocking`,
      `test_unequipping_never_requires_an_unlock`,
      `test_load_grandfathers_a_module_equipped_before_the_gate`,
      `test_load_does_not_grandfather_an_unknown_equipped_id`), and the six existing tests that
      equipped without unlocking now unlock first. Watched them fail: 15/17, with exactly the
      gate assertion (l.137-138) and the migration assertions (l.197, l.214) red.
- [x] Step 2 — `global/autoloads/ship_module_state.gd`: unlock check in `equip()` (&"" exempt),
      grandfather append in `_load()` before `_unlocked[slot] = list`, guarded on
      `installed != &"" and installed not in list` per review round-2 note 1. Corrected the
      stale `_unlocked` comment. 17/17 green.
- [x] Step 3 — `global/ui/player_menu/module_list_item.gd`: `_is_locked`, third `configure()`
      argument (defaults `false`), `is_locked()` accessor, and `_LOCKED_MODULATE` /
      `_LOCKED_CURSOR_MODULATE` tested **before** `_is_cursor` in `_update_modulate()` (round-2
      note 2) so a locked row under the cursor cannot light up yellow.
- [x] Step 4 — `global/ui/player_menu/module_list.gd`: `_locked: Array[bool]` filled in `open()`
      and cleared in `_clear()`, `_LOCKED_PREFIX` on a locked row's description, `confirm()` a
      defined no-op on a locked row. Bound-checked against `_locked.size()` (round-2 note 3).
      The `&""` row is explicitly never locked.
- [x] Step 5 — `open_space/scenes/levels/sector_hub.tscn`: 14 further
      `ship_module_unlocker_pickup.tscn` instances reusing `ExtResource("13_b4ymh")`, two rows
      at y = -315 and y = -415, x from -280 to 320 at 100 px (round-2 note 4 — the plan's
      "y ≈ -215" was the *existing* row). 24 nodes → 38.
- [x] Step 6 — `tests/integration/test_module_unlock_sources.gd` (3 tests, invariant) and
      `tests/integration/test_module_list_lock.gd` (6 tests, intent).
- [x] Step 7 — `bash /agent/verify.sh`: **GATE PASS**, 274/274 tests over 29 scripts.
- [x] Step 8 — `updating-project-docs`: PROJECT.md autoload row, global.md autoload table + unlock-gate section + "to add a new module" step 4, open_space.md hub bench + progression table, CLAUDE.md test conventions, tests/README.md invariant + gate sections.

**Resume at:** done.

**Deviations from plan:**
- Design point 5's colour rationale was factually wrong (`_COLOR_LOCKED` and `_GREY_MODULATE`
  are the same value). `3-plan.md` corrected in place; locked rows use their own darker
  `_LOCKED_MODULATE`/`_LOCKED_CURSOR_MODULATE` so the selectable "None" row stays
  distinguishable at rest. Structure and precedence still mirror `MissionListItem`.
- The existing hub instance is still named `ShipModuleUnlockerPickup` while the 14 new ones are
  named `ModuleUnlockerX`. Left alone deliberately — renaming it buys nothing and churns a node
  path.

**Verified failing before implementation** (so none of these tests are vacuous):
- Unit: 2 tests / 4 asserts red before step 2.
- `test_module_unlock_sources.gd`: with the scene edit stashed, 14 of 15 coverage asserts fail
  (3/17 asserts pass).
- `test_module_list_lock.gd`: with the `&""` exemption removed from `ModuleList.open()`,
  3 of 6 tests fail.

**Known cosmetic issue:** GUT reports 24 orphans for `test_reopening_rebuilds_the_lock_flags` —
the first open's rows, which `ModuleList._clear()` `queue_free()`s and which the delete queue
does not flush before the test ends. Pre-existing `ModuleList` behaviour, not a gate failure;
awaiting `process_frame` does not change the count. Noted in the test.
