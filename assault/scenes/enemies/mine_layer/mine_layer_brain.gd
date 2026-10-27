## The Mine Layer's brain (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.11 shell, §2.12 passes; task plan
## docs/plans/cmvkb0hdc00uiqs2xhvb2awai/3-plan.md).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   plans a pass and flies to its run-in point R, then runs in along the line's axis R -> S at
##                           `lay_speed`. Two steps, one phase: seek R (re-planned every tick until the plan freezes within
##                           `commit_distance` of R), then the run-in from the first tick within `path_lookahead` of R.
##   LAY        [ATTACK]     committed: pure pursuit along the polyline S -> mine 0 .. mine 5 -> E at `lay_speed`, dropping each
##                           mine once the Dispenser has passed its point by the eject lead (the Bomber's "plus" rule). It
##                           refuses a tow. StateLight ARMED, CHARGING for `CHARGE_TIME` before each drop.
##   BREAK_OFF  [EVADE]      Open Space: `break_contact` away from the player and off the far end of the fresh line.
##   REPOSITION [REPOSITION] Open Space: orbits the player at `standoff_range` for `pass_period_min..max`, then APPROACH.
##   DISENGAGE  [DISENGAGE]  Assault: the budget ran out (a LAY finishes first) or the one pass of this life is laid. Release the
##                           corridor and leave at `exit_speed` along the line's axis (no pass laid: the heading on entry, which
##                           `SpecialistExitProbe` measures); free once outside the world rect.
##   IDLE / NOTICING / RETURNING   Open Space hub idle (t12).
## The enum is declared in full and append-only.
##
## Where a line goes (§2.12). Open Space: a moving player (smoothed |v-bar| >= `frame_speed`) gets a LEAD line across the
## predicted track, from the Bomber's earliest-feasible arrival scan; a standing player, or a moving one no arrival can be
## found for, gets a FENCE line between the player and the layer (`fence_distance` from the player). A standing player's frame
## is latched (f = player -> layer at APPROACH start) so R is a fixed point; the axis sign keeps the start S on the layer's
## side, re-applied after the fence spread rotates the frame. Assault: a horizontal line `assault_ahead` above the player,
## clamped into the view.
##
## Requests only (single-writer gate): the writes on the mover are `request_velocity` (and its wrappers), `boost`,
## `max_speed` and `release_constraint()` on DISENGAGE. Mines leave through `MineLayer.drop_mine()`, always via `lay_mine()`,
## which keeps the live-mine FIFO and retires the oldest at the cap.
class_name MineLayerBrain
extends EnemyBrain

enum Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }
enum Shape { ZIGZAG, ARC }

signal phase_changed(new_phase: int)
## Every mine this brain lays (pass and tail drops), after it is launched.
signal mine_dropped(mine: EnemyMine)

## Below this speed the heading is the nose's direction, not the velocity's (px/s).
const HEADING_MIN_SPEED := 1.0
## The lead form's arrival time: scanned in these steps (s) up to `lead_scan_cap`, then bisected this many times (the
## Bomber's `_solve_arrival`, re-declared here rather than borrowed).
const ARRIVAL_SCAN_STEP := 0.1
const ARRIVAL_BISECTIONS := 5
## The spread moves a centre this much further than `min_pass_separation` (px).
const SPREAD_EXTRA := 10.0
## REPOSITION's orbit anchor leads the layer's bearing round the player by this (rad; the Bomber's).
const REPOSITION_LEAD := 0.4
## No-stacking (Open Space): a rest point within a live mine's `trigger_radius` + this (px) is skipped.
const NO_STACK_PAD := 40.0
## The StateLight goes CHARGING this long before each drop (s, at `lay_speed`).
const CHARGE_TIME := 0.3
## |offset| below this (px) is a tie for the axis-sign rule.
const TIE_PX := 1.0
## LAY's stall guard: `path_length * STALL_FACTOR / lay_speed + STALL_SLACK` (s).
const STALL_FACTOR := 1.2
const STALL_SLACK := 0.5
## Open Space: a run-in still short of S this long after the freeze is given up (s; see `_abandon_due`).
const RUN_IN_STALL_SECONDS := 20.0

var config: MineLayerConfig = MineLayerConfig.new()
var budget: EngagementBudget
var phase: Phase = Phase.APPROACH
## Test seam, read by the hub idle task: start in the fight instead of patrolling.
var start_engaged: bool = false

