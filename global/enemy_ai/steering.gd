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


## Exactly the Razor Drone's orbit formula (razor_drone_brain.gd:95-109): the anchor point
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


## Constant velocity in direction, at speed. Zero with a zero-length direction — the caller decides
## the fallback (the retired ambient hub drone fell back to RIGHT).
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


## Phase 4 addition (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.2.1).


## Open the distance to a threat without fleeing straight down its line of advance: away from
## `threat_pos`, plus a sideways share (`lateral_weight` of the away component, on the `side`
## the caller chose; `side < 0` is the left-hand mirror, anything else the right, as in `strafe`).
## A *closing* threat (moving along the away axis, i.e. toward `pos`) doubles the lateral share —
## a straight flight from a faster pursuer is the one direction it always catches. Always
## `max_speed` long. Coincident positions have no away axis, so the ship leaves across the
## threat's velocity, else `RIGHT` — finite, never NaN.
static func break_contact(pos: Vector2, threat_pos: Vector2, threat_vel: Vector2, side: float, max_speed: float, lateral_weight: float = 0.6) -> Vector2:
	var offset := pos - threat_pos
	if offset.length() < 1e-3:
		var across := threat_vel.orthogonal().normalized()
		if across == Vector2.ZERO:
			across = Vector2.RIGHT
		return across * max_speed
	var away := offset.normalized()
	var lateral := away.orthogonal() * (-1.0 if side < 0.0 else 1.0)
	var weight := lateral_weight * (2.0 if threat_vel.dot(away) > 0.0 else 1.0)
	return (away + lateral * weight).normalized() * max_speed


## Phase 6 addition (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md §2.4; task plan
## docs/plans/cmvg30aa90073qs2xrw74hcvg/3-plan.md, which records the four refinements below).

## Headings the context stage chooses among (slot 0 = +x). Between F2's 8 and 32: judgement.
const CONTEXT_SLOTS := 16
## Seconds ahead a hazard is led by its `velocity`, and the speed share of the danger skirt (`|desired| · this`).
const CONTEXT_LOOKAHEAD := 0.6
## Share of the previous step's heading blended into the interest map (hysteresis, F1).
const CONTEXT_PREV_BLEND := 0.5
## The stage never slows a ship below this share of its desired speed: round the edge, never a stall.
const CONTEXT_MIN_SPEED_RATIO := 0.35


## Context steering (Fray, research F1/F2) as one pure function: the brain's `desired` velocity is the
## interest map, every `HazardInfo` in `infos` writes a danger map, and the result is the heading with the
## least danger nearest the brain's own. Returns `desired` itself — the same value, bit for bit — when nothing
## is in the way, so a ship with no hazard near flies exactly as it did before hazards existed.
##
## Per hazard, centred `velocity · lookahead` ahead (a drifting hazard is led), at distance `d` with radius `R`:
## a skirt `clamp(1 − max(0, d − R) / (margin + |desired| · lookahead), 0, 1)` times a cone round the hazard's
## bearing of half-width `asin(min(1, (R + margin) / d))` widened by one slot, scaled by `avoid_weight`.
## Inside (`d ≤ R`) that is the full 90° half-plane plus one slot, at skirt 1: every heading within 112.5° of
## the centre is dangerous and every outward one is not. Maps merge per slot by MAX, never a sum. A slot's
## danger counts only above `1 − avoidance` (R6.8: a soft profile ignores glancing danger).
##
## Then, with `lo` the least danger of any slot: if the two slots either side of `desired` (or the one slot it
## lies on) carry `lo`, `desired` is returned unchanged. Otherwise every slot above `lo` is masked, the unmasked
## slot nearest `(1 − CONTEXT_PREV_BLEND) · want + CONTEXT_PREV_BLEND · prev_dir` wins (the side chosen last
## step keeps winning; the brain's own heading when the two cancel), its heading is refined by parabolic
## interpolation with its neighbours (at most half a slot; the one-slot widening keeps that outside the tangent),
## and the speed is `|desired|` times that heading's own interest, floored at `CONTEXT_MIN_SPEED_RATIO`.
static func context_avoid(pos: Vector2, desired: Vector2, infos: Array, avoidance: float, margin: float,
		lookahead: float, prev_dir: Vector2) -> Vector2:
	if infos.is_empty() or desired == Vector2.ZERO or avoidance <= 0.0:
		return desired
	var speed := desired.length()
	var want := desired / speed
	var slot := TAU / CONTEXT_SLOTS
	var skirt_reach := margin + speed * lookahead
	var danger := PackedFloat64Array()
	danger.resize(CONTEXT_SLOTS)
	danger.fill(0.0)
	for info: HazardInfo in infos:
		if info == null or info.avoid_weight <= 0.0:
			continue
		var to := info.position + info.velocity * lookahead - pos
		var d := to.length()
		if d < 0.001:
			continue  # on the centre: no bearing, and every heading leaves it alike
		var outside := maxf(0.0, d - info.radius)
		var skirt := 1.0
		if outside > 0.0:
			if skirt_reach <= 0.0:
				continue
			skirt = 1.0 - outside / skirt_reach
			if skirt <= 0.0:
				continue
		var half_width := asin(minf(1.0, (info.radius + margin) / d)) + slot
		var bearing := to.angle()
		for i in CONTEXT_SLOTS:
			var off := absf(angle_difference(bearing, i * slot))
			if off < half_width:
				danger[i] = maxf(danger[i], info.avoid_weight * skirt * (1.0 - off / half_width))

	var threshold := 1.0 - avoidance
	var lo := INF
	for i in CONTEXT_SLOTS:
		danger[i] = maxf(0.0, danger[i] - threshold)
		lo = minf(lo, danger[i])
	# Clear way: `desired` lies between two slots that carry the least danger, or on one that does. `angle()` is
	# a 32-bit float, so an axis-aligned request lands a hair off its slot: within 1e-4 of one it is on it.
	var at := fposmod(want.angle(), TAU) / slot
	var on_slot := absf(at - roundf(at)) < 1e-4
	var below := (roundi(at) if on_slot else int(at)) % CONTEXT_SLOTS
	var clear := danger[below] <= lo
	if clear and not on_slot:
		clear = danger[(below + 1) % CONTEXT_SLOTS] <= lo
	if clear:
		return desired

	var aim := want
	if prev_dir != Vector2.ZERO:
		var blended := want * (1.0 - CONTEXT_PREV_BLEND) + prev_dir.normalized() * CONTEXT_PREV_BLEND
		if blended.length_squared() > 1e-6:
			aim = blended  # a brain that reversed its request cancels the blend: its own heading ranks
	var score := PackedFloat64Array()
	score.resize(CONTEXT_SLOTS)
	var best := -1
	for i in CONTEXT_SLOTS:
		score[i] = Vector2.from_angle(i * slot).dot(aim)
		if danger[i] <= lo and (best < 0 or score[i] > score[best]):
			best = i
	var before := score[(best + CONTEXT_SLOTS - 1) % CONTEXT_SLOTS]
	var after := score[(best + 1) % CONTEXT_SLOTS]
	var curvature := before - 2.0 * score[best] + after
	var shift := 0.0
	if curvature < -1e-9:
		shift = clampf(0.5 * (before - after) / curvature, -0.5, 0.5)
	var heading := Vector2.from_angle((best + shift) * slot)
	return heading * speed * maxf(heading.dot(want), CONTEXT_MIN_SPEED_RATIO)
