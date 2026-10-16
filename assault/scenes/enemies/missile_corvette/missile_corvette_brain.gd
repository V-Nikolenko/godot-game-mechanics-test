## The Missile Corvette's brain (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.9 and §2.10; tasks t7 and t8,
## task plan docs/plans/cmv9szqlq001zqs2x6vi0nlxj/3-plan.md).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   closes to the held range along the line to the player; HOLD_ARC once within
##                           `range_tolerance` of it.
##   HOLD_ARC   [POSITION]   a broad orbit about the player at `held_range()` plus a slow drift of up to
##                           ±`range_drift`, reversing every `reversal_min`..`reversal_max` s. Inside `min_range` it
##                           blends `Steering.break_contact` into the orbit until back outside. The nose tracks the
##                           player (`face_toward`, capped by the mover's `max_turn_rate`). A salvo starts only when
##                           the player is inside the launch cone (`launch_cone_deg` round the nose) and
##                           `salvo_cooldown` has run out — getting behind it is the counterplay.
##   TELEGRAPH  [ATTACK]     `salvo_telegraph` s: StateLight CHARGING, tube lights ramp 0 -> 1, the arc at half speed.
##                           Open Space cancels it if the player gets more than 2x the half-cone off the nose; Assault
##                           never does (deadline bound).
##   SALVO      [ATTACK]     `salvo_size(kind)` rockets `salvo_gap` apart through `MissileCorvette.fire()`, each aimed
##                           at a predicted point (`_aim_point`). StateLight ARMED, tube lights flash per launch. Never
##                           COMMIT (shooters do not use it). Then HOLD_ARC, light OFF.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor, curve away from the player toward
##                           the nearest corridor edge at `exit_speed`, freed once outside the projectile rect (the
##                           Bomber's exit). A started TELEGRAPH / SALVO finishes first (<= `attack_window()`).
##   IDLE       [SEARCH]     Open Space only (t15): a slow ring orbit of `idle_radius` round `patrol_anchor`; it never fires.
##   NOTICING   [SEARCH]     a beat (`notice_time`): it stops and the nose turns to the player, then APPROACH.
##   RETURNING  [REPOSITION] `arrive` back at `patrol_anchor`, then IDLE. Never interrupts a TELEGRAPH or a SALVO
##                           (retried every tick). Hub idle (epic §2.16): `AnchorIdle` runs ahead of the phase dispatch on
##                           the corvette-player distance; `lose_radius` is above `preferred_range + range_drift +
##                           range_tolerance`, so the corvette's own arc never reads as losing the player.
##
## Attack gate (Assault): a TELEGRAPH starts only with `budget.remaining() >= attack_window() + ATTACK_GATE_MARGIN`
## (INF in Open Space), so a salvo it starts always ends inside its life.
##
## Rails: `on_suspended()` switches the light and the tubes off. The rocket fallback is a clock on the
## `MissileCorvette` root, because a rail stops this brain's ticks.
##
## Requests only (single-writer gate): the writes on the mover are `arrive`, `orbit`, `request_velocity`,
## `face_toward`, `max_speed` and `release_constraint()` on DISENGAGE.
class_name MissileCorvetteBrain
extends EnemyBrain

enum Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The attack gate asks for this much budget beyond the salvo's own length (s): a few ticks of rounding. The Ram
## Corvette's margin.
const ATTACK_GATE_MARGIN := 0.05
## The drift of the held range has a period drawn in this range (s).
const DRIFT_PERIOD_MIN := 6.0
const DRIFT_PERIOD_MAX := 9.0
## The arc's angular speed while telegraphing and firing, as a share of `orbit_angular_speed`.
const ATTACK_ARC_SCALE := 0.5
## Open Space cancels a telegraph once the player is outside this many times the launch cone.
const CANCEL_CONE_FACTOR := 2.0
## A Dumb choice becomes a Pursuit salvo this often, so the rotation is not fixed.
const DUMB_SWAP_CHANCE := 0.25
## The tube lights between two launches of a salvo (0..1); each launch flashes them to 1.
const SALVO_GLOW_FLOOR := 0.35
## `EnemyRocket.cruise_speed`'s script default, for a rocket scene that leaves it unset (px/s).
const ROCKET_CRUISE_DEFAULT := 520.0
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35

