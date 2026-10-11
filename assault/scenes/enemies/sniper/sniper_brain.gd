## The Sniper's brain (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5; the cycle's own plan is
## docs/plans/cmuyk2qq0008loa2xqwco8raj/3-plan.md).
##
## A relocation loop: it never fires from where it fired last, never fires through a rock, and never moves
## while it aims. The player's window is the stationary AIM / LOCK pair; the bright LOCK line (COMMIT) is the
## one moment worth dodging.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   ENTER         [APPROACH]    seeks the first firing point (the nearest legal one) at `relocate_speed`.
##                               There is no fly-in timer: its length is `distance / relocate_speed`.
##   BREAK_CONTACT [REPOSITION]  opens the range after a shot (or a refusal) for at least `break_min`, on the side
##                               of the player's line it is already on; ends at `0.9 * range` or `break_cap`.
##   RELOCATE      [POSITION]    arrives at the next firing point, at a new bearing round the player.
##   SETTLE        [POSITION]    brakes to under `settle_epsilon`, then re-checks line of sight.
##   DECOY         [ATTACK]      only with `decoy_telegraph` (default off): after SETTLE, for `decoy_seconds`, a dim
##                               orange line `decoy_offset_min..max` degrees off the player (side drawn per decoy),
##                               CHARGING, never COMMIT, no round; then AIM. Stationary, still facing the player. A
##                               budget expiry here leaves at once: a fake aim is not a shot to finish.
##   AIM           [ATTACK]      stationary: tracks the full-intercept lock point at <= `aim_track_rate`, dim line,
##                               CHARGING, the barrel unfolds.
##   LOCK          [ATTACK]      stationary and frozen: bright line, COMMIT. Line of sight (to the player and along
##                               the locked line) is re-checked on the tick it would fire; blocked -> no round.
##   FIRE          [ATTACK]      one rail round plus its `RailTrail`; entered and left in the same tick.
##   DISENGAGE     [DISENGAGE]   Assault only: the budget ran out. Release the corridor, curve to the nearest
##                               edge of the world rect at `exit_speed`, free once outside it. Expiry in AIM or
##                               LOCK waits for the shot (or the refusal): at most `aim + lock` late.
##
## Firing points (`choose_firing_point()`) are picked in the PLAYER FRAME: bearings are measured from the
## player's smoothed velocity, or its facing while it is slow. See that function for the filters and the
## 45-degree rule.
##
## Rails: `on_suspended()` starts the telegraph's own legacy aim / lock / fire cycle (§2.8). A rail stops this
## brain's ticks, and the cycle never writes the ship's rotation.
##
## Requests only (single-writer gate): the writes on the mover are `max_speed` and `release_constraint()` on
## DISENGAGE. The barrel's `scale` / `position` are a visual pose, not motion; nothing here writes a rotation.
class_name SniperBrain
extends EnemyBrain

