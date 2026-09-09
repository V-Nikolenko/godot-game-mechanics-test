# ESC menu Lore Logs section

## Problem

The player can find lore-log pickups (upstream tasks in this epic) and `LogState` tracks which
ones they've found, but nothing in the game ever shows them the text again. Today `LogState` is a
write-only store: entries are collected and immediately forgotten by the UI. The player has no way
to answer "what have I found so far" or "how much is left."

## Design

Add a fifth ESC-menu option, **Lore Logs**, that opens a full-catalogue reader:

- Every catalogue entry (`LogState.total_count()` of them) gets a row, in catalogue (`sequence`)
  order. Found entries show their real title and, when the cursor lands on them, their full body.
  Unfound entries show a `???` title and a "not yet found" placeholder body — visibly present,
  not hidden, so the player can see there is more to find.
- A header reads `Lore Logs — <collected> / <total>`.
- `ModuleList`'s row-lock visual language (grey modulate, darker grey while under the cursor) is
  reused in a new, simpler item — no icon, no equipped/selected tint, since nothing here is ever
  equipped.
- **Paging, not `ModuleList`'s truncation.** `ModuleList.MAX_ITEMS = 8` silently drops any row past
  the 8th; `CLAUDE.md` calls this out by name as unfit for a log catalogue that will grow past one
  screen. The new list pages in fixed-size (8-row) chunks instead: `menu_left`/`menu_right` change
  page, `menu_up`/`menu_down` move the cursor within a page, and the header appends
  `(Page P/N)` whenever there's more than one page.
- **Reading is just navigating.** `ModuleList` already shows a hovered row's description without a
  separate "confirm" step (`_refresh_cursor()` sets the description label). Lore Logs does the
  same — no row is ever "confirmed", since there's nothing to select. `menu_confirm` has no meaning
  inside the list and is simply not wired there.

### Files

New:
- `global/ui/pause_menu/lore_log_list.gd` (`class_name LoreLogList`, `extends Node2D`) — mirrors
  `ModuleList`'s shape: `open()`, `close()`, `navigate(delta)`, plus `page(delta)`. No
  `confirmed`/`cancelled` signals — `PauseMenu` owns closing it directly, the same way
  `PlayerMenu` owns `_module_list_open` rather than the list owning its own dismissal.
- `global/ui/pause_menu/lore_log_list.tscn` — a full-screen-ish panel (`ColorRect` background,
  `HeaderLabel`, `BodyLabel` as a `RichTextLabel`, `HintLabel` for the control legend), all
  siblings in one local coordinate frame centered on the node's origin. Row items are created at
  runtime the same way `ModuleList` creates `ModuleListItem`s.
- `global/ui/pause_menu/lore_log_list_item.gd` (`class_name LoreLogListItem`, `extends Control`)
  and `.tscn` — title `Label` only, locked/cursor modulate copied from `ModuleListItem` minus the
  icon and equipped-tint logic (nothing is ever equipped here).
- `tests/integration/test_lore_log_list.gd` — model: `test_module_list_lock.gd`.
- `tests/unit/fixtures/log_entries_many/*.tres` — 10 fixture entries (more than one page) for the
  paging tests.
- `tests/integration/test_pause_menu_lore_logs.gd` — covers the ESC-menu wiring itself (see Test
  plan).

Changed:
- `global/autoloads/log_state.gd` — add `all_ids() -> Array[StringName]`: catalogue-order ids for
  every entry, collected or not (the existing `collected_ids()` is the same walk filtered to
  collected-only; this is the unfiltered version the list needs to render locked rows at all).
- `tests/unit/test_log_state.gd` — one new test for `all_ids()`.
- `global/ui/pause_menu/pause_menu.gd` — fifth option:
  - `_options` grows to `[Option0..Option4]`; `Option3` = Lore Logs (always visible in both
    `mission_mode` states), `Option4` = Exit Game (shifted from index 3).
  - `_lore_logs_open: bool` flag mirroring `PlayerMenu._module_list_open`. While it's true,
    `_unhandled_input` fully absorbs input the same way `PlayerMenu` does: `ui_cancel` closes the
    list back to the menu (not the whole pause menu), `menu_up/down/left/right` route to
    `_lore_log_list`, and the branch ends in an unconditional `return` so `menu_confirm` (and
    anything else) is swallowed too — it must never fall through to the outer `_confirm()` and
    re-trigger `_lore_log_list.open()` on cursor 3. Tested explicitly (see Test plan).
  - `_confirm()` gets a `3:` case that hides `$MenuContainer`, calls `_lore_log_list.open()`, sets
    the flag; a `_close_lore_logs()` helper reverses it. `_close()` defensively closes the list
    first if it's somehow still open (tree-pause edge case), so the pause menu never leaves stale
    state behind if something force-closes it.
- `global/ui/pause_menu/pause_menu.tscn` — insert a new `Option3` (Lore Logs: `Bg` sprite +
  `Label`, no icon — there's no existing icon asset for this and generating one is out of scope
  for a functional UI list) before the existing Exit Game row, renamed `Option4` and repositioned
  one row down. Instance `lore_log_list.tscn` as a new top-level child, positioned at the screen
  center `(640, 360)`.
- `global/ui/pause_menu/open_space_pause_menu.tscn` — same `Option3`/`Option4` insertion; `Option1`/
  `Option2` stay `visible = false` as today (mission_mode = false).

