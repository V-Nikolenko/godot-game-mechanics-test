## INTENT tests for LoreLogList (global/ui/pause_menu/lore_log_list.gd), the ESC-menu Lore Logs
## reader. New code, so this asserts what should happen, not what used to.
##
## Model: tests/integration/test_module_list_lock.gd. LoreLogList reads the live LogState
## singleton directly, so before_all/after_all sandbox its catalogue_dir and save file — see the
## Risks section of docs/plans/the-esc-menu-.../3-plan.md for why a bare catalogue_dir reassignment
## is not enough: LogState only (re)populates _catalogue/_by_id inside _load_catalogue(), so every
## fixture switch below is followed by an explicit reload, and the final restore reloads the real
## catalogue too rather than leaving the singleton pointed at fixture data for the rest of the run.
extends GutTest

const LIST_SCENE: PackedScene = preload("res://global/ui/pause_menu/lore_log_list.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## 3 entries -> exactly one page (PAGE_SIZE = 8).
const _SINGLE_PAGE_DIR := "res://tests/unit/fixtures/log_entries"
## 10 entries -> two pages (8 + 2).
const _MULTI_PAGE_DIR := "res://tests/unit/fixtures/log_entries_many"
## Never created on disk — LogState.DirAccess.open() returns null for it, the same "no catalogue
## yet" path total_count() == 0 already relies on.
const _EMPTY_DIR := "res://tests/unit/fixtures/log_entries_does_not_exist"

var _sandbox := SaveSandbox.new()
var _saved_catalogue_dir: String
var _list: LoreLogList


func before_all() -> void:
	_sandbox.capture()
	_saved_catalogue_dir = LogState.catalogue_dir


func after_all() -> void:
	## Put the live singleton back on the real catalogue and real save state before the sandbox
	## hands the save file back, so no later test file in this GUT run sees fixture data.
	LogState.catalogue_dir = _saved_catalogue_dir
	LogState._load_catalogue()
	LogState._load()
	_sandbox.restore()


func before_each() -> void:
	_list = LIST_SCENE.instantiate() as LoreLogList
	add_child_autofree(_list)


## Points the live LogState singleton at `dir` with a clean (nothing collected) save state.
func _use_catalogue(dir: String) -> void:
	_sandbox.clear_all()
	LogState.catalogue_dir = dir
	LogState._load_catalogue()
	LogState._load()


func test_locked_rows_show_placeholder_title_unlocked_show_real_title() -> void:
	_use_catalogue(_SINGLE_PAGE_DIR)
	LogState.collect_next()  # entry_beta (sequence 0, first in catalogue order)

	_list.open()

	assert_eq(_list._items.size(), 3, "every catalogue entry gets a row, none truncated")
	assert_false(_list._items[0].is_locked(), "entry_beta was collected")
	assert_true(_list._items[1].is_locked(), "entry_gamma was not collected")
	assert_true(_list._items[2].is_locked(), "entry_alpha was not collected")


func test_header_shows_collected_over_total_ratio() -> void:
	_use_catalogue(_SINGLE_PAGE_DIR)
	LogState.collect_next()
	LogState.collect_next()

	_list.open()

	assert_string_contains(_list._header_lbl.text, "2 / 3")


func test_single_page_catalogue_has_no_page_suffix_and_page_is_noop() -> void:
	_use_catalogue(_SINGLE_PAGE_DIR)
	_list.open()

	assert_false(_list._header_lbl.text.contains("Page"), "3 entries fit on one page")
	var before := _list._items.size()
	_list.page(1)
	assert_eq(_list._items.size(), before, "paging a single-page catalogue changes nothing")


## NOTE: GUT reports orphans for this test and test_navigate_is_bounded_by_current_page_row_count
## below — each page() call frees the previous page's rows via _clear_items()'s queue_free(),
## which doesn't flush before the test ends. Same pre-existing shape as
## test_module_list_lock.gd's documented ModuleList orphans; harmless in play (page changes are
## frames apart), not something this test can avoid by awaiting a frame (test_module_list_lock.gd
## already found that doesn't change the count).
func test_multi_page_catalogue_shows_suffix_and_page_advances_and_wraps() -> void:
	_use_catalogue(_MULTI_PAGE_DIR)
	_list.open()

	assert_string_contains(_list._header_lbl.text, "Page 1/2", "10 entries over PAGE_SIZE=8")
	assert_eq(_list._items.size(), 8, "first page holds PAGE_SIZE rows")

	_list.page(1)
	assert_string_contains(_list._header_lbl.text, "Page 2/2")
	assert_eq(_list._items.size(), 2, "second page holds the remaining 2 rows")

	_list.page(1)
	assert_string_contains(_list._header_lbl.text, "Page 1/2", "paging past the last page wraps")


func test_navigate_is_bounded_by_current_page_row_count() -> void:
	_use_catalogue(_MULTI_PAGE_DIR)
	_list.open()
	_list.page(1)  # second page: 2 rows

	_list.navigate(1)
	_list.navigate(1)
	_list.navigate(1)  # three pushes past a 2-row page

	assert_eq(_list._cursor_row, 1, "cursor clamps to the last row of the shorter page")


func test_reading_shows_real_body_for_unlocked_and_placeholder_for_locked() -> void:
	_use_catalogue(_SINGLE_PAGE_DIR)
	LogState.collect_next()  # entry_beta
	_list.open()

	assert_eq(_list._body_lbl.text, "Fixture body text for beta.",
		"cursor starts on the unlocked first row")

	_list.navigate(1)  # entry_gamma, locked
	assert_string_contains(_list._body_lbl.text, "LOCKED",
		"a locked row's real body must never be shown")
	assert_eq(_list._body_lbl.text.find("Fixture body text"), -1,
		"the real fixture body text must not leak through a locked row")


func test_empty_catalogue_boundary() -> void:
	_use_catalogue(_EMPTY_DIR)

	_list.open()

	assert_eq(_list._items.size(), 0)
	assert_string_contains(_list._header_lbl.text, "0 / 0")
	assert_ne(_list._body_lbl.text.find("catalogued"), -1,
		"empty catalogue shows a placeholder body, not a crash or blank label")
	## Boundary: navigating/paging an empty list must not error.
	_list.navigate(1)
	_list.page(1)
