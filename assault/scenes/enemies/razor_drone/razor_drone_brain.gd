## The Razor Drone's brain: orbit, reversal, feint and the real dash
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.8.2; task plan
## docs/plans/cmuj4y8rr007gp52xxs8dec5s/3-plan.md, rev 2 + amendments A1-A5).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   ENTER        [APPROACH]   seek the player; on reaching `orbit_radius` re-anchor the orbit where the
##                             drone is (A2) and ORBIT. Also the handover target from NOTICING: no
##                             entry code runs, so a perceiving drone keeps its current velocity.
##   ORBIT        [POSITION]   `Steering.orbit` round `orbit_centre` (the player; in Assault clamped into
##                             the corridor's `inner_rect()` shrunk by `orbit_radius`). Each rng window
##                             (1-2 s) ends in a roll: REVERSE, a fake or a real attack.
##   REVERSE      [POSITION]   the anchor's angular speed ramps through zero to the opposite sense over
##                             `reverse_seconds`. Barred again until the next attack begins.
##   FEINT_WINDUP [ATTACK]     yellow for `windup_seconds × fake_windup_scale`, holding.
##   FEINT_LUNGE  [ATTACK]     a boost aimed `feint_clearance_px` BESIDE the player; light off, never armed.
##   FEINT_BRAKE  [ATTACK]     brake to a stop on the far side, flip the orbit, WINDUP at once.
##   WINDUP       [ATTACK]     yellow for `windup_seconds`, then white (COMMIT) for
##                             `commit_flash_seconds` with the dash point locked on its first tick.
##                             The only code path that shows white.
##   DASH         [ATTACK]     RAMMING contact armed, red; a boost through the locked point.
##   OVERSHOOT    [REPOSITION] disarm; after a miss fire ONE pulse; curve back with
##                             `Steering.turn_toward()` from the actor's CURRENT velocity (D7).
##   RETURN       [REPOSITION] `arrive` back onto the orbit ring, then ORBIT with a new window.
##   DISENGAGE    [DISENGAGE]  Assault only (`EngagementBudget`): release the corridor, seek the nearest
##                             edge of the projectile world rect, free once strictly outside it.
##   IDLE_ORBIT   [SEARCH]     Open Space only (t11): a slow, irregular patrol ring round `patrol_anchor`.
##                             Re-anchors on entry (never a snap) and redraws its radius/speed/duration.
##   IDLE_BRAKE   [SEARCH]     a short hold (`IDLE_BRAKE_SECONDS`), then a fresh IDLE_ORBIT leg.
##   IDLE_REVERSE [SEARCH]     like REVERSE, but on the idle ring: ramps through zero, flips `orbit_dir`.
##   IDLE_BOOST   [SEARCH]     a short boost along the current heading, then a fresh IDLE_ORBIT leg.
##   NOTICING     [SEARCH]     a beat: the light blinks once and the drone faces the player for
##                             `notice_time`, then hands over to ENTER from its CURRENT velocity — no
##                             `halt()`, no `boost()` (the handover guard).
##   RETURNING    [REPOSITION] Open Space only: `arrive` back at `patrol_anchor`, then IDLE_ORBIT. Named
##                             differently from the combat RETURN (the post-overshoot return to the
##                             orbit ring), which it never interrupts.
##
## Side lane (Assault only): an attack starts only when the point the REAL dash will start from lies
## `side_lane_min_deg`-`side_lane_max_deg` off the vertical axis about the player. For a real attack
## that is the WINDUP hold point; for a fake it is the predicted far-side stop, and the lunge side is
## chosen so that it lands in the lane.
##
## Hub idle (t11, §2.8.4): Open Space only (`EngagementBudget.active == false`) — Assault always starts
## in combat, since the level has already decided the fight is on. The drone owns an `AnchorIdle` on
## `patrol_anchor` (an exported sentinel `Vector2.INF` defaults it to the spawn position, same
## convention as the Swarm's). `start_engaged` is a test seam: every pre-t11 test sets it so a spawned
## drone starts already fighting, exactly as every drone did before this task.
##
## Tunables are exported here and overwritten from `RazorDroneConfig` by `razor_drone.gd`'s `_ready()`,
## which runs AFTER this node's `_ready()`, so the budget is built on the first tick. Requests only
## (single-writer gate): the one field writes on the mover are `max_speed` and `release_constraint()`
## on DISENGAGE.
class_name RazorDroneBrain
extends EnemyBrain

