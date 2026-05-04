## DialogPlayer — global runner for DialogScriptResources.
extends Node

const _DIALOG_BOX_SCENE: PackedScene = preload("res://dialog/ui/dialog_box.tscn")

signal dialog_started(script: DialogScriptResource)
signal line_changed(line: DialogLineResource, index: int)
signal dialog_finished(was_skipped: bool)

## True between dialog_started and dialog_finished. Player controllers gate input on this.
var is_active: bool = false

## True when autoplay is on. Toggled in a later task by hold-X.
var auto_mode: bool = false

const _HOLD_SKIP_SEC: float = 2.0
var _accept_held_since: float = -1.0

var _box: DialogBox
var _current_script: DialogScriptResource
var _current_index: int = 0
var _was_skipped: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = _DIALOG_BOX_SCENE.instantiate()
	add_child(_box)


## Play a script start-to-finish. Awaitable — resolves on dialog_finished.
func play(script: DialogScriptResource) -> void:
	if is_active:
		push_warning("[DialogPlayer] play() called while already active; ignoring.")
		return
	if script == null or script.lines.is_empty():
		push_warning("[DialogPlayer] play() called with empty/null script; ignoring.")
		return

	_current_script = script
	_current_index = 0
	_was_skipped = false
	is_active = true

	if script.pause_gameplay:
		get_tree().paused = true

	dialog_started.emit(script)

	for i in script.lines.size():
		if _was_skipped:
			break
		_current_index = i
		var line: DialogLineResource = script.lines[i]
		line_changed.emit(line, i)
		await _box.present_line(line)
		await _box.line_finished
		if _was_skipped:
			break

	if _was_skipped:
		_box.close_now()
	_finish()


## Stop the current dialog immediately. Used by hold-Space and external skips.
func skip_dialog() -> void:
	if not is_active:
		return
	_was_skipped = true
	_box.close_now()


func _finish() -> void:
	var script := _current_script
	_current_script = null
	is_active = false
	if script != null and script.pause_gameplay:
		get_tree().paused = false
	dialog_finished.emit(_was_skipped)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event.is_action_pressed("ui_accept"):
		_accept_held_since = Time.get_ticks_msec() / 1000.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept") and _accept_held_since >= 0.0:
		var held := Time.get_ticks_msec() / 1000.0 - _accept_held_since
		_accept_held_since = -1.0
		_box.set_hold_progress(0.0)
		if held < _HOLD_SKIP_SEC:
			_handle_advance_press()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shoot"):
		get_viewport().set_input_as_handled()
		_handle_advance_press()


func _handle_advance_press() -> void:
	if _box.is_typing():
		_box.skip_typing()
	elif _box.is_ready_to_advance():
		_box.advance()
