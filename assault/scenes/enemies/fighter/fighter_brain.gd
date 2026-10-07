## The Fighter's brain: attack runs (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4, §2.8;
## task plan docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md, Revision 2 — read it for the numbers).
##
## A pass is a bearing `b` (the side the run comes from), a run direction `u = −b` and a lane `l ⟂ u`
## (the side and distance it passes the player at). The run starts at `S = P̂ + b·standoff_radius + l`,
## on the pass line `P̂ + l + u·t`, so the closest approach equals `|l|`.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   a Dubins lead-in to the first pass's start S, arriving pointing along the
##                           run. Inside the breach radius (derived from S) it starts a FRONTAL-shaped
##                           pass from where it is instead of circling the player.
##   RUN_IN     [ATTACK]     path following along the pass line, `lookahead` ahead of the fighter's own
##                           projection; the lane's sideways velocity is fed forward. Ends at the
##                           closest approach, `(P̂ − X)·u < 0`. Burst opportunity (a).
##   EXTEND     [ATTACK]     holds the heading until ≥ 350 px from the player (0.6–1.5 s).
##   TURN       [REPOSITION] the visible wide turn: back in toward the player at full rate until the
##                           nose is on it (burst opportunity (b), the snapshot), then a break-away
##                           arc — the first arc of the REPOSITION path.
##   REPOSITION [REPOSITION] the rest of a Dubins lead-in to the next S, clear of
##                           `reposition_min_radius`; the epic's ring routing when no clear path
##                           exists. After `passes` passes, Open Space loiters at S for
##                           `regroup_seconds` first.
##   DISENGAGE  [DISENGAGE]  Assault only: budget expiry or `passes` done (deferred to the end of a
##                           running burst); release the corridor, curve out of the world rect, free.
##   IDLE       [SEARCH]     Open Space only (t12): a slow ring orbit round `patrol_anchor`, no shots.
##   NOTICING   [SEARCH]     a beat: the light blinks once and the fighter faces the player, then APPROACH.
##   RETURNING  [REPOSITION] `arrive` back at `patrol_anchor` (never interrupts a burst), then IDLE.
##
## Hub idle (epic §2.10, X2): `AnchorIdle` on the squad's shared `patrol_anchor`, the Swarm Drone's shape.
## Assault (`EngagementBudget.active`) and the `start_engaged` test seam skip it and start in APPROACH.
##
## The pass is re-derived every tick until RUN_IN (so it follows the player's heading and the squad
## role) and latched from RUN_IN entry to EXTEND's end, lead time included.
##
## Squads (epic §2.5; task plan docs/plans/cmulwkar300bxqj2xgtk6jyu3/3-plan.md). With a squad of two or
## more, `SquadController.role_of()` — read every tick, never cached — picks the pass kind: LEAD a
## FRONTAL pass, FLANK_LEFT / FLANK_RIGHT the pincer on two lanes, REAR a dry pass on an outer lane
## from `rear_standoff_radius`. The LEAD opens `attack_window_open` on RUN_IN entry and closes it on its
## own EXTEND entry. FLANKs and REARs fly to their S and hold there; a FLANK answers each window once
## (`_answered_window`, reset on reading the window closed) or goes after `flank_wait_max`; a REAR
## answers every other window and never fires. The role a pass was flown in (`pass_role`) is latched
## with it, so a new role's pass kind is only ever reached through TURN and REPOSITION. A squad of one
## is a solo fighter (t8b's alternation).
##
## Weapons are an independent layer ticked before the phase logic: at most one burst per leg (leg A =
## RUN_IN/EXTEND, leg B = TURN), `min_burst_period` apart; the mode is chosen by distance with
## hysteresis and latched for the burst; FORWARD needs the nose on the player and, while it fires,
## the nose (not the path) is held on the player. A `burst_telegraph` CHARGING light precedes every
## burst.
##
## Rails (§2.8, X1): `on_suspended()` hands `AttackController` back to self-timed legacy fire.
## `aim_mode` is read there and nowhere else: an AI fighter ignores it.
##
## Requests only (single-writer gate): the field writes on the mover are `max_speed` and
## `release_constraint()` on DISENGAGE.
class_name FighterBrain
extends EnemyBrain

## IDLE, NOTICING and RETURNING are appended (t12) so the earlier values do not move.
enum Phase { APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }
## The shape of a pass (epic §2.4.1). The solo alternation uses the flank shapes at `pass_offset`;
## squad roles (and the `forced_pass_kind` seam) use FLANK_RIGHT's outer lane. REAR is a squad REAR's
## dry pass.
enum PassKind { FLANK_LEFT, FLANK_RIGHT, FRONTAL, REAR }
enum WeaponMode { AIMED, FORWARD }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)
## Emitted when a burst starts in a different mode from the last burst.
signal weapon_mode_changed(mode: int)

## The player-lead window P̂ uses (s).
const LEAD_MIN := 0.3
const LEAD_MAX := 0.8
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## Rail fire leaves from this far behind the hull's centre along local +y, as it always did (px).
const RAIL_SPAWN_OFFSET := Vector2(0.0, 10.0)
## Open Space `h` follows the player's velocity above this speed, else its facing (px/s).
const HEADING_REF_MIN_SPEED := 40.0
## EXTEND (epic §2.4.1).
const EXTEND_MIN_DISTANCE := 350.0
const EXTEND_MIN_SECONDS := 0.6
const EXTEND_MAX_SECONDS := 1.5
## RUN_IN hands over when the heading is within this of the run heading (deg).
const HANDOVER_HEADING_DEG := 30.0
## Controller tolerances (task plan §5), not balance.
const REPLAN_GOAL_PX := 24.0
const REPLAN_OFF_PATH_PX := 40.0
const PLAN_RADIUS_FACTOR := 1.1
const PLAN_SAMPLE_PX := 16.0
const TRACK_SAMPLE_PX := 8.0
const TRACK_SEARCH := 12
const TRACK_AHEAD := 3
const BREACH_MARGIN := 24.0
const BREAK_CLEARANCE_FACTOR := 0.75
const CORRIDOR_SLACK := 60.0
## Assault: EXTEND ends when the point this far ahead (s) leaves the corridor; the ring fallback keeps
## this far inside it (px) — the prototyped rules (review I7).
const EXTEND_CORRIDOR_LOOKAHEAD := 0.3
const RING_CORRIDOR_MARGIN := 200.0
## The ring fallback halves its angle at most this many times to clear the corridor clamp.
const RING_SHRINK_STEPS := 6
const LOITER_SPEED := 60.0
const LOITER_GAIN := 2.0
## A moving player's goal is predicted at most this far ahead (s), refined this many times.
const GOAL_PREDICT_MAX := 3.0
const GOAL_PREDICT_ITERATIONS := 3
## The peel gives up after this (s). (The turn-in gives up after a full circle, review I4.)
const PEEL_MAX_SECONDS := 2.5
## A holding squad member flies back to its S once it drifts this far from it (px).
const HOLD_DRIFT_PX := 160.0
## Slack on top of the run's own time when a squad member checks it still fits the budget (s).
const BUDGET_RUN_MARGIN := 0.25
## A squad member within this many plan radii of its S, with a clear straight line to it, brakes onto
## it instead of flying a lead-in.
const STATION_ARRIVE_PLAN_RADII := 2.0
## Below this fraction of `max_speed` a RUN_IN sets off along the line instead of turning onto it.
const STANDING_START_FRACTION := 0.3
## A holding member counts as on its S within this (px).
const STATION_SETTLE_PX := 32.0
## A member kept unsettled this many times its own wait still goes (round-2 N6).
const UNSETTLED_WAIT_FACTOR := 2.0
## Two runs whose directions differ by less than this sine are parallel (≈ 10°).
const PARALLEL_SIN := 0.17
## Squad give-way (task plan §3.3): the centre distance a member keeps from a mate's planned track,
## in hull radii, over this horizon (s) sampled this often (s); the speed a holding member slides
## aside at (px/s); and the fractions of its speed a member flying to its S may slow to, fastest first.
const GIVE_WAY_HULLS := 3.0
const GIVE_WAY_HORIZON := 1.5
const GIVE_WAY_SAMPLE := 0.1
const GIVE_WAY_SLIDE_SPEED := 180.0
const GIVE_WAY_STEPS: Array[float] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.0]
## Hull radius used when the scene has no readable body circle (px).
const DEFAULT_HULL_RADIUS := 28.0