## ENTER, ORBIT and DASH keep their Phase 1 values; later phases append.
enum Phase {
	ENTER, ORBIT, DASH, REVERSE, FEINT_WINDUP, FEINT_LUNGE, FEINT_BRAKE, WINDUP, OVERSHOOT, RETURN, DISENGAGE,
	IDLE_ORBIT, IDLE_BRAKE, IDLE_REVERSE, IDLE_BOOST, NOTICING, RETURNING,
}

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## Orbit windows are drawn from this range (s).
const WINDOW_MIN := 1.0
const WINDOW_MAX := 2.0
## An attack pending on the lane waits at most this long, then goes anyway (s).
const LANE_WAIT_MAX := 2.0
## The lane check's inner margin at each end (deg): the hold tolerance plus prediction error. The
## lunge runs 28 ticks rather than 27 from float accumulation; this margin absorbs that — do not
## tighten it (task review round 2).
const LANE_MARGIN_DEG := 3.0
## The WINDUP hold tolerance (px).
const HOLD_TOLERANCE := 4.0
## FEINT_BRAKE hands over below this speed (px/s)...
const FEINT_STOP_SPEED := 40.0
## ...or after this long (s), in case the corridor pins the drone.
const FEINT_BRAKE_MAX_SECONDS := 1.0
## OVERSHOOT ends once the heading is within this of the bearing to the player (deg).
const OVERSHOOT_EXIT_DEG := 20.0
## RETURN hands over within this of the ring (px), or after this long (s).
const RETURN_TOLERANCE := 20.0
const RETURN_MAX_SECONDS := 2.0
## With no target, WINDUP locks this far along the facing (px).
const NO_TARGET_LOCK_DISTANCE := 200.0
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Each idle leg lasts this long (s), drawn from `rng`.
const IDLE_LEG_MIN := 2.0
const IDLE_LEG_MAX := 4.0
## IDLE_BRAKE holds for this long (s).
const IDLE_BRAKE_SECONDS := 0.6
## IDLE_BOOST's speed is this many times the leg's tangential speed (idle_speed × idle_radius).
const IDLE_BOOST_MULT := 1.8
const IDLE_BOOST_SECONDS := 0.4

@export_group("Movement")
@export var orbit_radius: float = 130.0
@export var orbit_speed: float = 1.8
@export var approach_speed: float = 200.0
@export var orbit_correct_speed: float = 260.0
## The mover's braking (px/s²), for the stopping-point and far-side predictions.
@export var braking: float = 700.0

@export_group("Choices")
@export var reverse_chance: float = 0.35
@export var reverse_seconds: float = 0.25
@export var fake_chance: float = 0.35

@export_group("Feint")
@export var fake_windup_scale: float = 1.5
@export var feint_lunge_speed: float = 360.0
@export var feint_lunge_seconds: float = 0.45
@export var feint_clearance_px: float = 70.0

@export_group("Attack")
@export var windup_seconds: float = 0.5
@export var commit_flash_seconds: float = 0.12
@export var dash_speed: float = 480.0
@export var dash_prediction_time: float = 0.2
@export var overshoot_px: float = 120.0
@export var max_dash_seconds: float = 0.9

@export_group("Overshoot")
@export var overshoot_speed: float = 200.0
@export var overshoot_turn_rate: float = 3.0
@export var overshoot_max_seconds: float = 1.2

@export_group("Assault")
@export var engage_seconds: float = 9.0
@export var exit_speed: float = 320.0
@export var side_lane_min_deg: float = 30.0
@export var side_lane_max_deg: float = 75.0

