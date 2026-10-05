## The Gatling Interceptor's brain: side-on pressure windows (docs/plans/cmufs7ekv000lnm2x7nbswijy/
## 3-plan.md §2.6, §2.8; task plan docs/plans/cmulwkar600c1qj2xnqykqsvo/3-plan.md — read it for the numbers).
##
## A suppression unit, not a chaser: it holds `preferred_range` on one flank of the player, fires one
## readable stream, goes quiet, and swings round to the other flank for the next one.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   flank routing toward the first window's flank point F; hands over once F is
##                           within `swing_in_reach` (or `reposition_cap` after closing to
##                           `preferred_range + approach_margin`).
##   SWING_IN   [POSITION]   CHARGING. Routes to F, tapering speed; within 60 px or `swing_in_max` → SPIN_UP.
##                           Entered only with `swing_in_max` of budget left, so a yellow light is always
##                           followed by a stream.
##   SPIN_UP    [ATTACK]     CHARGING, `spin_up_seconds`, braking into the strafe; nose on the player.
##   STREAM     [ATTACK]     ARMED. One `BurstClock` of `rng` 8–12 rounds at `stream_interval`, aimed at the
##                           player's predicted position; strafes through the flank ("ahead → behind").
##   COOLDOWN   [ATTACK]     OFF, `cooldown_seconds`, keeps drifting.
##   REPOSITION [REPOSITION] flips the side (the Assault wall exception aside), brakes and swings round
##                           AHEAD of the player (Assault) or the short way (Open Space) to the new F; at
##                           least rng(`reposition_min`, `reposition_max`) and until F is within
##                           `swing_in_reach`, capped by `reposition_cap` (task plan §D2).
##   DISENGAGE  [DISENGAGE]  Assault only: budget expiry (deferred to the end of a running window);
##                           release the corridor, curve out of the world rect, free.
##
## Side rule (epic §2.6): the first window takes the side the Gatling is on (Open Space) or the corridor
## half opposite the player's x (Assault). APPROACH re-derives it every tick and latches it on exit
## (review A3). Every later window flips, except in Assault when the flipped F would sit within
## `min_flank_range` (horizontally) of a player hugging a wall.
##
## Convergence (plan §2.6.1): a squad of two or more shares `squad.convergence_point`. The LEAD opens the
## window at its SWING_IN entry (`attack_window_open`, `convergence_stage`) and rewrites the point every
## tick until the window closes. A FLANK within `convergence_join_range_factor × preferred_range`
## answers once, from APPROACH, COOLDOWN or REPOSITION: it takes the LEAD's side and a flank point
## `convergence_bearing_offset_deg` toward the heading, then both hold in SPIN_UP until each is ready
## (stage 1 = own spin-up done) or `sync_wait_max` has passed. Stage 2 = stream done; the LEAD closes
## the window when every key is 2. A cleared board (LEAD change or death) drops a member back to its
## own predicted point without cutting its stream.
##
## Rails (§2.8, X1): `on_suspended()` hands `attack` back to the legacy self-timed constant stream, from
## the `rail_*` config fields, on the same 36-round `StreamPool` (the legacy starvation shape, deliberate).
##
## Requests only (single-writer gate): the field writes on the mover are `max_speed` and
## `release_constraint()` on DISENGAGE.
class_name GatlingInterceptorBrain
extends EnemyBrain