## Set by `fighter.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: FighterConfig = FighterConfig.new()
## The rail fallback's aim mode, resolved once by `fighter.gd`: the spawn prop if set, else the
## config default. "FORWARD" or "PLAYER".
var rail_aim_mode: String = "PLAYER"
## The sibling `AttackController` past `attack` (`ForwardAttack`), or null.
var forward_attack: AttackController
## Test seam: ≥ 0 makes every pass this `PassKind`, with its role-shaped lane, and no squad hold.
var forced_pass_kind: int = -1
## The Open Space hub idle's ring centre. `Vector2.INF` (unset) means "not set" — `_start()` then
## defaults it to the spawn position, so a loose fighter with no owner still patrols somewhere.
var patrol_anchor: Vector2 = Vector2.INF
## Test seam (t12): every pre-idle test sets this so a spawned fighter starts already fighting, the
## only behaviour that existed before. Real spawns (SectorHub) never set it — an Open Space fighter
## patrols `patrol_anchor` until it perceives the player. Assault ignores it: `EngagementBudget.active`
## alone decides combat-from-spawn there.
var start_engaged: bool = false
## Open Space only (`budget.active == false` and not `start_engaged`); null otherwise. Built once, in
## `_start()`.
var anchor_idle: AnchorIdle
## This fighter's offset on the idle ring (rad), drawn from `rng` within ±`MAX_IDLE_PHASE_OFFSET` when the idle starts (never for an
## engaged fighter, so a seeded combat sequence is unchanged).
var idle_phase_offset: float = 0.0
## `idle_phase_offset` is drawn from ±this (rad), bounded so it never undoes the idle ring's
## `member_index × TAU / member_count` spacing (same idea as the Swarm's `MAX_PHASE_OFFSET`).
const MAX_IDLE_PHASE_OFFSET := 0.35

var phase: Phase = Phase.APPROACH
## Built on the first tick. Null before it.
var budget: EngagementBudget

## The current (or, before RUN_IN, the next) pass. Read-only outside this script.
var pass_kind: int = PassKind.FLANK_RIGHT
var pass_bearing: Vector2 = Vector2.RIGHT
var pass_dir: Vector2 = Vector2.LEFT
var pass_lane: Vector2 = Vector2.ZERO
## The FRONTAL lane side σ (+1 = `right(h)`), or the side the breach pass took.
var pass_side: float = 1.0
## This tick's predicted player position P̂, the pass line's anchor.
var pass_anchor: Vector2 = Vector2.ZERO
var pass_start: Vector2 = Vector2.ZERO
## The point the fighter is steering at this tick.
var seek_target: Vector2 = Vector2.ZERO
var passes_done: int = 0
## The squad role the current (or last) pass was entered in, latched at RUN_IN entry; -1 before the
## first. Read-only outside this script.
var pass_role: int = -1
## The mode of the last burst started. Read-only outside this script.
var weapon_mode: int = WeaponMode.AIMED

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _hull_radius: float = DEFAULT_HULL_RADIUS

# Pass state.
var _latched: bool = false
var _pass_prepared: bool = false
var _lead: float = LEAD_MAX
var _run_heading: Vector2 = Vector2.LEFT
var _next_solo_kind: int = -1
var _frontal_sigma: float = 0.0
var _regroup_pending: bool = false
var _loiter_time: float = -1.0

# Squad state.
## ≥ 0 while a FLANK / REAR holds at S waiting for the LEAD's window (s held).
var _hold_time: float = -1.0
## How long a holding member has been continuously unsettled (`is_settled()` false), s.
var _unsettled_time: float = 0.0
var _answered_window: bool = false
## Windows a REAR has seen while holding: every second one makes it due a dry pass.
var _rear_windows: int = 0
## A REAR due a dry pass flies it in the gap after the window, once no mate is on a pass (task plan §3.4).
var _rear_due: bool = false
## The side (+1 = `right(h)`) a REAR's dry pass comes from; 0 until it first derives one as REAR.
var _rear_side: float = 0.0
## ≥ 0 while a FLANK on the LEAD's side counts down `flank_stagger` before its run (s).
var _stagger_left: float = -1.0
## Seconds a FLANK has held while its LEAD was not holding too: `flank_wait_max` bounds this.
var _wait_time: float = 0.0

# Lead-in path.
var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_idx: int = 0
## S when the path was planned, the player velocity then, and the seconds flown since: a moving
## player's S is expected at `_path_goal + _path_goal_velocity × _path_age`, and only a departure
## from that track re-plans (review I5).
var _path_goal: Vector2 = Vector2.INF
var _path_goal_velocity: Vector2 = Vector2.ZERO
var _path_age: float = 0.0
var _path_first_end: int = 0
var _path_length: float = 0.0
var _deadline: float = INF
var _deadline_from_plan: bool = false
## The tick's last velocity request, for the give-way.
var _last_request: Vector2 = Vector2.ZERO
var _has_request: bool = false

# TURN: 0 = turn-in, 1 = break-away arc, 2 = peel.
var _turn_step: int = 0
var _turn_sign: float = 1.0

# Weapons.
var _leg_a_open: bool = false
var _leg_b_open: bool = false
var _since_burst: float = INF
var _telegraph_left: float = -1.0
var _clock := BurstClock.new()
var _burst_mode: int = WeaponMode.AIMED
var _burst_controller: AttackController
var _disengage_pending: bool = false


func _ready() -> void:
	super._ready()
	var parent := get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling is AttackController and sibling != attack:
			forward_attack = sibling
			break
	var body := parent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null and body.shape is CircleShape2D:
		_hull_radius = (body.shape as CircleShape2D).radius * absf(body.scale.x)


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	_since_burst += delta
	var target := TargetInfo.player(get_tree())
	var squad := _squad()
	if squad != null:
		if target.has_target:
			squad.update_target(target.position, heading_ref(target))
		if not squad.attack_window_open:
			_answered_window = false
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	if anchor_idle != null:
		_tick_anchor_idle(delta, target, squad)
	_tick_weapons(delta, target)
	var was := phase
	match phase:
		Phase.IDLE: _tick_idle(delta, target)
		Phase.NOTICING: _tick_noticing(target)
		Phase.RETURNING: _tick_returning(target)
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.RUN_IN: _tick_run_in(delta, target)
		Phase.EXTEND: _tick_extend(target)
		Phase.TURN: _tick_turn(delta, target)
		Phase.REPOSITION: _tick_reposition(delta, target)
		Phase.DISENGAGE: _tick_disengage(delta)
	if phase == Phase.RUN_IN and was != Phase.RUN_IN:
		_steer_run_in(delta, target)
	if _has_request:
		_give_way(delta)
	_has_request = false


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.APPROACH, Phase.REPOSITION:
			_deadline = config.reposition_max
			_deadline_from_plan = false
			_loiter_time = -1.0
			_hold_time = -1.0
			if p == Phase.REPOSITION and not _path_pts.is_empty():
				_set_deadline_from_path()
		Phase.RUN_IN:
			_enter_run_in()
		Phase.EXTEND:
			_close_window()
		Phase.TURN:
			_enter_turn()
		Phase.DISENGAGE:
			_enter_disengage()
		Phase.IDLE, Phase.RETURNING:
			_enter_calm()
		Phase.NOTICING:
			_enter_noticing()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. Self-timed fire from the same pool, from
## config fields (`rail_*`), so the round-lifetime sweep reads the same numbers the rail fires with.
func on_suspended() -> void:
	anchor_idle = null  # a rail owns the motion: no idle
	_abort_burst()
	_set_light(StateLight.State.OFF)
	var squad := _squad()
	if squad != null:
		squad.leave(actor)
	if forward_attack != null:
		forward_attack.enabled = false
	if attack == null:
		return
	var forward := rail_aim_mode == "FORWARD"
	var pattern := AimedAttackPattern.new()
	pattern.fire_interval = config.rail_forward_interval if forward else config.fire_interval
	pattern.bullet_damage = config.bullet_damage
	pattern.bullet_speed = config.rail_forward_speed if forward else config.rail_aimed_speed
	pattern.aim_at_player = not forward
	pattern.accuracy = 0.0
	pattern.spawn_offset = RAIL_SPAWN_OFFSET
	attack.pattern = pattern
	attack.driven_by_brain = false
	attack.enabled = true


## The mode a burst opportunity at distance `d` takes: FORWARD below `forward_range`, AIMED from
## `forward_range + mode_hysteresis`, and the last burst's mode in between.
func select_weapon_mode(d: float) -> int:
	if d < config.forward_range:
		return WeaponMode.FORWARD
	if d >= config.forward_range + config.mode_hysteresis:
		return WeaponMode.AIMED
	return weapon_mode


## True while a burst's telegraph or its shots are running.
func is_bursting() -> bool:
	return _telegraph_left >= 0.0 or _clock.is_running()


## True while a FLANK / REAR holds at its S waiting for the LEAD's window.
func is_holding() -> bool:
	return phase == Phase.REPOSITION and _hold_time >= 0.0