## Set by `missile_corvette.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: MissileCorvetteConfig = MissileCorvetteConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH
## Test seam: a spawned corvette starts already fighting, skipping the hub idle. Real hub spawns never set it. Assault
## ignores it: `EngagementBudget.active` decides there.
var start_engaged: bool = false
## The hub idle's ring centre. `Vector2.INF` (unset) means "not set": `_start()` then defaults it to the spawn position.
var patrol_anchor: Vector2 = Vector2.INF
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once, in `_start()`.
var anchor_idle: AnchorIdle
## This corvette's offset on the idle ring (rad), drawn from `rng` when the idle starts (never for an engaged one).
var idle_phase_offset: float = 0.0

## ±1: the way round the player the arc goes. Drawn on the first tick, flipped on every reversal.
var orbit_dir: float = 1.0
## Seconds until a salvo may start. Drawn in [`salvo_period_min`, `salvo_period_max`] on the first tick and again
## when a salvo ends; counts down in every phase.
var salvo_cooldown: float = 0.0
## The kind of the salvo being telegraphed or fired.
var salvo_kind: EnemyRocket.Kind = EnemyRocket.Kind.DUMB
## Salvos completed in this life.
var salvos_fired: int = 0

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _expiry_seen: bool = false
var _disengage_pending: bool = false
var _orbit_angle: float = 0.0
var _orbit_synced: bool = false
var _breaking: bool = false
var _arc_clock: float = 0.0
var _drift_period: float = DRIFT_PERIOD_MIN
var _drift_phase: float = 0.0
var _reversal_left: float = 0.0
var _forced_kind: int = -1
var _burst := BurstClock.new()
var _flash: float = 0.0
## The unit vector a Warhead pair is spread along, fixed once per salvo (at SALVO entry) so the pair is exactly
## `2 × warhead_offset` apart across it.
var _salvo_across: Vector2 = Vector2.RIGHT
## Each rocket kind's cruise speed (px/s), read once from its scene: the intercept's shot speed.
var _cruise: Dictionary = {}


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	salvo_cooldown = maxf(salvo_cooldown - delta, 0.0)
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		_on_budget_expired()
	if anchor_idle != null:
		_tick_anchor_idle(delta)
	match phase:
		Phase.IDLE: _tick_idle()
		Phase.NOTICING: _tick_noticing()
		Phase.RETURNING: _tick_returning()
		Phase.APPROACH: _tick_approach()
		Phase.HOLD_ARC: _tick_hold_arc(delta)
		Phase.TELEGRAPH: _tick_telegraph(delta)
		Phase.SALVO: _tick_salvo(delta)
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.HOLD_ARC:
			_set_light(StateLight.State.OFF)
			_set_glow(0.0)
		Phase.TELEGRAPH:
			salvo_kind = _roll_kind()
			_set_light(StateLight.State.CHARGING)
			_set_glow(0.0)
		Phase.SALVO:
			_burst.start(salvo_size(salvo_kind), config.salvo_gap)
			_salvo_across = _across_the_path()
			_flash = 0.0
			_set_light(StateLight.State.ARMED)
		Phase.DISENGAGE:
			_enter_disengage()
		Phase.IDLE, Phase.NOTICING, Phase.RETURNING:
			_enter_calm(p)
		_:
			_set_light(StateLight.State.OFF)
			_set_glow(0.0)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The root's rail clock fires the fallback rocket.
func on_suspended() -> void:
	_burst.stop()
	anchor_idle = null  # a rail owns the motion: no idle
	_set_light(StateLight.State.OFF)
	_set_glow(0.0)


