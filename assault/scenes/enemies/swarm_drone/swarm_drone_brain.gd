## The Swarm Drone's brain: the ram cycle and the squad roles (docs/plans/cmufs7ek60001nm2x6d0bt2et/
## 3-plan.md §2.7.1 and §2.7.2; task plans docs/plans/cmuj4y8rh0070p52xk6vzfvbe/ (solo, t8b) and
## docs/plans/cmuj4y8rj0074p52xqmin24gu/ (squad, t8c)).
##
## A drone with no squad (`actor.squad == null`) is a squad of one and its own LEAD. With a squad the
## board (`SquadController`) hands out roles and this brain reads `role_of(actor)` every tick:
## - **LEAD** spirals in (CLOSE_IN) and rams. Its BURST opens `squad.attack_window_open`.
## - **FLANK_LEFT / FLANK_RIGHT** hold a formation slot `flank_distance` from the target at
##   ±`flank_angle_deg` off its heading (FORM). Each answers an open window **once** with its own
##   WINDUP, which gives the pincer.
## - **REAR** circles the target on `rear_orbit_radius` (FORM), evenly spaced by `rear_index`, and
##   never attacks. In Assault it leaves after `rear_engage_seconds`.
## A role change during WINDUP/BURST/OVERSHOOT takes effect after that pass (REJOIN routes by the new
## role). Board calls: `update_target()` every tick, `claim_side()` on WINDUP entry, `release_side()`
## on OVERSHOOT entry, `release_lead()` at REJOIN after a pass made as LEAD, `leave()` on DISENGAGE
## or rail suspension.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH  [APPROACH]  corkscrew toward the player, phase drawn from `rng` (R2.3).
##   FORM      [POSITION]  FLANK slot or REAR ring, by role (t8c).
##   CLOSE_IN  [POSITION]  the LEAD spirals in on a shrinking ring to `flank_distance`.
##   WINDUP    [ATTACK]    hold at the stopping point, face the clamped 0.4-0.8 s prediction; yellow.
##   BURST     [ATTACK]    `mover.boost()` at the aim locked on WINDUP's last tick; red, contact armed.
##   OVERSHOOT [REPOSITION] a missed burst curves back toward the player — `Steering.turn_toward()`
##                          from the actor's CURRENT velocity every tick (D7), never a zero request.
##   REJOIN    one tick: hand the lead on (a pass made as LEAD), reset the passes, then CLOSE_IN
##             (LEAD), FORM (other roles) or APPROACH (far).
##   DISENGAGE [DISENGAGE] Assault only (`EngagementBudget`): release the corridor, seek the nearest
##                          edge of the projectile world rect, free once strictly outside it.
##   IDLE      [SEARCH]    Open Space only (t8d): a slow ring orbit around `patrol_anchor`.
##   NOTICING  [SEARCH]    a beat: the light blinks once and the drone faces the player for
##                          `notice_time`, then hands over to APPROACH from its CURRENT velocity —
##                          no `halt()`, no `boost()` (the handover guard).
##   RETURNING [REPOSITION] `arrive` back at `patrol_anchor`, then IDLE.
##
## Tunables are exported here and overwritten from `SwarmDroneConfig` by `swarm_drone.gd`'s
## `_ready()`, which runs AFTER this node's `_ready()` (children first). So nothing that depends on
## a tunable is derived in `_ready()`: the budget and `passes_left` are built on the first tick.
##
## Nudges (flocking + evade) are offered in APPROACH, CLOSE_IN, FORM, IDLE and RETURNING only: never
## in WINDUP/BURST (committed), OVERSHOOT (its per-tick curve bound assumes the one request) or
## NOTICING (a beat, not a positioning phase).
##
## Hub idle (t8d, §2.7.3): Open Space only (`EngagementBudget.active == false`) — Assault always
## starts in combat, since the level has already decided the fight is on. Each member owns an
## `AnchorIdle` on the squad's shared `patrol_anchor`. A perceiving member calls
## `squad.set_engaged(actor, true)`; a member in IDLE/RETURNING sees `squad.is_engaged()` and calls
## `force_notice()`; `hold_combat` keeps every member fighting while any one of them is engaged, so
## the squad returns together once none are. `start_engaged` is a test seam: every pre-t8d test
## sets it so a spawned drone starts already fighting, exactly as every drone did before this task.
##
## Requests only (single-writer gate): the one field writes on the mover are `max_speed` and
## `release_constraint()` on DISENGAGE. Board writes (`attack_window_open`, `rear_ring_angle`) are
## field writes too.
class_name SwarmDroneBrain
extends EnemyBrain

