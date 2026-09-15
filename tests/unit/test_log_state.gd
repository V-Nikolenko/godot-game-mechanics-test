## Characterization + intent tests for LogState (global/autoloads/log_state.gd).
##
## LogState's catalogue is a directory sweep, not a hand list, so every test here points
## `catalogue_dir` at a fixture directory under tests/unit/fixtures/ rather than the (possibly
## empty, possibly content-authored-later) production directory.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const LogStateScript := preload("res://global/autoloads/log_state.gd")

const FIXTURE_DIR := "res://tests/unit/fixtures/log_entries"
const DUPLICATE_FIXTURE_DIR := "res://tests/unit/fixtures/log_entries_duplicate"

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


## Tree-less instance pointed at the fixture catalogue: `_ready()` never fires, so the
## caller decides when `_load_catalogue()` / `_load()` run.
func _fresh(dir: String = FIXTURE_DIR) -> Node:
	var ls := LogStateScript.new()
	ls.catalogue_dir = dir
	return ls


func test_total_count_is_derived_from_the_catalogue_directory() -> void:
	var ls := _fresh()
	ls._load_catalogue()
	assert_eq(ls.total_count(), 3, "3 fixture .tres files on disk, no hardcoded count")
	ls.free()


func test_catalogue_sorts_by_sequence_not_filename() -> void:
	## entry_a.tres has sequence=2, entry_b.tres sequence=0, entry_c.tres sequence=1 —
	## directory listing order (alphabetical by filename) disagrees with reading order.
	var ls := _fresh()
	ls._load_catalogue()
	var order: Array[StringName] = []
	for i in range(3):
		order.append(ls.collect_next())
	assert_eq(order, [&"entry_beta", &"entry_gamma", &"entry_alpha"] as Array[StringName])
	ls.free()


func test_collect_next_collects_in_order_and_reports_it() -> void:
	var ls := _fresh()
	ls._load_catalogue()
	var seen: Array[StringName] = []
	ls.log_collected.connect(func(id: StringName) -> void: seen.append(id))

	var collected: StringName = ls.collect_next()

	assert_eq(collected, &"entry_beta", "lowest sequence value goes first")
	assert_true(ls.is_collected(&"entry_beta"))
	assert_false(ls.is_collected(&"entry_gamma"))
	assert_false(ls.is_collected(&"entry_alpha"))
	assert_eq(seen, [&"entry_beta"] as Array[StringName])
	ls.free()


## Boundary: once every entry is collected, further calls are a no-op, not an error —
## an anonymous pickup firing after 100% completion must not crash or double-collect.
func test_collect_next_is_idempotent_once_everything_is_collected() -> void:
	var ls := _fresh()
	ls._load_catalogue()
	for i in range(ls.total_count()):
		ls.collect_next()
	assert_eq(ls.collected_count(), ls.total_count())

	var seen: Array[StringName] = []
	ls.log_collected.connect(func(id: StringName) -> void: seen.append(id))
	var extra: StringName = ls.collect_next()

	assert_eq(extra, &"", "nothing left to collect")
	assert_eq(seen, [] as Array[StringName], "no signal for a no-op collect")
	assert_eq(ls.collected_count(), ls.total_count(), "count does not change")
	ls.free()


func test_collected_state_survives_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer._load_catalogue()
	writer.collect_next()  # entry_beta
	writer.collect_next()  # entry_gamma
	writer.free()

	var reader := _fresh()
	reader._load_catalogue()
	reader._load()

	assert_true(reader.is_collected(&"entry_beta"))
	assert_true(reader.is_collected(&"entry_gamma"))
	assert_false(reader.is_collected(&"entry_alpha"))
	reader.free()


func test_load_drops_unknown_ids_left_in_the_save_file() -> void:
	_sandbox.clear_all()
	var cfg := ConfigFile.new()
	cfg.set_value(LogStateScript.SECTION, "entry_beta", true)
	cfg.set_value(LogStateScript.SECTION, "a_log_that_was_removed", true)
	assert_eq(cfg.save(LogStateScript.SAVE_PATH), OK, "sandbox save file written")

	var ls := _fresh()
	ls._load_catalogue()
	ls._load()

	assert_true(ls.is_collected(&"entry_beta"), "known ids still load")
	assert_false(ls.is_collected(&"a_log_that_was_removed"), "unknown ids are dropped")
	assert_eq(ls.collected_count(), 1)
	ls.free()


func test_all_ids_returns_every_entry_in_catalogue_order_regardless_of_collection() -> void:
	var ls := _fresh()
	ls._load_catalogue()
	ls.collect_next()  # entry_beta

	assert_eq(ls.all_ids(), [&"entry_beta", &"entry_gamma", &"entry_alpha"] as Array[StringName],
		"collecting one entry must not shrink or reorder the full catalogue walk")
	ls.free()


func test_get_entry_returns_the_matching_resource() -> void:
	var ls := _fresh()
	ls._load_catalogue()

	var entry: LogEntryResource = ls.get_entry(&"entry_gamma")
	assert_not_null(entry)
	assert_eq(entry.title, "Test Entry Gamma")
	assert_eq(entry.body, "Fixture body text for gamma.")

	assert_null(ls.get_entry(&"not_a_real_entry"))
	ls.free()


## Boundary: two catalogue files sharing one id must not inflate the total or collapse
## two logical entries onto one collected flag.
func test_duplicate_catalogue_id_is_dropped_not_double_counted() -> void:
	var ls := _fresh(DUPLICATE_FIXTURE_DIR)
	ls._load_catalogue()
	assert_eq(ls.total_count(), 1, "duplicate id counted once, not twice")

	var collected: StringName = ls.collect_next()
	assert_eq(collected, &"dup_entry")
	assert_eq(ls.collect_next(), &"", "nothing left after the one surviving entry")
	ls.free()
