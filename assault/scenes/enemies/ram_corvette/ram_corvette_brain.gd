## The Ram Corvette's brain (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.6.2; task plan
## docs/plans/cmuyk2qqb0091oa2xy7yn9sxa/3-plan.md).
##
## The predicted-intercept charge: line up on where the player WILL be, wind up with the plates glowing,
## ram in a straight line through and `overshoot` past that point, swing round in a wide arc and go again.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   at `cruise_speed` until within `engage_range`. Open Space: a plain intercept.
##                           Assault: toward a point `assault_side_offset` beside and above/below the
##                           player, so the charge line is diagonal across the corridor (R4.35).
##   LINE_UP    [POSITION]   brake, turn the nose onto the aim (P̂ = the player `clamped_lead_time` ahead),
##                           at most `line_up_cap`. The charge follows the AIM, never the nose.
##   WIND_UP    [TELEGRAPH]  a crawl along the aim, light CHARGING, every live plate's glow ramping to 1 (from
##                           whatever the last charge's fading glow left, so it never snaps). The aim
##                           tracks P̂ for the first `windup_track_fraction`, then FREEZES (`charge_dir`,
##                           `charge_point`); nothing re-aims it after that.
##   CHARGE     [ATTACK]     `mover.boost` along `charge_dir` to `overshoot` past `charge_point`, never
##                           longer than `charge_max_time`. Light COMMIT. Exposed: contact armed.
##   WIDE_TURN  [REPOSITION] the heading turns toward the player at `wide_turn_rate` while cruising.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor and leave - straight
##                           along the charge heading after a charge, else curving to the nearest edge.
##   STAGGER    [-]          a plate broke during LINE_UP / WIND_UP: the charge is cancelled, the ship
##                           stops for `stagger_seconds`, then lines up again (IDEAS §16 "heavy weapons
##                           stagger"). A plate broken during CHARGE changes nothing.
##   IDLE       [SEARCH]     Open Space only (t19): a slow ring orbit of `idle_radius` round `patrol_anchor`; it never
##                           lines up, winds up or charges.
##   NOTICING   [SEARCH]     a beat (`notice_time`): the light blinks once and it faces the player, then APPROACH.
##   RETURNING  [REPOSITION] `arrive` back at `patrol_anchor`, then IDLE. Never interrupts a WIND_UP or a CHARGE
##                           (retried every tick).
## IDLE / NOTICING / RETURNING are appended after STAGGER so these values do not move. Hub idle (epic §2.10):
## `AnchorIdle` runs ahead of the phase dispatch on the actor-player distance; `lose_radius` is above the distance a
## charge and its wide turn open (`RamCorvetteConfig`), so the cycle never reads as losing the player.
##
## Attack gate: LINE_UP is entered only with `budget.remaining() >= line_up_cap` (INF in Open Space), so once
## it lines up, WIND_UP starts before the budget expires. Budget expiry by phase: APPROACH / LINE_UP /
## WIDE_TURN disengage that tick; WIND_UP / CHARGE / STAGGER set `disengage_pending` and leave when that
## phase ends (the deferral is at most `wind_up_seconds + charge_max_time`).
##
## Exposed (`on_exposed()`, from `RamCorvette._expose` on `armor_broken`): `exposed_cruise_speed` and
## `exposed_charge_speed`; the ARMOR contact is disarmed except during CHARGE; in APPROACH and WIDE_TURN it
## strafes out of the player's aim line (`evade_nudge`) while aimed at.
##
## Rails: `on_suspended()` only switches the light off. The rail fallback is the ARMOR contact profile
## itself, armed for life (`BaseEnemy.suspend_ai()`); there is nothing to fire.
##
## Requests only (single-writer gate): the writes on the mover are the fields `max_speed` and `braking` (the hard
## `config.braking` only on entry to LINE_UP, WIND_UP and STAGGER) and `release_constraint()`.
class_name RamCorvetteBrain
extends EnemyBrain

