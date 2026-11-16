## The Carrier's brain (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.6.3; Phase 10 t6, task plan docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md).
## "A carrier does not chase the player; it controls space" (IDEAS §6.11). Movement only in t6: weapons (t7) and hangars (t8) hang off this brain later.
##
## Phases (append-only):
##   CRUISE     Open Space hub idle: a slow orbit round `patrol_anchor` (`AnchorIdle`), until the player comes within `perceive_radius`.
##   SCREEN     Open Space, engaged: hold the player in the `screen_range_min .. screen_range_max` band (close only from beyond it, open only from inside
##              it), never more than `leash_radius` from the anchor; a live battery side turned to the player.
##   PANIC      the core is exposed. Open Space: back away to the far side of the anchor from the player, on the leash circle (the leash wins). Assault:
##              the crossing, unchanged. Entered on the tick after exposure, from any phase, for good.
##   CROSS      Assault: a constant `assault_cross_speed` straight down, nose-down and never rotated, swaying at most `assault_sway_leash` px either side
##              of its spawn x to keep the player in a live battery's arc. The root frees it below the projectile rect.
##   IDLE       Open Space, engaged, no player in the tree: stop (t6 D4).
##   NOTICING / RETURNING  the hub idle's beat before SCREEN and its way home.
##
## MODULE DEATH CHANGES MOVEMENT. With one engine lost the turn rate halves (`one_engine_turn`) and the Open Space speed drops (`one_engine_speed`), and the
## hull LISTS: while it holds a heading it sags toward the dead side at `list_rate` until it is `list_hold_deg` off, then turns back at the scaled rate
## (t6 D3). With both lost: `no_engine_turn` / `no_engine_speed`, no list (the thrust is gone on both sides alike). The mover limits are keyed by the
## MODE, never the phase: in Assault the crossing's limits (`assault_max_speed`, acceleration / braking 0, avoidance 0) hold in every phase.
##
## EMP. Open Space keeps the Phase 9 halt. In Assault `on_emp_started()` / `on_emp_refreshed()` commit `mover.boost(DOWN, assault_cross_speed, window)`,
## so the hull keeps descending while the brain (weapons, hangars) is frozen.
##
## Requests only (single-writer gate): `arrive`, `orbit`, `request_velocity`, `face_toward`, `boost`, and limit writes on the mover.
class_name CarrierBrain
extends EnemyBrain

