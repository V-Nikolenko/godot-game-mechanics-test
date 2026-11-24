## The Space Fortress's brain (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5, §2.6; Phase 11 t5 built the shell, task plan
## docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md; t6 the movement, task plan docs/plans/cmwt4y3hk00ssqs2ybengu81w/3-plan.md). t7 adds the batteries and the
## attack gate, t16 the geometry weapons (it calls `begin_spin()` / `end_spin()`), t8 the bays; each fills the hooks below without changing their names.
##
## What it does: ticks the fortress's `BossReinforcements` (held while not engaged), hears the boss phase ladder through `on_boss_phase()`, silences everything it
## ticks when an EMP window starts (`on_emp_started()`: every attached mount `scan(0.0)`s and the bays get one `tick(0.0, false)`, because the brain is not ticked
## during the window) and when the fortress dies (`silence()`), and refuses tows.
##
## MOVEMENT (t6). A face point is requested EVERY tick (with none the mover would yaw the hull to its direction of travel):
##   - the FACING RULE (`present_side()`): the stronger sector (live batteries, halved once its generator is destroyed; a tie keeps the side) is turned toward
##     the player at `turn_rate` (Assault `assault_turn_rate`), slower than a circling player, so circling reaches the weak side;
##   - SPINS while engaged: a volley spin (`begin_spin()`, alternating) at `beam_spin_rate`, and in `critical` a continuous spin at `critical_spin_rate`;
##   - the Open Space hub idle spin at `idle_spin_rate`.
## A spin faces a point 1 rad ahead of the current facing with the mover's `max_turn_rate` at the spin rate; the fortress mover authors `turn_lerp` 0, so the cap
## alone sets the rate.
##   Open Space: `patrol_anchor` is the combat zone's centre. IDLE holds it (`AnchorIdle`; `start_engaged` skips it, the Carrier rule: no leash then), NOTICING ->
##   HOLD at the station point; from `core_exposed` REPOSITION: every `reposition_period` a new station point (`pick_station_point()`) on the 0.6 x zone circle,
##   reached at the phase's speed; the player beyond `lose_radius` -> RETURNING to the anchor -> IDLE (the boss phase and damage kept).
##   Assault: ENTER straight down to `assault_hold_y`, HOLD there; from `core_exposed` REPOSITION is a vertical bob of `assault_bob_amplitude`; x never moves
##   (only a correction back to the anchored x, at most `assault_x_correct_speed`). No engagement budget, no exit.
## The per-boss-phase settings written in `on_boss_phase()` are `movement_snapshot()` (the §25 key): phase-driven state only.
## Thrusters: `Thrusters.visible` is the root's phase flag (the snapshot's); this brain writes only its `modulate.a`, full while travelling, dimmed holding.
##
## TWO PHASE ENUMS, NEVER MIXED: the boss phase ladder (`BossPhaseDriver` on the root: batteries -> shields_exposed -> core_exposed -> critical) and
## this brain's movement `Phase` below (append-only). `is_engaged()` is HOLD or REPOSITION in both modes: weapons fire and bays run only then.
##
## Requests only (single-writer gate): this brain never writes the body's velocity or rotation.
class_name FortressBrain
extends EnemyBrain

## Append-only. IDLE / NOTICING / RETURNING: the Open Space hub idle; ENTER: the Assault descent; HOLD / REPOSITION: engaged.
enum Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }

## Emitted on every movement-phase transition, with the phase entered.
signal phase_changed(new_phase: int)