## The range the corvette holds: the corridor is narrower than the open sky.
func held_range() -> float:
	return config.assault_preferred_range if budget != null and budget.active else config.preferred_range


## The rocket kind for a player `distance` px away moving at `player_speed`, of which `radial_speed` is along the
## corvette -> player line (> 0 = moving away). Checked in order: a close player gets Warheads; a fast one fleeing
## gets Pursuit rockets; a far one crossing gets Clusters; else Dumb rockets. Deterministic: the 1-in-4 swap of a
## Dumb choice is drawn outside it (`_roll_kind`).
func choose_kind(distance: float, player_speed: float, radial_speed: float) -> EnemyRocket.Kind:
	if distance < config.warhead_range:
		return EnemyRocket.Kind.WARHEAD
	if player_speed >= config.pursuit_flee_speed and radial_speed > 0.0:
		return EnemyRocket.Kind.PURSUIT
	var tangential := sqrt(maxf(player_speed * player_speed - radial_speed * radial_speed, 0.0))
	if distance >= config.cluster_min_range and tangential > absf(radial_speed):
		return EnemyRocket.Kind.CLUSTER
	return EnemyRocket.Kind.DUMB


## Rockets in a salvo of `kind`: the one place the count is read (review finding 15).
func salvo_size(kind: EnemyRocket.Kind) -> int:
	return config.warhead_salvo_count if kind == EnemyRocket.Kind.WARHEAD else config.salvo_count


## Test seam: the next TELEGRAPH fires `kind`, skipping the choice and the swap. Consumed.
func force_next_kind(kind: EnemyRocket.Kind) -> void:
	_forced_kind = kind


## True when `target_pos` lies within `cone_deg / 2` of the nose.
func in_launch_cone(target_pos: Vector2, cone_deg: float) -> bool:
	var to_target := target_pos - actor.global_position
	if to_target.length_squared() < 1e-6:
		return true
	return absf(_nose().angle_to(to_target)) <= deg_to_rad(cone_deg) * 0.5


## The longest a started salvo runs (s): its telegraph plus the gaps of the larger salvo. The budget defers to it,
## and the attack gate asks for it.
func attack_window() -> float:
	return config.salvo_telegraph + float(maxi(config.salvo_count, config.warhead_salvo_count) - 1) * config.salvo_gap


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	salvo_cooldown = rng.randf_range(config.salvo_period_min, config.salvo_period_max)
	_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	_drift_period = rng.randf_range(DRIFT_PERIOD_MIN, DRIFT_PERIOD_MAX)
	_drift_phase = 0.0 if rng.randf() < 0.5 else PI
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.idle_radius)
		idle_phase_offset = rng.randf_range(-MAX_IDLE_PHASE_OFFSET, MAX_IDLE_PHASE_OFFSET)
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER, EnemyRocket.Kind.WARHEAD]:
		_cruise[kind] = float(EnemyRocketScenes.export_of(kind, &"cruise_speed", ROCKET_CRUISE_DEFAULT))
	if anchor_idle != null:
		enter_phase(Phase.IDLE)


## The budget ran out: leave now, unless a salvo is being shown or fired, which finishes first.
func _on_budget_expired() -> void:
	if phase == Phase.TELEGRAPH or phase == Phase.SALVO:
		_disengage_pending = true
		return
	if phase != Phase.DISENGAGE:
		enter_phase(Phase.DISENGAGE)


# ── Hub idle (t15; epic §2.16) ────────────────────────────────────────────────────────────────────

## The meta-state that decides whether the corvette is patrolling, noticing or fighting, run once a tick ahead of the
## phase dispatch. A TELEGRAPH or a SALVO is never interrupted: the return is retried every tick until it has ended.
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
			# From NOTICING only: any other phase is already fighting.
			if phase == Phase.NOTICING:
				enter_phase(Phase.APPROACH)
		AnchorIdle.State.RETURNING:
			if phase != Phase.RETURNING and not _is_committed():
				enter_phase(Phase.RETURNING)


