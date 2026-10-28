## EnemyBeam - the enemy energy-weapon family's beam: BEAM, SWEEP, LANCE and (endpoint-beam task) TWIN
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.1–§2.3; task t2). Notes: `BEAMS.md` beside this file.
##
## **Owner-driven clock.** The owner calls `setup(host, owner_group)` once, then `start()`, `tick(delta)` on its physics tick (a brain or a
## mount) and `cancel()`. `tick()` is the only clock: no `Timer`, no `create_timer`, no `_process`. `self_tick` makes `_physics_process` call
## it, for scene-placed props only. Timeline: TELEGRAPH (`telegraph_seconds`, never lethal) -> ACTIVE (`active_seconds`, 0 = held until
## `cancel()`; lethal once `ignite_grace` has passed and while not strained) -> FADE (`fade_seconds`, never lethal) -> OFF. Every phase change
## emits `phase_changed` once.
##
## **Geometry.** An emitter kind starts at its own `global_position` and points along its **local +X** for `length` px; the owner rotates
## the beam's PARENT (a turret mount, a hull), never the beam. TWIN takes `set_endpoints(a, b)` every tick. The hit segment is the drawn one
## less `tip_grace_px` at the free tip (both ends for TWIN).
##
## **Hits.** Each lethal tick tests the band (`hit_half_width` either side of the hit segment) and the triangles swept since the previous
## lethal tick against every `EnergyHitScan.candidates()` target outside the owner set, by exact hurtbox shape. At most one hit per target
## per `rehit_interval` (keyed by instance id, cleared by `start()`; INF = once per activation, the Lance); each delivered hit emits
## `target_hit`.
##
## **Drawing.** Three code-built `Line2D` children (no PNG; the `PiercingBeam` / `MineWake` precedent), `top_level`, in global space, not
## anti-aliased: `Telegraph` (`telegraph_width` px on the exact path, yellow, white while `is_committed()`), then `Glow` (red, `2 *
## draw_half_width`) under `Core` (white-hot, `hit_half_width`), easing in over `ignite_grace` and out over `fade_seconds`. The drawn glow is
## wider than the hit band: a graze that looks safe is safe.
##
## Cover clipping, the strain flicker and laser-wall hazard registration are the endpoint-beam task's: `blocked_by_cover`,
## `registers_hazard`, `avoid_weight` and `hazard_pad` are exported here, `set_strained()` already makes the beam non-lethal and
## `hazard_info()` answers null.
class_name EnemyBeam
extends Node2D

## Append-only.
enum Kind { BEAM, SWEEP, LANCE, TWIN }
## Append-only.
enum Phase { OFF, TELEGRAPH, ACTIVE, FADE }

## Emitted once per phase change with the new `Phase`.
signal phase_changed(phase: int)
## Emitted once per delivered hit.
signal target_hit(target: Node2D, damage: int)

## Tolerance on summed tick deltas, so 54 ticks of 1/60 s end a 0.9 s phase.
const EPS := 1e-6
## Twice a swept triangle's area below which it is degenerate and skipped.
const MIN_SWEEP_AREA2 := 1e-3
const TELEGRAPH_COLOR := Color(1.0, 0.85, 0.3, 0.55)
const COMMIT_COLOR := Color(1.0, 1.0, 1.0, 0.85)
const GLOW_COLOR := Color(1.0, 0.18, 0.22, 0.6)
const CORE_COLOR := Color(1.0, 0.96, 0.9, 1.0)

@export var kind: Kind = Kind.BEAM
## Seconds of warning line before the beam can hurt.
@export var telegraph_seconds: float = 0.9
## The last seconds of TELEGRAPH in which the shot is locked (white line); 0 = never.
@export var commit_seconds: float = 0.0
## Seconds lit; 0 = held until `cancel()`.
@export var active_seconds: float = 1.2
@export var fade_seconds: float = 0.15
## Seconds into ACTIVE before the beam can hurt (the glow eases in meanwhile).
@export var ignite_grace: float = 0.1
## Drawn length of an emitter beam, px.
@export var length: float = 700.0
@export var hit_half_width: float = 12.0
@export var draw_half_width: float = 16.0
## Px at the free tip (both ends for TWIN) that are drawn but never hit.
@export var tip_grace_px: float = 24.0
## Width of the telegraph line, px (≥ 3: a thinner warning line is near-invisible).
@export var telegraph_width: float = 4.0
@export var damage: int = 10
## At most one hit per target per this many seconds; INF = once per activation.
@export var rehit_interval: float = 0.55
## The sweep's arc and rate, read by whatever rotates it (the mount), so the sweep's tuning stays in this scene.
@export var sweep_arc_deg: float = 0.0
@export var sweep_rate: float = 0.0
## Endpoint-beam task: stops at opt-in blockers on the physics step.
@export var blocked_by_cover: bool = true
## Endpoint-beam task: registers as a `&"laser_wall"` hazard while lit.
@export var registers_hazard: bool = false
@export var avoid_weight: float = 0.5
@export var hazard_pad: float = 24.0
## Scene-placed props only: tick from `_physics_process`. An owned beam leaves this off and is ticked by its owner.
@export var self_tick: bool = false

