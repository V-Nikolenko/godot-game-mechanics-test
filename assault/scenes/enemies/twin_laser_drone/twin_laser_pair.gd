## TwinLaserPair - the rig that holds two Twin-Laser Drones and the beam between them (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12;
## task plan docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/3-plan.md; Phase 8 t12). Behaviour: `ENEMY.md` beside this file.
##
## A `RefCounted` board both drones' brains hold (the `SquadController` precedent): it lives while either brain does, and the signal connections it
## makes on the drones do not keep it alive. It computes the pair's shared frame and owns the one rig clock; it never moves anything. Each drone's
## brain applies the current phase's motion through its own `EnemyMover`.
##
## **Frame.** `centre`, `axis` u (unit, A -> B), `normal` n (unit; the line advances along -n). Slot of A = centre - u * L/2, of B = centre + u * L/2.
## FORM updates the frame every leader tick; TELEGRAPH and ADVANCE use it latched (the shown line is the line that advances).
##
## **One clock.** `tick(delta, caller)` returns at once unless `caller == leader()` (drone A while it lives, else B), so phase transitions happen only
## in the leader's tick. TELEGRAPH -> ADVANCE reads the beam's own phase (the beam is the authority on its telegraph).
##
## **Strain and collapse.** In TELEGRAPH and ADVANCE a separation error above `length_tolerance` strains the beam (never lethal, flickering); held for
## `strain_seconds` it collapses (COLLAPSED, then BREAK with both drones alive). A drone that dies, leaves the tree, is released (DISENGAGE) or is
## suspended (a rail) breaks the pair for good in the same call: the beam is cancelled at once, and freed with drone A if A was the one to go.
##
## **One owner.** The beam is a child of drone A, `setup(A, owner_group)`; A's brain feeds it its endpoints and ticks it (`tick_beam`) in every phase,
## so a cancelled beam fades out. Both drones (and a controller, if bound with one) join `owner_group`, so the beam never hurts them.
##
## The file names its own class only in `bind()`, a static factory on a RefCounted (the `TargetInfo` precedent); `scripts/check-test-leaks.sh`
## proves it does not leak. It never names the drone or brain classes: a drone's brain is reached as its `Brain` child, duck-typed.
class_name TwinLaserPair
extends RefCounted

## Append-only. §2.12's five, plus WAIT (Open Space's pause between attacks: both drones re-FORM on the same tick, so it is a rig phase).
enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT }

signal phase_changed(new_phase: int)
## Emitted once per collapse: [param intact] true for a strain collapse with both drones alive (they BREAK and re-FORM), false when the pair broke
## for good (a drone died, left, was released or suspended).
signal collapsed(intact: bool)

## The FORM frame's normal turns toward the player's bearing at most this fast (rad/s; §2.12 "a turn of at most 90°/s").
const FRAME_TURN_RATE := PI / 2.0
## Slack on summed tick deltas (as `EnemyBeam`).
const EPS := 1e-6

var drone_a: Node2D
var drone_b: Node2D
## The ship that launched the pair (the Laser Tender, t13), or null.
var controller: Node2D
## `&"twin_pair_<rig instance id>"`: both drones and the controller are in it; the beam exempts it.
var owner_group: StringName = &""
## The pair's beam, a child of drone A; null once freed with A.
var beam: EnemyBeam
## Drone A's private config: one config tunes the whole pair.
var config: TwinLaserDroneConfig
var phase: int = Phase.FORM