enum Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE, STAGGER, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## APPROACH aims at the player this many seconds ahead (s).
const INTERCEPT_LOOKAHEAD := 0.5
## Assault side choice: an x difference under this is a tie (px; review N5).
const SIDE_TIE := 8.0
## Assault side choice: the offset point should stay this far inside the corridor on x (px).
const SIDE_EDGE_MARGIN := 64.0
## WIDE_TURN gives up turning after this long (s): a player circling inside the turn could hold it forever.
const WIDE_TURN_CAP := 4.0
## Float slack on the phase caps, so 30 summed 1/60 s ticks count as 0.5 s.
const TIME_EPS := 0.0001
## The attack gate asks for this much budget beyond `line_up_cap` (s): a few ticks of rounding, so a LINE_UP
## always reaches WIND_UP before the budget (updated before the phase logic) expires. The Swarm Drone precedent.
const ATTACK_GATE_MARGIN := 0.05
## `idle_phase_offset` is drawn from ±this (rad).
const MAX_IDLE_PHASE_OFFSET := 0.35

## Set by `ram_corvette.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: RamCorvetteConfig = RamCorvetteConfig.new()
## The ship's ARMOR profile, wired by `ram_corvette.gd`. Null on a bare brain.
var contact: ContactProfile
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH
## True once every plate is gone.
var exposed: bool = false
## Set when the budget expired in a committed phase (WIND_UP / CHARGE / STAGGER); acted on at its end.
var disengage_pending: bool = false
## Latched by `on_suspended()`: a rail drives the ship, so plate breaks and exposure change nothing here.
var suspended: bool = false
## The hub idle's ring centre. `Vector2.INF` (unset) means "not set": `_start()` then defaults it to the spawn
## position.
var patrol_anchor: Vector2 = Vector2.INF
## Test seam (t19): a spawned Corvette starts already fighting, the only behaviour that existed before the hub idle.
## Real spawns (`SectorHub`) never set it. Assault ignores it: `EngagementBudget.active` decides there.
var start_engaged: bool = false
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once, in `_start()`.
var anchor_idle: AnchorIdle
## This Corvette's offset on the idle ring (rad), drawn from `rng` when the idle starts (never for an engaged one).
var idle_phase_offset: float = 0.0

## Assault approach side: +1 = the player's +x side, -1 = its -x side. 0 until chosen (or in Open Space).
var side: float = 0.0
## Assault approach: +1 below the player, -1 above.
var vertical_side: float = -1.0
## LINE_UP / WIND_UP: the current aim point (P̂, corridor-clamped in Assault) and direction.
var aim_point: Vector2 = Vector2.ZERO
var aim_dir: Vector2 = Vector2.ZERO
## WIND_UP: true from the freeze on.
var aim_frozen: bool = false
## Latched at the freeze; the charge's line and the point it overshoots.
var charge_dir: Vector2 = Vector2.ZERO
var charge_point: Vector2 = Vector2.ZERO
## Where the last charge started, its boost duration, and when (s since spawn).
var charge_origin: Vector2 = Vector2.ZERO
var charge_duration: float = 0.0
var charge_started_at: float = -1.0
## Charges started this life.
var charges: int = 0
## Seconds since spawn at the first WIND_UP (-1 before it).
var first_wind_up_at: float = -1.0
## WIDE_TURN's commanded heading.
var turn_dir: Vector2 = Vector2.ZERO
## The plates' glow, 0..1.
var glow: float = 0.0
## The exposed strafe offered to the mover this tick (zero when not evading).
var evade_nudge: Vector2 = Vector2.ZERO