## Holding, on its S (not slid aside for a mate, `_slide_aside()`) and slow enough to set off along its
## run from a standing start: only a settled member counts as ready for the rendezvous, or answers a
## window — a run started off S converges on its line at an angle no stagger predicted.
func is_settled() -> bool:
	return is_holding() and actor.global_position.distance_to(pass_start) <= STATION_SETTLE_PX \
			and actor.velocity.length() < config.max_speed * STANDING_START_FRACTION


## Braking onto its S: a lead-in slowed to a standing start inside the arrive zone, about to hold. A
## mate on its own lead-in slows for it like for a moving mate (`_slow_for_mates()`) rather than closing
## in on a ship it neither slides from nor yields to (round-2 review N5).
func is_braking_onto_station() -> bool:
	return not is_holding() and _loiter_time < 0.0 and _waits_for_window() and (phase == Phase.APPROACH or phase == Phase.REPOSITION) \
			and actor.velocity.length() < config.max_speed * STANDING_START_FRACTION \
			and actor.global_position.distance_to(pass_start) <= STATION_ARRIVE_PLAN_RADII * _plan_radius()


## The turn radius the attack run flies at full rate (px).
func turn_radius() -> float:
	return config.max_speed / config.turn_rate if config.turn_rate > 0.0 else INF


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())
	_deadline = config.reposition_max
	if not patrol_anchor.is_finite():
		patrol_anchor = actor.global_position
	if not budget.active and not start_engaged:
		anchor_idle = AnchorIdle.new(patrol_anchor, config.perceive_radius, config.lose_radius, config.notice_time, config.idle_radius)
		idle_phase_offset = rng.randf_range(-MAX_IDLE_PHASE_OFFSET, MAX_IDLE_PHASE_OFFSET)
		enter_phase(Phase.IDLE)


# ── Hub idle (t12; epic §2.10) ───────────────────────────────────────────────────────────────────

## The meta-state that decides whether this member is patrolling, noticing or fighting, run once a tick
## ahead of the phase dispatch (the Swarm Drone's shape): `anchor_idle` tracks the fighter's own
## proximity to the target whatever pass it is in, and a squad returns together because
## `hold_combat` keeps every member fighting while any one of them is engaged.
func _tick_anchor_idle(delta: float, target: TargetInfo, squad: SquadController) -> void:
	if squad != null and _is_calm() and squad.is_engaged():
		anchor_idle.force_notice()
	var state := anchor_idle.update(delta, actor.global_position, target)
	if squad != null:
		# Engaged only while perceiving/fighting AND within lose_radius — never from hold_combat alone,
		# or a member held in COMBAT by its mates could never stop reporting engaged.
		var near := target.has_target and actor.global_position.distance_squared_to(target.position) < config.lose_radius * config.lose_radius
		squad.set_engaged(actor, (state == AnchorIdle.State.NOTICING or state == AnchorIdle.State.COMBAT) and near)
		anchor_idle.hold_combat = squad.is_engaged()
	match state:
		AnchorIdle.State.IDLE:
			if phase != Phase.IDLE and not is_bursting():
				enter_phase(Phase.IDLE)
		AnchorIdle.State.NOTICING:
			if phase != Phase.NOTICING and not is_bursting():
				enter_phase(Phase.NOTICING)
		AnchorIdle.State.COMBAT:
			# From NOTICING only: any other phase is already fighting.
			if phase == Phase.NOTICING:
				passes_done = 0
				enter_phase(Phase.APPROACH)
		AnchorIdle.State.RETURNING:
			# Neither this nor IDLE or NOTICING interrupts a burst: retried every tick until it has ended.
			if phase != Phase.RETURNING and not is_bursting():
				enter_phase(Phase.RETURNING)


func _is_calm() -> bool:
	return phase == Phase.IDLE or phase == Phase.RETURNING


## IDLE and RETURNING entry: forget the pass in progress, so the next fight starts from a clean APPROACH.
func _enter_calm() -> void:
	_clear_path()
	_latched = false
	_pass_prepared = false
	_leg_a_open = false
	_leg_b_open = false
	_regroup_pending = false
	_loiter_time = -1.0
	_hold_time = -1.0
	_stagger_left = -1.0
	_wait_time = 0.0
	_rear_due = false
	_answered_window = false
	var squad := _squad()
	if squad != null and squad.role_of(actor) == SquadController.Role.LEAD:
		squad.attack_window_open = false
	pass_role = -1
	_set_light(StateLight.State.OFF)


func _enter_noticing() -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(StateLight.State.OFF)
		light.blink_once()


func _tick_noticing(target: TargetInfo) -> void:
	if target.has_target:
		mover.face_toward(target.position)


func _tick_returning(_target: TargetInfo) -> void:
	mover.arrive(patrol_anchor, config.max_speed)


func _tick_idle(_delta: float, _target: TargetInfo) -> void:
	mover.orbit(patrol_anchor, config.idle_radius, _idle_ring_angle(), config.max_speed)


## `offset + index × TAU / n + idle_speed × t`: `index` is the member's join order among the whole
## squad — a squad of one (or no squad) is index 0 of 1 — so a squad spreads round one shared ring.
func _idle_ring_angle() -> float:
	var squad := _squad()
	var index := 0
	var n := 1
	if squad != null:
		index = maxi(squad.member_index(actor), 0)
		n = maxi(squad.member_count(), 1)
	return idle_phase_offset + index * TAU / n + config.idle_speed * _phase_time


# ── Pass geometry (epic §2.4.1) ──────────────────────────────────────────────────────────────────

## The heading reference `h`: UP in the corridor, else the player's velocity or facing. Also the
## squad board's heading hint, so a flank role's side and its pass's bearing side agree.
func heading_ref(target: TargetInfo) -> Vector2:
	if _corridor().has_area():
		return Vector2.UP
	if target.velocity.length() > HEADING_REF_MIN_SPEED:
		return target.velocity.normalized()
	return target.facing if target.facing != Vector2.ZERO else Vector2.UP


## Re-derives the pass from this tick's world, unless it is latched (RUN_IN to EXTEND's end).
func _derive_pass(target: TargetInfo) -> void:
	if _latched or not target.has_target:
		return
	var pos := actor.global_position
	_lead = Steering.clamped_lead_time(pos.distance_to(target.position), config.max_speed, LEAD_MIN, LEAD_MAX)
	var anchor := target.predicted_position(_lead)
	var h := heading_ref(target)
	var right := h.rotated(PI / 2.0)
	var kind := _kind_for(right, pos - anchor)
	var b: Vector2
	var l: Vector2
	var side := 1.0
	var standoff := config.standoff_radius
	if kind != PassKind.REAR:
		_rear_side = 0.0
		_rear_due = false
	match kind:
		PassKind.FLANK_LEFT:
			b = h.rotated(-PI / 2.0)
			l = h * config.pass_offset
		PassKind.FLANK_RIGHT:
			b = right
			var lane := config.pass_offset
			if _role_shaped():
				lane += config.flank_lane_gap
			l = h * lane
		PassKind.REAR:
			# The side it is on when it becomes REAR, then kept, so a REAR that crosses the heading
			# line never swings its S across the player. One lane per REAR, outside both flanks'.
			if _rear_side == 0.0:
				_rear_side = -1.0 if right.dot(pos - anchor) < 0.0 else 1.0
			side = _rear_side
			b = right * side
			var squad := _squad()
			var index := maxi(squad.rear_index(actor), 0) if squad != null else 0
			l = h * (config.pass_offset + (2 + index) * config.flank_lane_gap)
			standoff = config.rear_standoff_radius
		_:
			b = h
			# σ is taken from the fighter's side on the first FRONTAL derivation and then kept (it
			# alternates per pass): re-read every tick, a LEAD spawned on the heading line flips it
			# as it moves, and its S jumps across the player.
			if _frontal_sigma == 0.0:
				_frontal_sigma = -1.0 if right.dot(pos - anchor) < 0.0 else 1.0
			side = _frontal_sigma
			l = right * side * config.pass_offset
	var rect := _corridor()
	if rect.has_area():
		if kind == PassKind.FRONTAL:
			var lane_x := anchor.x + l.x
			if lane_x - _hull_radius < rect.position.x or lane_x + _hull_radius > rect.end.x:
				side = -side
				l = -l
		elif anchor.y + l.y - _hull_radius < rect.position.y:
			l = -l  # the ahead lane does not fit under the corridor top: pass behind
	var s := anchor + b * standoff + l
	if rect.has_area():
		s = _clamp_run(s, b, rect)
		if (anchor + l - s).dot(-b) < config.min_run_length:
			b = -b
			s = _clamp_run(anchor + b * standoff + l, b, rect)
	pass_kind = kind
	pass_bearing = b
	pass_dir = -b
	pass_lane = l
	pass_side = side
	pass_anchor = anchor
	pass_start = s
	_run_heading = _ground_run_heading(pass_dir, target.velocity)