# ── The current pass (read-only seams) ───────────────────────────────────────────────────────────
var pass_centre: Vector2 = Vector2.ZERO
var pass_start: Vector2 = Vector2.ZERO
var pass_end: Vector2 = Vector2.ZERO
var pass_run_in_point: Vector2 = Vector2.ZERO
## u: the unit axis, from S toward E.
var pass_axis: Vector2 = Vector2.RIGHT
## n-hat: the unit normal of the axis pointing from C toward the player's side.
var pass_normal: Vector2 = Vector2.DOWN
var pass_shape: Shape = Shape.ZIGZAG
## `&"lead"`, `&"fence"` (Open Space) or `&"assault"`; empty before the first plan of an APPROACH.
var pass_form: StringName = &""
var plan_frozen: bool = false
## The frame's f: the latched (or, for a moving player, read) direction the line is laid across.
var frame_f: Vector2 = Vector2.ZERO
## The lead scan's arrival time T (s).
var arrival_time: float = 0.0
## True when this plan took the spread fallback (no legal candidate, or a centre that drifted illegal by the freeze).
var pass_spread_fallback: bool = false
var planned_rest_points: Array[Vector2] = []
var planned_variants: Array[int] = []
var drops_this_pass: int = 0
var skipped_this_pass: int = 0
## LAY entries this life.
var passes_started: int = 0
var tail_drops: int = 0
## True from the run-in handover to LAY.
var run_in_active: bool = false
var spread_fallbacks: int = 0
var fence_fallbacks: int = 0
## Open Space: frozen passes given up because R could not be reached (the abandon guard).
var abandoned_passes: int = 0

var _started: bool = false
var _phase_time: float = 0.0
var _exit_dir: Vector2 = Vector2.DOWN
var _disengage_pending: bool = false
var _light_state: int = -1

var _v_bar: Vector2 = Vector2.ZERO
var _v_bar_ready: bool = false

# APPROACH / plan
var _frame_latched: bool = false
var _frame_moving: bool = false
var _axis_sign_value: float = 1.0
var _shift: float = 0.0
var _approach_time: float = 0.0
var _freeze_time: float = -1.0
var _near_time: float = -1.0
var _prev_s_from_start: float = -INF

# The path S -> mines -> E, its cumulative coordinates, and each mine's coordinate.
var _path: PackedVector2Array = PackedVector2Array()
var _path_s: PackedFloat64Array = PackedFloat64Array()
var _mine_s: PackedFloat64Array = PackedFloat64Array()
var _next_mine: int = 0

# Mines: the live FIFO (oldest first) and one record per laid pass, `{"centre": Vector2, "mines": Array}`.
var _live: Array = []
var _passes: Array = []
var _current_pass: Dictionary = {}

# BREAK_OFF / REPOSITION / tail
var _break_side: float = 1.0
var _reposition_time: float = 0.0
var _orbit_sign: float = 1.0
var _tail_clock: float = 0.0


func tick(delta: float) -> void:
	if not _started:
		_setup()
		_enter_approach()
	_phase_time += delta
	var target := TargetInfo.player(get_tree())
	_update_prediction(target, delta)
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	_tick_tail(delta, target)
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.LAY: _tick_lay(delta)
		Phase.BREAK_OFF: _tick_break_off(delta, target)
		Phase.REPOSITION: _tick_reposition(delta, target)
		Phase.DISENGAGE: _tick_disengage()


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_setup()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.APPROACH:
			_set_light(StateLight.State.OFF)
			_enter_approach()
		Phase.LAY:
			_set_light(StateLight.State.ARMED)
			_enter_lay()
		Phase.BREAK_OFF:
			_set_light(StateLight.State.OFF)
			_enter_break_off()
		Phase.REPOSITION:
			_set_light(StateLight.State.OFF)
			_enter_reposition()
		Phase.DISENGAGE:
			_enter_disengage()
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the layer over. The root's rail clock does the laying.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


## A committed phase is never moved by an ally (`BaseEnemy.accept_tow`).
func accepts_tow() -> bool:
	return phase != Phase.LAY


# ── Read-only seams ──────────────────────────────────────────────────────────────────────────────

## The player's smoothed velocity, v-bar.
func smoothed_velocity() -> Vector2:
	return _v_bar


## The polyline S -> mine 0 .. mine n-1 -> E of the current plan.
func path_points() -> PackedVector2Array:
	return _path


## This layer's live mines, oldest first.
func live_mines() -> Array:
	_prune()
	return _live.duplicate()


func live_mine_count() -> int:
	_prune()
	return _live.size()


