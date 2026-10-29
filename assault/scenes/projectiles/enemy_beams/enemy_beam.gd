## EnemyBeam - the enemy energy-weapon family's beam: BEAM, SWEEP, LANCE and TWIN
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
## Cover, strain and laser-wall registration (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.4; task t5):
## - **Cover.** With `blocked_by_cover`, and only on the physics step (`Engine.is_in_physics_frame()`; a hand-ticked beam never casts), a
##   ray on `LineOfSight`'s opt-in blockers (asteroids, wrecks) clips the beam: an emitter beam ends at the first blocker (no tip grace
##   there), an endpoint beam casts a -> b and b -> a and is lethal and drawn only on `a`..`hit_a` and `hit_b`..`b`; the shadow between is safe.
## - **Strain.** `set_strained(true)` makes the beam non-lethal and flickers it at `STRAIN_HZ` from its own clock.
## - **Laser wall.** With `registers_hazard` the beam is in `Hazards` from TELEGRAPH start to FADE start (and not after `cancel()`, OFF or
##   `_exit_tree()`), one `HazardInfo` of kind `&"laser_wall"` updated in place every tick: the full `a`..`b` segment, `velocity` = the
##   midpoint's motion per second over the last tick, `exempt_group` = the owner group.
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
## A strained beam flickers at this rate (Hz) between full and `STRAIN_DIM` alpha, from the beam's own clock.
const STRAIN_HZ := 15.0
const STRAIN_DIM := 0.25
## A hit part that ends on a blocker reaches this far into it, so a blocker that is also a target (an asteroid, whose hurtbox is its
## body) is hit; the drawn beam stops on the surface.
const COVER_BITE_PX := 2.0
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
## Stops at opt-in blockers (`LineOfSight`) on the physics step.
@export var blocked_by_cover: bool = true
## Registers as a `&"laser_wall"` hazard from TELEGRAPH start to FADE start.
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
## The previous lethal tick's hit parts; empty when the previous tick was not lethal.
var _prev_hit: Array[PackedVector2Array] = []
## Cover: the first blocker met from `a` (an emitter's origin), and (endpoint beams) from `b`. Only set on a physics-step tick.
var _clip_a: bool = false
var _clip_a_at: Vector2 = Vector2.ZERO
var _clip_b: bool = false
var _clip_b_at: Vector2 = Vector2.ZERO
var _hazard := HazardInfo.new()
var _hazard_registered: bool = false
var _prev_mid: Vector2 = Vector2.ZERO
var _has_prev_mid: bool = false
## The drawn layers; a second set draws the far part of a beam that cover split in two.
var _telegraph_lines: Array[Line2D] = []
var _glow_lines: Array[Line2D] = []
var _core_lines: Array[Line2D] = []


func _enter_tree() -> void:
	_sync_hazard()


func _exit_tree() -> void:
	_sync_hazard(false)


func _ready() -> void:
	for suffix in ["", "2"]:
		_telegraph_lines.append(_make_line("Telegraph" + suffix))
		_glow_lines.append(_make_line("Glow" + suffix))
		_core_lines.append(_make_line("Core" + suffix))
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
	_prev_hit = []
	_clip_a = false
	_clip_b = false
	_has_prev_mid = false
	_refresh_hazard(0.0)
	_set_phase(Phase.TELEGRAPH)
	_redraw()


## Advances the clock, the phase, the hit scan and the drawing by [param delta] seconds. The beam's only clock.
func tick(delta: float) -> void:
	if _phase == Phase.OFF:
		return
	_t += delta
	_clock += delta
	_advance()
	_refresh_hazard(delta)
	_update_cover()
	if is_lethal():
		_scan()
	else:
		_prev_hit = []
	_redraw()


## TELEGRAPH -> OFF at once (it never hurt); ACTIVE -> FADE; FADE and OFF unchanged.
func cancel() -> void:
	if _phase == Phase.TELEGRAPH:
		_t = 0.0
		_set_phase(Phase.OFF)
	elif _phase == Phase.ACTIVE:
		_t = 0.0
		_set_phase(Phase.FADE)
	_prev_hit = []
	_redraw()


