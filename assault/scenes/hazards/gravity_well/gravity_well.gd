## The Gravity Well: a `HazardField` with the plan §2.5 numbers (set in the scene) plus its presentation.
## The pull, the stress and the registry are all the base script's; this adds only what the eye sees:
## a faint ring at the field's full `radius` and an inner glow scaled by the field's strength where the
## player is. Read-only: nothing here touches a ship.
class_name GravityWell
extends HazardField

const RING_COLOR := Color(0.62, 0.45, 0.95, 0.2)
const RING_WIDTH := 2.0
const RING_POINTS := 96
## Brightness with no player in reach of the field (0 would make a well look switched off).
const GLOW_MIN := 0.15

var _glow: float = GLOW_MIN


func _process(_delta: float) -> void:
	var next := _strength_at_player()
	if not is_equal_approx(next, _glow):
		_glow = next
		var glow_node := get_node_or_null("Glow")
		if glow_node != null:
			glow_node.queue_redraw()


## 0..1 brightness of the inner glow: `GLOW_MIN` out of reach, 1.0 inside the core.
func glow_strength() -> float:
	return _glow


func _strength_at_player() -> float:
	if not is_inside_tree():
		return GLOW_MIN
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return GLOW_MIN
	return lerpf(GLOW_MIN, 1.0, hazard_info().falloff(player.global_position.distance_to(global_position)))


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINTS, RING_COLOR, RING_WIDTH, true)