var _started: bool = false
var _phase_time: float = 0.0
var _life: float = 0.0
var _expiry_seen: bool = false
var _aim_distance: float = 0.0
var _straight_exit: bool = false
var _wind_up_glow_from: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	_life += delta
	evade_nudge = Vector2.ZERO
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		_on_budget_expired()
	if anchor_idle != null:
		_tick_anchor_idle(delta)
	match phase:
		Phase.IDLE: _tick_idle()
		Phase.NOTICING: _tick_noticing()
		Phase.RETURNING: _tick_returning()
		Phase.APPROACH: _tick_approach(delta)
		Phase.LINE_UP: _tick_line_up(delta)
		Phase.WIND_UP: _tick_wind_up(delta)
		Phase.CHARGE: _tick_charge()
		Phase.WIDE_TURN: _tick_wide_turn(delta)
		Phase.STAGGER: _tick_stagger()
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	var was := phase
	phase = p
	_phase_time = 0.0
	if was == Phase.CHARGE and p != Phase.CHARGE and exposed:
		_set_armed(false)
	# The hard brake only while it is stopping to aim; the post-charge slow-down and the wide turn keep the
	# mover's own `acceleration` (0 = same as acceleration).
	var stopping := p == Phase.LINE_UP or p == Phase.WIND_UP or p == Phase.STAGGER
	mover.braking = config.braking if stopping else 0.0
	match p:
		Phase.APPROACH:
			_set_light(StateLight.State.OFF)
			side = 0.0
		Phase.LINE_UP:
			_set_light(StateLight.State.OFF)
			aim_frozen = false
		Phase.WIND_UP:
			_enter_wind_up()
		Phase.CHARGE:
			_enter_charge()
		Phase.WIDE_TURN:
			_set_light(StateLight.State.OFF)
			turn_dir = charge_dir if charge_dir != Vector2.ZERO else _heading()
			mover.max_speed = cruise_speed()
		Phase.STAGGER:
			_set_glow(0.0)
			_set_light(StateLight.State.OFF)
			_blink()
		Phase.DISENGAGE:
			_enter_disengage()
		Phase.IDLE, Phase.RETURNING:
			_enter_calm()
		Phase.NOTICING:
			_enter_calm()
			_blink()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The ARMOR profile stays armed; nothing to fire.
func on_suspended() -> void:
	suspended = true
	anchor_idle = null  # a rail owns the motion: no idle
	_set_light(StateLight.State.OFF)


## Called by `RamCorvette` when one plate breaks. Cancels a line-up or a wind-up; nothing else. Ignored on a rail.
func on_plate_broken() -> void:
	if suspended:
		return
	if phase == Phase.LINE_UP or phase == Phase.WIND_UP:
		enter_phase(Phase.STAGGER)


## Called by `RamCorvette._expose` (after `armor_broken`): faster, harder-hitting, contact only in CHARGE.
## Ignored on a rail: the rail's contact stays armed for life (epic §2.6.3).
func on_exposed() -> void:
	if exposed or suspended:
		return
	exposed = true
	if phase != Phase.CHARGE:
		_set_armed(false)
	if phase == Phase.APPROACH or phase == Phase.WIDE_TURN:
		mover.max_speed = cruise_speed()
	_blink()


func cruise_speed() -> float:
	return config.exposed_cruise_speed if exposed else config.cruise_speed


func charge_speed() -> float:
	return config.exposed_charge_speed if exposed else config.charge_speed


## The attack gate: a line-up is started only when the budget leaves time for it (INF in Open Space).
func can_attack() -> bool:
	return budget == null or budget.remaining() >= config.line_up_cap + ATTACK_GATE_MARGIN


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.idle_radius)
		idle_phase_offset = rng.randf_range(-MAX_IDLE_PHASE_OFFSET, MAX_IDLE_PHASE_OFFSET)
		enter_phase(Phase.IDLE)


func _on_budget_expired() -> void:
	match phase:
		Phase.DISENGAGE:
			pass
		Phase.WIND_UP, Phase.CHARGE, Phase.STAGGER:
			disengage_pending = true
		_:
			enter_phase(Phase.DISENGAGE)


