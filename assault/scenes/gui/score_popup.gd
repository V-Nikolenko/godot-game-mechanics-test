## ScorePopup — transient floating label.
##
## A pool of these lives under the HUD root. ScorePopupSpawner instantiates
## a fresh popup for each EventBus.score_event and frees it when its tween
## finishes.
##
## "Highlight" reasons (survival, wave_clear, skill_clean) get a larger font,
## a longer float, and an extended lifetime so they're unmissable.
class_name ScorePopup
extends Node2D

const _LIFETIME: float = 1.0
const _FLOAT_DISTANCE: float = 30.0

## Reasons that deserve extra visual emphasis.
const _HIGHLIGHT_REASONS: Array[String] = ["survival", "wave_clear", "skill_clean"]
const _HIGHLIGHT_FONT_SIZE: int = 22
const _HIGHLIGHT_LIFETIME: float = 1.8
const _HIGHLIGHT_FLOAT: float = 60.0
const _DEFAULT_FONT_SIZE: int = 14

@onready var _label: Label = $Label

func show_for(world_pos: Vector2, points: int, reason: String) -> void:
	# Convert from world-space (kill location) into HUD CanvasLayer space.
	var cam := get_viewport().get_camera_2d()
	var screen_pos: Vector2 = world_pos
	if cam:
		var size: Vector2 = get_viewport().get_visible_rect().size
		screen_pos = world_pos - cam.global_position + size * 0.5
	position = screen_pos

	_label.text = _format_text(points, reason)
	_label.modulate = _color_for(reason)

	var is_highlight: bool = reason in _HIGHLIGHT_REASONS
	var lifetime: float = _HIGHLIGHT_LIFETIME if is_highlight else _LIFETIME
	var float_dist: float = _HIGHLIGHT_FLOAT if is_highlight else _FLOAT_DISTANCE
	_label.add_theme_font_size_override("font_size",
			_HIGHLIGHT_FONT_SIZE if is_highlight else _DEFAULT_FONT_SIZE)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position:y", position.y - float_dist, lifetime)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_label, "modulate:a", 0.0, lifetime)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)

func _format_text(points: int, reason: String) -> String:
	match reason:
		"wave_clear":
			return "WAVE! +%d" % points
		"survival":
			return "SAFE +%d" % points
		"bonus_target":
			return "BONUS +%d" % points
		"skill_clean":
			return "PERFECT! +%d" % points
		"skill_partial":
			return "SURVIVED +%d" % points
		_:
			return "+%d" % points

func _color_for(reason: String) -> Color:
	match reason:
		"wave_clear":     return Color(1.0, 0.85, 0.35, 1.0)
		"bonus_target":   return Color(1.0, 0.85, 0.35, 1.0)
		"survival":       return Color(0.6, 1.0, 0.6, 1.0)
		"skill_clean":    return Color(0.4, 1.0, 1.0, 1.0)
		"skill_partial":  return Color(0.9, 0.7, 0.4, 1.0)
		_:                return Color.WHITE