var centre: Vector2 = Vector2.ZERO
## u: unit, from A's slot toward B's.
var axis: Vector2 = Vector2.RIGHT
## n: unit, from the player toward the line; the advance direction is -n.
var normal: Vector2 = Vector2.UP
var has_frame: bool = false
## Assault: the frame's shape (a vertical rig beside the player) and which side it is on (+1 right, -1 left).
var vertical: bool = false
var assault_side: float = 1.0
## The length of this attack's advance (px) and the advance time left (s).
var advance_distance: float = 0.0
var advance_left: float = 0.0
## The player's position at the latch: the point the line advances through.
var latched_player: Vector2 = Vector2.ZERO
## The player's velocity in the leader's last tick (the FORM feed-forward).
var player_velocity: Vector2 = Vector2.ZERO
var advances_started: int = 0
var collapses: int = 0
var strained: bool = false
var strain_time: float = 0.0
## WAIT's length, drawn from the leader's brain rng on entry.
var wait_seconds: float = 0.0

var _phase_time: float = 0.0
var _axis_sign: float = 1.0
var _broken: bool = false
## Instance ids of drones that died, left the tree or were released: the rig's own "gone" flag. `died` is emitted before `queue_free()`, so inside
## the death hook "queued for deletion" is not yet true; `_live()` reads this first.
var _gone: Dictionary = {}
## Set on every FORM entry: the next Open Space frame takes the player's bearing outright (after an advance the old normal points the wrong way).
var _fresh_frame: bool = true
var _last_a: Vector2 = Vector2.ZERO
var _last_b: Vector2 = Vector2.ZERO


## Binds [param a] and [param b] (and [param p_controller], if any) into a new rig: the owner group, the beam on A, each brain's `pair`, the death
## hooks. Works on drones in or out of the tree.
static func bind(a: Node2D, b: Node2D, p_controller: Node2D = null) -> TwinLaserPair:
	var rig := TwinLaserPair.new()
	rig._setup(a, b, p_controller)
	return rig


func _setup(a: Node2D, b: Node2D, p_controller: Node2D) -> void:
	drone_a = a
	drone_b = b
	controller = p_controller
	owner_group = StringName("twin_pair_%d" % get_instance_id())
	var cfg: Variant = a.get(&"config")
	config = cfg if cfg is TwinLaserDroneConfig else TwinLaserDroneConfig.new()
	for member: Node in [a, b, p_controller]:
		if member != null:
			member.add_to_group(owner_group)
	var scene := EnemyBeamScenes.scene_for(EnemyBeam.Kind.TWIN)
	beam = scene.instantiate() as EnemyBeam
	beam.name = "TwinBeam"
	a.add_child(beam)
	beam.setup(a, owner_group)
	_last_a = a.global_position if a.is_inside_tree() else a.position
	_last_b = b.global_position if b.is_inside_tree() else b.position
	beam.set_endpoints(_last_a, _last_b)
	for drone: Node2D in [a, b]:
		var brain := drone.get_node_or_null("Brain")
		if brain != null:
			brain.set(&"pair", self)
		if drone.has_signal(&"died"):
			drone.connect(&"died", _on_drone_gone.bind(drone), CONNECT_ONE_SHOT)
		drone.tree_exiting.connect(_on_drone_gone.bind(drone), CONNECT_ONE_SHOT)


# ── Queries ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Drone A while it is live, else drone B.
func leader() -> Node2D:
	if _live(drone_a):
		return drone_a
	return drone_b if _live(drone_b) else null


## Both drones live, neither suspended by a rail, and the pair not broken.
func is_intact() -> bool:
	if _broken or not _live(drone_a) or not _live(drone_b):
		return false
	return not _suspended(drone_a) and not _suspended(drone_b)


## True once the pair has broken for good.
func is_broken() -> bool:
	return _broken


## TELEGRAPH or ADVANCE: the shown line is the line that fires, so nothing interrupts it.
func is_committed() -> bool:
	return phase == Phase.TELEGRAPH or phase == Phase.ADVANCE


func partner_of(d: Object) -> Node2D:
	var other: Variant = drone_b if d == drone_a else drone_a
	return other if _live(other) else null


## -1 for drone A, +1 for drone B.
func side_of(d: Object) -> float:
	return -1.0 if d == drone_a else 1.0