## Sector names (`present_side()`).
const NORTH := &"north"
const SOUTH := &"south"
## `movement_snapshot()` vocabulary.
const TRANSLATION_HOLD := &"hold"
const TRANSLATION_REPOSITION := &"reposition"
const TRANSLATION_BOB := &"bob"
const SPIN_FACE := &"face"
const SPIN_VOLLEY := &"volley"
const SPIN_CONTINUOUS := &"continuous"
## Each sector's batteries and generator, and the local bearing of its centre (north 270 degrees = local -y, south 90 = local +y).
const NORTH_BATTERIES: Array[StringName] = [&"battery_artillery", &"battery_missiles"]
const SOUTH_BATTERIES: Array[StringName] = [&"battery_spread", &"battery_pulse", &"battery_sweep"]
const NORTH_GENERATOR := &"shield_north"
const SOUTH_GENERATOR := &"shield_south"
const NORTH_BEARING := -PI / 2.0
const SOUTH_BEARING := PI / 2.0
## How far out the face point is placed (px). Only its direction matters; a long lever keeps it true when a hand tick's `move_and_slide()` moved the hull by
## the idle delta before the mover measured it (task plan review R1-4).
const FACE_REACH := 10000.0
## A spin faces this far ahead of the current facing (rad): more than one tick of any spin rate, so the mover's cap sets the rate.
const SPIN_LEAD := 1.0
## The station-point candidates on the zone circle, and the margin a later one must beat to win (so the lowest index wins ties).
const STATION_CANDIDATES := 8
const PICK_EPS := 0.001
## A travel ends this close to its point (px); the hold takes over.
const ARRIVED := 2.0
## Assault: the hold and x-correction gain (1/s): `gain · dt` < 1, so a correction never overshoots.
const HOLD_GAIN := 4.0
## The bob reverses this close to an end (px).
const BOB_END_EPS := 0.01
## `Thrusters.modulate.a` while not travelling.
const THRUSTER_IDLE_ALPHA := 0.35
## The project clock rule: a countdown is over at <= this.
const CLOCK_EPS := 1e-6

## Set by `space_fortress.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SpaceFortressConfig = SpaceFortressConfig.new()
var phase: Phase = Phase.IDLE
## Test seam: an Open Space fortress starts engaged, skipping the hub idle (and with it the leash). Assault ignores it.
var start_engaged: bool = false
## The Open Space combat zone's centre. `Vector2.INF` (unset): `_start()` defaults it to the spawn position.
var patrol_anchor: Vector2 = Vector2.INF
## True in Assault (an arena exists). Resolved in `on_boss_phase()` (it runs from the root's `_ready()`, before the first tick) or `_start()`.
var assault: bool = false
## Open Space hub idle only; null otherwise.
var anchor_idle: AnchorIdle

var _hull: ModularHull
var _reinforcements: BossReinforcements
var _started: bool = false
var _mode_known: bool = false
## Phase-driven movement settings (`on_boss_phase()`), the §25 `movement` key.
var _translation_mode: StringName = TRANSLATION_HOLD
var _spin_mode: StringName = SPIN_FACE
var _reposition_period: float = 0.0
var _travel_speed: float = 0.0
## Open Space: where the hull holds; seconds until the next pick (REPOSITION only).
var _station_point: Vector2 = Vector2.ZERO
var _reposition_left: float = 0.0
## Assault: the anchored x and the bob's direction (+1 down).
var _anchor_x: float = 0.0
var _bob_dir: float = 1.0
## The sector the facing rule presents (empty until first evaluated).
var _side: StringName = &""
## The running volley spin's direction (0 = none), the last spin direction handed out, and the critical spin's.
var _volley_dir: int = 0
var _last_spin_dir: int = -1
var _continuous_dir: int = 1
var _travelling: bool = false
var _thrusters: CanvasItem
## The batteries (t7): the gate cap, the cooldown factor applied in `critical` (1.0 before) and whether it was applied (once).
var _max_attacks: int = 2
var _cooldown_factor: float = 1.0
var _cooldown_applied: bool = false


## Hands the brain its parts and its bays (called by the root in `_ready()`).
func bind(hull: ModularHull, reinforcements: BossReinforcements) -> void:
	_hull = hull
	_reinforcements = reinforcements


func tick(delta: float) -> void:
	if actor != null:
		if not _started:
			_start()
		var target := TargetInfo.player(get_tree())
		if assault:
			_tick_assault(delta)
		else:
			_tick_open_space(delta, target)
		_face(target)
		_show_thrust()
		_tick_weapons(delta, target)
	if _reinforcements != null:
		_reinforcements.tick(delta, is_engaged())