# ── Hub idle (t19; epic §2.10) ────────────────────────────────────────────────────────────────────

## The meta-state that decides whether the Corvette is patrolling, noticing or fighting, run once a tick ahead of the
## phase dispatch. A WIND_UP or a CHARGE is never interrupted: the return is retried every tick until it has ended.
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
	return phase == Phase.WIND_UP or phase == Phase.CHARGE


## IDLE, NOTICING and RETURNING entry: forget the attack in progress - no glow, no light, no aim.
func _enter_calm() -> void:
	_set_light(StateLight.State.OFF)
	_set_glow(0.0)
	aim_frozen = false
	mover.max_speed = cruise_speed()


func _tick_idle() -> void:
	mover.orbit(patrol_anchor, config.idle_radius, idle_phase_offset + config.idle_speed * _phase_time, cruise_speed())


func _tick_noticing() -> void:
	mover.request_velocity(Vector2.ZERO)
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		mover.face_toward(target.position)


func _tick_returning() -> void:
	mover.arrive(patrol_anchor, cruise_speed())


# ── APPROACH ──────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float) -> void:
	_fade_glow(delta)
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var pos := actor.global_position
	if pos.distance_to(target.position) <= config.engage_range and can_attack():
		enter_phase(Phase.LINE_UP)
		_tick_line_up(0.0)
		return
	mover.max_speed = cruise_speed()
	var rect := _corridor()
	if rect.has_area() and config.assault_side_offset > 0.0:
		if side == 0.0:
			_choose_side(target, rect)
		var offset := Vector2(side, vertical_side) * config.assault_side_offset
		mover.seek(target.predicted_position(INTERCEPT_LOOKAHEAD) + offset, cruise_speed())
	else:
		mover.intercept(target, cruise_speed(), INTERCEPT_LOOKAHEAD)
	_evade(target)


## Assault: the side the Corvette is on (review N5's tie-break: the roomier corridor half, then a coin),
## flipped when its offset point would sit within SIDE_EDGE_MARGIN of the corridor's edge and the other
## would not; above the player unless it is below it.
func _choose_side(target: TargetInfo, rect: Rect2) -> void:
	var pos := actor.global_position
	var dx := pos.x - target.position.x
	var room := rect.get_center().x - target.position.x
	if absf(dx) >= SIDE_TIE:
		side = signf(dx)
	elif absf(room) >= SIDE_TIE:
		side = signf(room)
	else:
		side = 1.0 if rng.randf() < 0.5 else -1.0
	var inner := rect.grow(-SIDE_EDGE_MARGIN)
	var here := target.position.x + side * config.assault_side_offset
	var there := target.position.x - side * config.assault_side_offset
	var here_ok := here >= inner.position.x and here <= inner.end.x
	var there_ok := there >= inner.position.x and there <= inner.end.x
	if not here_ok and there_ok:
		side = -side
	vertical_side = 1.0 if pos.y > target.position.y else -1.0


## Exposed only, in APPROACH and WIDE_TURN: while the player's nose points at it (within `evade_cone_deg`,
## inside `evade_range`), offer a strafe away from the player's aim line.
func _evade(target: TargetInfo) -> void:
	if not exposed or not target.has_target:
		return
	var pos := actor.global_position
	var to_me := pos - target.position
	var d := to_me.length()
	if d >= config.evade_range or d <= 0.0 or target.facing == Vector2.ZERO:
		return
	if absf(target.facing.angle_to(to_me)) > deg_to_rad(config.evade_cone_deg):
		return
	var lateral := to_me - target.facing * to_me.dot(target.facing)
	var nudge := Steering.strafe(pos, target.position, 1.0, config.evade_speed)
	if lateral.length_squared() > 0.0001 and nudge.dot(lateral) < 0.0:
		nudge = -nudge
	evade_nudge = nudge
	mover.add_nudge(nudge)


