## The Support Ship's brain (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.11; task t10: the shell).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   SEEK_WARD  [POSITION]   holds near the nearest live `BaseEnemy` ally (group `enemies`, never another support) at
##                           `follow_distance`, or drifts in place with none. t11 replaces "nearest" with the ward
##                           choice (score, threat, hysteresis) and puts the ship behind it.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor, curve away toward the nearest
##                           corridor edge at `exit_speed`, freed once outside the projectile rect (the Bomber's
##                           exit). It has no telegraphed attack, so nothing defers the exit.
##   FOLLOW / ESCORT / IDLE / NOTICING / RETURNING  reserved for t11, t13 and t15.
##
## Rails: `on_suspended()` drops the ward and folds the projector. The ship has no weapon, so there is no rail
## fallback.
##
## Requests only (single-writer gate): the writes on the mover are `arrive`, `request_velocity`, `face_toward`,
## `max_speed` and `release_constraint()` on DISENGAGE.
class_name SupportShipBrain
extends EnemyBrain

enum Phase { SEEK_WARD, FOLLOW, ESCORT, DISENGAGE, IDLE, NOTICING, RETURNING }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0
## The ship stops closing inside this distance of its hold point (px).
const HOLD_TOLERANCE := 12.0

## Set by `support_ship.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SupportShipConfig = SupportShipConfig.new()
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.SEEK_WARD
## The ally being supported, or null. t10 only holds near it.
var ward: BaseEnemy = null

var _started: bool = false
var _phase_time: float = 0.0
var _exit_point: Vector2 = Vector2.ZERO
var _expiry_seen: bool = false


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and not _expiry_seen:
		_expiry_seen = true
		if phase != Phase.DISENGAGE:
			enter_phase(Phase.DISENGAGE)
	match phase:
		Phase.SEEK_WARD: _tick_seek_ward()
		Phase.DISENGAGE: _tick_disengage(delta)


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	if p == Phase.DISENGAGE:
		_enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. Drop the ward and fold the dish; there is no weapon.
func on_suspended() -> void:
	ward = null
	if actor is SupportShip:
		(actor as SupportShip).fold_projector()


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


## The nearest live ally that is not another support, or null.
func nearest_ally() -> BaseEnemy:
	var best: BaseEnemy = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var ally := node as BaseEnemy
		if ally == null or ally == actor or ally is SupportShip or ally.is_queued_for_deletion():
			continue
		var d := actor.global_position.distance_squared_to(ally.global_position)
		if d < best_d:
			best_d = d
			best = ally
	return best


func _tick_seek_ward() -> void:
	ward = nearest_ally()
	if ward == null:
		mover.request_velocity(Vector2.ZERO)
		return
	var pos := actor.global_position
	var away := pos - ward.global_position
	var dir := away.normalized() if away.length_squared() > 1e-6 else Vector2.UP
	var hold_point := ward.global_position + dir * config.follow_distance
	if pos.distance_to(hold_point) <= HOLD_TOLERANCE:
		mover.request_velocity(Vector2.ZERO)
	else:
		mover.arrive(hold_point, config.max_speed)


func _enter_disengage() -> void:
	ward = null
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
