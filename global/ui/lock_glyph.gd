# global/ui/lock_glyph.gd
## A 12x12 code-drawn padlock laid over the special-weapon icon while the abilities are locked (Phase 9 tell).
## Code-built by MissionHud as a child of `WeaponContainer`; hidden unless the lock is on.
class_name LockGlyph
extends Control

const GLYPH_SIZE: Vector2 = Vector2(12.0, 12.0)
const COLOR: Color = Color(1.0, 0.85, 0.55)

func _init() -> void:
	name = "LockGlyph"
	size = GLYPH_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, GLYPH_SIZE), Color(0.0, 0.0, 0.0, 0.65))
	draw_arc(Vector2(6.0, 5.0), 2.5, PI, TAU, 8, COLOR, 1.5)
	draw_rect(Rect2(2.0, 5.0, 8.0, 6.0), COLOR)
