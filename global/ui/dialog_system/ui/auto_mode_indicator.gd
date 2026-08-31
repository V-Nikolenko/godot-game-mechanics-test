## AutoModeIndicator — small "AUTO" pill that pulses while autoplay is on.
class_name AutoModeIndicator
extends Label

const _PULSE_SEC := 0.9

var _tween: Tween


func _ready() -> void:
	text = "AUTO"
	add_theme_color_override("font_color", Color(0.6, 0.95, 0.7, 1.0))
	add_theme_font_size_override("font_size", 10)
	visible = false


func set_active(on: bool) -> void:
	visible = on
	if _tween:
		_tween.kill()
		_tween = null
	if on:
		modulate.a = 1.0
		_tween = create_tween().set_loops()
		_tween.tween_property(self, "modulate:a", 0.4, _PULSE_SEC)
		_tween.tween_property(self, "modulate:a", 1.0, _PULSE_SEC)
