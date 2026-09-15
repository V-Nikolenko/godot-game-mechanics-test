## Integrity test over the test suite itself: every `test_*.gd` under `res://tests` must be a
## script GUT can actually run.
##
## GUT fails *open* on a test script it cannot use. `test_collector.gd:131` drops such a script
## with nothing but a `[GUT WARNING]` line, the run summary reports a smaller `Scripts` count,
## and GUT still prints `---- All tests passed! ----` and exits 0. The gate
## (`/agent/verify.sh` step 3) checks the exit code and greps for `^N failing`, so **neither
## signal fires**: a test file broken by a rename or a deleted symbol silently vanishes from the
## suite while the gate stays green. That is how `test_space_station.gd` disappeared once —
## the parse errors went to stderr and GUT's verdict never mentioned them.
##
## This file closes that hole from inside the suite, so it works for any runner (the gate, CI, a
## human at a terminal) rather than only for the one shell script. A script GUT would silently
## drop now fails a real test, which turns the exit code red the way it always should have been.
##
## Like `test_resource_uid_integrity.gd`, this is NOT a characterization test — it asserts a
## property that must hold, so a failure here is a regression to fix.
##
## Note that a script with a parse error still `load()`s to a non-null `GDScript`: the giveaway is
## `can_instantiate() == false`, an empty base-script chain and an empty
## `get_instance_base_type()`. Checking for null would catch nothing.
##
## `addons/` is not walked: vendored third-party tests are not ours to police, and the gate does
## not run them.
extends GutTest

## The script every GUT test must ultimately extend. `class_name GutTest` resolves to this file,
## so a test written as `extends GutTest` and one written as `extends "res://addons/gut/test.gd"`
## produce the same base-script chain.
const GUT_TEST_SCRIPT := "res://addons/gut/test.gd"

const TESTS_ROOT := "res://tests"

## Mirrors GUT's own collection rules — `gut_config.gd:45` defaults `prefix` to `test_`, and the
## gate passes no `-gprefix`. Keep these in step with the command in `tests/README.md`.
const TEST_PREFIX := "test_"
const TEST_SUFFIX := ".gd"

## Every test script path GUT is expected to collect.
var _test_scripts: Array[String] = []


func before_all() -> void:
	_test_scripts = _collect_test_scripts(TESTS_ROOT)
	_test_scripts.sort()


## Recursive walk of `res://tests` returning every path GUT would try to collect.
func _collect_test_scripts(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				found.append_array(_collect_test_scripts(full))
		elif entry.begins_with(TEST_PREFIX) and entry.ends_with(TEST_SUFFIX):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## The chain of base scripts above `script`, outermost last. Empty when the script failed to
## compile or extends a native class directly.
func _base_script_paths(script: GDScript) -> Array[String]:
	var chain: Array[String] = []
	var base := script.get_base_script()
	while base != null:
		chain.append(base.resource_path)
		base = base.get_base_script()
	return chain


func test_the_walk_actually_found_the_suite() -> void:
	# Without this every test below would pass trivially if the walk ever broke.
	assert_gt(_test_scripts.size(), 20,
		"expected well over 20 test_*.gd files under %s, found %d"
		% [TESTS_ROOT, _test_scripts.size()])
	assert_has(_test_scripts, "res://tests/integration/test_suite_integrity.gd",
		"the walk should find this very file")


func test_every_test_script_compiles() -> void:
	# A script that does not compile is the exact case GUT drops with only a warning.
	var broken: Array[String] = []
	for path: String in _test_scripts:
		var script := load(path) as GDScript
		if script == null:
			broken.append("%s -> did not load as a GDScript at all" % path)
		elif not script.can_instantiate():
			broken.append("%s -> compiled with errors (see the Parse Error lines above)" % path)
	assert_eq(broken, [] as Array[String],
		"test scripts GUT would silently skip because they do not compile:\n  "
		+ "\n  ".join(broken))


func test_every_test_script_extends_gut_test() -> void:
	# The other half of GUT's skip condition: a `test_*.gd` that compiles but is not a GutTest is
	# collected as zero tests and reported only as `[GUT WARNING]: Ignoring script ...`.
	var not_a_gut_test: Array[String] = []
	for path: String in _test_scripts:
		var script := load(path) as GDScript
		# Scripts that failed to compile have no base chain to inspect; they are already reported
		# by test_every_test_script_compiles and would only duplicate the noise here.
		if script == null or not script.can_instantiate():
			continue
		if not _base_script_paths(script).has(GUT_TEST_SCRIPT):
			not_a_gut_test.append("%s -> extends %s"
				% [path, script.get_instance_base_type()])
	assert_eq(not_a_gut_test, [] as Array[String],
		"test scripts GUT would silently skip because they do not extend GutTest"
		+ " (a helper belongs in tests/helpers/ under a name that does not start with '%s'):\n  "
		% TEST_PREFIX + "\n  ".join(not_a_gut_test))
