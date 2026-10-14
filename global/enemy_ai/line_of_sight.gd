## Can `from` see `to`, or does a rock stand between them? (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.2.2.)
##
## One ray on the beam's own block mask (`ENVIRONMENT | HAZARD_CONTACT`), bodies only — a hurtbox,
## trigger or pickup never blocks. Blocking is **opt-in**: a hit blocks only if its collider is in
## group `asteroids` or answers `blocks_line_of_sight() == true` (duck-typed, like
## `Bullet.is_armored()`; later phases' wrecks plug in through it). Any other body — a fighter, the
## player — is added to the exclude list and the ray recast, at most `MAX_RECASTS` times; past the
## cap the line counts as clear. The recast loop is new code: `beam_behavior.gd` casts a single
## ray and only the mask comes from it.
##
## Physics-step only (F12): the space state is not safe to query elsewhere. The brain tick is the
## physics step, so a brain may call it directly.
class_name LineOfSight
extends RefCounted

const BLOCK_MASK := CollisionLayers.ENVIRONMENT | CollisionLayers.HAZARD_CONTACT
const BLOCKER_GROUP := &"asteroids"
const MAX_RECASTS := 4


## True when no blocker stands on the segment `from`→`to`. `exclude` (e.g. the caster's own body)
## is never modified.
static func clear(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, exclude: Array[RID] = []) -> bool:
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, BLOCK_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var skipped: Array[RID] = exclude.duplicate()
	for _cast in MAX_RECASTS + 1:
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider: Object = hit.get("collider")
		if _blocks(collider):
			return false
		skipped.append(hit.rid)
	if OS.is_stdout_verbose():
		print("LineOfSight: recast cap reached between %s and %s; counting the line as clear" % [from, to])
	return true


static func _blocks(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is Node and (collider as Node).is_in_group(BLOCKER_GROUP):
		return true
	return collider.has_method(&"blocks_line_of_sight") and collider.call(&"blocks_line_of_sight") == true
