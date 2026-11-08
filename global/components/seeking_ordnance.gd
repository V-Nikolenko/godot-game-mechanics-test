## SeekingOrdnance — the retarget contract's group and its one query (Phase 9 §2.5,
## docs/plans/cmug23onr001pm52w9swwophy/3-plan.md).
##
## A player seeking projectile that a claimer (the Hacker Frigate's dart) may take over joins `GROUP` and answers,
## duck-typed like `is_armored()`: `can_be_retargeted() -> bool`, `retarget(target: Node2D, seconds: float,
## source: Node) -> bool`, `is_retargeted() -> bool`, `jam_guidance(source: Node) -> void`, and declares
## `signal retargeted(source: Node)` and `signal retarget_ended()`. Only `homing_missile` implements it today;
## a `WarheadMissile` is never eligible.
class_name SeekingOrdnance
extends RefCounted

const GROUP := &"player_seeking_ordnance"


## Every member of `GROUP` within [param reach] of [param at] (centre distance, inclusive) whose
## `can_be_retargeted()` is true, nearest first, ties by instance id (deterministic). A null tree gives none.
static func eligible(tree: SceneTree, at: Vector2, reach: float) -> Array[Node2D]:
	var found: Array[Node2D] = []
	if tree == null:
		return found
	for node in tree.get_nodes_in_group(GROUP):
		var n := node as Node2D
		if n == null or not is_instance_valid(n) or not n.is_inside_tree() or n.is_queued_for_deletion():
			continue
		if not n.has_method(&"can_be_retargeted") or not n.call(&"can_be_retargeted"):
			continue
		if n.global_position.distance_to(at) <= reach:
			found.append(n)
	found.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var da := a.global_position.distance_squared_to(at)
		var db := b.global_position.distance_squared_to(at)
		if da != db:
			return da < db
		return a.get_instance_id() < b.get_instance_id())
	return found
