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


## Phase 2 additions (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.2).


## Like `orbit`, but with an added radial term so the caller can widen or narrow the ring the
## anchor sits on: `radius_rate` is the speed, px/s, the returned velocity carries outward
## (positive) or inward (negative) along the line from `center` through `pos`. Zero holds the
## current radius exactly — at the anchor itself (`pos == anchor`) the tangential term is already
## zero (as in `orbit`), so the whole return value is the radial term alone.
static func spiral(pos: Vector2, center: Vector2, radius: float, angle: float, radius_rate: float, max_correct_speed: float) -> Vector2:
	var v := orbit(pos, center, radius, angle, max_correct_speed)
	v += (pos - center).normalized() * radius_rate
	return v


## Forward motion plus a perpendicular sinusoid of `amplitude`, at `phase` (the caller advances
## `phase` itself each tick). Its mean over one full period of `phase` is `forward_dir * speed` —
## the sinusoid only bends the path, it never changes the average heading. Zero `forward_dir`
## collapses both terms to zero.
static func corkscrew(_pos: Vector2, forward_dir: Vector2, speed: float, amplitude: float, phase: float) -> Vector2:
	var forward := forward_dir.normalized()
	var perpendicular := forward.rotated(PI / 2.0)
	return forward * speed + perpendicular * amplitude * sin(phase)


## `arrive` at a slot fixed relative to a moving formation: `anchor + slot_offset` rotated by
## `heading`'s facing. A zero `slot_offset` is exactly `arrive` at `anchor` itself.
static func formation_slot(pos: Vector2, vel: Vector2, anchor: Vector2, heading: Vector2, slot_offset: Vector2, speed: float, decel: float) -> Vector2:
	var target := anchor + slot_offset.rotated(heading.angle())
	return arrive(pos, vel, target, speed, decel)


## Boids separation: push away from every neighbour within `radius`, strongest at zero distance.
## Zero with no neighbours. A neighbour exactly on top of `pos` has no defined direction to push
## along, so it pushes along a fixed axis instead of dividing by zero — finite, never NaN.
static func separation(pos: Vector2, neighbours: Array[Vector2], radius: float) -> Vector2:
	var push := Vector2.ZERO
	for neighbour in neighbours:
		var offset := pos - neighbour
		var dist := offset.length()
		if dist >= radius:
			continue
		if dist <= 0.0001:
			push += Vector2.RIGHT * radius
		else:
			push += offset.normalized() * (radius - dist)
	return push


## Boids alignment: the mean of the neighbours' velocities. Zero with no neighbours.
static func alignment(_vel: Vector2, neighbour_vels: Array[Vector2]) -> Vector2:
	if neighbour_vels.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for v in neighbour_vels:
		total += v
	return total / neighbour_vels.size()


## Boids cohesion: the vector from `pos` toward the neighbours' centroid. Zero with no neighbours.
static func cohesion(pos: Vector2, neighbours: Array[Vector2]) -> Vector2:
	if neighbours.is_empty():
		return Vector2.ZERO
	var centroid := Vector2.ZERO
	for neighbour in neighbours:
		centroid += neighbour
	centroid /= neighbours.size()
	return centroid - pos


## The 0.4-0.8 s ram prediction window (finding 5): `distance / speed`, clamped to `[t_min, t_max]`.
## A zero or negative `speed` returns `t_min` rather than dividing by zero.
static func clamped_lead_time(distance: float, speed: float, t_min: float, t_max: float) -> float:
	if speed <= 0.0:
		return t_min
	return clampf(distance / speed, t_min, t_max)


## The only way a brain bends a path (D7): rotates the unit vector `current_dir` toward
## `desired_dir` by at most `max_rate * delta` radians, taking the short way across ±π, and never
## overshooting past `desired_dir`. Always returns a unit vector. A zero `current_dir` snaps
## straight to `desired_dir` (nothing to rotate from); a zero `desired_dir` holds `current_dir`
## (nothing to rotate toward).
static func turn_toward(current_dir: Vector2, desired_dir: Vector2, max_rate: float, delta: float) -> Vector2:
	if current_dir == Vector2.ZERO:
		return desired_dir.normalized()
	if desired_dir == Vector2.ZERO:
		return current_dir.normalized()
	var current := current_dir.normalized()
	var desired := desired_dir.normalized()
	var diff := current.angle_to(desired)
	var step := clampf(diff, -max_rate * delta, max_rate * delta)
	return current.rotated(step)
