## The static registry of live hazards. A hazard node answers duck-typed `hazard_info() -> HazardInfo`,
## calls `Hazards.register(self)` in `_enter_tree()` and `Hazards.unregister(self)` in `_exit_tree()`.
## Hazards are SAMPLED by the body: nothing here writes a ship's velocity, position or rotation, and no
## physics layer is used (bit 12 stays free). Plan §2.1.
class_name Hazards
extends RefCounted

## No slow ever exceeds this, and slows never stack: the strongest one wins.
const MAX_PENALTY := 0.5
const CONTAINER_GROUP: StringName = &"hazard_container"

static var _nodes: Array = []


static func register(node: Node) -> void:
	if node != null and not _nodes.has(node):
		_nodes.append(node)


static func unregister(node: Node) -> void:
	_nodes.erase(node)


## O(1). Callers gate every query on `count() > 0`.
static func count() -> int:
	return _nodes.size()


## Every info with `pos.distance_to(info.position) <= info.radius + reach`. Allocates.
static func around(pos: Vector2, reach: float) -> Array:
	var found: Array = []
	for node in _nodes:
		var info := _info(node)
		if info != null and info.contains(pos, reach):
			found.append(info)
	return found


## Sum of every field's acceleration at [param pos], px/s².
static func accel_at(pos: Vector2) -> Vector2:
	var total := Vector2.ZERO
	for node in _nodes:
		var info := _info(node)
		if info != null:
			total += info.accel_at(pos)
	return total


## The strongest slow at [param pos], capped at `MAX_PENALTY`. Never stacked.
static func penalty_at(pos: Vector2) -> float:
	var strongest := 0.0
	for node in _nodes:
		var info := _info(node)
		if info != null:
			strongest = maxf(strongest, info.penalty_at(pos))
	return minf(strongest, MAX_PENALTY)


## The first node in group `hazard_container`, or null.
static func container(tree: SceneTree) -> Node2D:
	if tree == null:
		return null
	return tree.get_first_node_in_group(CONTAINER_GROUP) as Node2D


## The ship's `HurtBox`: its `hurt_box` property when that is one, else the child named `HurtBox`.
static func hurt_box_of(ship: Node) -> HurtBox:
	if ship == null:
		return null
	var prop = ship.get(&"hurt_box")
	if prop is HurtBox:
		return prop
	return ship.get_node_or_null("HurtBox") as HurtBox


## Direct hazard damage (hull stress, an explosive-wreck blast): emits `damage` on the HurtBox of every
## node in groups `enemies` and `player` whose CENTRE is within [param radius] of [param at]. A direct
## emit, so it bypasses `EnemyShield`, and it adds no body, so it is safe inside a physics callback.
## Returns how many ships were hit.
static func pulse_damage(tree: SceneTree, at: Vector2, radius: float, damage: int) -> int:
	if tree == null:
		return 0
	var hit := 0
	var seen := {}
	for group in [&"enemies", &"player"]:
		for node in tree.get_nodes_in_group(group):
			var ship := node as Node2D
			if ship == null or seen.has(ship) or ship.is_queued_for_deletion():
				continue
			seen[ship] = true
			if ship.global_position.distance_to(at) > radius:
				continue
			var box := hurt_box_of(ship)
			if box == null:
				continue
			box.received_damage.emit(damage)
			hit += 1
	return hit


static func _info(node) -> HazardInfo:
	if not is_instance_valid(node) or not node.has_method(&"hazard_info"):
		return null
	return node.hazard_info() as HazardInfo
