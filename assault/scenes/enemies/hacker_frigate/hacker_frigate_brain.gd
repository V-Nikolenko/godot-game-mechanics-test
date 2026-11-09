## The Hacker Frigate's brain (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.10; Phase 9 t8, task plan
## docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md). HOLD_ARC, DISENGAGE and the hub idle are composed from `MissileCorvetteBrain`'s (copied,
## not inherited).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   HOLD_ARC   [POSITION]   a lopsided orbit of the player at `held_range()` ± a slow drift of `range_drift`: `orbit_dir` +1 (clockwise
##                           on screen) at `orbit_speed_cw`, -1 at `orbit_speed_ccw`, reversing every `reversal_min`..`reversal_max` s.
##                           Bearing penalty (§18.6): while its bearing from the player lies inside the player's nose cone (± `nose_cone_deg`
##                           round its facing) or route cone (± `route_cone_deg` round its velocity, above `route_min_speed`), the arc is
##                           forced toward the cone's nearer edge at `cone_escape_speed` and no reversal is drawn. It closes from far away
##                           through the orbit's own correction (no APPROACH). Inside `min_range` (rearmed) it breaks off. Nose on the player.
##   TELEGRAPH  [ATTACK]     t9. A stub until then: back to HOLD_ARC on its first tick.
##   PULSE      [ATTACK]     t9. A stub until then: back to HOLD_ARC on its first tick.
##   BREAK_OFF  [EVADE]      Open Space: committed `mover.boost` bursts at `break_speed` along `Steering.break_contact` (`break_lateral_weight`),
##                           re-issued at each burst's end. Assault: no boost; a `max_speed` request toward a point ahead along the same line,
##                           clamped into view. Ends beyond `min_range + break_exit_margin` or after `break_max_seconds`; the next waits
##                           `break_rearm_seconds`.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor, curve toward the nearest edge of the projectile rect at
##                           `exit_speed`, freed once outside it (the corvette's exit). A TELEGRAPH / PULSE finishes first.
##   IDLE       [SEARCH]     Open Space hub only: a slow ring of `idle_radius` round `patrol_anchor`, lopsided like its arc.
##   NOTICING   [SEARCH]     a beat (`notice_time`): it stops and the nose turns to the player, then HOLD_ARC.
##   RETURNING  [REPOSITION] `arrive` back at `patrol_anchor`, then IDLE. Never interrupts a TELEGRAPH or a PULSE.
##
## Assault: every target point goes through `_clamp_into_view()` (the Support Ship's view clamp), so the Hacker stays on screen for its
## `EngagementBudget`.
##
## Requests only (single-writer gate): the writes on the mover are `orbit`, `arrive`, `request_velocity`, `boost`, `face_toward`,
## `max_speed` and `release_constraint()` on DISENGAGE.
class_name HackerFrigateBrain
extends EnemyBrain