## The centres of this layer's laid passes that still have a live mine (the spread's "earlier" centres).
func live_pass_centres() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(_passes.size() - 1, -1, -1):
		var rec: Dictionary = _passes[i]
		var alive := false
		for m in rec.mines:
			if is_instance_valid(m) and (m as EnemyMine).is_live():
				alive = true
				break
		if alive:
			out.push_front(rec.centre)
		elif not is_same(rec, _current_pass):
			_passes.remove_at(i)  # a record never comes back to life: a reused mine is removed from it on its next drop
	return out


## Seconds the layer needs to reach `point`: a straight run at `max_speed` plus the spin-up from its current speed toward
## it, `(max_speed - v0)^2 / (2 * acceleration * max_speed)`.
func flight_time(point: Vector2) -> float:
	var to := point - actor.global_position
	var dist := to.length()
	var vmax := maxf(config.max_speed, 1.0)
	var v0 := 0.0
	if dist > 0.0:
		v0 = clampf(_own_velocity().dot(to / dist), 0.0, vmax)
	var spin := 0.0
	if config.acceleration > 0.0:
		spin = (vmax - v0) * (vmax - v0) / (2.0 * config.acceleration * vmax)
	return dist / vmax + spin


## The lead form's run-in point R for an arrival time `t`, with the latched axis sign and spread shift.
func lead_run_in_point(p: Vector2, v_bar: Vector2, t: float) -> Vector2:
	return _lead_run_in(p, v_bar, t, _shift)


## Test seam: freezes the current plan where it stands.
func freeze_plan() -> void:
	_freeze(live_pass_centres())


## One planning step, exactly what a pre-freeze APPROACH tick does (the tick passes the live player position, v-bar and
## `live_pass_centres()`). A no-op once frozen. The frame is latched on the first plan of an APPROACH and on every
## standing / moving switch, which also re-chooses the spread candidate.
func plan_pass(p: Vector2, v_bar: Vector2, earlier: Array[Vector2]) -> void:
	if plan_frozen:
		return
	if _is_assault():
		_plan_assault(p)
		return
	var moving := v_bar.length() >= config.frame_speed
	var choose := false
	if not _frame_latched or moving != _frame_moving:
		_latch_frame(p, v_bar, moving)
		choose = true
		pass_spread_fallback = false  # a re-latch re-chooses the candidate: an earlier choice's fallback does not carry over
	if not moving:
		pass_form = &"fence"
		_plan_fence(p, earlier, choose)
		return
	pass_form = &"lead"
	if choose:
		_choose_shift(p, v_bar, earlier)
		return
	var t := _scan(p, v_bar, _shift)
	if t < 0.0:
		# Lost feasibility: the last feasible plan is frozen as it stands (not a fence fallback).
		_freeze(earlier)
		return
	_set_lead(p, v_bar, t, _shift)


## Lays one mine through `MineLayer.drop_mine()`, keeping the live FIFO: at the cap (`max_live_mines`, Assault
## `assault_max_live_mines`) the oldest is retired first. A pooled mine handed out again is dropped from every older
## record (`BulletPool.acquire()` is LIFO, so a retired mine of an early pass comes back in a later one).
func lay_mine(variant: int, rest_point: Vector2) -> EnemyMine:
	_prune()
	var cap := config.assault_max_live_mines if _is_assault() else config.max_live_mines
	while _live.size() >= maxi(cap, 1):
		var oldest: EnemyMine = _live.pop_front()
		oldest.retire()
	if actor == null or not actor.has_method(&"drop_mine"):
		return null
	var mine := actor.call(&"drop_mine", variant, rest_point) as EnemyMine
	if mine == null:
		return null
	_live.erase(mine)
	for rec in _passes:
		(rec.mines as Array).erase(mine)
	_live.append(mine)
	if phase == Phase.LAY and not _current_pass.is_empty():
		(_current_pass.mines as Array).append(mine)
		drops_this_pass += 1
	mine_dropped.emit(mine)
	return mine


# ── Setup and prediction ─────────────────────────────────────────────────────────────────────────

func _setup() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	_tail_clock = config.tail_drop_cooldown  # the first chase drop is immediate


func _is_assault() -> bool:
	return budget.active if budget != null else EnemyWorld.arena(get_tree()) != null


func _request_disengage() -> void:
	if phase == Phase.LAY:
		_disengage_pending = true  # the pass finishes first (<= the LAY stall guard)
		return
	enter_phase(Phase.DISENGAGE)


