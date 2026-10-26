## The warning beacon of a `Minefield`: an amber blink (the `StateLight` look) that marks the field as a placed
## structure and goes dark with the last mine. Until the art task, a code-drawn placeholder: it draws itself only
## while it has no `Sprite` child with a texture, so the PNG swaps in without a code change.
class_name MinefieldBeacon
extends Node2D

const AMBER := Color(1.0, 0.65, 0.1)
const BLINK_PERIOD := 1.0
const RADIUS := 7.0

## False once the field's last mine is gone: nothing is drawn (a sprite is hidden) and the blink stops.
var lit: bool = true : set = set_lit

var _clock: float = 0.0


func set_lit(value: bool) -> void:
	lit = value
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null:
		sprite.visible = value
	queue_redraw()


## 1.0 on the bright half of the blink, 0.35 on the dim half, 0 when dark.
func blink_alpha() -> float:
	if not lit:
		return 0.0
	return 1.0 if fmod(_clock, BLINK_PERIOD) < BLINK_PERIOD * 0.5 else 0.35


func _process(delta: float) -> void:
	if not lit:
		return
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite != null and sprite.texture != null:
		sprite.modulate.a = blink_alpha()
		return
	var a := blink_alpha()
	if a <= 0.0:
		return
	var c := Color(AMBER, a)
	draw_circle(Vector2.ZERO, RADIUS * 0.5, c)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, Color(AMBER, a * 0.7), 1.5)
