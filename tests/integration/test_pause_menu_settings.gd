## INTENT tests for the Settings option and SettingsPanel sub-overlay added to PauseMenu
## (global/ui/pause_menu/pause_menu.gd + global/ui/pause_menu/settings_panel.gd).
## New wiring, so this asserts what should happen, not what used to.
##
## Same technique as test_pause_menu_lore_logs.gd: PauseMenu pauses the SceneTree on open, which
## would freeze the GUT runner, so these tests never call _try_open() — they set _cursor and call
## _confirm() directly, the "call the private method a real input event would have reached"
## technique. Nothing here ever sets get_tree().paused.
##
## Sandboxed: confirming and cycling the row write to the LIVE SettingsState autoload, which saves
## to user://settings.cfg. The live scheme is also restored in after_all, because the autoload's
## in-memory value outlives the file restore for the rest of the suite run.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const MISSION_SCENE:    PackedScene = preload("res://global/ui/pause_menu/pause_menu.tscn")
const OPEN_SPACE_SCENE: PackedScene = preload("res://global/ui/pause_menu/open_space_pause_menu.tscn")

var _sandbox := SaveSandbox.new()
var _menu: PauseMenu
var _scheme_before: StringName


func before_all() -> void:
	_sandbox.capture()
	_scheme_before = SettingsState.get_open_space_scheme()


func after_all() -> void:
	SettingsState.set_open_space_scheme(_scheme_before)
	_sandbox.restore()


func before_each() -> void:
	SettingsState.set_open_space_scheme(&"mouse")
	_menu = MISSION_SCENE.instantiate() as PauseMenu
	add_child_autofree(_menu)
	_menu.visible = true  ## Skip _try_open(): no tree pause, no camera/HUD side effects.


func _swap_to_open_space_menu() -> void:
	_menu.queue_free()
	_menu = OPEN_SPACE_SCENE.instantiate() as PauseMenu
	add_child_autofree(_menu)
	_menu.visible = true


func _send(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_menu._unhandled_input(ev)


## ── The rows ────────────────────────────────────────────────────────────────

func test_settings_is_index_4_and_exit_game_moved_to_index_5_in_mission_mode() -> void:
	assert_eq(_menu._options.size(), 6, "the option list grew by exactly one row")
	assert_true(_menu._options[4].visible)
	assert_eq(_menu._options[4].get_node("Label").text, "Settings")
	assert_eq(_menu._options[5].get_node("Label").text, "Exit Game")


func test_settings_row_is_present_in_open_space_mode_too() -> void:
	## It is a stored preference, not a mode-local toggle: hiding it outside the hub would mean
	## flying back to the hub to change your controls. Asserted on indices 4 and 5 specifically —
	## open_space_pause_menu.tscn's Option1/Option2 are bare Node2Ds with no Label child, so a
	## loop over _options calling get_node("Label") would crash on this scene.
	_swap_to_open_space_menu()

	assert_true(_menu._options[4].visible, "Settings is not gated by mission_mode")
	assert_eq(_menu._options[4].get_node("Label").text, "Settings")
	assert_eq(_menu._options[5].get_node("Label").text, "Exit Game")


## ── Opening / closing the sub-overlay ───────────────────────────────────────

func test_confirming_settings_opens_the_panel_and_hides_the_option_list() -> void:
	_menu._cursor = 4
	_menu._confirm()

	assert_true(_menu._settings_open)
	assert_true(_menu._settings_panel.visible)
	assert_false(_menu._menu_container.visible)
	assert_true(_menu.visible, "the pause menu itself must stay open, only the option list hides")


func test_cancel_while_panel_open_closes_it_without_closing_the_pause_menu() -> void:
	_menu._cursor = 4
	_menu._confirm()

	_send("ui_cancel")

	assert_false(_menu._settings_open, "one ESC closes the panel, not the whole menu")
	assert_false(_menu._settings_panel.visible)
	assert_true(_menu._menu_container.visible, "the option list is restored")
	assert_true(_menu.visible, "the pause menu is still open")


func test_menu_confirm_while_panel_open_does_not_fall_through_to_confirm() -> void:
	## The exact bug the lore-log branch was written to avoid: a leaking menu_confirm reaches
	## _confirm() on cursor 4 and re-opens the panel — or, worse, runs a future non-idempotent
	## action. Proven by cursor 5 (Exit Game): if the confirm fell through, the suite would quit.
	_menu._cursor = 4
	_menu._confirm()
	assert_true(_menu._settings_open)

	_menu._cursor = 5  ## Exit Game — a fall-through here would kill the test run outright.
	_send("menu_confirm")

	assert_true(_menu._settings_open, "panel stays open — confirm must not fall through")
	assert_eq(_menu._cursor, 5, "the option cursor is untouched while the panel owns input")


## ── The row actually does something ─────────────────────────────────────────

func test_menu_right_on_the_steering_row_flips_the_live_setting_and_the_value_label() -> void:
	## THE PLACEMENT-ONLY TRAP: a settings row whose handler is empty passes every "is it visible
	## and labelled" assertion above. This case drives the live autoload, the same lesson
	## test_weapon_unlock_sources.gd records for pickups.
	_menu._cursor = 4
	_menu._confirm()
	assert_eq(SettingsState.get_open_space_scheme(), &"mouse", "precondition")

	_send("menu_right")

	assert_eq(SettingsState.get_open_space_scheme(), &"keys",
			"menu_right cycles the stored scheme, not just a local variable")
	assert_eq(_menu._settings_panel._value_lbl.text, "Classic (A/D)",
			"the row's value label follows the store")

	_send("menu_right")

	assert_eq(SettingsState.get_open_space_scheme(), &"mouse", "the two values wrap")
	assert_eq(_menu._settings_panel._value_lbl.text, "Mouse Aim")


func test_menu_left_cycles_the_other_way() -> void:
	_menu._cursor = 4
	_menu._confirm()

	_send("menu_left")

	assert_eq(SettingsState.get_open_space_scheme(), &"keys")
	assert_eq(_menu._settings_panel._value_lbl.text, "Classic (A/D)")


func test_panel_reflects_a_value_changed_behind_its_back_before_open() -> void:
	## BOUNDARY. The panel is instantiated with the scene, long before it is opened, so its label
	## must be built from the store at open() time and not once at _ready().
	SettingsState.set_open_space_scheme(&"keys")

	_menu._cursor = 4
	_menu._confirm()

	assert_eq(_menu._settings_panel._value_lbl.text, "Classic (A/D)",
			"open() re-reads SettingsState rather than trusting a stale label")
