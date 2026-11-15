## The Heavy Gunship's brain (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4; Phase 10 t4, task plan
## docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md). A mobile gun platform: it keeps its distance, turns a battery side-on to the player, strafes
## a wide arc and boosts away when rushed. It never parks and never leaves the fight on low health.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH    [APPROACH]   `arrive` at the point `held_range()` from the player on the line to it, the nose (the heavy cannon) on the
##                            player; BROADSIDE once within `range_tolerance` of the held range.
##   BROADSIDE   [POSITION]   a wide orbit about the player at `held_range()` ± `range_drift` (7-10 s period) at the arc speed, reversing every
##                            `reversal_min`..`reversal_max` s; in Assault the arc stays within ±`assault_arc_half_deg` of straight above the
##                            player and reverses at its ends. The hull turns its chosen battery side to the player (`_desired_nose()`).
##   BREAK_AWAY  [EVADE]      the player inside `min_range`: one committed `mover.boost` along `Steering.break_contact` (side `-orbit_dir`, the
##                            Ph5 sign), then BROADSIDE; no other for `break_rearm` s.
##   VENT        [ATTACK]     t5 (overheat-and-vent). A stub here: it falls straight back to BROADSIDE.
##   EMERGENCY   [PANIC]      t5 (emergency boosts and rear missiles). A stub here: it falls straight back to BROADSIDE.
##   DISENGAGE   [DISENGAGE]  Assault only: the budget ran out. Release the corridor, write `exit_speed` / `exit_acceleration` onto the mover
##                            and curve toward the nearest projectile-rect edge; freed once outside it. Nothing is ticked: no fire.
##   IDLE / NOTICING / RETURNING [SEARCH / REPOSITION]  the Open Space hub idle through `AnchorIdle` (the corvette's), mounts scanning.
##
## THE CHOSEN SIDE. Port is the hull's left: with the art nose-down (local +y), port is local +x. The side is chosen the first time one is needed
## as the side the player is on, and kept while its battery lives (so the hull never flips needlessly); when that battery dies it becomes the
## other side, and the mover's `max_turn_rate` swings the nose the shorter way (module death changes movement). No live battery: the nose (the
## cannon) to the player; nothing but the missiles: the nose away.
##
## WEAPONS. The four mounts are built by `ModularHull.build_mounts()` (the root's `_ready()`) and handed over in `bind_mounts()`. In APPROACH,
## BROADSIDE and BREAK_AWAY every gun mount is ticked with `can_fire = can_see_player() or fires_past_cover()` (line of sight only on the
## physics step, the turret rule); the rear Missiles mount gets `can_fire` false (t5 opens it). A destroyed part's mounts are UNPOWERED (t3).
##
## ASSAULT. `EngagementBudget` (`engage_seconds`). The attack gate (`attack_gate_open()`, every mount's `telegraph_gate`) refuses a telegraph
## that would end after the budget, and a break-away is not started with less than `break_seconds` left, so expiry is deferred only while a gun
## mount is in TELEGRAPH / FIRE or the hull is boosting: at most `attack_window()`.
##
## Requests only (single-writer gate): `arrive`, `orbit`, `request_velocity`, `face_toward`, `boost`, `release_constraint()` and the two limit
## writes on DISENGAGE.
class_name HeavyGunshipBrain
extends EnemyBrain