## t12 appends IDLE, NOTICING and RETURNING.
enum Phase { APPROACH, SWING_IN, SPIN_UP, STREAM, COOLDOWN, REPOSITION, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## The player-lead window P̂ uses (s).
const LEAD_MIN := 0.3
const LEAD_MAX := 0.8
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## Open Space `h` follows the player's velocity above this speed, else its facing (px/s).
const HEADING_REF_MIN_SPEED := 40.0
## Assault: F sits this far ahead of the player (px), epic §2.6.
const ASSAULT_FLANK_AHEAD := 60.0
## Assault: F and the routing waypoints stay this far (plus the hull) inside `inner_rect()` (px).
const CORRIDOR_MARGIN := 40.0
## SWING_IN hands over to SPIN_UP within this of F (px), epic §2.6.
const SWING_IN_ARRIVE_PX := 60.0
## The flank routing seeks ring waypoints at most this far round from the current bearing (deg).
const ROUTE_STEP_DEG := 50.0
## The strafe's range-holding correction, per second of range error.
const RANGE_GAIN := 2.0
## SPIN_UP latches the strafe from the current velocity above this speed (px/s, review A1).
const STRAFE_LATCH_MIN_SPEED := 40.0
## Assault: the swing's route is sampled this often (deg) to see whether it clears the player (A2).
const ROUTE_SAMPLE_DEG := 25.0
## Hull radius used when the scene has no readable body circle (px).
const DEFAULT_HULL_RADIUS := 25.0
## The shared aim point is the player predicted this far ahead (s), clamped like P̂'s lead.
const CONVERGENCE_LEAD_MIN := 0.4
const CONVERGENCE_LEAD_MAX := 0.8
## A FLANK's convergence flank point is at least this far round the player from the LEAD's (deg).
const CONVERGENCE_MIN_SEPARATION_DEG := 30.0
## `convergence_stage` values: answered / ready to stream (own spin-up done) / stream done.
const STAGE_ANSWERED := 0
const STAGE_READY := 1
const STAGE_DONE := 2

## Set by `gatling_interceptor.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: GatlingInterceptorConfig = GatlingInterceptorConfig.new()
## Test seam (review A2 boundary): false disables the Assault swing's round-behind fallback.
var route_fallback: bool = true

var phase: Phase = Phase.APPROACH
## Built on the first tick. Null before it.
var budget: EngagementBudget
## The flank the current (or next) window is on: +1 = `right(h)`, −1 = the other. Read-only outside.
var side: float = 1.0
## This tick's flank point F. Read-only outside this script.
var flank_point: Vector2 = Vector2.ZERO
## The point the Gatling is steering at this tick.
var seek_target: Vector2 = Vector2.ZERO
## Rounds in the current (or last) stream.
var stream_rounds: int = 0
## Streams completed.
var windows_done: int = 0

var _started: bool = false
var _phase_time: float = 0.0
var _hull_radius: float = DEFAULT_HULL_RADIUS
var _side_latched: bool = false
## Seconds since APPROACH first came within `preferred_range + approach_margin`; −1 = not yet.
var _close_time: float = -1.0
var _reposition_min_time: float = 0.0
var _strafe_sign: float = 1.0
var _clock := BurstClock.new()
var _disengage_pending: bool = false
var _exit_point: Vector2 = Vector2.ZERO
## This FLANK has already decided about the squad's open window (joined or skipped it).
var _answered_window: bool = false
## This member joined a window as a FLANK, so its flank point is the offset one.
var _conv_flank: bool = false
## The window's aim error (rad), drawn once on STREAM entry.
var _aim_error: float = 0.0


func _ready() -> void:
	super._ready()
	var parent := get_parent()
	if parent == null:
		return
	var body := parent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is CircleShape2D:
		_hull_radius = (body.shape as CircleShape2D).radius * absf(body.scale.x)


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	var target := TargetInfo.player(get_tree())
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	var squad := _squad()
	if squad != null:
		if target.has_target:
			squad.update_target(target.position, _heading_ref(target))
		_tick_convergence(target, squad)
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.SWING_IN: _tick_swing_in(delta, target)
		Phase.SPIN_UP: _tick_spin_up(target)
		Phase.STREAM: _tick_stream(delta, target)
		Phase.COOLDOWN: _tick_cooldown(target)
		Phase.REPOSITION: _tick_reposition(delta, target)
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	var from := phase
	phase = p
	_phase_time = 0.0
	match p:
		Phase.SWING_IN:
			_set_light(StateLight.State.CHARGING)
			_open_window()
		Phase.SPIN_UP:
			_set_light(StateLight.State.CHARGING)
			_enter_spin_up()
		Phase.STREAM:
			stream_rounds = rng.randi_range(config.stream_rounds_min, config.stream_rounds_max)
			_clock.start(stream_rounds, config.stream_interval)
			_set_light(StateLight.State.ARMED)
			if _converging(_squad()):
				var err := deg_to_rad(config.convergence_aim_error_deg)
				_aim_error = rng.randf_range(-err, err)
		Phase.COOLDOWN:
			_set_light(StateLight.State.OFF)
			_set_aim_point(Vector2.INF)
		Phase.REPOSITION:
			_set_light(StateLight.State.OFF)
			_reposition_min_time = rng.randf_range(config.reposition_min, config.reposition_max)
			if from == Phase.COOLDOWN:
				_flip_side(TargetInfo.player(get_tree()))
		Phase.DISENGAGE:
			_enter_disengage()
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The legacy constant stream, self-timed, from
## the `rail_*` config fields, so the round-lifetime sweep reads the same numbers the rail fires with.
## It shares the 36-round `StreamPool`: the rail need is 71, so a rail Gatling fires about 36 rounds and
## stalls until they expire — the legacy pool-starvation shape (it was 20), kept deliberately (epic §2.2).
func on_suspended() -> void:
	_clock.stop()
	_disengage_pending = false
	_set_light(StateLight.State.OFF)
	_leave_squad()
	_set_aim_point(Vector2.INF)
	if attack == null:
		return
	var pattern := GatlingAttackPattern.new()
	pattern.fire_interval = config.rail_stream_interval
	pattern.bullet_damage = config.rail_damage
	pattern.bullet_speed = config.rail_stream_speed
	pattern.spread_angle = config.rail_spread
	pattern.aim_at_player = true
	pattern.accuracy = 0.0
	attack.pattern = pattern
	attack.driven_by_brain = false
	attack.enabled = true


## True when a new window may start: SWING_IN's CHARGING light must always be followed by a stream, so
## it needs at least `swing_in_max` of budget left (always true outside Assault).
func can_start_window() -> bool:
	return (budget == null or budget.remaining() >= config.swing_in_max) and not _own_window_open()


## The shortest time between two stream starts (s): sizes `StreamPool` with
## `EnemyRounds.pool_size_for()`. REPOSITION never ends before `reposition_min`.
func min_window_period() -> float:
	return config.spin_up_seconds + (config.stream_rounds_min - 1) * config.stream_interval \
			+ config.cooldown_seconds + config.reposition_min


## True while a window's telegraph or stream is running (SWING_IN, SPIN_UP, STREAM).
func is_in_window() -> bool:
	return phase == Phase.SWING_IN or phase == Phase.SPIN_UP or phase == Phase.STREAM


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	side = _first_side(target)
	flank_point = _flank_for(side, target)
	_route(delta, target, false)
	var pos := actor.global_position
	if _close_time >= 0.0:
		_close_time += delta
	elif pos.distance_to(target.position) <= config.preferred_range + config.approach_margin:
		_close_time = 0.0
	if pos.distance_to(flank_point) <= config.swing_in_reach or _close_time >= config.reposition_cap:
		_side_latched = true
		if can_start_window():
			enter_phase(Phase.SWING_IN)
		else:
			enter_phase(Phase.REPOSITION)


# ── The window ───────────────────────────────────────────────────────────────────────────────────

func _tick_swing_in(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	flank_point = _convergence_flank(target) if _conv_flank and _converging(_squad()) else _flank_for(side, target)
	_route(delta, target, true)
	if actor.global_position.distance_to(flank_point) <= SWING_IN_ARRIVE_PX or _phase_time >= config.swing_in_max:
		enter_phase(Phase.SPIN_UP)


## Latches the strafe's direction (review A1): the tangent that continues the current velocity, so the
## Gatling keeps sliding the way it arrived instead of stopping and backing up; at (near) rest, the one
## that slides from ahead toward behind.
func _enter_spin_up() -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	var to_p := _anchor(target) - actor.global_position
	var tangent := to_p.normalized().rotated(PI / 2.0)
	if actor.velocity.length() > STRAFE_LATCH_MIN_SPEED:
		_strafe_sign = -1.0 if tangent.dot(actor.velocity) < 0.0 else 1.0
	else:
		_strafe_sign = -1.0 if tangent.dot(_heading_ref(target)) > 0.0 else 1.0


func _tick_spin_up(target: TargetInfo) -> void:
	_strafe(target, true)
	if _phase_time < config.spin_up_seconds:
		return
	# A convergence pair holds here until every participant's own spin-up is over, but never longer than
	# `sync_wait_max` (plan §2.6.1, review B2): a partner that died or got stuck cannot stall this one.
	var squad := _squad()
	if _converging(squad):
		if squad.convergence_stage[actor] < STAGE_READY:
			squad.convergence_stage[actor] = STAGE_READY
		if not _partners_ready(squad) and _phase_time < config.spin_up_seconds + config.sync_wait_max:
			return
	enter_phase(Phase.STREAM)


func _tick_stream(delta: float, target: TargetInfo) -> void:
	_strafe(target, true)
	_aim_stream(_squad())
	for _i in _clock.advance(delta):
		if attack != null:
			attack.fire_now()
	if not _clock.is_running():
		windows_done += 1
		_finish_convergence()
		if _disengage_pending:
			_disengage_pending = false
			enter_phase(Phase.DISENGAGE)
		else:
			enter_phase(Phase.COOLDOWN)


func _tick_cooldown(target: TargetInfo) -> void:
	_strafe(target, false)
	if _phase_time >= config.cooldown_seconds:
		enter_phase(Phase.REPOSITION)


func _tick_reposition(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	flank_point = _flank_for(side, target)
	# Once F is in reach (an unflipped window, review A6) slow into it rather than circling it.
	_route(delta, target, actor.global_position.distance_to(flank_point) <= config.swing_in_reach)
	if _phase_time < _reposition_min_time:
		return
	var in_reach := actor.global_position.distance_to(flank_point) <= config.swing_in_reach
	if (in_reach or _phase_time >= config.reposition_cap) and can_start_window():
		enter_phase(Phase.SWING_IN)


## DISENGAGE now, or — mid-window — when the stream ends (worst case: SWING_IN's last tick, then
## spin-up and the longest stream; t11 adds `sync_wait_max`, 2.08 s in all).
func _request_disengage() -> void:
	if phase == Phase.DISENGAGE:
		return
	if is_in_window():
		_disengage_pending = true
	else:
		enter_phase(Phase.DISENGAGE)


# ── Convergence (plan §2.6.1) ────────────────────────────────────────────────────────────────────

## `_heading_ref()` for the actor's `squad.update_target()` (the Fighter's `heading_ref()` shape).
func heading_ref(target: TargetInfo) -> Vector2:
	return _heading_ref(target)


## The squad board `WaveManager` / `SectorHub` wrote on the actor (duck-typed), or null.
func _squad() -> SquadController:
	if actor == null:
		return null
	return actor.get(&"squad") as SquadController


## True for a member of a squad of two or more that still holds a role.
func _in_pair(squad: SquadController) -> bool:
	return squad != null and squad.member_count() >= 2 and squad.role_of(actor) != SquadController.Role.NONE


## True while this member is a participant of the squad's open window (its key is on the board).
func _converging(squad: SquadController) -> bool:
	return squad != null and squad.attack_window_open and squad.convergence_stage.has(actor)


## True while this member leads a squad whose window is still open: it opens no second one.
func _own_window_open() -> bool:
	var squad := _squad()
	return squad != null and squad.attack_window_open and squad.role_of(actor) == SquadController.Role.LEAD


## LEAD, SWING_IN entry: opens the window and writes the first point. No-op for anyone else, for a
## solo Gatling and while the last window is still open.
func _open_window() -> void:
	var squad := _squad()
	if not _in_pair(squad) or squad.attack_window_open or squad.role_of(actor) != SquadController.Role.LEAD:
		return
	squad.attack_window_open = true
	squad.convergence_stage[actor] = STAGE_ANSWERED
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		squad.convergence_point = _convergence_point(target)


## Every tick: the LEAD refreshes the point and closes the window; a FLANK decides once about it.
func _tick_convergence(target: TargetInfo, squad: SquadController) -> void:
	if not squad.attack_window_open:
		_answered_window = false
		_conv_flank = false
		return
	if not squad.convergence_stage.has(actor):
		_conv_flank = false
		if not _answered_window:
			_answer_window(target, squad)
		return
	if squad.role_of(actor) == SquadController.Role.LEAD:
		if target.has_target:
			squad.convergence_point = _convergence_point(target)
		_try_close_window(squad)


## A FLANK's one answer to the open window: join it from APPROACH, COOLDOWN or REPOSITION (never
## abort a live window or stream) when within `convergence_join_range_factor × preferred_range` of the
## player, else skip it — either way this window is decided.
func _answer_window(target: TargetInfo, squad: SquadController) -> void:
	_answered_window = true
	var role := squad.role_of(actor)
	if role != SquadController.Role.FLANK_LEFT and role != SquadController.Role.FLANK_RIGHT:
		return
	if phase != Phase.APPROACH and phase != Phase.COOLDOWN and phase != Phase.REPOSITION:
		return
	if not target.has_target or not can_start_window():
		return
	if actor.global_position.distance_to(target.position) > config.convergence_join_range_factor * config.preferred_range:
		return
	var lead := _lead_brain(squad)
	if lead == null:
		return
	# The LEAD's intended side (its `side`, flipped at its REPOSITION), not where its hull is now.
	side = lead.side
	_side_latched = true
	squad.convergence_stage[actor] = STAGE_ANSWERED
	_conv_flank = true
	enter_phase(Phase.SWING_IN)


func _lead_brain(squad: SquadController) -> GatlingInterceptorBrain:
	for m in squad.members():
		if squad.role_of(m) == SquadController.Role.LEAD:
			return m.get_node_or_null("Brain") as GatlingInterceptorBrain
	return null


## The shared aim point: the player predicted `d / round_speed` seconds ahead, `d` this shooter's range.
func _convergence_point(target: TargetInfo) -> Vector2:
	var d := actor.global_position.distance_to(target.position)
	return target.predicted_position(Steering.clamped_lead_time(d, config.round_speed, CONVERGENCE_LEAD_MIN, CONVERGENCE_LEAD_MAX))


## A FLANK's flank point: the LEAD's (same `side`) rotated `convergence_bearing_offset_deg` toward the
## heading round the player. When the corridor clamp leaves that closer than
## `CONVERGENCE_MIN_SEPARATION_DEG` to the LEAD's, the other way round is taken instead.
func _convergence_flank(target: TargetInfo) -> Vector2:
	var anchor := _anchor(target)
	var base := _flank_for(side, target)
	var v := base - anchor
	var offset := deg_to_rad(config.convergence_bearing_offset_deg) * -side
	var best := _clamp_if_corridor(anchor + v.rotated(offset))
	var best_gap := absf(v.angle_to(best - anchor))
	if rad_to_deg(best_gap) < CONVERGENCE_MIN_SEPARATION_DEG:
		var other := _clamp_if_corridor(anchor + v.rotated(-offset))
		if absf(v.angle_to(other - anchor)) > best_gap:
			best = other
	return best


func _clamp_if_corridor(p: Vector2) -> Vector2:
	return _clamp_corridor(p) if _corridor().has_area() else p


## True when every participant has finished its own spin-up (or streamed already).
func _partners_ready(squad: SquadController) -> bool:
	for stage in squad.convergence_stage.values():
		if stage < STAGE_READY:
			return false
	return true


## The LEAD closes the window on the first tick every key is STREAM-done: the later COOLDOWN entry.
func _try_close_window(squad: SquadController) -> void:
	for stage in squad.convergence_stage.values():
		if stage != STAGE_DONE:
			return
	squad.attack_window_open = false
	squad.convergence_point = Vector2.INF
	squad.convergence_stage.clear()


## STREAM end: this participant is done, and the aim returns to its own prediction.
func _finish_convergence() -> void:
	var squad := _squad()
	if _converging(squad):
		squad.convergence_stage[actor] = STAGE_DONE
		if squad.role_of(actor) == SquadController.Role.LEAD:
			_try_close_window(squad)
	_set_aim_point(Vector2.INF)


## Each STREAM tick: aim at the shared point with this window's error, or — no point (a solo Gatling,
## or the board was cleared mid-stream) — at its own predicted point.
func _aim_stream(squad: SquadController) -> void:
	if _converging(squad) and squad.convergence_point.is_finite():
		var from := actor.global_position
		_set_aim_point(from + (squad.convergence_point - from).rotated(_aim_error))
	else:
		_set_aim_point(Vector2.INF)


func _set_aim_point(p: Vector2) -> void:
	var pattern := attack.pattern as GatlingAttackPattern if attack != null else null
	if pattern != null:
		pattern.aim_point = p


func _leave_squad() -> void:
	var squad := _squad()
	if squad != null:
		squad.leave(actor)
	_conv_flank = false


# ── Sides and geometry (task plan §D4, §D5) ──────────────────────────────────────────────────────

## The first window's side: the side it is on (Open Space), or the corridor half opposite the player's
## x (Assault; exact centre → +1, review N7). Once latched, the current side.
func _first_side(target: TargetInfo) -> float:
	if _side_latched:
		return side
	var rect := _corridor()
	if rect.has_area():
		return -1.0 if target.position.x > rect.get_center().x else 1.0
	var right := _heading_ref(target).rotated(PI / 2.0)
	return -1.0 if right.dot(actor.global_position - _anchor(target)) < 0.0 else 1.0


## REPOSITION after a stream: the other flank, unless (Assault) that flank point would sit closer than
## `min_flank_range` horizontally to the player — a player hugging a wall keeps the open side.
func _flip_side(target: TargetInfo) -> void:
	_side_latched = true
	if not target.has_target:
		side = -side
		return
	var flipped := -side
	if _corridor().has_area():
		var f := _flank_for(flipped, target)
		if absf(f.x - target.position.x) < config.min_flank_range:
			return
	side = flipped


## P̂: the player's position `lead` seconds ahead.
func _anchor(target: TargetInfo) -> Vector2:
	var lead := Steering.clamped_lead_time(actor.global_position.distance_to(target.position), config.max_speed, LEAD_MIN, LEAD_MAX)
	return target.predicted_position(lead)


## F = P̂ + right(h) × side × preferred_range; in Assault 60 px ahead and clamped into the corridor.
func _flank_for(s: float, target: TargetInfo) -> Vector2:
	var anchor := _anchor(target)
	var f := anchor + _heading_ref(target).rotated(PI / 2.0) * s * config.preferred_range
	if _corridor().has_area():
		f.y = anchor.y - ASSAULT_FLANK_AHEAD
		f = _clamp_corridor(f)
	return f


## Flank routing: seek F, or — more than `ROUTE_STEP_DEG` of bearing away — a waypoint that far round
## on the `preferred_range` ring, so a swing never cuts across the player. Assault goes round ahead
## (the plain bearing difference never wraps through ±180°, i.e. below the player) unless the corridor
## clamp would pull that route within `min_flank_range` of the player — a player near the corridor top —
## and then round behind (review A2); Open Space takes the short way. `taper` slows into F. The
## player's velocity is fed forward.
func _route(delta: float, target: TargetInfo, taper: bool) -> void:
	var anchor := _anchor(target)
	var h := _heading_ref(target)
	var pos := actor.global_position
	var phi := h.angle_to(pos - anchor)
	var diff := h.angle_to(flank_point - anchor) - phi
	var corridor := _corridor().has_area()
	if not corridor:
		diff = wrapf(diff, -PI, PI)
	elif route_fallback and not _arc_clears(anchor, h, phi, diff):
		var other := diff - signf(diff) * TAU
		if _arc_clears(anchor, h, phi, other):
			diff = other
	var point := flank_point
	var step := deg_to_rad(ROUTE_STEP_DEG)
	if absf(diff) > step:
		point = _ring_point(anchor, h, phi + clampf(diff, -step, step))
	seek_target = point
	var to := point - pos
	var speed := config.max_speed
	if taper:
		speed = minf(speed, sqrt(2.0 * config.braking * to.length()))
	var desired := to.normalized() * speed + target.velocity
	var dir := Steering.turn_toward(_heading(), desired, config.turn_rate, delta)
	mover.request_velocity(dir * desired.length())


## A route waypoint at bearing `angle` on the `preferred_range` ring, clamped into the corridor.
func _ring_point(anchor: Vector2, h: Vector2, angle: float) -> Vector2:
	var p := anchor + h.rotated(angle) * config.preferred_range
	return _clamp_corridor(p) if _corridor().has_area() else p


## True when every (clamped) waypoint of the swing from bearing `phi` round by `diff` stays at least
## `min_flank_range` from the player.
func _arc_clears(anchor: Vector2, h: Vector2, phi: float, diff: float) -> bool:
	var samples := int(ceil(absf(diff) / deg_to_rad(ROUTE_SAMPLE_DEG)))
	for k in range(1, samples + 1):
		var p := _ring_point(anchor, h, phi + diff * float(k) / float(samples))
		if p.distance_to(anchor) < config.min_flank_range:
			return false
	return true


## Slides along the flank at `stream_strafe_speed` (the latched sign), holding `preferred_range` and
## moving with the player; `face` keeps the nose on the player (SPIN_UP, STREAM).
func _strafe(target: TargetInfo, face: bool) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var to_p := _anchor(target) - actor.global_position
	var d := to_p.length()
	var u := to_p / d if d > 0.0 else _heading()
	var tangent := u.rotated(PI / 2.0) * _strafe_sign
	var radial := (u * (d - config.preferred_range) * RANGE_GAIN).limit_length(config.stream_strafe_speed)
	seek_target = actor.global_position + tangent * config.stream_strafe_speed
	mover.request_velocity(target.velocity + tangent * config.stream_strafe_speed + radial)
	if face:
		mover.face_toward(target.position)


func _clamp_corridor(p: Vector2) -> Vector2:
	var inner := _corridor().grow(-(_hull_radius + CORRIDOR_MARGIN))
	return p.clamp(inner.position, inner.end)


## `h`: UP in the corridor, else the player's velocity or facing (`FighterBrain._heading_ref()`).
func _heading_ref(target: TargetInfo) -> Vector2:
	if _corridor().has_area():
		return Vector2.UP
	if target.velocity.length() > HEADING_REF_MIN_SPEED:
		return target.velocity.normalized()
	return target.facing if target.facing != Vector2.ZERO else Vector2.UP


# ── DISENGAGE (the Fighter's exit) ───────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	_clock.stop()
	_leave_squad()
	_set_aim_point(Vector2.INF)
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
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


## The corridor rect while the mover holds a constraint with one; `Rect2()` otherwise.
func _corridor() -> Rect2:
	if mover == null or mover.constraint == null:
		return Rect2()
	return mover.constraint.inner_rect()


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