## [param d]'s slot on the current frame; its own position before the first frame.
func slot_of(d: Node2D) -> Vector2:
	if not has_frame:
		return d.global_position
	return centre + axis * side_of(d) * config.rig_length * 0.5


## | |A - B| - L |, INF unless both drones are valid.
func separation_error() -> float:
	if not is_instance_valid(drone_a) or not is_instance_valid(drone_b):
		return INF
	return absf(drone_a.global_position.distance_to(drone_b.global_position) - config.rig_length)


func advance_dir() -> Vector2:
	return -normal


## Seconds in the current rig phase (leader time).
func phase_time() -> float:
	return _phase_time


# ── The rig clock (leader only) ──────────────────────────────────────────────────────────────────────────────────────

## One rig tick. A no-op unless [param caller] is the leader.
func tick(delta: float, caller: Node2D) -> void:
	if caller != leader() or caller == null:
		return
	var target := TargetInfo.player(caller.get_tree())
	player_velocity = target.velocity if target.has_target else Vector2.ZERO
	if _broken:
		return
	if not is_intact():
		_break_for_good()
		return
	_phase_time += delta
	match phase:
		Phase.FORM:
			_tick_form(delta, target, caller)
		Phase.TELEGRAPH:
			if not _strain(delta) and is_instance_valid(beam) and beam.phase() == EnemyBeam.Phase.ACTIVE:
				advance_left = advance_distance / config.advance_speed if config.advance_speed > 0.0 else 0.0
				advances_started += 1
				_enter(Phase.ADVANCE)
		Phase.ADVANCE:
			if not _strain(delta):
				advance_left -= delta
				if advance_left <= EPS:
					advance_left = 0.0
					_enter(Phase.BREAK)
		Phase.BREAK:
			if _phase_time + EPS >= config.break_seconds:
				_enter(Phase.FORM if _corridor_rect(caller).has_area() else Phase.WAIT)
		Phase.WAIT:
			if _phase_time + EPS >= wait_seconds:
				_enter(Phase.FORM)
		Phase.COLLAPSED:
			_enter(Phase.BREAK)  # a strain collapse: the survivors break and re-form


## Drone A's beam step: its endpoints (B's last position once B is gone), its strain, its clock. Called by A's brain at the end of every tick, in
## every phase, so a cancelled beam always fades out. A no-op for any other caller or once the beam is gone.
func tick_beam(delta: float, caller: Node2D) -> void:
	if caller != drone_a or not is_instance_valid(beam):
		return
	if _present(drone_a):
		_last_a = drone_a.global_position
	if _present(drone_b):
		_last_b = drone_b.global_position
	beam.set_endpoints(_last_a, _last_b)
	beam.set_strained(strained)
	beam.tick(delta)


## [param d] leaves the rig for good (DISENGAGE, a rail): the pair breaks. A suspended drone A frees the beam (nobody would tick its fade).
func release(d: Object) -> void:
	if not is_instance_valid(d):
		return
	_gone[d.get_instance_id()] = true
	if not _broken:
		_break_for_good()
	if d == drone_a and _suspended(d) and is_instance_valid(beam):
		beam.queue_free()
		beam = null


func _tick_form(delta: float, target: TargetInfo, caller: Node2D) -> void:
	if not target.has_target:
		return
	var rect := _corridor_rect(caller)
	if rect.has_area():
		if not _assault_frame(target.position, rect):
			_enter(Phase.BREAK)
			return
	else:
		_open_space_frame(target.position, delta)
	var tol := config.slot_tolerance
	if drone_a.global_position.distance_to(slot_of(drone_a)) <= tol and drone_b.global_position.distance_to(slot_of(drone_b)) <= tol \
			and separation_error() <= config.length_tolerance:
		latched_player = target.position
		_enter(Phase.TELEGRAPH)
	elif _phase_time + EPS >= config.form_timeout:
		_enter(Phase.BREAK)