## Append-only.
enum Phase { CRUISE, SCREEN, PANIC, CROSS, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

const GUN_PORT := &"gun_port"
const GUN_STARBOARD := &"gun_starboard"
const ENGINE_PORT := &"engine_port"
const ENGINE_STARBOARD := &"engine_starboard"
## How far ahead of the hull the facing point is placed (px): only its direction matters.
const FACE_REACH := 100.0
## The list's correction ends once the heading is this close to the wanted one (rad).
const LIST_SETTLED := 0.01
## Half the side batteries' 150 degree traverse (§2.7); t7 reads it from the battery slot instead. The sway aims a margin inside it.
const SWAY_ARC_HALF_DEG := 75.0
const SWAY_ARC_MARGIN_DEG := 10.0
## The sway's proportional gain (1/s): `gain · dt` < 1, so x approaches its target without overshoot.
const SWAY_GAIN := 4.0
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35

## Set by `carrier.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: CarrierConfig = CarrierConfig.new()
var phase: Phase = Phase.CRUISE
## Test seam: an Open Space carrier starts screening, skipping the hub idle. Assault ignores it.
var start_engaged: bool = false
## The leash and idle centre. `Vector2.INF` (unset): `_start()` defaults it to the spawn position.
var patrol_anchor: Vector2 = Vector2.INF
## True in Assault (an arena exists), fixed in `_start()`; read by the root.
var assault: bool = false
## Open Space hub idle only; null otherwise.
var anchor_idle: AnchorIdle
var idle_phase_offset: float = 0.0
## Live ENGINE parts, counted from the hull's `module_destroyed`.
var engines_alive: int = 2

var _hull: ModularHull
var _started: bool = false
var _phase_time: float = 0.0
## Assault: the spawn x the sway is leashed to (after the root's world anchoring).
var _anchor_x: float = 0.0
## The list's correction flag (one engine lost).
var _correcting: bool = false
## Which engine died when exactly one is lost: +1 / -1 rotation sign toward the dead side, 0 otherwise.
var _list_sign: float = 0.0
var _engine_port_dead: bool = false
var _engine_starboard_dead: bool = false


## Hands the brain its parts (called by the root in `_ready()`).
func bind_hull(hull: ModularHull) -> void:
	_hull = hull
	_engine_port_dead = _part_dead(ENGINE_PORT)
	_engine_starboard_dead = _part_dead(ENGINE_STARBOARD)
	_recount_engines()
	if not hull.module_destroyed.is_connected(_on_module_destroyed):
		hull.module_destroyed.connect(_on_module_destroyed)


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if phase != Phase.PANIC and _core_exposed():
		enter_phase(Phase.PANIC)
	if assault:
		_tick_cross()
		return
	var target := TargetInfo.player(get_tree())
	if anchor_idle != null and phase != Phase.PANIC:
		_tick_anchor_idle(delta, target)
	match phase:
		Phase.CRUISE: _tick_cruise()
		Phase.NOTICING: _tick_noticing(target)
		Phase.RETURNING: _tick_returning()
		Phase.SCREEN, Phase.IDLE: _tick_screen(delta, target)
		Phase.PANIC: _tick_panic(delta, target)


## Test seam and the one place a transition happens.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	if p == Phase.PANIC:
		anchor_idle = null
	phase_changed.emit(p)


## Open Space: the Phase 9 halt (nothing to do). Assault: the crossing goes on for the whole window.
func on_emp_started() -> void:
	_boost_through_emp()


## `Carrier.apply_emp()`: a later EMP extended the running window.
func on_emp_refreshed() -> void:
	_boost_through_emp()


func on_suspended() -> void:
	anchor_idle = null


## A capital ship is never towed, in any phase.
func accepts_tow() -> bool:
	return false


## True while the hull is in a panic (the core exposed).
func is_panicking() -> bool:
	return phase == Phase.PANIC


## 1 / `one_engine_turn` / `no_engine_turn` with 2 / 1 / 0 engines.
func turn_factor() -> float:
	return [config.no_engine_turn, config.one_engine_turn, 1.0][clampi(engines_alive, 0, 2)]


## 1 / `one_engine_speed` / `no_engine_speed` (Open Space only).
func speed_factor() -> float:
	return [config.no_engine_speed, config.one_engine_speed, 1.0][clampi(engines_alive, 0, 2)]


## 1 / `one_engine_sway` / `no_engine_sway` (Assault).
func sway_factor() -> float:
	return [config.no_engine_sway, config.one_engine_sway, 1.0][clampi(engines_alive, 0, 2)]


## The rotation sign toward the dead engine's side with exactly one lost, else 0. Port (local +x) dead: the nose yaws toward +x, rotation decreasing.
func list_sign() -> float:
	return _list_sign


## Assault: the sway's leash centre.
func anchor_x() -> float:
	return _anchor_x


## The unit direction the nose should point along with the player along unit [param bearing] (hull -> player): the nearer live battery side turned
## to it (port is the nose turned -90 degrees: it faces `bearing` when the nose is `bearing` turned +90 degrees, the Gunship's mapping); a tie picks
## port; no live battery: the bow to the player.
func desired_nose(bearing: Vector2) -> Vector2:
	var nose := Vector2.DOWN.rotated(actor.rotation)
	var best := bearing
	var best_err := INF
	if _part_live(GUN_PORT):
		best = bearing.rotated(PI / 2.0)
		best_err = absf(nose.angle_to(best))
	if _part_live(GUN_STARBOARD):
		var starboard := bearing.rotated(-PI / 2.0)
		if absf(nose.angle_to(starboard)) < best_err:
			best = starboard
	return best


func _start() -> void:
	_started = true
	assault = EnemyWorld.arena(get_tree()) != null
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	_apply_limits()
	if assault:
		_anchor_x = actor.global_position.x
		phase = Phase.CROSS
		phase_changed.emit(phase)
		return
	if start_engaged:
		enter_phase(Phase.SCREEN)
		return
	anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.idle_radius)
	idle_phase_offset = rng.randf_range(-MAX_IDLE_PHASE_OFFSET, MAX_IDLE_PHASE_OFFSET)
	enter_phase(Phase.CRUISE)


