## Characterization tests for the DialogPlayer autoload.
##
## DialogPlayer drives a DialogBox UI scene and is `await`-driven end to end, so
## these tests cover the parts that are reachable without simulating a full
## typewriter run: the idle contract, the guard clauses on play(), and the
## signal surface every cutscene binds to.
extends GutTest

const DialogPlayerScript := preload("res://global/autoload/dialog_player.gd")


func before_each() -> void:
	## Every test below assumes DialogPlayer is idle; fail fast rather than
	## producing a confusing downstream failure if a previous test left it running.
	assert_false(DialogPlayer.is_active, "DialogPlayer starts each test idle")


func test_the_live_autoload_matches_the_script() -> void:
	assert_eq(DialogPlayer.get_script(), DialogPlayerScript)


func test_idle_defaults() -> void:
	assert_false(DialogPlayer.is_active, "not active until play() is called")
	assert_false(DialogPlayer.auto_mode, "autoplay is off by default")


func test_it_always_processes_so_it_works_while_the_tree_is_paused() -> void:
	## Dialog scripts with pause_gameplay set pause the tree; the player itself
	## must keep running or it would deadlock waiting on its own box.
	assert_eq(DialogPlayer.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_it_owns_a_dialog_box_child() -> void:
	assert_not_null(DialogPlayer._box, "the dialog box is instantiated in _ready")
	assert_eq(DialogPlayer._box.get_parent(), DialogPlayer)


func test_signal_surface() -> void:
	for name: String in ["dialog_started", "line_changed", "dialog_finished"]:
		assert_true(DialogPlayer.has_signal(name), "DialogPlayer declares '%s'" % name)


func test_play_with_null_is_ignored() -> void:
	DialogPlayer.play(null)              ## push_warning, no state change
	assert_false(DialogPlayer.is_active)


func test_play_with_an_empty_script_is_ignored() -> void:
	var empty := DialogScriptResource.new()
	empty.lines = []
	DialogPlayer.play(empty)             ## push_warning, no state change
	assert_false(DialogPlayer.is_active)


func test_skip_while_idle_is_a_no_op() -> void:
	DialogPlayer.skip_dialog()
	assert_false(DialogPlayer.is_active)


func test_hold_timings_are_stable() -> void:
	## These constants are the feel of the dialog controls; pin them so a tweak
	## is a deliberate, reviewed change.
	assert_eq(DialogPlayerScript._HOLD_SKIP_SEC, 2.0, "hold-accept to skip the scene")
	assert_eq(DialogPlayerScript._HOLD_AUTO_SEC, 0.5, "hold-auto to toggle autoplay")
	assert_eq(DialogPlayerScript._AUTO_BASE_SEC, 0.6, "autoplay base dwell")
	assert_eq(DialogPlayerScript._AUTO_PER_CHAR, 0.045, "autoplay dwell per character")