## Open Space: the line stands `standoff` from the player on the drones' side. The first frame of every FORM takes their bearing outright (after an
## advance they are past the player, so the old normal points the wrong way); later frames turn toward it at `FRAME_TURN_RATE`.
func _open_space_frame(p: Vector2, delta: float) -> void:
	var mid := (drone_a.global_position + drone_b.global_position) * 0.5
	var to_mid := mid - p
	var n_target := to_mid.normalized() if to_mid.length_squared() > EPS else normal
	var fresh := _fresh_frame or not has_frame
	_fresh_frame = false
	if fresh:
		normal = n_target  # the first frame of every FORM takes the bearing outright; the u sign is re-derived from the drones
	else:
		var cap := FRAME_TURN_RATE * delta
		normal = normal.rotated(clampf(normal.angle_to(n_target), -cap, cap)).normalized()
	centre = p + normal * config.standoff
	_set_axis(fresh)
	advance_distance = config.standoff + config.overshoot
	has_frame = true


## Assault: the planner's frame inside the corridor (`assault_frame`). False when nothing fits.
func _assault_frame(p: Vector2, rect: Rect2) -> bool:
	var inset := rect.grow(-config.slot_tolerance)
	var f := assault_frame(p, inset, config.rig_length, config.standoff, config.overshoot, vertical if has_frame else false,
			assault_side if has_frame else 0.0, config.slot_tolerance)
	if f.is_empty():
		return false
	centre = f["centre"]
	normal = f["normal"]
	vertical = f["vertical"]
	assault_side = f["side"]
	advance_distance = f["advance"]
	_set_axis(not has_frame)
	has_frame = true
	return true


## u = ±n.orthogonal(), signed so A is on the -u side; the sign is kept from the previous frame unless the drones are clearly crossed (hysteresis:
## two drones nearly in line along n never swap slots back and forth).
func _set_axis(first: bool) -> void:
	var ortho := normal.orthogonal()
	var ab := drone_b.global_position - drone_a.global_position
	var across := ab.dot(ortho)
	var sign_now := 1.0 if across >= 0.0 else -1.0
	if first:
		_axis_sign = sign_now
	elif ab.dot(ortho * _axis_sign) < 0.0 and absf(across) > config.slot_tolerance:
		_axis_sign = sign_now
	axis = ortho * _axis_sign


## Strain bookkeeping for TELEGRAPH / ADVANCE; true when it collapsed the beam this tick.
func _strain(delta: float) -> bool:
	if separation_error() > config.length_tolerance:
		if not strained:
			strained = true
			strain_time = 0.0
		else:
			strain_time += delta
		if strain_time + EPS >= config.strain_seconds:
			collapses += 1
			_enter(Phase.COLLAPSED)
			collapsed.emit(true)
			return true
	else:
		strained = false
		strain_time = 0.0
	return false


func _enter(next: int) -> void:
	phase = next
	_phase_time = 0.0
	if next != Phase.TELEGRAPH and next != Phase.ADVANCE:
		strained = false
		strain_time = 0.0
	match next:
		Phase.TELEGRAPH:
			if is_instance_valid(beam):
				beam.start()
		Phase.BREAK, Phase.COLLAPSED:
			if is_instance_valid(beam):
				beam.cancel()
		Phase.WAIT:
			var lo := config.attack_period_min
			var hi := maxf(config.attack_period_max, lo)
			var brain := leader().get_node_or_null("Brain") if leader() != null else null
			var rng: Variant = brain.get(&"rng") if brain != null else null
			wait_seconds = (rng as RandomNumberGenerator).randf_range(lo, hi) if rng is RandomNumberGenerator else lo
		Phase.FORM:
			_fresh_frame = true
	phase_changed.emit(next)


