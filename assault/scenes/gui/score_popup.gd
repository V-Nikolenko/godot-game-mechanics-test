## ScorePopup — transient floating label.
##
## A pool of these lives under the HUD root. ScorePopupSpawner instantiates
## a fresh popup for each EventBus.score_event and frees it when its tween
## finishes.
class_name ScorePopup
extends Node2D

const _LIFETIME: float = 1.0
const _FLOAT_DISTANCE: float = 30.0

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

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "position:y", position.y - _FLOAT_DISTANCE, _LIFETIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_label, "modulate:a", 0.0, _LIFETIME)\
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