func _is_committed() -> bool:
	return phase == Phase.TELEGRAPH or phase == Phase.SALVO


## IDLE, NOTICING and RETURNING entry: forget the attack in progress and the arc, so the next fight starts clean. A
## corvette that has been calm does not fire the instant it notices the player: the salvo clock restarts on NOTICING.
func _enter_calm(p: Phase) -> void:
	_burst.stop()
	_set_light(StateLight.State.OFF)
	_set_glow(0.0)
	_orbit_synced = false
	_breaking = false
	if p == Phase.NOTICING:
		salvo_cooldown = rng.randf_range(config.salvo_period_min, config.salvo_period_max)


func _tick_idle() -> void:
	mover.orbit(patrol_anchor, config.idle_radius, idle_phase_offset + config.idle_speed * _phase_time, config.max_speed)


func _tick_noticing() -> void:
	mover.request_velocity(Vector2.ZERO)
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		mover.face_toward(target.position)


func _tick_returning() -> void:
	mover.arrive(patrol_anchor, config.max_speed)


## The attack gate: a salvo is started only when the budget leaves time to finish it (INF in Open Space).
func _attack_allowed() -> bool:
	return not _disengage_pending and (budget == null or budget.remaining() >= attack_window() + ATTACK_GATE_MARGIN)


func _tick_approach() -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	var pos := actor.global_position
	var away := pos - target.position
	if absf(away.length() - held_range()) <= config.range_tolerance:
		enter_phase(Phase.HOLD_ARC)
		return
	if away.length() < 1.0:
		away = Vector2.UP
	mover.arrive(target.position + away.normalized() * held_range(), config.max_speed)
	mover.face_toward(target.position)


