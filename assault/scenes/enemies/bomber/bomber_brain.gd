## The Bomber's brain (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4; task plan
## docs/plans/cmuyk2qpr0089oa2xlih7xvmg/3-plan.md, Revision 3).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   chooses the ordnance, lays a bombing line across where the player is heading and flies
##                           a Dubins lead-in that arrives on it pointing along it, re-planned from a fresh prediction
##                           every `replan_interval` until RUN entry.
##   RUN        [ATTACK]     the slow straight run along the frozen line at `run_speed`: mines dropped by distance,
##                           a gravity bomb released short of the aim point, or a pursuit bomb launched at it.
##                           StateLight ARMED.
##   ESCAPE     [REPOSITION] turns away from the player on an arc for `escape_time`.
##   REPOSITION [REPOSITION] Open Space: orbits at `standoff` for a moment, then APPROACHes again.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out (a running run finishes first), or the one run of
##                           this life is over. Release the corridor, curve out of the world rect, free.
## IDLE / NOTICING / RETURNING (the hub, t19) are appended later so these values do not move.
##
## Two leads. The mine wall uses an UNDAMPED lead on the bomber's own timeline — the wall must be armed where the
## player will be when they get there — and the Dubins goal is planned to where that wall will be on ARRIVAL (the
## Fighter's arrival prediction), so for a constant-velocity player the line does not move during the approach.
## The gravity bomb and the pursuit aim keep the damped, aimed-shot lead (`lead_factor`, `horizon`).
##
## Rails: `on_suspended()` only switches the light off. The legacy bombing (a gravity bomb DOWN every
## `rail_bomb_interval`) is a clock on the `Bomber` root, because a rail stops this brain's ticks.
##
## Requests only (single-writer gate): the writes on the mover are `request_velocity`, `max_speed` and
## `release_constraint()` on DISENGAGE. Ordnance leaves through `Bomber.drop()`.
class_name BomberBrain
extends EnemyBrain

