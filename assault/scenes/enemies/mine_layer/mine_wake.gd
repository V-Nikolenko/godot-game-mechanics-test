## The fading line a Mine Layer leaves along the path its Dispenser took while laying
## (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.13; task t13): it shows where the line of mines was just laid.
##
## A code-built `Line2D` (no texture) added to the layer's parent container at LAY start. It **follows** the Dispenser,
## appending its global position every `SPACING` px (several points when one tick covers more, so the spacing is exactly
## `SPACING` and a 24 px stretch always holds at least two points), until `finish()`; it then **fades** `modulate.a` to 0
## over `fade_seconds` on its own counter and frees itself. It owns itself: nothing else frees it, and it never touches the
## layer. The `RailTrail` precedent: no `Timer`, no `create_timer`; `step(delta)` is the whole clock, called from
## `_physics_process` (and by tests, which switch the process off).
class_name MineWake
extends Line2D

const SPACING := 12.0
const WIDTH := 3.0
const ALPHA := 0.45
## The oldest end of the line is transparent, the newest dark red.
const HEAD_COLOR := Color(0.55, 0.05, 0.08, ALPHA)
const TAIL_COLOR := Color(0.55, 0.05, 0.08, 0.0)

## Seconds the fade takes once laying is done.
var fade_seconds: float = 2.5
## True while the line tracks the Dispenser.
var following: bool = false

var _source_ref: WeakRef
var _global_points: PackedVector2Array = PackedVector2Array()
var _fade_left: float = 0.0


## Builds a wake following `dispenser`, adds it to `dispenser`'s owner's parent (the enemy container) and seeds it with
## the Dispenser's current position. Null when there is no such parent.
static func spawn(dispenser: Node2D, p_fade_seconds: float) -> MineWake:
	var layer := dispenser.get_parent()
	var parent := layer.get_parent() if layer != null else null
	if parent == null:
		return null
	var wake := MineWake.new()
	wake.name = "MineWake"
	wake.width = WIDTH
	wake.default_color = HEAD_COLOR
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([TAIL_COLOR, HEAD_COLOR])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	wake.gradient = gradient
	wake.begin_cap_mode = Line2D.LINE_CAP_ROUND
	wake.end_cap_mode = Line2D.LINE_CAP_ROUND
	wake.fade_seconds = p_fade_seconds
	wake._source_ref = weakref(dispenser)
	wake.following = true
	wake._global_points.append(dispenser.global_position)
	parent.add_child(wake)
	wake._refresh_points()
	return wake


## The line's points in global space (test seam).
func global_points() -> PackedVector2Array:
	return _global_points


func _physics_process(delta: float) -> void:
	step(delta)


## One tick: follow the Dispenser, or fade and free.
func step(delta: float) -> void:
	if following:
		var source := _source_ref.get_ref() as Node2D if _source_ref != null else null
		if source == null or source.is_queued_for_deletion():
			finish()
		else:
			_extend_to(source.global_position)
	if not following:
		_fade_left -= delta
		modulate.a = clampf(_fade_left / fade_seconds, 0.0, 1.0) if fade_seconds > 0.0 else 0.0
		if _fade_left <= 0.0:
			queue_free()
			return
	_refresh_points()


## Laying is over: take one last point where the Dispenser is, then start the fade.
func finish() -> void:
	if not following:
		return
	var source := _source_ref.get_ref() as Node2D if _source_ref != null else null
	if source != null and not source.is_queued_for_deletion():
		_extend_to(source.global_position)
	following = false
	_source_ref = null
	_fade_left = fade_seconds


## Appends points every `SPACING` px along the straight run from the last point to `to`.
func _extend_to(to: Vector2) -> void:
	var last := _global_points[_global_points.size() - 1]
	var gap := to.distance_to(last)
	while gap >= SPACING:
		last = last + (to - last) / gap * SPACING
		_global_points.append(last)
		gap = to.distance_to(last)


func _refresh_points() -> void:
	if not is_inside_tree():
		return
	var local := PackedVector2Array()
	for p in _global_points:
		local.append(to_local(p))
	points = local
