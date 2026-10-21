## The well's inner glow, drawn above the sprite. Its strength comes from `GravityWell.glow_strength()`;
## the parent redraws it when that changes.
extends Node2D

const COLOR := Color(1.0, 0.72, 0.3)


func _draw() -> void:
	var well := get_parent() as GravityWell
	if well == null:
		return
	var s := well.glow_strength()
	var r := well.core_radius
	draw_circle(Vector2.ZERO, r, Color(COLOR, 0.10 * s))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(COLOR, 0.55 * s), 3.0, true)
