## Characterization tests for the HitBox / HurtBox damage-contact pair.
extends GutTest


func _make_hitbox(damage: int, type: HitBox.DamageType) -> HitBox:
	var hb := HitBox.new()
	hb.damage = damage
	hb.damage_type = type
	var cs := CollisionShape2D.new()
	cs.shape = RectangleShape2D.new()
	hb.add_child(cs)
	return hb


func _make_hurtbox(accepted: Array[HitBox.DamageType]) -> HurtBox:
	var hb := HurtBox.new()
	hb.accepted_damage_types = accepted
	var cs := CollisionShape2D.new()
	cs.shape = RectangleShape2D.new()
	hb.add_child(cs)
	return hb


func test_hitbox_defaults() -> void:
	var hb := HitBox.new()
	assert_eq(hb.damage, 1)
	assert_eq(hb.damage_type, HitBox.DamageType.LASER)
	hb.free()


func test_damage_type_enum_is_stable() -> void:
	## Enum ordinals are serialised into .tscn/.tres files; reordering them would
	## silently repurpose every authored hitbox.
	assert_eq(HitBox.DamageType.LASER, 0)
	assert_eq(HitBox.DamageType.ROCKET, 1)
	assert_eq(HitBox.DamageType.CONTACT, 2)


func test_an_empty_filter_accepts_every_damage_type() -> void:
	var hurt := _make_hurtbox([] as Array[HitBox.DamageType])
	add_child_autofree(hurt)
	var seen: Array[int] = []
	hurt.received_damage.connect(func(d: int) -> void: seen.append(d))

	for type: HitBox.DamageType in [HitBox.DamageType.LASER, HitBox.DamageType.ROCKET, HitBox.DamageType.CONTACT]:
		var hit := _make_hitbox(3, type)
		autofree(hit)
		hurt._on_area_entered(hit)
	assert_eq(seen, [3, 3, 3] as Array[int])


func test_a_populated_filter_rejects_other_damage_types() -> void:
	var accepted: Array[HitBox.DamageType] = [HitBox.DamageType.ROCKET]
	var hurt := _make_hurtbox(accepted)
	add_child_autofree(hurt)
	var seen: Array[int] = []
	hurt.received_damage.connect(func(d: int) -> void: seen.append(d))

	var laser := _make_hitbox(9, HitBox.DamageType.LASER)
	autofree(laser)
	hurt._on_area_entered(laser)
	assert_eq(seen, [] as Array[int], "a laser is filtered out")

	var rocket := _make_hitbox(9, HitBox.DamageType.ROCKET)
	autofree(rocket)
	hurt._on_area_entered(rocket)
	assert_eq(seen, [9] as Array[int], "a rocket passes the filter")


func test_a_plain_area_is_ignored() -> void:
	var hurt := _make_hurtbox([] as Array[HitBox.DamageType])
	add_child_autofree(hurt)
	var seen: Array[int] = []
	hurt.received_damage.connect(func(d: int) -> void: seen.append(d))

	var area := Area2D.new()
	autofree(area)
	hurt._on_area_entered(area)
	assert_eq(seen, [] as Array[int], "an Area2D that is not a HitBox deals no damage")


func test_overlapping_areas_report_damage_through_the_physics_server() -> void:
	## End-to-end through real collision, not just the handler: this is what
	## proves the default collision layers/masks actually let the pair meet.
	var root := Node2D.new()
	add_child_autofree(root)

	var hurt := _make_hurtbox([] as Array[HitBox.DamageType])
	root.add_child(hurt)
	var seen: Array[int] = []
	hurt.received_damage.connect(func(d: int) -> void: seen.append(d))

	var hit := _make_hitbox(12, HitBox.DamageType.CONTACT)
	root.add_child(hit)

	await wait_physics_frames(4)
	assert_eq(seen, [12] as Array[int], "overlapping boxes deal the hitbox's damage once")


# ---------------------------------------------------------------------------------------------
# The absorb hook (Phase 5 t2, docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.3).
# INTENT rows: they cover new code. One slot; the absorber is duck-typed `absorbs_hit(hb) -> bool`.
# ---------------------------------------------------------------------------------------------

## A duck-typed absorber that answers a fixed value and counts how often it was asked.
class FakeAbsorber extends RefCounted:
	var answer: bool = true
	var asked: int = 0

	func absorbs_hit(_hit_box: HitBox) -> bool:
		asked += 1
		return answer