@export_group("Idle")
@export var idle_radius: float = 160.0
@export var idle_radius_jitter: float = 40.0
@export var idle_speed: float = 0.5
@export var idle_speed_jitter: float = 0.2
@export var perceive_radius: float = 450.0
@export var lose_radius: float = 700.0
@export var notice_time: float = 0.35
## The Open Space hub idle's ring centre. `Vector2.INF` (unfinished) means "not set" — `_start()`
## then defaults it to the spawn position, the same sentinel `SwarmDroneBrain.patrol_anchor` uses.
@export var patrol_anchor: Vector2 = Vector2.INF

## Test seam (t11): every pre-idle test sets this so a spawned drone starts already fighting, the
## only behaviour that existed before this task. A real spawn always patrols `patrol_anchor` until it
## perceives the player. Assault ignores it: `EngagementBudget.active` alone decides combat-from-spawn.
var start_engaged: bool = false

var phase: Phase = Phase.ENTER
## +1 or -1: the orbit's sense. Drawn from `rng` in `_ready()`.
var orbit_dir: float = 1.0
## The orbit anchor's angular speed (rad/s) this tick: `orbit_dir × orbit_speed`, except in REVERSE.
var angular_speed: float = 0.0
## What the orbit circles: the player, clamped into the corridor in Assault.
var orbit_centre: Vector2 = Vector2.ZERO
## The current (or last) dash's unit direction.
var dash_direction: Vector2 = Vector2.ZERO
## True once the current dash registered a contact.
var dash_hit: bool = false
## Pulse shots fired since spawn (one per missed dash at most).
var pulses_fired: int = 0
## The side (±1) the current feint lunges on; defaults to `orbit_dir`.
var lunge_side: float = 1.0
## Built on the first tick. Null before it.
var budget: EngagementBudget
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once,
## in `_start()`.
var anchor_idle: AnchorIdle

var _started: bool = false
var _orbit_angle: float = 0.0
var _window_left: float = 0.0
var _phase_time: float = 0.0
var _forced: StringName = &""
## The roll's result while it waits for the lane: &"" (none), &"fake" or &"real".
var _pending: StringName = &""
var _pending_wait: float = 0.0
var _reverse_barred: bool = false
var _reverse_from: float = 0.0
var _hold_at: Vector2 = Vector2.ZERO
var _locked: bool = false
var _locked_point: Vector2 = Vector2.ZERO
var _exit_point: Vector2 = Vector2.ZERO
## The idle ring's own angle/radius/tangential speed (rad, px, rad/s) — kept apart from the combat
## `_orbit_angle` / `orbit_centre`, which the player-following ORBIT phase owns.
var _idle_angle: float = 0.0
var _idle_ring_radius: float = 0.0
var _idle_speed_mag: float = 0.0
var _idle_leg_left: float = 0.0
## The next idle leg's roll, forced by `force_next_idle_leg()`: &"" (none), &"brake", &"reverse" or
## &"boost".
var _forced_idle: StringName = &""


func _ready() -> void:
	super._ready()
	# Same order as the Phase 1 port, so a seed keeps its orbit angle and first window.
	_orbit_angle = rng.randf_range(0.0, TAU)
	_window_left = rng.randf_range(WINDOW_MIN, WINDOW_MAX)
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	angular_speed = orbit_dir * orbit_speed
	lunge_side = orbit_dir