var _phase: int = Phase.OFF
## Seconds in the current phase.
var _t: float = 0.0
## Seconds since `start()`: the re-hit table's time base.
var _clock: float = 0.0
var _telegraph_duration: float = 0.0
var _active_duration: float = 0.0
var _host: Node2D = null
var _owner_group: StringName = &""
var _strained: bool = false
var _endpoint_a: Vector2 = Vector2.ZERO
var _endpoint_b: Vector2 = Vector2.ZERO
## Instance id -> `_clock` of its last hit.
var _last_hit: Dictionary = {}
## The previous lethal tick's hit segment; empty when the previous tick was not lethal.
var _prev_hit: PackedVector2Array = PackedVector2Array()
var _telegraph_line: Line2D = null
var _glow_line: Line2D = null
var _core_line: Line2D = null


func _ready() -> void:
	_telegraph_line = _make_line("Telegraph")
	_glow_line = _make_line("Glow")
	_core_line = _make_line("Core")
	set_physics_process(self_tick)
	_redraw()


func _physics_process(delta: float) -> void:
	if self_tick:
		tick(delta)


## The owner set: [param host] and every node in [param owner_group] are never hit. Called once by the owner before the first `start()`.
func setup(host: Node2D, owner_group: StringName = &"") -> void:
	_host = host
	_owner_group = owner_group


## OFF / FADE -> TELEGRAPH (ignored in TELEGRAPH or ACTIVE: a beam never re-aims mid-shot). A negative override uses the scene export;
## an active override of 0 holds the beam until `cancel()`. Clears the re-hit table.
func start(telegraph_override: float = -1.0, active_override: float = -1.0) -> void:
	if _phase == Phase.TELEGRAPH or _phase == Phase.ACTIVE:
		return
	_telegraph_duration = telegraph_override if telegraph_override >= 0.0 else telegraph_seconds
	_active_duration = active_override if active_override >= 0.0 else active_seconds
	_t = 0.0
	_clock = 0.0
	_last_hit.clear()
	_prev_hit = PackedVector2Array()
	_set_phase(Phase.TELEGRAPH)
	_redraw()


## Advances the clock, the phase, the hit scan and the drawing by [param delta] seconds. The beam's only clock.
func tick(delta: float) -> void:
	if _phase == Phase.OFF:
		return
	_t += delta
	_clock += delta
	_advance()
	if is_lethal():
		_scan()
	else:
		_prev_hit = PackedVector2Array()
	_redraw()


## TELEGRAPH -> OFF at once (it never hurt); ACTIVE -> FADE; FADE and OFF unchanged.
func cancel() -> void:
	if _phase == Phase.TELEGRAPH:
		_t = 0.0
		_set_phase(Phase.OFF)
	elif _phase == Phase.ACTIVE:
		_t = 0.0
		_set_phase(Phase.FADE)
	_prev_hit = PackedVector2Array()
	_redraw()


## World endpoints of an endpoint (TWIN) beam, set every tick before `tick()`.
func set_endpoints(a: Vector2, b: Vector2) -> void:
	_endpoint_a = a
	_endpoint_b = b


## While on, the beam is never lethal (the twin rig's strain; the endpoint-beam task adds the flicker).
func set_strained(on: bool) -> void:
	_strained = on


func phase() -> int:
	return _phase


func is_lethal() -> bool:
	return _phase == Phase.ACTIVE and _t + EPS >= ignite_grace and not _strained


## True in the last `commit_seconds` of TELEGRAPH: the shot is locked.
func is_committed() -> bool:
	return _phase == Phase.TELEGRAPH and commit_seconds > 0.0 and _telegraph_duration - _t <= commit_seconds + EPS


## The lethal parts of the beam, as world segments; empty while it is not lethal.
func hit_segments() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not is_lethal():
		return out
	var seg := _hit_segment()
	if not seg.is_empty():
		out.append(seg)
	return out


## The laser-wall hazard while lit (endpoint-beam task); null until then.
func hazard_info() -> HazardInfo:
	return null


# ---------------------------------------------------------------------------------------------

func _set_phase(next: int) -> void:
	_phase = next
	phase_changed.emit(_phase)


## Crosses every phase boundary [member _t] has passed, carrying the overshoot.
func _advance() -> void:
	while true:
		if _phase == Phase.TELEGRAPH and _t + EPS >= _telegraph_duration:
			_t = maxf(0.0, _t - _telegraph_duration)
			_set_phase(Phase.ACTIVE)
		elif _phase == Phase.ACTIVE and _active_duration > 0.0 and _t + EPS >= _active_duration:
			_t = maxf(0.0, _t - _active_duration)
			_set_phase(Phase.FADE)
		elif _phase == Phase.FADE and _t + EPS >= fade_seconds:
			_t = 0.0
			_set_phase(Phase.OFF)
		else:
			return