## The same as an Object that can be freed (a RefCounted cannot be).
class NodeAbsorber extends Node:
	func absorbs_hit(_hit_box: HitBox) -> bool:
		return true


func _absorber_rig(answer: bool) -> Dictionary:
	var hurt := _make_hurtbox([] as Array[HitBox.DamageType])
	add_child_autofree(hurt)
	var rig := {"hurt": hurt, "damage": [] as Array[int], "absorbed": [] as Array[HitBox],
			"absorber": FakeAbsorber.new()}
	rig.absorber.answer = answer
	hurt.received_damage.connect(func(d: int) -> void: rig.damage.append(d))
	hurt.hit_absorbed.connect(func(hb: HitBox) -> void: rig.absorbed.append(hb))
	return rig


func test_without_an_absorber_damage_is_reported_as_before() -> void:
	var rig := _absorber_rig(true)
	var hit := _make_hitbox(7, HitBox.DamageType.LASER)
	autofree(hit)
	assert_false(rig.hurt.has_absorber())
	rig.hurt._on_area_entered(hit)
	assert_eq(rig.damage, [7] as Array[int])
	assert_eq(rig.absorbed.size(), 0)


func test_an_absorber_answering_true_swallows_the_hit() -> void:
	var rig := _absorber_rig(true)
	assert_true(rig.hurt.set_absorber(rig.absorber))
	assert_true(rig.hurt.has_absorber())
	var hit := _make_hitbox(7, HitBox.DamageType.LASER)
	autofree(hit)
	rig.hurt._on_area_entered(hit)
	assert_eq(rig.damage, [] as Array[int], "an absorbed hit never reaches received_damage")
	assert_eq(rig.absorbed.size(), 1)
	assert_same(rig.absorbed[0], hit, "hit_absorbed carries the HitBox")


func test_an_absorber_answering_false_lets_the_hit_land() -> void:
	var rig := _absorber_rig(false)
	rig.hurt.set_absorber(rig.absorber)
	var hit := _make_hitbox(7, HitBox.DamageType.LASER)
	autofree(hit)
	rig.hurt._on_area_entered(hit)
	assert_eq(rig.damage, [7] as Array[int])
	assert_eq(rig.absorbed.size(), 0)
	assert_eq(rig.absorber.asked, 1)


func test_a_freed_absorber_is_ignored_and_its_slot_can_be_retaken() -> void:
	var rig := _absorber_rig(true)
	var node_absorber := NodeAbsorber.new()
	assert_true(rig.hurt.set_absorber(node_absorber))
	node_absorber.free()
	assert_false(rig.hurt.has_absorber(), "a freed holder does not count")
	var hit := _make_hitbox(7, HitBox.DamageType.LASER)
	autofree(hit)
	rig.hurt._on_area_entered(hit)
	assert_eq(rig.damage, [7] as Array[int], "a freed absorber is never asked")
	assert_true(rig.hurt.set_absorber(rig.absorber), "a freed holder's slot is free")


func test_the_slot_holds_one_absorber() -> void:
	var rig := _absorber_rig(true)
	var other := FakeAbsorber.new()
	assert_true(rig.hurt.set_absorber(rig.absorber))
	assert_false(rig.hurt.set_absorber(other), "a second live absorber is refused")
	assert_true(rig.hurt.set_absorber(rig.absorber), "the holder setting itself again is fine")

	rig.hurt.clear_absorber(other)
	assert_true(rig.hurt.has_absorber(), "clear_absorber by a non-holder is a no-op")
	rig.hurt.clear_absorber(rig.absorber)
	assert_false(rig.hurt.has_absorber())
	assert_true(rig.hurt.set_absorber(other))


func test_an_object_without_absorbs_hit_is_refused() -> void:
	var rig := _absorber_rig(true)
	var not_an_absorber := RefCounted.new()
	assert_false(rig.hurt.set_absorber(not_an_absorber), "no absorbs_hit, no slot")
	assert_false(rig.hurt.set_absorber(null))
	assert_false(rig.hurt.has_absorber())


func test_the_damage_type_filter_runs_before_the_absorber() -> void:
	var accepted: Array[HitBox.DamageType] = [HitBox.DamageType.ROCKET]
	var hurt := _make_hurtbox(accepted)
	add_child_autofree(hurt)
	var absorber := FakeAbsorber.new()
	hurt.set_absorber(absorber)
	var laser := _make_hitbox(9, HitBox.DamageType.LASER)
	autofree(laser)
	hurt._on_area_entered(laser)
	assert_eq(absorber.asked, 0, "a filtered-out hit never reaches the absorber")
