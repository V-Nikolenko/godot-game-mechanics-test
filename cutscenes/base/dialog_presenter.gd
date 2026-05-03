## DialogPresenter — minimal subtitle UI for cutscenes.
## Fades a panel in, holds the text for `duration` seconds, fades it out.
## Future dialog systems (voice, choices, portraits) can replace the internals
## without changing the `present()` signature — every cutscene awaits this API.
class_name DialogPresenter
extends CanvasLayer

@onready var _panel: PanelContainer = $Panel
@onready var _speaker_label: Label = $Panel/Margin/VBox/SpeakerLabel
@onready var _text_label: Label = $Panel/Margin/VBox/TextLabel

const _FADE_SEC := 0.3

func _ready() -> void:
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.visible = false

## Show one line. Awaitable — completes after fade-out finishes.
## `speaker` may be empty (in which case the speaker line is hidden).
func present(speaker: String, text: String, duration: float = 2.5) -> void:
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_text_label.text = text
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_panel.visible = true

	var fade_in := create_tween()
	fade_in.tween_property(_panel, "modulate:a", 1.0, _FADE_SEC)
	await fade_in.finished

	await get_tree().create_timer(duration).timeout

	var fade_out := create_tween()
	fade_out.tween_property(_panel, "modulate:a", 0.0, _FADE_SEC)
	await fade_out.finished
	_panel.visible = false