func _kind_for(right: Vector2, offset: Vector2) -> int:
	if forced_pass_kind >= 0:
		return forced_pass_kind
	if _in_squad():
		match _role():
			SquadController.Role.FLANK_LEFT: return PassKind.FLANK_LEFT
			SquadController.Role.FLANK_RIGHT: return PassKind.FLANK_RIGHT
			SquadController.Role.REAR: return PassKind.REAR
			_: return PassKind.FRONTAL
	if _next_solo_kind >= 0:
		return _next_solo_kind
	return PassKind.FLANK_LEFT if right.dot(offset) < 0.0 else PassKind.FLANK_RIGHT


## Clamps S along the run axis only (so it stays on the pass line), into the corridor shrunk by the
## lead-in loop's diameter plus the hull, so the loop that ends at S fits.
func _clamp_run(s: Vector2, b: Vector2, rect: Rect2) -> Vector2:
	var margin := 2.0 * _plan_radius() + _hull_radius
	if absf(b.x) >= absf(b.y):
		s.x = clampf(s.x, rect.position.x + margin, maxf(rect.position.x + margin, rect.end.x - margin))
	else:
		s.y = clampf(s.y, rect.position.y + margin, maxf(rect.position.y + margin, rect.end.y - margin))
	return s


## The heading that holds a pass line moving with the player: its sideways velocity plus the rest of
## `max_speed` along `u` (`u` itself for a holding player).
func _ground_run_heading(u: Vector2, player_velocity: Vector2) -> Vector2:
	var v_perp := player_velocity - u * player_velocity.dot(u)
	var along := sqrt(maxf(config.max_speed * config.max_speed - v_perp.length_squared(), 0.0))
	var g := v_perp + u * along
	return g.normalized() if g != Vector2.ZERO else u


## The pass the solo alternation flies after this one.
func _complete_pass() -> void:
	passes_done += 1
	_latched = false
	if pass_kind == PassKind.FRONTAL:
		_frontal_sigma = -pass_side
	if forced_pass_kind < 0:
		match pass_kind:
			PassKind.FLANK_LEFT: _next_solo_kind = PassKind.FLANK_RIGHT
			PassKind.FLANK_RIGHT: _next_solo_kind = PassKind.FLANK_LEFT
			_: _next_solo_kind = -1
	var cycle_done := config.passes > 0 and passes_done % config.passes == 0
	if cycle_done and budget.active:
		_request_disengage()
		if phase == Phase.DISENGAGE:
			return
	elif cycle_done:
		_regroup_pending = true
	enter_phase(Phase.TURN)


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_request(Vector2.ZERO)
		return
	_derive_pass(target)
	var clear := minf(config.standoff_radius, pass_start.distance_to(pass_anchor)) - 1.0
	if _waits_for_window():
		# A squad member flies to S to hold there, like REPOSITION: its clearance, and no breach
		# (a hold never circles the player waiting). The deadline below still bounds it.
		clear = config.reposition_min_radius
	elif actor.global_position.distance_to(target.position) < clear - BREACH_MARGIN:
		_begin_breach_pass(target)
		return
	_fly_to_start(delta, target, clear, -1.0)
	if _at_start():
		if _waits_for_window():
			enter_phase(Phase.REPOSITION)
			_begin_hold()
		else:
			enter_phase(Phase.RUN_IN)
	elif _phase_time >= _deadline:
		_begin_breach_pass(target)


## A FRONTAL-shaped pass from where the fighter is (epic §2.4.1 APPROACH; review N9): the lane is
## perpendicular to the NEW run direction, on the side the fighter is already drifting to.
func _begin_breach_pass(target: TargetInfo) -> void:
	var pos := actor.global_position
	_lead = Steering.clamped_lead_time(pos.distance_to(target.position), config.max_speed, LEAD_MIN, LEAD_MAX)
	var anchor := target.predicted_position(_lead)
	var b := (pos - anchor).normalized()
	if b == Vector2.ZERO:
		b = -_heading()
	var u := -b
	var right := u.rotated(PI / 2.0)
	var side := -1.0 if right.dot(_heading()) < 0.0 else 1.0
	pass_kind = PassKind.FRONTAL
	pass_bearing = b
	pass_dir = u
	pass_lane = right * side * config.pass_offset
	pass_side = side
	pass_anchor = anchor
	pass_start = pos
	_run_heading = _ground_run_heading(u, target.velocity)
	_pass_prepared = true
	enter_phase(Phase.RUN_IN)


# ── RUN_IN ───────────────────────────────────────────────────────────────────────────────────────

func _enter_run_in() -> void:
	_clear_path()
	if not _pass_prepared:
		_derive_pass(TargetInfo.player(get_tree()))
	_pass_prepared = false
	_latched = true
	_leg_a_open = true
	_regroup_pending = false
	_loiter_time = -1.0
	_hold_time = -1.0
	_stagger_left = -1.0
	_wait_time = 0.0
	_rear_due = false
	pass_role = _role()
	var squad := _squad()
	if squad != null and pass_role == SquadController.Role.LEAD:
		squad.attack_window_open = true


func _tick_run_in(delta: float, target: TargetInfo) -> void:
	_steer_run_in(delta, target)
	if not target.has_target:
		return
	if (pass_anchor - actor.global_position).dot(pass_dir) < 0.0 or _phase_time >= config.run_in_max:
		enter_phase(Phase.EXTEND)


