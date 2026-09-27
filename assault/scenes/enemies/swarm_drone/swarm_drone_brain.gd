## The Swarm Drone's brain — the solo ram cycle (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md
## §2.7.1; task plan docs/plans/cmuj4y8rh0070p52xk6vzfvbe/3-plan.md).
##
## A drone with no squad (`actor.squad == null`) is a squad of one and its own LEAD. With a squad it
## still behaves as a LEAD here — roles, FORM and the flank pincer are t8c's — but it already makes
## the board calls t8c builds on: `update_target()` every tick, `claim_side()` on WINDUP entry,
## `release_side()` on OVERSHOOT entry, `release_lead()` at REJOIN (only with a mate to hand it to),
## and `leave()` on DISENGAGE or rail suspension.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH  [APPROACH]  corkscrew toward the player, phase drawn from `rng` (R2.3).
##   CLOSE_IN  [POSITION]  spiral in on a shrinking ring to CLOSE_IN_RADIUS.
##   WINDUP    [ATTACK]    hold at the stopping point, face the clamped 0.4-0.8 s prediction; yellow.
##   BURST     [ATTACK]    `mover.boost()` at the aim locked on WINDUP's last tick; red, contact armed.
##   OVERSHOOT [REPOSITION] a missed burst curves back toward the player — `Steering.turn_toward()`
##                          from the actor's CURRENT velocity every tick (D7), never a zero request.
##   REJOIN    one tick: hand the lead on, reset the passes, back to CLOSE_IN / APPROACH.
##   DISENGAGE [DISENGAGE] Assault only (`EngagementBudget`): release the corridor, seek the nearest
##                          edge of the projectile world rect, free once strictly outside it.
##
## Tunables are exported here and overwritten from `SwarmDroneConfig` by `swarm_drone.gd`'s
## `_ready()`, which runs AFTER this node's `_ready()` (children first). So nothing that depends on
## a tunable is derived in `_ready()`: the budget and `passes_left` are built on the first tick.
##
## Requests only (single-writer gate): the one field writes on the mover are `max_speed` and
## `release_constraint()` on DISENGAGE.
class_name SwarmDroneBrain
extends EnemyBrain

enum Phase { APPROACH, CLOSE_IN, WINDUP, BURST, OVERSHOOT, REJOIN, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## APPROACH hands over to CLOSE_IN inside this distance (px). t8c repoints it at
## `rear_orbit_radius + 100`.
const APPROACH_EXIT_RADIUS := 360.0
## CLOSE_IN falls back to APPROACH beyond this distance (px).
const APPROACH_REENTER_RADIUS := 460.0
## The ring CLOSE_IN spirals down to before winding up (px). t8c: `flank_distance`.
const CLOSE_IN_RADIUS := 200.0
## How fast CLOSE_IN's ring shrinks (px/s).
const CLOSE_IN_SHRINK_SPEED := 120.0
## CLOSE_IN's tangential anchor speed (px/s) — below `max_speed`, so the anchor stays catchable.
const CLOSE_IN_TANGENT_SPEED := 130.0
## CLOSE_IN is "on the ring" within this distance of CLOSE_IN_RADIUS (px).
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

var phase: Phase = Phase.APPROACH
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


func _ready() -> void:
	super._ready()
	cork_phase = rng.randf_range(0.0, TAU)
	_spin = 1.0 if rng.randf() < 0.5 else -1.0


func tick(delta: float) -> void:
	if not _started:
		_start()
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		_last_target_pos = target.position
		var squad := _squad()
		if squad != null:
			squad.update_target(target.position, _heading_of(target))

	if budget.update(delta) and phase != Phase.DISENGAGE and phase != Phase.BURST:
		enter_phase(Phase.DISENGAGE)

	# A transition hands over to the new phase's handler in the same tick, so a tick never goes
	# without a request. Bounded: no chain is longer than REJOIN -> CLOSE_IN -> WINDUP.
	for _i in 3:
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


func _tick_phase(delta: float, target: TargetInfo) -> void:
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.CLOSE_IN: _tick_close_in(delta, target)
		Phase.WINDUP: _tick_windup(delta, target)
		Phase.BURST: _tick_burst()
		Phase.OVERSHOOT: _tick_overshoot(delta, target)
		Phase.REJOIN: _tick_rejoin(target)
		Phase.DISENGAGE: _tick_disengage()


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_hold_here()
		return
	var pos := actor.global_position
	if pos.distance_to(target.position) <= APPROACH_EXIT_RADIUS:
		enter_phase(Phase.CLOSE_IN)
		return
	mover.request_velocity(Steering.corkscrew(
		pos, target.position - pos, max_speed, corkscrew_amplitude, cork_phase))
	cork_phase = fposmod(cork_phase + TAU * corkscrew_frequency * delta, TAU)


# ── CLOSE_IN ─────────────────────────────────────────────────────────────────────────────────────

func _enter_close_in() -> void:
	var target := TargetInfo.player(get_tree())
	var center := target.position if target.has_target else _last_target_pos
	var offset := actor.global_position - center
	_ring = maxf(offset.length(), CLOSE_IN_RADIUS)
	_ring_angle = offset.angle()


func _tick_close_in(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_hold_here()
		return
	var dist := actor.global_position.distance_to(target.position)
	if dist > APPROACH_REENTER_RADIUS:
		enter_phase(Phase.APPROACH)
		return
	_phase_time += delta
	var settled := is_equal_approx(_ring, CLOSE_IN_RADIUS) and absf(dist - CLOSE_IN_RADIUS) <= CLOSE_IN_TOLERANCE
	if (settled or _phase_time >= CLOSE_IN_MAX_SECONDS) and can_start_attack():
		enter_phase(Phase.WINDUP)
		return
	_ring = move_toward(_ring, CLOSE_IN_RADIUS, CLOSE_IN_SHRINK_SPEED * delta)
	_ring_angle += _spin * CLOSE_IN_TANGENT_SPEED / _ring * delta
	mover.spiral(target.position, _ring, _ring_angle, 0.0, max_speed)


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
	var squad := _squad()
	if squad != null:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			_claimed_side = squad.claim_side(actor, _sector_of(pos, target))
	aim = pos + _facing() * CLOSE_IN_RADIUS


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
		if passes_left > 0 and can_start_attack():
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

func _enter_rejoin() -> void:
	passes_left = second_passes
	var squad := _squad()
	# A sole member keeps its lead: `release_lead()` would leave nobody eligible and pin it to REAR
	# (squad_controller.gd `_reassign(force_rear)`), and every loose level spawn is a squad of one.
	if squad != null and squad.members().size() >= 2:
		squad.release_lead(actor)


func _tick_rejoin(target: TargetInfo) -> void:
	if target.has_target and actor.global_position.distance_to(target.position) > APPROACH_REENTER_RADIUS:
		enter_phase(Phase.APPROACH)
	else:
		enter_phase(Phase.CLOSE_IN)


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


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

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