## The mover limits, keyed by the mode: Assault holds the crossing's in every phase; Open Space scales the speed with the engines. The turn rate always
## follows the engines.
func _apply_limits() -> void:
	if mover == null:
		return
	mover.max_turn_rate = config.max_turn_rate * turn_factor()
	if assault:
		mover.max_speed = config.assault_max_speed
		mover.acceleration = 0.0
		mover.braking = 0.0
		mover.hazard_avoidance = 0.0
	else:
		mover.max_speed = config.max_speed * speed_factor()


func _on_module_destroyed(part: EnemyModule) -> void:
	if part.role != EnemyModule.Role.ENGINE:
		return
	if part.module_id == ENGINE_PORT:
		_engine_port_dead = true
	elif part.module_id == ENGINE_STARBOARD:
		_engine_starboard_dead = true
	_recount_engines()
	if _started:
		_apply_limits()


func _recount_engines() -> void:
	engines_alive = (0 if _engine_port_dead else 1) + (0 if _engine_starboard_dead else 1)
	if engines_alive == 1:
		_list_sign = -1.0 if _engine_port_dead else 1.0
	else:
		_list_sign = 0.0
	_correcting = false


func _core_exposed() -> bool:
	return actor != null and actor.has_method(&"is_core_exposed") and actor.is_core_exposed()


func _part_live(id: StringName) -> bool:
	if _hull == null:
		return false
	var part := _hull.module(id)
	return part != null and not part.is_destroyed()


func _part_dead(id: StringName) -> bool:
	if _hull == null:
		return false
	var part := _hull.module(id)
	return part != null and part.is_destroyed()


func _boost_through_emp() -> void:
	if not _started or not assault or mover == null or actor == null:
		return
	var left: float = actor.emp_seconds_left() if actor.has_method(&"emp_seconds_left") else 0.0
	if left > 0.0:
		mover.boost(Vector2.DOWN, config.assault_cross_speed, left)


# ── Open Space ──────────────────────────────────────────────────────────────────────────────────

func _tick_anchor_idle(delta: float, target: TargetInfo) -> void:
	match anchor_idle.update(delta, actor.global_position, target):
		AnchorIdle.State.IDLE:
			if phase != Phase.CRUISE:
				enter_phase(Phase.CRUISE)
		AnchorIdle.State.NOTICING:
			if phase != Phase.NOTICING:
				enter_phase(Phase.NOTICING)
		AnchorIdle.State.COMBAT:
			if phase != Phase.SCREEN and phase != Phase.IDLE:
				enter_phase(Phase.SCREEN)
		AnchorIdle.State.RETURNING:
			if phase != Phase.RETURNING:
				enter_phase(Phase.RETURNING)


func _tick_cruise() -> void:
	mover.orbit(patrol_anchor, config.idle_radius, idle_phase_offset + config.idle_speed * _phase_time, mover.max_speed)


func _tick_noticing(target: TargetInfo) -> void:
	mover.request_velocity(Vector2.ZERO)
	if target.has_target:
		mover.face_toward(target.position)


func _tick_returning() -> void:
	mover.arrive(patrol_anchor, mover.max_speed)


