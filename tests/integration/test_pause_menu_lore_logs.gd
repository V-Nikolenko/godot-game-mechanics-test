## INTENT tests for the Lore Logs option added to PauseMenu (global/ui/pause_menu/pause_menu.gd).
## New wiring, so this asserts what should happen, not what used to — there was no PauseMenu test
## before this task.
##
## PauseMenu pauses the SceneTree on open (get_tree().paused = true), which would freeze the GUT
## runner itself if driven through real _try_open()/_confirm(0..2) input. These tests avoid that
## entirely: they call _confirm() directly after setting _cursor, the same "call the private method
## a real input event would have reached" technique tests/unit/test_info_log_interactable.gd uses
## for _unhandled_input(). Nothing here ever sets get_tree().paused, so there is nothing to restore.
extends GutTest

const MISSION_SCENE:    PackedScene = preload("res://global/ui/pause_menu/pause_menu.tscn")
const OPEN_SPACE_SCENE: PackedScene = preload("res://global/ui/pause_menu/open_space_pause_menu.tscn")

var _menu: PauseMenu


func before_each() -> void:
	_menu = MISSION_SCENE.instantiate() as PauseMenu
	add_child_autofree(_menu)
	_menu.visible = true  ## Skip _try_open(): no tree pause, no camera/HUD side effects.


func test_lore_logs_option_is_visible_and_labelled_in_mission_mode() -> void:
	assert_true(_menu._options[3].visible)
	assert_eq(_menu._options[3].get_node("Label").text, "Lore Logs")


func test_lore_logs_option_is_visible_in_open_space_mode_too() -> void:
	_menu.queue_free()
	_menu = OPEN_SPACE_SCENE.instantiate() as PauseMenu
	add_child_autofree(_menu)
	_menu.visible = true

	assert_true(_menu._options[3].visible, "Lore Logs is not gated by mission_mode")
	assert_false(_menu._options[1].visible, "Restart Mission stays hidden in open space")
	assert_false(_menu._options[2].visible, "Exit Mission stays hidden in open space")


func test_confirming_lore_logs_opens_the_reader_and_hides_the_option_list() -> void:
	_menu._cursor = 3
	_menu._confirm()

	assert_true(_menu._lore_logs_open)
	assert_true(_menu._lore_log_list.visible)
	assert_false(_menu._menu_container.visible)
	assert_true(_menu.visible, "the pause menu itself must stay open, only the option list hides")


func test_cancel_while_reader_open_closes_it_without_closing_the_pause_menu() -> void:
	_menu._cursor = 3
	_menu._confirm()

	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	_menu._unhandled_input(cancel)

	assert_false(_menu._lore_logs_open, "one ESC closes the reader, not the whole menu")
	assert_true(_menu._menu_container.visible, "the option list is restored")
	assert_true(_menu.visible, "the pause menu is still open")


func test_menu_confirm_while_reader_open_does_not_reopen_it_or_reach_the_pause_menu_confirm() -> void:
	_menu._cursor = 3
	_menu._confirm()
	assert_true(_menu._lore_logs_open)

	var confirm := InputEventAction.new()
	confirm.action = "menu_confirm"
	confirm.pressed = true
	_menu._unhandled_input(confirm)

	## Still open (not toggled shut), and _cursor untouched — a leaking confirm would have called
	## _confirm() again on cursor 3, which is harmless here only by accident (it would re-run
	## _open_lore_logs()); the real risk this guards is a future option at cursor 3 doing something
	## that is NOT idempotent.
	assert_true(_menu._lore_logs_open, "reader stays open — confirm must not fall through")
	assert_eq(_menu._cursor, 3)


func test_exit_game_is_now_at_index_4() -> void:
	assert_eq(_menu._options[4].get_node("Label").text, "Exit Game")
