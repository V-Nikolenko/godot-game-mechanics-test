class_name HitBox
extends Area2D

enum DamageType { LASER, ROCKET, CONTACT }

@export var damage: int = 1
@export var damage_type: DamageType = DamageType.LASER


## Builds a HitBox whose geometry mirrors `source` exactly: the same `Shape2D` resource AND the
## node transform that sizes and places it.
##
## Copying only `shape` silently drops the scale — a `Shape2D` is a resource and carries the
## radius, not the `CollisionShape2D.scale` that multiplies it — which is how every code-built
## contact hitbox in the game ended up smaller than the hull it belongs to (the gunship's ram box
## was 18 px against a 41.5 px hull). Use this rather than hand-rolling the four lines.
##
## The `Shape2D` is shared, not duplicated: the hitbox and the body describe the same hull and
## nothing mutates it at runtime.
static func matching_shape(
	source: CollisionShape2D, layer: int, mask: int, dmg: int,
	dmg_type: DamageType = DamageType.CONTACT
) -> HitBox:
	var hb := HitBox.new()
	hb.collision_layer = layer
	hb.collision_mask = mask
	hb.damage = dmg
	hb.damage_type = dmg_type
	var shape_node := CollisionShape2D.new()
	shape_node.shape = source.shape
	shape_node.transform = source.transform
	hb.add_child(shape_node)
	return hb
