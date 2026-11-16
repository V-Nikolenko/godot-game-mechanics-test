## CarrierHangarDoors - the code-drawn doors of one Carrier hangar (Phase 10 §2.8 / §2.9, t8; placeholders until t9 draws the art). Two leaves
## that slide apart along the hangar's long axis (local y) as `open_amount` goes 0 -> 1; `broken` draws them torn and hanging open (the wreck).
## `CarrierHangars` writes both; the node redraws only when one changes. Visual only: no collision, no clock of its own.
class_name CarrierHangarDoors
extends Node2D

## The doorway's size (px): the leaves cover it when shut.
@export var size: Vector2 = Vector2(36.0, 44.0)
@export var leaf_color: Color = Color(0.32, 0.36, 0.46)
@export var seam_color: Color = Color(0.85, 0.75, 0.25)
@export var bay_color: Color = Color(0.05, 0.06, 0.1)
@export var broken_color: Color = Color(0.22, 0.2, 0.22)

## 0 = shut, 1 = fully open.
var open_amount: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, open_amount):
			open_amount = value
			queue_redraw()
## A wreck's doors: torn, hanging open.
var broken: bool = false:
	set(value):
		if value != broken:
			broken = value
			queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	draw_rect(Rect2(-half, size), bay_color)
	var leaf_h := half.y * (1.0 - open_amount)
	var color := broken_color if broken else leaf_color
	if leaf_h > 0.5:
		draw_rect(Rect2(Vector2(-half.x, -half.y), Vector2(size.x, leaf_h)), color)
		draw_rect(Rect2(Vector2(-half.x, half.y - leaf_h), Vector2(size.x, leaf_h)), color)
	if broken:
		# Torn stubs at both ends, skewed: a door that will never close again.
		var stub := half.y * 0.3
		draw_colored_polygon(PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x * 0.2, -half.y + stub)]), color)
		draw_colored_polygon(PackedVector2Array([Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(-half.x * 0.3, half.y - stub)]), color)
	elif open_amount < 1.0:
		draw_line(Vector2(-half.x, -half.y + leaf_h), Vector2(half.x, -half.y + leaf_h), seam_color, 1.0)
		draw_line(Vector2(-half.x, half.y - leaf_h), Vector2(half.x, half.y - leaf_h), seam_color, 1.0)
