## EmpStatic - the enemy-side EMP tell (Phase 9 §2.6): a code-built blue-white jagged ring round the hull, the shape of
## the player's boost-disruption ring, re-jittered every JITTER_INTERVAL seconds from a seeded rng and flickering like
## it. `BaseEnemy` builds it on its first EMP, shows it exactly while `is_emp_disrupted()` and steps it on its physics
## tick. No scene, no PNG; it changes nothing but its own drawing (IDEAS §21: a state shows on a light or overlay, never
## a recoloured hull).
class_name EmpStatic
extends Node2D

const COLOR: Color = Color(0.7, 0.85, 1.0)
const POINTS: int = 16
const SPIKE: float = 3.0
const JITTER: float = 1.5
const LINE_WIDTH: float = 1.5
const JITTER_INTERVAL: float = 0.08
const SEED: int = 17

var radius: float = 24.0

var _rng := RandomNumberGenerator.new()
var _ring := PackedVector2Array()
var _jitter_left: float = JITTER_INTERVAL
var _clock: float = 0.0


func _init(p_radius: float = 24.0) -> void:
	name = "EmpStatic"
	radius = p_radius
	z_index = 1
	_rng.seed = SEED
	_rejitter()


## The ring's points (a read for tests).
func ring() -> PackedVector2Array:
	return _ring


## Starts the flicker from the top (each new window).
func restart() -> void:
	_clock = 0.0
	modulate.a = 1.0


## One tick: the jitter and flicker clocks.
func step(delta: float) -> void:
	_clock += delta
	_jitter_left -= delta
	if _jitter_left <= 0.0:
		_jitter_left += JITTER_INTERVAL
		_rejitter()
	modulate.a = 0.55 + 0.45 * absf(sin(_clock * 21.0))


func _rejitter() -> void:
	_ring.clear()
	for i in range(POINTS):
		var r: float = radius + (SPIKE if i % 2 == 0 else -SPIKE) + _rng.randf_range(-JITTER, JITTER)
		_ring.append(Vector2.RIGHT.rotated(TAU * i / POINTS) * r)
	_ring.append(_ring[0])
	queue_redraw()


func _draw() -> void:
	draw_polyline(_ring, COLOR, LINE_WIDTH)
