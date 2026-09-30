## The Fighter's brain: attack runs (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4, §2.8;
## task plan docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md, Revision 2 — read it for the numbers).
##
## A pass is a bearing `b` (the side the run comes from), a run direction `u = −b` and a lane `l ⟂ u`
## (the side and distance it passes the player at). The run starts at `S = P̂ + b·standoff_radius + l`,
## on the pass line `P̂ + l + u·t`, so the closest approach equals `|l|`.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   a Dubins lead-in to the first pass's start S, arriving pointing along the
##                           run. Inside the breach radius (derived from S) it starts a FRONTAL-shaped
##                           pass from where it is instead of circling the player.
##   RUN_IN     [ATTACK]     path following along the pass line, `lookahead` ahead of the fighter's own
##                           projection; the lane's sideways velocity is fed forward. Ends at the
##                           closest approach, `(P̂ − X)·u < 0`. Burst opportunity (a).
##   EXTEND     [ATTACK]     holds the heading until ≥ 350 px from the player (0.6–1.5 s).
##   TURN       [REPOSITION] the visible wide turn: back in toward the player at full rate until the
##                           nose is on it (burst opportunity (b), the snapshot), then a break-away
##                           arc — the first arc of the REPOSITION path.
##   REPOSITION [REPOSITION] the rest of a Dubins lead-in to the next S, clear of
##                           `reposition_min_radius`; the epic's ring routing when no clear path
##                           exists. After `passes` passes, Open Space loiters at S for
##                           `regroup_seconds` first.
##   DISENGAGE  [DISENGAGE]  Assault only: budget expiry or `passes` done (deferred to the end of a
##                           running burst); release the corridor, curve out of the world rect, free.
##
## The pass is re-derived every tick until RUN_IN (so it follows the player's heading and, in t9, the
## squad role) and latched from RUN_IN entry to EXTEND's end, lead time included.
##
## Weapons are an independent layer ticked before the phase logic: at most one burst per leg (leg A =
## RUN_IN/EXTEND, leg B = TURN), `min_burst_period` apart; the mode is chosen by distance with
## hysteresis and latched for the burst; FORWARD needs the nose on the player and, while it fires,
## the nose (not the path) is held on the player. A `burst_telegraph` CHARGING light precedes every
## burst.
##
## Rails (§2.8, X1): `on_suspended()` hands `AttackController` back to self-timed legacy fire.
## `aim_mode` is read there and nowhere else: an AI fighter ignores it.
##
## Requests only (single-writer gate): the field writes on the mover are `max_speed` and
## `release_constraint()` on DISENGAGE.
class_name FighterBrain
extends EnemyBrain

## t12 appends IDLE, NOTICING and RETURNING.
enum Phase { APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE }
## The shape of a pass (epic §2.4.1). The solo alternation uses the flank shapes at `pass_offset`;
## squad roles (t9, and the `forced_pass_kind` seam) use FLANK_RIGHT's outer lane.
enum PassKind { FLANK_LEFT, FLANK_RIGHT, FRONTAL }
enum WeaponMode { AIMED, FORWARD }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)
## Emitted when a burst starts in a different mode from the last burst.
signal weapon_mode_changed(mode: int)