## FORM is appended so the t8b values do not move; IDLE/NOTICING/RETURNING likewise for t8c's.
enum Phase { APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT, REJOIN, DISENGAGE, FORM, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## APPROACH hands over at `rear_orbit_radius` + this (px).
const APPROACH_EXIT_MARGIN := 100.0
## CLOSE_IN / FORM / REJOIN fall back to APPROACH beyond `rear_orbit_radius` + this (px).
const APPROACH_REENTER_MARGIN := 200.0
## `phase_offset` is drawn from ±this (rad): R2.3's per-drone offset, bounded so it never undoes the
## REAR ring's index spacing (t8c task plan D2: ≥ 50° between REARs at the widest 90° spacing).
const MAX_PHASE_OFFSET := 0.35
## Flocking gains [judgement], summed then capped at `flock_nudge_cap × max_speed`: separation in
## px/s per px of overlap, alignment on (mean mate velocity − own), cohesion on the offset to the
## mates' centroid.
const SEPARATION_GAIN := 6.0
const ALIGNMENT_GAIN := 0.1
const COHESION_GAIN := 0.05
## Evade's look-ahead on the target's velocity (s).
const EVADE_LOOKAHEAD := 0.25
## How fast CLOSE_IN's ring shrinks (px/s).
const CLOSE_IN_SHRINK_SPEED := 120.0
## CLOSE_IN's tangential anchor speed (px/s) — below `max_speed`, so the anchor stays catchable.
const CLOSE_IN_TANGENT_SPEED := 130.0
## CLOSE_IN is "on the ring" within this distance of `flank_distance` (px).
const CLOSE_IN_TOLERANCE := 30.0
## CLOSE_IN winds up after this long even if it never settled (s).
const CLOSE_IN_MAX_SECONDS := 2.5
## WINDUP's hold tolerance (px).
const HOLD_TOLERANCE := 4.0
## With a squad, the aim is offset one hull width toward the claimed side (px).
const HULL_WIDTH := 32.0
## Below this target speed (px/s) its heading comes from its facing instead of its velocity.
const HEADING_MIN_SPEED := 20.0
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Slack on the WINDUP budget gate (s) — a few physics ticks of rounding on each phase.
const ATTACK_GATE_MARGIN := 0.15

@export_group("Movement")
@export var max_speed: float = 220.0
@export var braking: float = 900.0

@export_group("Approach")
@export var corkscrew_amplitude: float = 120.0
@export var corkscrew_frequency: float = 0.6

@export_group("Attack")
@export var windup_seconds: float = 0.4
@export var burst_speed: float = 480.0
@export var burst_seconds: float = 0.45
@export var lead_time_min: float = 0.4
@export var lead_time_max: float = 0.8
@export var overshoot_seconds: float = 0.8
@export var overshoot_turn_rate: float = 2.4
@export var second_passes: int = 1

@export_group("Exit")
@export var engage_seconds: float = 5.5
@export var exit_speed: float = 320.0

@export_group("Squad")
@export var rear_orbit_radius: float = 260.0
@export var rear_orbit_speed: float = 0.55
@export var flank_distance: float = 200.0
@export var flank_angle_deg: float = 70.0
@export var separation_radius: float = 30.0
@export var flock_nudge_cap: float = 0.35
@export var evade_radius: float = 90.0
@export var rear_engage_seconds: float = 5.5

@export_group("Idle")
@export var perceive_radius: float = 380.0
@export var lose_radius: float = 620.0
@export var notice_time: float = 0.35
@export var idle_radius: float = 140.0
@export var idle_speed: float = 0.6
## The Open Space hub idle's ring centre. `Vector2.INF` (unfinished) means "not set" — `_start()`
## then defaults it to the spawn position, so a loose drone with no owner still patrols somewhere.
@export var patrol_anchor: Vector2 = Vector2.INF

## Test seam (t8d): every pre-idle test sets this so a spawned drone starts already fighting, the
## only behaviour that existed before this task. Real spawns (SectorHub) never set it — an Open
## Space Swarm Drone always patrols `patrol_anchor` until it perceives the player. Assault ignores
## it: `EngagementBudget.active` alone decides combat-from-spawn there.
var start_engaged: bool = false

var phase: Phase = Phase.APPROACH
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once,
## in `_start()`.
var anchor_idle: AnchorIdle
## This drone's offset on the REAR ring (rad), drawn once from `rng` in `_ready()` (R2.3).
var phase_offset: float = 0.0
## Extra passes left in the current attack cycle.
var passes_left: int = 0
## The ram point: re-evaluated every WINDUP tick, locked on the last one.
var aim: Vector2 = Vector2.ZERO
## The lead time (s) behind `aim`.
var lead_time: float = 0.0
## Bursts started since spawn.
var burst_count: int = 0
## The corkscrew phase (rad). Drawn from `rng` in `_ready()`, advanced every APPROACH tick.
var cork_phase: float = 0.0
## Built on the first tick (see the header). Null before it.
var budget: EngagementBudget

var _started: bool = false
var _spin: float = 1.0
var _phase_time: float = 0.0
var _ring: float = 0.0
var _ring_angle: float = 0.0
var _hold_at: Vector2 = Vector2.ZERO
var _burst_dir: Vector2 = Vector2.DOWN
var _last_target_pos: Vector2 = Vector2.ZERO
var _exit_point: Vector2 = Vector2.ZERO
## The side `claim_side()` returned on WINDUP entry, or -1 (none / released).
var _claimed_side: int = -1
## The role this drone held on its last WINDUP entry, or -1. A different `_role()` at the end of
## the pass means the role changed mid-pass.
var _pass_role: int = -1
## True once this FLANK has answered the currently open attack window; cleared whenever the window
## reads closed, so each window is answered once (the lead's second-pass burst re-opens nothing).
var _answered_window: bool = false


func _ready() -> void:
	super._ready()
	cork_phase = rng.randf_range(0.0, TAU)
	_spin = 1.0 if rng.randf() < 0.5 else -1.0
	# Drawn last, so the t8b draws above keep their values for a given seed.
	phase_offset = rng.randf_range(-MAX_PHASE_OFFSET, MAX_PHASE_OFFSET)


func tick(delta: float) -> void:
	if not _started:
		_start()
	var target := TargetInfo.player(get_tree())
	var squad := _squad()
	if target.has_target:
		_last_target_pos = target.position
		if squad != null:
			squad.update_target(target.position, _heading_of(target))
	if squad != null and not squad.attack_window_open:
		_answered_window = false

