## Integration test for the hit-aware armour query (`ArmorQuery`, `ArmorPlate`, `homing_point`).
##
## INTENT tests (they cover new code). The premise: an armoured hull deflects a player bullet
## without consuming it, but a breakable plate on it must still be able to say "bullets glance
## off, rockets and Sniper Shots break me". That needs a hit-aware query (`deflects_hit`), which
## the hit-blind `is_armored()` cannot express. Proven on a fixture armoured entity
## (tests/helpers/armored_fixture.gd) with REAL projectile scenes and real collision layers.
##
## The space station implements neither new method and takes the unchanged fallback path; its
## suites (`test_space_station.gd`, `test_station_incoming_damage_paths.gd`,
## `test_player_bullet_lifetime.gd`) must pass unedited.
extends GutTest

const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/sniper_bullet.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const ArmoredFixture := preload("res://tests/helpers/armored_fixture.gd")
const ArmoredHomingFixture := preload("res://tests/helpers/armored_homing_fixture.gd")

const ORIGIN := Vector2(400.0, 300.0)

var _container: Node2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)


func _fixture(script: GDScript = ArmoredFixture) -> Node2D:
	var f: Node2D = script.new()
	_container.add_child(f)
	f.global_position = ORIGIN
	return f


func _spawn(scene: PackedScene, pos: Vector2, setup: Callable = Callable()) -> Node2D:
	var node: Node2D = scene.instantiate()
	if setup.is_valid():
		setup.call(node)
	_container.add_child(node)
	node.global_position = pos
	return node


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _is_consumed(node: Variant) -> bool:
	return not is_instance_valid(node) or node.is_queued_for_deletion()


func _hit_box(damage_type: HitBox.DamageType, damage: int = 50, parent: Node = null) -> HitBox:
	var hb := HitBox.new()
	hb.damage_type = damage_type
	hb.damage = damage
	if parent != null:
		parent.add_child(hb)
	else:
		add_child_autofree(hb)
	return hb


## A stand-in for the station: only `is_armored()`.
class IsArmoredOnly extends Node2D:
	func is_armored() -> bool:
		return true


# ---------------------------------------------------------------------------------------------
# ArmorQuery
# ---------------------------------------------------------------------------------------------

func test_query_prefers_deflects_hit_over_is_armored() -> void:
	var f := _fixture()
	var area: Area2D = f.plate.hurt_box
	# The plate says "a rocket is not deflected" while its owner-less is_armored would be absent.
	assert_false(ArmorQuery.deflects(area, _hit_box(HitBox.DamageType.ROCKET)))
	assert_true(ArmorQuery.deflects(area, _hit_box(HitBox.DamageType.LASER)))


func test_query_falls_back_to_is_armored() -> void:
	var armored := IsArmoredOnly.new()
	_container.add_child(armored)
	var hurt := HurtBox.new()
	armored.add_child(hurt)
	assert_true(ArmorQuery.deflects(hurt, _hit_box(HitBox.DamageType.ROCKET)),
			"an is_armored-only target (the station) deflects everything, rockets included")

	var plain := Node2D.new()
	_container.add_child(plain)
	var plain_hurt := HurtBox.new()
	plain.add_child(plain_hurt)
	assert_false(ArmorQuery.deflects(plain_hurt, _hit_box(HitBox.DamageType.LASER)),
			"a target with neither method deflects nothing")


func test_bullet_is_high_impact_only_with_unlimited_pierce() -> void:
	var bullet: Bullet = BULLET_SCENE.instantiate()
	autofree(bullet)
	assert_false(bullet.is_high_impact())
	bullet.unlimited_pierce = true
	assert_true(bullet.is_high_impact())


# ---------------------------------------------------------------------------------------------
# Real projectiles against a plate
# ---------------------------------------------------------------------------------------------

## Counts a signal without GUT's watcher, which cannot read an object that has since freed itself
## (a broken plate frees itself, and GUT's `assert_signal_*` then crashes the run).
func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null) -> void: n[0] += 1)
	return n


func test_a_default_bullet_crossing_a_plate_is_not_consumed() -> void:
	var f := _fixture()
	var stub := HurtBox.new()
	stub.collision_layer = CollisionLayers.ENEMY_HURTBOX
	stub.collision_mask = CollisionLayers.PLAYER_HITBOX
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	stub.add_child(shape)
	_container.add_child(stub)
	stub.global_position = ORIGIN + Vector2(0.0, -160.0)
	watch_signals(stub)
	var deflected := _count(f.plate.deflected)

	var bullet := _spawn(BULLET_SCENE, ORIGIN + Vector2(0.0, 110.0)) as Bullet
	var expired := _count(bullet.expired)
	await _frames(40)

	assert_signal_emitted(stub, "received_damage", "the bullet crossed hull and plate and reached the stub")
	assert_eq(expired[0], 1, "it expired exactly once: on the stub, not on the hull or the plate")
	assert_eq(f.plate.health.current_health, 50, "a bullet never damages a plate")
	assert_eq(deflected[0], 1)
	assert_true(f.plate.is_alive())


func test_a_warhead_rocket_breaks_the_plate_and_is_consumed() -> void:
	var f := _fixture()
	var plate: ArmorPlate = f.plate
	var broke := _count(plate.broken)
	var rocket := _spawn(WARHEAD_SCENE, ORIGIN + Vector2(0.0, -10.0))
	await _frames(3)

	assert_eq(broke[0], 1)
	assert_true(_is_consumed(rocket), "the rocket that breaks a plate is spent on it")
	await get_tree().process_frame
	assert_false(is_instance_valid(plate), "a broken plate frees itself")


