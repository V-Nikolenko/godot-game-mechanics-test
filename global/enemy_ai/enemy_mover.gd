## The movement half of an AI-driven enemy (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4).
##
## A child `Node` of the enemy's `CharacterBody2D`. The brain *requests* movement during its
## `tick()`; the owner (`BaseEnemy._physics_process`) then calls `step(delta)`, which turns the
## request into the actor's velocity and facing. While present, this node is the **single writer**
## of the actor's `velocity` and `rotation` and the only caller of `move_and_slide()` — gated by
## `tests/integration/test_enemy_mover_single_writer.gd`.
##
## Requests are **per step**: `step()` clears them, so a brain that stops requesting slows to a
## stop at `braking`. `request_velocity()` is the one primary request — a second call in the same
## tick replaces the first. `add_nudge()` is an *offered* additive correction on top of it. No
## weighted blending of primitives (rejected: cancellation shows as stalls).
##
## `step()`:
## 1. desired = boost velocity while boosting, else primary + nudges, capped at `max_speed`;
## 2. accel/braking limits (skipped while boosting);
## 3. `constraint.filter(position, v)` if there is a constraint;
## 4. `actor.velocity = v; actor.move_and_slide()`;
## 5. facing — the one rule: `rotation → heading.angle() - sprite_forward_angle`, where heading is
##    the `face_toward()` direction if requested, else `v`, and `sprite_forward_angle` is read
##    duck-typed from the actor (default `PI / 2`, nose-down) so nothing here is typed against
##    `BaseEnemy`.
##
## Every limit uses "0 = off / instant", so an unconfigured mover is a pass-through.
class_name EnemyMover
extends Node

enum ConstraintMode {
	AUTO, ## Resolve the mode's constraint once in `_ready()` via `EnemyWorld.movement_constraint()`.
	NONE, ## Never resolve one (an injected `constraint` still applies).
}

const DEFAULT_SPRITE_FORWARD_ANGLE := PI / 2.0

## Cap on the non-boost velocity, px/s. 0 = uncapped.
@export var max_speed: float = 0.0
## Cap on the velocity change per second when speeding up, px/s². 0 = instant.
@export var acceleration: float = 0.0
## Cap on the velocity change per second when the desired speed is below the current one, px/s².
## 0 = same as `acceleration`.
@export var braking: float = 0.0
## `lerp_angle` factor per second toward the target facing. 0 = snap to it.
@export var turn_lerp: float = 0.0
## Cap on the rotation change, rad/s (IDEAS §3.1 `turn_rate`). 0 = off.
@export var max_turn_rate: float = 0.0
@export var constraint_mode: ConstraintMode = ConstraintMode.AUTO

## The body this mover drives: the parent, if it is a `CharacterBody2D`; null otherwise (inert).
var actor: CharacterBody2D
## The mode's movement rule. Set before `add_child` to inject one (tests do); an injected
## constraint wins over `AUTO`.
var constraint: MovementConstraint

var _primary: Vector2 = Vector2.ZERO
var _nudge: Vector2 = Vector2.ZERO
var _face_point: Vector2 = Vector2.ZERO
var _has_face_point: bool = false
var _boost_velocity: Vector2 = Vector2.ZERO
var _boost_left: float = 0.0


func _ready() -> void:
	var parent := get_parent()
	actor = parent as CharacterBody2D
	if parent != null and actor == null:
		push_warning("[EnemyMover] Parent %s is not a CharacterBody2D; the mover stays inert." % parent.name)
	if constraint == null and constraint_mode == ConstraintMode.AUTO:
		constraint = EnemyWorld.movement_constraint(get_tree()) as MovementConstraint


# ── Requests (called by the brain during its tick) ─────────────────────────────────────────────

## The one primary request for this step. A second call in the same tick replaces the first.
func request_velocity(v: Vector2) -> void:
	_primary = v


## An offered, additive correction summed onto the primary request this step.
func add_nudge(v: Vector2) -> void:
	_nudge += v


## Face `point` this step instead of the direction of travel.
func face_toward(point: Vector2) -> void:
	_face_point = point
	_has_face_point = true


## For `duration` seconds, move at `dir.normalized() * speed`, ignoring requests, nudges,
## `max_speed` and the accel/braking limits. The constraint still applies. Replaces any current boost.
func boost(dir: Vector2, speed: float, duration: float) -> void:
	_boost_velocity = dir.normalized() * speed
	_boost_left = duration


