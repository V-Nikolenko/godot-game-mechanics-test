## The Mine Layer's brain (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.11).
##
## Phases (IDEAS §4 vocabulary in brackets):
##   APPROACH   [APPROACH]   seeks the player at `max_speed`.
##   LAY        [ATTACK]     the laying pass (later task); it refuses a tow.
##   BREAK_OFF  [EVADE]      later task.
##   REPOSITION [REPOSITION] later task.
##   DISENGAGE  [DISENGAGE]  Assault only: the budget ran out. Release the corridor, leave along the current heading
##                           (the velocity direction, else the facing) at `exit_speed`, free once outside the world rect.
##   IDLE / NOTICING / RETURNING   Open Space hub idle (later task).
## The enum is declared in full and append-only; this shell plays only APPROACH and DISENGAGE.
##
## Requests only (single-writer gate): the writes on the mover are `request_velocity`, `max_speed` and
## `release_constraint()` on DISENGAGE. Mines leave through `MineLayer.drop_mine()`.
class_name MineLayerBrain
extends EnemyBrain

enum Phase { APPROACH, LAY, BREAK_OFF, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }

signal phase_changed(new_phase: int)

## Below this speed (px/s) the heading is the nose's direction, not the velocity's.
const HEADING_MIN_SPEED := 1.0

var config: MineLayerConfig = MineLayerConfig.new()
var budget: EngagementBudget
var phase: Phase = Phase.APPROACH
## Test seam, read by the hub idle task: start in the fight instead of patrolling.
var start_engaged: bool = false

var _started: bool = false
var _phase_time: float = 0.0
var _exit_dir: Vector2 = Vector2.DOWN


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and phase != Phase.DISENGAGE:
		enter_phase(Phase.DISENGAGE)
	match phase:
		Phase.APPROACH: _tick_approach()
		Phase.DISENGAGE: _tick_disengage()


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


## `BaseEnemy.suspend_ai()`: a rail took the layer over. The root's rail clock does the laying.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)


## A committed phase is never moved by an ally (`BaseEnemy.accept_tow`).
func accepts_tow() -> bool:
	return phase != Phase.LAY


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


func _tick_approach() -> void:
	var target := TargetInfo.player(get_tree())
	if target.has_target:
		mover.seek(target.position, config.max_speed)


func _enter_disengage() -> void:
	_set_light(StateLight.State.OFF)
	_exit_dir = _heading()
	mover.release_constraint()
	mover.max_speed = config.exit_speed


## Straight out along the heading it had on entry. Strict `<`/`>` against the rect's edges, as the Bomber's exit.
func _tick_disengage() -> void:
	if EnemyWorld.has_projectile_world_rect(get_tree()):
		var rect := EnemyWorld.projectile_world_rect(get_tree())
		var pos := actor.global_position
		if pos.x < rect.position.x or pos.x > rect.end.x or pos.y < rect.position.y or pos.y > rect.end.y:
			actor.queue_free()
			return
	mover.request_velocity(_exit_dir * config.exit_speed)


## The direction of travel, or the nose's direction while (nearly) at rest.
func _heading() -> Vector2:
	if actor.velocity.length() > HEADING_MIN_SPEED:
		return actor.velocity.normalized()
	return Vector2.RIGHT.rotated(actor.rotation + EnemyMover.sprite_forward_angle_of(actor))


func _set_light(state: int) -> void:
	var light := actor.get_node_or_null("StateLight") as StateLight if actor != null else null
	if light != null:
		light.set_state(state)