enum Phase { APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The Dubins plan radius is the mover's real turn radius times this, so a plan is always followable.
const PLAN_RADIUS_FACTOR := 1.1
## Pure-pursuit tracking of the sampled lead-in (the Fighter's `_track`).
const TRACK_SAMPLE_PX := 8.0
const TRACK_SEARCH := 12
const TRACK_AHEAD := 3
## The mine wall's arrival time: scanned in these steps (s), then bisected this many times.
const ARRIVAL_SCAN_STEP := 0.1
const ARRIVAL_BISECTIONS := 5
## A new lead-in replaces the tracked one only when its goal moved this far, or the bomber is this far off the
## tracked one (px; the Fighter's numbers).
const REPLAN_GOAL_PX := 24.0
const REPLAN_OFF_PATH_PX := 40.0
## The last stretch: within this lateral offset (px) and heading error (deg) of the line, from this far before its
## start, the bomber pursues a point `CAPTURE_SEEK_AHEAD` px further along the line instead of the curve.
const CAPTURE_LATERAL_PX := 96.0
const CAPTURE_HEADING_DEG := 45.0
const CAPTURE_BEHIND_PX := 160.0
const CAPTURE_SEEK_AHEAD := 80.0
## RUN entry: on the line within this lateral offset (px) and heading error (deg), with a run coordinate in
## [-ENTRY_BEHIND_PX, run_length / 2].
const ENTRY_LATERAL_PX := 32.0
const ENTRY_HEADING_DEG := 12.0
const ENTRY_BEHIND_PX := 32.0
## RUN seeks a point this far ahead on the line, so drift back onto it is corrected.
const RUN_SEEK_AHEAD := 40.0
## RUN ends at the latest `line_length / run_speed` plus this (s), however the run went (stall guard).
const RUN_STALL_SLACK := 0.25
## REPOSITION's orbit anchor leads the bomber's bearing round the player by this (rad).
const REPOSITION_LEAD := 0.4
## |cross| below this counts as "parallel" for the side tie-break.
const PARALLEL_CROSS := 0.05
## The two sides of an angled line whose lead-ins differ by less than this (px) are a tie.
const SIDE_TIE_PX := 1.0
## The angled approach narrows from `approach_angle` to 0 in this many steps until its lead-in has no loop.
const ANGLE_STEPS := 4
## An anchor moved further than this by the Assault clamp reports `wall_clamped()` (px).
const CLAMP_EPS := 0.5

## Set by `bomber.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: BomberConfig = BomberConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH

## The ordnance of the current APPROACH / RUN (`EnemyOrdnance.Kind`).
var ordnance_kind: int = EnemyOrdnance.Kind.MINE
## The bombing line: the run starts at `line_start` and goes `line_length` px along the unit `line_dir`.
var line_start: Vector2 = Vector2.ZERO
var line_dir: Vector2 = Vector2.DOWN
var line_length: float = 0.0
## MINE runs: where each mine is planned to come to rest, fixed at RUN entry.
var planned_rest_points: Array[Vector2] = []
## Mines / bombs released this RUN.
var drops_this_run: int = 0
## Runs started (RUN entries) this life.
var runs_started: int = 0
## The angle (deg) the current angled line actually turns off the bearing (`approach_angle` or narrower).
var approach_angle_used: float = 0.0

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO

var _v_bar: Vector2 = Vector2.ZERO
var _v_bar_ready: bool = false
## The P-hat the current line was built from.
var _drop_point: Vector2 = Vector2.ZERO
var _wall_clamped: bool = false
## Assault: `inner_rect().grow(-drop_margin)`; an empty rect in Open Space.
var _drop_rect: Rect2 = Rect2()

# APPROACH
var _needs_choice: bool = true
var _side: float = 1.0
var _mine_side: float = 1.0
var _angled_dir: Vector2 = Vector2.DOWN
var _replan_clock: float = 0.0
var _approach_time: float = 0.0
var _t_approach_left: float = 0.0
var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_idx: int = 0
var _path_goal: Vector2 = Vector2.INF

# RUN
var _rest_s: Array[float] = []
var _next_mine: int = 0
var _single_dropped: bool = false
var _disengage_pending: bool = false

# REPOSITION
var _reposition_time: float = 0.0
var _orbit_sign: float = 1.0


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	var target := TargetInfo.player(get_tree())
	_update_prediction(target, delta)
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.RUN: _tick_run(delta, target)
		Phase.ESCAPE: _tick_escape(delta, target)
		Phase.REPOSITION: _tick_reposition(delta, target)
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.APPROACH:
			_set_light(StateLight.State.OFF)
			_enter_approach()
		Phase.RUN:
			_set_light(StateLight.State.ARMED)
			_enter_run()
		Phase.REPOSITION:
			_set_light(StateLight.State.OFF)
			_enter_reposition()
		Phase.DISENGAGE:
			_enter_disengage()
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The root's rail clock does the bombing.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


# ── Read-only seams ──────────────────────────────────────────────────────────────────────────────

## The player's smoothed velocity, `v-bar`.
func smoothed_velocity() -> Vector2:
	return _v_bar


## The P-hat the current line was built from: the mine wall's centre (undamped lead) or the gravity / pursuit
## aim point (damped lead). Frozen with the line at RUN entry.
func predicted_drop_point() -> Vector2:
	return _drop_point


func line_centre() -> Vector2:
	return line_start + line_dir * line_length * 0.5


## True when the Assault clamp moved the line's anchor (P-hat, or the abeam point of a pursuit line).
func wall_clamped() -> bool:
	return _wall_clamped


## The undamped mine-wall lead from RUN entry (s): `c` of the task plan, capped by `mine_horizon`.
func wall_lead_at_entry(speed: float) -> float:
	var c := (config.run_length * 0.5) / config.run_speed + config.mine_arm_delay + config.wall_margin
	if speed > 0.0:
		c += (config.trigger_radius + config.arc_depth) / speed
	return minf(c, config.mine_horizon)


## The damped gravity / pursuit aim point for a player at `p` moving at `v`, seen from `from`.
func damped_aim_point(p: Vector2, v: Vector2, from: Vector2) -> Vector2:
	if v.length() < config.min_lead_speed:
		return p
	return p + v * config.lead_factor * minf(config.horizon, from.distance_to(p) / config.run_speed)


## The ordnance the choice rule gives a player at speed `speed` and distance `d`, before jitter.
func choose_kind(speed: float, d: float) -> int:
	if speed > config.mine_speed_max:
		return EnemyOrdnance.Kind.PURSUIT_BOMB
	if speed >= config.mine_speed_min:
		return EnemyOrdnance.Kind.MINE
	if d < config.gravity_range:
		return EnemyOrdnance.Kind.GRAVITY_BOMB
	return EnemyOrdnance.Kind.PURSUIT_BOMB


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	var constraint := mover.constraint if mover != null else null
	if constraint != null and constraint.inner_rect().has_area():
		_drop_rect = constraint.inner_rect().grow(-config.drop_margin)
	_enter_approach()


func _request_disengage() -> void:
	if phase == Phase.RUN:
		_disengage_pending = true  # the run finishes first (<= line_length / run_speed + RUN_STALL_SLACK)
		return
	enter_phase(Phase.DISENGAGE)


## The exponential moving average of the player's velocity, seeded from the first sample.
func _update_prediction(target: TargetInfo, delta: float) -> void:
	if not target.has_target:
		return
	if not _v_bar_ready:
		_v_bar = target.velocity
		_v_bar_ready = true
		return
	var alpha := 1.0 if config.velocity_smoothing <= 0.0 else 1.0 - exp(-delta / config.velocity_smoothing)
	_v_bar += (target.velocity - _v_bar) * alpha


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _enter_approach() -> void:
	_needs_choice = true
	_approach_time = 0.0
	_clear_path()


## Ordnance choice, line side and the angled direction: once per APPROACH (and again after `approach_cap`).
func _choose(target: TargetInfo, kind: int) -> void:
	var pos := actor.global_position
	ordnance_kind = kind
	if _v_bar.length() >= config.min_lead_speed:
		# MINE: the wall's start sits on the bomber's side of the player's track.
		var cr := _v_bar.cross(pos - target.position)
		if absf(cr) < 1e-3:
			_mine_side = -1.0 if rng.randf() < 0.5 else 1.0
		else:
			_mine_side = signf(cr)
	_choose_angled_side(target)
	_t_approach_left = pos.distance_to(target.position) / maxf(config.max_speed, 1.0)
	_approach_time = 0.0
	_needs_choice = false
	_replan(target)


## The angled line (GRAVITY / PURSUIT, and a MINE run on a near-stationary player) turns off the bearing to P-hat
## by up to `approach_angle`, to whichever side gives the shorter lead-in. The angle narrows (in
## `ANGLE_STEPS`) to the widest one whose lead-in has no loop (shorter than half a turn circle): the line's start
## is `L / 2 + gravity_release_lead` from P-hat, so a bomber closer than about 880 px is BESIDE it at the full
## angle and could only reach it by looping round, which at the plan radius takes longer than `approach_cap`.
## Near the player the pass is therefore near-direct; from range it is the full angled approach (R4.2). No
## loop-free angle at all: the shortest lead-in. A side tie (a nose-on bomber) goes to `_turn_side()`. Chosen
## once per APPROACH and kept: from the line's start the bearing to P-hat IS the line, so re-deriving it on a
## re-plan would rotate it again.
func _choose_angled_side(target: TargetInfo) -> void:
	var pos := actor.global_position
	var bearing := (damped_aim_point(target.position, _v_bar, pos) - pos).normalized()
	if bearing == Vector2.ZERO:
		bearing = _heading()
	var loop_free := PI * _plan_radius()
	var best_len := INF
	var best_side := 1.0
	var best_angle := 0.0
	for step in ANGLE_STEPS + 1:
		var angle := deg_to_rad(config.approach_angle) * (1.0 - float(step) / ANGLE_STEPS)
		var lengths: Array[float] = []
		for side in [1.0, -1.0]:
			_side = side
			_angled_dir = bearing.rotated(side * angle)
			_build_line(target, 0.0)
			lengths.append(_lead_in_length(pos))
		var side_here := _turn_side(bearing) if absf(lengths[0] - lengths[1]) < SIDE_TIE_PX \
				else (1.0 if lengths[0] < lengths[1] else -1.0)
		var len_here := minf(lengths[0], lengths[1])
		if len_here <= loop_free:
			best_side = side_here
			best_angle = angle
			break
		if len_here < best_len:
			best_len = len_here
			best_side = side_here
			best_angle = angle
	_side = best_side
	_angled_dir = bearing.rotated(_side * best_angle)
	approach_angle_used = rad_to_deg(best_angle)


## The tie-break for `_choose_angled_side()`: toward the bomber's heading; when the heading is parallel to the
## bearing, toward the corridor centre in Assault; when that is parallel too (or in Open Space), an rng side.
func _turn_side(bearing: Vector2) -> float:
	var cr := bearing.cross(_heading())
	if absf(cr) >= PARALLEL_CROSS:
		return signf(cr)
	if _drop_rect.has_area():
		var to_centre := (_drop_rect.get_center() - actor.global_position).normalized()
		var cc := bearing.cross(to_centre)
		if absf(cc) >= PARALLEL_CROSS:
			return signf(cc)
	return -1.0 if rng.randf() < 0.5 else 1.0


func _next_kind(kind: int) -> int:
	match kind:
		EnemyOrdnance.Kind.MINE: return EnemyOrdnance.Kind.GRAVITY_BOMB
		EnemyOrdnance.Kind.GRAVITY_BOMB: return EnemyOrdnance.Kind.PURSUIT_BOMB
		_: return EnemyOrdnance.Kind.MINE


func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if _needs_choice:
		var kind := choose_kind(_v_bar.length(), actor.global_position.distance_to(target.position))
		if rng.randf() < config.choice_jitter:
			kind = _next_kind(kind)
		_choose(target, kind)
	_approach_time += delta
	if _approach_time >= config.approach_cap:
		# The line could not be reached: take the next kind in the cycle rather than chase the same one (F5).
		_choose(target, _next_kind(ordnance_kind))
	_replan_clock += delta
	if _replan_clock >= config.replan_interval:
		_replan(target)
	if _on_line():
		enter_phase(Phase.RUN)
		_tick_run(delta, target)
		return
	_track(delta)


## A fresh prediction, line and Dubins lead-in. For a moving player's mine wall the arrival time and the goal
## depend on each other: the goal is the line through `P + v (T + c)`, and `T` is the EARLIEST time at which the
## path to it can be flown, `length / max_speed <= T` (scanned in `ARRIVAL_SCAN_STEP`s up to `approach_cap`,
## then bisected). For a constant-velocity player that goal does not move while the bomber flies to it. (A plain
## fixed-point iteration, the Fighter's, diverges here: a far start makes a long loop, which makes a later
## goal, which makes a longer loop.) The tracked path is only swapped when the new goal moved more than
## `REPLAN_GOAL_PX` or the bomber is `REPLAN_OFF_PATH_PX` off it, so a static goal is flown as one curve.
func _replan(target: TargetInfo) -> void:
	_replan_clock = 0.0
	if _capturing():
		# The last stretch is flown along the line itself: only the prediction is refreshed, with the time left
		# read from the distance still to go along the line.
		_t_approach_left = _time_to_start()
		_build_line(target, _t_approach_left if _is_moving_wall() else 0.0)
		return
	var pos := actor.global_position
	var path: DubinsPath = null
	if _is_moving_wall():
		path = _solve_arrival(target, pos)
	else:
		_build_line(target, 0.0)
		path = _plan_path(pos)
		if path != null:
			_t_approach_left = _flight_time(path.length)
	if path == null:
		_clear_path()
		return
	var off_path := _path_pts.is_empty() or pos.distance_to(_path_pts[_path_idx]) > REPLAN_OFF_PATH_PX
	if off_path or _path_goal.distance_to(line_start) > REPLAN_GOAL_PX:
		_path_pts = path.sample(TRACK_SAMPLE_PX)
		_path_idx = 0
		_path_goal = line_start


func _solve_arrival(target: TargetInfo, pos: Vector2) -> DubinsPath:
	var prev := -1.0
	var t := 0.0
	# No feasible arrival at all (a pose the curve cannot fix in time): the least-late one.
	var fallback_t := config.approach_cap
	var fallback_late := INF
	while t <= config.approach_cap + 1e-6:
		_build_line(target, t)
		var path := _plan_path(pos)
		if path != null and _flight_time(path.length) <= t:
			var hi := t
			var best := path
			if prev >= 0.0:
				var lo := prev
				for _k in ARRIVAL_BISECTIONS:
					var mid := (lo + hi) * 0.5
					_build_line(target, mid)
					var p_mid := _plan_path(pos)
					if p_mid != null and _flight_time(p_mid.length) <= mid:
						hi = mid
						best = p_mid
					else:
						lo = mid
			_build_line(target, hi)
			_t_approach_left = hi
			return best
		if path != null and _flight_time(path.length) - t < fallback_late:
			fallback_late = _flight_time(path.length) - t
			fallback_t = t
		prev = t
		t += ARRIVAL_SCAN_STEP
	_build_line(target, fallback_t)
	_t_approach_left = fallback_t
	return _plan_path(pos)


func _is_moving_wall() -> bool:
	return ordnance_kind == EnemyOrdnance.Kind.MINE and _v_bar.length() >= config.min_lead_speed


## Builds the line for the current kind from the live player and `v-bar`; `t_left` is the approach time still to
## fly (mine wall only).
func _build_line(target: TargetInfo, t_left: float) -> void:
	var p := target.position
	var pos := actor.global_position
	var length := config.run_length
	var dir: Vector2
	var anchor: Vector2
	var anchor_s: float
	if _is_moving_wall():
		_drop_point = p + _v_bar * (t_left + wall_lead_at_entry(_v_bar.length()))
		var perp := _v_bar.normalized().orthogonal()
		# The start (P-hat - dir * L / 2) must be on the bomber's side of the track.
		dir = perp if _v_bar.cross(-perp) * _mine_side > 0.0 else -perp
		anchor = _drop_point
		anchor_s = length * 0.5
	else:
		_drop_point = damped_aim_point(p, _v_bar, pos)
		dir = _angled_dir
		match ordnance_kind:
			EnemyOrdnance.Kind.GRAVITY_BOMB:
				anchor = _drop_point
				anchor_s = length * 0.5 + config.gravity_release_lead
			EnemyOrdnance.Kind.PURSUIT_BOMB:
				# P-hat abeam the line's end, on the side the bearing was turned away from (F2).
				anchor = _drop_point - dir.rotated(-_side * PI / 2.0) * config.pursuit_launch_range
				anchor_s = length
			_:
				anchor = _drop_point  # a MINE run against a (near) stationary player: centred over it
				anchor_s = length * 0.5
	_set_line(anchor, anchor_s, dir, length)


## Places the line so `anchor` sits at run coordinate `anchor_s`; in Assault clamps the anchor into the drop
## rect, clips the line to it and slides (or cuts) the run to fit (R4.6).
func _set_line(anchor: Vector2, anchor_s: float, dir: Vector2, length: float) -> void:
	line_dir = dir
	_wall_clamped = false
	if not _drop_rect.has_area():
		line_start = anchor - dir * anchor_s
		line_length = length
		return
	var a := anchor.clamp(_drop_rect.position, _drop_rect.end)
	_wall_clamped = a.distance_to(anchor) > CLAMP_EPS
	var span := _clip(a, dir, _drop_rect)
	var t0 := -anchor_s
	var t1 := length - anchor_s
	if t1 - t0 > span.y - span.x:
		t0 = span.x
		t1 = span.y
	elif t0 < span.x:
		t1 += span.x - t0
		t0 = span.x
	elif t1 > span.y:
		t0 -= t1 - span.y
		t1 = span.y
	line_start = a + dir * t0
	line_length = t1 - t0


## The parameter interval [x, y] for which `a + dir * t` is inside `rect` (`a` is inside it).
static func _clip(a: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var lo := -INF
	var hi := INF
	for axis in 2:
		var d: float = dir[axis]
		if absf(d) < 1e-6:
			continue
		var ta: float = (rect.position[axis] - a[axis]) / d
		var tb: float = (rect.end[axis] - a[axis]) / d
		lo = maxf(lo, minf(ta, tb))
		hi = minf(hi, maxf(ta, tb))
	return Vector2(minf(lo, 0.0), maxf(hi, 0.0))


## The lead-in to the current line: 0 when the bomber is already inside the RUN entry window.
func _lead_in_length(pos: Vector2) -> float:
	if _on_line():
		return 0.0
	var path := _plan_path(pos)
	return path.length if path != null else INF


func _plan_path(pos: Vector2) -> DubinsPath:
	var paths := DubinsPath.candidates(pos, _heading().angle(), line_start, line_dir.angle(), _plan_radius())
	return paths[0] if not paths.is_empty() else null


## Seconds to fly `length` px from the current speed, accelerating at `acceleration` up to `max_speed` (a bomber
## starting from rest takes about 0.9 s to reach transit speed; ignoring that puts a fast player's wall too short).
func _flight_time(length: float) -> float:
	var vmax := maxf(config.max_speed, 1.0)
	var v0 := minf(actor.velocity.length(), vmax)
	if config.acceleration <= 0.0 or v0 >= vmax:
		return length / vmax
	var t_acc := (vmax - v0) / config.acceleration
	var d_acc := (v0 + vmax) * 0.5 * t_acc
	if length >= d_acc:
		return t_acc + (length - d_acc) / vmax
	# length = v0 t + a t^2 / 2
	return (-v0 + sqrt(v0 * v0 + 2.0 * config.acceleration * length)) / config.acceleration


## The turn radius the mover can actually hold at `max_speed`, with margin.
func _plan_radius() -> float:
	var rate := config.max_turn_rate
	if config.max_speed > 0.0 and config.acceleration > 0.0:
		rate = minf(rate, config.acceleration / config.max_speed)
	return config.max_speed / maxf(rate, 0.01) * PLAN_RADIUS_FACTOR


## Pure pursuit on the sampled path: a point `TRACK_AHEAD` samples past the nearest one; past its end, along
## the line. In the last stretch (`_capturing()`), a point `CAPTURE_SEEK_AHEAD` along the line itself.
func _track(delta: float) -> void:
	var pos := actor.global_position
	var seek: Vector2
	if _capturing():
		seek = line_start + line_dir * (maxf(_run_s(), -CAPTURE_SEEK_AHEAD) + CAPTURE_SEEK_AHEAD)
		_t_approach_left = _time_to_start()
	elif _path_pts.is_empty():
		seek = line_start
	else:
		var best := _path_idx
		var best_d := pos.distance_to(_path_pts[_path_idx])
		for i in range(_path_idx, mini(_path_idx + TRACK_SEARCH, _path_pts.size())):
			var d := pos.distance_to(_path_pts[i])
			if d < best_d:
				best_d = d
				best = i
		_path_idx = best
		var last := _path_pts.size() - 1
		if best + TRACK_AHEAD <= last:
			seek = _path_pts[best + TRACK_AHEAD]
		else:
			seek = _path_pts[last] + line_dir * TRACK_AHEAD * TRACK_SAMPLE_PX
	var dir := Steering.turn_toward(_heading(), seek - pos, config.max_turn_rate, delta)
	mover.request_velocity(dir * config.max_speed)


## Time until the bomber is at the line's start, along the line: NEGATIVE once it is past it (it is then that much
## further into the run than the wall's lead assumes). Reading 0 there instead would let a fast player's wall slide
## ahead at the player's own speed while the bomber is still settling onto the line.
func _time_to_start() -> float:
	var s := _run_s()
	if s <= 0.0:
		return _flight_time(-s)
	return -s / maxf(config.run_speed, 1.0)


## True in the last stretch before RUN: close to the line, roughly along it, not yet past its middle.
func _capturing() -> bool:
	if line_length <= 0.0:
		return false
	var rel := actor.global_position - line_start
	var s := rel.dot(line_dir)
	if s < -CAPTURE_BEHIND_PX or s > line_length * 0.5:
		return false
	if absf(line_dir.cross(rel)) > CAPTURE_LATERAL_PX:
		return false
	return absf(_heading().angle_to(line_dir)) <= deg_to_rad(CAPTURE_HEADING_DEG)


func _on_line() -> bool:
	if line_length <= 0.0:
		return false
	var rel := actor.global_position - line_start
	var s := rel.dot(line_dir)
	if s < -ENTRY_BEHIND_PX or s > line_length * 0.5:
		return false
	if absf(line_dir.cross(rel)) > ENTRY_LATERAL_PX:
		return false
	return absf(_heading().angle_to(line_dir)) <= deg_to_rad(ENTRY_HEADING_DEG)


func _clear_path() -> void:
	_path_pts = PackedVector2Array()
	_path_idx = 0
	_path_goal = Vector2.INF


# ── RUN ──────────────────────────────────────────────────────────────────────────────────────────

func _enter_run() -> void:
	runs_started += 1
	drops_this_run = 0
	_single_dropped = false
	_next_mine = 0
	planned_rest_points.clear()
	_rest_s.clear()
	_clear_path()
	if ordnance_kind == EnemyOrdnance.Kind.MINE:
		_plan_mines()


## Mines by distance (§2.4 item 5): `n` rest points `mine_spacing` apart, centred on the run coordinate where the
## line crosses the player's current track, bowed up to `arc_depth` toward the player's side, largest in the
## middle. Each is released `eject` px past its rest coordinate, so all of them fit between here and the end.
func _plan_mines() -> void:
	var target := TargetInfo.player(get_tree())
	var p := target.position if target.has_target else line_centre()
	var s_entry := maxf(_run_s(), 0.0)
	var eject := _eject_lead()
	var n := rng.randi_range(config.mines_per_run_min, config.max_mines_per_run)
	var s_star := (p - line_start).dot(line_dir)
	while true:
		var half := (n - 1) * 0.5 * config.mine_spacing
		var lo := s_entry - eject + half
		var hi := line_length - eject - half
		if lo <= hi or n <= 1:
			s_star = clampf(s_star, lo, hi) if lo <= hi else hi
			break
		n -= 1
	var toward := 1.0 if line_dir.cross(p - line_start) >= 0.0 else -1.0
	var normal := line_dir.orthogonal() * -toward  # `orthogonal()` is the -90 deg (left) normal
	var mid := (n - 1) * 0.5
	for i in n:
		var k := i - mid
		var bow := config.arc_depth * (1.0 - pow(k / (mid + 1.0), 2.0))
		var s := s_star + k * config.mine_spacing
		var rest := line_start + line_dir * s + normal * bow
		if _drop_rect.has_area():
			rest = rest.clamp(_drop_rect.position, _drop_rect.end)
		planned_rest_points.append(rest)
		_rest_s.append(s)


func _eject_lead() -> float:
	return config.mine_eject_speed * config.mine_eject_time * 0.5


func _run_s() -> float:
	return (actor.global_position - line_start).dot(line_dir)


func _tick_run(_delta: float, target: TargetInfo) -> void:
	var s := _run_s()
	var pos := actor.global_position
	match ordnance_kind:
		EnemyOrdnance.Kind.MINE:
			while _next_mine < _rest_s.size() and s >= _rest_s[_next_mine] + _eject_lead():
				_drop_mine(_next_mine)
				_next_mine += 1
		EnemyOrdnance.Kind.GRAVITY_BOMB:
			if not _single_dropped and target.has_target:
				var aim := damped_aim_point(target.position, _v_bar, pos)
				if (aim - pos).dot(line_dir) <= config.gravity_release_lead:
					_drop_gravity(aim)
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			if not _single_dropped and s >= line_length * 0.5:
				_drop_pursuit(target)
	var stall := line_length / maxf(config.run_speed, 1.0) + RUN_STALL_SLACK
	if s >= line_length or _phase_time >= stall:
		_finish_run(target)
		return
	var seek := line_start + line_dir * (maxf(s, 0.0) + RUN_SEEK_AHEAD)
	mover.request_velocity((seek - pos).normalized() * config.run_speed)


## Whatever the run did not get to drop goes now, so a run always delivers its whole pattern.
func _finish_run(target: TargetInfo) -> void:
	match ordnance_kind:
		EnemyOrdnance.Kind.MINE:
			while _next_mine < _rest_s.size():
				_drop_mine(_next_mine)
				_next_mine += 1
		EnemyOrdnance.Kind.GRAVITY_BOMB:
			if not _single_dropped:
				var aim := damped_aim_point(target.position, _v_bar, actor.global_position) if target.has_target \
						else actor.global_position + _heading() * config.gravity_release_lead
				_drop_gravity(aim)
		EnemyOrdnance.Kind.PURSUIT_BOMB:
			if not _single_dropped:
				_drop_pursuit(target)
	if _disengage_pending:
		enter_phase(Phase.DISENGAGE)  # the budget ran out during the run
	else:
		enter_phase(Phase.ESCAPE)


## Ejected along `rest - pos` at `v0 = 2 |rest - pos| / eject_time`, so the linear decay stops it on its point.
func _drop_mine(i: int) -> void:
	var rest := planned_rest_points[i]
	var offset := rest - actor.global_position
	var speed := 2.0 * offset.length() / maxf(config.mine_eject_time, 0.001)
	_drop(EnemyOrdnance.Kind.MINE, offset if offset != Vector2.ZERO else line_dir, speed, rest)


## Inherits the bomber's heading (§2.4 item 5).
func _drop_gravity(aim: Vector2) -> void:
	_single_dropped = true
	_drop(EnemyOrdnance.Kind.GRAVITY_BOMB, _heading(), config.gravity_bomb_speed, aim)


func _drop_pursuit(target: TargetInfo) -> void:
	_single_dropped = true
	var pos := actor.global_position
	var aim := damped_aim_point(target.position, _v_bar, pos) if target.has_target else pos + _heading() * 300.0
	_drop(EnemyOrdnance.Kind.PURSUIT_BOMB, aim - pos, config.pursuit_launch_speed, aim)


func _drop(kind: int, dir: Vector2, speed: float, at: Vector2) -> void:
	drops_this_run += 1
	if actor.has_method(&"drop"):
		actor.call(&"drop", kind, dir, speed, at)


# ── ESCAPE / REPOSITION ──────────────────────────────────────────────────────────────────────────

## Turns away from the player at most `escape_turn_rate` (capped by what the mover's acceleration can follow at
## `escape_speed`) — a brain-side arc, never the mover's turn cap.
func _tick_escape(delta: float, target: TargetInfo) -> void:
	if _phase_time >= config.escape_time:
		if budget.active:
			enter_phase(Phase.DISENGAGE)
		else:
			enter_phase(Phase.REPOSITION)
		return
	var pos := actor.global_position
	var away := (pos - target.position) if target.has_target else _heading()
	var dir := Steering.turn_toward(_heading(), away, _escape_rate(), delta)
	mover.request_velocity(dir * config.escape_speed)


func _escape_rate() -> float:
	var rate := config.escape_turn_rate
	if config.escape_speed > 0.0 and config.acceleration > 0.0:
		rate = minf(rate, config.acceleration / config.escape_speed)
	return rate


func _enter_reposition() -> void:
	_reposition_time = rng.randf_range(config.reposition_min, config.reposition_max)
	var target := TargetInfo.player(get_tree())
	var cr := (actor.global_position - target.position).cross(actor.velocity) if target.has_target else 0.0
	_orbit_sign = signf(cr) if absf(cr) > 1e-3 else (-1.0 if rng.randf() < 0.5 else 1.0)


func _tick_reposition(delta: float, target: TargetInfo) -> void:
	if _phase_time >= _reposition_time:
		enter_phase(Phase.APPROACH)
		return
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var pos := actor.global_position
	var angle := (pos - target.position).angle() + _orbit_sign * REPOSITION_LEAD
	var want := Steering.orbit(pos, target.position, config.standoff, angle, config.max_speed)
	var dir := Steering.turn_toward(_heading(), want, config.max_turn_rate, delta)
	mover.request_velocity(dir * want.length())


# ── DISENGAGE (the Fighter's exit) ───────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	_set_light(StateLight.State.OFF)
	_disengage_pending = false
	mover.release_constraint()
	mover.max_speed = config.exit_speed
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	var to_left := pos.x - rect.position.x
	var to_right := rect.end.x - pos.x
	var to_top := pos.y - rect.position.y
	var to_bottom := rect.end.y - pos.y
	var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if nearest == to_left:
		_exit_point = Vector2(rect.position.x - EXIT_OVERSHOOT, pos.y)
	elif nearest == to_right:
		_exit_point = Vector2(rect.end.x + EXIT_OVERSHOOT, pos.y)
	elif nearest == to_top:
		_exit_point = Vector2(pos.x, rect.position.y - EXIT_OVERSHOOT)
	else:
		_exit_point = Vector2(pos.x, rect.end.y + EXIT_OVERSHOOT)


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The
## curve's rate is capped by what the mover's acceleration can follow at exit speed.
func _tick_disengage(delta: float) -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	var rate := config.max_turn_rate
	if config.exit_speed > 0.0:
		rate = minf(rate, config.acceleration / config.exit_speed)
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, rate, delta)
	mover.request_velocity(dir * config.exit_speed)


## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
