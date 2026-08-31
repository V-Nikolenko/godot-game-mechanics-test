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
