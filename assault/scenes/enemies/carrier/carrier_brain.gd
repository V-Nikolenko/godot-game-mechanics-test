## The Carrier's brain (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.6.3; Phase 10 t6, task plan docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md).
## "A carrier does not chase the player; it controls space" (IDEAS §6.11). HANGARS (t8, §2.8): the brain ticks its `CarrierHangars` after the weapons
## (the schedule runs in Assault from the hull centre's first tick in the view, in Open Space while fighting) and PANIC entry deploys every live one.
##
## WEAPONS (t7, §2.7; task plan docs/plans/cmwafsrb900ajqs2yb5jcl5ij/3-plan.md). Every tick, after the movement: the side batteries and the bow cannon
## (each limited by its own traverse: a dead battery leaves its side safe), the missile bank (only beyond `missile_min_range`) and the anti-approach
## ring this brain owns and ticks (`pulse_trigger_range`, `pulse_cooldown` from each start). In Assault nothing fires with the hull centre outside the
## view. PANIC entry multiplies the battery cooldowns by `panic_battery_factor`, the pulse cooldown by `panic_pulse_factor`, and calls the t8
## emergency-deployment hook; the hull light strobes and the core light flashes red. An EMP or a rail silences every weapon at once (the ring ends).
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
## Half the side batteries' 150 degree traverse (§2.7): the fallback of `_battery_half_deg()`, which reads a live battery mount (t7). The sway aims a
## margin inside it.
const SWAY_ARC_HALF_DEG := 75.0
const SWAY_ARC_MARGIN_DEG := 10.0
## The sway's proportional gain (1/s): `gain · dt` < 1, so x approaches its target without overshoot.
const SWAY_GAIN := 4.0
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35
## PANIC strobe period of the hull and core lights (s): lit for the first half, dark for the second.
const PANIC_STROBE := 0.25
## The project clock rule: a countdown is over at <= this.
const CLOCK_EPS := 1e-6

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
## Weapons (t7), handed over by the root in `bind_weapons()`.
var _bow: TurretMount
var _bank: TurretMount
var _ring: EnergyRing
## Seconds until the pulse may start again; counts down every tick from the last `start()`.
var _pulse_left: float = 0.0
var _panic_applied: bool = false
var _light: StateLight
var _core_light: StateLight
## The hangars (t8), handed over by the root in `bind_hangars()`.
var _hangars: CarrierHangars
## Assault: true from the hull centre's first tick inside the view (the hangar schedule's clock runs from then).
var _view_entered: bool = false


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
	var target := TargetInfo.player(get_tree())
	if assault:
		_tick_cross(target)
	else:
		if anchor_idle != null and phase != Phase.PANIC:
			_tick_anchor_idle(delta, target)
		match phase:
			Phase.CRUISE: _tick_cruise()
			Phase.NOTICING: _tick_noticing(target)
			Phase.RETURNING: _tick_returning()
			Phase.SCREEN, Phase.IDLE: _tick_screen(delta, target)
			Phase.PANIC: _tick_panic(delta, target)
	_tick_weapons(delta, target)
	_tick_hangars(delta, target)


## Test seam and the one place a transition happens.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	if p == Phase.PANIC:
		anchor_idle = null
		_on_panic_entered()
	phase_changed.emit(p)


## Every weapon goes quiet at once (a shown telegraph never lands, the ring ends: the brain is not ticked for the window, so a live ring would hang
## frozen); then Open Space keeps the Phase 9 halt and Assault the crossing for the whole window.
func on_emp_started() -> void:
	_silence_weapons()
	_boost_through_emp()


## `Carrier.apply_emp()`: a later EMP extended the running window.
func on_emp_refreshed() -> void:
	_boost_through_emp()


func on_suspended() -> void:
	anchor_idle = null
	_silence_weapons()


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
	if _hangars != null:
		_hangars.assault = assault
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

func _tick_cross(target: TargetInfo) -> void:
	var pos := actor.global_position
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
		var half := deg_to_rad(_battery_half_deg() - SWAY_ARC_MARGIN_DEG)
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


