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

var _box: DialogBox
var _current_script: DialogScriptResource
var _current_index: int = 0
var _was_skipped: bool = false


func _ready() -> void:
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
