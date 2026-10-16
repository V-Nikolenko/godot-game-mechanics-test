## The Missile Corvette's brain (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.9; task t7: the minimal brain).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   closes to the held range along the line to the player and settles there.
##   HOLD_ARC / TELEGRAPH / SALVO  reserved for t8 (the fight): the enum is append-only, so they exist now and the
##              brain never enters them yet.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor, curve away from the player toward
##                           the nearest corridor edge at `exit_speed`, freed once outside the projectile rect (the
##                           Bomber's exit).
##   IDLE / NOTICING / RETURNING  reserved for t15 (the hub idle).
##
## Rails: `on_suspended()` only switches the light off. The rocket fallback is a clock on the `MissileCorvette` root,
## because a rail stops this brain's ticks.
##
## Requests only (single-writer gate): the writes on the mover are `arrive`, `request_velocity`, `max_speed` and
## `release_constraint()` on DISENGAGE.
class_name MissileCorvetteBrain
extends EnemyBrain

enum Phase { APPROACH, HOLD_ARC, TELEGRAPH, SALVO, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0

## Set by `missile_corvette.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: MissileCorvetteConfig = MissileCorvetteConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.APPROACH
## Test seam (the hub idle lands in t15): a spawned corvette starts already fighting. Assault ignores it.
var start_engaged: bool = false

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and phase != Phase.DISENGAGE:
		enter_phase(Phase.DISENGAGE)
	match phase:
		Phase.APPROACH: _tick_approach()
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	match p:
		Phase.DISENGAGE:
			_enter_disengage()
		_:
			_set_light(StateLight.State.OFF)
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The root's rail clock fires the fallback rocket.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


## The range the corvette holds: the corridor is narrower than the open sky.
func held_range() -> float:
	return config.assault_preferred_range if budget != null and budget.active else config.preferred_range


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


func _tick_approach() -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		return
	var pos := actor.global_position
	var away := pos - target.position
	if away.length() < 1.0:
		away = Vector2.UP
	mover.arrive(target.position + away.normalized() * held_range(), config.max_speed)
	mover.face_toward(target.position)


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
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)


## The telegraphed phases are never moved by an ally (`BaseEnemy.accept_tow`). They are not entered until t8.
func accepts_tow() -> bool:
	match phase:
		Phase.TELEGRAPH, Phase.SALVO:
			return false
	return true
