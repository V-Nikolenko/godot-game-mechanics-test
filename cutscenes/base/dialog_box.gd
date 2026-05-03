## DialogBox — two-bar portrait dialog system.
##
## Layout:
##   Top bar    — other character: portrait on the LEFT, text on the right.
##   Bottom bar — main character:  text on the left, portrait on the RIGHT (mirrored).
##
## Usage (awaitable):
##   await dialog.present_top("Control", "Sector is hot. Watch yourself.", portrait_tex)
##   await dialog.present_bottom("Edith", "Copy. Engaging now.", edith_tex)
##
## Both bars are independent — you can call present_top and present_bottom in
## sequence (back-and-forth conversation) or overlap them via parallel coroutines.
class_name DialogBox
extends CanvasLayer

# ── Top bar nodes ─────────────────────────────────────────────────────────────
@onready var _top_bar: PanelContainer        = $TopBar
@onready var _top_portrait: TextureRect      = $TopBar/Margin/HBox/Portrait
@onready var _top_speaker: Label             = $TopBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _top_text: Label                = $TopBar/Margin/HBox/TextCol/TextLabel

# ── Bottom bar nodes ──────────────────────────────────────────────────────────
@onready var _bot_bar: PanelContainer        = $BottomBar
@onready var _bot_portrait: TextureRect      = $BottomBar/Margin/HBox/Portrait
@onready var _bot_speaker: Label             = $BottomBar/Margin/HBox/TextCol/SpeakerLabel
@onready var _bot_text: Label                = $BottomBar/Margin/HBox/TextCol/TextLabel

const _FADE_SEC := 0.25

func _ready() -> void:
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false


## Show one line in the TOP bar (other character, portrait on the left).
## Awaitable — resolves after the bar has fully faded out.
func present_top(speaker: String, text: String,
		portrait_tex: Texture2D = null, duration: float = 3.0) -> void:
	_top_portrait.texture = portrait_tex
	_top_portrait.visible = portrait_tex != null
	_top_speaker.text = speaker
	_top_speaker.visible = not speaker.is_empty()
	_top_text.text = text
	await _show_bar(_top_bar, duration)


## Show one line in the BOTTOM bar (main character, portrait on the right, mirrored).
## Awaitable — resolves after the bar has fully faded out.
func present_bottom(speaker: String, text: String,
		portrait_tex: Texture2D = null, duration: float = 3.0) -> void:
	_bot_portrait.texture = portrait_tex
	_bot_portrait.visible = portrait_tex != null
	_bot_speaker.text = speaker
	_bot_speaker.visible = not speaker.is_empty()
	_bot_text.text = text
	await _show_bar(_bot_bar, duration)


## Immediately hide both bars (called by cutscene skip logic).
func dismiss() -> void:
	_top_bar.modulate.a = 0.0
	_top_bar.visible = false
	_bot_bar.modulate.a = 0.0
	_bot_bar.visible = false


# ── Internal helpers ──────────────────────────────────────────────────────────
func _show_bar(bar: PanelContainer, duration: float) -> void:
	bar.modulate.a = 0.0
	bar.visible = true
	var t_in := create_tween()
	t_in.tween_property(bar, "modulate:a", 1.0, _FADE_SEC)
	await t_in.finished

	await get_tree().create_timer(duration).timeout

	var t_out := create_tween()
	t_out.tween_property(bar, "modulate:a", 0.0, _FADE_SEC)
	await t_out.finished
	bar.visible = false