## True in HOLD or REPOSITION (both modes): the weapons (t7, t16) fire and the bays (t8) run only then.
func is_engaged() -> bool:
	return phase == Phase.HOLD or phase == Phase.REPOSITION


## The batteries' shared `TurretMount.telegraph_gate` (zero arguments: `TurretMount` calls `telegraph_gate.call()` and `ModularHull.build_mounts()` hands the
## same unbound Callable to every mount). True while fewer than `_max_attacks` battery mounts are in TELEGRAPH or FIRE (the asking mount is still in TRACK, so
## it is not counted): never a wall of five bursts at once. The cap is 2, 3 in `critical`.
func attack_gate() -> bool:
	return attacking_count() < _max_attacks


## How many battery mounts are in TELEGRAPH or FIRE right now.
func attacking_count() -> int:
	var n := 0
	for mount in _mounts():
		var p := mount.phase()
		if p == TurretMount.Phase.TELEGRAPH or p == TurretMount.Phase.FIRE:
			n += 1
	return n


## The boss phase ladder entered [param phase_id] (`SpaceFortress._on_phase_entered`): the movement settings of that phase. t7, t16 and t8 add theirs here.
func on_boss_phase(phase_id: StringName) -> void:
	_resolve_mode()
	match phase_id:
		&"batteries":
			_set_movement(TRANSLATION_HOLD, SPIN_FACE, 0.0, 0.0)
		&"shields_exposed":
			_set_movement(TRANSLATION_HOLD, SPIN_VOLLEY, 0.0, 0.0)
		&"core_exposed":
			if assault:
				_set_movement(TRANSLATION_BOB, SPIN_VOLLEY, 0.0, config.assault_bob_speed)
			else:
				_set_movement(TRANSLATION_REPOSITION, SPIN_VOLLEY, config.reposition_period, config.reposition_speed)
		&"critical":
			if assault:
				_set_movement(TRANSLATION_BOB, SPIN_CONTINUOUS, 0.0, config.critical_bob_speed)
			else:
				_set_movement(TRANSLATION_REPOSITION, SPIN_CONTINUOUS, config.critical_reposition_period, config.critical_reposition_speed)
			_continuous_dir = -_last_spin_dir
			_last_spin_dir = _continuous_dir
	_set_attacks(phase_id)


## The batteries' phase settings (the §25 `attacks` key's battery fields): `critical` cuts every live battery mount's cooldown by `critical_cooldown_factor`,
## once, on the instanced mount nodes (never on a resource: the shipped mount scene keeps its value), and raises the gate cap.
func _set_attacks(phase_id: StringName) -> void:
	if phase_id != &"critical":
		_max_attacks = config.max_concurrent_attacks
		return
	_max_attacks = config.critical_max_concurrent_attacks
	if _cooldown_applied:
		return
	_cooldown_applied = true
	_cooldown_factor = config.critical_cooldown_factor
	if _hull == null:
		return
	for part in _hull.modules():
		if part.is_destroyed():
			continue
		for mount in part.mounts():
			if is_instance_valid(mount):
				mount.cooldown_seconds *= _cooldown_factor


## An EMP window started: nothing this brain ticks may hang lit or open through it (the brain is not ticked for the window). The hull stops (the base rule
## halts the mover; with no request it writes no motion and no rotation).
func on_emp_started() -> void:
	_scan_mounts()
	if _reinforcements != null:
		_reinforcements.tick(0.0, false)
	_travelling = false
	_show_thrust()


## The fortress's death started (after `suspend_ai()`): every mount is already powered down by the root; t16 cancels its beams and rings here.
func silence() -> void:
	pass


## A boss is never towed.
func accepts_tow() -> bool:
	return false


## §25 `movement`: `[translation_mode, spin_mode, reposition_period, travel_speed]`, the current boss phase's settings (0 while holding).
func movement_snapshot() -> Array:
	return [_translation_mode, _spin_mode, _reposition_period, _travel_speed]


