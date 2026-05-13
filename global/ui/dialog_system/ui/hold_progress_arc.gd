## HoldProgressArc — circular progress indicator for hold gestures.
## set_progress(0..1) → redraws arc.
class_name HoldProgressArc
extends Control

@export var radius: float = 7.0
@export var width: float = 2.0
@export var color: Color = Color(0.8, 0.95, 1.0, 0.9)
@export var bg_color: Color = Color(0.2, 0.3, 0.5, 0.4)

var _progress: float = 0.0


func set_progress(value: float) -> void:
	_progress = clamp(value, 0.0, 1.0)
	visible = _progress > 0.001
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	# Background ring
	draw_arc(c, radius, 0.0, TAU, 32, bg_color, width, true)
	# Foreground sweep
	if _progress > 0.0:
		draw_arc(c, radius, -PI * 0.5, -PI * 0.5 + TAU * _progress, 32, color, width, true)