## The drawn segment in world space.
func _drawn_segment() -> PackedVector2Array:
	if kind == Kind.TWIN:
		return PackedVector2Array([_endpoint_a, _endpoint_b])
	var origin := global_position
	return PackedVector2Array([origin, origin + Vector2.RIGHT.rotated(global_rotation) * length])


## The hit segment in world space (the drawn one less the tip grace); empty when nothing is left.
func _hit_segment() -> PackedVector2Array:
	var drawn := _drawn_segment()
	var a := drawn[0]
	var b := drawn[1]
	var span := a.distance_to(b)
	var dir := (b - a) / span if span > EPS else Vector2.ZERO
	if kind == Kind.TWIN:
		if span <= 2.0 * tip_grace_px + EPS:
			return PackedVector2Array()
		return PackedVector2Array([a + dir * tip_grace_px, b - dir * tip_grace_px])
	if span <= tip_grace_px + EPS:
		return PackedVector2Array()
	return PackedVector2Array([a, b - dir * tip_grace_px])


func _scan() -> void:
	var seg := _hit_segment()
	if seg.is_empty():
		_prev_hit = PackedVector2Array()
		return
	var a1 := seg[0]
	var b1 := seg[1]
	var shapes: Array[Shape2D] = []
	var xforms: Array[Transform2D] = []
	var band := RectangleShape2D.new()
	band.size = Vector2(a1.distance_to(b1), 2.0 * hit_half_width)
	shapes.append(band)
	xforms.append(Transform2D((b1 - a1).angle(), (a1 + b1) * 0.5))
	var triangles: Array[PackedVector2Array] = []
	if _prev_hit.size() == 2:
		var a0 := _prev_hit[0]
		var b0 := _prev_hit[1]
		for tri: PackedVector2Array in [PackedVector2Array([a0, b0, b1]), PackedVector2Array([a0, b1, a1])]:
			if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < MIN_SWEEP_AREA2:
				continue
			var poly := ConvexPolygonShape2D.new()
			poly.points = tri
			shapes.append(poly)
			xforms.append(Transform2D.IDENTITY)
			triangles.append(tri)
	var host: Node2D = _host if is_instance_valid(_host) else null
	for target in EnergyHitScan.candidates(get_tree()):
		if not is_instance_valid(target) or EnergyHitScan.is_exempt(target, host, _owner_group):
			continue
		var id := target.get_instance_id()
		if _last_hit.has(id) and _clock - float(_last_hit[id]) + EPS < rehit_interval:
			continue
		# Broad phase: nothing whose hurtbox cannot reach the swept region.
		var reach := hit_half_width + EnergyHitScan.bounding_radius(target)
		if _distance_to_region(target.global_position, seg, triangles) > reach:
			continue
		var hit := false
		for i in shapes.size():
			if EnergyHitScan.hits_band(shapes[i], xforms[i], target):
				hit = true
				break
		if not hit:
			continue
		_last_hit[id] = _clock
		if EnergyHitScan.deliver(target, damage):
			if OS.is_stdout_verbose():
				print("[EnemyBeam] %s hit %s for %d" % [name, target.name, damage])
			target_hit.emit(target, damage)
	_prev_hit = seg


## Distance from [param p] to the hit segment and the swept triangles (0 inside a triangle).
func _distance_to_region(p: Vector2, seg: PackedVector2Array, triangles: Array[PackedVector2Array]) -> float:
	var best := p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]))
	for tri in triangles:
		if Geometry2D.point_is_inside_triangle(p, tri[0], tri[1], tri[2]):
			return 0.0
		for i in 3:
			var q := Geometry2D.get_closest_point_to_segment(p, tri[i], tri[(i + 1) % 3])
			best = minf(best, p.distance_to(q))
	return best


func _make_line(line_name: String) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.top_level = true
	line.antialiased = false
	line.visible = false
	add_child(line)
	return line


## Brightness of the lit beam: 0 -> 1 over the ignite grace, 1 -> 0 over the fade.
func _intensity() -> float:
	if _phase == Phase.ACTIVE:
		return 1.0 if ignite_grace <= 0.0 else clampf(_t / ignite_grace, 0.0, 1.0)
	if _phase == Phase.FADE:
		return 0.0 if fade_seconds <= 0.0 else clampf(1.0 - _t / fade_seconds, 0.0, 1.0)
	return 0.0


func _redraw() -> void:
	if _telegraph_line == null:
		return
	var seg := _drawn_segment()
	var telegraphing := _phase == Phase.TELEGRAPH
	var lit := _phase == Phase.ACTIVE or _phase == Phase.FADE
	_telegraph_line.visible = telegraphing
	_glow_line.visible = lit
	_core_line.visible = lit
	if telegraphing:
		_telegraph_line.points = seg
		_telegraph_line.width = telegraph_width
		_telegraph_line.default_color = COMMIT_COLOR if is_committed() else TELEGRAPH_COLOR
	if lit:
		var s := _intensity()
		_glow_line.points = seg
		_glow_line.width = 2.0 * draw_half_width * s
		_glow_line.default_color = GLOW_COLOR
		_core_line.points = seg
		_core_line.width = hit_half_width * s
		_core_line.default_color = CORE_COLOR
