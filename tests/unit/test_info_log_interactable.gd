## Characterization/intent tests for InfoLogInteractable — the re-readable environmental
## message (a tablet, terminal, or scrap of hull). Unlike PickupBase's collectibles, this
## never frees itself and never touches LogState.
##
## No test here starts a real, non-empty DialogPlayer.play() coroutine — see the sibling
## lore-log-pickup task's stuck review (docs/plans/flying-into-a-log-record-in-open-space-
## picks-it-up-and-tells/4-review.md) for why that leaves a permanently-suspended
## GDScriptFunctionState invisible to the gate. Message content and the busy-guard are
## asserted via _build_script() and a pre-armed DialogPlayer.is_active instead.
extends GutTest

const PlayerStub := preload("res://tests/helpers/player_stub.gd")
const SCENE: PackedScene = preload("res://global/interactables/scenes/info_log_interactable.tscn")


func after_each() -> void:
	DialogPlayer.is_active = false


func _make_interact_press() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	return event


func test_prompt_is_hidden_until_player_enters_range() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	assert_false(interactable._prompt.visible)


func test_entering_range_shows_prompt_and_leaving_hides_it() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	interactable._on_body_entered(player)
	assert_true(interactable._prompt.visible, "prompt shows once the player is in range")

	interactable._on_body_exited(player)
	assert_false(interactable._prompt.visible, "prompt hides once the player leaves range")


func test_a_non_player_body_is_ignored() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	var rock := Node2D.new()
	add_child_autofree(rock)

	interactable._on_body_entered(rock)

	assert_false(interactable._prompt.visible, "a non-player overlap never shows the prompt")
	assert_true(interactable._in_range.is_empty())


func test_interact_while_out_of_range_does_nothing() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	interactable.message = "Something worth reading."

	interactable._unhandled_input(_make_interact_press())

	assert_false(DialogPlayer.is_active, "_read() is never reached without a player in range")


func test_interact_is_blocked_while_dialog_player_is_already_busy() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	interactable.message = "Something worth reading."
	var player := PlayerStub.spawn()
	add_child_autofree(player)
	interactable._on_body_entered(player)

	DialogPlayer.is_active = true
	interactable._unhandled_input(_make_interact_press())

	assert_true(DialogPlayer.is_active, "guard leaves the pre-existing state untouched")
	assert_null(DialogPlayer._current_script, "no real play() call was ever made")


func test_build_script_shapes_the_message_as_an_instant_inner_thought() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)

	var script_res: DialogScriptResource = interactable._build_script("Found: a data tablet.")

	assert_eq(script_res.lines.size(), 1)
	assert_eq(script_res.lines[0].text, "Found: a data tablet.")
	assert_eq(script_res.lines[0].side, DialogLineResource.Side.INNER_THOUGHT)
	assert_eq(script_res.lines[0].reveal, DialogLineResource.Reveal.INSTANT)
	assert_false(script_res.pause_gameplay, "an info-log message must not pause the mission")


func test_reading_twice_is_idempotent_and_does_not_free_the_node() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	interactable.message = "Found: a data tablet."

	var first: DialogScriptResource = interactable._build_script(interactable.message)
	var second: DialogScriptResource = interactable._build_script(interactable.message)

	assert_eq(first.lines[0].text, second.lines[0].text, "the same message reads the same twice")
	assert_false(interactable.is_queued_for_deletion(), "reading never consumes the interactable")
	assert_eq(interactable.message, "Found: a data tablet.", "reading never mutates the message")


func test_reading_never_touches_log_state() -> void:
	var before: int = LogState.collected_count()
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	interactable.message = "Found: a data tablet."

	interactable._build_script(interactable.message)
	interactable._build_script(interactable.message)

	assert_eq(LogState.collected_count(), before, "an information log never advances LogState")


func test_boundary_empty_message_never_starts_a_dialog() -> void:
	var interactable := SCENE.instantiate() as InfoLogInteractable
	add_child_autofree(interactable)
	interactable.message = ""
	var player := PlayerStub.spawn()
	add_child_autofree(player)
	interactable._on_body_entered(player)

	interactable._unhandled_input(_make_interact_press())

	assert_false(DialogPlayer.is_active, "empty message returns before play() is ever called")
