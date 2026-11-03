## The Laser Tender's brain (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.13; task plan docs/plans/cmvqw0vnz018nqs2xv56q6a0a/3-plan.md;
## Phase 8 t13). Behaviour: `ENEMY.md` beside the tender.
##
## Phases (IDEAS §4 vocabulary in brackets). The enum is declared in full and append-only; t13 plays the first six:
##   APPROACH   [POSITION]   Open Space: `arrive` at `preferred_range` from the player, facing it; within `range_tolerance` -> HOLD. Assault:
##                           `arrive` at the hold point (the upper band of the visible corridor, above the player); once in the band (its y within
##                           `HOLD_REACH` of the hold point's) and inside the view -> HOLD. The band, not the point: `arrive` trails a hold point
##                           that tracks a strafing player's x and never catches one at 360 px/s.
##   HOLD       [POSITION]   the hold motion (Open Space: a broad arc at `preferred_range`, `arc_rate`; Assault: the hold point), facing the player.
##                           With a docked pair, no live pair, line of sight (on the physics step; assumed off it, the turret's rule) and, in Assault,
##                           no launch yet this life and the tender inside the view -> LAUNCH.
##   LAUNCH     [ATTACK]     the cradle light CHARGING for `launch_telegraph`, then `LaserTender.launch_pair(attack_b_points())`. Refuses a tow.
##   WAIT       [REPOSITION] Open Space: holds while its pair lives; once no live pair -> REARM.
##   REARM      [REPOSITION] cradles empty for `rearm_seconds`, then `LaserTender.rearm_cradles()` -> HOLD (and LAUNCH on the same tick if it can).
##   DISENGAGE  [DISENGAGE]  Assault: after the one launch of this life, or once the budget runs out before LAUNCH. Release the corridor, leave
##                           toward the nearest edge of the projectile world rect at `exit_speed`, free once strictly outside it. A budget that runs
##                           out during LAUNCH lets that launch finish first.
##   IDLE, NOTICING, RETURNING: declared for t14 (the hub idle); they hold still until then.
##
## **At most one live pair:** LAUNCH needs both cradles full and no intact rig of this tender. **Docking** (Open Space, every phase but DISENGAGE): a
## drone this tender launched whose brain is SOLO (its rig broke; it heads for its live controller) within `dock_radius` is taken back
## (`LaserTender.dock()`).
##
## Requests only (single-writer gate): `request_velocity` and its wrappers, `face_toward`, `max_speed` and `release_constraint()` on DISENGAGE.
class_name LaserTenderBrain
extends EnemyBrain

enum Phase { APPROACH, HOLD, LAUNCH, WAIT, REARM, DISENGAGE, IDLE, NOTICING, RETURNING }

signal phase_changed(new_phase: int)
## Once per launch, with the new rig.
signal launched(pair: TwinLaserPair)

## Slack on summed tick deltas (as `EnemyBeam`).
const EPS := 1e-6
## Assault: the tender is "in the band" once its y is within this of the hold point's (px).
const HOLD_REACH := 24.0
## Assault: the hold point stays at least `2 * body radius + HOLD_CLEARANCE` above the player (px), so a player in the top band is not sat on.
const HOLD_CLEARANCE := 40.0
## Below this speed the player is standing (px/s): the wall goes ahead of its nose instead of along its path.
const STANDING_SPEED := 20.0
## Below this speed the heading is the nose's direction, not the velocity's (px/s).
const HEADING_MIN_SPEED := 1.0

var config: LaserTenderConfig = LaserTenderConfig.new()
var phase: Phase = Phase.APPROACH
var budget: EngagementBudget
## Test seam (t14 gives it its meaning: a hub spawn idles unless engaged). Nothing idles yet, so it changes nothing in t13.
var start_engaged: bool = false
## Where the tender idles in the hub (t14). `Vector2.INF` (unset) defaults to the spawn position on the first tick.
var patrol_anchor: Vector2 = Vector2.INF
## The launched drone's tuning (`rig_length`, `standoff`, `slot_tolerance`), from a probe of the tender's `drone_scene` in `_setup()`: a caller that
## swaps the scene is planned with its own drone's numbers.
var drone_config: TwinLaserDroneConfig