# ── LINE_UP / WIND_UP ─────────────────────────────────────────────────────────────────────────────

func _tick_line_up(delta: float) -> void:
	_fade_glow(delta)
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		_update_aim(target)
	mover.request_velocity(Vector2.ZERO)
	if aim_dir != Vector2.ZERO:
		mover.face_toward(actor.global_position + aim_dir * 100.0)
	var lined_up := aim_dir != Vector2.ZERO \
			and absf(_nose().angle_to(aim_dir)) <= deg_to_rad(config.line_up_tolerance_deg) \
			and mover.own_velocity().length() <= config.crawl_speed
	if lined_up or _phase_time >= config.line_up_cap - TIME_EPS:
		enter_phase(Phase.WIND_UP)


## P̂: the player `clamped_lead_time` ahead at the current charge speed, kept inside the corridor.
func _predicted_aim(target: TargetInfo) -> Vector2:
	var pos := actor.global_position
	var lead := Steering.clamped_lead_time(pos.distance_to(target.position), charge_speed(),
			config.lead_min, config.lead_max)
	var p := target.predicted_position(lead)
	var rect := _corridor()
	if rect.has_area():
		p = p.clamp(rect.position, rect.end)
	return p


func _update_aim(target: TargetInfo) -> void:
	aim_point = _predicted_aim(target)
	var to := aim_point - actor.global_position
	if to.length_squared() > 0.0001:
		aim_dir = to.normalized()
		_aim_distance = to.length()


func _enter_wind_up() -> void:
	aim_frozen = false
	if first_wind_up_at < 0.0:
		first_wind_up_at = _life
	if aim_dir == Vector2.ZERO:
		aim_dir = _heading()
	_set_light(StateLight.State.CHARGING)
	_wind_up_glow_from = glow


func _tick_wind_up(delta: float) -> void:
	var pos := actor.global_position
	if not aim_frozen:
		var target := TargetInfo.player(get_tree())
		if target.has_target:
			var p := _predicted_aim(target)
			aim_point = p
			aim_dir = Steering.turn_toward(aim_dir, p - pos, config.windup_track_rate, delta)
			_aim_distance = pos.distance_to(p)
		if _phase_time >= config.wind_up_seconds * config.windup_track_fraction - TIME_EPS:
			aim_frozen = true
			charge_dir = aim_dir
			charge_point = pos + aim_dir * _aim_distance
	mover.request_velocity(aim_dir * config.crawl_speed)
	mover.face_toward(pos + aim_dir * 100.0)
	_set_glow(lerpf(_wind_up_glow_from, 1.0, _phase_time / config.wind_up_seconds))
	if _phase_time >= config.wind_up_seconds - TIME_EPS:
		enter_phase(Phase.CHARGE)


# ── CHARGE / WIDE_TURN ────────────────────────────────────────────────────────────────────────────

func _enter_charge() -> void:
	var pos := actor.global_position
	if not aim_frozen:  # entered through the seam: freeze whatever the aim is now
		aim_frozen = true
		charge_dir = aim_dir if aim_dir != Vector2.ZERO else _heading()
		charge_point = pos + charge_dir * _aim_distance
	var speed := charge_speed()
	var along := maxf((charge_point - pos).dot(charge_dir), 0.0)
	charge_duration = minf((along + config.overshoot) / speed, config.charge_max_time) if speed > 0.0 else 0.0
	charge_origin = pos
	charge_started_at = _life
	charges += 1
	mover.boost(charge_dir, speed, charge_duration)
	_set_glow(1.0)
	_set_light(StateLight.State.COMMIT)
	if exposed:
		_set_armed(true)


func _tick_charge() -> void:
	if mover.is_boosting():
		return
	if disengage_pending:
		_straight_exit = true
		enter_phase(Phase.DISENGAGE)
	else:
		enter_phase(Phase.WIDE_TURN)
		_tick_wide_turn(0.0)


