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
##   IDLE       [IDLE]       t14 (§2.14), Open Space only: the rig is IDLE; both drones circle `idle_anchor` at `idle_radius`, opposite each other,
##                           the beam OFF (`mover.orbit` to its own moving ring point).
##   NOTICING   [NOTICING]   the leader's `AnchorIdle` saw the player: both drones stop, face it and blink their lens once; after `notice_time` FORM.
##   RETURNING  [RETURNING]  the player passed `lose_radius`: the rig stood down (once any attack and its BREAK ended) and the drones fly back to their
##                           ring points. A launched pair (with a controller) is RETURNING while its tender recalls it: it flies to the tender, which
##                           docks it.
##
## **The hub idle (t14).** A standalone Open Space pair that is not `start_engaged` builds an `AnchorIdle` (config group "Idle") in each brain, but
## only the **leader of an intact, uncontrolled pair** updates it, once per tick before the rig's tick (the rig's single clock): IDLE / RETURNING
## stand the rig down (`TwinLaserPair.stand_down()`; never a busy phase), NOTICING is mirrored while the rig is IDLE, COMBAT engages it. The leader of
## a launched pair instead reads its controller's duck-typed `recalls_drones()` (never naming the tender's class): true stands the rig down at the
## controller, false (or a dead controller) engages it again. A lone drone in Open Space with no live controller circles its own anchor.
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
## True skips the hub idle (no `AnchorIdle`): the pair fights at once (behaviour rows; the Ph7 convention).
var start_engaged: bool = false
## The hub pair's patrol point (`TwinLaserPairSpawn` sets both drones' to its own position), where a lone drone circles in Open Space. `Vector2.INF`
## (unset) defaults to the spawn position on the first tick.
var patrol_anchor: Vector2 = Vector2.INF
## The hub idle's notice / lose handover (§2.14); null in Assault, when `start_engaged`, and for a launched drone. Only the leader's is updated.
var anchor_idle: AnchorIdle

var _started: bool = false
var _phase_time: float = 0.0
var _exit_dir: Vector2 = Vector2.DOWN
var _hold_point: Vector2 = Vector2.ZERO
var _light_state: int = -1
## SOLO in Open Space with no live controller: the angle of its point on its own idle ring.
var _solo_angle: float = 0.0


func tick(delta: float) -> void:
	if not _started:
		_setup()
	_phase_time += delta
	var expired := budget.update(delta)
	if phase != Phase.DISENGAGE:
		if pair != null:
			if pair.is_intact() and pair.leader() == actor:
				# A hub pair (an `AnchorIdle`, built only without a controller) runs the idle; any other pair asks its controller. A freed
				# controller compares `== null`, so the branch is keyed on the `AnchorIdle`, never on `controller`.
				if anchor_idle != null:
					_tick_anchor_idle(delta)
				else:
					_tick_recall()
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
		Phase.SOLO:
			if patrol_anchor.is_finite():
				_solo_angle = (actor.global_position - patrol_anchor).angle()
	_update_light()
	if p == Phase.NOTICING:
		var light := actor.get_node_or_null("StateLight") as StateLight
		if light != null:
			light.blink_once()
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
	if not budget.active and not start_engaged and (pair == null or pair.controller == null):
		# `home_radius` is the ring plus `slot_tolerance`: the leader returns to a point on the ring, not to the anchor.
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time,
				config.idle_radius + config.slot_tolerance)


## The leader of an intact, uncontrolled pair (§2.14), once a tick before the rig's tick. A busy rig (an attack shown, its BREAK) is never stood
## down; a rig still fighting when the player comes back keeps fighting.
func _tick_anchor_idle(delta: float) -> void:
	var state := anchor_idle.update(delta, actor.global_position, TargetInfo.player(get_tree()))
	match state:
		AnchorIdle.State.IDLE, AnchorIdle.State.RETURNING:
			pair.idle_state = state
			if pair.phase != TwinLaserPair.Phase.IDLE and not pair.is_busy():
				pair.stand_down(patrol_anchor)
		AnchorIdle.State.NOTICING:
			if pair.phase == TwinLaserPair.Phase.IDLE:
				pair.idle_state = state
		AnchorIdle.State.COMBAT:
			if pair.phase == TwinLaserPair.Phase.IDLE:
				pair.engage()


## The leader of an intact, launched pair: its controller recalls it (duck-typed `recalls_drones()`, the `is_armored()` precedent) -> stand down at
## the controller (the brains mirror RETURNING and fly to it; it docks them). Not recalled, or the controller gone -> fight again.
func _tick_recall() -> void:
	var recalled := _controller_live() and pair.controller.has_method(&"recalls_drones") and bool(pair.controller.call(&"recalls_drones"))
	if recalled:
		if pair.phase != TwinLaserPair.Phase.IDLE and not pair.is_busy():
			pair.stand_down(pair.controller.global_position)
	elif pair.phase == TwinLaserPair.Phase.IDLE:
		pair.engage()


## The pair's controller (the tender) is valid and not queued for deletion.
func _controller_live() -> bool:
	return pair != null and pair.controller != null and is_instance_valid(pair.controller) and not pair.controller.is_queued_for_deletion()


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
		TwinLaserPair.Phase.IDLE:
			if anchor_idle == null:
				return Phase.RETURNING  # a launched pair, recalled to its tender (only a hub pair builds an `AnchorIdle`)
			match pair.idle_state:
				AnchorIdle.State.NOTICING:
					return Phase.NOTICING
				AnchorIdle.State.RETURNING:
					return Phase.RETURNING
			return Phase.IDLE
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
			if _controller_live():
				mover.arrive(pair.controller.global_position, config.max_speed)  # home to dock
			else:
				# Nowhere to dock: it circles its own anchor alone (from far away the ring point lies on the line to the anchor).
				_solo_angle += config.idle_speed * delta
				mover.orbit(patrol_anchor, config.idle_radius, _solo_angle, config.max_speed)
		Phase.IDLE:
			mover.orbit(pair.idle_anchor, config.idle_radius, pair.idle_slot_angle(actor), config.max_speed)
		Phase.RETURNING:
			if anchor_idle != null:
				mover.orbit(pair.idle_anchor, config.idle_radius, pair.idle_slot_angle(actor), config.max_speed)
			elif _controller_live():
				mover.arrive(pair.controller.global_position, config.max_speed)
			else:
				mover.request_velocity(Vector2.ZERO)  # its tender is gone: the leader engages again this tick
		Phase.NOTICING:
			mover.request_velocity(Vector2.ZERO)
			var target := TargetInfo.player(get_tree())
			if target.has_target:
				mover.face_toward(target.position)


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
