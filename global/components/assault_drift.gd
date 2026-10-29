## AssaultDrift - the shared "static things scroll with the corridor" rule (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7, Phase 8 t6).
##
## A child `Node` of a static structure (the defense turret, and later the heavy emplacement, shield generator, power source and laser fence).
## In Assault (an `EnemyWorld.arena()` provider exists) it moves its parent's `global_position.y` down by `speed · delta` and frees the parent
## once it is below `EnemyWorld.projectile_world_rect().end.y`. In Open Space it does nothing. The Wreck and the Minefield keep their own drift
## code.
##
## It writes the parent's position only. The parents have no `EnemyMover`, so the single-writer gate
## (`tests/integration/test_enemy_mover_single_writer.gd`) is untouched. Nothing here names `ArenaCamera`.
##
## `step(delta)` is the whole rule and is hand-tickable; `_physics_process` calls it.
class_name AssaultDrift
extends Node

## Downward drift in Assault, px/s. A host copies its config's value here in `_ready()`.
@export var speed: float = 60.0


func _physics_process(delta: float) -> void:
	step(delta)


## One drift step: down by `speed · delta` in Assault, then free the parent below the projectile world rect. A no-op in Open Space, outside the
## tree, or once the parent is already queued for deletion.
func step(delta: float) -> void:
	var host := get_parent() as Node2D
	if host == null or not is_inside_tree() or host.is_queued_for_deletion():
		return
	var tree := get_tree()
	if EnemyWorld.arena(tree) == null:
		return
	host.global_position.y += speed * delta
	if EnemyWorld.has_projectile_world_rect(tree) and host.global_position.y > EnemyWorld.projectile_world_rect(tree).end.y:
		host.queue_free()


## The drift velocity `(0, speed)` in Assault, ZERO otherwise - for anything that must lead a carried hazard.
func velocity() -> Vector2:
	if not is_inside_tree() or EnemyWorld.arena(get_tree()) == null:
		return Vector2.ZERO
	return Vector2(0.0, speed)