enum Phase { HOLD_ARC, TELEGRAPH, PULSE, BREAK_OFF, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The drift of the held range has a period drawn in this range (s).
const DRIFT_PERIOD_MIN := 6.0
const DRIFT_PERIOD_MAX := 9.0
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35
## Assault break-off: the request aims at a point this many seconds of `max_speed` ahead along the break line, clamped into view.
const BREAK_LOOKAHEAD := 1.0
## The view clamp keeps every target point this much further in than `view_margin` (px): `Steering.orbit`'s 60 px/s correction floor makes
## a body parked on its point wobble ±2.6 px (60² / (2·700)), and the hull itself has to stay inside `grow(-view_margin)`.
const VIEW_CLAMP_PAD := 8.0
## The clock rule (Phase 9): a countdown is over at `<= this`.
const CLOCK_EPSILON := 1e-6

## Set by `hacker_frigate.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: HackerFrigateConfig = HackerFrigateConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.HOLD_ARC
## Test seam: a spawned Hacker starts already fighting, skipping the hub idle. Assault ignores it: `EngagementBudget.active` decides there.
var start_engaged: bool = false
## The hub idle's ring centre. `Vector2.INF` (unset) means "not set": `_start()` then defaults it to the spawn position.
var patrol_anchor: Vector2 = Vector2.INF
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once, in `_start()`.
var anchor_idle: AnchorIdle
## This Hacker's offset on the idle ring (rad), drawn from `rng` when the idle starts.
var idle_phase_offset: float = 0.0

## ±1: the way round the player the arc goes (+1 clockwise on screen, at `orbit_speed_cw`). Drawn on the first tick, flipped on every
## reversal, forced toward the nearer edge inside a cone.
var orbit_dir: float = 1.0
## True on a tick the bearing was inside a cone; `cone_kind` says which (`&"nose"`, `&"route"`, or `&""`). Read-only, for tests and docs.
var in_cone: bool = false
var cone_kind: StringName = &""
## True when the last `_clamp_into_view()` moved its point (the Assault view clamp bound). Read-only.
var view_clamp_bound: bool = false
## BREAK_OFF entries so far.
var break_offs: int = 0

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _expiry_seen: bool = false
var _disengage_pending: bool = false
var _orbit_angle: float = 0.0
var _orbit_synced: bool = false
var _arc_clock: float = 0.0
var _drift_period: float = DRIFT_PERIOD_MIN
var _drift_phase: float = 0.0
var _reversal_left: float = 0.0
var _rearm_left: float = 0.0
var _break_side: float = 1.0


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if _rearm_left > 0.0:
		_rearm_left -= delta
		if _rearm_left <= CLOCK_EPSILON:
			_rearm_left = 0.0
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		_on_budget_expired()
	if anchor_idle != null:
		_tick_anchor_idle(delta)
	match phase:
		Phase.IDLE: _tick_idle()
		Phase.NOTICING: _tick_noticing()
		Phase.RETURNING: _tick_returning()
		Phase.HOLD_ARC: _tick_hold_arc(delta)
		Phase.TELEGRAPH, Phase.PULSE: _tick_attack_stub(delta)
		Phase.BREAK_OFF: _tick_break_off(delta)
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.HOLD_ARC:
			_orbit_synced = false
			_set_light(StateLight.State.OFF)
		Phase.BREAK_OFF:
			break_offs += 1
			_break_side = 1.0 if rng.randf() < 0.5 else -1.0
			_set_light(StateLight.State.OFF)
		Phase.DISENGAGE:
			_enter_disengage()
		Phase.IDLE, Phase.NOTICING, Phase.RETURNING:
			_orbit_synced = false
			_set_light(StateLight.State.OFF)
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## Test seam: sets the arc's direction once (+1 the cw arc at `orbit_speed_cw`, -1 the ccw arc at `orbit_speed_ccw`). A cone still overrides it
## while the bearing is inside one (unless that cone is 0°).
func force_orbit_direction(dir: int) -> void:
	if not _started:
		_start()
	orbit_dir = 1.0 if dir >= 0 else -1.0


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. No weapon yet, so nothing to fall back to.
func on_suspended() -> void:
	anchor_idle = null  # a rail owns the motion: no idle
	_set_light(StateLight.State.OFF)


## The range the Hacker holds: the corridor is narrower than the open sky.
func held_range() -> float:
	return config.assault_preferred_range if budget != null and budget.active else config.preferred_range


## The arc's angular speed in direction `dir` outside a cone (rad/s).
func orbit_speed(dir: float) -> float:
	return config.orbit_speed_cw if dir > 0.0 else config.orbit_speed_ccw


## The arc's target angle (rad): the bearing of the orbit's anchor from the player. Read-only.
func orbit_angle() -> float:
	return _orbit_angle


## The telegraphed phases are never moved by an ally (`BaseEnemy.accept_tow`): the dish is charging or pulsing at what the player was shown.
func accepts_tow() -> bool:
	match phase:
		Phase.TELEGRAPH, Phase.PULSE:
			return false
	return true


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	_drift_period = rng.randf_range(DRIFT_PERIOD_MIN, DRIFT_PERIOD_MAX)
	_drift_phase = 0.0 if rng.randf() < 0.5 else PI
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.idle_radius)
		idle_phase_offset = rng.randf_range(-MAX_IDLE_PHASE_OFFSET, MAX_IDLE_PHASE_OFFSET)
		enter_phase(Phase.IDLE)


