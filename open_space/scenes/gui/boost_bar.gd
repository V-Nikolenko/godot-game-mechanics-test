# open_space/scenes/gui/boost_bar.gd
## The readout for the Shift boost's charge economy: one long bar, drawn just under the hull,
## 6 px below the existing overheat bar (OverheatBar.BAR_HEIGHT = 4, at (0, 20)).
##
## Modelled on assault/scenes/player/overheat_bar.gd, with one deliberate difference: this bar
## is ALWAYS visible, including at full charges. A resource readout that hides itself is the
## failure this epic exists to fix — see docs/plans/
## open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md, "The bar".
##
## Width is PROPORTIONAL TO CAPACITY (`_UNIT_WIDTH` px per bar-unit), not fixed: re-slicing a
## fixed-width bar into more, thinner pieces on an upgrade reads as a downgrade. "One long
## charging line that is upgradable" means the line gets longer — see docs/plans/
## open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy/3-plan.md, "Thread 4".
##
## `_max_charges` bar-units are drawn as `_tanks` equal partitions: `_tanks == 1` is one long
## bar (the default, continuous tier), `_tanks > 1` is the Boost-Drive-style discrete-tank tier,
## with its own fill colour (finding 7 in that plan's research: Ridge Racer 7 ships per-tier
## nitrous colours for exactly this reason). Faint ticks mark every whole bar-unit boundary in
## BOTH tiers, so the continuous tier's capacity is legible even with one undivided tank.
##
## The handler stores what it draws (`_charges` / `_max_charges` / `_tanks` as members, set then
## `queue_redraw()`), the same shape `OverheatBar._percentage` uses: a `_draw()`-only node
## exposes nothing a headless test can assert on. The geometry itself is split into pure
## `_bar_width()` / `_tank_rects()` / `_unit_tick_xs()` / `_fill_color()` helpers for the same
## reason — `_draw()`'s canvas calls are not readable from a headless test, but the numbers that
## feed them are.
class_name BoostBar
extends Node2D

const _UNIT_WIDTH := 16.0   ## px per bar-unit; 2 units = 32 px (today's width), 5 = 80 px.
const BAR_HEIGHT := 4.0
const _GAP       := 1.0

const _BACKING_COLOR          := Color(0.15, 0.15, 0.15, 0.85)
const _TICK_COLOR             := Color(1.0, 1.0, 1.0, 0.25)
const _FILL_COLOR_CONTINUOUS  := Color(0.35, 0.9, 1.0)     ## tanks == 1
const _FILL_COLOR_TANKS       := Color(1.0, 0.65, 0.25)    ## tanks > 1

var _charges: float = 0.0
var _max_charges: int = 0
var _tanks: int = 1

## Children `_ready()` before parents, so BoostMeter's initial state already exists by the time
## OpenSpacePlayerShip._ready() creates this bar and calls setup() — connecting to
## charges_changed alone would leave `_max_charges` at 0 until the first spend, drawing an
## empty bar over a full meter for the whole time the hub is freshly loaded. Seeding here from
## the meter's current values, THEN connecting, is what closes that hole.
func setup(meter: BoostMeter) -> void:
	_charges = meter.charges
	_max_charges = meter.max_charges
	_tanks = meter.tanks
	queue_redraw()
	meter.charges_changed.connect(_on_charges_changed)
	meter.tanks_changed.connect(_on_tanks_changed)

func _on_charges_changed(current: float, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	queue_redraw()

func _on_tanks_changed(tanks: int) -> void:
	_tanks = tanks
	queue_redraw()

## Total bar width in px — proportional to capacity, never fixed.
func _bar_width() -> float:
	return _UNIT_WIDTH * float(_max_charges)

## The fill colour for the current tier: continuous (one long bar) vs. discrete tanks.
func _fill_color() -> Color:
	return _FILL_COLOR_CONTINUOUS if _tanks <= 1 else _FILL_COLOR_TANKS

## The backing rect for each of the `_tanks` partitions, left to right, spanning `_bar_width()`
## with the existing 1 px gap between them. `_tanks == 1` returns exactly one rect: one long bar.
func _tank_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if _max_charges <= 0 or _tanks <= 0:
		return rects
	var width: float = _bar_width()
	var x: float = -width * 0.5
	var tank_width: float = (width - _GAP * float(_tanks - 1)) / float(_tanks)
	for i: int in range(_tanks):
		var tank_x: float = x + float(i) * (tank_width + _GAP)
		rects.append(Rect2(tank_x, 0.0, tank_width, BAR_HEIGHT))
	return rects

## Local-space x of the faint tick marking each whole bar-unit boundary (there are
## `_max_charges - 1` of them), drawn in both tiers so the continuous bar's capacity stays
## legible even as one undivided tank.
func _unit_tick_xs() -> Array[float]:
	var xs: Array[float] = []
	if _max_charges <= 1:
		return xs
	var width: float = _bar_width()
	var x: float = -width * 0.5
	for i: int in range(1, _max_charges):
		xs.append(x + float(i) * _UNIT_WIDTH)
	return xs

func _draw() -> void:
	if _max_charges <= 0:
		return
	var rects: Array[Rect2] = _tank_rects()
	var tank_size: float = float(_max_charges) / float(_tanks)
	var fill_color: Color = _fill_color()
	for i: int in range(rects.size()):
		var rect: Rect2 = rects[i]
		draw_rect(rect, _BACKING_COLOR)
		var filled_units: float = clampf(_charges - float(i) * tank_size, 0.0, tank_size)
		if filled_units > 0.0:
			draw_rect(Rect2(rect.position.x, rect.position.y,
					rect.size.x * (filled_units / tank_size), rect.size.y), fill_color)
	for tick_x: float in _unit_tick_xs():
		draw_line(Vector2(tick_x, 0.0), Vector2(tick_x, BAR_HEIGHT), _TICK_COLOR, 1.0)
