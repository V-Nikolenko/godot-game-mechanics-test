## A snapshot of a target's position, velocity and facing, taken once at construction
## (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.6). Nothing here holds a reference to the
## source Node, so reading a TargetInfo after the node it was built from is freed is safe — it can
## only ever describe where the target *was* when the snapshot was taken.
##
## `player(tree)` is the one player resolver for code this phase touches, replacing scattered
## `get_nodes_in_group("player")[0]` calls (aimed/gatling attack patterns migrate onto it in t8).
class_name TargetInfo
extends RefCounted

const NO_TARGET_AIM := Vector2.DOWN
## Below this squared length, a Vector2 is treated as the zero vector for branch selection —
## guards the quadratic solver's degenerate cases against floating-point noise, not gameplay scale.
const EPS := 0.000001

var has_target: bool = false
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
## Unit vector for the node's rotation, using the project's player/bullet convention
## (`Vector2.UP.rotated(rotation)` — see player_ship.gd, bullet.gd).
var facing: Vector2 = Vector2.ZERO


## The single player resolver. Returns has_target = false when there is no player in the tree.
static func player(tree: SceneTree) -> TargetInfo:
	if tree == null:
		return TargetInfo.new()
	var players := tree.get_nodes_in_group(&"player")
	if players.is_empty():
		return TargetInfo.new()
	return TargetInfo.of(players[0] as Node2D)


## A snapshot of any Node2D. velocity is read when node is a CharacterBody2D, else ZERO.
static func of(node: Node2D) -> TargetInfo:
	var info := TargetInfo.new()
	if node == null or not is_instance_valid(node):
		return info
	info.has_target = true
	info.position = node.global_position
	info.facing = Vector2.UP.rotated(node.rotation)
	if node is CharacterBody2D:
		info.velocity = (node as CharacterBody2D).velocity
	return info


func distance_from(p: Vector2) -> float:
	return position.distance_to(p)


## Signed angle from from_facing to the direction from p to the target, in radians.
func relative_angle_from(p: Vector2, from_facing: Vector2) -> float:
	return from_facing.angle_to(position - p)


func predicted_position(t: float) -> Vector2:
	return position + velocity * t


## Closed-form quadratic intercept: the first t >= 0 at which a shot fired from `from` at
## `shot_speed` reaches predicted_position(t). Returns {ok, point, time}; point falls back to
## position and time to 0.0 when ok is false. ok is false with no target, shot_speed <= 0, or no
## t >= 0 solution (the target outruns the shot, or is moving away at exactly the shot's speed).
func intercept(from: Vector2, shot_speed: float) -> Dictionary:
	var failure := {"ok": false, "point": position, "time": 0.0}
	if not has_target or shot_speed <= 0.0:
		return failure

	# |position - from + velocity*t| = shot_speed*t, squared and rearranged into a*t^2+b*t+c=0.
	var d := position - from
	var a := velocity.length_squared() - shot_speed * shot_speed
	var b := 2.0 * d.dot(velocity)
	var c := d.length_squared()

	var t := -1.0
	if absf(a) < EPS:
		if absf(b) < EPS:
			if absf(c) < EPS:
				t = 0.0  # target already at `from` and not separating: intercept now.
			# else: b == 0 and c != 0 has no root at all.
		else:
			var candidate := -c / b
			if candidate >= -EPS:
				t = maxf(candidate, 0.0)
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var sqrt_disc := sqrt(discriminant)
			var best := INF
			for candidate in [(-b + sqrt_disc) / (2.0 * a), (-b - sqrt_disc) / (2.0 * a)]:
				if candidate >= -EPS and candidate < best:
					best = candidate
			if best != INF:
				t = maxf(best, 0.0)

	if t < 0.0:
		return failure
	return {"ok": true, "point": predicted_position(t), "time": t}


## Blends direct aim at position (accuracy 0.0) with the intercept point (accuracy 1.0). A failed
## intercept falls back to direct aim at every accuracy. No target returns Vector2.DOWN, matching
## every attack pattern's existing no-target fallback.
func aim_direction(from: Vector2, shot_speed: float, accuracy: float) -> Vector2:
	if not has_target:
		return NO_TARGET_AIM
	var result := intercept(from, shot_speed)
	var intercept_point: Vector2 = result.point if result.ok else position
	var blended := position.lerp(intercept_point, clampf(accuracy, 0.0, 1.0))
	var dir := blended - from
	if dir.length_squared() < EPS:
		return NO_TARGET_AIM
	return dir.normalized()


## Stub — always agrees with has_target. The real raycast lands in Phase 4 (sniper LOS, IDEAS §28).
func line_of_sight(_from: Vector2) -> bool:
	return has_target
