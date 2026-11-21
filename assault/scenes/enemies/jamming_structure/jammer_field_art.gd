## The code-drawn look of a jamming tower's field, a child of its `Field` (Phase 9 plan §2.8, R9.5). LIT (ACTIVE): 48 short dashed arcs at
## the radius, 3 px, amber-white at alpha 0.35, crawling round at 0.4 rad/s, over a faint fill. FLICKER (TELEGRAPH): the same ring, its alpha
## toggling between 0.35 and 0.1 every 0.1 s. QUIET (QUIET, or suppressed by an EMP): one 1 px outline at alpha 0.08. Never cyan (shield) or
## violet (boost disruption). Reads the field's `phase()` / `is_suppressed()`; it has no effect of its own and never writes its `rotation`
## (the crawl is an angle offset in `_draw()`).
class_name JammerFieldArt
extends Node2D

enum Look { LIT, FLICKER, QUIET }

const DASHES := 48
const DASH_WIDTH := 3.0
const RING_COLOR := Color(1.0, 0.85, 0.55)
const LIT_ALPHA := 0.35
const FLICKER_LOW_ALPHA := 0.1
const FLICKER_PERIOD := 0.1
const QUIET_ALPHA := 0.08
const FILL_ALPHA := 0.05
const CRAWL_SPEED := 0.4
const DASH_POINTS := 4

var _field: HazardField
## Seconds since the art started: drives the crawl and the flicker.
var _clock: float = 0.0


func _ready() -> void:
	_field = get_parent() as HazardField
	z_index = 4


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func look() -> int:
	if _field == null or _field.is_suppressed() or _field.phase() == HazardField.Phase.QUIET:
		return Look.QUIET
	if _field.phase() == HazardField.Phase.TELEGRAPH:
		return Look.FLICKER
	return Look.LIT


func ring_alpha() -> float:
	match look():
		Look.LIT:
			return LIT_ALPHA
		Look.FLICKER:
			return LIT_ALPHA if int(floor(_clock / FLICKER_PERIOD)) % 2 == 0 else FLICKER_LOW_ALPHA
	return QUIET_ALPHA


func _draw() -> void:
	if _field == null:
		return
	var r := _field.radius
	var current := look()
	if current == Look.QUIET:
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(RING_COLOR, QUIET_ALPHA), 1.0, true)
		return
	if current == Look.LIT:
		draw_circle(Vector2.ZERO, r, Color(RING_COLOR, FILL_ALPHA))
	var color := Color(RING_COLOR, ring_alpha())
	var slot := TAU / DASHES
	var crawl := fposmod(_clock * CRAWL_SPEED, TAU)
	for i in DASHES:
		var start := crawl + slot * i
		draw_arc(Vector2.ZERO, r, start, start + slot * 0.5, DASH_POINTS, color, DASH_WIDTH, true)