## The pair is over: COLLAPSED for good, the beam cancelled in the same call (A's death frees it with A; B's leaves A to fade it).
func _break_for_good() -> void:
	if _broken:
		return
	_broken = true
	phase = Phase.COLLAPSED
	_phase_time = 0.0
	strained = false
	strain_time = 0.0
	if is_instance_valid(beam):
		beam.set_strained(false)
		beam.cancel()
	phase_changed.emit(phase)
	collapsed.emit(false)


func _on_drone_gone(d: Object) -> void:
	if is_instance_valid(d):
		_gone[d.get_instance_id()] = true
		if d == drone_a:
			_last_a = d.global_position
		elif d == drone_b:
			_last_b = d.global_position
	if not _broken:
		_break_for_good()


## Valid, not queued for deletion, not gone (dead, out of the tree or released).
func _live(d: Variant) -> bool:
	return is_instance_valid(d) and not (d as Node).is_queued_for_deletion() and not _gone.has((d as Object).get_instance_id())


## Valid and not queued for deletion (a released drone is still present: the beam's end follows it while it fades).
func _present(d: Variant) -> bool:
	return is_instance_valid(d) and not (d as Node).is_queued_for_deletion()


func _suspended(d: Object) -> bool:
	return d.has_method(&"is_ai_suspended") and bool(d.call(&"is_ai_suspended"))


## The leader's corridor rect: its mover's constraint `inner_rect()` while one is held; an empty rect in Open Space.
func _corridor_rect(caller: Node2D) -> Rect2:
	var mover := caller.get_node_or_null("EnemyMover") as EnemyMover
	if mover == null or mover.constraint == null or mover.constraint_released():
		return Rect2()
	return mover.constraint.inner_rect()


# ── The Assault frame planner (pure) ─────────────────────────────────────────────────────────────────────────────────

## Plans an Assault frame for a player at [param p] inside [param rect] (the corridor's `inner_rect()` already inset by `slot_tolerance`, so a drone
## within that of its slot is inside `inner_rect()` and the corridor constraint is the identity on both ends). Returns `{centre, normal, vertical,
## side, advance}`, or `{}` when nothing fits.
##
## Horizontal (preferred): the line `standoff` above the player, advancing down (n = UP), its centre clamped along x so the whole line is inside;
## it needs `standoff` of room above the player (`standoff + hysteresis` when the previous frame was vertical). Otherwise vertical: beside the
## player on the side with more room (the previous side kept unless the other has more by over `hysteresis`), advancing across, centre clamped
## along y. The overshoot is clamped to the room past the player. Neither fits, or the rect is shorter than `length` along the line: `{}`.
static func assault_frame(p: Vector2, rect: Rect2, length: float, standoff: float, overshoot: float, prev_vertical: bool,
		prev_side: float, hysteresis: float) -> Dictionary:
	var half := length * 0.5
	var above := p.y - rect.position.y
	var need_above := standoff + (hysteresis if prev_vertical else 0.0)
	if rect.size.x >= length and above >= need_above:
		return {
			"centre": Vector2(clampf(p.x, rect.position.x + half, rect.end.x - half), p.y - standoff),
			"normal": Vector2.UP,
			"vertical": false,
			"side": 0.0,
			"advance": standoff + clampf(rect.end.y - p.y, 0.0, overshoot),
		}
	if rect.size.y < length:
		return {}
	var left := p.x - rect.position.x
	var right := rect.end.x - p.x
	var side := 1.0 if right >= left else -1.0
	if prev_side != 0.0:
		side = prev_side
		var mine := right if prev_side > 0.0 else left
		var other := left if prev_side > 0.0 else right
		if other > mine + hysteresis:
			side = -prev_side
	var room := right if side > 0.0 else left
	if room < standoff:
		return {}
	var beyond := left if side > 0.0 else right
	return {
		"centre": Vector2(p.x + side * standoff, clampf(p.y, rect.position.y + half, rect.end.y - half)),
		"normal": Vector2(side, 0.0),
		"vertical": true,
		"side": side,
		"advance": standoff + clampf(beyond, 0.0, overshoot),
	}