enum Phase { ENTER, BREAK_CONTACT, RELOCATE, SETTLE, DECOY, AIM, LOCK, FIRE, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The seven seed bearings round the player frame (deg).
const SEED_BEARINGS: Array[float] = [60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]
## Tier A keeps this margin above `min_bearing_change`, because the shot is fired from where the sniper settles,
## not from the exact point: a point picked at 45.1 degrees could be fired from at 44 (deg).
const BEARING_SLACK := 5.0
## A sniper that has not settled after this long breaks contact instead, so the loop cannot stall (s).
const SETTLE_CAP := 1.5
## Assault BREAK_CONTACT stops moving outward on an axis this far before the corridor's edge (px).
const EDGE_KEEP := 16.0
## The barrel's length while folded, as a share of its unfolded length.
const BARREL_FOLDED := 0.35

## Set by `sniper.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SniperConfig = SniperConfig.new()
## Set by `sniper.gd`: the aim line and rail fallback. Null in a bare brain.
var telegraph: SniperTelegraph
## Set by `sniper.gd`: where the round leaves, the pool it comes from, and the barrel's sprite.
var muzzle: Marker2D
var pool: BulletPool
var barrel: Sprite2D
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.ENTER
## True while the sniper sits on its ENTER / RELOCATE point (latched with hysteresis).
var arrived: bool = false
## The firing point ENTER / RELOCATE is travelling to; `Vector2.INF` when there is none.
var target_point: Vector2 = Vector2.INF

## Shot bookkeeping, read by tests.
var shots_fired: int = 0
## LOS refusals at the end of LOCK, and SETTLE ends that found the line blocked.
var refusals: int = 0
## The player-frame bearing (rad) of the sniper's position on its last shot.
var last_bearing: float = 0.0
var has_last_bearing: bool = false
## AIM's tracked point, and LOCK's frozen point and the muzzle position it was frozen from.
var aim_point: Vector2 = Vector2.ZERO
var lock_point: Vector2 = Vector2.ZERO
var lock_origin: Vector2 = Vector2.ZERO
## The last round fired and its trail (null until the first shot).
var last_round: EnemyBullet
var last_trail: RailTrail
## 0 = folded, 1 = unfolded.
var barrel_open: float = 0.0
## True when the budget expired in AIM or LOCK: DISENGAGE follows the shot (or the refusal).
var disengage_pending: bool = false
## The current decoy's signed bearing offset from the player (rad); 0 until the first decoy.
var decoy_angle: float = 0.0

## `choose_firing_point()`'s last working, for tests: one Dictionary per candidate
## (`point`, `bearing`, `delta`, `tier`, `travel`, `score`, `rect_ok`, `cone_ok`, `path_ok`, `los` - null when no ray was
## spent on it), whether the winner came from the fallback tier, and how many rays it cast.
var last_candidates: Array[Dictionary] = []
var last_choice_fallback: bool = false
var last_los_rays: int = 0

var _started: bool = false
var _phase_time: float = 0.0
var _budget_seen: bool = false
var _exit_point: Vector2 = Vector2.ZERO
var _target: TargetInfo = TargetInfo.new()
## The player's smoothed velocity, and whether it has been seeded.
var _player_vel: Vector2 = Vector2.ZERO
var _player_vel_seeded: bool = false
var _aim_dir: Vector2 = Vector2.ZERO
var _break_side: float = 1.0
## Seconds since BREAK_CONTACT was entered; unlike `_phase_time`, a retry does not reset it.
var _break_time: float = 0.0
## True once a choice from this BREAK_CONTACT found nothing: retries then wait a whole `break_cap`.
var _break_failed: bool = false
## ENTER / RELOCATE re-pick their point after this long (s); see `_set_target_point()`.
var _travel_cap: float = 4.0
var _barrel_ready: bool = false
var _barrel_base_y: float = 0.0
var _barrel_length: float = 0.0


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	_sense(delta)
	if budget.update(delta) and not _budget_seen:
		_budget_seen = true
		_request_disengage()
	match phase:
		Phase.ENTER: _tick_enter()
		Phase.BREAK_CONTACT: _tick_break_contact(delta)
		Phase.RELOCATE: _tick_relocate()
		Phase.SETTLE: _tick_settle()
		Phase.DECOY: _tick_decoy()
		Phase.AIM: _tick_aim(delta)
		Phase.LOCK: _tick_lock()
		Phase.DISENGAGE: _tick_disengage(delta)
		_: pass  # FIRE never lasts past its own tick
	_tick_barrel(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	_set_light(StateLight.State.OFF)
	if telegraph != null:
		telegraph.hide_line()
	match p:
		Phase.BREAK_CONTACT: _enter_break_contact()
		Phase.RELOCATE, Phase.ENTER: arrived = false
		Phase.DECOY: _enter_decoy()
		Phase.AIM: _enter_aim()
		Phase.LOCK: _enter_lock()
		Phase.DISENGAGE: _enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The telegraph's cycle does the shooting.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)
	if telegraph != null:
		telegraph.start_rail_cycle()


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


## The budget ran out: leave now, unless a shot is already being shown (AIM / LOCK), which is finished first.
func _request_disengage() -> void:
	if phase == Phase.DISENGAGE:
		return
	if phase == Phase.AIM or phase == Phase.LOCK:
		disengage_pending = true
		return
	enter_phase(Phase.DISENGAGE)


## Reads the player once per tick and smooths its velocity (time constant `velocity_smoothing`).
func _sense(delta: float) -> void:
	_target = TargetInfo.player(get_tree())
	if not _target.has_target:
		return
	if not _player_vel_seeded:
		_player_vel = _target.velocity
		_player_vel_seeded = true
	elif config.velocity_smoothing > 0.0:
		_player_vel += (_target.velocity - _player_vel) * (1.0 - exp(-delta / config.velocity_smoothing))
	else:
		_player_vel = _target.velocity


## The player frame's forward axis: the smoothed velocity while the player moves at `frame_speed` or more, else
## its facing, else UP.
func player_frame() -> Vector2:
	if _player_vel.length() >= config.frame_speed:
		return _player_vel.normalized()
	if _target.has_target and _target.facing != Vector2.ZERO:
		return _target.facing.normalized()
	return Vector2.UP


## The player-frame bearing of `point` (rad, signed).
func bearing_of(point: Vector2) -> float:
	return player_frame().angle_to(point - _target.position)


# ── ENTER and RELOCATE ───────────────────────────────────────────────────────────────────────────

func _tick_enter() -> void:
	if not _target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	if not target_point.is_finite():
		var point := choose_firing_point()
		_set_target_point(point if point.is_finite() else nearest_firing_point(_target.position))
	_travel(Phase.SETTLE)


func _tick_relocate() -> void:
	if not _target.has_target or not target_point.is_finite():
		mover.request_velocity(Vector2.ZERO)
		return
	_travel(Phase.SETTLE)


## Sets the point ENTER / RELOCATE travels to, and the time after which it is re-picked: the trip's own length at
## `relocate_speed` plus a second, and never under `relocate_cap` - so a long relocation round the player is not
## cut short on every cycle, and a point the player has left behind is still dropped.
func _set_target_point(point: Vector2) -> void:
	target_point = point
	_travel_cap = config.relocate_cap
	if point.is_finite() and config.relocate_speed > 0.0:
		_travel_cap = maxf(config.relocate_cap, actor.global_position.distance_to(point) / config.relocate_speed + 1.0)


## Arrives at `target_point`; on arrival hands over to `next`. Past `_travel_cap` it re-picks the point (the
## player has moved on), keeping the last firing bearing.
func _travel(next: Phase) -> void:
	# Arrival latches with hysteresis: `Steering.arrive` at rest has a zero slowing radius, so re-seeking a point
	# the sniper is already on would chatter at full speed round it.
	var dist := (target_point - actor.global_position).length()
	if dist <= config.arrive_radius:
		arrived = true
	elif dist > config.arrive_radius * 2.0:
		arrived = false
	if arrived:
		mover.request_velocity(Vector2.ZERO)
		mover.face_toward(_target.position)
		enter_phase(next)
		arrived = true
		return
	mover.arrive(target_point, config.relocate_speed)
	if _phase_time >= _travel_cap:
		var again := choose_firing_point()
		if again.is_finite():
			_set_target_point(again)
		_phase_time = 0.0


## The nearest point on the mode's range ring, on this sniper's side; in Assault inside the corridor's
## `inner_rect()` shrunk by `fire_margin`. ENTER's fallback when `choose_firing_point()` finds nothing legal.
func nearest_firing_point(player_pos: Vector2) -> Vector2:
	var away := actor.global_position - player_pos
	if away.length_squared() < 1.0:
		away = Vector2.UP
	var point := player_pos + away.normalized() * _preferred_range()
	if mover.constraint != null:
		var rect := mover.constraint.inner_rect().grow(-config.fire_margin)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			point = Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point


## The mode's firing distance: the tighter Assault value when the corridor (and so the budget) is on.
func _preferred_range() -> float:
	return config.assault_preferred_range if _assault() else config.preferred_range


func _range_jitter() -> float:
	return config.assault_range_jitter if _assault() else config.range_jitter


func _assault() -> bool:
	return budget != null and budget.active


# ── Firing-point selection ───────────────────────────────────────────────────────────────────────

## The next firing point, or `Vector2.INF` when nothing is legal.
##
## 1. Candidates: the seven `SEED_BEARINGS` round the player frame, each jittered by `seed_jitter`, plus
##    `random_candidates` uniform bearings; each at the mode's range plus or minus its jitter.
## 2. Filters, before any scoring: Assault - inside `inner_rect()` shrunk by `fire_margin`; the path - the straight
##    line there never passes closer to the player than `pass_clearance_ratio * range`; the forward cone -
##    not within `forward_cone` of the player frame while the player moves at `forward_cone_speed` or more.
## 3. Tiers, once there is a last firing bearing: A = at least `min_bearing_change + BEARING_SLACK` from it,
##    B = at least `min_bearing_change`, C = the rest (the documented fallback for a cornered player). With no
##    last bearing everything is C and the score is pure travel, so the first point is the nearest legal one.
## 4. Score within a tier: `w_sep * clamp(delta / 180) - w_travel * travel / (2 * range)`.
## 5. Line of sight from the candidate to the player, in rank order, at most `max_los_rays` rays: the first
##    clear one wins.
func choose_firing_point() -> Vector2:
	last_candidates = []
	last_choice_fallback = false
	last_los_rays = 0
	if not _target.has_target:
		return Vector2.INF
	var player_pos := _target.position
	var frame := player_frame()
	var range_ := _preferred_range()
	var jitter := _range_jitter()
	var bearings: Array[float] = []
	for seed_deg in SEED_BEARINGS:
		bearings.append(deg_to_rad(seed_deg + rng.randf_range(-config.seed_jitter, config.seed_jitter)))
	for _i in config.random_candidates:
		bearings.append(rng.randf_range(-PI, PI))

	var has_rect := mover.constraint != null
	var rect := mover.constraint.inner_rect().grow(-config.fire_margin) if has_rect else Rect2()
	var cone_on := _player_vel.length() >= config.forward_cone_speed
	var cone := deg_to_rad(config.forward_cone)
	var tier_a := deg_to_rad(config.min_bearing_change + BEARING_SLACK)
	var tier_b := deg_to_rad(config.min_bearing_change)
	var clearance := config.pass_clearance_ratio * range_
	var survivors: Array[Dictionary] = []
	for b in bearings:
		var bearing := wrapf(b, -PI, PI)
		var point := player_pos + frame.rotated(bearing) * (range_ + rng.randf_range(-jitter, jitter))
		var travel := actor.global_position.distance_to(point)
		var delta := absf(angle_difference(last_bearing, bearing)) if has_last_bearing else 0.0
		var tier := 2
		if has_last_bearing and delta >= tier_a:
			tier = 0
		elif has_last_bearing and delta >= tier_b:
			tier = 1
		var c := {
			"point": point, "bearing": bearing, "delta": delta, "tier": tier, "travel": travel,
			"score": config.w_sep * clampf(delta / PI, 0.0, 1.0) - config.w_travel * travel / (2.0 * range_),
			"rect_ok": not has_rect or rect.has_point(point),
			"cone_ok": not cone_on or absf(bearing) >= cone,
			"path_ok": _path_clears(actor.global_position, point, player_pos, clearance),
			"los": null,
		}
		last_candidates.append(c)
		if c["rect_ok"] and c["cone_ok"] and c["path_ok"]:
			survivors.append(c)
	survivors.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["tier"] != y["tier"]:
			return x["tier"] < y["tier"]
		return x["score"] > y["score"])

