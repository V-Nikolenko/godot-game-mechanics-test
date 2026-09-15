# open_space/scenes/gui/boost_bar.gd
## The readout for the Shift boost's charge economy: a 32x4 cyan pip bar drawn just under the
## hull, 6 px below the existing overheat bar (OverheatBar.BAR_HEIGHT = 4, at (0, 20)).
##
## Modelled on assault/scenes/player/overheat_bar.gd, with one deliberate difference: this bar
## is ALWAYS visible, including at full charges. A resource readout that hides itself is the
## failure this epic exists to fix — see docs/plans/
## open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md, "The bar".
##
## The handler stores what it draws (`_charges` / `_max_charges` as members, set then
## `queue_redraw()`), the same shape `OverheatBar._percentage` uses: a `_draw()`-only node
## exposes nothing a headless test can assert on.
class_name BoostBar
extends Node2D

const BAR_WIDTH  := 32.0
const BAR_HEIGHT := 4.0
const _GAP       := 1.0

const _BACKING_COLOR := Color(0.15, 0.15, 0.15, 0.85)
const _FILL_COLOR    := Color(0.35, 0.9, 1.0)

var _charges: float = 0.0
var _max_charges: int = 0

## Children `_ready()` before parents, so BoostMeter's initial state already exists by the time
## OpenSpacePlayerShip._ready() creates this bar and calls setup() — connecting to
## charges_changed alone would leave `_max_charges` at 0 until the first spend, drawing an
## empty bar over a full meter for the whole time the hub is freshly loaded. Seeding here from
## the meter's current values, THEN connecting, is what closes that hole.
func setup(meter: BoostMeter) -> void:
	_charges = meter.charges
	_max_charges = meter.max_charges
	queue_redraw()
	meter.charges_changed.connect(_on_charges_changed)

func _on_charges_changed(current: float, maximum: int) -> void:
	_charges = current
	_max_charges = maximum
	queue_redraw()

func _draw() -> void:
	if _max_charges <= 0:
		return
	var x := -BAR_WIDTH * 0.5
	var segment_width: float = (BAR_WIDTH - _GAP * float(_max_charges - 1)) / float(_max_charges)
	for i: int in range(_max_charges):
		var seg_x: float = x + float(i) * (segment_width + _GAP)
		draw_rect(Rect2(seg_x, 0, segment_width, BAR_HEIGHT), _BACKING_COLOR)
		var filled: float = clampf(_charges - float(i), 0.0, 1.0)
		if filled > 0.0:
			draw_rect(Rect2(seg_x, 0, segment_width * filled, BAR_HEIGHT), _FILL_COLOR)
