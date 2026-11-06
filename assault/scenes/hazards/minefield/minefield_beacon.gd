## The warning beacon of a `Minefield`: a buoy sprite (`minefield_beacon.png`, the scene's `Sprite` child) that blinks
## like a `StateLight` and marks the field as a placed structure. It goes dark (the sprite is hidden) with the field's
## last mine. The blink is the sprite's alpha, never painted into the art.
class_name MinefieldBeacon
extends Node2D

const BLINK_PERIOD := 1.0

## False once the field's last mine is gone: the sprite is hidden and the blink stops.
var lit: bool = true : set = set_lit

var _clock: float = 0.0


func set_lit(value: bool) -> void:
	lit = value
	_apply()


## 1.0 on the bright half of the blink, 0.35 on the dim half, 0 when dark.
func blink_alpha() -> float:
	if not lit:
		return 0.0
	return 1.0 if fmod(_clock, BLINK_PERIOD) < BLINK_PERIOD * 0.5 else 0.35


func _process(delta: float) -> void:
	if not lit:
		return
	_clock += delta
	_apply()


func _apply() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	sprite.visible = lit
	sprite.modulate.a = blink_alpha()