## The exponential moving average of the player's velocity, seeded from the first sample (the Bomber's shape).
func _update_prediction(target: TargetInfo, delta: float) -> void:
	if not target.has_target:
		return
	if not _v_bar_ready:
		_v_bar = target.velocity
		_v_bar_ready = true
		return
	var alpha := 1.0 if config.velocity_smoothing <= 0.0 else 1.0 - exp(-delta / config.velocity_smoothing)
	_v_bar += (target.velocity - _v_bar) * alpha


# ── Planning ─────────────────────────────────────────────────────────────────────────────────────

func _latch_frame(p: Vector2, v_bar: Vector2, moving: bool) -> void:
	_frame_latched = true
	_frame_moving = moving
	frame_f = v_bar.normalized() if moving else _toward_layer(p)
	_axis_sign_value = _axis_sign(frame_f, p)


## The sign that puts S (`C - u L / 2`) on the layer's side: `(-u).(layer - P) > 0`; on a tie the side the layer's
## velocity points to; with no velocity, +1.
func _axis_sign(f: Vector2, p: Vector2) -> float:
	var u0 := f.orthogonal()
	var d := u0.dot(actor.global_position - p)
	if absf(d) >= TIE_PX:
		return -signf(d)
	var dv := u0.dot(_own_velocity())
	if absf(dv) >= 1e-3:
		return -signf(dv)
	return 1.0


func _toward_layer(p: Vector2) -> Vector2:
	var to := actor.global_position - p
	return to.normalized() if to.length() > 0.001 else _heading()


## FENCE: `C = P + f * fence_distance`. On a choice the candidates are C itself, then C rotated about P by +theta,
## -theta, +2 theta, -2 theta (theta moves C by `min_pass_separation + SPREAD_EXTRA`); the first one clear of every
## earlier live centre is latched by rotating f, and the axis sign is re-applied to the rotated f.
func _plan_fence(p: Vector2, earlier: Array[Vector2], choose: bool) -> void:
	if choose:
		var base := frame_f
		var theta := 2.0 * asin(minf(1.0, (config.min_pass_separation + SPREAD_EXTRA) / (2.0 * maxf(config.fence_distance, 1.0))))
		var chosen := 0.0
		var legal := false
		for rot: float in [0.0, theta, -theta, 2.0 * theta, -2.0 * theta]:
			if _clear_of(p + base.rotated(rot) * config.fence_distance, earlier):
				chosen = rot
				legal = true
				break
		if not legal:
			_take_spread_fallback("fence")
		frame_f = base.rotated(chosen)
		_axis_sign_value = _axis_sign(frame_f, p)
	_set_plan(p + frame_f * config.fence_distance, frame_f.orthogonal() * _axis_sign_value, p, -frame_f)


## LEAD, first plan of the frame: each spread shift along the heading is scanned; the first feasible and legal one is
## latched. Some feasible but none legal: the first feasible (spread fallback). None feasible: the fence fallback.
func _choose_shift(p: Vector2, v_bar: Vector2, earlier: Array[Vector2]) -> void:
	var first_shift := -1.0
	var first_t := -1.0
	for shift: float in [0.0, config.min_pass_separation + SPREAD_EXTRA]:
		var t := _scan(p, v_bar, shift)
		if t < 0.0:
			continue
		if first_shift < 0.0:
			first_shift = shift
			first_t = t
		if _clear_of(_lead_centre(p, v_bar, t, shift), earlier):
			_shift = shift
			_set_lead(p, v_bar, t, shift)
			return
	if first_shift >= 0.0:
		_take_spread_fallback("lead")
		_shift = first_shift
		_set_lead(p, v_bar, first_t, first_shift)
		return
	_fence_fallback(p, earlier)


## A fresh standing-style frame (f = P -> layer), the fence form with its spread, frozen at once.
func _fence_fallback(p: Vector2, earlier: Array[Vector2]) -> void:
	_latch_frame(p, Vector2.ZERO, false)
	pass_form = &"fence"
	_plan_fence(p, earlier, true)
	fence_fallbacks += 1
	if OS.is_stdout_verbose():
		print("[MineLayerBrain] fence fallback #%d at %s" % [fence_fallbacks, pass_centre])
	_freeze(earlier)


## The earliest T in [0, lead_scan_cap] with `flight_time(R(T)) <= T`, or -1 when there is none.
func _scan(p: Vector2, v_bar: Vector2, shift: float) -> float:
	var prev := -1.0
	var t := 0.0
	while t <= config.lead_scan_cap + 1e-6:
		if _feasible(p, v_bar, t, shift):
			var hi := t
			if prev >= 0.0:
				var lo := prev
				for _k in ARRIVAL_BISECTIONS:
					var mid := (lo + hi) * 0.5
					if _feasible(p, v_bar, mid, shift):
						hi = mid
					else:
						lo = mid
			return hi
		prev = t
		t += ARRIVAL_SCAN_STEP
	return -1.0