func tick(delta: float) -> void:
	if not _started:
		_start()
	var target := TargetInfo.player(get_tree())
	if target.has_target and not _in_anchor_idle_phase():
		orbit_centre = _centre_of(target.position)
	if anchor_idle != null:
		_tick_anchor_idle(delta, target)
	elif budget.update(delta) and phase != Phase.DISENGAGE and not mover.is_boosting():
		enter_phase(Phase.DISENGAGE)
	# A transition hands over to the new phase's handler in the same tick. Bounded: the longest
	# chain is DASH -> OVERSHOOT -> RETURN -> ORBIT.
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
		Phase.ORBIT: _enter_orbit()
		Phase.REVERSE: _enter_reverse()
		Phase.FEINT_WINDUP: _enter_feint_windup()
		Phase.FEINT_LUNGE: _enter_feint_lunge()
		Phase.WINDUP: _enter_windup()
		Phase.DASH: _enter_dash()
		Phase.OVERSHOOT: _enter_overshoot()
		Phase.DISENGAGE: _enter_disengage()
		Phase.IDLE_ORBIT: _enter_idle_orbit()
		Phase.IDLE_REVERSE: _enter_idle_reverse()
		Phase.IDLE_BOOST: _enter_idle_boost()
		Phase.NOTICING: _enter_noticing()
		Phase.RETURNING: _enter_returning()
	phase_changed.emit(p)


## Test seam: the next window roll takes `choice` (&"real", &"fake" or &"reverse").
func force_next_choice(choice: StringName) -> void:
	_forced = choice


## Test seam: the next idle-leg roll takes `choice` (&"brake", &"reverse" or &"boost").
func force_next_idle_leg(choice: StringName) -> void:
	_forced_idle = choice


## `ContactProfile.contact_made` (only ever while armed, i.e. in DASH): the dash hit.
func on_contact(_area: Area2D) -> void:
	if phase == Phase.DASH:
		dash_hit = true


func on_suspended() -> void:
	_set_light(StateLight.State.ARMED)


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, perceive_radius, lose_radius, notice_time, idle_radius)
		enter_phase(Phase.IDLE_ORBIT)


func _tick_phase(delta: float, target: TargetInfo) -> void:
	match phase:
		Phase.ENTER: _tick_enter(target)
		Phase.ORBIT: _tick_orbit(delta, target)
		Phase.REVERSE: _tick_reverse(delta, target)
		Phase.FEINT_WINDUP: _tick_feint_windup(delta, target)
		Phase.FEINT_LUNGE: _tick_feint_lunge()
		Phase.FEINT_BRAKE: _tick_feint_brake(delta, target)
		Phase.WINDUP: _tick_windup(delta, target)
		Phase.DASH: _tick_dash()
		Phase.OVERSHOOT: _tick_overshoot(delta, target)
		Phase.RETURN: _tick_return(delta, target)
		Phase.DISENGAGE: _tick_disengage()
		Phase.IDLE_ORBIT: _tick_idle_orbit(delta)
		Phase.IDLE_BRAKE: _tick_idle_brake(delta)
		Phase.IDLE_REVERSE: _tick_idle_reverse(delta)
		Phase.IDLE_BOOST: _tick_idle_boost()
		Phase.NOTICING: _tick_noticing(target)
		Phase.RETURNING: _tick_returning()


# ── ENTER ────────────────────────────────────────────────────────────────────────────────────────

