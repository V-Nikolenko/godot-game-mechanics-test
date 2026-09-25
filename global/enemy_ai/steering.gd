## Pure movement primitives (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4). Each takes a
## snapshot of the world and returns a *desired velocity* in world px/s — no state, no Node, no
## side effects — so every primitive is unit-testable alone. `EnemyMover` (t10) turns the desired
## velocity into an actual one (accel/turn/constraint limits) and is the only stateful piece;
## `boost` lives there because it needs a duration timer.
##
## Every function is safe with a zero-length or coincident vector: Godot's `Vector2.normalized()`
## already returns `Vector2.ZERO` instead of NaN when the length is zero, so a "no NaN" guard is
## built into using `normalized()` everywhere a direction is derived, rather than dividing by a
## length by hand.
class_name Steering
extends RefCounted


## Full speed straight at target_pos. Zero when pos == target_pos.
static func seek(pos: Vector2, target_pos: Vector2, max_speed: float) -> Vector2:
	return (target_pos - pos).normalized() * max_speed


## Like seek, but the speed ramps down to 0 inside a slowing radius derived from the *current*
## velocity's stopping distance, `vel.length()^2 / (2 * accel)` — never a free-tuned number
## (research §2: a too-short radius overshoots and oscillates at the ship's own accel). `accel <=
## 0` means no ramp (radius 0): full speed until exactly at the target, matching "acceleration = 0
## means instant" elsewhere in the mover. Zero at the target itself, full speed at or beyond the
## radius.
static func arrive(pos: Vector2, vel: Vector2, target_pos: Vector2, max_speed: float, accel: float) -> Vector2:
	var to_target := target_pos - pos
	var dist := to_target.length()
	if dist <= 0.0:
		return Vector2.ZERO
	var radius := (vel.length_squared() / (2.0 * accel)) if accel > 0.0 else 0.0
	var speed := max_speed
	if radius > 0.0 and dist < radius:
		speed = max_speed * (dist / radius)
	return to_target.normalized() * speed


## Exactly the Drone Interceptor's orbit formula (drone_interceptor.gd:95-109): the anchor point
## walks the circle of `radius` around `center` at `angle` (the caller advances `angle`), and the
## correction speed toward that anchor is `clamp(dist * 4, 60, max_correct_speed)`.
static func orbit(pos: Vector2, center: Vector2, radius: float, angle: float, max_correct_speed: float) -> Vector2:
	var anchor := center + Vector2.RIGHT.rotated(angle) * radius
	var to_anchor := anchor - pos
	var speed := clampf(to_anchor.length() * 4.0, 60.0, max_correct_speed)
	return to_anchor.normalized() * speed


## Reynolds pursuit: seek the target's predicted position `lookahead` seconds out, rather than
## where it is now. Zero with no target.
static func intercept(pos: Vector2, target: TargetInfo, speed: float, lookahead: float) -> Vector2:
	if target == null or not target.has_target:
		return Vector2.ZERO
	return seek(pos, target.predicted_position(lookahead), speed)


## Flee threat_pos directly.
static func retreat_from(pos: Vector2, threat_pos: Vector2, max_speed: float) -> Vector2:
	return (pos - threat_pos).normalized() * max_speed


## Flee the threat's predicted position `lookahead` seconds out, rather than where it is now.
static func evade(pos: Vector2, threat_pos: Vector2, threat_vel: Vector2, max_speed: float, lookahead: float) -> Vector2:
	return retreat_from(pos, threat_pos + threat_vel * lookahead, max_speed)


## Perpendicular to the line toward target_pos. side > 0 and side < 0 give the two opposite
## perpendiculars; side == 0 behaves as side > 0.
static func strafe(pos: Vector2, target_pos: Vector2, side: float, max_speed: float) -> Vector2:
	var perpendicular := (target_pos - pos).normalized().rotated(PI / 2.0)
	if side < 0.0:
		perpendicular = -perpendicular
	return perpendicular * max_speed


## Zero inside tolerance of anchor; arrive() at it otherwise.
static func hold_position(pos: Vector2, vel: Vector2, anchor: Vector2, tolerance: float, max_speed: float, accel: float) -> Vector2:
	if pos.distance_to(anchor) <= tolerance:
		return Vector2.ZERO
	return arrive(pos, vel, anchor, max_speed, accel)


## Constant velocity in direction, at speed. PatrolDrone's movement model. Zero with a
## zero-length direction — PatrolDrone itself is what falls that back to RIGHT (test_patrol_drone.gd).
static func drift(direction: Vector2, speed: float) -> Vector2:
	return direction.normalized() * speed