func _feasible(p: Vector2, v_bar: Vector2, t: float, shift: float) -> bool:
	return flight_time(_lead_run_in(p, v_bar, t, shift)) <= t


## `t_lead(T) = T + run_in / lay_speed + min((L / 2) / lay_speed + mine_arm_delay, lead_horizon)`.
func _t_lead(t: float) -> float:
	var lay := maxf(config.lay_speed, 1.0)
	return t + config.run_in / lay + minf(config.pass_length * 0.5 / lay + config.mine_arm_delay, config.lead_horizon)


func _lead_centre(p: Vector2, v_bar: Vector2, t: float, shift: float) -> Vector2:
	return p + v_bar * _t_lead(t) + v_bar.normalized() * (config.ahead_distance + shift)


func _lead_run_in(p: Vector2, v_bar: Vector2, t: float, shift: float) -> Vector2:
	var u := v_bar.normalized().orthogonal() * _axis_sign_value
	return _lead_centre(p, v_bar, t, shift) - u * (config.pass_length * 0.5 + config.run_in)


func _set_lead(p: Vector2, v_bar: Vector2, t: float, shift: float) -> void:
	arrival_time = t
	frame_f = v_bar.normalized()
	_set_plan(_lead_centre(p, v_bar, t, shift), frame_f.orthogonal() * _axis_sign_value, p, -frame_f)


## ASSAULT: a horizontal axis with S on the layer's side (latched), `C = (P.x, P.y - assault_ahead)` clamped so C, S and E
## lie in `view_rect().grow(-(view_margin + max(zigzag_amplitude, arc_depth)))`.
func _plan_assault(p: Vector2) -> void:
	pass_form = &"assault"
	if not _frame_latched:
		_frame_latched = true
		var dx := actor.global_position.x - p.x
		var sx := 1.0
		if absf(dx) >= TIE_PX:
			sx = -signf(dx)
		elif absf(_own_velocity().x) >= 1e-3:
			sx = -signf(_own_velocity().x)
		pass_axis = Vector2(sx, 0.0)
	frame_f = Vector2.UP
	var c := Vector2(p.x, p.y - config.assault_ahead)
	var view := EnemyWorld.view_rect(get_tree())
	if view.has_area():
		var rect := view.grow(-(config.view_margin + maxf(config.zigzag_amplitude, config.arc_depth)))
		var half := config.pass_length * 0.5
		var lo := rect.position.x + half
		var hi := rect.end.x - half
		c.x = clampf(c.x, lo, hi) if lo <= hi else rect.get_center().x
		c.y = clampf(c.y, rect.position.y, rect.end.y)
	_set_plan(c, pass_axis, p, Vector2.DOWN)


func _clear_of(c: Vector2, earlier: Array[Vector2]) -> bool:
	for e in earlier:
		if c.distance_to(e) < config.min_pass_separation:
			return false
	return true


func _take_spread_fallback(form: String) -> void:
	spread_fallbacks += 1
	pass_spread_fallback = true
	if OS.is_stdout_verbose():
		print("[MineLayerBrain] spread fallback #%d (%s)" % [spread_fallbacks, form])


func _freeze(earlier: Array[Vector2]) -> void:
	if plan_frozen:
		return
	plan_frozen = true
	_freeze_time = _approach_time
	# A lead centre keeps moving after its candidate was chosen: a plan that froze too close to an earlier centre is a
	# spread fallback too (counted once).
	if not pass_spread_fallback and not _is_assault() and not _clear_of(pass_centre, earlier):
		_take_spread_fallback("drift")


