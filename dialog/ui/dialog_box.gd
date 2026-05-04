## DialogBox — passive view driven by DialogPlayer.
##
## Displays one line at a time. Calls present_line(line) and waits for
## line_finished to fire (advance) or line_dismissed to fire (skip-typing-only,
## not used directly — DialogPlayer interprets it).
##
## State machine:
##   IDLE     — nothing showing
##   FADE_IN  — bar fading in, text empty
##   TYPING   — text revealing
##   READY    — text fully shown, awaiting advance
##   FADE_OUT — bar fading out
class_name DialogBox
extends CanvasLayer

signal line_finished       ## Player advanced past this line.
signal typing_completed    ## Typing animation just finished (used for autoplay).

enum State { IDLE, FADE_IN, TYPING, READY, FADE_OUT }

# ── Top bar ───────────────────────────────────────────────────────────────────
@onready var _top_bar: PanelContainer    = $TopBar
@onready var _top_portrait: TextureRect  = $TopBar/Margin/HBox/Portrait
@onready var _top_speaker: Label         = $TopBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _top_text: RichTextLabel    = $TopBar/Margin/HBox/TextCol/TextLabel

# ── Bottom bar ────────────────────────────────────────────────────────────────
@onready var _bot_bar: PanelContainer    = $BottomBar
@onready var _bot_portrait: TextureRect  = $BottomBar/Margin/HBox/Portrait
@onready var _bot_speaker: Label         = $BottomBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _bot_text: RichTextLabel    = $BottomBar/Margin/HBox/TextCol/TextLabel
@onready var _hold_arc: HoldProgressArc  = $BottomBar/Margin/HBox/HoldArc

const _FADE_SEC := 0.22

var _state: State = State.IDLE
var _active_bar: PanelContainer
var _active_text: RichTextLabel
var _typing_tween: Tween


func _ready() -> void:
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false


## Display one line. Awaitable — resolves when the player advances or skip fires.
func present_line(line: DialogLineResource) -> void:
	if _state != State.IDLE:
		push_warning("[DialogBox] present_line while not IDLE; forcing close.")
		_force_close()

	# Pick the bar based on side.
	match line.side:
		DialogLineResource.Side.OTHER_TOP:
			_active_bar = _top_bar
			_active_text = _top_text
			_top_portrait.texture = line.speaker.portrait if line.speaker else null
			_top_portrait.visible = _top_portrait.texture != null
			_top_speaker.text = line.speaker.display_name if line.speaker else ""
			_top_speaker.visible = not _top_speaker.text.is_empty()
			if line.speaker:
				_top_speaker.add_theme_color_override("font_color", line.speaker.name_color)
		DialogLineResource.Side.PLAYER_BOTTOM:
			_active_bar = _bot_bar
			_active_text = _bot_text
			_bot_portrait.texture = line.speaker.portrait if line.speaker else null
			_bot_portrait.visible = _bot_portrait.texture != null
			_bot_speaker.text = line.speaker.display_name if line.speaker else ""
			_bot_speaker.visible = not _bot_speaker.text.is_empty()
			if line.speaker:
				_bot_speaker.add_theme_color_override("font_color", line.speaker.name_color)
		DialogLineResource.Side.INNER_THOUGHT:
			_active_bar = _bot_bar
			_active_text = _bot_text
			_bot_portrait.visible = false
			_bot_speaker.visible = false

	# Wrap text in BBCode for inner thoughts.
	var display_text: String = line.text
	if line.side == DialogLineResource.Side.INNER_THOUGHT:
		display_text = "[i]%s[/i]" % line.text

	_active_text.bbcode_enabled = true
	_active_text.text = display_text
	_active_text.visible_ratio = 0.0

	# Fade the bar in.
	_state = State.FADE_IN
	_active_bar.modulate.a = 0.0
	_active_bar.visible = true
	var t_in := create_tween()
	t_in.tween_property(_active_bar, "modulate:a", 1.0, _FADE_SEC)
	await t_in.finished

	# Reveal the text.
	_state = State.TYPING
	match line.reveal:
		DialogLineResource.Reveal.TYPEWRITER:
			var duration: float = max(line.text.length() / max(line.typing_speed, 1.0), 0.05)
			_typing_tween = create_tween()
			_typing_tween.tween_property(_active_text, "visible_ratio", 1.0, duration)
			await _typing_tween.finished
		DialogLineResource.Reveal.FADE_IN:
			_active_text.visible_ratio = 1.0
			_active_text.modulate.a = 0.0
			var t := create_tween()
			t.tween_property(_active_text, "modulate:a", 1.0, 0.35)
			await t.finished
		DialogLineResource.Reveal.INSTANT:
			_active_text.visible_ratio = 1.0

	_state = State.READY
	typing_completed.emit()


## Called by DialogPlayer on tap-Space when the line is done typing.
func advance() -> void:
	if _state != State.READY:
		return
	_state = State.FADE_OUT
	var t_out := create_tween()
	t_out.tween_property(_active_bar, "modulate:a", 0.0, _FADE_SEC)
	t_out.finished.connect(_after_fade_out, CONNECT_ONE_SHOT)


## Called by DialogPlayer on tap-Space when typing is in progress.
## Completes the typing animation immediately.
func skip_typing() -> void:
	if _state != State.TYPING:
		return
	if _typing_tween:
		_typing_tween.kill()
	_active_text.visible_ratio = 1.0
	_active_text.modulate.a = 1.0
	_state = State.READY
	typing_completed.emit()


## Used by DialogPlayer.skip_dialog() — close everything immediately.
func close_now() -> void:
	if _state == State.IDLE:
		return
	_force_close()


## Read by DialogPlayer to know if it can advance.
func is_typing() -> bool:
	return _state == State.TYPING


func is_ready_to_advance() -> bool:
	return _state == State.READY


func set_hold_progress(ratio: float) -> void:
	if _hold_arc:
		_hold_arc.set_progress(ratio)


func _after_fade_out() -> void:
	if is_instance_valid(_active_bar):
		_active_bar.visible = false
	_state = State.IDLE
	line_finished.emit()


func _force_close() -> void:
	if _typing_tween:
		_typing_tween.kill()
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false
	_state = State.IDLE
	line_finished.emit()
