## INVARIANT test over `BaseEnemy`'s conventions debt cleanup
## (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.10, task t6-base-enemy-debt).
##
## `test_base_enemy.gd` (t1) pins the class's live *behaviour* before the rework. This file checks
## the one piece of that debt cleanup with no behavioural signal to pin against: the death print
## must never reach stdout on a non-verbose run. `OS.is_stdout_verbose()` cannot be forced true from
## inside a GUT run, so this is a structural check of the source — the print call must sit as the
## direct, sole-statement body of an `if OS.is_stdout_verbose():` guard — rather than a captured-
## output test.
extends GutTest

const _BASE_ENEMY_SCRIPT := "res://assault/scenes/enemies/base_enemy.gd"


func test_death_print_is_gated_behind_is_stdout_verbose() -> void:
	var source := FileAccess.get_file_as_string(_BASE_ENEMY_SCRIPT)
	assert_false(source.is_empty(), "could not read %s" % _BASE_ENEMY_SCRIPT)

	# Matches an `if OS.is_stdout_verbose():` line immediately followed by a `print(...)` line
	# indented exactly one level deeper, so the print only reaches stdout inside that guard —
	# not merely somewhere later in the same function.
	var guard_re := RegEx.create_from_string(
		"(?m)^(\\t+)if OS\\.is_stdout_verbose\\(\\):\\n\\1\\tprint\\("
	)
	var guarded := guard_re.search(source)
	assert_not_null(
		guarded,
		"expected the death print to be the direct body of `if OS.is_stdout_verbose():` in %s" % _BASE_ENEMY_SCRIPT
	)

	# Boundary: today's (pre-fix) shape — the print as the direct body of `if current == 0:`, two
	# tabs deep, with no verbose guard at all — must NOT satisfy the guard regex above. Proven here
	# against a literal reconstruction of that shape, so this is not just "the current file passes".
	var ungated_shape := "func _on_health_changed(current: int) -> void:\n" + \
		"\tif current == 0:\n\t\tprint(\"[Enemy] %s DESPAWNED (died)\")\n"
	assert_null(
		guard_re.search(ungated_shape),
		"the guard regex must reject the un-gated (pre-fix) shape, or it would be vacuously true"
	)


func test_death_print_mentions_despawned_so_the_regex_is_checking_the_right_line() -> void:
	var source := FileAccess.get_file_as_string(_BASE_ENEMY_SCRIPT)
	assert_true(
		source.contains("DESPAWNED (died)"),
		"expected the known death-print text in %s — if it changed, update this test's target" % _BASE_ENEMY_SCRIPT
	)