## The player-lead window P̂ uses (s).
const LEAD_MIN := 0.3
const LEAD_MAX := 0.8
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## Rail fire leaves from this far behind the hull's centre along local +y, as it always did (px).
const RAIL_SPAWN_OFFSET := Vector2(0.0, 10.0)
## Open Space `h` follows the player's velocity above this speed, else its facing (px/s).
const HEADING_REF_MIN_SPEED := 40.0
## EXTEND (epic §2.4.1).
const EXTEND_MIN_DISTANCE := 350.0
const EXTEND_MIN_SECONDS := 0.6
const EXTEND_MAX_SECONDS := 1.5
## RUN_IN hands over when the heading is within this of the run heading (deg).
const HANDOVER_HEADING_DEG := 30.0
## Controller tolerances (task plan §5), not balance.
const REPLAN_GOAL_PX := 24.0
const REPLAN_OFF_PATH_PX := 40.0
const PLAN_RADIUS_FACTOR := 1.1
const PLAN_SAMPLE_PX := 16.0
const TRACK_SAMPLE_PX := 8.0
const TRACK_SEARCH := 12
const TRACK_AHEAD := 3
const BREACH_MARGIN := 24.0
const BREAK_CLEARANCE_FACTOR := 0.75
const CORRIDOR_SLACK := 60.0
## Assault: EXTEND ends when the point this far ahead (s) leaves the corridor; the ring fallback keeps
## this far inside it (px) — the prototyped rules (review I7).
const EXTEND_CORRIDOR_LOOKAHEAD := 0.3
const RING_CORRIDOR_MARGIN := 200.0
const LOITER_SPEED := 60.0
const LOITER_GAIN := 2.0
## A moving player's goal is predicted at most this far ahead (s), refined this many times.
const GOAL_PREDICT_MAX := 3.0
const GOAL_PREDICT_ITERATIONS := 3
## The peel gives up after this (s). (The turn-in gives up after a full circle, review I4.)
const PEEL_MAX_SECONDS := 2.5
## Hull radius used when the scene has no readable body circle (px).
const DEFAULT_HULL_RADIUS := 28.0

## Set by `fighter.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: FighterConfig = FighterConfig.new()
## The rail fallback's aim mode, resolved once by `fighter.gd`: the spawn prop if set, else the
## config default. "FORWARD" or "PLAYER".
var rail_aim_mode: String = "PLAYER"
## The sibling `AttackController` past `attack` (`ForwardAttack`), or null.
var forward_attack: AttackController
## Test seam (and t9's hook): ≥ 0 makes every pass this `PassKind`, with its role-shaped lane.
var forced_pass_kind: int = -1

var phase: Phase = Phase.APPROACH
## Built on the first tick. Null before it.
var budget: EngagementBudget

## The current (or, before RUN_IN, the next) pass. Read-only outside this script.
var pass_kind: int = PassKind.FLANK_RIGHT
var pass_bearing: Vector2 = Vector2.RIGHT
var pass_dir: Vector2 = Vector2.LEFT
var pass_lane: Vector2 = Vector2.ZERO
## The FRONTAL lane side σ (+1 = `right(h)`), or the side the breach pass took.
var pass_side: float = 1.0
## This tick's predicted player position P̂, the pass line's anchor.
var pass_anchor: Vector2 = Vector2.ZERO
var pass_start: Vector2 = Vector2.ZERO
## The point the fighter is steering at this tick.
var seek_target: Vector2 = Vector2.ZERO
var passes_done: int = 0
## The mode of the last burst started. Read-only outside this script.
var weapon_mode: int = WeaponMode.AIMED

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _hull_radius: float = DEFAULT_HULL_RADIUS

# Pass state.
var _latched: bool = false
var _pass_prepared: bool = false
var _lead: float = LEAD_MAX
var _run_heading: Vector2 = Vector2.LEFT
var _next_solo_kind: int = -1
var _frontal_sigma: float = 0.0
var _regroup_pending: bool = false
var _loiter_time: float = -1.0

# Lead-in path.
var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_idx: int = 0
## S when the path was planned, the player velocity then, and the seconds flown since: a moving
## player's S is expected at `_path_goal + _path_goal_velocity × _path_age`, and only a departure
## from that track re-plans (review I5).
var _path_goal: Vector2 = Vector2.INF
var _path_goal_velocity: Vector2 = Vector2.ZERO
var _path_age: float = 0.0
var _path_first_end: int = 0
var _path_length: float = 0.0
var _deadline: float = INF
var _deadline_from_plan: bool = false

# TURN: 0 = turn-in, 1 = break-away arc, 2 = peel.
var _turn_step: int = 0
var _turn_sign: float = 1.0

# Weapons.
var _leg_a_open: bool = false
var _leg_b_open: bool = false
var _since_burst: float = INF
var _telegraph_left: float = -1.0
var _clock := BurstClock.new()
var _burst_mode: int = WeaponMode.AIMED
var _burst_controller: AttackController
var _disengage_pending: bool = false