	if anchor_idle != null:
		_tick_anchor_idle(delta, target, squad)
	else:
		var expired := budget.update(delta) or _rear_budget_expired()
		if expired and phase != Phase.DISENGAGE and phase != Phase.BURST:
			enter_phase(Phase.DISENGAGE)

	# A transition hands over to the new phase's handler in the same tick, so a tick never goes
	# without a request. Bounded: no chain is longer than OVERSHOOT -> REJOIN -> FORM -> WINDUP.
	for _i in 4:
		var before := phase
		_tick_phase(delta, target)
		if phase == before:
			break


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	phase = p
	_phase_time = 0.0
	match p:
		Phase.CLOSE_IN: _enter_close_in()
		Phase.WINDUP: _enter_windup()
		Phase.BURST: _enter_burst()
		Phase.OVERSHOOT: _enter_overshoot()
		Phase.REJOIN: _enter_rejoin()
		Phase.DISENGAGE: _enter_disengage()
		Phase.NOTICING: _enter_noticing()
		Phase.RETURNING: _enter_returning()
	phase_changed.emit(p)


func on_suspended() -> void:
	_set_light(StateLight.State.ARMED)
	var squad := _squad()
	if squad != null:
		squad.leave(actor)


## True when there is time left to finish a whole wind-up + burst and shed the burst's excess speed
## before the budget expires, so expiry never lands in a burst (task plan, review B3).
func can_start_attack() -> bool:
	if budget == null:
		return true
	var shed := maxf(burst_speed - max_speed, 0.0) / braking if braking > 0.0 else 0.0
	return budget.remaining() >= windup_seconds + burst_seconds + shed + ATTACK_GATE_MARGIN


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(engage_seconds, get_tree())
	passes_left = second_passes
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, perceive_radius, lose_radius, notice_time, idle_radius)
		enter_phase(Phase.IDLE)