func _tick_hold_arc(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	_arc_motion(delta, 1.0, target)
	if salvo_cooldown <= 0.0 and _attack_allowed() and in_launch_cone(target.position, config.launch_cone_deg):
		enter_phase(Phase.TELEGRAPH)


func _tick_telegraph(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		_arc_motion(delta, ATTACK_ARC_SCALE, target)
		if not budget.active and not in_launch_cone(target.position, config.launch_cone_deg * CANCEL_CONE_FACTOR):
			enter_phase(Phase.HOLD_ARC)
			return
	_set_glow(_phase_time / config.salvo_telegraph if config.salvo_telegraph > 0.0 else 1.0)
	if _phase_time >= config.salvo_telegraph - 1e-6:
		enter_phase(Phase.SALVO)
		_tick_salvo(0.0)  # the first rocket leaves on the telegraph's last tick


func _tick_salvo(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	if target.has_target and delta > 0.0:
		_arc_motion(delta, ATTACK_ARC_SCALE, target)
	var due := _burst.advance(delta)
	for _i in due:
		var index := _burst.shots_fired - due + _i
		(actor as MissileCorvette).fire(salvo_kind, _aim_point(index))
		_flash = 1.0
	if due == 0 and config.salvo_gap > 0.0:
		_flash = maxf(_flash - delta / config.salvo_gap, 0.0)
	_set_glow(lerpf(SALVO_GLOW_FLOOR, 1.0, _flash))
	if not _burst.is_running():
		_end_salvo()


func _end_salvo() -> void:
	salvos_fired += 1
	salvo_cooldown = rng.randf_range(config.salvo_period_min, config.salvo_period_max)
	if _disengage_pending:
		enter_phase(Phase.DISENGAGE)
	else:
		enter_phase(Phase.HOLD_ARC)


## The broad arc (HOLD_ARC, and at `scale` speed while telegraphing and firing).
func _arc_motion(delta: float, scale: float, target: TargetInfo) -> void:
	var pos := actor.global_position
	var offset := pos - target.position
	var distance := offset.length()
	if not _orbit_synced:
		_sync_orbit(offset)
	_arc_clock += delta
	_reversal_left -= delta
	if _reversal_left <= 0.0:
		orbit_dir = -orbit_dir
		_reversal_left = rng.randf_range(config.reversal_min, config.reversal_max)
	var radius := held_range() + config.range_drift * sin(TAU * _arc_clock / _drift_period + _drift_phase)
	var inside := distance < config.min_range
	if _breaking and not inside:
		_sync_orbit(offset)
	_breaking = inside
	_orbit_angle += orbit_dir * config.orbit_angular_speed * scale * delta
	var v := Steering.orbit(pos, target.position, radius, _orbit_angle, config.max_speed)
	if inside:
		# The break-off continues the way the arc turns. `break_contact`'s `side` is `away.orthogonal()` (a -90°
		# turn) for +1, while the orbit's +1 is a +90° turn, so the arc's own sense is `-orbit_dir` (3-plan.md §2.10.2
		# "side = orbit direction"; with the literal +1 the two laterals oppose and a 350 px/s rusher gets 100 px closer).
		v += Steering.break_contact(pos, target.position, target.velocity, -orbit_dir, config.max_speed)
	mover.request_velocity(v)
	mover.face_toward(target.position)


func _sync_orbit(offset: Vector2) -> void:
	_orbit_synced = true
	_orbit_angle = offset.angle() if offset.length_squared() > 1e-6 else -PI / 2.0


## The kind of the next salvo: forced (tests), else `choose_kind` with a 1-in-4 swap of Dumb for Pursuit.
func _roll_kind() -> EnemyRocket.Kind:
	if _forced_kind >= 0:
		var forced := _forced_kind as EnemyRocket.Kind
		_forced_kind = -1
		return forced
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return EnemyRocket.Kind.DUMB
	var line := target.position - actor.global_position
	var radial := target.velocity.dot(line.normalized()) if line.length_squared() > 1e-6 else 0.0
	var kind := choose_kind(line.length(), target.velocity.length(), radial)
	if kind == EnemyRocket.Kind.DUMB and rng.randf() < DUMB_SWAP_CHANCE:
		kind = EnemyRocket.Kind.PURSUIT
	return kind


## Where rocket `index` of the salvo is aimed (§2.10.7), from a fresh snapshot and the tube it will leave from.
func _aim_point(index: int) -> Vector2:
	var target := TargetInfo.player(get_tree())
	var tube := (actor as MissileCorvette).next_tube_position()
	if not target.has_target:
		return tube + _nose() * 600.0
	var hit := target.intercept(tube, float(_cruise.get(salvo_kind, 0.0)))
	match salvo_kind:
		EnemyRocket.Kind.DUMB:
			return target.predicted_position(float(hit.time) + index * config.salvo_lead_step)
		EnemyRocket.Kind.WARHEAD:
			var side := 1.0 if index % 2 == 0 else -1.0
			return (hit.point as Vector2) + _salvo_across * config.warhead_offset * side
		_:
			return hit.point


## Across the player's path: the perpendicular of its velocity, or of the line of sight from the hull's centre while
## it is still. Unit length.
func _across_the_path() -> Vector2:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return Vector2.RIGHT
	var across := target.velocity.orthogonal()
	if across.length_squared() < 1e-6:
		across = (target.position - actor.global_position).orthogonal()
	return across.normalized() if across.length_squared() > 1e-6 else Vector2.RIGHT


func _enter_disengage() -> void:
	_burst.stop()
	_set_light(StateLight.State.OFF)
	_set_glow(0.0)
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The curve's rate is
## capped by what the mover's acceleration can follow at exit speed.
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
	return _nose()


## The direction the hull's nose points (the launch tubes face it).
func _nose() -> Vector2:
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)


func _set_glow(amount: float) -> void:
	if actor is MissileCorvette:
		(actor as MissileCorvette).set_tube_glow(amount)


## The telegraphed phases are never moved by an ally (`BaseEnemy.accept_tow`): the tubes are glowing or firing at the
## points the player was shown.
func accepts_tow() -> bool:
	match phase:
		Phase.TELEGRAPH, Phase.SALVO:
			return false
	return true
