# global/entities/ability_lock_static.gd
## The ship-side tell for the Phase 9 ability lock: six short jagged amber-white arcs round the hull, re-jittered
## every JITTER_INTERVAL seconds from a seeded rng. Code-built by PlayerBase on the first lock (no scene, no PNG);
## PlayerBase shows it exactly while `abilities_locked()` and feeds it `ability_lock_fill()` each tick. Alpha is
## `0.3 + 0.6 * fill` (0.9 while held); a refused press flashes it to full alpha for FLASH_SECONDS.
class_name AbilityLockStatic
extends Node2D

const COLOR: Color = Color(1.0, 0.85, 0.55)
const ARC_COUNT: int = 6
const RADIUS: float = 30.0
const RADIUS_JITTER: float = 3.0
const ARC_SPAN: float = 0.55  ## radians
const ARC_POINTS: int = 5
const LINE_WIDTH: float = 2.0
const JITTER_INTERVAL: float = 0.08
const FLASH_SECONDS: float = 0.15
const SEED: int = 9

var _rng := RandomNumberGenerator.new()
var _arcs: Array[PackedVector2Array] = []
var _jitter_left: float = JITTER_INTERVAL
var _flash_left: float = 0.0
var _fill: float = 1.0

func _init() -> void:
	name = "AbilityLockStatic"
	_rng.seed = SEED
	_rejitter()
	_apply_alpha()

## The current arcs (a copy-safe read for tests).
func arcs() -> Array[PackedVector2Array]:
	return _arcs

## Sets the fill (`ability_lock_fill()`) the alpha follows.
func set_fill(fill: float) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	_apply_alpha()

## A refused press: full alpha for FLASH_SECONDS.
func flash() -> void:
	_flash_left = FLASH_SECONDS
	_apply_alpha()

## One tick: the flash and jitter clocks, and the alpha for [param fill].
func step(delta: float, fill: float) -> void:
	_fill = clampf(fill, 0.0, 1.0)
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
	_jitter_left -= delta
	if _jitter_left <= 0.0:
		_jitter_left += JITTER_INTERVAL
		_rejitter()
	_apply_alpha()

func _apply_alpha() -> void:
	modulate.a = 1.0 if _flash_left > 0.0 else 0.3 + 0.6 * _fill

func _rejitter() -> void:
	_arcs.clear()
	for i in range(ARC_COUNT):
		var start: float = TAU * i / ARC_COUNT + _rng.randf_range(-0.2, 0.2)
		var pts := PackedVector2Array()
		for k in range(ARC_POINTS):
			var a: float = start + ARC_SPAN * k / (ARC_POINTS - 1)
			var r: float = RADIUS + _rng.randf_range(-RADIUS_JITTER, RADIUS_JITTER)
			pts.append(Vector2.RIGHT.rotated(a) * r)
		_arcs.append(pts)
	queue_redraw()

func _draw() -> void:
	for pts in _arcs:
		draw_polyline(pts, COLOR, LINE_WIDTH)
