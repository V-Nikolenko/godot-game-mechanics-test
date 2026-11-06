## EnergyRing - the Pulse Ring: an expanding band of energy with rotating gaps, hurting everything it crosses except its own group
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.5; task t3). Not `PulseRing`, which is Phase 7's visual ring. Notes: `BEAMS.md`.
##
## **Owner-driven clock,** the `EnemyBeam` rule: the owner calls `setup(host, owner_group)` once, then `start()`, `tick(delta)` on its
## physics tick and `cancel()`. `tick()` is the only clock: no `Timer`, no `create_timer`, no `_process`. Timeline: TELEGRAPH
## (`telegraph_seconds`: a faint circle at `max_radius`, drawn with the gaps' current bearings, and a charge glow at the centre; never
## lethal) -> EXPANDING (the band grows at `ring_speed`; lethal) -> FADE (`fade_seconds`; never lethal) -> OFF.
##
## **Geometry.** The centre is fixed at `start()` (the node's global position then); moving the node afterwards moves nothing. The band is
## `band` px thick and its OUTER edge never passes `max_radius`, so `radius()` (the band's centre) tops out at `max_radius - band / 2`; the
## outer edge still travels at `ring_speed` and reaches `max_radius` in `max_radius / ring_speed`. `gap_count` gaps of `gap_deg` degrees
## are spread evenly and turn at `gap_spin_deg` degrees/s from `start()`, from a start bearing the owner draws from its brain `rng`
## (`start(gap_start_deg)`; 0 when omitted).
##
## **Hits.** A target is hit once per ring (the table is cleared by `start()`) on the first tick on which its centre distance `d` lies in
## `[r_prev - band/2 - R_t, r + band/2 + R_t]` (the swept interval since the last scan; `R_t` = `EnergyHitScan.bounding_radius`) and its
## bearing from the centre is not inside a gap. Owner set, victims and the direct-emit damage path are `EnergyHitScan`'s, as for a beam.
##
## **Drawing.** A plain child `Node2D` ("Visual", `top_level`, at the world origin) paints with `draw_arc` in global coordinates, so the
## ring stays where it started whatever its owner does. Not anti-aliased.
class_name EnergyRing
extends Node2D

## Append-only.
enum Phase { OFF, TELEGRAPH, EXPANDING, FADE }

## Emitted once per phase change with the new `Phase`.
signal phase_changed(phase: int)
## Emitted once per delivered hit.
signal target_hit(target: Node2D, damage: int)

## Tolerance on summed tick deltas, so 48 ticks of 1/60 s end a 0.8 s phase.
const EPS := 1e-6
const TELEGRAPH_COLOR := Color(1.0, 0.85, 0.3, 0.45)
const CHARGE_COLOR := Color(1.0, 0.85, 0.3, 0.5)
const GLOW_COLOR := Color(1.0, 0.18, 0.22, 0.6)
const CORE_COLOR := Color(1.0, 0.96, 0.9, 1.0)
## Arc segment length, px, for `draw_arc`'s point count.
const ARC_STEP := 8.0

## Seconds of warning before the band can hurt.
@export var telegraph_seconds: float = 0.8
@export var fade_seconds: float = 0.15
## Growth of the band's outer edge, px/s.
@export var ring_speed: float = 360.0
## The farthest the band's outer edge reaches, px.
@export var max_radius: float = 280.0
## Thickness of the band, px.
@export var band: float = 24.0
@export var gap_count: int = 2
## Width of each gap, degrees.
@export var gap_deg: float = 45.0
## Turn rate of the gaps, degrees/s.
@export var gap_spin_deg: float = 30.0
@export var damage: int = 12
## Width of the warning circle, px (>= 3: a thinner warning line is near-invisible).
@export var telegraph_width: float = 4.0

var _phase: int = Phase.OFF
## Seconds in the current phase.
var _t: float = 0.0
## Seconds since `start()`: the gaps' time base.
var _clock: float = 0.0
var _telegraph_duration: float = 0.0
var _centre: Vector2 = Vector2.ZERO
var _gap_start_deg: float = 0.0
## The band's centre radius now / at the previous scan.
var _r: float = 0.0
var _r_prev: float = 0.0
## True on the tick EXPANDING ended, so that tick still scans the final radius.
var _scan_pending: bool = false
var _host: Node2D = null
var _owner_group: StringName = &""
## Instance ids already hit by this ring.
var _hit: Dictionary = {}
var _visual: Node2D = null


func _ready() -> void:
	set_physics_process(false)
	set_process(false)
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.top_level = true
	_visual.draw.connect(_paint)
	add_child(_visual)
	_visual.queue_redraw()


## The owner set: [param host] and every node in [param owner_group] are never hit. Called once by the owner before the first `start()`.
func setup(host: Node2D, owner_group: StringName = &"") -> void:
	_host = host
	_owner_group = owner_group


## OFF / FADE -> TELEGRAPH, centred where this node is now (ignored in TELEGRAPH or EXPANDING: a ring never moves mid-shot).
## [param gap_start_deg] is the first gap's bearing in degrees (the owner's `rng` draw); NAN = 0. Clears the once-per-ring table.
func start(gap_start_deg: float = NAN) -> void:
	if _phase == Phase.TELEGRAPH or _phase == Phase.EXPANDING:
		return
	_centre = global_position
	_gap_start_deg = 0.0 if is_nan(gap_start_deg) else gap_start_deg
	_telegraph_duration = telegraph_seconds
	_t = 0.0
	_clock = 0.0
	_r = 0.0
	_r_prev = 0.0
	_scan_pending = false
	_hit.clear()
	_set_phase(Phase.TELEGRAPH)
	_redraw()