# ── Weapons (t7) ────────────────────────────────────────────────────────────────────────────────

## Hands the brain its hull systems (the root, once every mount is built): the bow cannon, the missile bank and the anti-approach ring. The side
## batteries are read from the hull (`mounts_of`), so a wreck's UNPOWERED mount stays in the list and keeps drooping.
func bind_weapons(bow: TurretMount, bank: TurretMount, ring: EnergyRing) -> void:
	_bow = bow
	_bank = bank
	_ring = ring
	if actor != null:
		_light = actor.get_node_or_null(^"StateLight") as StateLight
	var core := _hull.module(&"core") if _hull != null else null
	if core != null:
		_core_light = core.get_node_or_null(^"Light") as StateLight


func bow_mount() -> TurretMount:
	return _bow


func missile_mount() -> TurretMount:
	return _bank


## `died` (the root): the ring ends in the same call.
func cancel_pulse() -> void:
	_kill_ring()


## The two side batteries' mounts, port first.
func battery_mounts() -> Array[TurretMount]:
	var out: Array[TurretMount] = []
	if _hull != null:
		out.append_array(_hull.mounts_of(GUN_PORT))
		out.append_array(_hull.mounts_of(GUN_STARBOARD))
	return out


func _mounts() -> Array[TurretMount]:
	var out := battery_mounts()
	if _bow != null:
		out.append(_bow)
	if _bank != null:
		out.append(_bank)
	return out


## Every mount is ticked with `can_fire = in view and (line of sight or fires past cover)` (the turret rule: never fire from outside the Assault view;
## line of sight only on the physics step, so a hand-ticked row counts it clear). The traverse refuses an off-arc target by itself, so a dead battery's
## side stays safe. The bank also needs the player beyond `missile_min_range`. Outside a fight every mount scans. The ring is ticked first, so a ring
## that ended this tick may start again in the same tick and its telegraph lasts its full length.
func _tick_weapons(delta: float, target: TargetInfo) -> void:
	_pulse_left -= delta
	if _ring != null:
		_ring.tick(delta)
	var fighting := target.has_target and (assault or phase == Phase.SCREEN or phase == Phase.PANIC)
	if not fighting:
		for mount in _mounts():
			mount.scan(delta)
	else:
		var sees := true
		if Engine.is_in_physics_frame():
			sees = can_see_player()
		var tree := get_tree()
		var in_view := not EnemyWorld.has_view_rect(tree) or EnemyWorld.view_rect(tree).has_point(actor.global_position)
		var dist := actor.global_position.distance_to(target.position)
		for mount in battery_mounts():
			mount.tick(delta, target, in_view and (sees or mount.fires_past_cover()))
		if _bow != null:
			_bow.tick(delta, target, in_view and (sees or _bow.fires_past_cover()))
		if _bank != null:
			_bank.tick(delta, target, in_view and dist > config.missile_min_range and (sees or _bank.fires_past_cover()))
		if in_view:
			_try_pulse(dist)
	_update_lights()


## The anti-approach pulse: with the player strictly inside `pulse_trigger_range` of the hull centre, the cooldown run and no ring in TELEGRAPH or
## EXPANDING, one ring from the hull centre, its gaps from the brain's rng. The cooldown counts from this start (halved in PANIC).
func _try_pulse(dist: float) -> void:
	if _ring == null or _pulse_left > CLOCK_EPS or dist >= config.pulse_trigger_range:
		return
	var p := _ring.phase()
	if p == EnergyRing.Phase.TELEGRAPH or p == EnergyRing.Phase.EXPANDING:
		return
	_ring.start(rng.randf_range(0.0, 360.0))
	_pulse_left = config.pulse_cooldown * (config.panic_pulse_factor if phase == Phase.PANIC else 1.0)


## PANIC entry, once: the batteries cool down faster, the pulse recharges twice as fast, the hangars deploy (t8).
func _on_panic_entered() -> void:
	if _panic_applied:
		return
	_panic_applied = true
	for mount in battery_mounts():
		mount.cooldown_seconds *= config.panic_battery_factor
	_pulse_left = minf(_pulse_left, config.pulse_cooldown * config.panic_pulse_factor)
	_emergency_deploy()


