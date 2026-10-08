## The Bomber's brain (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4).
##
## This is the t9 shell: the phase enum, the `enter_phase` seam, APPROACH as a plain intercept, and the
## Assault budget with its DISENGAGE exit. It drops nothing; t10 fills in RUN / ESCAPE / REPOSITION
## (prediction, ordnance choice, the bombing line, the Dubins approach, the drops by distance).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   intercepts the player at transit speed (`max_speed`).
##   RUN        [ATTACK]     (t10) the slow straight bombing run. StateLight ARMED.
##   ESCAPE     [REPOSITION](t10) the arc away after the drop.
##   REPOSITION [REPOSITION](t10) Open Space orbit at `standoff` between runs.
##   DISENGAGE  [DISENGAGE] Assault only: the budget ran out. Release the corridor, curve to the nearest
##                           edge of the world rect at `exit_speed`, free once outside it.
## IDLE / NOTICING / RETURNING (the hub, t19) are appended later so these values do not move.
##
## Rails: `on_suspended()` only switches the light off. The legacy bombing (a gravity bomb DOWN every
## `rail_bomb_interval`) is a clock on the `Bomber` root, because a rail stops this brain's ticks.
##
## Requests only (single-writer gate): the writes on the mover are `max_speed` and `release_constraint()`
## on DISENGAGE.
class_name BomberBrain
extends EnemyBrain

enum Phase { APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The plain intercept aims at the player this many seconds ahead (s); t10 replaces it with the bombing line.
const INTERCEPT_LOOKAHEAD := 0.5

## Set by `bomber.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: BomberConfig = BomberConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	match phase:
		Phase.APPROACH: _tick_approach()
		Phase.DISENGAGE: _tick_disengage(delta)
		_: pass  # RUN, ESCAPE and REPOSITION arrive with t10


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.RUN:
			_set_light(StateLight.State.ARMED)
		Phase.DISENGAGE:
			_enter_disengage()
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The root's rail clock does the bombing.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


func _request_disengage() -> void:
	# t10: a running run defers this to the run's end (<= run_length / run_speed).
	enter_phase(Phase.DISENGAGE)


func _tick_approach() -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	mover.intercept(target, config.max_speed, INTERCEPT_LOOKAHEAD)


# ── DISENGAGE (the Fighter's exit) ───────────────────────────────────────────────────────────────

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