## Builds S, E, R, the rest points and the path from the centre `c`, the unit axis `u`, the player at `p` and the normal to
## use when the player is on the axis (`tie_normal`).
func _set_plan(c: Vector2, u: Vector2, p: Vector2, tie_normal: Vector2) -> void:
	pass_centre = c
	pass_axis = u
	var n := u.orthogonal()
	var side := n.dot(p - c)
	if absf(side) < 1e-3:
		side = n.dot(tie_normal)
	pass_normal = n if side >= 0.0 else -n
	var half := config.pass_length * 0.5
	pass_start = c - u * half
	pass_end = c + u * half
	pass_run_in_point = pass_start - u * config.run_in
	planned_rest_points.clear()
	var count := maxi(config.mines_per_pass, 0)
	for k in count:
		var x := (k - (count - 1) * 0.5) * config.mine_step
		var y: float
		if pass_shape == Shape.ZIGZAG:
			y = config.zigzag_amplitude * (1.0 if k % 2 == 0 else -1.0)
		else:
			var t := float(k) / float(maxi(count - 1, 1))
			y = 4.0 * config.arc_depth * t * (1.0 - t)
		planned_rest_points.append(c + u * x + pass_normal * y)
	_path = PackedVector2Array()
	_path.append(pass_start)
	_path.append_array(PackedVector2Array(planned_rest_points))
	_path.append(pass_end)
	_path_s = PackedFloat64Array()
	_path_s.resize(_path.size())
	_path_s[0] = 0.0
	for i in range(1, _path.size()):
		_path_s[i] = _path_s[i - 1] + _path[i - 1].distance_to(_path[i])
	_mine_s = PackedFloat64Array()
	for k in count:
		_mine_s.append(_path_s[k + 1])


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _enter_approach() -> void:
	if mover != null:
		mover.max_speed = config.max_speed
	plan_frozen = false
	_frame_latched = false
	run_in_active = false
	pass_spread_fallback = false
	pass_form = &""
	_approach_time = 0.0
	_freeze_time = -1.0
	_near_time = -1.0
	_prev_s_from_start = -INF
	pass_shape = Shape.ARC if rng.randf() < config.arc_chance else Shape.ZIGZAG


func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_approach_time += delta
	var pos := actor.global_position
	var assault := _is_assault()
	if not plan_frozen:
		var earlier := live_pass_centres()
		plan_pass(target.position, _v_bar, earlier)
		if not plan_frozen and not assault and _approach_time >= config.approach_max_seconds:
			_fence_fallback(target.position, earlier)  # the backstop: no freeze in time
		if not plan_frozen and pos.distance_to(pass_run_in_point) <= config.commit_distance:
			_freeze(earlier)
	if not assault and _abandon_due(pos):
		abandoned_passes += 1
		if OS.is_stdout_verbose():
			print("[MineLayerBrain] pass abandoned #%d: R %s not reached" % [abandoned_passes, pass_run_in_point])
		enter_phase(Phase.REPOSITION)
		_tick_reposition(delta, target)
		return
	if not run_in_active:
		if plan_frozen and pos.distance_to(pass_run_in_point) <= config.path_lookahead:
			run_in_active = true
			_prev_s_from_start = (pos - pass_start).dot(pass_axis)
		else:
			mover.seek(pass_run_in_point, config.max_speed)
			return
	var from_start := (pos - pass_start).dot(pass_axis)
	if _prev_s_from_start < 0.0 and from_start >= 0.0:
		run_in_active = false
		enter_phase(Phase.LAY)
		_tick_lay(delta)
		return
	_prev_s_from_start = from_start
	var s := (pos - pass_run_in_point).dot(pass_axis)
	var aim := pass_run_in_point + pass_axis * (s + config.path_lookahead)
	mover.request_velocity((aim - pos).normalized() * config.lay_speed)


## Open Space: the abandon guard, three clocks. Frozen and within `commit_distance` of R without starting the run-in for
## `approach_max_seconds` (R held off by an older line: it would circle R); frozen and never within `commit_distance` for twice
## that; or in a run-in `RUN_IN_STALL_SECONDS` after the freeze (a run-in past an older line crawls at the context floor, but it
## finishes: this only stops one that never will).
func _abandon_due(pos: Vector2) -> bool:
	if not plan_frozen:
		return false
	var since_freeze := _approach_time - _freeze_time
	if run_in_active:
		return since_freeze >= RUN_IN_STALL_SECONDS
	if _near_time < 0.0 and pos.distance_to(pass_run_in_point) <= config.commit_distance:
		_near_time = _approach_time
	if _near_time >= 0.0:
		return _approach_time - _near_time >= config.approach_max_seconds
	return since_freeze >= 2.0 * config.approach_max_seconds


# ── LAY ──────────────────────────────────────────────────────────────────────────────────────────

func _enter_lay() -> void:
	passes_started += 1
	drops_this_pass = 0
	skipped_this_pass = 0
	_next_mine = 0
	_light_state = StateLight.State.ARMED
	_current_pass = {"centre": pass_centre, "mines": []}
	_passes.append(_current_pass)
	planned_variants.clear()
	var homing_used := false
	for _k in planned_rest_points.size():
		var v := _draw_variant(false)
		if v == EnemyMine.Variant.HOMING:
			if homing_used:
				v = _draw_variant(true)
			homing_used = true
		planned_variants.append(v)