func is_boosting() -> bool:
	return _boost_left > 0.0


## Stop dead: zero the actor's velocity, clear every request and cancel any boost. Used by
## `BaseEnemy.suspend_ai()`, so the mover stays the only writer of velocity.
func halt() -> void:
	_clear_requests()
	_boost_left = 0.0
	_boost_velocity = Vector2.ZERO
	if actor != null:
		actor.velocity = Vector2.ZERO


# ── Steering wrappers: one-liners over `Steering`, no maths of their own ───────────────────────

func seek(target_pos: Vector2, speed: float) -> void:
	request_velocity(Steering.seek(_pos(), target_pos, speed))


## Slows using the rate the mover actually decelerates at (`braking`, or `acceleration` when that
## is 0), so the slowing radius matches the braking the step applies.
func arrive(target_pos: Vector2, speed: float) -> void:
	request_velocity(Steering.arrive(_pos(), _vel(), target_pos, speed, _decel()))


func orbit(center: Vector2, radius: float, angle: float, max_correct_speed: float) -> void:
	request_velocity(Steering.orbit(_pos(), center, radius, angle, max_correct_speed))


func intercept(target: TargetInfo, speed: float, lookahead: float) -> void:
	request_velocity(Steering.intercept(_pos(), target, speed, lookahead))


func retreat_from(threat_pos: Vector2, speed: float) -> void:
	request_velocity(Steering.retreat_from(_pos(), threat_pos, speed))


func evade(threat_pos: Vector2, threat_vel: Vector2, speed: float, lookahead: float) -> void:
	request_velocity(Steering.evade(_pos(), threat_pos, threat_vel, speed, lookahead))


func strafe(target_pos: Vector2, side: float, speed: float) -> void:
	request_velocity(Steering.strafe(_pos(), target_pos, side, speed))


func hold_position(anchor: Vector2, tolerance: float, speed: float) -> void:
	request_velocity(Steering.hold_position(_pos(), _vel(), anchor, tolerance, speed, _decel()))


func drift(direction: Vector2, speed: float) -> void:
	request_velocity(Steering.drift(direction, speed))


# ── The step (called by the owner after the brain's tick) ──────────────────────────────────────

func step(delta: float) -> void:
	if actor == null:
		_clear_requests()
		return

	var boosting := is_boosting()
	var v: Vector2
	if boosting:
		v = _boost_velocity
	else:
		var desired := _primary + _nudge
		if max_speed > 0.0:
			desired = desired.limit_length(max_speed)
		var current := actor.velocity
		var rate := acceleration
		if braking > 0.0 and desired.length() < current.length():
			rate = braking
		v = current.move_toward(desired, rate * delta) if rate > 0.0 else desired

	if constraint != null:
		v = constraint.filter(actor.global_position, v)

	actor.velocity = v
	actor.move_and_slide()

	var heading := (_face_point - actor.global_position) if _has_face_point else v
	if heading.length_squared() > 0.000001:
		var target := heading.angle() - _sprite_forward_angle()
		var current_rotation := actor.rotation
		var next := target if turn_lerp <= 0.0 else lerp_angle(current_rotation, target, delta * turn_lerp)
		if max_turn_rate > 0.0:
			var cap := max_turn_rate * delta
			next = current_rotation + clampf(angle_difference(current_rotation, next), -cap, cap)
		actor.rotation = next

	if boosting:
		_boost_left -= delta
	_clear_requests()


func _clear_requests() -> void:
	_primary = Vector2.ZERO
	_nudge = Vector2.ZERO
	_has_face_point = false


func _pos() -> Vector2:
	return actor.global_position if actor != null else Vector2.ZERO


func _vel() -> Vector2:
	return actor.velocity if actor != null else Vector2.ZERO


func _decel() -> float:
	return braking if braking > 0.0 else acceleration


## The actor's `sprite_forward_angle`, read duck-typed; `PI / 2` (nose-down) when it has none.
func _sprite_forward_angle() -> float:
	if actor == null:
		return DEFAULT_SPRITE_FORWARD_ANGLE
	var value: Variant = actor.get(&"sprite_forward_angle")
	if value is float or value is int:
		return float(value)
	return DEFAULT_SPRITE_FORWARD_ANGLE