var _started: bool = false
var _phase_time: float = 0.0
var _leave_after_launch: bool = false
var _arc_angle: float = 0.0
var _arc_dir: float = 1.0
var _exit_dir: Vector2 = Vector2.UP
var _light_state: int = -1


func tick(delta: float) -> void:
	if not _started:
		_setup()
	_phase_time += delta
	var expired := budget.update(delta)
	if expired and phase != Phase.DISENGAGE:
		if phase == Phase.LAUNCH:
			_leave_after_launch = true  # the shown telegraph is the launch that happens
		else:
			enter_phase(Phase.DISENGAGE)
	if phase == Phase.DISENGAGE:
		_tick_disengage()
		_update_light()
		return
	if not budget.active:
		_dock_returning()
	var target := TargetInfo.player(get_tree())
	_decide(target)
	if phase == Phase.DISENGAGE:
		_tick_disengage()
	else:
		_move(delta, target)
	_update_light()


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits. Works on a lone tender.
func enter_phase(p: Phase) -> void:
	if not _started:
		_setup()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.HOLD:
			var target := TargetInfo.player(get_tree())
			if target.has_target:
				_arc_angle = (actor.global_position - target.position).angle()
		Phase.DISENGAGE:
			_enter_disengage()
	_update_light()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the tender over. The light goes out.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


## The cradle telegraph is never moved by an ally (`BaseEnemy.accept_tow`).
func accepts_tow() -> bool:
	return phase != Phase.LAUNCH


## Seconds in the current phase.
func phase_time() -> float:
	return _phase_time


## The Attack B points for the player as it is now, ordered for the cradles (`points[0]` for `CradleL`'s drone A): see `open_space_points()` /
## `assault_points()` and `order_for_cradles()`.
func attack_b_points() -> PackedVector2Array:
	if not _started:
		_setup()
	var target := TargetInfo.player(get_tree())
	var dc := drone_config if drone_config != null else TwinLaserDroneConfig.new()
	var rect := _corridor_rect()
	var pts: PackedVector2Array
	if rect.has_area():
		pts = assault_points(target.position, target.velocity, rect.grow(-dc.slot_tolerance), dc.rig_length, dc.standoff, config)
	else:
		pts = open_space_points(target.position, target.velocity, target.facing, actor.global_position, dc.rig_length, config)
	var cradles := _tender().cradles()
	return order_for_cradles(pts, cradles[0].global_position, cradles[1].global_position)


# ── Attack B points (pure) ───────────────────────────────────────────────────────────────────────────────────────────

## The prediction horizon for a player [param distance] px from the tender: `min(lead_time_max, distance / launch_speed)` (s).
static func lead_time(distance: float, cfg: LaserTenderConfig) -> float:
	if cfg.launch_speed <= 0.0:
		return 0.0
	return minf(cfg.lead_time_max, distance / cfg.launch_speed)


## Open Space (§2.13): a moving player's wall stands on its predicted path, `P + v * lead_time`, across its heading; a standing player's
## `standing_lead` ahead of its nose, across the tender's bearing. Two points [param length] apart, unordered.
static func open_space_points(p: Vector2, v: Vector2, facing: Vector2, from: Vector2, length: float, cfg: LaserTenderConfig) -> PackedVector2Array:
	var bearing := p - from
	var bearing_dir := bearing.normalized() if bearing.length_squared() > EPS else Vector2.DOWN
	var aim: Vector2
	var heading: Vector2
	if v.length() >= STANDING_SPEED:
		aim = p + v * lead_time(bearing.length(), cfg)
		heading = v.normalized()
	else:
		var nose := facing.normalized() if facing.length_squared() > EPS else bearing_dir
		aim = p + nose * cfg.standing_lead
		heading = bearing_dir
	var u := heading.orthogonal()
	return PackedVector2Array([aim - u * length * 0.5, aim + u * length * 0.5])