func _tick_phase(delta: float, target: TargetInfo) -> void:
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.CLOSE_IN: _tick_close_in(delta, target)
		Phase.WINDUP: _tick_windup(delta, target)
		Phase.BURST: _tick_burst()
		Phase.OVERSHOOT: _tick_overshoot(delta, target)
		Phase.REJOIN: _tick_rejoin(target)
		Phase.DISENGAGE: _tick_disengage()
		Phase.FORM: _tick_form(delta, target)
		Phase.IDLE: _tick_idle(delta, target)
		Phase.NOTICING: _tick_noticing(target)
		Phase.RETURNING: _tick_returning(target)


## In Assault, a REAR that is not attacking leaves after `rear_engage_seconds` (t8c; ≤
## `engage_seconds`, so the §2.6 deadline still bounds it). Never cuts a pass: an attacker is never
## REAR in APPROACH/FORM.
func _rear_budget_expired() -> bool:
	if not budget.active or _role() != SquadController.Role.REAR:
		return false
	if phase != Phase.APPROACH and phase != Phase.FORM:
		return false
	return budget.seconds - budget.remaining() >= rear_engage_seconds


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_hold_here()
		return
	var pos := actor.global_position
	if pos.distance_to(target.position) <= rear_orbit_radius + APPROACH_EXIT_MARGIN:
		enter_phase(Phase.CLOSE_IN if _role() == SquadController.Role.LEAD else Phase.FORM)
		return
	mover.request_velocity(Steering.corkscrew(
		pos, target.position - pos, max_speed, corkscrew_amplitude, cork_phase))
	cork_phase = fposmod(cork_phase + TAU * corkscrew_frequency * delta, TAU)
	_apply_nudge(target)


# ── FORM (t8c): FLANK slot or REAR ring ──────────────────────────────────────────────────────────

