class_name OverheatBar
extends Node2D

const BAR_WIDTH  := 32.0
const BAR_HEIGHT := 4.0

var _percentage: float = 0.0

func setup(overheat: Overheat) -> void:
	overheat.overheat.connect(_on_overheat)
	visible = false

func _on_overheat(percentage: float) -> void:
	_percentage = percentage
	visible = percentage > 0.0
	queue_redraw()

func _draw() -> void:
	var x := -BAR_WIDTH * 0.5
	draw_rect(Rect2(x, 0, BAR_WIDTH, BAR_HEIGHT), Color(0.15, 0.15, 0.15, 0.85))
	var fill := BAR_WIDTH * (_percentage / 100.0)
	if fill > 0.0:
		var t := _percentage / 100.0
		var color := Color(1.0, lerp(0.55, 0.05, t), 0.0, 1.0)
		draw_rect(Rect2(x, 0, fill, BAR_HEIGHT), color)