func _ready() -> void:
	super._ready()
	var parent := get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling is AttackController and sibling != attack:
			forward_attack = sibling
			break
	var body := parent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is CircleShape2D:
		_hull_radius = (body.shape as CircleShape2D).radius * absf(body.scale.x)


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	_since_burst += delta
	var target := TargetInfo.player(get_tree())
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	_tick_weapons(delta, target)
	var was := phase
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.RUN_IN: _tick_run_in(delta, target)
		Phase.EXTEND: _tick_extend(target)
		Phase.TURN: _tick_turn(delta, target)
		Phase.REPOSITION: _tick_reposition(delta, target)
		Phase.DISENGAGE: _tick_disengage(delta)
	if phase == Phase.RUN_IN and was != Phase.RUN_IN:
		_steer_run_in(delta, target)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.APPROACH, Phase.REPOSITION:
			_deadline = config.reposition_max
			_deadline_from_plan = false
			_loiter_time = -1.0
			if p == Phase.REPOSITION and not _path_pts.is_empty():
				_set_deadline_from_path()
		Phase.RUN_IN:
			_enter_run_in()
		Phase.EXTEND:
			pass
		Phase.TURN:
			_enter_turn()
		Phase.DISENGAGE:
			_enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. Self-timed fire from the same pool, from
## config fields (`rail_*`), so the round-lifetime sweep reads the same numbers the rail fires with.
func on_suspended() -> void:
	_abort_burst()
	_set_light(StateLight.State.OFF)
	if forward_attack != null:
		forward_attack.enabled = false
	if attack == null:
		return
	var forward := rail_aim_mode == "FORWARD"
	var pattern := AimedAttackPattern.new()
	pattern.fire_interval = config.rail_forward_interval if forward else config.fire_interval
	pattern.bullet_damage = config.bullet_damage
	pattern.bullet_speed = config.rail_forward_speed if forward else config.rail_aimed_speed
	pattern.aim_at_player = not forward
	pattern.accuracy = 0.0
	pattern.spawn_offset = RAIL_SPAWN_OFFSET
	attack.pattern = pattern
	attack.driven_by_brain = false
	attack.enabled = true


## The mode a burst opportunity at distance `d` takes: FORWARD below `forward_range`, AIMED from
## `forward_range + mode_hysteresis`, and the last burst's mode in between.
func select_weapon_mode(d: float) -> int:
	if d < config.forward_range:
		return WeaponMode.FORWARD
	if d >= config.forward_range + config.mode_hysteresis:
		return WeaponMode.AIMED
	return weapon_mode


## True while a burst's telegraph or its shots are running.
func is_bursting() -> bool:
	return _telegraph_left >= 0.0 or _clock.is_running()


## The turn radius the attack run flies at full rate (px).
func turn_radius() -> float:
	return config.max_speed / config.turn_rate if config.turn_rate > 0.0 else INF


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	_deadline = config.reposition_max


# ── Pass geometry (epic §2.4.1) ──────────────────────────────────────────────────────────────────

## The heading reference `h`: UP in the corridor, else the player's velocity or facing.
func _heading_ref(target: TargetInfo) -> Vector2:
	if _corridor().has_area():
		return Vector2.UP
	if target.velocity.length() > HEADING_REF_MIN_SPEED:
		return target.velocity.normalized()
	return target.facing if target.facing != Vector2.ZERO else Vector2.UP