## The pass line's path following. Also flown on the tick RUN_IN is entered, so the run's first
## request is already along the line (and `seek_target` is a lookahead ahead from that tick on).
func _steer_run_in(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_request(_heading() * config.max_speed)
		return
	pass_anchor = target.predicted_position(_lead)
	var pos := actor.global_position
	var u := pass_dir
	var a := pass_anchor + pass_lane
	var s := (pos - a).dot(u)
	seek_target = a + u * (s + config.lookahead)
	var v_perp := target.velocity - u * target.velocity.dot(u)
	var along := sqrt(maxf(config.max_speed * config.max_speed - v_perp.length_squared(), 0.0))
	var desired := v_perp + (seek_target - pos).normalized() * along
	# From (nearly) rest — a squad member leaving its hold — there is no heading to turn from: the
	# mover's acceleration limit shapes the start, and the run sets off along the line.
	var heading := desired.normalized() if actor.velocity.length() < config.max_speed * STANDING_START_FRACTION else _heading()
	var dir := Steering.turn_toward(heading, desired, config.turn_rate, delta)
	_request(dir * config.max_speed)


# ── EXTEND ───────────────────────────────────────────────────────────────────────────────────────

func _tick_extend(target: TargetInfo) -> void:
	var heading := _heading()
	_request(heading * config.max_speed)
	var pos := actor.global_position
	var d := pos.distance_to(target.position) if target.has_target else INF
	var done := (_phase_time >= EXTEND_MIN_SECONDS and d >= EXTEND_MIN_DISTANCE) \
			or _phase_time >= EXTEND_MAX_SECONDS
	var rect := _corridor()
	if rect.has_area() and not rect.grow(-_hull_radius).has_point(pos + heading * config.max_speed * EXTEND_CORRIDOR_LOOKAHEAD):
		done = true
	if done:
		_complete_pass()


# ── TURN: turn back in, snapshot, break away ─────────────────────────────────────────────────────

func _enter_turn() -> void:
	_clear_path()
	_turn_step = 0
	_leg_b_open = true
	var target := TargetInfo.player(get_tree())
	var heading := _heading()
	var to_player := (target.position - actor.global_position) if target.has_target else heading
	_turn_sign = -1.0 if heading.angle_to(to_player) < 0.0 else 1.0
	var rect := _corridor()
	if rect.has_area():
		# The short way round must fit the corridor; if only the long way does, take it.
		var room := rect.grow(CORRIDOR_SLACK - turn_radius())
		var short_centre := actor.global_position + heading.rotated(_turn_sign * PI / 2.0) * turn_radius()
		var long_centre := actor.global_position + heading.rotated(-_turn_sign * PI / 2.0) * turn_radius()
		if not room.has_point(short_centre) and room.has_point(long_centre):
			_turn_sign = -_turn_sign


func _tick_turn(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_request(_heading() * config.max_speed)
		return
	_derive_pass(target)
	var pos := actor.global_position
	match _turn_step:
		0:
			var heading := _heading()
			var to_player := target.position - pos
			var remaining := fposmod(_turn_sign * heading.angle_to(to_player), TAU)
			var desired := heading.rotated(_turn_sign * minf(remaining, PI * 0.99))
			seek_target = target.position
			_request(Steering.turn_toward(heading, desired, config.turn_rate, delta) * config.max_speed)
			if _nose_on(target) or _phase_time >= TAU / config.turn_rate:
				var break_clear := config.pass_offset * BREAK_CLEARANCE_FACTOR
				_turn_step = 1 if _plan(target, config.reposition_min_radius, break_clear) else 2
				_phase_time = 0.0
		1:
			if pos.distance_to(_path_pts[_path_idx]) > REPLAN_OFF_PATH_PX:
				_turn_step = 2
				_clear_path()
				return
			_track(delta)
			if _path_idx >= _path_first_end:
				enter_phase(Phase.REPOSITION)
		_:
			var away := pos - target.position
			seek_target = pos + away
			_request(Steering.turn_toward(_heading(), away, config.turn_rate, delta) * config.max_speed)
			if away.length() >= config.reposition_min_radius or _phase_time >= PEEL_MAX_SECONDS:
				enter_phase(Phase.REPOSITION)


# ── REPOSITION ───────────────────────────────────────────────────────────────────────────────────

func _tick_reposition(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		_request(Vector2.ZERO)
		return
	_derive_pass(target)
	if _loiter_time >= 0.0:
		_tick_loiter(delta, target)
		return
	if _hold_time >= 0.0:
		_tick_hold(delta, target)
		return
	_fly_to_start(delta, target, config.reposition_min_radius, -1.0)
	if _at_start():
		if _waits_for_window():
			_begin_hold()
		elif _regroup_pending:
			_loiter_time = 0.0
		else:
			enter_phase(Phase.RUN_IN)
	elif _phase_time >= _deadline:
		_begin_breach_pass(target)


## Holds S (which moves with the player) with the nose along the run; only the correction toward S
## is capped, so a moving player's S can still be held.
func _tick_loiter(delta: float, target: TargetInfo) -> void:
	_loiter_time += delta
	_hold_station(target)
	if _loiter_time >= config.regroup_seconds:
		enter_phase(Phase.RUN_IN)


func _hold_station(target: TargetInfo) -> void:
	var off := pass_start - actor.global_position
	# A squad member that slid aside for a mate (`_slide_aside()`) comes back as fast as it left.
	var cap := GIVE_WAY_SLIDE_SPEED if _in_squad() and off.length() > STATION_SETTLE_PX else LOITER_SPEED
	var correction := (off * LOITER_GAIN).limit_length(cap)
	seek_target = pass_start
	_request(target.velocity + correction)
	mover.face_toward(actor.global_position + pass_dir * 100.0)


# ── Squad hold (epic §2.5) ───────────────────────────────────────────────────────────────────────

## Every member of a squad of two or more holds at S: a FLANK or REAR for the LEAD's window, the
## LEAD for its flanks. A solo fighter and the `forced_pass_kind` seam never do.
func _waits_for_window() -> bool:
	return forced_pass_kind < 0 and _in_squad()


## True when every FLANK of the squad is holding at its S (duck-typed through the board).
func _flanks_ready() -> bool:
	var squad := _squad()
	for m in squad.members():
		var role := squad.role_of(m)
		if role != SquadController.Role.FLANK_LEFT and role != SquadController.Role.FLANK_RIGHT:
			continue
		var brain := m.get_node_or_null("Brain")
		if brain != null and brain.has_method(&"is_settled") and not brain.is_settled():
			return false
	return true


func _begin_hold() -> void:
	_hold_time = 0.0
	_unsettled_time = 0.0
	_stagger_left = -1.0
	_wait_time = 0.0
	_regroup_pending = false  # the hold is a squad member's regroup


## Holds S. A FLANK answers each window once, or goes after `flank_wait_max`; a REAR answers every
## other window. A member that drifts off S, or is promoted to LEAD, flies back to (its new) S.
func _tick_hold(delta: float, target: TargetInfo) -> void:
	_hold_time += delta
	if not _waits_for_window() or actor.global_position.distance_to(pass_start) > HOLD_DRIFT_PX:
		_hold_time = -1.0
		_clear_path()
		_deadline = _phase_time + config.reposition_max
		_deadline_from_plan = false
		_fly_to_start(delta, target, config.reposition_min_radius, -1.0)
		return
	_hold_station(target)
	if _stagger_left >= 0.0:
		_stagger_left -= delta
		if _stagger_left <= 0.0:
			_go()
		return
	var role := _role()
	if role != SquadController.Role.REAR and _budget_short():
		# Assault: waiting any longer would leave no time for the run. Still only from a standing
		# start or already heading along the run: a member sliding in fast across its line would
		# swing a turn radius off it, towards the player.
		if is_settled() or absf(_heading().angle_to(_run_heading)) <= deg_to_rad(HANDOVER_HEADING_DEG):
			_go()
		return
	if not is_settled():
		# Still sliding in: a run started now would curve off its line. Bounded (round-2 review N6): a
		# member kept off S — two holders pushing apart, a mate crossing its station again and again — goes
		# once it has been off it for `UNSETTLED_WAIT_FACTOR` times its own wait, so no Open Space hold is endless.
		_unsettled_time += delta
		if role != SquadController.Role.REAR and _unsettled_time >= UNSETTLED_WAIT_FACTOR * _own_wait_max() \
				and not _rear_slot_taken():
			_go()
		return
	_unsettled_time = 0.0
	var squad := _squad()
	if role == SquadController.Role.LEAD:
		if (_flanks_ready() or _hold_time >= config.lead_wait_max) and not _rear_slot_taken():
			_go()
		return
	# A holding LEAD is timing the attack, not dead or slow: the wait only runs while it is not.
	if not _lead_holding():
		_wait_time += delta
	var is_rear := role == SquadController.Role.REAR
	if squad.attack_window_open and not _answered_window:
		_answered_window = true
		if not is_rear:
			_go()
			return
		_rear_windows += 1
		_rear_due = _rear_due or _rear_windows % 2 == 0
	if is_rear:
		# The dry pass has its own slot: after the window, once no mate is on a pass and every attacker
		# holds its station (task plan §3.4).
		if _rear_due and not squad.attack_window_open and _rear_slot_free():
			_go()
		return
	if _wait_time >= config.flank_wait_max and not _rear_slot_taken():
		_go()


## The longest an attacker waits at its S before it goes on its own: `lead_wait_max` for the LEAD,
## `flank_wait_max` for a FLANK.
func _own_wait_max() -> float:
	return config.lead_wait_max if _role() == SquadController.Role.LEAD else config.flank_wait_max


## Starts the run now, or — if a squad mate already on a run would reach the crossing of the two
## lines within `flank_stagger` of this fighter — that much later (re-checked when the wait ends).
## Never once the run's closest approach no longer fits the budget (`run_budget_slack()`).
func _go() -> void:
	if run_budget_slack() <= 0.0:
		return  # Assault: too late for this run; it holds and leaves with the budget
	var wait := _crossing_stagger()
	if wait > 0.0:
		_stagger_left = wait
	else:
		enter_phase(Phase.RUN_IN)


## The delay that puts this fighter at least `flank_stagger` behind every squad mate on a run (RUN_IN
## or EXTEND) at the crossing of their lines, both flying at `max_speed`. 0 when no line crosses
## ahead of both, or every crossing is already far enough apart. In a pincer this is the flank on
## the side the LEAD's lane passes (its σ): the two lines' crossing is the same distance from both.
func _crossing_stagger() -> float:
	var squad := _squad()
	var need := 0.0
	for m in squad.members():
		if m == actor:
			continue
		var mate := m.get_node_or_null("Brain") as FighterBrain
		if mate == null or (mate.phase != Phase.RUN_IN and mate.phase != Phase.EXTEND):
			continue
		# On a run the line is the pass line (a run just started from rest has no useful velocity yet);
		# EXTEND holds its heading.
		var mate_dir: Vector2 = mate.pass_dir
		if mate.phase == Phase.EXTEND and m.velocity.length() > HEADING_MIN_SPEED:
			mate_dir = m.velocity.normalized()
		if absf(mate_dir.cross(pass_dir)) < PARALLEL_SIN and mate_dir.dot(pass_dir) > 0.0:
			# The same way on a parallel lane: this run trails the mate's by one crossing gap (Revision 2:
			# two gaps cost Assault runs and bought no separation). Their turns can still converge (round 2 B1).
			var ahead := (m.global_position - actor.global_position).dot(pass_dir)
			var trail := config.flank_stagger * config.max_speed
			if ahead < trail:
				need = maxf(need, (trail - ahead) / config.max_speed)
			continue
		var hit: Variant = Geometry2D.line_intersects_line(m.global_position, mate_dir, actor.global_position, pass_dir)
		if hit == null:
			continue
		var t_mate := ((hit as Vector2) - m.global_position).dot(mate_dir) / config.max_speed
		var t_mine := ((hit as Vector2) - actor.global_position).dot(pass_dir) / config.max_speed
		if t_mate < 0.0 or t_mine < 0.0 or absf(t_mine - t_mate) >= config.flank_stagger:
			continue
		need = maxf(need, t_mate + config.flank_stagger - t_mine)
	return need


## Assault: the engagement budget left once this pass's run, from here to its closest approach (plus
## `BUDGET_RUN_MARGIN`), is flown (s); INF with no running budget. A squad member stops waiting for its
## squad once only the run and the shortest extension still fit (`_budget_short()`), and never starts a
## run at all below 0: that run would still be heading at the player when the budget sends it out.
func run_budget_slack() -> float:
	if budget == null or not budget.active:
		return INF
	var along := maxf((pass_anchor + pass_lane - actor.global_position).dot(pass_dir), 0.0)
	return budget.remaining() - (along / config.max_speed + BUDGET_RUN_MARGIN)


func _budget_short() -> bool:
	return run_budget_slack() <= EXTEND_MIN_SECONDS


## On a pass: RUN_IN, EXTEND or TURN (its break-away included), or counting down a stagger to one.
func is_on_pass() -> bool:
	return phase == Phase.RUN_IN or phase == Phase.EXTEND or phase == Phase.TURN or _stagger_left >= 0.0


## A REAR's dry pass may start: no mate is on a pass (`is_on_pass()`), and every attacker (LEAD, FLANK)
## holds its station — a holder slides off a crossing track, a member still on its lead-in could only
## slow and stall behind it.
func _rear_slot_free() -> bool:
	var squad := _squad()
	for m in squad.members():
		var mate := m.get_node_or_null("Brain") as FighterBrain if m != actor else null
		if mate == null:
			continue
		if mate.is_on_pass() or (squad.role_of(m) != SquadController.Role.REAR and not mate.is_holding()):
			return false
	return true


## True while a REAR flies its dry pass, or is due one and could start it now: the LEAD holds its next
## window (and a FLANK its `flank_wait_max` run) for it, so a dry pass never shares the sky with an
## attack (task plan §3.4). Bounded: a pass ends, and a due REAR goes the first tick no mate is on one.
func _rear_slot_taken() -> bool:
	var squad := _squad()
	for m in squad.members():
		if m == actor or squad.role_of(m) != SquadController.Role.REAR:
			continue
		var rear := m.get_node_or_null("Brain") as FighterBrain
		if rear != null and (rear.is_on_pass() or (rear._rear_due and rear.is_settled() and rear.run_budget_slack() > 0.0)):
			return true
	return false


## True while the squad's LEAD holds at its own S.
func _lead_holding() -> bool:
	var squad := _squad()
	for m in squad.members():
		if squad.role_of(m) == SquadController.Role.LEAD:
			var lead := m.get_node_or_null("Brain") as FighterBrain
			return lead != null and lead.is_holding()
	return false


## The LEAD's window closes on its own EXTEND entry — unless it has lost the lead, when
## `SquadController._reassign()` already closed it and any open window is the new LEAD's.
func _close_window() -> void:
	var squad := _squad()
	if squad != null and pass_role == SquadController.Role.LEAD and squad.role_of(actor) == SquadController.Role.LEAD:
		squad.attack_window_open = false


## At S: within `start_tolerance`, and — for a fighter that starts its run straight away — with the
## heading within 30° of the run heading. A squad member only has to reach S: it holds there, and the
## hold turns its nose onto the run.
func _at_start() -> bool:
	if actor.global_position.distance_to(pass_start) > config.start_tolerance:
		return false
	return _waits_for_window() \
			or absf(_heading().angle_to(_run_heading)) <= deg_to_rad(HANDOVER_HEADING_DEG)


# ── Lead-in paths (task plan §3) ─────────────────────────────────────────────────────────────────

func _plan_radius() -> float:
	return turn_radius() * PLAN_RADIUS_FACTOR


## Plans (when needed) and tracks a Dubins lead-in to S; the epic's ring routing with no clear path.
func _fly_to_start(delta: float, target: TargetInfo, clearance: float, first_clearance: float) -> void:
	var pos := actor.global_position
	if _waits_for_window() and pos.distance_to(pass_start) <= STATION_ARRIVE_PLAN_RADII * _plan_radius() \
			and _segment_clears(pos, pass_start, target.position, clearance):
		# A squad member's S is a station it stops at, not a run it must line up for: close in, it
		# brakes and slides onto it (a Dubins lead-in from here can be a full loop, review of t9).
		_clear_path()
		seek_target = pass_start
		_request(Steering.arrive(pos, actor.velocity, pass_start, config.max_speed, mover.braking if mover.braking > 0.0 else mover.acceleration))
		return
	var replan := _path_pts.is_empty() \
			or pass_start.distance_to(_path_goal + _path_goal_velocity * _path_age) > REPLAN_GOAL_PX \
			or pos.distance_to(_path_pts[_path_idx]) > REPLAN_OFF_PATH_PX
	if replan and _plan(target, clearance, first_clearance) and not _deadline_from_plan:
		_set_deadline_from_path()
	if _path_pts.is_empty():
		_fly_ring(delta, target, clearance)
	else:
		_track(delta)


func _segment_clears(a: Vector2, b: Vector2, point: Vector2, clearance: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) >= clearance


## The phase's deadline: this path's flying time plus `reposition_max`, measured from now.
func _set_deadline_from_path() -> void:
	var remaining := maxf(_path_length - _path_idx * TRACK_SAMPLE_PX, 0.0)
	_deadline = _phase_time + remaining / config.max_speed + config.reposition_max
	_deadline_from_plan = true


## The shortest clear Dubins path to (S, run heading); for a moving player, to where S will be on
## arrival. `first_clearance` ≥ 0 relaxes the clearance of the path's first arc (TURN's break-away).
func _plan(target: TargetInfo, clearance: float, first_clearance: float) -> bool:
	var goal := pass_start
	var path := _best_path(goal, target, clearance, first_clearance)
	if path != null and target.velocity != Vector2.ZERO:
		# Arrival time and goal depend on each other: refine T = length(S + v·T) / max_speed.
		for _k in GOAL_PREDICT_ITERATIONS:
			var t := minf(path.length / config.max_speed, GOAL_PREDICT_MAX)
			var predicted := _best_path(goal + target.velocity * t, target, clearance, first_clearance)
			if predicted == null:
				break
			path = predicted
	if path == null:
		_clear_path()
		return false
	_path_pts = path.sample(TRACK_SAMPLE_PX)
	_path_idx = 0
	_path_goal = pass_start
	_path_goal_velocity = target.velocity
	_path_age = 0.0
	_path_length = path.length
	_path_first_end = path.first_arc_samples(TRACK_SAMPLE_PX)
	return true


func _best_path(goal: Vector2, target: TargetInfo, clearance: float, first_clearance: float) -> DubinsPath:
	var pos := actor.global_position
	var rect := _corridor()
	var check_rect := rect.has_area() and rect.grow(CORRIDOR_SLACK).has_point(pos)
	var room := rect.grow(CORRIDOR_SLACK)
	var break_clear := config.pass_offset * BREAK_CLEARANCE_FACTOR
	# Planning from inside `clearance` (after a break-away): the path's start is held only to the
	# break-away clearance until it first leaves the radius (review I5).
	var starts_inside := first_clearance < 0.0 and pos.distance_to(target.position) < clearance
	# A squad member plans to S as a station (arriving along its own approach, no loop to line up);
	# everyone else arrives pointing along the run.
	var goal_heading := _run_heading.angle()
	if _waits_for_window() and goal != pos:
		goal_heading = (goal - pos).angle()
	for path in DubinsPath.candidates(pos, _heading().angle(), goal, goal_heading, _plan_radius()):
		var pts := path.sample(PLAN_SAMPLE_PX)
		var first_n := path.first_arc_samples(PLAN_SAMPLE_PX) if first_clearance >= 0.0 else -1
		var exempt := starts_inside
		var clear := true
		for i in pts.size():
			var player_then := target.position + target.velocity * (i * PLAN_SAMPLE_PX / config.max_speed)
			var dist := pts[i].distance_to(player_then)
			if exempt and dist >= clearance:
				exempt = false
			var needed := first_clearance if i <= first_n else clearance
			if exempt:
				needed = break_clear
			if dist < needed or (check_rect and not room.has_point(pts[i])):
				clear = false
				break
		if clear:
			return path
	return null


## Pure pursuit on the sampled path: a point `TRACK_AHEAD` samples past the nearest one.
func _track(delta: float) -> void:
	_path_age += delta
	var pos := actor.global_position
	var best := _path_idx
	var best_d := pos.distance_to(_path_pts[_path_idx])
	for i in range(_path_idx, mini(_path_idx + TRACK_SEARCH, _path_pts.size())):
		var d := pos.distance_to(_path_pts[i])
		if d < best_d:
			best_d = d
			best = i
	_path_idx = best
	var last := _path_pts.size() - 1
	if best + TRACK_AHEAD <= last:
		seek_target = _path_pts[best + TRACK_AHEAD]
	else:
		seek_target = _path_pts[last] + _run_heading * TRACK_AHEAD * TRACK_SAMPLE_PX
	var dir := Steering.turn_toward(_heading(), seek_target - pos, config.turn_rate, delta)
	_request(dir * config.max_speed)


## The epic's REPOSITION routing: seek a point on the standoff ring at most 90° round toward S — but
## never so far round that the straight segment to it cuts inside `clearance` (task plan t9 §2.2,
## the side-change rule's seek-target clearance). From radius r outside it, the farthest clear ring
## point is acos(c / r) + acos(c / R) round: the chord tangent to the clearance circle. In Assault the
## corridor clamp can pull the point back in, so the angle is halved until the clamped chord clears.
func _fly_ring(delta: float, target: TargetInfo, clearance: float) -> void:
	var pos := actor.global_position
	var r := pos.distance_to(pass_anchor)
	var ring_r := config.standoff_radius
	var b_now := (pos - pass_anchor).normalized()
	var b_goal := (pass_start - pass_anchor).normalized()
	var reach := PI / 2.0
	var outside := clearance > 0.0 and r > clearance and ring_r > clearance
	if outside:
		reach = minf(reach, acos(clearance / r) + acos(clearance / ring_r))
	var angle := clampf(b_now.angle_to(b_goal), -reach, reach)
	var ring := pass_anchor + b_now.rotated(angle) * ring_r
	var rect := _corridor()
	if rect.has_area():
		var inner := rect.grow(-RING_CORRIDOR_MARGIN)
		for _k in RING_SHRINK_STEPS:
			var clamped := ring.clamp(inner.position, inner.end)
			if not outside or _segment_clears(pos, clamped, pass_anchor, clearance):
				break
			angle *= 0.5
			ring = pass_anchor + b_now.rotated(angle) * ring_r
		ring = ring.clamp(inner.position, inner.end)
	seek_target = ring
	_request(Steering.turn_toward(_heading(), ring - pos, config.turn_rate, delta) * config.max_speed)


func _clear_path() -> void:
	_path_pts = PackedVector2Array()
	_path_idx = 0
	_path_goal = Vector2.INF
	_path_goal_velocity = Vector2.ZERO
	_path_age = 0.0
	_path_length = 0.0
	_path_first_end = 0



# ── Squad routing (task plan §3.3) ───────────────────────────────────────────────────────────────

## Where this fighter expects to be in `t` seconds, from its own plan — read by squad mates whose
## lead-ins route round it: along its lead-in (then at the path's end, where a squad member holds),
## round its turn-in, braking onto its station, straight on its run, extension, peel and exit; where
## it is while it holds.
func predicted_position(t: float) -> Vector2:
	var pos := actor.global_position
	if is_holding() or _loiter_time >= 0.0:
		return pos
	var tracking := phase == Phase.APPROACH or phase == Phase.REPOSITION or (phase == Phase.TURN and _turn_step == 1)
	if tracking and not _path_pts.is_empty():
		return _path_pts[mini(_path_idx + int(t * config.max_speed / TRACK_SAMPLE_PX), _path_pts.size() - 1)]
	if phase == Phase.TURN and _turn_step == 0 and config.turn_rate > 0.0:
		var omega := _turn_sign * config.turn_rate
		var v := actor.velocity
		return pos + (v.rotated(omega * t - PI / 2.0) - v.rotated(-PI / 2.0)) / omega
	var step := actor.velocity * t
	if _waits_for_window() and (phase == Phase.APPROACH or phase == Phase.REPOSITION):
		var to_station := pass_start - pos
		if step.length() > to_station.length():
			return pass_start
	return pos + step


## This fighter's routing priority in its squad: a lower number goes first and ignores those after
## it. LEAD, FLANK_LEFT, FLANK_RIGHT, then the REARs in `rear_index` order; -1 off the board (a
## disengaging fighter), which everyone routes round.
func squad_priority() -> int:
	var squad := _squad()
	if squad == null:
		return 0
	match squad.role_of(actor):
		SquadController.Role.LEAD:
			return 0
		SquadController.Role.FLANK_LEFT:
			return 1
		SquadController.Role.FLANK_RIGHT:
			return 2
		SquadController.Role.REAR:
			return 3 + maxi(squad.rear_index(actor), 0)
	return -1



# ── Weapons (epic §2.4.2) ────────────────────────────────────────────────────────────────────────

func _tick_weapons(delta: float, target: TargetInfo) -> void:
	if _telegraph_left >= 0.0:
		_hold_nose(target)
		_telegraph_left -= delta
		if _telegraph_left > 0.0:
			return
		_telegraph_left = -1.0
		_fire_burst(target)
	if _clock.is_running():
		_hold_nose(target)
		for _i in _clock.advance(delta):
			if _burst_controller != null:
				_burst_controller.fire_now()
		if not _clock.is_running():
			_end_burst()
		return
	_try_open_burst(target)


func _try_open_burst(target: TargetInfo) -> void:
	if not target.has_target or _disengage_pending or _since_burst < config.min_burst_period:
		return
	if pass_role == SquadController.Role.REAR or (_in_squad() and _role() == SquadController.Role.REAR):
		return  # a REAR's pass is dry, and so is a pass whose flier was demoted to REAR: ≤ 3 shooters
	var open := (phase == Phase.RUN_IN and _leg_a_open) or (phase == Phase.TURN and _turn_step == 0 and _leg_b_open and _nose_on(target))
	if not open:
		return
	var d := actor.global_position.distance_to(target.position)
	if d > config.fire_range:
		return
	var mode := select_weapon_mode(d)
	if mode == WeaponMode.FORWARD and not _nose_on(target):
		return  # skipped, not spent: the leg stays open
	if phase == Phase.RUN_IN:
		_leg_a_open = false
	else:
		_leg_b_open = false
	_since_burst = 0.0
	_burst_mode = mode
	if mode != weapon_mode:
		weapon_mode = mode
		weapon_mode_changed.emit(mode)
	_telegraph_left = config.burst_telegraph
	_set_light(StateLight.State.CHARGING)
	_hold_nose(target)


func _fire_burst(target: TargetInfo) -> void:
	var count: int
	var gap: float
	if _burst_mode == WeaponMode.FORWARD:
		count = rng.randi_range(config.forward_min, config.forward_max)
		gap = config.forward_gap
		_burst_controller = forward_attack
	else:
		count = rng.randi_range(config.aimed_min, config.aimed_max)
		gap = config.aimed_gap
		_burst_controller = attack
		var pattern := attack.pattern as AimedAttackPattern if attack != null else null
		if pattern != null and target.has_target:
			var hit := target.intercept(actor.global_position, config.aimed_speed)
			var lead_point: Vector2 = hit.point if hit.ok else target.position
			pattern.aim_point = target.position.lerp(lead_point, clampf(config.aimed_accuracy, 0.0, 1.0))
	_set_light(StateLight.State.ARMED)
	_clock.start(count, gap)


func _end_burst() -> void:
	_clock.stop()
	_telegraph_left = -1.0
	_burst_controller = null
	var pattern := attack.pattern as AimedAttackPattern if attack != null else null
	if pattern != null:
		pattern.aim_point = Vector2.INF
	_set_light(StateLight.State.OFF)
	if _disengage_pending:
		_disengage_pending = false
		enter_phase(Phase.DISENGAGE)


## Stops a burst without the deferred-exit handover (rails, a forced DISENGAGE).
func _abort_burst() -> void:
	if not is_bursting():
		return
	_clock.stop()
	_telegraph_left = -1.0
	_burst_controller = null
	var pattern := attack.pattern as AimedAttackPattern if attack != null else null
	if pattern != null:
		pattern.aim_point = Vector2.INF


## A FORWARD burst fires along the nose, so the nose (never the path) stays on the player.
func _hold_nose(target: TargetInfo) -> void:
	if _burst_mode == WeaponMode.FORWARD and target.has_target:
		mover.face_toward(target.position)


func _nose() -> Vector2:
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _nose_on(target: TargetInfo) -> bool:
	var to_player := target.position - actor.global_position
	return absf(_nose().angle_to(to_player)) <= deg_to_rad(config.nose_cone_deg)


## DISENGAGE now, or when the running burst ends (worst case telegraph + one burst, ≤ 0.8 s).
func _request_disengage() -> void:
	if phase == Phase.DISENGAGE:
		return
	if is_bursting():
		_disengage_pending = true
	else:
		enter_phase(Phase.DISENGAGE)


# ── DISENGAGE (the Swarm and Razor Drones' exit, curved) ─────────────────────────────────────────

func _enter_disengage() -> void:
	var squad := _squad()
	if squad != null:
		squad.leave(actor)
	_abort_burst()
	_disengage_pending = false
	_set_light(StateLight.State.OFF)
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The
## curve's rate is capped by what the mover's acceleration can follow at exit speed.
func _tick_disengage(delta: float) -> void:
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var pos := actor.global_position
	if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
		actor.queue_free()
		return
	var rate := config.turn_rate
	if config.exit_speed > 0.0:
		rate = minf(rate, config.acceleration / config.exit_speed)
	# From (nearly) rest — a squad member whose budget ran out while it held — it sets off straight
	# at the exit instead of turning round on an exit-speed arc.
	var heading := (_exit_point - pos).normalized() if actor.velocity.length() < config.max_speed * STANDING_START_FRACTION else _heading()
	var dir := Steering.turn_toward(heading, _exit_point - pos, rate, delta)
	_request(dir * config.exit_speed)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return _nose()


## The squad board `WaveManager` / `SectorHub` wrote on the actor (duck-typed), or null.
func _squad() -> SquadController:
	if actor == null:
		return null
	return actor.get(&"squad") as SquadController


## The actor's squad role; LEAD with no squad (a squad of one is its own lead).
func _role() -> int:
	var squad := _squad()
	if squad == null:
		return SquadController.Role.LEAD
	var role: int = squad.role_of(actor)
	return SquadController.Role.LEAD if role == SquadController.Role.NONE else role


## A squad of two or more: roles pick the pass kind. A squad of one flies the solo alternation.
func _in_squad() -> bool:
	var squad := _squad()
	return squad != null and squad.member_count() >= 2


## Lanes shaped by a role (FLANK_RIGHT's outer lane): squad members and the `forced_pass_kind` seam.
func _role_shaped() -> bool:
	return forced_pass_kind >= 0 or _in_squad()


## The corridor rect while the mover holds a constraint with one; `Rect2()` otherwise.
func _corridor() -> Rect2:
	if mover == null or mover.constraint == null:
		return Rect2()
	return mover.constraint.inner_rect()


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)



# ── Squad give-way (task plan §3.3) ──────────────────────────────────────────────────────────────

## Every velocity request of this brain goes through here, so the give-way can shape the tick's last
## one.
func _request(v: Vector2) -> void:
	_last_request = v
	_has_request = true
	mover.request_velocity(v)


## Squad members keep `GIVE_WAY_HULLS` hull radii from each other without anyone bending an attack:
## - a member holding (or loitering at) its S slides aside from a mate whose own plan
##   (`predicted_position()`) will cross the station — a station is a place to wait, not a line;
## - a member flying to its S slows along its own track (never turns) for a mate on a run, a turn,
##   an extension or an exit, and for a mate ahead of it in `squad_priority()` on a lead-in — and when
##   no slow-down keeps the clearance (the mate's own track runs over the point it would stop at), it
##   slides aside from those mates like a holder (task plan §3.3, Revision 3).
## A run, an extension, a turn and an exit never give way: their timing is `flank_stagger`'s
## (`_crossing_stagger()`) and the dry-pass slot's (§3.4), and their line is the pass. Strangers never
## interact.
func _give_way(delta: float) -> void:
	if not _in_squad() or phase == Phase.DISENGAGE:
		return
	if is_holding() or _loiter_time >= 0.0:
		_slide_aside(_mates())
	elif phase == Phase.APPROACH or phase == Phase.REPOSITION:
		_slow_for_mates(delta)


## Every other fighter on this fighter's board, or one that left it to DISENGAGE.
func _mates() -> Array[FighterBrain]:
	var out: Array[FighterBrain] = []
	var squad := _squad()
	for node in get_tree().get_nodes_in_group(&"enemies"):
		if node == actor or node.get(&"squad") != squad or node.is_queued_for_deletion():
			continue
		var mate := node.get_node_or_null("Brain") as FighterBrain
		if mate != null:
			out.append(mate)
	return out


func _give_way_clearance() -> float:
	return GIVE_WAY_HULLS * _hull_radius


## Steps off the planned track of every mate in `mates` that will pass within the clearance; returns
## false when none will (nothing requested).
func _slide_aside(mates: Array[FighterBrain]) -> bool:
	var pos := actor.global_position
	var clear := _give_way_clearance()
	var push := Vector2.ZERO
	for mate in mates:
		if mate.is_holding() or mate._loiter_time >= 0.0:
			# Two holders: only where they are now (one may have slid towards the other).
			var gap := pos.distance_to(mate.actor.global_position)
			if gap < clear:
				var apart := pos - mate.actor.global_position
				push += (apart / gap if gap > 0.001 else Vector2.RIGHT) * (clear - gap) / clear
			continue
		# The closest point of the mate's planned track over the horizon, and the track's direction
		# there: the member steps off the track sideways, the shortest way out (≤ one clearance), never
		# along it, where the mate would keep pushing it ahead of itself.
		var best_d := INF
		var best_q := Vector2.ZERO
		var best_dir := Vector2.ZERO
		var prev := mate.predicted_position(0.0)
		var t := GIVE_WAY_SAMPLE
		while t <= GIVE_WAY_HORIZON + 0.0001:
			var q := mate.predicted_position(t)
			var d := Geometry2D.get_closest_point_to_segment(pos, prev, q).distance_to(pos)
			if d < best_d and q != prev:
				best_d = d
				best_q = Geometry2D.get_closest_point_to_segment(pos, prev, q)
				best_dir = (q - prev).normalized()
			prev = q
			t += GIVE_WAY_SAMPLE
		if best_d >= clear or best_dir == Vector2.ZERO:
			continue
		var side := best_dir.orthogonal()
		var off := (pos - best_q).dot(side)
		if absf(off) < 0.001:
			off = (pass_start - best_q).dot(side)  # dead on the track: the side its own S is on
		push += side * signf(off if off != 0.0 else 1.0) * (clear - best_d) / clear
	if push == Vector2.ZERO:
		return false
	var target := TargetInfo.player(get_tree())
	mover.request_velocity(target.velocity + push.normalized() * GIVE_WAY_SLIDE_SPEED)
	return true


## The lead-in's deadline (`_deadline`) does not run while it gives way: waiting for a mate is not
## failing to arrive, and a deadline breach would start a run from wherever it waited.
func _slow_for_mates(delta: float) -> void:
	var clear := _give_way_clearance()
	var mine := squad_priority()
	var yield_to: Array[FighterBrain] = []
	for mate in _mates():
		if mate.is_holding() or mate._loiter_time >= 0.0:
			continue  # it slides aside
		if mate.actor.velocity.length() < config.max_speed * STANDING_START_FRACTION and not mate.is_braking_onto_station():
			continue  # slowing never waits out a mate that is not going anywhere; one about to stop it does
		var lead_in := mate.phase == Phase.APPROACH or mate.phase == Phase.REPOSITION
		if lead_in and mate.squad_priority() >= 0 and mate.squad_priority() < mine:
			yield_to.append(mate)
		elif not lead_in:
			yield_to.append(mate)
	if yield_to.is_empty():
		return
	var best_k := 1.0
	var best_gap := -INF
	for k in GIVE_WAY_STEPS:
		var gap := _closest_on_horizon(yield_to, k)
		if gap >= clear:
			best_k = k
			best_gap = gap
			break
		if gap > best_gap + 1.0:
			best_gap = gap
			best_k = k
	if best_gap < clear and _slide_aside(yield_to.filter(func(m: FighterBrain) -> bool: return m.is_on_pass())):
		_deadline += delta  # no speed keeps clear: the mate's track runs over where it would stop
	elif best_k < 1.0:
		_deadline += delta * (1.0 - best_k)
		mover.request_velocity(_last_request * best_k)


## The closest this fighter comes to any of `mates` over the horizon if it flies its own plan at `k`
## of its speed (px), but never less than how close they are now (a give-way only has to stop it
## closing in).
func _closest_on_horizon(mates: Array[FighterBrain], k: float) -> float:
	var pos := actor.global_position
	var out := INF
	for mate in mates:
		var now := pos.distance_to(mate.actor.global_position)
		var gap := INF
		var t := GIVE_WAY_SAMPLE
		while t <= GIVE_WAY_HORIZON:
			gap = minf(gap, predicted_position(t * k).distance_to(mate.predicted_position(t)))
			t += GIVE_WAY_SAMPLE
		out = minf(out, gap if gap < now else INF)
	return out