## World endpoints of an endpoint (TWIN) beam, set every tick before `tick()`.
func set_endpoints(a: Vector2, b: Vector2) -> void:
	_endpoint_a = a
	_endpoint_b = b


## While on, the beam is never lethal and flickers at `STRAIN_HZ` (the twin rig's strain).
func set_strained(on: bool) -> void:
	_strained = on


func phase() -> int:
	return _phase


func is_lethal() -> bool:
	return _phase == Phase.ACTIVE and _t + EPS >= ignite_grace and not _strained


## True in the last `commit_seconds` of TELEGRAPH: the shot is locked.
func is_committed() -> bool:
	return _phase == Phase.TELEGRAPH and commit_seconds > 0.0 and _telegraph_duration - _t <= commit_seconds + EPS


## The lethal parts of the beam, as world segments (after tips and cover); empty while it is not lethal.
func hit_segments() -> Array[PackedVector2Array]:
	if not is_lethal():
		var none: Array[PackedVector2Array] = []
		return none
	return _parts(true)


## The laser-wall hazard while the beam is registered (TELEGRAPH and ACTIVE of a `registers_hazard` beam); null otherwise.
func hazard_info() -> HazardInfo:
	return _hazard if _hazard_registered else null


# ---------------------------------------------------------------------------------------------

func _set_phase(next: int) -> void:
	_phase = next
	_sync_hazard()
	phase_changed.emit(_phase)


## Registers the beam in `Hazards` exactly while it is lit-or-warning, in the tree and a `registers_hazard` beam.
func _sync_hazard(in_tree: bool = true) -> void:
	var want := in_tree and registers_hazard and is_inside_tree() and (_phase == Phase.TELEGRAPH or _phase == Phase.ACTIVE)
	if want == _hazard_registered:
		return
	_hazard_registered = want
	if want:
		Hazards.register(self)
	else:
		Hazards.unregister(self)


## The laser wall's footprint over the full `a`..`b` segment (cover does not shorten what avoidance sees), updated in place.
func _refresh_hazard(delta: float) -> void:
	if not registers_hazard:
		return
	var seg := _full_segment()
	var mid := (seg[0] + seg[1]) * 0.5
	_hazard.kind = &"laser_wall"
	_hazard.position = mid
	_hazard.segment_half = (seg[1] - seg[0]) * 0.5
	_hazard.radius = draw_half_width + hazard_pad
	_hazard.avoid_weight = avoid_weight
	_hazard.velocity = (mid - _prev_mid) / delta if _has_prev_mid and delta > 0.0 else Vector2.ZERO
	_hazard.source = self
	_hazard.exempt_group = _owner_group
	_prev_mid = mid
	_has_prev_mid = true


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


## The unclipped segment in world space: an emitter's origin to its tip, or a TWIN's two endpoints.
func _full_segment() -> PackedVector2Array:
	if kind == Kind.TWIN:
		return PackedVector2Array([_endpoint_a, _endpoint_b])
	var origin := global_position
	return PackedVector2Array([origin, origin + Vector2.RIGHT.rotated(global_rotation) * length])


## Casts for cover, on the physics step only (off it the clip is cleared, so a hand-ticked beam never clips).
func _update_cover() -> void:
	_clip_a = false
	_clip_b = false
	if _phase == Phase.OFF or not blocked_by_cover or not Engine.is_in_physics_frame() or not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	var full := _full_segment()
	var exclude: Array[RID] = []
	if is_instance_valid(_host) and _host is CollisionObject2D:
		exclude.append((_host as CollisionObject2D).get_rid())
	var hit := LineOfSight.first_blocker(space, full[0], full[1], exclude)
	if hit.is_empty():
		return
	_clip_a = true
	_clip_a_at = hit.position
	if kind == Kind.TWIN:
		var back := LineOfSight.first_blocker(space, full[1], full[0], exclude)
		if not back.is_empty():
			_clip_b = true
			_clip_b_at = back.position


