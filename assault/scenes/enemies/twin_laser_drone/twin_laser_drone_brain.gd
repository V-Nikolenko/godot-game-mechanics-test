## The Twin-Laser Drone's brain (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12; task plan docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/3-plan.md;
## Phase 8 t12).
##
## Phases (IDEAS §4 vocabulary in brackets). The enum is declared in full and append-only; t12 plays the first seven:
##   FORM       [POSITION]   fly to this drone's slot on the pair's frame (`arrive` + the player's velocity as feed-forward), facing the partner.
##   TELEGRAPH  [ATTACK]     hold the slot on the latched frame while the beam warns. Refuses a tow.
##   ADVANCE    [ATTACK]     committed: `mover.boost(-n, advance_speed, ...)` every tick, identical on both drones, the beam lit. Refuses a tow.
##   BREAK      [REPOSITION] separate along the axis (A along -u, B along +u) at `break_speed`.
##   WAIT       [REPOSITION] Open Space: hold where BREAK left it until the rig's next FORM.
##   SOLO       [PANIC]      no partner: it cannot attack. Open Space: back to the controller (t13 docks it) or `patrol_anchor` (t14 idles there).
##   DISENGAGE  [DISENGAGE]  Assault: the one attack of this life is over, the budget ran out, or the partner is gone. Release the corridor and
##                           leave along -n (no frame: the heading) at `exit_speed`; free once outside the projectile world rect.
##   LAUNCHED   [POSITION]   t13 (Attack B): a straight boost from the Laser Tender's cradle to this drone's launch point (the V), then FORM on
##                           the fixed launched frame (no player feed-forward). Refuses a tow.
##   IDLE, NOTICING, RETURNING: declared for t14 (the hub idle); they hold still until then.
##
## The rig (`TwinLaserPair`) owns the phase clock: the leader's tick advances it and each brain mirrors the rig phase (COLLAPSED with both drones
## alive mirrors as BREAK). **Assault: one attack per life.** Once an ADVANCE has started, or the `EngagementBudget` runs out, the drone disengages,
## but never in TELEGRAPH or ADVANCE: a budget that expires there lets the attack finish (the shown line is the line that fires).
##
## Requests only (single-writer gate): the writes on the mover are `request_velocity` (and its wrappers), `add_nudge`, `face_toward`, `boost`,
## `max_speed` and `release_constraint()` on DISENGAGE. The ADVANCE boost is renewed every tick for one step (`boost(dir, speed, delta)`), so a phase
## change (a kill, a collapse, the advance's end) stops it on the very next step; the rig's `advance_left` is the one clock.
class_name TwinLaserDroneBrain
extends EnemyBrain

enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, WAIT, SOLO, DISENGAGE, LAUNCHED, IDLE, NOTICING, RETURNING }

signal phase_changed(new_phase: int)

## Below this speed the heading is the nose's direction, not the velocity's (px/s).
const HEADING_MIN_SPEED := 1.0

var config: TwinLaserDroneConfig = TwinLaserDroneConfig.new()
## The rig this drone is bound into (`TwinLaserPair.bind` sets it); null for a lone drone.
var pair: TwinLaserPair
var phase: Phase = Phase.FORM
var budget: EngagementBudget
## Test seam (t14 gives it its meaning: a hub spawn idles unless engaged). Nothing idles yet, so it changes nothing in t12.
var start_engaged: bool = false
## Where a lone drone returns to in Open Space. `Vector2.INF` (unset) defaults to the spawn position on the first tick.
var patrol_anchor: Vector2 = Vector2.INF

var _started: bool = false
var _phase_time: float = 0.0
var _exit_dir: Vector2 = Vector2.DOWN
var _hold_point: Vector2 = Vector2.ZERO
var _light_state: int = -1