## Assault (§2.13), inside [param rect] (the corridor's `inner_rect()` inset by the drone's `slot_tolerance`): a strafing player (`|v.x| >=
## strafe_speed_min`) gets a vertical wall `assault_wall_lead` ahead of it along x, centred on its y; any other a horizontal wall [param standoff]
## above it. Both clamped into the rect. Two points [param length] apart, unordered.
static func assault_points(p: Vector2, v: Vector2, rect: Rect2, length: float, standoff: float, cfg: LaserTenderConfig) -> PackedVector2Array:
	var half := length * 0.5
	if absf(v.x) >= cfg.strafe_speed_min:
		var x := clampf(p.x + signf(v.x) * cfg.assault_wall_lead, rect.position.x, rect.end.x)
		var y := clampf(p.y, rect.position.y + half, rect.end.y - half)
		return PackedVector2Array([Vector2(x, y - half), Vector2(x, y + half)])
	var cx := clampf(p.x, rect.position.x + half, rect.end.x - half)
	var cy := clampf(p.y - standoff, rect.position.y, rect.end.y)
	return PackedVector2Array([Vector2(cx - half, cy), Vector2(cx + half, cy)])


## The V never crosses: [param pts] reordered so `[0]` is the left cradle's point, choosing the matching with the smaller total length (if the legs
## crossed, swapping the ends would be strictly shorter, by the triangle inequality).
static func order_for_cradles(pts: PackedVector2Array, cradle_l: Vector2, cradle_r: Vector2) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var kept := cradle_l.distance_to(pts[0]) + cradle_r.distance_to(pts[1])
	var swapped := cradle_l.distance_to(pts[1]) + cradle_r.distance_to(pts[0])
	if swapped < kept:
		return PackedVector2Array([pts[1], pts[0]])
	return pts


# ── Decisions ────────────────────────────────────────────────────────────────────────────────────────────────────────

func _setup() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	_arc_dir = 1.0 if rng.randf() < 0.5 else -1.0
	var tender := _tender()
	if tender != null and tender.drone_scene != null:
		var probe := tender.drone_scene.instantiate()
		var cfg: Variant = probe.get(&"config")
		if cfg is TwinLaserDroneConfig:
			drone_config = cfg
		probe.free()


func _tender() -> LaserTender:
	return actor as LaserTender


## Transitions, in an order that lets one tick cascade (APPROACH -> HOLD -> LAUNCH; REARM -> HOLD -> LAUNCH).
func _decide(target: TargetInfo) -> void:
	if phase == Phase.APPROACH and _in_hold(target):
		enter_phase(Phase.HOLD)
	if phase == Phase.REARM and _phase_time + EPS >= config.rearm_seconds:
		_tender().rearm_cradles()
		enter_phase(Phase.HOLD)
	if phase == Phase.HOLD and _can_launch(target):
		enter_phase(Phase.LAUNCH)
	elif phase == Phase.LAUNCH and _phase_time > 0.0 and _phase_time + EPS >= config.launch_telegraph:
		_launch()
	elif phase == Phase.WAIT and not _pair_lives():
		enter_phase(Phase.REARM)


func _in_hold(target: TargetInfo) -> bool:
	if not target.has_target:
		return false
	var pos := actor.global_position
	if _corridor_rect().has_area():
		var hold := _hold_point(target.position)
		return absf(pos.y - hold.y) <= HOLD_REACH and _in_view(pos)
	return absf(pos.distance_to(target.position) - config.preferred_range) <= config.range_tolerance


func _can_launch(target: TargetInfo) -> bool:
	var tender := _tender()
	if not target.has_target or tender.docked_count() < 2 or _pair_lives():
		return false
	if Engine.is_in_physics_frame() and not can_see_player():
		return false
	if budget.active and (tender.launches() > 0 or not _in_view(actor.global_position)):
		return false
	return true


func _launch() -> void:
	var rig := _tender().launch_pair(attack_b_points())
	if rig != null:
		launched.emit(rig)
	if budget.active or _leave_after_launch:
		enter_phase(Phase.DISENGAGE)
	else:
		enter_phase(Phase.WAIT)