## Append-only.
enum Phase { APPROACH, BROADSIDE, BREAK_AWAY, VENT, EMERGENCY, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## The module ids of the gun parts (battery and cannon mounts) and of the rear missile part.
const BATTERY_PORT := &"battery_port"
const BATTERY_STARBOARD := &"battery_starboard"
const CANNON := &"cannon"
const MISSILES := &"missiles"
const GUN_PARTS: Array[StringName] = [BATTERY_PORT, BATTERY_STARBOARD, CANNON]
## `side` values: the battery side turned to the player.
const SIDE_NONE := 0
const SIDE_PORT := 1
const SIDE_STARBOARD := -1
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The attack gate asks for this much budget beyond the longest burst (s). The Ram Corvette's margin.
const ATTACK_GATE_MARGIN := 0.05
## The drift of the held range has a period drawn in this range (s).
const DRIFT_PERIOD_MIN := 7.0
const DRIFT_PERIOD_MAX := 10.0
## How far ahead of the hull the facing point is placed (px): only its direction matters.
const FACE_REACH := 100.0
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35
## The arc's angle never leads the hull's own bearing from the player by more than this (rad), so a moving player cannot drag the orbit
## anchor away from the hull (at 140 px/s it would chase it and lose the range).
const ORBIT_MAX_LEAD := 0.35

## Set by `heavy_gunship.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: HeavyGunshipConfig = HeavyGunshipConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH
## Test seam: a spawned gunship starts already fighting, skipping the hub idle. Assault ignores it (`EngagementBudget.active` decides).
var start_engaged: bool = false
## The hub idle's ring centre. `Vector2.INF` (unset): `_start()` defaults it to the spawn position.
var patrol_anchor: Vector2 = Vector2.INF
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once, in `_start()`.
var anchor_idle: AnchorIdle
## This gunship's offset on the idle ring (rad), drawn from `rng` when the idle starts.
var idle_phase_offset: float = 0.0
## ±1: the way round the player the arc goes. Drawn on the first tick, flipped on every reversal.
var orbit_dir: float = 1.0
## The battery side turned to the player: `SIDE_PORT`, `SIDE_STARBOARD`, or `SIDE_NONE` until one is first needed.
var side: int = SIDE_NONE
## Seconds until another break-away may start; counts down in every phase.
var break_left: float = 0.0
## Break-away boosts started in this life.
var breaks_started: int = 0
## Every mount's `telegraph_gate` (the root passes it to `ModularHull.build_mounts()`).
var attack_gate: Callable = Callable(self, &"attack_gate_open")

var _hull: ModularHull
var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
## The projectile world rect DISENGAGE leaves, read once on entry: `ArenaCamera.projectile_world_rect()` is pinned (a constant), so a per-tick
## lookup (two group searches) would only cost the exit probe time.
var _exit_rect: Rect2 = Rect2()
## DISENGAGE's turn rate (rad/s), also fixed on entry: `max_turn_rate` capped by what the exit acceleration can follow.
var _exit_turn_rate: float = 0.0
var _expiry_seen: bool = false
var _disengage_pending: bool = false
var _orbit_angle: float = 0.0
var _orbit_synced: bool = false
var _arc_clock: float = 0.0
var _drift_period: float = DRIFT_PERIOD_MIN
var _drift_phase: float = 0.0
var _reversal_left: float = 0.0
var _light: StateLight


func _ready() -> void:
	super._ready()
	if actor != null:
		_light = actor.get_node_or_null(^"StateLight") as StateLight


## Hands the brain its parts (called by the root once `build_mounts()` has run).
func bind_mounts(hull: ModularHull) -> void:
	_hull = hull


func tick(delta: float) -> void:
	# The exit reads no player, ticks no mount, shows no light (OFF since entry) and no longer needs the budget or the break rearm: the short
	# path keeps the exit probe cheap. A DISENGAGE entered later in this tick takes the branch below once.
	if phase == Phase.DISENGAGE and _started:
		_phase_time += delta
		_tick_disengage(delta)
		return
	if not _started:
		_start()
	_phase_time += delta
	break_left = maxf(break_left - delta, 0.0)
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		_on_budget_expired()
	if _disengage_pending and not _is_committed():
		_disengage_pending = false
		enter_phase(Phase.DISENGAGE)
	if phase == Phase.DISENGAGE:
		_tick_disengage(delta)
		return
	if anchor_idle != null:
		_tick_anchor_idle(delta)
	var target := TargetInfo.player(get_tree())
	match phase:
		Phase.IDLE: _tick_idle(delta)
		Phase.NOTICING: _tick_noticing(delta, target)
		Phase.RETURNING: _tick_returning(delta)
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.BROADSIDE: _tick_broadside(delta, target)
		Phase.BREAK_AWAY: _tick_break_away(delta, target)
		Phase.VENT, Phase.EMERGENCY: enter_phase(Phase.BROADSIDE)  # t5 stubs
	_update_light()


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.DISENGAGE:
			_enter_disengage()
		Phase.IDLE, Phase.NOTICING, Phase.RETURNING:
			_orbit_synced = false
		Phase.APPROACH:
			_orbit_synced = false
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the gunship over. Its mounts are no longer ticked, so it rides without firing; a telegraph shown
## at that moment is cancelled (`scan(0.0)`) rather than left frozen on the light.
func on_suspended() -> void:
	anchor_idle = null
	_scan_mounts(0.0)
	_set_light(StateLight.State.OFF)


## An EMP window started (`BaseEnemy.apply_emp`; the mover is already halted): a shown telegraph never lands. Every mount `scan(0.0)`s (its weapon
## stops; a FIRE cut here still starts its cooldown) and the light goes OFF; the brain is not ticked for the window and fights again after it
## (the Phase 9 rule for shown telegraphs).
func on_emp_started() -> void:
	_scan_mounts(0.0)
	_set_light(StateLight.State.OFF)


## A heavy hull is never towed (§2.4.1), in any phase.
func accepts_tow() -> bool:
	return false


## The range the gunship holds: the corridor is narrower than the open sky.
func held_range() -> float:
	return config.assault_preferred_range if _assault() else config.preferred_range


## The longest a started gun burst runs (s): `charge_seconds + (burst_count - 1) * burst_gap` over the live battery and cannon mounts (read
## duck-typed from the mounts). 1.05 s at full strength (the heavy cannon). The attack gate asks for it; the budget defers to it.
func attack_window() -> float:
	var longest := 0.0
	for mount in _gun_mounts(true):
		if "charge_seconds" in mount and "burst_count" in mount and "burst_gap" in mount:
			var w: float = float(mount.get("charge_seconds")) + float(int(mount.get("burst_count")) - 1) * float(mount.get("burst_gap"))
			longest = maxf(longest, w)
	return longest


## Every mount's `telegraph_gate`: true unless the Assault budget is running out (a burst it starts would end after it) or DISENGAGE is pending.
func attack_gate_open() -> bool:
	if budget == null or not budget.active:
		return true
	return not _disengage_pending and not _expiry_seen and budget.remaining() >= attack_window() + ATTACK_GATE_MARGIN


## The unit vector the nose should point along with the player along unit `bearing` (hull -> player): the chosen battery side turned to it,
## else the nose (cannon) to it, else the nose away. Chooses and keeps `side` (header).
func desired_nose(bearing: Vector2) -> Vector2:
	var port := _part_live(BATTERY_PORT)
	var starboard := _part_live(BATTERY_STARBOARD)
	if port or starboard:
		if side == SIDE_NONE:
			if port and starboard:
				side = SIDE_PORT if bearing.rotated(-actor.rotation).x >= 0.0 else SIDE_STARBOARD
			else:
				side = SIDE_PORT if port else SIDE_STARBOARD
		elif side == SIDE_PORT and not port:
			side = SIDE_STARBOARD
		elif side == SIDE_STARBOARD and not starboard:
			side = SIDE_PORT
		# Port is the nose turned -90 degrees (nose-down art: local +y nose, +x port), so port faces `bearing` when the nose is `bearing`
		# turned +90 degrees.
		return bearing.rotated(PI / 2.0) if side == SIDE_PORT else bearing.rotated(-PI / 2.0)
	if _part_live(CANNON):
		return bearing
	return -bearing


## The mounts on the gun parts (batteries, cannon); with [param live_only], only those whose part is not a wreck.
func _gun_mounts(live_only: bool) -> Array[TurretMount]:
	var out: Array[TurretMount] = []
	if _hull == null:
		return out
	for id in GUN_PARTS:
		var part := _hull.module(id)
		if part == null or (live_only and part.is_destroyed()):
			continue
		out.append_array(part.mounts())
	return out


func _part_live(id: StringName) -> bool:
	if _hull == null:
		return false
	var part := _hull.module(id)
	return part != null and not part.is_destroyed()


func _assault() -> bool:
	return budget != null and budget.active


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


## The budget ran out: leave now, unless a burst is being shown or fired or a boost is running, which finishes first.
func _on_budget_expired() -> void:
	if phase == Phase.DISENGAGE:
		return
	if _is_committed():
		_disengage_pending = true
		return
	enter_phase(Phase.DISENGAGE)


## True while a gun mount is telegraphing or firing, or the hull is in a committed boost.
func _is_committed() -> bool:
	if mover != null and mover.is_boosting():
		return true
	for mount in _gun_mounts(true):
		var p := mount.phase()
		if p == TurretMount.Phase.TELEGRAPH or p == TurretMount.Phase.FIRE:
			return true
	return false


# ── Hub idle ────────────────────────────────────────────────────────────────────────────────────

## The meta-state that decides whether the gunship is patrolling, noticing or fighting, once a tick ahead of the phase dispatch. A committed
## boost or burst is never interrupted: the change is retried every tick until it has ended.
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
			if phase == Phase.NOTICING:
				enter_phase(Phase.APPROACH)
		AnchorIdle.State.RETURNING:
			if phase != Phase.RETURNING and not _is_committed():
				enter_phase(Phase.RETURNING)


func _tick_idle(delta: float) -> void:
	mover.orbit(patrol_anchor, config.idle_radius, idle_phase_offset + config.idle_speed * _phase_time, config.max_speed)
	_scan_mounts(delta)


func _tick_noticing(delta: float, target: TargetInfo) -> void:
	mover.request_velocity(Vector2.ZERO)
	if target.has_target:
		mover.face_toward(target.position)
	_scan_mounts(delta)


func _tick_returning(delta: float) -> void:
	mover.arrive(patrol_anchor, config.max_speed)
	_scan_mounts(delta)


# ── The fight ───────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if target.has_target:
		var pos := actor.global_position
		var away := pos - target.position
		if absf(away.length() - held_range()) <= config.range_tolerance:
			enter_phase(Phase.BROADSIDE)
			_tick_broadside(delta, target)
			return
		if _try_break_away(target):
			_tick_break_away(delta, target)
			return
		if away.length() < 1.0:
			away = Vector2.UP
		mover.arrive(target.position + away.normalized() * held_range(), config.max_speed)
		mover.face_toward(target.position)
	_tick_weapons(delta, target)


func _tick_broadside(delta: float, target: TargetInfo) -> void:
	if target.has_target:
		if _try_break_away(target):
			_tick_break_away(delta, target)
			return
		_arc_motion(delta, target)
		_face_broadside(target)
	_tick_weapons(delta, target)


func _tick_break_away(delta: float, target: TargetInfo) -> void:
	if target.has_target:
		_face_broadside(target)
	_tick_weapons(delta, target)
	if not mover.is_boosting() and _phase_time > 0.0:
		_orbit_synced = false  # the arc resumes from where the boost left it (the corvette's re-sync after its break-off)
		enter_phase(Phase.BROADSIDE)


## One break-away boost if the player is inside `min_range` and the rearm has run out (and, in Assault, a whole boost fits in the budget).
func _try_break_away(target: TargetInfo) -> bool:
	if break_left > 0.0 or mover.is_boosting() or _disengage_pending:
		return false
	var pos := actor.global_position
	if pos.distance_to(target.position) >= config.min_range:
		return false
	if _assault() and budget.remaining() < config.break_seconds:
		return false
	# The arc's own sense is `-orbit_dir` in `break_contact`'s convention (the Missile Corvette's note): the boost continues the way it turns.
	var dir := Steering.break_contact(pos, target.position, target.velocity, -orbit_dir, 1.0)
	mover.boost(dir, config.break_speed, config.break_seconds)
	break_left = config.break_rearm
	breaks_started += 1
	enter_phase(Phase.BREAK_AWAY)
	return true


## The wide arc: the corvette's orbit with a drifting radius and timed reversals; in Assault, kept within the sector above the player.
func _arc_motion(delta: float, target: TargetInfo) -> void:
	var pos := actor.global_position
	var offset := pos - target.position
	if not _orbit_synced:
		_orbit_synced = true
		_orbit_angle = offset.angle() if offset.length_squared() > 1e-6 else -PI / 2.0
	_arc_clock += delta
	_reversal_left -= delta
	if _reversal_left <= 0.0:
		orbit_dir = -orbit_dir
		_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	var speed := config.assault_orbit_angular_speed if _assault() else config.orbit_angular_speed
	_orbit_angle += orbit_dir * speed * delta
	if offset.length_squared() > 1e-6:
		var bearing := offset.angle()
		_orbit_angle = bearing + clampf(angle_difference(bearing, _orbit_angle), -ORBIT_MAX_LEAD, ORBIT_MAX_LEAD)
	if _assault():
		# 0 = straight above the player; a growing angle is `orbit_dir` +1.
		var half := deg_to_rad(config.assault_arc_half_deg)
		var rel := wrapf(_orbit_angle + PI / 2.0, -PI, PI)
		if rel > half:
			_orbit_angle = -PI / 2.0 + half
			orbit_dir = -1.0
			_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
		elif rel < -half:
			_orbit_angle = -PI / 2.0 - half
			orbit_dir = 1.0
			_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	var radius := held_range() + config.range_drift * sin(TAU * _arc_clock / _drift_period + _drift_phase)
	mover.orbit(target.position, radius, _orbit_angle, config.max_speed)


func _face_broadside(target: TargetInfo) -> void:
	var to_player := target.position - actor.global_position
	if to_player.length_squared() < 1e-6:
		return
	mover.face_toward(actor.global_position + desired_nose(to_player.normalized()) * FACE_REACH)


func _tick_weapons(delta: float, target: TargetInfo) -> void:
	if _hull == null:
		return
	var sees := true
	if Engine.is_in_physics_frame():
		sees = can_see_player()
	# The turret rule (Assault): never fire from outside the view, where shells would arrive from nowhere.
	var tree := get_tree()
	var in_view := not EnemyWorld.has_view_rect(tree) or EnemyWorld.view_rect(tree).has_point(actor.global_position)
	for mount in _gun_mounts(false):
		mount.tick(delta, target, in_view and (sees or mount.fires_past_cover()))
	var missiles := _hull.module(MISSILES)
	if missiles != null:
		for mount in missiles.mounts():
			mount.tick(delta, target, false)  # t5 opens the rear missiles


func _scan_mounts(delta: float) -> void:
	if _hull == null:
		return
	for part in _hull.modules():
		for mount in part.mounts():
			mount.scan(delta)


# ── Assault exit ────────────────────────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	_disengage_pending = false
	_set_light(StateLight.State.OFF)
	mover.release_constraint()
	mover.max_speed = config.exit_speed
	mover.acceleration = config.exit_acceleration
	_exit_rect = EnemyWorld.projectile_world_rect(get_tree())
	_exit_turn_rate = config.max_turn_rate
	if config.exit_speed > 0.0:
		_exit_turn_rate = minf(_exit_turn_rate, config.exit_acceleration / config.exit_speed)
	var rect := _exit_rect
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


## Strict `<` / `>` against the rect's edges (the corvette's). The curve's rate is capped by what the exit acceleration can follow.
func _tick_disengage(delta: float) -> void:
	var rect := _exit_rect
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, _exit_turn_rate, delta)
	mover.request_velocity(dir * config.exit_speed)


## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


# ── Light ───────────────────────────────────────────────────────────────────────────────────────

## CHARGING while a gun telegraphs, ARMED while one tracks or fires at the player, else OFF (the turret brain's mapping, without COMMIT).
func _update_light() -> void:
	if _light == null:
		return
	var want: int = StateLight.State.OFF
	if phase == Phase.APPROACH or phase == Phase.BROADSIDE or phase == Phase.BREAK_AWAY:
		for mount in _gun_mounts(true):
			var p := mount.phase()
			if p == TurretMount.Phase.TELEGRAPH:
				want = StateLight.State.CHARGING
				break
			if p == TurretMount.Phase.TRACK or p == TurretMount.Phase.FIRE or p == TurretMount.Phase.COOLDOWN:
				want = StateLight.State.ARMED
	_set_light(want)


func _set_light(state: int) -> void:
	if _light != null:
		_light.set_state(state)