## The beam's parts in world space: drawn parts, or (with [param grace]) the hit parts less `tip_grace_px` at every free tip (the free
## end of an emitter beam, both ends of a TWIN). A tip that ends on a blocker is not a free tip. Empty when nothing is left.
func _parts(grace: bool) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var full := _full_segment()
	var a := full[0]
	var b := full[1]
	var span := a.distance_to(b)
	if span <= EPS:
		return out
	var dir := (b - a) / span
	var g := tip_grace_px if grace else 0.0
	var bite := COVER_BITE_PX if grace else 0.0
	if kind == Kind.TWIN:
		if not _clip_a and span <= 2.0 * g + EPS:
			return out
		var a2 := a + dir * g
		var b2 := b - dir * g
		if not _clip_a:
			_add_part(out, a2, b2, dir)
		else:
			_add_part(out, a2, _clip_a_at + dir * bite, dir)
			if _clip_b:
				_add_part(out, _clip_b_at - dir * bite, b2, dir)
		return out
	if _clip_a:
		_add_part(out, a, _clip_a_at + dir * bite, dir)
	elif span > g + EPS:
		_add_part(out, a, b - dir * g, dir)
	return out


## Appends [param p]..[param q] when it still runs along [param dir] (cover or tip grace may have used the part up).
func _add_part(out: Array[PackedVector2Array], p: Vector2, q: Vector2, dir: Vector2) -> void:
	if (q - p).dot(dir) > EPS:
		out.append(PackedVector2Array([p, q]))


func _scan() -> void:
	var parts := _parts(true)
	if parts.is_empty():
		_prev_hit = []
		return
	var shapes: Array[Shape2D] = []
	var xforms: Array[Transform2D] = []
	var triangles: Array[PackedVector2Array] = []
	var sweep := _prev_hit.size() == parts.size()
	for i in parts.size():
		var a1 := parts[i][0]
		var b1 := parts[i][1]
		var band := RectangleShape2D.new()
		band.size = Vector2(a1.distance_to(b1), 2.0 * hit_half_width)
		shapes.append(band)
		xforms.append(Transform2D((b1 - a1).angle(), (a1 + b1) * 0.5))
		if not sweep:
			continue
		var a0 := _prev_hit[i][0]
		var b0 := _prev_hit[i][1]
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
		if _distance_to_region(target.global_position, parts, triangles) > reach:
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
	_prev_hit = parts


## Distance from [param p] to the hit parts and the swept triangles (0 inside a triangle).
func _distance_to_region(p: Vector2, parts: Array[PackedVector2Array], triangles: Array[PackedVector2Array]) -> float:
	var best := INF
	for seg in parts:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])))
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
	if _telegraph_lines.is_empty():
		return
	var parts := _parts(false) if _phase != Phase.OFF else ([] as Array[PackedVector2Array])
	var telegraphing := _phase == Phase.TELEGRAPH
	var lit := _phase == Phase.ACTIVE or _phase == Phase.FADE
	var s := _intensity()
	var flicker := 1.0
	if _strained and lit and fposmod(_clock * STRAIN_HZ, 1.0) < 0.5:
		flicker = STRAIN_DIM
	for i in _telegraph_lines.size():
		var has := i < parts.size()
		_telegraph_lines[i].visible = telegraphing and has
		_glow_lines[i].visible = lit and has
		_core_lines[i].visible = lit and has
		if not has:
			continue
		if telegraphing:
			_telegraph_lines[i].points = parts[i]
			_telegraph_lines[i].width = telegraph_width
			_telegraph_lines[i].default_color = COMMIT_COLOR if is_committed() else TELEGRAPH_COLOR
		if lit:
			_glow_lines[i].points = parts[i]
			_glow_lines[i].width = 2.0 * draw_half_width * s
			_glow_lines[i].default_color = GLOW_COLOR
			_glow_lines[i].modulate.a = flicker
			_core_lines[i].points = parts[i]
			_core_lines[i].width = hit_half_width * s
			_core_lines[i].default_color = CORE_COLOR
			_core_lines[i].modulate.a = flicker
