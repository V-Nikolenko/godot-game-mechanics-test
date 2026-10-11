## The fading line a Sniper's rail round leaves behind (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5 "FIRE",
## R4.17; task plan docs/plans/cmuyk2qq0008loa2xqwco8raj/3-plan.md).
##
## A code-built `Line2D` (no texture) from the muzzle the round left to the round's current position. It
## **follows** the round until the round is done, then **fades** `modulate.a` to 0 over `fade_seconds` on its own
## counter and frees itself. It owns itself: nothing else frees it, and it never touches the round.
##
## "Done" has two signals, because a pooled round is never freed when it expires:
## - **`expired`**, connected one-shot. `BulletPool._recycle` reparents an expired round into its pool and hides
##   it, so the round stays a valid object - a trail reading it after that would follow a parked round. The end
##   point is taken at the moment `expired` fires (the recycle is deferred, so the round is still where it hit).
## - **A dead weak reference**, kept only for the owner-death case: `BulletPool.cancel_active()` frees in-flight
##   rounds without emitting `expired`.
##
## No `Timer`, no `create_timer`: `step(delta)` is the whole clock, called from `_physics_process` (and by tests).
class_name RailTrail
extends Line2D

const COLOR := Color(1.0, 0.85, 0.8, 0.85)
const WIDTH := 2.0

## Seconds the fade takes once the round is done.
var fade_seconds: float = 0.4
## True while the far end tracks the round.
var following: bool = false

var _round_ref: WeakRef
var _origin: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO
var _fade_left: float = 0.0


## Builds a trail from `origin` to `round_`, adds it to the round's parent (the pool's container) and starts it
## following. Null if the round has no parent.
static func spawn(round_: Node2D, origin: Vector2, p_fade_seconds: float) -> RailTrail:
	var parent := round_.get_parent()
	if parent == null:
		return null
	var trail := RailTrail.new()
	trail.name = "RailTrail"
	trail.width = WIDTH
	trail.default_color = COLOR
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	trail.fade_seconds = p_fade_seconds
	trail._origin = origin
	trail._end = round_.global_position
	trail._round_ref = weakref(round_)
	trail.following = true
	if round_.has_signal(&"expired"):
		round_.connect(&"expired", trail._on_round_expired.bind(round_), CONNECT_ONE_SHOT)
	parent.add_child(trail)
	trail._refresh_points()
	return trail


## The two global endpoints: the muzzle and the round (or where it ended).
func global_points() -> PackedVector2Array:
	return PackedVector2Array([_origin, _end])


func _physics_process(delta: float) -> void:
	step(delta)


## One tick: follow the round, or fade and free.
func step(delta: float) -> void:
	if following:
		var round_ := _round_ref.get_ref() as Node2D if _round_ref != null else null
		if round_ == null or round_.is_queued_for_deletion():
			_stop_following()
		else:
			_end = round_.global_position
	else:
		_fade_left -= delta
		modulate.a = clampf(_fade_left / fade_seconds, 0.0, 1.0) if fade_seconds > 0.0 else 0.0
		if _fade_left <= 0.0:
			queue_free()
			return
	_refresh_points()


func _on_round_expired(round_: Node2D) -> void:
	if not following:
		return
	if is_instance_valid(round_):
		_end = round_.global_position
	_stop_following()
	_refresh_points()


func _stop_following() -> void:
	following = false
	_round_ref = null
	_fade_left = fade_seconds


func _refresh_points() -> void:
	if not is_inside_tree():
		return
	points = PackedVector2Array([to_local(_origin), to_local(_end)])
