## PulseRing - the violet shockwave a PULSE mine leaves: a code-built closed `Line2D` that expands from the blast point
## to `max_radius` over `DURATION` seconds of its own clock (accumulated delta), fading as it goes, then frees
## itself. It is spawned into the mine's parent (the container), so it outlives the mine; it has no collision and no
## effect of its own (the disruption is applied by `EnemyMine._disrupt_players()`).
class_name PulseRing
extends Line2D

const DURATION := 0.3
const SEGMENTS := 32
const COLOR := Color(0.7, 0.35, 1.0, 0.9)

var max_radius: float = 170.0
var _clock: float = 0.0


## Adds a ring at [param at] (global) to [param parent]; null parent -> nothing is made.
static func spawn(parent: Node, at: Vector2, radius: float) -> PulseRing:
	if parent == null or not parent.is_inside_tree():
		return null
	var ring := PulseRing.new()
	ring.max_radius = radius
	ring.top_level = true
	ring.global_position = at
	parent.add_child(ring)
	ring.global_position = at
	return ring


func _ready() -> void:
	width = 3.0
	default_color = COLOR
	closed = true
	z_index = 5
	_shape()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= DURATION:
		queue_free()
		return
	_shape()


## The fraction of the way out, 0..1.
func progress() -> float:
	return clampf(_clock / DURATION, 0.0, 1.0)


func _shape() -> void:
	var radius := max_radius * progress()
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		pts.append(Vector2.RIGHT.rotated(TAU * float(i) / SEGMENTS) * radius)
	points = pts
	modulate.a = 1.0 - progress()
