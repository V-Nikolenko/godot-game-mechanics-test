## DialogPlayer — global runner for DialogScriptResources.
extends Node

const _DIALOG_BOX_SCENE: PackedScene = preload("res://dialog/ui/dialog_box.tscn")

signal dialog_started(script: DialogScriptResource)
signal line_changed(line: DialogLineResource, index: int)
signal dialog_finished(was_skipped: bool)

## True between dialog_started and dialog_finished. Player controllers gate input on this.
var is_active: bool = false

## True when autoplay is on. Toggled by hold-X.
var auto_mode: bool = false

const _HOLD_SKIP_SEC: float = 2.0
const _HOLD_AUTO_SEC: float = 0.5
const _AUTO_BASE_SEC: float = 0.6
const _AUTO_PER_CHAR: float = 0.045
var _accept_held_since: float = -1.0
var _auto_held_since: float = -1.0

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
	_accept_held_since = -1.0
	_auto_held_since = -1.0
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

		# Race: line_finished (player advance/skip) vs. auto-dwell timer (if auto_mode).
		if auto_mode:
			var dwell: float = _AUTO_BASE_SEC + line.text.length() * _AUTO_PER_CHAR + line.post_delay
			var auto_timer := get_tree().create_timer(dwell)
			var winner: int = await _race_line_or_timer(_box.line_finished, auto_timer.timeout)
			if winner == 1 and not _was_skipped:
				_box.advance()
				await _box.line_finished
		else:
			await _box.line_finished

		if _was_skipped:
			break

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
	auto_mode = false
	_box.set_auto_indicator(false)
	if script != null and script.pause_gameplay:
		get_tree().paused = false
	dialog_finished.emit(_was_skipped)


func _process(_delta: float) -> void:
	if not is_active or _accept_held_since < 0.0:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _accept_held_since
	_box.set_hold_progress(held / _HOLD_SKIP_SEC)
	if held >= _HOLD_SKIP_SEC:
		_accept_held_since = -1.0
		_box.set_hold_progress(0.0)
		skip_dialog()


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
	elif event.is_action_pressed("dialog_auto"):
		_auto_held_since = Time.get_ticks_msec() / 1000.0
		get_viewport().set_input_as_handled()
	elif event.is_action_released("dialog_auto") and _auto_held_since >= 0.0:
		var held := Time.get_ticks_msec() / 1000.0 - _auto_held_since
		_auto_held_since = -1.0
		if held >= _HOLD_AUTO_SEC:
			auto_mode = not auto_mode
			_box.set_auto_indicator(auto_mode)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("shoot"):
		get_viewport().set_input_as_handled()
		_handle_advance_press()


func _handle_advance_press() -> void:
	if _box.is_typing():
		_box.skip_typing()
	elif _box.is_ready_to_advance():
		_box.advance()


## Returns 0 if sig_a fires first, 1 if sig_b fires first.
## Disconnects the losing connection after the race resolves.
func _race_line_or_timer(sig_a: Signal, sig_b: Signal) -> int:
	var done := false
	var winner: int = -1
	var resume: Callable
	resume = func(idx: int) -> void:
		if done: return
		done = true
		winner = idx
	var cb_a: Callable = func() -> void: resume.call(0)
	var cb_b: Callable = func() -> void: resume.call(1)
	sig_a.connect(cb_a, CONNECT_ONE_SHOT)
	sig_b.connect(cb_b, CONNECT_ONE_SHOT)
	while winner == -1:
		await get_tree().process_frame
	# Disconnect the loser's pending one-shot (if it hasn't fired yet).
	if sig_a.is_connected(cb_a): sig_a.disconnect(cb_a)
	if sig_b.is_connected(cb_b): sig_b.disconnect(cb_b)
	return winner