## One variant from the flat `w_<variant>` weights by `rng` (PROXIMITY when they sum to 0).
func _draw_variant(no_homing: bool) -> int:
	var weights := [config.w_proximity, config.w_drifting, 0.0 if no_homing else config.w_homing,
		config.w_chain, config.w_pulse, config.w_emp]
	var total := 0.0
	for w: float in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return EnemyMine.Variant.PROXIMITY
	var r := rng.randf() * total
	for i in weights.size():
		r -= maxf(weights[i], 0.0)
		if r < 0.0:
			return i
	return EnemyMine.Variant.PROXIMITY


func _tick_lay(delta: float) -> void:
	if _path.size() < 2:
		_finish_lay(delta)
		return
	var pos := actor.global_position
	var s_c := _path_coord(pos)
	var s_d := _path_coord(_dispenser_pos())
	var lead := _eject_lead()
	while _next_mine < _mine_s.size() and s_d >= _mine_s[_next_mine] + lead:
		_drop_pass_mine(_next_mine)
		_next_mine += 1
	var length := _path_s[_path_s.size() - 1]
	if s_c >= length or _phase_time >= length * STALL_FACTOR / maxf(config.lay_speed, 1.0) + STALL_SLACK:
		_finish_lay(delta)
		return
	var charging := _next_mine < _mine_s.size() and _mine_s[_next_mine] + lead - s_d <= config.lay_speed * CHARGE_TIME
	_set_light_once(StateLight.State.CHARGING if charging else StateLight.State.ARMED)
	var aim := _point_at(s_c + config.path_lookahead)
	_lay_drive((aim - pos).normalized() * config.lay_speed, delta)


## The committed run (the pre-approved §2.12 lever, in its acceleration-limited form): an older line's mines across the
## path would otherwise push the layer off it (avoidance turned it 85 deg and 178 px off the line), so LAY bypasses the
## avoidance stage through `boost()`, one tick at a time, while still turning at the mover's own `acceleration`.
func _lay_drive(desired: Vector2, delta: float) -> void:
	var v := _own_velocity().move_toward(desired, config.acceleration * delta)
	if v.length() < 0.001:
		mover.request_velocity(desired)
		return
	mover.boost(v.normalized(), v.length(), delta)


## Whatever was not dropped goes now, so a pass always delivers its pattern. The next phase ticks at once, as LAY does
## on the tick it starts, so no tick goes by with no request.
func _finish_lay(delta: float) -> void:
	while _next_mine < _mine_s.size():
		_drop_pass_mine(_next_mine)
		_next_mine += 1
	if _disengage_pending or _is_assault():
		enter_phase(Phase.DISENGAGE)  # Assault: one pass per life
		_tick_disengage()
	else:
		enter_phase(Phase.BREAK_OFF)
		_tick_break_off(delta, TargetInfo.player(get_tree()))


func _drop_pass_mine(k: int) -> void:
	var rest := planned_rest_points[k]
	if not _is_assault() and _stacked(rest):
		skipped_this_pass += 1
		return
	var variant := planned_variants[k] if k < planned_variants.size() else EnemyMine.Variant.PROXIMITY
	lay_mine(variant, rest)


## Open Space no-stacking: a live mine (any layer's or field's, through the hazard registry, or one of ours) other than
## this pass's own within its `trigger_radius + NO_STACK_PAD` of `rest`.
func _stacked(rest: Vector2) -> bool:
	var own: Array = _current_pass.get("mines", [])
	for info: HazardInfo in Hazards.around(rest, 0.0):
		if info.kind != &"mine":
			continue
		var m := info.source as EnemyMine
		if m != null and _stacks_on(m, rest, own):
			return true
	for m in _live:
		if is_instance_valid(m) and _stacks_on(m, rest, own):
			return true
	return false


func _stacks_on(m: EnemyMine, rest: Vector2, own: Array) -> bool:
	return not own.has(m) and m.is_live() and m.global_position.distance_to(rest) <= m.trigger_radius + NO_STACK_PAD


func _eject_lead() -> float:
	return config.mine_eject_speed * config.mine_eject_time * 0.5


## The coordinate along the path of the point on it closest to `point`.
func _path_coord(point: Vector2) -> float:
	var best_d := INF
	var best_s := 0.0
	for i in _path.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(point, _path[i], _path[i + 1])
		var d := point.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_s = _path_s[i] + _path[i].distance_to(q)
	return best_s