## Emergency deployment (§2.8): every live hangar that may still launch goes straight to LAUNCH, once (`CarrierHangars.emergency_deploy()`).
func _emergency_deploy() -> void:
	if _hangars != null:
		_hangars.emergency_deploy()


## An EMP or a rail: every mount scans (a telegraph never lands; a FIRE cut here still starts its cooldown), the ring ends, the lights go out.
func _silence_weapons() -> void:
	for mount in _mounts():
		mount.scan(0.0)
	_kill_ring()
	_set_light(StateLight.State.OFF)
	if _core_light != null:
		_core_light.set_state(StateLight.State.OFF)


## Ends the ring at once: a telegraph goes OFF, an expanding band is cancelled into FADE and the fade is finished on the spot (nothing ticks it after).
func _kill_ring() -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring.cancel()
	if _ring.phase() == EnergyRing.Phase.FADE:
		_ring.tick(_ring.fade_seconds)


## The hull light: CHARGING while a mount or the ring telegraphs, ARMED while one tracks, fires or cools down or the band expands, else OFF. In PANIC
## it strobes (ARMED / OFF), and a telegraph is never hidden by the strobe. The core light flashes red on the same strobe in PANIC.
func _update_lights() -> void:
	var charging := false
	var armed := false
	if _ring != null:
		charging = _ring.phase() == EnergyRing.Phase.TELEGRAPH
		armed = _ring.phase() == EnergyRing.Phase.EXPANDING
	for mount in _mounts():
		match mount.phase():
			TurretMount.Phase.TELEGRAPH:
				charging = true
			TurretMount.Phase.TRACK, TurretMount.Phase.FIRE, TurretMount.Phase.COOLDOWN:
				armed = true
	var want: int = StateLight.State.OFF
	var strobe_on := fmod(_phase_time, PANIC_STROBE) < PANIC_STROBE * 0.5
	if charging:
		want = StateLight.State.CHARGING
	elif phase == Phase.PANIC:
		want = StateLight.State.ARMED if strobe_on else StateLight.State.OFF
	elif armed:
		want = StateLight.State.ARMED
	_set_light(want)
	if _core_light != null:
		var core_want: int = StateLight.State.ARMED if phase == Phase.PANIC and strobe_on else StateLight.State.OFF
		if _core_light.get_state() != core_want:
			_core_light.set_state(core_want)


func _set_light(state: int) -> void:
	if _light != null and _light.get_state() != state:
		_light.set_state(state)


## Half a live battery's traverse (degrees): the sway's arc. The t6 constant is the fallback with no live battery mount.
func _battery_half_deg() -> float:
	for mount in battery_mounts():
		if mount.phase() != TurretMount.Phase.UNPOWERED:
			return mount.traverse_deg * 0.5
	return SWAY_ARC_HALF_DEG


# ── Hangars (t8) ────────────────────────────────────────────────────────────────────────────────

## Hands the brain its hangars (the root, in `_ready()`).
func bind_hangars(hangars: CarrierHangars) -> void:
	_hangars = hangars
	if _started:
		_hangars.assault = assault


func hangars() -> CarrierHangars:
	return _hangars


## The hangar schedule runs in Assault from the hull centre's first tick inside the view (latched), in Open Space while it fights (SCREEN or PANIC
## with a player). A door cycle already under way runs on either way (`CarrierHangars.tick`).
func _tick_hangars(delta: float, target: TargetInfo) -> void:
	if _hangars == null:
		return
	var active := false
	if assault:
		if not _view_entered:
			var tree := get_tree()
			_view_entered = EnemyWorld.has_view_rect(tree) and EnemyWorld.view_rect(tree).has_point(actor.global_position)
		active = _view_entered
	else:
		active = target.has_target and (phase == Phase.SCREEN or phase == Phase.PANIC)
	_hangars.tick(delta, active)