## Re-derives the pass from this tick's world, unless it is latched (RUN_IN to EXTEND's end).
func _derive_pass(target: TargetInfo) -> void:
	if _latched or not target.has_target:
		return
	var pos := actor.global_position
	_lead = Steering.clamped_lead_time(pos.distance_to(target.position), config.max_speed, LEAD_MIN, LEAD_MAX)
	var anchor := target.predicted_position(_lead)
	var h := _heading_ref(target)
	var right := h.rotated(PI / 2.0)
	var kind := _kind_for(right, pos - anchor)
	var b: Vector2
	var l: Vector2
	var side := 1.0
	match kind:
		PassKind.FLANK_LEFT:
			b = h.rotated(-PI / 2.0)
			l = h * config.pass_offset
		PassKind.FLANK_RIGHT:
			b = right
			var lane := config.pass_offset
			if forced_pass_kind >= 0:
				lane += config.flank_lane_gap
			l = h * lane
		_:
			b = h
			side = _frontal_sigma
			if side == 0.0:
				side = -1.0 if right.dot(pos - anchor) < 0.0 else 1.0
			l = right * side * config.pass_offset
	var rect := _corridor()
	if rect.has_area():
		if kind == PassKind.FRONTAL:
			var lane_x := anchor.x + l.x
			if lane_x - _hull_radius < rect.position.x or lane_x + _hull_radius > rect.end.x:
				side = -side
				l = -l
		elif anchor.y + l.y - _hull_radius < rect.position.y:
			l = -l  # the ahead lane does not fit under the corridor top: pass behind
	var s := anchor + b * config.standoff_radius + l
	if rect.has_area():
		s = _clamp_run(s, b, rect)
		if (anchor + l - s).dot(-b) < config.min_run_length:
			b = -b
			s = _clamp_run(anchor + b * config.standoff_radius + l, b, rect)
	pass_kind = kind
	pass_bearing = b
	pass_dir = -b
	pass_lane = l
	pass_side = side
	pass_anchor = anchor
	pass_start = s
	_run_heading = _ground_run_heading(pass_dir, target.velocity)


func _kind_for(right: Vector2, offset: Vector2) -> int:
	if forced_pass_kind >= 0:
		return forced_pass_kind
	if _next_solo_kind >= 0:
		return _next_solo_kind
	return PassKind.FLANK_LEFT if right.dot(offset) < 0.0 else PassKind.FLANK_RIGHT