func _tick_screen(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		if phase != Phase.IDLE:
			enter_phase(Phase.IDLE)
		mover.request_velocity(Vector2.ZERO)
		return
	if phase == Phase.IDLE:
		enter_phase(Phase.SCREEN)
	var pos := actor.global_position
	var away := pos - target.position
	var d := away.length()
	var outside_leash := pos.distance_to(patrol_anchor) > config.leash_radius
	if d < config.screen_range_min or d > config.screen_range_max or outside_leash:
		if d < 1.0:
			away = Vector2.UP
		var mid := (config.screen_range_min + config.screen_range_max) * 0.5
		mover.arrive(_leashed(target.position + away.normalized() * mid), mover.max_speed)
	else:
		mover.request_velocity(Vector2.ZERO)
	_face_broadside(delta, target)


## The far side of the anchor from the player, on the leash circle: the leash wins over the retreat.
func _tick_panic(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var from_player := patrol_anchor - target.position
	if from_player.length_squared() < 1.0:
		from_player = actor.global_position - patrol_anchor
	if from_player.length_squared() < 1.0:
		from_player = Vector2.UP
	mover.arrive(patrol_anchor + from_player.normalized() * config.leash_radius, mover.max_speed)
	_face_broadside(delta, target)


## [param p] clamped into the leash disc round the anchor.
func _leashed(p: Vector2) -> Vector2:
	return patrol_anchor + (p - patrol_anchor).limit_length(config.leash_radius)


func _face_broadside(delta: float, target: TargetInfo) -> void:
	var to_player := target.position - actor.global_position
	if to_player.length_squared() < 1e-6:
		return
	_face(delta, desired_nose(to_player.normalized()))


## The one facing call outside the crossing. With exactly one engine lost the hull lists (header): it sags toward the dead side while within
## `list_hold_deg` of the wanted heading, and turns back at the scaled rate once past it.
func _face(delta: float, desired_dir: Vector2) -> void:
	var pos := actor.global_position
	if _list_sign == 0.0:
		mover.face_toward(pos + desired_dir * FACE_REACH)
		return
	var desired_rot := desired_dir.angle() - EnemyMover.sprite_forward_angle_of(actor)
	var err := absf(angle_difference(actor.rotation, desired_rot))
	if err > deg_to_rad(config.list_hold_deg):
		_correcting = true
	elif err <= LIST_SETTLED:
		_correcting = false
	if _correcting:
		mover.face_toward(pos + desired_dir * FACE_REACH)
		return
	var sag_rot := actor.rotation + _list_sign * config.list_rate * delta
	mover.face_toward(pos + Vector2.RIGHT.rotated(sag_rot + EnemyMover.sprite_forward_angle_of(actor)) * FACE_REACH)


# ── Assault ─────────────────────────────────────────────────────────────────────────────────────

func _tick_cross() -> void:
	var pos := actor.global_position
	var target := TargetInfo.player(get_tree())
	var tx := _sway_target_x(pos, target)
	var cap := config.assault_sway_speed * sway_factor()
	var vx := clampf((tx - pos.x) * SWAY_GAIN, -cap, cap)
	mover.request_velocity(Vector2(vx, config.assault_cross_speed))
	mover.face_toward(pos + Vector2.DOWN * FACE_REACH)


## The x the sway steers to (header): hold while the player is already inside a live battery's arc (a margin inside it), else the x that puts the
## player on the nearer live battery's arc line, else the spawn x; always inside the leash.
func _sway_target_x(pos: Vector2, target: TargetInfo) -> float:
	var tx := _anchor_x
	if target.has_target:
		var half := deg_to_rad(SWAY_ARC_HALF_DEG - SWAY_ARC_MARGIN_DEG)
		var to_player := target.position - pos
		var port := _part_live(GUN_PORT)
		var starboard := _part_live(GUN_STARBOARD)
		# At rotation 0 port (local +x) faces world +x, starboard world -x.
		var covered := (port and absf(Vector2.RIGHT.angle_to(to_player)) <= half) \
				or (starboard and absf(Vector2.LEFT.angle_to(to_player)) <= half)
		if covered:
			tx = pos.x
		elif port or starboard:
			var reach := absf(to_player.y) / tan(half)
			var best := INF
			if port:
				var px := target.position.x - reach
				best = px
			if starboard:
				var sx := target.position.x + reach
				if not port or absf(sx - pos.x) < absf(best - pos.x):
					best = sx
			tx = best
	return clampf(tx, _anchor_x - config.assault_sway_leash, _anchor_x + config.assault_sway_leash)
