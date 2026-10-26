## EmpRing - the blue-white crackle an EMP mine leaves: a code-built closed `Line2D` whose radius jitters like an arc
## discharge, expanding from the blast point to `max_radius` over `DURATION` seconds of its own clock (accumulated delta),
## fading as it goes, then frees itself. Spawned into the mine's parent (the container), so it outlives the mine; no
## collision and no effect of its own (the EMP is applied by `EmpPulse.emit()`). The jitter is a pure function of the
## point index and the clock, so it needs no rng.
class_name EmpRing
extends Line2D

const DURATION := 0.35
const SEGMENTS := 40
const COLOR := Color(0.65, 0.88, 1.0, 0.95)
const JITTER := 7.0

var max_radius: float = 190.0
var _clock: float = 0.0


## Adds a ring at [param at] (global) to [param parent]; null parent -> nothing is made.
static func spawn(parent: Node, at: Vector2, radius: float) -> EmpRing:
	if parent == null or not parent.is_inside_tree():
		return null
	var ring := EmpRing.new()
	ring.max_radius = radius
	ring.top_level = true
	ring.global_position = at
	parent.add_child(ring)
	ring.global_position = at
	return ring


func _ready() -> void:
	width = 2.0
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
		var jitter := JITTER * sin(float(i) * 2.7 + _clock * 90.0) * (1.0 if i % 2 == 0 else -1.0)
		pts.append(Vector2.RIGHT.rotated(TAU * float(i) / SEGMENTS) * maxf(radius + jitter * progress(), 0.0))
	points = pts
	modulate.a = 1.0 - progress()