## The budget ran out: leave now, unless a pulse is being charged or fired, which finishes first.
func _on_budget_expired() -> void:
	if _is_committed():
		_disengage_pending = true
		return
	if phase != Phase.DISENGAGE:
		enter_phase(Phase.DISENGAGE)


func _is_committed() -> bool:
	return phase == Phase.TELEGRAPH or phase == Phase.PULSE


# ── Hub idle ─────────────────────────────────────────────────────────────────────────────────────

## The meta-state that decides whether the Hacker is patrolling, noticing or fighting, run once a tick ahead of the phase dispatch. A
## TELEGRAPH or a PULSE is never interrupted: the return is retried every tick until it has ended.
func _tick_anchor_idle(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	match anchor_idle.update(delta, actor.global_position, target):
		AnchorIdle.State.IDLE:
			if phase != Phase.IDLE and not _is_committed():
				enter_phase(Phase.IDLE)
		AnchorIdle.State.NOTICING:
			if phase != Phase.NOTICING and not _is_committed():
				enter_phase(Phase.NOTICING)
		AnchorIdle.State.COMBAT:
			# From NOTICING only: any other phase is already fighting.
			if phase == Phase.NOTICING:
				enter_phase(Phase.HOLD_ARC)
		AnchorIdle.State.RETURNING:
			if phase != Phase.RETURNING and not _is_committed():
				enter_phase(Phase.RETURNING)


## The ring runs the way `orbit_dir` points, at `idle_speed` the ccw way and in the same cw / ccw proportion as the combat arc the other way.
func _tick_idle() -> void:
	var k := orbit_speed(orbit_dir) / config.orbit_speed_ccw if config.orbit_speed_ccw > 0.0 else 1.0
	var angle := idle_phase_offset + orbit_dir * config.idle_speed * k * _phase_time
	mover.orbit(patrol_anchor, config.idle_radius, angle, config.max_speed)


func _tick_noticing() -> void:
	mover.request_velocity(Vector2.ZERO)
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		mover.face_toward(target.position)


func _tick_returning() -> void:
	mover.arrive(patrol_anchor, config.max_speed)


# ── HOLD_ARC ─────────────────────────────────────────────────────────────────────────────────────

func _tick_hold_arc(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	if actor.global_position.distance_to(target.position) < config.min_range and _rearm_left <= 0.0:
		enter_phase(Phase.BREAK_OFF)
		_tick_break_off(delta)  # the first burst leaves on the entry tick
		return
	_arc_motion(delta, target)
	if _want_pulse():
		enter_phase(Phase.TELEGRAPH)


## t9 fills this (the pulse gate). Never true in t8.
func _want_pulse() -> bool:
	return false


func _arc_motion(delta: float, target: TargetInfo) -> void:
	var pos := actor.global_position
	var offset := pos - target.position
	if not _orbit_synced:
		_orbit_synced = true
		_orbit_angle = offset.angle() if offset.length_squared() > 1e-6 else -PI / 2.0
	_arc_clock += delta
	var edge := _cone_edge_dir(target, offset)
	var speed: float
	if edge != 0.0:
		orbit_dir = edge
		speed = config.cone_escape_speed
	else:
		speed = orbit_speed(orbit_dir)
		_reversal_left -= delta
		if _reversal_left <= 0.0:
			orbit_dir = -orbit_dir
			_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	_orbit_angle += orbit_dir * speed * delta
	var radius := held_range() + config.range_drift * sin(TAU * _arc_clock / _drift_period + _drift_phase)
	var anchor := _clamp_into_view(target.position + Vector2.RIGHT.rotated(_orbit_angle) * radius)
	# Radius 0 makes the anchor the centre: exactly `Steering.orbit`'s correction toward the (clamped) point. Unclamped, it is the
	# corvette's `Steering.orbit(pos, player, radius, angle, max_speed)`.
	mover.request_velocity(Steering.orbit(pos, anchor, 0.0, 0.0, config.max_speed))
	mover.face_toward(target.position)


## The bearing penalty: inside the nose cone (checked first) or the route cone, the direction toward that cone's nearer edge in
## `_orbit_angle`'s sense (on the centre line, the current `orbit_dir`); 0 outside both. The sizes are read from `config` on every call.
func _cone_edge_dir(target: TargetInfo, offset: Vector2) -> float:
	in_cone = false
	cone_kind = &""
	if offset.length_squared() < 1e-6:
		return 0.0
	if config.nose_cone_deg > 0.0 and target.facing.length_squared() > 1e-6:
		var a := target.facing.angle_to(offset)
		if absf(a) < deg_to_rad(config.nose_cone_deg):
			in_cone = true
			cone_kind = &"nose"
			return orbit_dir if a == 0.0 else signf(a)
	if config.route_cone_deg > 0.0 and target.velocity.length() > config.route_min_speed:
		var b := target.velocity.angle_to(offset)
		if absf(b) < deg_to_rad(config.route_cone_deg):
			in_cone = true
			cone_kind = &"route"
			return orbit_dir if b == 0.0 else signf(b)
	return 0.0


# ── BREAK_OFF ────────────────────────────────────────────────────────────────────────────────────

func _tick_break_off(_delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		_end_break_off()
		return
	var pos := actor.global_position
	var distance := pos.distance_to(target.position)
	if distance > config.min_range + config.break_exit_margin or _phase_time >= config.break_max_seconds - CLOCK_EPSILON:
		_end_break_off()
		_arc_motion(_delta, target)  # HOLD_ARC requests on the tick it resumes
		return
	var dir := Steering.break_contact(pos, target.position, target.velocity, _break_side, 1.0, config.break_lateral_weight).normalized()
	if EnemyWorld.has_view_rect(get_tree()):
		var point := _clamp_into_view(pos + dir * config.max_speed * BREAK_LOOKAHEAD)
		mover.request_velocity(Steering.orbit(pos, point, 0.0, 0.0, config.max_speed))
	elif not mover.is_boosting():
		mover.boost(dir, config.break_speed, config.break_burst_seconds)
	mover.face_toward(target.position)


func _end_break_off() -> void:
	_rearm_left = config.break_rearm_seconds
	enter_phase(Phase.HOLD_ARC)


# ── TELEGRAPH / PULSE (t9) ───────────────────────────────────────────────────────────────────────

## Stub until t9: a TELEGRAPH or PULSE ends on its first tick (DISENGAGE if the budget ran out meanwhile).
func _tick_attack_stub(delta: float) -> void:
	if _disengage_pending:
		enter_phase(Phase.DISENGAGE)
		_tick_disengage(delta)
		return
	enter_phase(Phase.HOLD_ARC)
	_tick_hold_arc(delta)


# ── View clamp ───────────────────────────────────────────────────────────────────────────────────

## Assault: `p` clamped into `view_rect().grow(-(view_margin + VIEW_CLAMP_PAD))` (the Support Ship's clamp, padded); the identity with no view
## rect. Sets `view_clamp_bound`.
func _clamp_into_view(p: Vector2) -> Vector2:
	if not EnemyWorld.has_view_rect(get_tree()):
		view_clamp_bound = false
		return p
	var r := EnemyWorld.view_rect(get_tree()).grow(-(config.view_margin + VIEW_CLAMP_PAD))
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	view_clamp_bound = q != p
	return q


# ── DISENGAGE (the corvette's) ───────────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The curve's rate is capped by what the mover's
## acceleration can follow at exit speed.
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
	if actor is HackerFrigate:
		var light := (actor as HackerFrigate).state_light()
		if light != null:
			light.set_state(state)
