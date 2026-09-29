## The Fighter's brain (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4, §2.8; task t8a-fighter-shell).
##
## This is the *shell* of the attack-run brain: the full phase vocabulary, the Assault engagement
## budget and exit, and the rail fallback. The attack run itself (pass geometry, weapon selection,
## bursts) arrives in t8b, so today an AI fighter closes on the player, holds at `standoff_radius`
## and never fires.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   a plain curved intercept: predicted player position, heading bent by
##                           `Steering.turn_toward()` at `turn_rate`. Brakes at `standoff_radius`.
##   RUN_IN     [ATTACK]     t8b
##   EXTEND     [ATTACK]     t8b
##   TURN       [REPOSITION] t8b
##   REPOSITION [REPOSITION] t8b
##   DISENGAGE  [DISENGAGE]  Assault only (`EngagementBudget`): release the corridor, curve toward
##                           the nearest edge of the projectile world rect, free once outside it.
##
## Rails (§2.8, X1): `EnemyPathMover` suspends the AI through `BaseEnemy.suspend_ai()`, which calls
## `on_suspended()` — the brain hands its `AttackController` back to self-timed fire, with a pattern
## equivalent to the legacy weapon, so a fighter on a level-1 or station rail is never silent.
## `aim_mode` is read there and nowhere else: an AI fighter ignores it.
##
## Requests only (single-writer gate): the one field write on the mover is `max_speed`, plus
## `release_constraint()`, on DISENGAGE. `fighter.gd` copies the config on in its `_ready()`, which
## runs AFTER this node's, so the budget is built on the first tick.
class_name FighterBrain
extends EnemyBrain

## t12 appends IDLE, NOTICING and RETURNING.
enum Phase { APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## The player-lead window APPROACH aims with (s).
const LEAD_MIN := 0.3
const LEAD_MAX := 0.8
## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## Rail fire leaves from this far behind the hull's centre along local +y, as it always did (px).
const RAIL_SPAWN_OFFSET := Vector2(0.0, 10.0)

## Set by `fighter.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: FighterConfig = FighterConfig.new()
## The rail fallback's aim mode, resolved once by `fighter.gd`: the spawn prop if set, else the
## config default. "FORWARD" or "PLAYER".
var rail_aim_mode: String = "PLAYER"
## The sibling `AttackController` past `attack` (`ForwardAttack`), or null. t8b fires it.
var forward_attack: AttackController

var phase: Phase = Phase.APPROACH
## Built on the first tick. Null before it.
var budget: EngagementBudget

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	super._ready()
	var parent := get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling is AttackController and sibling != attack:
			forward_attack = sibling
			break


func tick(delta: float) -> void:
	if not _started:
		_start()
	if budget.update(delta) and phase != Phase.DISENGAGE:
		enter_phase(Phase.DISENGAGE)
	_phase_time += delta
	var target := TargetInfo.player(get_tree())
	match phase:
		Phase.APPROACH: _tick_approach(delta, target)
		Phase.DISENGAGE: _tick_disengage(delta)
		_: pass  # RUN_IN .. REPOSITION: t8b


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	phase = p
	_phase_time = 0.0
	if p == Phase.DISENGAGE:
		_enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. Self-timed fire from the same pool, from
## config fields (`rail_*`), so the round-lifetime sweep reads the same numbers the rail fires with.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)
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


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func _tick_approach(delta: float, target: TargetInfo) -> void:
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	var pos := actor.global_position
	var distance := pos.distance_to(target.position)
	if distance <= config.standoff_radius:
		mover.request_velocity(Vector2.ZERO)
		mover.face_toward(target.position)
		return
	var lead := Steering.clamped_lead_time(distance, config.max_speed, LEAD_MIN, LEAD_MAX)
	var desired := target.predicted_position(lead) - pos
	var dir := Steering.turn_toward(_heading(), desired, config.turn_rate, delta)
	mover.request_velocity(dir * config.max_speed)


# ── DISENGAGE (the Swarm and Razor Drones' exit, curved) ─────────────────────────────────────────

func _enter_disengage() -> void:
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
	var dir := Steering.turn_toward(_heading(), _exit_point - pos, rate, delta)
	mover.request_velocity(dir * config.exit_speed)


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