func _tick_form(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_hold_here()
		return
	if actor.global_position.distance_to(target.position) > _reenter_radius():
		enter_phase(Phase.APPROACH)
		return
	var role := _role()
	var squad := _squad()
	if role == SquadController.Role.LEAD or squad == null:
		enter_phase(Phase.CLOSE_IN)
		return
	if role == SquadController.Role.REAR:
		_form_rear(delta, target, squad)
	else:
		if squad.attack_window_open and not _answered_window and can_start_attack():
			_answered_window = true
			enter_phase(Phase.WINDUP)
			return
		var side := 1.0 if role == SquadController.Role.FLANK_RIGHT else -1.0
		var slot := Vector2.RIGHT.rotated(side * deg_to_rad(flank_angle_deg)) * flank_distance
		mover.formation_slot(target.position, _heading_of(target), slot, max_speed)
	_apply_nudge(target)


## The member's slot on the shared ring: `rear_ring_angle + rear_index × TAU / rear_count +
## phase_offset`. Any REAR that finds the ring unset starts it where it already is; only rear 0
## advances it, so while rear 0 is elsewhere (still approaching) the ring stands still.
func _form_rear(delta: float, target: TargetInfo, squad: SquadController) -> void:
	var centre := _ring_centre(target.position)
	var spacing := TAU / maxi(squad.rear_count(), 1)
	var index := maxi(squad.rear_index(actor), 0)
	if is_nan(squad.rear_ring_angle):
		squad.rear_ring_angle = (actor.global_position - centre).angle() - index * spacing - phase_offset
	if index == 0:
		squad.rear_ring_angle = fposmod(squad.rear_ring_angle + rear_orbit_speed * delta, TAU)
	mover.orbit(centre, rear_orbit_radius, squad.rear_ring_angle + index * spacing + phase_offset, max_speed)


## The target position, kept inside the constraint's `inner_rect()` shrunk by the ring radius, so a
## ring near a corridor edge does not fight the edge pressure (§2.7.1). Unbounded (Open Space): as is.
func _ring_centre(p: Vector2) -> Vector2:
	if mover.constraint == null:
		return p
	var inner := mover.constraint.inner_rect().grow(-rear_orbit_radius)
	if not inner.has_area():
		return p
	return p.clamp(inner.position, inner.end)


# ── CLOSE_IN ─────────────────────────────────────────────────────────────────────────────────────

func _enter_close_in() -> void:
	var target := TargetInfo.player(get_tree())
	var center := target.position if target.has_target else _last_target_pos
	var offset := actor.global_position - center
	_ring = maxf(offset.length(), flank_distance)
	_ring_angle = offset.angle()


func _tick_close_in(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_hold_here()
		return
	var dist := actor.global_position.distance_to(target.position)
	if dist > _reenter_radius():
		enter_phase(Phase.APPROACH)
		return
	if _role() != SquadController.Role.LEAD:
		enter_phase(Phase.FORM)
		return
	_phase_time += delta
	var settled := is_equal_approx(_ring, flank_distance) and absf(dist - flank_distance) <= CLOSE_IN_TOLERANCE
	if (settled or _phase_time >= CLOSE_IN_MAX_SECONDS) and can_start_attack():
		enter_phase(Phase.WINDUP)
		return
	_ring = move_toward(_ring, flank_distance, CLOSE_IN_SHRINK_SPEED * delta)
	_ring_angle += _spin * CLOSE_IN_TANGENT_SPEED / _ring * delta
	mover.spiral(target.position, _ring, _ring_angle, 0.0, max_speed)
	_apply_nudge(target)


# ── WINDUP ───────────────────────────────────────────────────────────────────────────────────────

func _enter_windup() -> void:
	var pos := actor.global_position
	var v := actor.velocity
	# Hold at the point the drone can stop at, not where it was — arriving back at the entry point
	# overshoots and is still drifting when the burst starts (task plan review N1).
	_hold_at = pos
	if braking > 0.0 and v.length_squared() > 0.0:
		_hold_at = pos + v.normalized() * (v.length_squared() / (2.0 * braking))
	_set_armed(false)
	_set_light(StateLight.State.CHARGING)
	_pass_role = _role()
	var squad := _squad()
	if squad != null:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			_claimed_side = squad.claim_side(actor, _sector_of(pos, target))
	aim = pos + _facing() * flank_distance


func _tick_windup(delta: float, target: TargetInfo) -> void:
	if target.has_target:
		var dist := actor.global_position.distance_to(target.position)
		lead_time = Steering.clamped_lead_time(dist, burst_speed, lead_time_min, lead_time_max)
		aim = target.predicted_position(lead_time) + _side_offset(target)
	mover.hold_position(_hold_at, HOLD_TOLERANCE, max_speed)
	mover.face_toward(aim)
	_phase_time += delta
	if _phase_time >= windup_seconds - 0.0001:
		enter_phase(Phase.BURST)


# ── BURST ────────────────────────────────────────────────────────────────────────────────────────

func _enter_burst() -> void:
	burst_count += 1
	var dir := aim - actor.global_position
	if dir.length_squared() < 0.000001:
		dir = _facing()
	_burst_dir = dir.normalized()
	_set_armed(true)
	_set_light(StateLight.State.ARMED)
	if _pass_role < 0:
		_pass_role = _role()  # a burst entered without a WINDUP (the `enter_phase` test seam)
	# Only a lead that wound up as lead and still is opens the window: one demoted during its
	# WINDUP must not open a window for the new lead (t8c task plan review round 2 A1).
	var squad := _squad()
	if squad != null and _pass_role == SquadController.Role.LEAD and _role() == SquadController.Role.LEAD:
		squad.attack_window_open = true
	mover.boost(_burst_dir, burst_speed, burst_seconds)


func _tick_burst() -> void:
	# The boost ignores requests; a contact would already have detonated and freed the drone.
	if not mover.is_boosting():
		enter_phase(Phase.OVERSHOOT)


# ── OVERSHOOT ────────────────────────────────────────────────────────────────────────────────────

func _enter_overshoot() -> void:
	_set_armed(false)
	_set_light(StateLight.State.OFF)
	var squad := _squad()
	_claimed_side = -1
	if squad != null:
		squad.release_side(actor)


func _tick_overshoot(delta: float, target: TargetInfo) -> void:
	_phase_time += delta
	if _phase_time > overshoot_seconds + 0.0001:
		# A role change during the pass takes effect now: no further pass in the old role.
		if _role() == _pass_role and passes_left > 0 and can_start_attack():
			passes_left -= 1
			enter_phase(Phase.WINDUP)
		else:
			enter_phase(Phase.REJOIN)
		return
	# Rebuilt from the actor's CURRENT velocity every tick, never from the previous request, so the
	# mover's straight-segment `move_toward` bounds the heading change to `overshoot_turn_rate · delta`.
	var current := actor.velocity
	if current.length_squared() < 0.000001:
		current = _burst_dir
	var toward := (target.position - actor.global_position) if target.has_target else current
	var dir := Steering.turn_toward(current.normalized(), toward, overshoot_turn_rate, delta)
	mover.request_velocity(dir * max_speed)


# ── REJOIN ───────────────────────────────────────────────────────────────────────────────────────

## Only a cycle made as LEAD, by a drone that still is LEAD, hands the token on. A member promoted
## mid-pass keeps it (it has not attacked as lead yet); a flank has nothing to hand on.
func _enter_rejoin() -> void:
	passes_left = second_passes
	var squad := _squad()
	if squad == null or _pass_role != SquadController.Role.LEAD or _role() != SquadController.Role.LEAD:
		return
	# A sole member keeps its lead: `release_lead()` would leave nobody eligible and pin it to REAR
	# (squad_controller.gd `_reassign(force_rear)`), and every loose level spawn is a squad of one.
	# It closes its own window instead, so a later joiner never finds it stuck open.
	if squad.members().size() >= 2:
		squad.release_lead(actor)
	else:
		squad.attack_window_open = false


func _tick_rejoin(target: TargetInfo) -> void:
	if target.has_target and actor.global_position.distance_to(target.position) > _reenter_radius():
		enter_phase(Phase.APPROACH)
	elif _role() == SquadController.Role.LEAD:
		enter_phase(Phase.CLOSE_IN)
	else:
		enter_phase(Phase.FORM)


# ── DISENGAGE ────────────────────────────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	_set_armed(false)
	_set_light(StateLight.State.OFF)
	var squad := _squad()
	if squad != null:
		squad.leave(actor)
	mover.release_constraint()
	mover.max_speed = exit_speed
	# The nearest edge, chosen once: every point of the rect is within half its shorter side of
	# one, which is the bound the §2.6 deadline formula uses.
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open), the
## same rule `DroneInterceptorBrain._check_dash_end()` follows.
func _tick_disengage() -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	mover.seek(_exit_point, exit_speed)


# ── Hub idle (t8d; epic §2.7.3) ──────────────────────────────────────────────────────────────────

## The meta-state that decides whether this member is patrolling, noticing or fighting, run once a
## tick alongside (not instead of) the phase dispatch below — `anchor_idle`'s own state (IDLE /
## NOTICING / COMBAT / RETURNING) tracks this member's own proximity to the target independently of
## whichever attack-cycle phase it is currently in, so a squad still returns together even while one
## member is mid-FORM (§2.7.3 "hold_combat keeps everyone fighting").
func _tick_anchor_idle(delta: float, target: TargetInfo, squad: SquadController) -> void:
	if squad != null and (phase == Phase.IDLE or phase == Phase.RETURNING) and squad.is_engaged():
		anchor_idle.force_notice()
	var state := anchor_idle.update(delta, actor.global_position, target)
	if squad != null:
		# Review N17: engaged only while both perceiving/fighting AND still within lose_radius —
		# never from hold_combat alone, or a member held in COMBAT by its mates would itself never
		# stop reporting engaged, and the squad could never lose the player at all.
		var near := target.has_target and actor.global_position.distance_squared_to(target.position) < lose_radius * lose_radius
		var engaged := (state == AnchorIdle.State.NOTICING or state == AnchorIdle.State.COMBAT) and near
		squad.set_engaged(actor, engaged)
		anchor_idle.hold_combat = squad.is_engaged()
	match state:
		AnchorIdle.State.IDLE:
			if phase != Phase.IDLE:
				enter_phase(Phase.IDLE)
		AnchorIdle.State.NOTICING:
			if phase != Phase.NOTICING:
				enter_phase(Phase.NOTICING)
		AnchorIdle.State.COMBAT:
			# From NOTICING only: entering combat from FORM/CLOSE_IN/etc. would re-enter a phase
			# that is already running. From the drone's CURRENT velocity — enter_phase(APPROACH)
			# runs no entry code, so the handover guard rests entirely on the mover's own bounds.
			if phase == Phase.NOTICING:
				enter_phase(Phase.APPROACH)
		AnchorIdle.State.RETURNING:
			# Never interrupts a live BURST (same guard the budget-expiry check above uses).
			if phase != Phase.RETURNING and phase != Phase.BURST:
				enter_phase(Phase.RETURNING)


func _enter_noticing() -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(StateLight.State.OFF)
		light.blink_once()


func _tick_noticing(target: TargetInfo) -> void:
	if target.has_target:
		mover.face_toward(target.position)


func _enter_returning() -> void:
	_set_armed(false)
	_set_light(StateLight.State.OFF)


func _tick_returning(target: TargetInfo) -> void:
	mover.arrive(patrol_anchor, max_speed)
	_apply_nudge(target)


func _tick_idle(delta: float, target: TargetInfo) -> void:
	_phase_time += delta
	mover.orbit(patrol_anchor, idle_radius, _idle_ring_angle(), max_speed)
	_apply_nudge(target)


## `phase_offset + index × TAU / n + idle_speed × t` (§2.7.3), with `index` the member's join order
## among the whole squad — a squad of one (or no squad) is index 0 of 1.
func _idle_ring_angle() -> float:
	var squad := _squad()
	var index := 0
	var n := 1
	if squad != null:
		index = maxi(squad.member_index(actor), 0)
		n = maxi(squad.member_count(), 1)
	return phase_offset + index * TAU / n + idle_speed * _phase_time


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## This drone's role: LEAD without a squad (a squad of one) and after it has left one (NONE); the
## board's otherwise. Read every tick, never cached — the board recomputes on any join or leave.
## `int`, not `SquadController.Role`: the cross-script nested-enum rule (DECISIONS, t4).
func _role() -> int:
	var squad := _squad()
	if squad == null:
		return SquadController.Role.LEAD
	var role: int = squad.role_of(actor)
	return SquadController.Role.LEAD if role == SquadController.Role.NONE else role


## CLOSE_IN / FORM / REJOIN fall back to APPROACH beyond this distance (px).
func _reenter_radius() -> float:
	return rear_orbit_radius + APPROACH_REENTER_MARGIN


## Offers `_nudge()` to the mover, when it is non-zero.
func _apply_nudge(target: TargetInfo) -> void:
	var nudge := _nudge(target)
	if nudge != Vector2.ZERO:
		mover.add_nudge(nudge)


## Flocking over squad mates plus an evade inside `evade_radius` of the target, capped at
## `flock_nudge_cap × max_speed` (§2.2 composition rule: one request, one capped nudge). A mate's
## velocity is read only from a `CharacterBody2D`; anything else counts as still.
func _nudge(target: TargetInfo) -> Vector2:
	var cap := flock_nudge_cap * max_speed
	if cap <= 0.0:
		return Vector2.ZERO
	var pos := actor.global_position
	var total := Vector2.ZERO
	var squad := _squad()
	if squad != null:
		var mate_pos: Array[Vector2] = []
		var mate_vel: Array[Vector2] = []
		for m in squad.members():
			if m == actor:
				continue
			mate_pos.append(m.global_position)
			mate_vel.append((m as CharacterBody2D).velocity if m is CharacterBody2D else Vector2.ZERO)
		if not mate_pos.is_empty():
			total += Steering.separation(pos, mate_pos, separation_radius) * SEPARATION_GAIN
			total += (Steering.alignment(actor.velocity, mate_vel) - actor.velocity) * ALIGNMENT_GAIN
			total += Steering.cohesion(pos, mate_pos) * COHESION_GAIN
	if target.has_target and pos.distance_to(target.position) < evade_radius:
		total += Steering.evade(pos, target.position, target.velocity, max_speed, EVADE_LOOKAHEAD)
	return total.limit_length(cap)


func _hold_here() -> void:
	mover.hold_position(actor.global_position, HOLD_TOLERANCE, max_speed)


## The squad board the actor carries (`SwarmDrone.squad`), read duck-typed; null for none.
func _squad() -> SquadController:
	if actor == null:
		return null
	return actor.get(&"squad") as SquadController


## The unit vector the actor's nose points along, from its rotation and `sprite_forward_angle`.
func _facing() -> Vector2:
	var forward: Variant = actor.get(&"sprite_forward_angle")
	var offset := float(forward) if (forward is float or forward is int) else PI / 2.0
	return Vector2.RIGHT.rotated(actor.rotation + offset)


## The target's heading: its velocity direction, or its facing when it is nearly still.
func _heading_of(target: TargetInfo) -> Vector2:
	if target.velocity.length() >= HEADING_MIN_SPEED:
		return target.velocity.normalized()
	return target.facing


## The sector of the target the drone is in, relative to its heading — the same cross-product sign
## `SquadController` uses for flanks (cross >= 0 is the RIGHT side).
func _sector_of(pos: Vector2, target: TargetInfo) -> int:
	var heading := _heading_of(target)
	var rel := pos - target.position
	var forward := rel.dot(heading)
	var lateral := heading.cross(rel)
	if absf(lateral) >= absf(forward):
		return SquadController.Side.RIGHT if lateral >= 0.0 else SquadController.Side.LEFT
	return SquadController.Side.FRONT if forward >= 0.0 else SquadController.Side.BACK


## With a squad, one hull width toward the claimed side, so two attackers do not converge on one
## point. Zero without a squad or a claim.
func _side_offset(target: TargetInfo) -> Vector2:
	var squad := _squad()
	if squad == null or _claimed_side < 0:
		return Vector2.ZERO
	var heading := _heading_of(target)
	match _claimed_side:
		SquadController.Side.RIGHT: return heading.rotated(PI / 2.0) * HULL_WIDTH
		SquadController.Side.LEFT: return heading.rotated(-PI / 2.0) * HULL_WIDTH
		SquadController.Side.FRONT: return heading * HULL_WIDTH
		_: return -heading * HULL_WIDTH


func _profile() -> ContactProfile:
	return actor.get(&"contact_profile") as ContactProfile if actor != null else null


func _set_armed(armed: bool) -> void:
	var profile := _profile()
	if profile != null:
		profile.set_armed(armed)


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
