## Manually-run measurement: how many AI enemies die in level 1's laser columns (Enemy rework phase 8, t17; epic plan
## docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.16). NOT a GUT test (no `test_` prefix, so GUT never runs it, and
## GUT time is precious); `scripts/measure-level1-columns.sh` runs it headless:
##
##     godot --headless --path . -s tests/helpers/level1_column_replay.gd [-- <section> …]
##
## This file is only the launcher. A `SceneTree` script compiles before the autoloads are registered, so it must not name
## (or preload) anything that touches `EventBus`, `UpgradeState` and the rest; it loads the worker,
## `level1_column_replay_worker.gd`, at run time and adds it to the tree. The worker's header says what is measured and
## what the `RESULT` / `TOTAL` / `DONE` lines mean.
##
## No `class_name`: test-only.
extends SceneTree


func _initialize() -> void:
	var script := load("res://tests/helpers/level1_column_replay_worker.gd") as GDScript
	if script == null or not script.can_instantiate():
		printerr("level1_column_replay_worker.gd does not compile")
		quit(1)
		return
	var worker: Node = script.new()
	root.add_child.call_deferred(worker)
