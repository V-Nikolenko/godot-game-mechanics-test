## EnergyHitScan - the static target scan every enemy energy weapon shares (`EnemyBeam`, later `EnergyRing`)
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.2; task t2).
##
## **Who is hit:** every live node in groups `player`, `allies`, `enemies` and `asteroids` whose hurtbox SHAPE meets the weapon, except the
## weapon's owner set (`is_exempt`: the host and every node in its `owner_group`). Enemy ordnance (rockets, mines) is in none of those groups
## and is never hit.
##
## **How:** `Shape2D.collide()` against each enabled `CollisionShape2D` under the target's hurtbox (`Hazards.hurt_box_of`), with the shape's
## global transform, so circles, rectangles and capsules at any scale and rotation are exact, and no physics step is needed (hand-tickable).
## A hurtbox's `monitoring` is not read: a barrel-roll that switches it off does not dodge a beam, as it never dodged `LaserRay`.
##
## **Damage** is a direct emit (`HurtBox.received_damage.emit`), like every beam in the project: it skips `EnemyShield` absorbers and
## `HurtBox.accepted_damage_types`; the target's own handler decides the rest (a plated Ram refuses it, the player's i-frames and shield apply).
class_name EnergyHitScan
extends RefCounted

const VICTIM_GROUPS: Array[StringName] = [&"player", &"allies", &"enemies", &"asteroids"]


## Every live node in the victim groups, once each, skipping any queued for deletion.
static func candidates(tree: SceneTree) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if tree == null:
		return out
	var seen := {}
	for group in VICTIM_GROUPS:
		for node in tree.get_nodes_in_group(group):
			var target := node as Node2D
			if target == null or seen.has(target) or target.is_queued_for_deletion():
				continue
			seen[target] = true
			out.append(target)
	return out


## True when [param target] belongs to the weapon's owner set: it is [param host], or [param owner_group] is set and it is in that group.
static func is_exempt(target: Node, host: Node, owner_group: StringName) -> bool:
	if target == null:
		return true
	if host != null and target == host:
		return true
	return owner_group != &"" and target.is_in_group(owner_group)


## True when [param band] at [param band_xform] (global) overlaps any enabled hurtbox shape of [param target]. False with no hurtbox.
static func hits_band(band: Shape2D, band_xform: Transform2D, target: Node) -> bool:
	for cs in _shapes(target):
		if band.collide(band_xform, cs.shape, cs.global_transform):
			return true
	return false


## The radius about [param target]'s position that encloses every enabled hurtbox shape (the farthest corner of each shape's rect from
## the shape's origin, scaled), so an off-centre shape is never under-estimated. 0 with no hurtbox.
static func bounding_radius(target: Node2D) -> float:
	var r := 0.0
	for cs in _shapes(target):
		var xf := cs.global_transform
		var rect := cs.shape.get_rect()
		var far := 0.0
		for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.end]:
			far = maxf(far, corner.length())
		var scale := maxf(absf(xf.get_scale().x), absf(xf.get_scale().y))
		r = maxf(r, xf.origin.distance_to(target.global_position) + far * scale)
	return r


## Emits [param damage] on [param target]'s hurtbox. False (and nothing emitted) when it has none.
static func deliver(target: Node, damage: int) -> bool:
	var hurt := Hazards.hurt_box_of(target)
	if hurt == null:
		return false
	hurt.received_damage.emit(damage)
	return true


static func _shapes(target: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	if target == null:
		return out
	var hurt := Hazards.hurt_box_of(target)
	if hurt == null:
		return out
	for child in hurt.get_children():
		var cs := child as CollisionShape2D
		if cs != null and not cs.disabled and cs.shape != null:
			out.append(cs)
	return out
