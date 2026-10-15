class_name HurtBox
extends Area2D

signal received_damage(damage: int)
## Emitted instead of `received_damage` when this hurtbox's absorber took the hit (an `EnemyShield`).
signal hit_absorbed(hit_box: HitBox)

## When empty, all damage types are accepted. Otherwise only listed types pass.
@export var accepted_damage_types: Array[HitBox.DamageType] = []

## One absorber slot, duck-typed: `absorbs_hit(hit_box: HitBox) -> bool`. It is asked here, once per
## hit, because `received_damage` carries no HitBox and Godot orders `area_entered` callbacks
## undefined — this is the only place that sees the hit. With no absorber nothing changes.
## A direct `received_damage.emit()` (beam, nova, dash) never passes through it.
var _absorber: Object = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)

## Takes the slot. False while another live absorber holds it (a freed holder's slot is free),
## and for an object that has no `absorbs_hit`, so a misuse fails here rather than on every hit.
func set_absorber(obj: Object) -> bool:
	if obj == null or not obj.has_method(&"absorbs_hit"):
		return false
	if has_absorber() and _absorber != obj:
		return false
	_absorber = obj
	return true

## Releases the slot; a no-op unless `obj` holds it.
func clear_absorber(obj: Object) -> void:
	if _absorber == obj:
		_absorber = null

func has_absorber() -> bool:
	return _absorber != null and is_instance_valid(_absorber)

func _on_area_entered(area: Area2D) -> void:
	var hb := area as HitBox
	if not hb:
		return
	if not accepted_damage_types.is_empty() and hb.damage_type not in accepted_damage_types:
		return
	if has_absorber() and _absorber.absorbs_hit(hb):
		hit_absorbed.emit(hb)
		return
	received_damage.emit(hb.damage)