## True while the last rig this tender launched is an intact pair.
func _pair_lives() -> bool:
	var rig := _tender().pair()
	return rig != null and rig.is_intact()


func _dock_returning() -> void:
	var tender := _tender()
	for d in tender.launched_drones():
		var drone_brain := d.get_node_or_null("Brain") as TwinLaserDroneBrain
		if drone_brain != null and drone_brain.phase == TwinLaserDroneBrain.Phase.SOLO \
				and d.global_position.distance_to(actor.global_position) <= config.dock_radius:
			tender.dock(d)


func _in_view(pos: Vector2) -> bool:
	return EnemyWorld.has_view_rect(get_tree()) and EnemyWorld.view_rect(get_tree()).has_point(pos)


## The mover's corridor rect while one is held; an empty rect in Open Space.
func _corridor_rect() -> Rect2:
	if mover == null or mover.constraint == null or mover.constraint_released():
		return Rect2()
	return mover.constraint.inner_rect()


## Assault: the upper band of the visible corridor, above the player: x follows the player, y is `assault_hold_depth` below the view's top edge
## and at least `2 * R + HOLD_CLEARANCE` above the player, both clamped `2 * R` inside the corridor's inner rect.
func _hold_point(p: Vector2) -> Vector2:
	var r := _corridor_rect()
	var reach := 2.0 * _tender().body_radius()
	var y := p.y - reach - HOLD_CLEARANCE
	if EnemyWorld.has_view_rect(get_tree()):
		y = minf(EnemyWorld.view_rect(get_tree()).position.y + config.assault_hold_depth, y)
	return Vector2(clampf(p.x, r.position.x + reach, r.end.x - reach), clampf(y, r.position.y + reach, r.end.y - reach))


# ── Motion (requests only) ───────────────────────────────────────────────────────────────────────────────────────────

func _move(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var p := target.position
	match phase:
		Phase.APPROACH:
			if _corridor_rect().has_area():
				mover.arrive(_hold_point(p), config.max_speed)
			else:
				var away := actor.global_position - p
				var dir := away.normalized() if away.length_squared() > EPS else Vector2.UP
				mover.arrive(p + dir * config.preferred_range, config.max_speed)
			mover.face_toward(p)
		Phase.HOLD, Phase.LAUNCH, Phase.WAIT, Phase.REARM:
			if _corridor_rect().has_area():
				mover.arrive(_hold_point(p), config.max_speed)
			else:
				_arc_angle += config.arc_rate * _arc_dir * delta
				mover.orbit(p, config.preferred_range, _arc_angle, config.max_speed)
			mover.face_toward(p)
		_:
			mover.request_velocity(Vector2.ZERO)  # IDLE / NOTICING / RETURNING: t14 gives them motion


func _enter_disengage() -> void:
	_exit_dir = _heading()
	if EnemyWorld.has_projectile_world_rect(get_tree()):
		var rect := EnemyWorld.projectile_world_rect(get_tree())
		var pos := actor.global_position
		var to_left := pos.x - rect.position.x
		var to_right := rect.end.x - pos.x
		var to_top := pos.y - rect.position.y
		var to_bottom := rect.end.y - pos.y
		var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
		if nearest == to_top:
			_exit_dir = Vector2.UP
		elif nearest == to_left:
			_exit_dir = Vector2.LEFT
		elif nearest == to_right:
			_exit_dir = Vector2.RIGHT
		else:
			_exit_dir = Vector2.DOWN
	mover.release_constraint()
	mover.max_speed = config.exit_speed


## Straight out along the exit direction; strict `<` / `>` against the rect's edges (the Bomber's and the drone's exits).
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


# ── The cradle light ─────────────────────────────────────────────────────────────────────────────────────────────────

## CHARGING through the cradle telegraph (LAUNCH), OFF otherwise. Set only on change.
func _update_light() -> void:
	var want: int = StateLight.State.CHARGING if phase == Phase.LAUNCH else StateLight.State.OFF
	if want != _light_state:
		_set_light(want)


func _set_light(state: int) -> void:
	_light_state = state
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