## Clamps S along the run axis only (so it stays on the pass line), into the corridor shrunk by the
## lead-in loop's diameter plus the hull, so the loop that ends at S fits.
func _clamp_run(s: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var margin := 2.0 * _plan_radius() + _hull_radius
	if absf(b.x) >= absf(b.y):
		s.x = clampf(s.x, rect.position.x + margin, maxf(rect.position.x + margin, rect.end.x - margin))
	else:
		s.y = clampf(s.y, rect.position.y + margin, maxf(rect.position.y + margin, rect.end.y - margin))
	return s


## The heading that holds a pass line moving with the player: its sideways velocity plus the rest of
## `max_speed` along `u` (`u` itself for a holding player).
func _ground_run_heading(u: Vector2, player_velocity: Vector2) -> Vector2:
	var v_perp := player_velocity - u * player_velocity.dot(u)
	var along := sqrt(maxf(config.max_speed * config.max_speed - v_perp.length_squared(), 0.0))
	var g := v_perp + u * along
	return g.normalized() if g != Vector2.ZERO else u


## The pass the solo alternation flies after this one.
func _complete_pass() -> void:
	passes_done += 1
	_latched = false
	if pass_kind == PassKind.FRONTAL:
		_frontal_sigma = -pass_side
	if forced_pass_kind < 0:
		match pass_kind:
			PassKind.FLANK_LEFT: _next_solo_kind = PassKind.FLANK_RIGHT
			PassKind.FLANK_RIGHT: _next_solo_kind = PassKind.FLANK_LEFT
			_: _next_solo_kind = -1
	var cycle_done := config.passes > 0 and passes_done % config.passes == 0
	if cycle_done and budget.active:
		_request_disengage()
		if phase == Phase.DISENGAGE:
			return
	elif cycle_done:
		_regroup_pending = true
	enter_phase(Phase.TURN)


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_derive_pass(target)
	var clear := minf(config.standoff_radius, pass_start.distance_to(pass_anchor)) - 1.0
	if actor.global_position.distance_to(target.position) < clear - BREACH_MARGIN:
		_begin_breach_pass(target)
		return
	_fly_to_start(delta, target, clear, -1.0)
	if _at_start():
		enter_phase(Phase.RUN_IN)
	elif _phase_time >= _deadline:
		_begin_breach_pass(target)


## A FRONTAL-shaped pass from where the fighter is (epic §2.4.1 APPROACH; review N9): the lane is
## perpendicular to the NEW run direction, on the side the fighter is already drifting to.
func _begin_breach_pass(target: TargetInfo) -> void:
	var pos := actor.global_position
	_lead = Steering.clamped_lead_time(pos.distance_to(target.position), config.max_speed, LEAD_MIN, LEAD_MAX)
	var anchor := target.predicted_position(_lead)
	var b := (pos - anchor).normalized()
	if b == Vector2.ZERO:
		b = -_heading()
	var u := -b
	var right := u.rotated(PI / 2.0)
	var side := -1.0 if right.dot(_heading()) < 0.0 else 1.0
	pass_kind = PassKind.FRONTAL
	pass_bearing = b
	pass_dir = u
	pass_lane = right * side * config.pass_offset
	pass_side = side
	pass_anchor = anchor
	pass_start = pos
	_run_heading = _ground_run_heading(u, target.velocity)
	_pass_prepared = true
	enter_phase(Phase.RUN_IN)


# ── RUN_IN ───────────────────────────────────────────────────────────────────────────────────────

func _enter_run_in() -> void:
	_clear_path()
	if not _pass_prepared:
		_derive_pass(TargetInfo.player(get_tree()))
	_pass_prepared = false
	_latched = true
	_leg_a_open = true
	_regroup_pending = false
	_loiter_time = -1.0


func _tick_run_in(delta: float, target: TargetInfo) -> void:
	_steer_run_in(delta, target)
	if not target.has_target:
		return
	if (pass_anchor - actor.global_position).dot(pass_dir) < 0.0 or _phase_time >= config.run_in_max:
		enter_phase(Phase.EXTEND)


## The pass line's path following. Also flown on the tick RUN_IN is entered, so the run's first
## request is already along the line (and `seek_target` is a lookahead ahead from that tick on).
func _steer_run_in(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(_heading() * config.max_speed)
		return
	pass_anchor = target.predicted_position(_lead)
	var pos := actor.global_position
	var u := pass_dir
	var a := pass_anchor + pass_lane
	var s := (pos - a).dot(u)
	seek_target = a + u * (s + config.lookahead)
	var v_perp := target.velocity - u * target.velocity.dot(u)
	var along := sqrt(maxf(config.max_speed * config.max_speed - v_perp.length_squared(), 0.0))
	var desired := v_perp + (seek_target - pos).normalized() * along
	var dir := Steering.turn_toward(_heading(), desired, config.turn_rate, delta)
	mover.request_velocity(dir * config.max_speed)


# ── EXTEND ───────────────────────────────────────────────────────────────────────────────────────

func _tick_extend(target: TargetInfo) -> void:
	var heading := _heading()
	mover.request_velocity(heading * config.max_speed)
	var pos := actor.global_position
	var d := pos.distance_to(target.position) if target.has_target else INF
	var done := (_phase_time >= EXTEND_MIN_SECONDS and d >= EXTEND_MIN_DISTANCE) \
			or _phase_time >= EXTEND_MAX_SECONDS
	var rect := _corridor()
	if rect.has_area() and not rect.grow(-_hull_radius).has_point(pos + heading * config.max_speed * EXTEND_CORRIDOR_LOOKAHEAD):
		done = true
	if done:
		_complete_pass()


# ── TURN: turn back in, snapshot, break away ─────────────────────────────────────────────────────

func _enter_turn() -> void:
	_clear_path()
	_turn_step = 0
	_leg_b_open = true
	var target := TargetInfo.player(get_tree())
	var heading := _heading()
	var to_player := (target.position - actor.global_position) if target.has_target else heading
	_turn_sign = -1.0 if heading.angle_to(to_player) < 0.0 else 1.0
	var rect := _corridor()
	if rect.has_area():
		# The short way round must fit the corridor; if only the long way does, take it.
		var room := rect.grow(CORRIDOR_SLACK - turn_radius())
		var short_centre := actor.global_position + heading.rotated(_turn_sign * PI / 2.0) * turn_radius()
		var long_centre := actor.global_position + heading.rotated(-_turn_sign * PI / 2.0) * turn_radius()
		if not room.has_point(short_centre) and room.has_point(long_centre):
			_turn_sign = -_turn_sign


func _tick_turn(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(_heading() * config.max_speed)
		return
	_derive_pass(target)
	var pos := actor.global_position
	match _turn_step:
		0:
			var heading := _heading()
			var to_player := target.position - pos
			var remaining := fposmod(_turn_sign * heading.angle_to(to_player), TAU)
			var desired := heading.rotated(_turn_sign * minf(remaining, PI * 0.99))
			seek_target = target.position
			mover.request_velocity(Steering.turn_toward(heading, desired, config.turn_rate, delta) * config.max_speed)
			if _nose_on(target) or _phase_time >= TAU / config.turn_rate:
				var break_clear := config.pass_offset * BREAK_CLEARANCE_FACTOR
				_turn_step = 1 if _plan(target, config.reposition_min_radius, break_clear) else 2
				_phase_time = 0.0
		1:
			if pos.distance_to(_path_pts[_path_idx]) > REPLAN_OFF_PATH_PX:
				_turn_step = 2
				_clear_path()
				return
			_track(delta)
			if _path_idx >= _path_first_end:
				enter_phase(Phase.REPOSITION)
		_:
			var away := pos - target.position
			seek_target = pos + away
			mover.request_velocity(Steering.turn_toward(_heading(), away, config.turn_rate, delta) * config.max_speed)
			if away.length() >= config.reposition_min_radius or _phase_time >= PEEL_MAX_SECONDS:
				enter_phase(Phase.REPOSITION)


# ── REPOSITION ───────────────────────────────────────────────────────────────────────────────────

func _tick_reposition(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_derive_pass(target)
	if _loiter_time >= 0.0:
		_tick_loiter(delta, target)
		return
	_fly_to_start(delta, target, config.reposition_min_radius, -1.0)
	if _at_start():
		if _regroup_pending:
			_loiter_time = 0.0
		else:
			enter_phase(Phase.RUN_IN)
	elif _phase_time >= _deadline:
		_begin_breach_pass(target)


## Holds S (which moves with the player) with the nose along the run; only the correction toward S
## is capped, so a moving player's S can still be held.
func _tick_loiter(delta: float, target: TargetInfo) -> void:
	_loiter_time += delta
	var correction := ((pass_start - actor.global_position) * LOITER_GAIN).limit_length(LOITER_SPEED)
	seek_target = pass_start
	mover.request_velocity(target.velocity + correction)
	mover.face_toward(actor.global_position + pass_dir * 100.0)
	if _loiter_time >= config.regroup_seconds:
		enter_phase(Phase.RUN_IN)


func _at_start() -> bool:
	return actor.global_position.distance_to(pass_start) <= config.start_tolerance \
			and absf(_heading().angle_to(_run_heading)) <= deg_to_rad(HANDOVER_HEADING_DEG)


# ── Lead-in paths (task plan §3) ─────────────────────────────────────────────────────────────────

func _plan_radius() -> float:
	return turn_radius() * PLAN_RADIUS_FACTOR


## Plans (when needed) and tracks a Dubins lead-in to S; the epic's ring routing with no clear path.
func _fly_to_start(delta: float, target: TargetInfo, clearance: float, first_clearance: float) -> void:
	var pos := actor.global_position
	var replan := _path_pts.is_empty() \
			or pass_start.distance_to(_path_goal + _path_goal_velocity * _path_age) > REPLAN_GOAL_PX \
			or pos.distance_to(_path_pts[_path_idx]) > REPLAN_OFF_PATH_PX
	if replan and _plan(target, clearance, first_clearance) and not _deadline_from_plan:
		_set_deadline_from_path()
	if _path_pts.is_empty():
		_fly_ring(delta, target)
	else:
		_track(delta)


## The phase's deadline: this path's flying time plus `reposition_max`, measured from now.
func _set_deadline_from_path() -> void:
	var remaining := maxf(_path_length - _path_idx * TRACK_SAMPLE_PX, 0.0)
	_deadline = _phase_time + remaining / config.max_speed + config.reposition_max
	_deadline_from_plan = true


## The shortest clear Dubins path to (S, run heading); for a moving player, to where S will be on
## arrival. `first_clearance` ≥ 0 relaxes the clearance of the path's first arc (TURN's break-away).
func _plan(target: TargetInfo, clearance: float, first_clearance: float) -> bool:
	var goal := pass_start
	var path := _best_path(goal, target, clearance, first_clearance)
	if path != null and target.velocity != Vector2.ZERO:
		# Arrival time and goal depend on each other: refine T = length(S + v·T) / max_speed.
		for _k in GOAL_PREDICT_ITERATIONS:
			var t := minf(path.length / config.max_speed, GOAL_PREDICT_MAX)
			var predicted := _best_path(goal + target.velocity * t, target, clearance, first_clearance)
			if predicted == null:
				break
			path = predicted
	if path == null:
		_clear_path()
		return false
	_path_pts = path.sample(TRACK_SAMPLE_PX)
	_path_idx = 0
	_path_goal = pass_start
	_path_goal_velocity = target.velocity
	_path_age = 0.0
	_path_length = path.length
	_path_first_end = path.first_arc_samples(TRACK_SAMPLE_PX)
	return true


func _best_path(goal: Vector2, target: TargetInfo, clearance: float, first_clearance: float) -> DubinsPath:
	var pos := actor.global_position
	var rect := _corridor()
	var check_rect := rect.has_area() and rect.grow(CORRIDOR_SLACK).has_point(pos)
	var room := rect.grow(CORRIDOR_SLACK)
	var break_clear := config.pass_offset * BREAK_CLEARANCE_FACTOR
	# Planning from inside `clearance` (after a break-away): the path's start is held only to the
	# break-away clearance until it first leaves the radius (review I5).
	var starts_inside := first_clearance < 0.0 and pos.distance_to(target.position) < clearance
	for path in DubinsPath.candidates(pos, _heading().angle(), goal, _run_heading.angle(), _plan_radius()):
		var pts := path.sample(PLAN_SAMPLE_PX)
		var first_n := path.first_arc_samples(PLAN_SAMPLE_PX) if first_clearance >= 0.0 else -1
		var exempt := starts_inside
		var clear := true
		for i in pts.size():
			var player_then := target.position + target.velocity * (i * PLAN_SAMPLE_PX / config.max_speed)
			var dist := pts[i].distance_to(player_then)
			if exempt and dist >= clearance:
				exempt = false
			var needed := first_clearance if i <= first_n else clearance
			if exempt:
				needed = break_clear
			if dist < needed or (check_rect and not room.has_point(pts[i])):
				clear = false
				break
		if clear:
			return path
	return null


## Pure pursuit on the sampled path: a point `TRACK_AHEAD` samples past the nearest one.
func _track(delta: float) -> void:
	_path_age += delta
	var pos := actor.global_position
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
		seek_target = _path_pts[best + TRACK_AHEAD]
	else:
		seek_target = _path_pts[last] + _run_heading * TRACK_AHEAD * TRACK_SAMPLE_PX
	var dir := Steering.turn_toward(_heading(), seek_target - pos, config.turn_rate, delta)
	mover.request_velocity(dir * config.max_speed)


## The epic's REPOSITION routing: seek a point on the standoff ring at most 90° round toward S.
func _fly_ring(delta: float, target: TargetInfo) -> void:
	var pos := actor.global_position
	var b_now := (pos - pass_anchor).normalized()
	var b_goal := (pass_start - pass_anchor).normalized()
	var ring := pass_anchor + b_now.rotated(clampf(b_now.angle_to(b_goal), -PI / 2.0, PI / 2.0)) * config.standoff_radius
	var rect := _corridor()
	if rect.has_area():
		var inner := rect.grow(-RING_CORRIDOR_MARGIN)
		ring = ring.clamp(inner.position, inner.end)
	seek_target = ring
	mover.request_velocity(Steering.turn_toward(_heading(), ring - pos, config.turn_rate, delta) * config.max_speed)


func _clear_path() -> void:
	_path_pts = PackedVector2Array()
	_path_idx = 0
	_path_goal = Vector2.INF
	_path_goal_velocity = Vector2.ZERO
	_path_age = 0.0
	_path_length = 0.0
	_path_first_end = 0


# ── Weapons (epic §2.4.2) ────────────────────────────────────────────────────────────────────────

func _tick_weapons(delta: float, target: TargetInfo) -> void:
	if _telegraph_left >= 0.0:
		_hold_nose(target)
		_telegraph_left -= delta
		if _telegraph_left > 0.0:
			return
		_telegraph_left = -1.0
		_fire_burst(target)
	if _clock.is_running():
		_hold_nose(target)
		for _i in _clock.advance(delta):
			if _burst_controller != null:
				_burst_controller.fire_now()
		if not _clock.is_running():
			_end_burst()
		return
	_try_open_burst(target)


func _try_open_burst(target: TargetInfo) -> void:
	if not target.has_target or _disengage_pending or _since_burst < config.min_burst_period:
		return
	var open := (phase == Phase.RUN_IN and _leg_a_open) or (phase == Phase.TURN and _turn_step == 0 and _leg_b_open and _nose_on(target))
	if not open:
		return
	var d := actor.global_position.distance_to(target.position)
	if d > config.fire_range:
		return
	var mode := select_weapon_mode(d)
	if mode == WeaponMode.FORWARD and not _nose_on(target):
		return  # skipped, not spent: the leg stays open
	if phase == Phase.RUN_IN:
		_leg_a_open = false
	else:
		_leg_b_open = false
	_since_burst = 0.0
	_burst_mode = mode
	if mode != weapon_mode:
		weapon_mode = mode
		weapon_mode_changed.emit(mode)
	_telegraph_left = config.burst_telegraph
	_set_light(StateLight.State.CHARGING)
	_hold_nose(target)


func _fire_burst(target: TargetInfo) -> void:
	var count: int
	var gap: float
	if _burst_mode == WeaponMode.FORWARD:
		count = rng.randi_range(config.forward_min, config.forward_max)
		gap = config.forward_gap
		_burst_controller = forward_attack
	else:
		count = rng.randi_range(config.aimed_min, config.aimed_max)
		gap = config.aimed_gap
		_burst_controller = attack
		var pattern := attack.pattern as AimedAttackPattern if attack != null else null
		if pattern != null and target.has_target:
			var hit := target.intercept(actor.global_position, config.aimed_speed)
			var lead_point: Vector2 = hit.point if hit.ok else target.position
			pattern.aim_point = target.position.lerp(lead_point, clampf(config.aimed_accuracy, 0.0, 1.0))
	_set_light(StateLight.State.ARMED)
	_clock.start(count, gap)


func _end_burst() -> void:
	_clock.stop()
	_telegraph_left = -1.0
	_burst_controller = null
	var pattern := attack.pattern as AimedAttackPattern if attack != null else null
	if pattern != null:
		pattern.aim_point = Vector2.INF
	_set_light(StateLight.State.OFF)
	if _disengage_pending:
		_disengage_pending = false
		enter_phase(Phase.DISENGAGE)


## Stops a burst without the deferred-exit handover (rails, a forced DISENGAGE).
func _abort_burst() -> void:
	if not is_bursting():
		return
	_clock.stop()
	_telegraph_left = -1.0
	_burst_controller = null
	var pattern := attack.pattern as AimedAttackPattern if attack != null else null
	if pattern != null:
		pattern.aim_point = Vector2.INF


## A FORWARD burst fires along the nose, so the nose (never the path) stays on the player.
func _hold_nose(target: TargetInfo) -> void:
	if _burst_mode == WeaponMode.FORWARD and target.has_target:
		mover.face_toward(target.position)


func _nose() -> Vector2:
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _nose_on(target: TargetInfo) -> bool:
	var to_player := target.position - actor.global_position
	return absf(_nose().angle_to(to_player)) <= deg_to_rad(config.nose_cone_deg)


## DISENGAGE now, or when the running burst ends (worst case telegraph + one burst, ≤ 0.8 s).
func _request_disengage() -> void:
	if phase == Phase.DISENGAGE:
		return
	if is_bursting():
		_disengage_pending = true
	else:
		enter_phase(Phase.DISENGAGE)


# ── DISENGAGE (the Swarm and Razor Drones' exit, curved) ─────────────────────────────────────────

func _enter_disengage() -> void:
	_abort_burst()
	_disengage_pending = false
	_set_light(StateLight.State.OFF)
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
	var rate := config.turn_rate
	if config.exit_speed > 0.0:
		rate = minf(rate, config.acceleration / config.exit_speed)
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, rate, delta)
	mover.request_velocity(dir * config.exit_speed)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return _nose()


## The corridor rect while the mover holds a constraint with one; `Rect2()` otherwise.
func _corridor() -> Rect2:
	if mover == null or mover.constraint == null:
		return Rect2()
	return mover.constraint.inner_rect()


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