### Why not reuse `ModuleList` directly

`ModuleList` is keyed to `ShipModuleState` and a slot id, hard-codes "None" as row 0 (module
removal), and its confirm path equips a module. None of that applies to a read-only catalogue
browser, and bolting an `unlockable: bool` / `mode: enum` switch onto it to make it serve two
unrelated screens would cost more than the ~80 lines the new item/list scripts actually need.
Composition over inheritance, applied to *reuse the pattern*, not the class.

### Why pause menu owns the flag instead of `LoreLogList` emitting `closed`

Considered a `closed` signal (matching `ModuleList.cancelled`). Rejected: `ModuleList` needs
`confirmed`/`cancelled` because two different outcomes (equip vs. abandon) both close it from the
caller's side. `LoreLogList` only ever closes one way — `PauseMenu` already has to intercept
`ui_cancel` before the list sees it (to decide "close list" vs. "close whole menu"), so the flag
check is already sitting right there in `_unhandled_input`; a signal would be a round-trip back to
code that already has the answer.

## Build sequence

1. `LogState.all_ids()` + its unit test. Verify against the existing fixture directory (order
   matches `collected_ids()`'s walk, just unfiltered).
2. `tests/unit/fixtures/log_entries_many/` — 10 entries, sequence 0-9, ids `entry_00`..`entry_09`.
3. `LoreLogListItem` script + scene. No test of its own (mirrors `ModuleListItem`, which also has
   none — its behaviour is covered through the list's tests).
4. `LoreLogList` script + scene + `test_lore_log_list.gd`:
   - locked/unlocked rows rendered correctly (title vs. `???`, locked modulate)
   - header ratio (`collected / total`) correct and updates as entries are collected
   - single-page catalogue: no `(Page ...)` suffix, `page()` is a no-op
   - >1 page catalogue: `(Page 1/2)` suffix, `page(1)` advances, wraps past the last page,
     `navigate()` is bounded by the *current page's* row count
   - reading: cursor on an unlocked row shows its real body; cursor on a locked row shows the
     placeholder, never the real body
   - boundary: empty catalogue (`total_count() == 0`) — no crash, header reads `0 / 0`, body shows
     the "nothing catalogued" placeholder
5. `PauseMenu` five-option wiring + both `.tscn` edits + `test_pause_menu_lore_logs.gd`:
   - Option index 3 is visible and labelled "Lore Logs" in both `mission_mode` states
   - confirming it hides `$MenuContainer`, shows the list, sets `_lore_logs_open`
   - `ui_cancel` while open closes the list and restores `$MenuContainer`, **without** closing the
     pause menu or unpausing the tree
   - a second `ui_cancel` (list already closed) closes the pause menu as before
   - `mission_mode` still gates exactly options 1 and 2, unchanged from today
   - a `menu_confirm` while the list is open does not re-open it and does not reach the pause
     menu's own `_confirm()` (regression test for the round-1 review finding on this plan)
6. `bash /agent/verify.sh`.
7. `updating-project-docs` skill (structural change: new UI components + a new autoload method).

## Test plan

Enumerated above per step; the two new integration test files plus one unit test are the deliverable.
Boundary cases explicitly covered: empty catalogue, exactly-one-page catalogue, multi-page catalogue
with page wraparound, and locked-row body text never leaking through.

## Risks

- **Tree pausing in a test.** `PauseMenu._try_open()` sets `get_tree().paused = true`. A test that
  drives this through real input/`_try_open()` must restore `get_tree().paused = false` even on
  assertion failure (GUT runs `after_each`/`after_all` regardless), or it corrupts every later test
  in the suite. Mitigated by testing `PauseMenu`'s option/routing logic directly (calling `_confirm()`
  after setting `_cursor`, not simulating real ESC key input end-to-end) and asserting
  `get_tree().paused` is restored in `after_each`.
- **`LogState` is a live singleton shared by the whole suite.** Unlike `ShipModuleState`'s test
  (which mutates dictionaries the code reads live, no reload step), `LogState`'s catalogue is
  populated only inside `_load_catalogue()` — reassigning `catalogue_dir` alone does nothing.
  Exact sandbox procedure for `test_lore_log_list.gd`:
  - `before_all`: `SaveSandbox.capture()`; save the real `LogState.catalogue_dir`.
  - `before_each`: `SaveSandbox.clear_all()`; set `LogState.catalogue_dir` to the fixture path;
    call `LogState._load_catalogue()` then `LogState._load()` (loads nothing from the now-cleared
    save file); use `LogState.collect_next()` to mark specific fixture entries collected where a
    test needs some found and some not (it writes through `_save()`, which is sandboxed).
  - `after_all`: reset `LogState.catalogue_dir` back to `LogState.DEFAULT_CATALOGUE_DIR`, call
    `_load_catalogue()` then `_load()` again so the live singleton is fully back on the real
    catalogue and real save state before the next test file runs, **then** `SaveSandbox.restore()`.
  - Skipping the reload half of either end leaves the singleton silently pointed at fixture data
    (tests would pass against the wrong catalogue) or leaks fixture `_collected` state into every
    later GUT file in the same run — this is not optional cleanup, it's what makes the sandbox
    real.

## Out of scope

- New icon art for the Lore Logs menu row (no PixelLab asset generation triggered by this task).
- Any change to how logs are collected in the world (upstream/sibling tasks in this epic).
- Scroll/animation polish beyond functional paging.