func _tick_enter(target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if actor.global_position.distance_to(target.position) <= orbit_radius:
		# A2: start the orbit where the drone is, never on the far side of the player.
		_reanchor()
		enter_phase(Phase.ORBIT)
		return
	mover.seek(target.position, approach_speed)
	mover.face_toward(target.position)


# ── ORBIT / REVERSE ──────────────────────────────────────────────────────────────────────────────

func _enter_orbit() -> void:
	angular_speed = orbit_dir * orbit_speed


func _tick_orbit(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if _pending == &"":
		_window_left -= delta
		if _window_left <= 0.0:
			_roll()
			if _pending == &"reverse":
				_pending = &""
				enter_phase(Phase.REVERSE)
				return
	else:
		_pending_wait += delta
	if _pending != &"" and _try_start_attack(target):
		return
	_orbit_step(delta, target)


func _enter_reverse() -> void:
	_reverse_from = orbit_dir * orbit_speed


func _tick_reverse(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_phase_time += delta
	var t := clampf(_phase_time / reverse_seconds, 0.0, 1.0) if reverse_seconds > 0.0 else 1.0
	angular_speed = lerpf(_reverse_from, -_reverse_from, t)
	_orbit_angle += angular_speed * delta
	mover.orbit(orbit_centre, orbit_radius, _orbit_angle, orbit_correct_speed)
	mover.face_toward(target.position)
	if t >= 1.0:
		orbit_dir = -orbit_dir
		_reverse_barred = true
		_new_window()
		enter_phase(Phase.ORBIT)


func _orbit_step(delta: float, target: TargetInfo) -> void:
	angular_speed = orbit_dir * orbit_speed
	_orbit_angle += angular_speed * delta
	mover.orbit(orbit_centre, orbit_radius, _orbit_angle, orbit_correct_speed)
	mover.face_toward(target.position)


## Sets `_pending` to &"reverse", &"fake" or &"real". A forced choice wins and is consumed.
func _roll() -> void:
	_pending_wait = 0.0
	if _forced != &"":
		_pending = _forced
		_forced = &""
		return
	if not _reverse_barred and rng.randf() < reverse_chance:
		_pending = &"reverse"
	elif rng.randf() < fake_chance:
		_pending = &"fake"
	else:
		_pending = &"real"


## Starts the pending attack if the lane allows it (Assault) or the wait ran out. Returns true when
## it started.
func _try_start_attack(target: TargetInfo) -> bool:
	var stop := _stop_point()
	var lane_active := budget.active
	var side := orbit_dir
	if lane_active:
		var ok := false
		if _pending == &"real":
			ok = _in_lane(stop, target.position, LANE_MARGIN_DEG)
		else:
			for s in [orbit_dir, -orbit_dir]:
				if _in_lane(_predicted_feint_stop(stop, target.position, s), target.position, LANE_MARGIN_DEG):
					side = s
					ok = true
					break
		if not ok and _pending_wait < LANE_WAIT_MAX:
			return false
	var choice := _pending
	_pending = &""
	_reverse_barred = false
	if choice == &"fake":
		lunge_side = side
		enter_phase(Phase.FEINT_WINDUP)
	else:
		enter_phase(Phase.WINDUP)
	return true


# ── FEINT ────────────────────────────────────────────────────────────────────────────────────────

func _enter_feint_windup() -> void:
	_hold_at = _stop_point()
	_set_armed(false)
	_set_light(StateLight.State.CHARGING)


func _tick_feint_windup(delta: float, target: TargetInfo) -> void:
	mover.hold_position(_hold_at, HOLD_TOLERANCE, orbit_correct_speed)
	if target.has_target:
		mover.face_toward(target.position)
	_phase_time += delta
	if _phase_time >= windup_seconds * fake_windup_scale - 0.0001:
		enter_phase(Phase.FEINT_LUNGE)


func _enter_feint_lunge() -> void:
	var target := TargetInfo.player(get_tree())
	var pos := actor.global_position
	var dir := _facing()
	if target.has_target:
		dir = _lunge_direction(pos, target.position, lunge_side)
	# Dark while it lunges and brakes, so the real wind-up that follows reads as a new telegraph.
	_set_light(StateLight.State.OFF)
	mover.boost(dir, feint_lunge_speed, feint_lunge_seconds)


func _tick_feint_lunge() -> void:
	# The boost ignores requests and faces along its own velocity.
	if not mover.is_boosting():
		enter_phase(Phase.FEINT_BRAKE)


func _tick_feint_brake(delta: float, target: TargetInfo) -> void:
	_phase_time += delta
	if actor.velocity.length() < FEINT_STOP_SPEED or _phase_time >= FEINT_BRAKE_MAX_SECONDS:
		_reanchor()
		# The lunge swept round in the -lunge_side sense; the new orbit continues that sweep.
		orbit_dir = -lunge_side
		enter_phase(Phase.WINDUP)
		return
	mover.request_velocity(Vector2.ZERO)
	if target.has_target:
		mover.face_toward(target.position)


## The lunge aims `feint_clearance_px` beside the player, on side `s` (±1).
func _lunge_direction(from: Vector2, target_pos: Vector2, s: float) -> Vector2:
	var to_player := (target_pos - from).normalized()
	var aside := target_pos + to_player.rotated(s * PI / 2.0) * feint_clearance_px
	return (aside - from).normalized()


## Where a feint lunging from `from` on side `s` comes to rest: the boost's distance plus the brake
## from `feint_lunge_speed` down to `FEINT_STOP_SPEED`.
func _predicted_feint_stop(from: Vector2, target_pos: Vector2, s: float) -> Vector2:
	var travel := feint_lunge_speed * feint_lunge_seconds
	if braking > 0.0:
		travel += (feint_lunge_speed * feint_lunge_speed - FEINT_STOP_SPEED * FEINT_STOP_SPEED) / (2.0 * braking)
	return from + _lunge_direction(from, target_pos, s) * travel


# ── WINDUP / DASH ────────────────────────────────────────────────────────────────────────────────

func _enter_windup() -> void:
	_hold_at = _stop_point()
	_locked = false
	_set_armed(false)
	_set_light(StateLight.State.CHARGING)


func _tick_windup(delta: float, target: TargetInfo) -> void:
	_phase_time += delta
	mover.hold_position(_hold_at, HOLD_TOLERANCE, orbit_correct_speed)
	if not _locked and _phase_time >= windup_seconds - 0.0001:
		_lock(target)
		_set_light(StateLight.State.COMMIT)
	if _locked:
		mover.face_toward(_locked_point)
	elif target.has_target:
		mover.face_toward(target.position)
	if _phase_time >= windup_seconds + commit_flash_seconds - 0.0001:
		enter_phase(Phase.DASH)


func _lock(target: TargetInfo) -> void:
	_locked = true
	if target.has_target:
		_locked_point = target.predicted_position(dash_prediction_time)
	else:
		_locked_point = actor.global_position + _facing() * NO_TARGET_LOCK_DISTANCE


func _enter_dash() -> void:
	if not _locked:
		_lock(TargetInfo.player(get_tree()))  # entered without a WINDUP (the test seam)
	var to_point := _locked_point - actor.global_position
	dash_direction = to_point.normalized() if to_point.length_squared() > 0.000001 else _facing()
	dash_hit = false
	_set_armed(true)
	_set_light(StateLight.State.ARMED)
	var seconds := (to_point.length() + overshoot_px) / dash_speed if dash_speed > 0.0 else 0.0
	mover.boost(dash_direction, dash_speed, minf(seconds, max_dash_seconds))
	_locked = false


func _tick_dash() -> void:
	# Faces along the boost velocity itself (no face_toward: the Phase 1 tail-first fix).
	if not mover.is_boosting():
		enter_phase(Phase.OVERSHOOT)


# ── OVERSHOOT / RETURN ───────────────────────────────────────────────────────────────────────────

func _enter_overshoot() -> void:
	_set_armed(false)
	_set_light(StateLight.State.OFF)
	if not dash_hit and attack != null:
		attack.fire_now()
		pulses_fired += 1


func _tick_overshoot(delta: float, target: TargetInfo) -> void:
	var current := actor.velocity
	if current.length_squared() < 0.000001:
		current = dash_direction
	var toward := (target.position - actor.global_position) if target.has_target else current
	_phase_time += delta
	if absf(current.angle_to(toward)) <= deg_to_rad(OVERSHOOT_EXIT_DEG) \
			or _phase_time > overshoot_max_seconds + 0.0001:
		enter_phase(Phase.RETURN)
		return
	# Rebuilt from the actor's CURRENT velocity every tick, never from the previous request, so the
	# mover's straight-segment `move_toward` bounds the heading change to `overshoot_turn_rate · delta`.
	var dir := Steering.turn_toward(current.normalized(), toward, overshoot_turn_rate, delta)
	mover.request_velocity(dir * overshoot_speed)


func _tick_return(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_phase_time += delta
	var pos := actor.global_position
	var out := pos - orbit_centre
	var ring_point := orbit_centre + (out.normalized() if out.length_squared() > 0.000001 else Vector2.RIGHT) * orbit_radius
	if pos.distance_to(ring_point) <= RETURN_TOLERANCE or _phase_time >= RETURN_MAX_SECONDS:
		_reanchor()
		_new_window()
		enter_phase(Phase.ORBIT)
		return
	mover.arrive(ring_point, approach_speed)
	mover.face_toward(target.position)


# ── DISENGAGE (the Swarm Drone's exit, docs/plans/cmuj4y8rh0070p52xk6vzfvbe) ─────────────────────

func _enter_disengage() -> void:
	_set_armed(false)
	_set_light(StateLight.State.OFF)
	_pending = &""
	mover.release_constraint()
	mover.max_speed = exit_speed
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open).
func _tick_disengage() -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	mover.seek(_exit_point, exit_speed)


# ── Hub idle (t11; epic §2.8.4) ──────────────────────────────────────────────────────────────────

## The meta-state that decides whether the drone is patrolling, noticing or fighting, run once a tick
## alongside (not instead of) the phase dispatch below.
func _tick_anchor_idle(delta: float, target: TargetInfo) -> void:
	var state := anchor_idle.update(delta, actor.global_position, target)
	match state:
		AnchorIdle.State.IDLE:
			if not _in_idle_leg_phase():
				enter_phase(Phase.IDLE_ORBIT)
		AnchorIdle.State.NOTICING:
			if phase != Phase.NOTICING:
				enter_phase(Phase.NOTICING)
		AnchorIdle.State.COMBAT:
			# From NOTICING only, and from the drone's CURRENT velocity — `enter_phase(ENTER)` runs no
			# entry code, so the handover guard rests entirely on the mover's own bounds.
			if phase == Phase.NOTICING:
				enter_phase(Phase.ENTER)
		AnchorIdle.State.RETURNING:
			# Never interrupts a live DASH: a contact-armed pass always finishes.
			if phase != Phase.RETURNING and phase != Phase.DASH:
				enter_phase(Phase.RETURNING)


func _in_idle_leg_phase() -> bool:
	return phase == Phase.IDLE_ORBIT or phase == Phase.IDLE_BRAKE \
			or phase == Phase.IDLE_REVERSE or phase == Phase.IDLE_BOOST


func _in_anchor_idle_phase() -> bool:
	return _in_idle_leg_phase() or phase == Phase.NOTICING or phase == Phase.RETURNING


## Re-anchors where the drone actually is (never a snap to the far side of the ring) and draws a
## fresh radius, tangential speed and leg duration, all ± their jitter, from `rng`.
func _enter_idle_orbit() -> void:
	_idle_angle = (actor.global_position - patrol_anchor).angle()
	_idle_ring_radius = maxf(idle_radius + rng.randf_range(-idle_radius_jitter, idle_radius_jitter), 10.0)
	_idle_speed_mag = maxf(idle_speed + rng.randf_range(-idle_speed_jitter, idle_speed_jitter), 0.0)
	_idle_leg_left = rng.randf_range(IDLE_LEG_MIN, IDLE_LEG_MAX)


func _tick_idle_orbit(delta: float) -> void:
	_idle_leg_left -= delta
	_idle_angle += orbit_dir * _idle_speed_mag * delta
	mover.orbit(patrol_anchor, _idle_ring_radius, _idle_angle, orbit_correct_speed)
	if _idle_leg_left <= 0.0:
		_roll_idle_leg()


## Equally likely IDLE_BRAKE / IDLE_REVERSE / IDLE_BOOST, unless `force_next_idle_leg()` set one.
func _roll_idle_leg() -> void:
	var choice := _forced_idle
	if choice != &"":
		_forced_idle = &""
	else:
		choice = [&"brake", &"reverse", &"boost"][rng.randi_range(0, 2)]
	match choice:
		&"brake": enter_phase(Phase.IDLE_BRAKE)
		&"reverse": enter_phase(Phase.IDLE_REVERSE)
		_: enter_phase(Phase.IDLE_BOOST)


func _tick_idle_brake(delta: float) -> void:
	mover.request_velocity(Vector2.ZERO)
	_phase_time += delta
	if _phase_time >= IDLE_BRAKE_SECONDS - 0.0001:
		enter_phase(Phase.IDLE_ORBIT)


func _enter_idle_reverse() -> void:
	_reverse_from = orbit_dir * _idle_speed_mag


func _tick_idle_reverse(delta: float) -> void:
	_phase_time += delta
	var t := clampf(_phase_time / reverse_seconds, 0.0, 1.0) if reverse_seconds > 0.0 else 1.0
	var w := lerpf(_reverse_from, -_reverse_from, t)
	_idle_angle += w * delta
	mover.orbit(patrol_anchor, _idle_ring_radius, _idle_angle, orbit_correct_speed)
	if t >= 1.0:
		orbit_dir = -orbit_dir
		enter_phase(Phase.IDLE_ORBIT)


## A brief boost at `IDLE_BOOST_MULT` × the leg's tangential speed, along the drone's current
## heading, then a fresh IDLE_ORBIT leg.
func _enter_idle_boost() -> void:
	var v := actor.velocity
	var dir := v.normalized() if v.length_squared() > 0.000001 else _facing()
	var speed := IDLE_BOOST_MULT * maxf(_idle_speed_mag * _idle_ring_radius, 1.0)
	mover.boost(dir, speed, IDLE_BOOST_SECONDS)


func _tick_idle_boost() -> void:
	if not mover.is_boosting():
		enter_phase(Phase.IDLE_ORBIT)


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


func _tick_returning() -> void:
	mover.arrive(patrol_anchor, approach_speed)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## The player's position, kept inside the constraint's `inner_rect()` shrunk by `orbit_radius`, so an
## orbit near a corridor edge does not fight the edge pressure (R2.13). Unbounded (Open Space): as is.
func _centre_of(p: Vector2) -> Vector2:
	if mover == null or mover.constraint == null:
		return p
	var inner := mover.constraint.inner_rect().grow(-orbit_radius)
	if not inner.has_area():
		return p
	return p.clamp(inner.position, inner.end)


## Where the drone comes to rest if it brakes now: the point WINDUP / FEINT_WINDUP hold at.
func _stop_point() -> Vector2:
	var pos := actor.global_position
	var v := actor.velocity
	if braking <= 0.0 or v.length_squared() <= 0.0:
		return pos
	return pos + v.normalized() * (v.length_squared() / (2.0 * braking))


## True when `point` is `side_lane_min_deg`-`side_lane_max_deg` off the vertical axis about
## `target_pos`, with `margin` degrees taken off each end.
func _in_lane(point: Vector2, target_pos: Vector2, margin: float) -> bool:
	var angle := lane_angle_deg(point - target_pos)
	return angle >= side_lane_min_deg + margin and angle <= side_lane_max_deg - margin


## The angle (deg, 0-90) between `rel` and the vertical axis.
static func lane_angle_deg(rel: Vector2) -> float:
	var length := rel.length()
	if length <= 0.000001:
		return 0.0
	return rad_to_deg(acos(clampf(absf(rel.y) / length, 0.0, 1.0)))


func _reanchor() -> void:
	_orbit_angle = (actor.global_position - orbit_centre).angle()


func _new_window() -> void:
	_window_left = rng.randf_range(WINDOW_MIN, WINDOW_MAX)
	_pending = &""


## The unit vector the actor's nose points along, from its rotation and `sprite_forward_angle`.
func _facing() -> Vector2:
	var forward: Variant = actor.get(&"sprite_forward_angle")
	var offset := float(forward) if (forward is float or forward is int) else PI / 2.0
	return Vector2.RIGHT.rotated(actor.rotation + offset)


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
