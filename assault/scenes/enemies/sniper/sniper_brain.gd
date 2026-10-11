## The Sniper's brain (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5).
##
## This is the t12 shell: the phase enum, ENTER as a plain seek to the nearest legal firing point, and the
## Assault budget with its DISENGAGE exit. It aims and fires nothing; t13 fills in the relocation loop
## (BREAK_CONTACT -> RELOCATE -> SETTLE -> AIM -> LOCK -> FIRE), the firing-point selection and the
## line-of-sight gate, and t14 the decoy.
##
## Phases (IDEAS §4 vocabulary in brackets):
##   ENTER         [APPROACH]    seeks the nearest legal firing point at `relocate_speed`, then holds there.
##                               There is no fly-in timer: its length is `distance / relocate_speed`.
##   BREAK_CONTACT [REPOSITION]  (t13) opens the range after a shot.
##   RELOCATE      [POSITION]    (t13) slides to the next firing point.
##   SETTLE        [POSITION]    (t13) comes to rest and re-checks line of sight.
##   DECOY         [ATTACK]      (t14) the fake orange line, behind `decoy_telegraph`.
##   AIM, LOCK     [ATTACK]      (t13) stationary: the player's window.
##   FIRE          [ATTACK]      (t13) one rail round, then BREAK_CONTACT.
##   DISENGAGE     [DISENGAGE]   Assault only: the budget ran out. Release the corridor, curve to the nearest
##                               edge of the world rect at `exit_speed`, free once outside it.
##
## The nearest legal point (t12): on the ring of `preferred_range` round the player, on the sniper's own
## side of it; in Assault also inside `inner_rect()` shrunk by `fire_margin`.
##
## Rails: `on_suspended()` starts the telegraph's own legacy aim / lock / fire cycle (§2.8). A rail stops this
## brain's ticks, and the cycle never writes the ship's rotation.
##
## Requests only (single-writer gate): the writes on the mover are `max_speed` and `release_constraint()` on
## DISENGAGE.
class_name SniperBrain
extends EnemyBrain

enum Phase { ENTER, BREAK_CONTACT, RELOCATE, SETTLE, DECOY, AIM, LOCK, FIRE, DISENGAGE }

## Emitted on every transition, with the phase entered.
signal phase_changed(new_phase: int)

## DISENGAGE seeks a point this far beyond the chosen edge (px).
const EXIT_OVERSHOOT := 64.0
## Below this speed the heading is read from the actor's rotation instead of its velocity (px/s).
const HEADING_MIN_SPEED := 1.0

## Set by `sniper.gd` before the first tick. A fresh default keeps a bare brain steppable.
var config: SniperConfig = SniperConfig.new()
## Set by `sniper.gd`: the aim line and rail fallback. Null in a bare brain.
var telegraph: SniperTelegraph
## Built on the first tick. Null before it. Inactive (never expires) outside Assault.
var budget: EngagementBudget

var phase: Phase = Phase.ENTER
## True once ENTER has reached its point.
var arrived: bool = false

var _started: bool = false
var _phase_time: float = 0.0
var _entry_point: Vector2 = Vector2.ZERO
var _exit_point: Vector2 = Vector2.ZERO


func tick(delta: float) -> void:
	if not _started:
		_start()
	_phase_time += delta
	if budget.update(delta) and phase != Phase.DISENGAGE:
		_request_disengage()
	match phase:
		Phase.ENTER: _tick_enter()
		Phase.DISENGAGE: _tick_disengage(delta)
		_: pass  # the relocation loop arrives with t13


## Test seam and the one place a transition happens: runs `p`'s entry code, then emits.
func enter_phase(p: Phase) -> void:
	if not _started:
		_start()
	phase = p
	_phase_time = 0.0
	_set_light(StateLight.State.OFF)
	if telegraph != null:
		telegraph.hide_line()
	if p == Phase.DISENGAGE:
		_enter_disengage()
	phase_changed.emit(p)


## `BaseEnemy.suspend_ai()`: a rail took the enemy over. The telegraph's cycle does the shooting.
func on_suspended() -> void:
	_set_light(StateLight.State.OFF)
	if telegraph != null:
		telegraph.start_rail_cycle()


func _start() -> void:
	_started = true
	budget = EngagementBudget.new(config.engage_seconds, get_tree())


func _request_disengage() -> void:
	# t13: a sniper in AIM or LOCK defers this until its shot is fired (<= aim + lock).
	enter_phase(Phase.DISENGAGE)


# ── ENTER ────────────────────────────────────────────────────────────────────────────────────────

func _tick_enter() -> void:
	var target := TargetInfo.player(get_tree())
	if not target.has_target:
		mover.request_velocity(Vector2.ZERO)
		return
	_entry_point = nearest_firing_point(target.position)
	# Arrival latches with hysteresis: `Steering.arrive` at rest has a zero slowing radius, so re-seeking a point
	# the sniper is already on would chatter at full speed round it. It holds still until the point is out of
	# reach again (twice the arrival radius), e.g. because the player moved.
	var dist := (_entry_point - actor.global_position).length()
	if dist <= config.arrive_radius:
		arrived = true
	elif dist > config.arrive_radius * 2.0:
		arrived = false
	if arrived:
		mover.request_velocity(Vector2.ZERO)
		mover.face_toward(target.position)
	else:
		mover.arrive(_entry_point, config.relocate_speed)


## The nearest legal firing point for a player at `player_pos`: on the ring of the mode's preferred range
## round it, on this sniper's side; in Assault inside the corridor's `inner_rect()` shrunk by `fire_margin`.
func nearest_firing_point(player_pos: Vector2) -> Vector2:
	var away := actor.global_position - player_pos
	if away.length_squared() < 1.0:
		away = Vector2.UP
	var point := player_pos + away.normalized() * _preferred_range()
	if mover.constraint != null:
		var rect := mover.constraint.inner_rect().grow(-config.fire_margin)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			point = Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point


## The mode's firing distance: the tighter Assault value when the corridor (and so the budget) is on.
func _preferred_range() -> float:
	return config.assault_preferred_range if budget != null and budget.active else config.preferred_range


# ── DISENGAGE (the Fighter's exit) ───────────────────────────────────────────────────────────────

func _enter_disengage() -> void:
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


## Deliberately strict `<`/`>` against the rect's edges, not `Rect2.has_point()` (half-open). The curve's
## rate is capped by what the mover's acceleration can follow at exit speed.
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
