## DialogPlayer — global runner for DialogScriptResources.
## This skeleton handles the lifecycle and is_active flag; the UI is wired in
## a later task. play() prints to stdout for now so we can verify the flow.
extends Node

signal dialog_started(script: DialogScriptResource)
signal line_changed(line: DialogLineResource, index: int)
signal dialog_finished(was_skipped: bool)

## True between dialog_started and dialog_finished. Player controllers gate input on this.
var is_active: bool = false

## True when autoplay is on. Toggled by hold-X (registered in a later task).
var auto_mode: bool = false

var _current_script: DialogScriptResource
var _current_index: int = 0
var _was_skipped: bool = false


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
	print("[DialogPlayer] START %s (%d lines)" % [script.script_id, script.lines.size()])

	for i in script.lines.size():
		if _was_skipped:
			break
		_current_index = i
		var line: DialogLineResource = script.lines[i]
		line_changed.emit(line, i)
		print("[DialogPlayer]   line %d: %s" % [i, line.text])
		# Skeleton: simulate "line displayed" by waiting one frame.
		# Real wiring in Task 9 awaits the UI's line_finished signal.
		await get_tree().process_frame

	_finish()


## Stop the current dialog immediately. Used by hold-Space and external skips.
func skip_dialog() -> void:
	if not is_active:
		return
	_was_skipped = true


func _finish() -> void:
	var script := _current_script
	_current_script = null
	is_active = false
	if script != null and script.pause_gameplay:
		get_tree().paused = false
	print("[DialogPlayer] END (skipped=%s)" % _was_skipped)
	dialog_finished.emit(_was_skipped)