## The path point at coordinate `s`; past E, along the axis.
func _point_at(s: float) -> Vector2:
	var last := _path.size() - 1
	if s >= _path_s[last]:
		return _path[last] + pass_axis * (s - _path_s[last])
	for i in last:
		if s <= _path_s[i + 1]:
			var span := _path_s[i + 1] - _path_s[i]
			return _path[i].lerp(_path[i + 1], (s - _path_s[i]) / span if span > 0.0 else 0.0)
	return _path[last]


# ── BREAK_OFF / REPOSITION ───────────────────────────────────────────────────────────────────────

func _enter_break_off() -> void:
	mover.max_speed = maxf(config.max_speed, config.break_speed)  # the mover caps every request at max_speed
	var target := TargetInfo.player(get_tree())
	var away := (actor.global_position - target.position).normalized() if target.has_target else Vector2.ZERO
	# `Steering.break_contact`'s lateral is `away.orthogonal() * side`: make it point off the far end of the line.
	_break_side = 1.0 if away.orthogonal().dot(pass_axis) >= 0.0 else -1.0


func _tick_break_off(delta: float, target: TargetInfo) -> void:
	if _phase_time >= config.break_seconds:
		enter_phase(Phase.REPOSITION)
		_tick_reposition(delta, target)
		return
	if not target.has_target:
		mover.request_velocity(_heading() * config.break_speed)
		return
	mover.break_contact(target.position, _v_bar, _break_side, config.break_speed)


func _enter_reposition() -> void:
	mover.max_speed = config.max_speed
	_reposition_time = rng.randf_range(config.pass_period_min, config.pass_period_max)
	_orbit_sign = -1.0 if rng.randf() < 0.5 else 1.0


## The Bomber's orbit at `standoff_range`, its anchor `REPOSITION_LEAD` ahead of the layer's bearing.
func _tick_reposition(delta: float, target: TargetInfo) -> void:
	if _phase_time >= _reposition_time:
		enter_phase(Phase.APPROACH)
		_tick_approach(delta, target)
		return
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var pos := actor.global_position
	var angle := (pos - target.position).angle() + _orbit_sign * REPOSITION_LEAD
	var want := Steering.orbit(pos, target.position, config.standoff_range, angle, config.max_speed)
	var dir := Steering.turn_toward(_heading(), want, config.max_turn_rate, delta)
	mover.request_velocity(dir * want.length())


# ── Tail drop ────────────────────────────────────────────────────────────────────────────────────

## Any engaged phase but LAY: a player within `tail_range` of the Dispenser inside the rear cone (half-angle
## `tail_cone_deg / 2` about the stern) gets a PROXIMITY mine at the Dispenser, no eject, at most every
## `tail_drop_cooldown`.
func _tick_tail(delta: float, target: TargetInfo) -> void:
	_tail_clock += delta
	match phase:
		Phase.APPROACH, Phase.BREAK_OFF, Phase.REPOSITION, Phase.DISENGAGE:
			pass
		_:
			return
	if not target.has_target or _tail_clock < config.tail_drop_cooldown:
		return
	var at := _dispenser_pos()
	var to := target.position - at
	if to.length() > config.tail_range:
		return
	var stern := -Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))
	if to.length() > 0.001 and absf(stern.angle_to(to)) > deg_to_rad(config.tail_cone_deg * 0.5):
		return
	_tail_clock = 0.0
	tail_drops += 1
	lay_mine(EnemyMine.Variant.PROXIMITY, at)


# ── DISENGAGE ────────────────────────────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	_set_light(StateLight.State.OFF)
	_disengage_pending = false
	# Off the far side of the line it laid; with no pass laid, along the heading it had on entry.
	_exit_dir = pass_axis if passes_started > 0 else _heading()
	mover.release_constraint()
	mover.max_speed = config.exit_speed


## Straight out along the exit direction. Strict `<`/`>` against the rect's edges, as the Bomber's exit.
func _tick_disengage() -> void:
	if EnemyWorld.has_projectile_world_rect(get_tree()):
		var rect := EnemyWorld.projectile_world_rect(get_tree())
		var pos := actor.global_position
		if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
			actor.queue_free()
			return
	mover.request_velocity(_exit_dir * config.exit_speed)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var m: Variant = _live[i]
		if not is_instance_valid(m) or not (m as EnemyMine).is_live():
			_live.remove_at(i)


func _own_velocity() -> Vector2:
	return mover.own_velocity() if mover != null else actor.velocity


func _dispenser_pos() -> Vector2:
	var d := actor.get_node_or_null("Dispenser") as Node2D
	return d.global_position if d != null else actor.global_position


## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	_light_state = state
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)


func _set_light_once(state: int) -> void:
	if state != _light_state:
		_set_light(state)