	var space := actor.get_world_2d().direct_space_state if actor.is_inside_tree() else null
	var exclude: Array[RID] = [actor.get_rid()]
	for c in survivors:
		if last_los_rays >= config.max_los_rays:
			break
		last_los_rays += 1
		c["los"] = LineOfSight.clear(space, c["point"], player_pos, exclude)
		if c["los"]:
			last_choice_fallback = has_last_bearing and c["tier"] == 2
			if last_choice_fallback and OS.is_stdout_verbose():
				print("SniperBrain: no candidate %.0f deg from the last bearing; fallback to %.0f deg"
					% [config.min_bearing_change, rad_to_deg(c["delta"])])
			return c["point"]
	return Vector2.INF


## True when the straight path `from`→`to` never comes closer to `player_pos` than `clearance`, or than `from`
## already is (a sniper that starts close in may still leave).
static func _path_clears(from: Vector2, to: Vector2, player_pos: Vector2, clearance: float) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(player_pos, from, to)
	return closest.distance_to(player_pos) >= minf(clearance, from.distance_to(player_pos)) - 0.001


# ── SETTLE, AIM, LOCK, FIRE ──────────────────────────────────────────────────────────────────────

func _tick_settle() -> void:
	mover.request_velocity(Vector2.ZERO)
	if _target.has_target:
		mover.face_toward(_target.position)
	if actor.velocity.length() < config.settle_epsilon:
		if _line_clear():
			enter_phase(Phase.DECOY if config.decoy_telegraph else Phase.AIM)
		else:
			refusals += 1
			enter_phase(Phase.BREAK_CONTACT)
	elif _phase_time >= SETTLE_CAP:
		enter_phase(Phase.BREAK_CONTACT)


## Draws the side and size of this decoy's offset. The sign comes first so the draw order is fixed.
func _enter_decoy() -> void:
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	decoy_angle = side * deg_to_rad(rng.randf_range(config.decoy_offset_min, config.decoy_offset_max))
	_set_light(StateLight.State.CHARGING)
	_show_decoy_line()


## The fake line keeps its offset from the player's current bearing (so it cannot drift onto the player), and the
## sniper keeps facing the player. Ends in AIM.
func _tick_decoy() -> void:
	mover.request_velocity(Vector2.ZERO)
	if _target.has_target:
		mover.face_toward(_target.position)
		_show_decoy_line()
	if _phase_time >= config.decoy_seconds:
		enter_phase(Phase.AIM)


func _show_decoy_line() -> void:
	if telegraph == null or not _target.has_target:
		return
	var from := _muzzle_pos()
	telegraph.show_decoy_line(from + (_target.position - from).rotated(decoy_angle))


func _enter_aim() -> void:
	_aim_dir = Vector2.ZERO
	if _target.has_target:
		_aim_dir = (_target.position - _muzzle_pos()).normalized()
		aim_point = _target.position
	_set_light(StateLight.State.CHARGING)


func _tick_aim(delta: float) -> void:
	mover.request_velocity(Vector2.ZERO)
	if _target.has_target:
		var from := _muzzle_pos()
		var want: Vector2 = _target.intercept(from, config.rail_speed)["point"]
		_aim_dir = Steering.turn_toward(_aim_dir, want - from, config.aim_track_rate, delta)
		aim_point = from + _aim_dir * maxf((want - from).length(), 1.0)
	mover.face_toward(aim_point)
	if telegraph != null:
		telegraph.show_line(aim_point, false)
	if _phase_time >= config.aim_seconds:
		enter_phase(Phase.LOCK)


func _enter_lock() -> void:
	lock_point = aim_point
	lock_origin = _muzzle_pos()
	_set_light(StateLight.State.COMMIT)
	if telegraph != null:
		telegraph.show_line(lock_point, true)


func _tick_lock() -> void:
	mover.request_velocity(Vector2.ZERO)
	mover.face_toward(lock_point)
	if telegraph != null:
		telegraph.show_line(lock_point, true)
	if _phase_time < config.lock_seconds:
		return
	if not _line_clear() or not _line_clear_to(lock_point):
		refusals += 1
		_after_shot()
		return
	_fire()


## One rail round along the locked line, and its trail. A null round (an exhausted pool) is a refusal.
func _fire() -> void:
	enter_phase(Phase.FIRE)
	var from := _muzzle_pos()
	var round_ := pool.acquire(from) as EnemyBullet if pool != null else null
	if round_ != null:
		round_.set_direction(lock_point - from)
		round_.speed = config.rail_speed
		var hit_box := round_.get_node_or_null("HitBox") as HitBox
		if hit_box != null:
			hit_box.damage = config.rail_damage
		last_round = round_
		last_trail = RailTrail.spawn(round_, from, config.trail_fade)
		shots_fired += 1
		if _target.has_target:
			last_bearing = bearing_of(actor.global_position)
			has_last_bearing = true
	else:
		refusals += 1
	_after_shot()


## After a shot or a refusal: DISENGAGE if the budget ran out meanwhile, else BREAK_CONTACT.
func _after_shot() -> void:
	if disengage_pending:
		disengage_pending = false
		enter_phase(Phase.DISENGAGE)
	else:
		enter_phase(Phase.BREAK_CONTACT)


## Line of sight from the muzzle to the player, past this sniper's own body.
func _line_clear() -> bool:
	if not _target.has_target or not actor.is_inside_tree():
		return true
	var exclude: Array[RID] = [actor.get_rid()]
	return _target.line_of_sight(_muzzle_pos(), actor.get_world_2d().direct_space_state, exclude)


## Line of sight from the muzzle along the locked shot line. For a moving player the lock point is ahead of
## them, so LOCK checks both lines: it never fires at a player it cannot see, nor into a rock on the way.
func _line_clear_to(point: Vector2) -> bool:
	if not actor.is_inside_tree():
		return true
	var exclude: Array[RID] = [actor.get_rid()]
	return LineOfSight.clear(actor.get_world_2d().direct_space_state, _muzzle_pos(), point, exclude)


func _muzzle_pos() -> Vector2:
	return muzzle.global_position if muzzle != null else actor.global_position


# ── BREAK_CONTACT ────────────────────────────────────────────────────────────────────────────────

## Fixes the lateral side: the side of the player's line (the player frame through the player) the sniper is
## already on, so the break never cuts across the player's nose. On the line itself, the positive side.
func _enter_break_contact() -> void:
	_break_side = 1.0
	_break_time = 0.0
	_break_failed = false
	if not _target.has_target:
		return
	var away := actor.global_position - _target.position
	var frame := player_frame()
	var normal := away - frame * away.dot(frame)
	if away.orthogonal().dot(normal) < 0.0:
		_break_side = -1.0


func _tick_break_contact(delta: float) -> void:
	_break_time += delta
	if not _target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var dist := actor.global_position.distance_to(_target.position)
	var v := Steering.break_contact(actor.global_position, _target.position, _player_vel, _break_side,
		config.break_speed)
	if _break_time >= config.break_min and dist >= _preferred_range() + _range_jitter():
		v = Vector2.ZERO  # past the range band: wait for a point rather than wander off
	elif mover.constraint != null:
		v = _corridor_safe(v)
	mover.request_velocity(v)
	if _break_time < config.break_min:
		return
	if (dist >= _preferred_range() * 0.9 and not _break_failed) or _phase_time >= config.break_cap:
		var point := choose_firing_point()
		if point.is_finite():
			_set_target_point(point)
			enter_phase(Phase.RELOCATE)
		else:
			# Nothing legal: hold, and retry after another `break_cap`. `_break_time` is not reset, so a held
			# sniper does not break again.
			_phase_time = 0.0
			_break_failed = true


## Assault: the corridor pushes an enemy that leaves its visible rect back in, possibly toward the player. So
## an outward request on an axis stops while the sniper could still brake before that edge; if what is left
## points toward the player it is turned round (it slides along the wall the other way); in a corner it stops.
## A turned-round slide may cross the player's line: the corridor wins over the side rule there, because the
## alternative is being pushed back in toward the player.
## The braking distance is taken at `break_speed` (the most the rescaled request can be) and at half the
## mover's rate: `EnemyMover.step` steps the whole velocity vector, so one axis slows by only its share of it.
func _corridor_safe(v: Vector2) -> Vector2:
	var rect := mover.constraint.inner_rect()
	var pos := actor.global_position
	var axis_rate := maxf(mover.acceleration * 0.5, 1.0)
	var blocked_low := [false, false]
	var blocked_high := [false, false]
	for axis in 2:
		var speed := maxf(config.break_speed, absf(actor.velocity[axis]))
		var stop := speed * speed / (2.0 * axis_rate) + EDGE_KEEP
		blocked_low[axis] = pos[axis] - rect.position[axis] <= stop
		blocked_high[axis] = rect.end[axis] - pos[axis] <= stop
	var away := pos - _target.position
	var out := _drop_blocked(v, blocked_low, blocked_high)
	if out.dot(away) < 0.0:
		out = _drop_blocked(-out, blocked_low, blocked_high)
	if out.length_squared() < 0.000001 or out.dot(away) < 0.0:
		return Vector2.ZERO
	return out.normalized() * config.break_speed


static func _drop_blocked(v: Vector2, blocked_low: Array, blocked_high: Array) -> Vector2:
	var out := v
	for axis in 2:
		if (out[axis] < 0.0 and blocked_low[axis]) or (out[axis] > 0.0 and blocked_high[axis]):
			out[axis] = 0.0
	return out


# ── The barrel (a placeholder sprite until the art task) ─────────────────────────────────────────

## Unfolds in AIM / LOCK, folds everywhere else. The base (the end nearest the hull) stays put.
func _tick_barrel(delta: float) -> void:
	if barrel == null:
		return
	if not _barrel_ready:
		_barrel_ready = true
		_barrel_length = barrel.texture.get_height() if barrel.texture != null else 0.0
		_barrel_base_y = barrel.position.y + _barrel_length * 0.5
	var unfolding := phase == Phase.DECOY or phase == Phase.AIM or phase == Phase.LOCK
	if unfolding:
		barrel_open = minf(barrel_open + delta / maxf(config.barrel_unfold_seconds, 0.001), 1.0)
	else:
		barrel_open = maxf(barrel_open - delta / maxf(config.barrel_fold_seconds, 0.001), 0.0)
	var eased := 1.0 - (1.0 - barrel_open) * (1.0 - barrel_open)
	var length_share := lerpf(BARREL_FOLDED, 1.0, eased)
	barrel.scale.y = length_share
	barrel.position.y = _barrel_base_y - _barrel_length * length_share * 0.5


# ── DISENGAGE (the Fighter's exit) ───────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	disengage_pending = false
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The curve's
## rate is capped by what the mover's acceleration can follow at exit speed.
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
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