func tick(delta: float) -> void:
	if not _started:
		_setup()
	_phase_time += delta
	var expired := budget.update(delta)
	if phase != Phase.DISENGAGE:
		if pair != null:
			pair.tick(delta, actor)
		_decide(expired)
	if phase == Phase.DISENGAGE:
		_tick_disengage()
	else:
		_move(delta)
	if pair != null:
		pair.tick_beam(delta, actor)
	_update_light()


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits. Works on a lone drone (no pair).
func enter_phase(p: Phase) -> void:
	if not _started:
		_setup()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.WAIT:
			_hold_point = actor.global_position
		Phase.DISENGAGE:
			_enter_disengage()
	_update_light()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the drone over. It leaves the rig (the pair breaks; drone A's beam is freed).
func on_suspended() -> void:
	if pair != null:
		pair.release(actor)
	_set_light(StateLight.State.OFF)


## A telegraphed or committed phase is never moved by an ally (`BaseEnemy.accept_tow`).
func accepts_tow() -> bool:
	return phase != Phase.TELEGRAPH and phase != Phase.ADVANCE and phase != Phase.LAUNCHED


## Seconds in the current phase.
func phase_time() -> float:
	return _phase_time


# ── Decisions ────────────────────────────────────────────────────────────────────────────────────────────────────────

func _setup() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position


func _is_assault() -> bool:
	return budget.active if budget != null else EnemyWorld.arena(get_tree()) != null


func _decide(expired: bool) -> void:
	if pair == null or not pair.is_intact():
		if _is_assault():
			enter_phase(Phase.DISENGAGE)
		elif phase != Phase.SOLO:
			enter_phase(Phase.SOLO)
		return
	# One attack per Assault life; a budget that runs out mid-attack lets the attack finish.
	if budget.active and not pair.is_committed() and (expired or pair.advances_started > 0):
		enter_phase(Phase.DISENGAGE)
		return
	var want := _mirror(pair.phase)
	if want != phase:
		enter_phase(want)


func _mirror(rig_phase: int) -> Phase:
	match rig_phase:
		TwinLaserPair.Phase.TELEGRAPH:
			return Phase.TELEGRAPH
		TwinLaserPair.Phase.ADVANCE:
			return Phase.ADVANCE
		TwinLaserPair.Phase.BREAK, TwinLaserPair.Phase.COLLAPSED:
			return Phase.BREAK
		TwinLaserPair.Phase.WAIT:
			return Phase.WAIT
		TwinLaserPair.Phase.LAUNCHED:
			return Phase.LAUNCHED
	return Phase.FORM


# ── Motion (requests only) ───────────────────────────────────────────────────────────────────────────────────────────

func _move(delta: float) -> void:
	var partner: Node2D = pair.partner_of(actor) if pair != null else null
	match phase:
		Phase.FORM:
			mover.arrive(pair.slot_of(actor), config.max_speed)
			if not pair.frame_fixed:
				mover.add_nudge(pair.player_velocity)  # a launched frame does not follow the player: no feed-forward
			_face(partner)
		Phase.LAUNCHED:
			_move_launched(delta, partner)
		Phase.TELEGRAPH:
			mover.arrive(pair.slot_of(actor), config.max_speed)
			_face(partner)
		Phase.ADVANCE:
			mover.boost(pair.advance_dir(), config.advance_speed, delta)
			_face(partner)
		Phase.BREAK:
			mover.request_velocity(pair.axis * pair.side_of(actor) * config.break_speed)
			_face(partner)
		Phase.WAIT:
			mover.arrive(_hold_point, config.max_speed)
			_face(partner)
		Phase.SOLO:
			var home := patrol_anchor
			if pair != null and pair.controller != null and is_instance_valid(pair.controller) and not pair.controller.is_queued_for_deletion():
				home = pair.controller.global_position
			mover.arrive(home, config.max_speed)
		_:
			mover.request_velocity(Vector2.ZERO)  # IDLE / NOTICING / RETURNING: t14 gives them motion


## LAUNCHED (§2.13): a straight boost from the cradle along the launch direction at `launch_speed`, one step renewed per tick (the ADVANCE rule),
## slowed on the last step so it lands on its point; facing its flight, so the V reads. The next tick it stops dead (a zero-speed boost: a
## boost keeps its speed, which `arrive` could only brake at `acceleration`, overshooting the slot). After that (the shorter leg waiting for the
## longer one, or a capped leg short of its point) it `arrive`s at its point, facing the partner.
func _move_launched(delta: float, partner: Node2D) -> void:
	var point := pair.launch_point_of(actor)
	var dir := pair.launch_dir_of(actor)
	var secs := pair.launch_seconds_of(actor) - TwinLaserPair.EPS
	var started := pair.phase_time() - delta  # rig time is already advanced by this tick: when this tick began
	if delta > 0.0 and started < secs:
		# A tick that starts before the boost time ends boosts, so the last, partial step lands on the point and a capped leg flies exactly
		# `launch_speed * launch_max_seconds`.
		var s := clampf((point - actor.global_position).dot(dir) / delta, 0.0, pair.launch_speed)
		mover.boost(dir, s, delta)
	elif delta > 0.0 and started - delta < secs:
		mover.boost(dir, 0.0, delta)  # the stop tick
	else:
		mover.arrive(point, config.max_speed)
		_face(partner)


func _face(partner: Node2D) -> void:
	if partner != null and is_instance_valid(partner):
		mover.face_toward(partner.global_position)


func _enter_disengage() -> void:
	_exit_dir = _heading()
	if pair != null:
		if pair.has_frame:
			_exit_dir = pair.advance_dir()  # §2.12: out along -n, the way the line was going
		pair.release(actor)
	mover.release_constraint()
	mover.max_speed = config.exit_speed


## Straight out along the exit direction. Strict `<`/`>` against the rect's edges, as the Bomber's and the Mine Layer's exits.
func _tick_disengage() -> void:
	if EnemyWorld.has_projectile_world_rect(get_tree()):
		var rect := EnemyWorld.projectile_world_rect(get_tree())
		var pos := actor.global_position
		if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
			actor.queue_free()
			return
	mover.request_velocity(_exit_dir * config.exit_speed)


func _heading() -> Vector2:
	var v := mover.own_velocity() if mover != null else Vector2.ZERO
	if v.length() > HEADING_MIN_SPEED:
		return v.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


# ── The lens light ───────────────────────────────────────────────────────────────────────────────────────────────────

## CHARGING while the pair's beam warns, ARMED while it burns, OFF otherwise and always in SOLO / DISENGAGE. Set only on change.
func _update_light() -> void:
	var want: int = StateLight.State.OFF
	if phase != Phase.SOLO and phase != Phase.DISENGAGE and pair != null and is_instance_valid(pair.beam):
		match pair.beam.phase():
			EnemyBeam.Phase.TELEGRAPH:
				want = StateLight.State.CHARGING
			EnemyBeam.Phase.ACTIVE:
				want = StateLight.State.ARMED
	if want != _light_state:
		_set_light(want)


func _set_light(state: int) -> void:
	_light_state = state
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