## §25 `attacks`: `[cooldown_factor, max_concurrent_attacks, spoke_count, spoke_period, core_ring_armed, core_ring_period]`, the current boss phase's settings. t7 builds
## the two battery fields; the spoke and core-ring fields are zero / false until t16. The live battery set is not in it (a dead battery is §26, not a phase).
func attacks_snapshot() -> Array:
	return [_cooldown_factor, _max_attacks, 0, 0.0, false, 0.0]


func arena_snapshot() -> Array:
	return []


func reinforcements() -> BossReinforcements:
	return _reinforcements


# ── Spins (t16 drives the volley spin) ───────────────────────────────────────────────────────────

## A volley spin starts: [param direction] +1 / -1, or 0 for the next alternation (the first is +1). Turns only while engaged.
func begin_spin(direction: int = 0) -> void:
	var d := signi(direction) if direction != 0 else -_last_spin_dir
	_last_spin_dir = d
	_volley_dir = d


func end_spin() -> void:
	_volley_dir = 0


## True while a spin (volley or `critical`) owns the facing.
func spinning() -> bool:
	return is_engaged() and (_spin_mode == SPIN_CONTINUOUS or _volley_dir != 0)


## The running spin's direction (+1 / -1), 0 when none.
func spin_direction() -> int:
	if not spinning():
		return 0
	return _continuous_dir if _spin_mode == SPIN_CONTINUOUS else _volley_dir


# ── The facing rule ──────────────────────────────────────────────────────────────────────────────

## The sector the facing rule turns to the player: the stronger; a tie keeps the side presented (initially the stronger at the first call, south on a tie).
func present_side() -> StringName:
	var north := sector_strength(NORTH)
	var south := sector_strength(SOUTH)
	if north > south:
		_side = NORTH
	elif south > north or _side == &"":
		_side = SOUTH
	return _side


## [param side]'s live batteries, x 0.5 once its generator is destroyed.
func sector_strength(side: StringName) -> float:
	var batteries := NORTH_BATTERIES if side == NORTH else SOUTH_BATTERIES
	var live := 0
	for id in batteries:
		if _part_live(id):
			live += 1
	return float(live) * (1.0 if _part_live(NORTH_GENERATOR if side == NORTH else SOUTH_GENERATOR) else 0.5)


# ── Open Space combat zone ───────────────────────────────────────────────────────────────────────

## The station point after [param current] with the player expected at [param player_ahead]: of the `STATION_CANDIDATES` points on the circle of
## `station_ring_factor` x `zone_radius` round the anchor, those at least `reposition_min_step` from [param current], the one farthest from
## [param player_ahead] (the lowest index on a tie); none: [param current].
func pick_station_point(current: Vector2, player_ahead: Vector2) -> Vector2:
	var best := current
	var best_d := -INF
	var radius := config.station_ring_factor * config.zone_radius
	for k in STATION_CANDIDATES:
		var candidate := patrol_anchor + Vector2.from_angle(k * TAU / STATION_CANDIDATES) * radius
		if candidate.distance_to(current) < config.reposition_min_step:
			continue
		var d := candidate.distance_to(player_ahead)
		if d > best_d + PICK_EPS:
			best = candidate
			best_d = d
	return best


## Where an Open Space fortress holds (the anchor until the first reposition).
func station_point() -> Vector2:
	return _station_point


## Assault: the x the hull keeps.
func anchor_x() -> float:
	return _anchor_x


## True while the hull is under way (REPOSITION en route, RETURNING, ENTER, the bob): the thrusters burn full.
func is_travelling() -> bool:
	return _travelling


# ── Internals ────────────────────────────────────────────────────────────────────────────────────

func _resolve_mode() -> void:
	if _mode_known or not is_inside_tree():
		return
	_mode_known = true
	assault = EnemyWorld.arena(get_tree()) != null