func test_a_sniper_shot_damages_the_plate_and_keeps_flying() -> void:
	var f := _fixture()
	var plate: ArmorPlate = f.plate
	var setup := func(b: Bullet) -> void:
		b.unlimited_pierce = true
		b.damage = 40
	var deflected := _count(plate.deflected)
	var broke := _count(plate.broken)
	var first := _spawn(SNIPER_SCENE, ORIGIN + Vector2(0.0, 60.0), setup) as Bullet
	await _frames(20)
	assert_eq(plate.health.current_health, 10, "the shot took its damage (40 of 50)")
	assert_true(plate.is_alive())
	assert_false(_is_consumed(first), "a Sniper Shot passes through at full damage")
	assert_eq(deflected[0], 0)

	var second := _spawn(SNIPER_SCENE, ORIGIN + Vector2(0.0, 60.0), setup) as Bullet
	await _frames(20)
	assert_eq(broke[0], 1, "the second shot breaks it")
	assert_false(_is_consumed(second))


func test_two_rockets_on_one_plate_in_one_frame_only_one_is_consumed() -> void:
	var f := _fixture()
	var deflected := _count(f.plate.deflected)
	var a := _spawn(WARHEAD_SCENE, ORIGIN + Vector2(-3.0, -10.0))
	var b := _spawn(WARHEAD_SCENE, ORIGIN + Vector2(3.0, -10.0))
	await _frames(3)
	assert_eq(deflected[0], 0, "a rocket is never a deflect flash")
	assert_eq(int(_is_consumed(a)) + int(_is_consumed(b)), 1,
			"the first rocket breaks the plate and is consumed; the second finds it broken and flies on")


func test_a_direct_received_damage_emit_does_nothing_to_a_plate() -> void:
	var f := _fixture()
	f.plate.hurt_box.received_damage.emit(9999)
	assert_eq(f.plate.health.current_health, 50)
	assert_true(f.plate.is_alive())


func test_a_beam_style_laser_hit_never_breaks_a_plate() -> void:
	var f := _fixture()
	var hb := _hit_box(HitBox.DamageType.LASER, 9999)
	f.plate._on_hurt_box_area_entered(hb)
	assert_true(f.plate.is_alive())
	assert_eq(f.plate.health.current_health, 50)


# ---------------------------------------------------------------------------------------------
# Callback order independence (the plate classifies and the projectile asks; Godot orders them
# arbitrarily, so the result must not depend on which runs first)
# ---------------------------------------------------------------------------------------------

func test_a_rocket_is_consumed_whichever_callback_runs_first() -> void:
	var f := _fixture()
	var hb := _hit_box(HitBox.DamageType.ROCKET)
	# Plate classifies first, then the rocket asks.
	f.plate._on_hurt_box_area_entered(hb)
	assert_false(f.plate.deflects_hit(hb), "the rocket that broke the plate is consumed")
	assert_false(f.plate.is_alive())

	var f2 := _fixture()
	var hb2 := _hit_box(HitBox.DamageType.ROCKET)
	# The rocket asks first, then the plate classifies.
	assert_false(f2.plate.deflects_hit(hb2))
	f2.plate._on_hurt_box_area_entered(hb2)
	assert_eq(f2.plate.health.current_health, 0, "damage is applied exactly once")
	assert_false(f2.plate.is_alive())


func test_the_second_rocket_of_a_frame_is_not_consumed_in_either_order() -> void:
	for plate_first in [true, false]:
		var f := _fixture()
		var r1 := _hit_box(HitBox.DamageType.ROCKET)
		var r2 := _hit_box(HitBox.DamageType.ROCKET)
		var asked: Array[bool] = []
		if plate_first:
			f.plate._on_hurt_box_area_entered(r1)
			f.plate._on_hurt_box_area_entered(r2)
			asked = [f.plate.deflects_hit(r1), f.plate.deflects_hit(r2)]
		else:
			asked.append(f.plate.deflects_hit(r1))
			asked.append(f.plate.deflects_hit(r2))
			f.plate._on_hurt_box_area_entered(r1)
			f.plate._on_hurt_box_area_entered(r2)
		assert_false(asked[0], "first rocket consumed (plate_first=%s)" % plate_first)
		assert_true(asked[1], "second rocket passes (plate_first=%s)" % plate_first)
		assert_eq(f.plate.health.current_health, 0)


# ---------------------------------------------------------------------------------------------
# Homing
# ---------------------------------------------------------------------------------------------

func test_a_homing_rocket_fired_from_behind_meets_the_plate() -> void:
	var f := _fixture(ArmoredHomingFixture)
	var plate := f.plate as ArmorPlate
	var rocket := _spawn(HOMING_SCENE, ORIGIN + Vector2(0.0, 300.0)) as homing_missile
	rocket.locked_target = f
	await _frames(120)
	assert_false(is_instance_valid(plate) and plate.is_alive(), "the rocket steered at the plate and broke it")
	assert_true(_is_consumed(rocket))


func test_a_homing_rocket_at_a_target_without_homing_point_parks_at_the_centre() -> void:
	var f := _fixture(ArmoredFixture)
	var rocket := _spawn(HOMING_SCENE, ORIGIN + Vector2(0.0, 300.0)) as homing_missile
	rocket.locked_target = f
	await _frames(120)
	assert_true(is_instance_valid(rocket) and not rocket.is_queued_for_deletion())
	assert_lt(rocket.global_position.distance_to(ORIGIN), 12.0,
			"control: without homing_point the rocket flies to the hull centre and hovers there")
	assert_true(f.plate.is_alive())