func _tick_wide_turn(delta: float) -> void:
	var target := TargetInfo.player(get_tree())
	_fade_glow(delta)
	mover.max_speed = cruise_speed()
	if not target.has_target:
		mover.request_velocity(turn_dir * cruise_speed())
		return
	var pos := actor.global_position
	var to_player := target.position - pos
	turn_dir = Steering.turn_toward(turn_dir, to_player, config.wide_turn_rate, delta)
	mover.request_velocity(turn_dir * cruise_speed())
	_evade(target)
	var facing_player := absf(turn_dir.angle_to(to_player)) <= deg_to_rad(config.wide_turn_exit_angle_deg)
	if facing_player or _phase_time >= WIDE_TURN_CAP:
		if to_player.length() <= config.engage_range and can_attack():
			enter_phase(Phase.LINE_UP)
		else:
			enter_phase(Phase.APPROACH)


# ── STAGGER ───────────────────────────────────────────────────────────────────────────────────────

func _tick_stagger() -> void:
	mover.request_velocity(Vector2.ZERO)
	if _phase_time < config.stagger_seconds - TIME_EPS:
		return
	if disengage_pending:
		enter_phase(Phase.DISENGAGE)
		return
	var target := TargetInfo.player(get_tree())
	if target.has_target and actor.global_position.distance_to(target.position) <= config.engage_range and can_attack():
		enter_phase(Phase.LINE_UP)
	else:
		enter_phase(Phase.APPROACH)


# ── DISENGAGE ─────────────────────────────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
	disengage_pending = false
	_set_glow(0.0)
	_set_light(StateLight.State.OFF)
	mover.release_constraint()
	mover.max_speed = config.exit_speed
	if _straight_exit:
		return
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). After a charge
## it flies straight on along `charge_dir`; otherwise the curve's rate is capped by what the mover's
## acceleration can follow at exit speed.
func _tick_disengage(delta: float) -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	if _straight_exit:
		mover.request_velocity(charge_dir * config.exit_speed)
		return
	var rate := config.max_turn_rate
	if config.exit_speed > 0.0:
		rate = minf(rate, config.acceleration / config.exit_speed)
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, rate, delta)
	mover.request_velocity(dir * config.exit_speed)


# ── Helpers ───────────────────────────────────────────────────────────────────────────────────────

## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return _nose()


## The direction the nose points.
func _nose() -> Vector2:
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


## The corridor rect while the mover holds a constraint with one; `Rect2()` otherwise.
func _corridor() -> Rect2:
	if mover == null or mover.constraint == null:
		return Rect2()
	return mover.constraint.inner_rect()


## After a charge the glow fades at `1 / glow_fade_seconds` per second through WIDE_TURN, APPROACH and LINE_UP; a
## wind-up then ramps it from wherever it is to 1, so it never snaps.
func _fade_glow(delta: float) -> void:
	if glow <= 0.0:
		return
	_set_glow(glow - delta / config.glow_fade_seconds if config.glow_fade_seconds > 0.0 else 0.0)


func _set_glow(amount: float) -> void:
	glow = clampf(amount, 0.0, 1.0)
	if actor != null and actor.has_method("set_plate_glow"):
		actor.set_plate_glow(glow)


func _set_armed(armed: bool) -> void:
	if contact != null:
		contact.set_armed(armed)


func _set_light(state: int) -> void:
	var light := _light()
	if light != null:
		light.set_state(state)


func _blink() -> void:
	var light := _light()
	if light != null:
		light.blink_once()


func _light() -> StateLight:
	return actor.get_node_or_null("StateLight") as StateLight if actor != null else null


## A committed or telegraphed phase is never moved by an ally (`BaseEnemy.accept_tow`).
func accepts_tow() -> bool:
	match phase:
		Phase.WIND_UP, Phase.CHARGE:
			return false
	return true