## Advances the clock, the phase, the hit scan and the drawing by [param delta] seconds. The ring's only clock.
func tick(delta: float) -> void:
	if _phase == Phase.OFF:
		return
	_t += delta
	_clock += delta
	_advance()
	if _phase == Phase.EXPANDING or _scan_pending:
		_scan()
		_scan_pending = false
	_redraw()


## TELEGRAPH -> OFF at once (it never hurt); EXPANDING -> FADE; FADE and OFF unchanged.
func cancel() -> void:
	if _phase == Phase.TELEGRAPH:
		_t = 0.0
		_set_phase(Phase.OFF)
	elif _phase == Phase.EXPANDING:
		_t = 0.0
		_set_phase(Phase.FADE)
	_scan_pending = false
	_redraw()


func phase() -> int:
	return _phase


func is_lethal() -> bool:
	return _phase == Phase.EXPANDING


## The band's centre radius now, px (0 until EXPANDING).
func radius() -> float:
	return _r


## Where the ring is centred (fixed at `start()`).
func ring_centre() -> Vector2:
	return _centre


## Bearing, degrees, of gap [param index]'s centre now.
func gap_center_deg(index: int) -> float:
	var step := 360.0 / float(maxi(gap_count, 1))
	return _gap_start_deg + step * float(index) + gap_spin_deg * _clock


## True when [param bearing] (radians, from the centre) lies inside a gap now.
func in_gap(bearing: float) -> bool:
	var half := deg_to_rad(gap_deg) * 0.5
	for i in gap_count:
		if absf(angle_difference(deg_to_rad(gap_center_deg(i)), bearing)) <= half:
			return true
	return false


# ---------------------------------------------------------------------------------------------

func _set_phase(next: int) -> void:
	_phase = next
	phase_changed.emit(_phase)


## The centre radius at which the band's outer edge meets `max_radius`.
func _r_max() -> float:
	return maxf(0.0, max_radius - band * 0.5)


func _expand_duration() -> float:
	return max_radius / ring_speed if ring_speed > 0.0 else 0.0


## Crosses every phase boundary [member _t] has passed, carrying the overshoot, and sets the band radius.
func _advance() -> void:
	while true:
		if _phase == Phase.TELEGRAPH and _t + EPS >= _telegraph_duration:
			_t = maxf(0.0, _t - _telegraph_duration)
			_set_phase(Phase.EXPANDING)
		elif _phase == Phase.EXPANDING and _t + EPS >= _expand_duration():
			_t = maxf(0.0, _t - _expand_duration())
			_r = _r_max()
			_scan_pending = true
			_set_phase(Phase.FADE)
		elif _phase == Phase.FADE and _t + EPS >= fade_seconds:
			_t = 0.0
			_set_phase(Phase.OFF)
		else:
			break
	if _phase == Phase.EXPANDING:
		_r = minf(ring_speed * _t, _r_max())


func _scan() -> void:
	var half_band := band * 0.5
	var host: Node2D = _host if is_instance_valid(_host) else null
	for target in EnergyHitScan.candidates(get_tree()):
		if not is_instance_valid(target) or EnergyHitScan.is_exempt(target, host, _owner_group):
			continue
		var id := target.get_instance_id()
		if _hit.has(id):
			continue
		var offset := target.global_position - _centre
		var d := offset.length()
		var r_t := EnergyHitScan.bounding_radius(target)
		if d < _r_prev - half_band - r_t or d > _r + half_band + r_t:
			continue
		if in_gap(offset.angle()):
			continue
		_hit[id] = true
		if EnergyHitScan.deliver(target, damage):
			if OS.is_stdout_verbose():
				print("[EnergyRing] %s hit %s for %d" % [name, target.name, damage])
			target_hit.emit(target, damage)
	_r_prev = _r


## Brightness of the lit band: fades out over FADE.
func _intensity() -> float:
	if _phase == Phase.FADE:
		return 0.0 if fade_seconds <= 0.0 else clampf(1.0 - _t / fade_seconds, 0.0, 1.0)
	return 1.0


func _redraw() -> void:
	if _visual != null:
		_visual.queue_redraw()


## Draws the arcs between the gaps (or the full circle with no gaps) at [param radius].
func _draw_arcs(radius: float, color: Color, width: float) -> void:
	if radius <= 0.0 or width <= 0.0:
		return
	var half := deg_to_rad(gap_deg) * 0.5
	if gap_count <= 0:
		_visual.draw_arc(_centre, radius, 0.0, TAU, maxi(16, int(TAU * radius / ARC_STEP)), color, width, false)
		return
	var step := TAU / float(gap_count)
	for i in gap_count:
		var from := deg_to_rad(gap_center_deg(i)) + half
		var to := deg_to_rad(gap_center_deg(i)) + step - half
		if to <= from:
			continue
		_visual.draw_arc(_centre, radius, from, to, maxi(4, int((to - from) * radius / ARC_STEP)), color, width, false)


func _paint() -> void:
	if _phase == Phase.TELEGRAPH:
		# The reach the band will have, with the gaps where they are now, and a charge glow growing at the centre.
		_draw_arcs(max_radius - telegraph_width * 0.5, TELEGRAPH_COLOR, telegraph_width)
		var progress := 1.0 if _telegraph_duration <= 0.0 else clampf(_t / _telegraph_duration, 0.0, 1.0)
		_visual.draw_circle(_centre, 4.0 + 20.0 * progress, CHARGE_COLOR)
	elif _phase == Phase.EXPANDING or _phase == Phase.FADE:
		var s := _intensity()
		_draw_arcs(_r, Color(GLOW_COLOR, GLOW_COLOR.a * s), band)
		_draw_arcs(_r, Color(CORE_COLOR, CORE_COLOR.a * s), band * 0.4)