func _set_movement(translation: StringName, spin: StringName, period: float, speed: float) -> void:
	_translation_mode = translation
	_spin_mode = spin
	_reposition_period = period
	_travel_speed = speed
	_reposition_left = 0.0  # a phase that repositions picks a new point on its first engaged tick


func _start() -> void:
	_started = true
	_resolve_mode()
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	_station_point = patrol_anchor
	_anchor_x = actor.global_position.x
	_thrusters = actor.get_node_or_null(^"Thrusters") as CanvasItem
	present_side()
	if assault:
		_enter(Phase.ENTER if actor.global_position.y < config.assault_hold_y else _engaged_phase())
	elif start_engaged:
		_enter(_engaged_phase())
	else:
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.home_radius)
		_enter(Phase.IDLE)


func _enter(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


## HOLD while the boss phase holds, else REPOSITION.
func _engaged_phase() -> Phase:
	return Phase.HOLD if _translation_mode == TRANSLATION_HOLD else Phase.REPOSITION


func _tick_open_space(delta: float, target: TargetInfo) -> void:
	if anchor_idle != null:
		match anchor_idle.update(delta, actor.global_position, target):
			AnchorIdle.State.IDLE:
				if phase != Phase.IDLE:
					_station_point = patrol_anchor
					_enter(Phase.IDLE)
			AnchorIdle.State.NOTICING:
				_enter(Phase.NOTICING)
			AnchorIdle.State.COMBAT:
				if not is_engaged():
					_enter(_engaged_phase())
			AnchorIdle.State.RETURNING:
				if phase != Phase.RETURNING:
					_station_point = patrol_anchor
					_enter(Phase.RETURNING)
	if is_engaged():
		_enter(_engaged_phase())
	_travelling = false
	match phase:
		Phase.IDLE:
			mover.hold_position(patrol_anchor, config.home_radius * 0.5, config.hold_speed)
		Phase.RETURNING:
			_travel_to(patrol_anchor, config.reposition_speed)
		Phase.REPOSITION:
			_reposition_left -= delta
			if _reposition_left <= CLOCK_EPS:
				_reposition_left = maxf(_reposition_left + _reposition_period, 0.0)
				if target.has_target:
					_station_point = pick_station_point(_station_point, target.predicted_position(config.reposition_lookahead))
			_travel_to(_station_point, _travel_speed)
		_:  # NOTICING, HOLD
			mover.hold_position(_station_point, config.hold_tolerance, config.hold_speed)
			_travelling = actor.global_position.distance_to(_station_point) > config.hold_tolerance


## Under way to [param point] at [param speed] until within `ARRIVED`, then held there.
func _travel_to(point: Vector2, speed: float) -> void:
	if actor.global_position.distance_to(point) > ARRIVED:
		mover.arrive(point, speed)
		_travelling = true
	else:
		mover.hold_position(point, config.hold_tolerance, config.hold_speed)


func _tick_assault(delta: float) -> void:
	var pos := actor.global_position
	var vx := clampf((_anchor_x - pos.x) * HOLD_GAIN, -config.assault_x_correct_speed, config.assault_x_correct_speed)
	if phase == Phase.ENTER:
		if pos.y < config.assault_hold_y:
			_travelling = true
			mover.request_velocity(Vector2(vx, config.assault_enter_speed))
			return
	_enter(_engaged_phase())  # leaving ENTER, or HOLD <-> REPOSITION on a boss phase
	var vy := 0.0
	if phase == Phase.HOLD:
		_travelling = false
		vy = clampf((config.assault_hold_y - pos.y) * HOLD_GAIN, -config.assault_enter_speed, config.assault_enter_speed)
	else:
		_travelling = true
		vy = _bob_velocity(pos.y, delta)
	mover.request_velocity(Vector2(vx, vy))


## The bob between `assault_hold_y` ± `assault_bob_amplitude` at the phase's speed: never past an end in one step, reversing on it.
func _bob_velocity(y: float, delta: float) -> float:
	var top := config.assault_hold_y - config.assault_bob_amplitude
	var bottom := config.assault_hold_y + config.assault_bob_amplitude
	if y >= bottom - BOB_END_EPS:
		_bob_dir = -1.0
	elif y <= top + BOB_END_EPS:
		_bob_dir = 1.0
	var speed := _travel_speed
	if delta > 0.0:
		var room := (bottom - y) if _bob_dir > 0.0 else (y - top)
		if room > 0.0:
			speed = minf(speed, room / delta)
	return _bob_dir * speed


## The one face request of the tick: a spin, the hub idle spin, or the facing rule.
func _face(target: TargetInfo) -> void:
	if mover == null:
		return
	var engaged := is_engaged()
	if engaged and _spin_mode == SPIN_CONTINUOUS:
		_spin(_continuous_dir, config.critical_spin_rate)
	elif engaged and _volley_dir != 0:
		_spin(_volley_dir, config.beam_spin_rate)
	elif not target.has_target:
		if assault:
			_spin(0, 0.0)  # hold the current facing
		else:
			_spin(1, config.idle_spin_rate)
	elif phase == Phase.IDLE:
		_spin(1, config.idle_spin_rate)
	else:
		var local := NORTH_BEARING if present_side() == NORTH else SOUTH_BEARING
		var pos := actor.global_position
		var bearing := (target.position - pos).angle()
		mover.max_turn_rate = config.assault_turn_rate if assault else config.turn_rate
		mover.face_toward(pos + Vector2.from_angle(bearing - local + EnemyMover.sprite_forward_angle_of(actor)) * FACE_REACH)


## Faces `SPIN_LEAD` rad ahead of the current facing in [param dir] (0: the current facing) with the mover capped at [param rate].
func _spin(dir: int, rate: float) -> void:
	var heading := actor.rotation + EnemyMover.sprite_forward_angle_of(actor)
	if dir != 0:
		mover.max_turn_rate = rate
	mover.face_toward(actor.global_position + Vector2.from_angle(heading + dir * SPIN_LEAD) * FACE_REACH)


func _show_thrust() -> void:
	if _thrusters != null:
		_thrusters.modulate.a = 1.0 if _travelling else THRUSTER_IDLE_ALPHA


func _part_live(id: StringName) -> bool:
	if _hull == null:
		return false
	var p := _hull.module(id)
	return p != null and not p.is_destroyed()


func _scan_mounts() -> void:
	for mount in _mounts():
		mount.scan(0.0)


## Every attached battery mount (a wreck's is UNPOWERED and only droops), in module order.
func _mounts() -> Array[TurretMount]:
	var out: Array[TurretMount] = []
	if _hull == null:
		return out
	for part in _hull.modules():
		for mount in part.mounts():
			if is_instance_valid(mount):
				out.append(mount)
	return out


## The batteries (plan §2.7.1; the Carrier's rule): engaged (HOLD / REPOSITION, both modes), not in an EMP window, in Assault the hull centre inside the view,
## and line of sight (on a physics frame only: a hand-ticked row counts it clear) or a mount that `fires_past_cover()` (the rocket battery). Each mount adds its
## own range, cone, cooldown, traverse arc and the `attack_gate()`. A dead battery's mount is UNPOWERED and only droops, so its lane stays quiet (§26). Not
## engaged, or no target: every mount scans.
func _tick_weapons(delta: float, target: TargetInfo) -> void:
	var mounts := _mounts()
	if not (target.has_target and is_engaged()):
		for mount in mounts:
			mount.scan(delta)
		return
	var sees := true
	if Engine.is_in_physics_frame():
		sees = can_see_player()
	var tree := get_tree()
	var in_view := not assault or not EnemyWorld.has_view_rect(tree) or EnemyWorld.view_rect(tree).has_point(actor.global_position)
	var emp: bool = actor.emp_seconds_left() > 0.0 if actor.has_method(&"emp_seconds_left") else false
	for mount in mounts:
		mount.tick(delta, target, in_view and not emp and (sees or mount.fires_past_cover()))
