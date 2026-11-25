## INTENT tests for `ShieldSector` (`global/boss/shield_sector.gd`), Phase 11 t15 (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5.4;
## the row numbers below are that section's). A generator keeps one 360 degree `EnemyShield` bubble on each protected part until it is
## destroyed.
##
## On `tests/helpers/fixture_modular_host.tscn` (the armoured-root host); the parts under test are built here in code, added under its
## `Modules` node, so a row picks the shape, the lock and the light it needs. Rows 1-5 and 7 are hand-driven (a hit is `area_entered`
## emitted on the part's hurtbox, which is what the physics server would emit); row 6 is real physics at the 8x clock (the
## `test_enemy_module.gd` pair), the step stays 1/60 game-second.
extends GutTest

const HOST_SCENE: PackedScene = preload("res://tests/helpers/fixture_modular_host.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

const ORIGIN := Vector2(400.0, 300.0)
const SHOT: float = 110.0
const BULLET_DAMAGE: int = 50
const PART_HP: int = 100
const _SPEEDUP: int = 8
const PARAMS := {
	"capacity": 100,
	"regen_delay": 2.5,
	"regen_seconds": 1.25,
	"reboot_seconds": 100.0,
	"radius_pad": 8.0,
}

var _root: Node2D
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)


func after_each() -> void:
	_restore_clock()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ---------------------------------------------------------------------------------------------
# Builders and readers
# ---------------------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _host() -> BaseEnemy:
	var host := HOST_SCENE.instantiate() as BaseEnemy
	host.position = ORIGIN
	_root.add_child(host)
	return host


## A part with a `Sprite`, a `HurtBox` of [param shape], a `Health` and a `Light`, added under the host's `Modules` at [param at].
func _part(host: Node, id: StringName, at: Vector2, shape: Shape2D = null, locked: bool = false) -> EnemyModule:
	var m := EnemyModule.new()
	m.name = String(id)
	m.module_id = id
	m.max_health = PART_HP
	m.starts_vulnerable = not locked
	m.position = at
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	m.add_child(sprite)
	var hb := HurtBox.new()
	hb.name = "HurtBox"
	var cs := CollisionShape2D.new()
	if shape == null:
		var circle := CircleShape2D.new()
		circle.radius = 12.0
		shape = circle
	cs.shape = shape
	hb.add_child(cs)
	m.add_child(hb)
	var health := Health.new()
	health.name = "Health"
	m.add_child(health)
	var light := StateLight.new()
	light.name = "Light"
	m.add_child(light)
	host.get_node("Modules").add_child(m)
	return m


func _typed(parts: Array) -> Array[EnemyModule]:
	var out: Array[EnemyModule] = []
	for p in parts:
		out.append(p)
	return out


func _hp(part: EnemyModule) -> int:
	return part.health.current_health


## A hit on [param part]'s hurtbox as the physics server would deliver it.
func _hit(part: EnemyModule, damage: int = 30) -> void:
	var hb := HitBox.new()
	hb.damage = damage
	hb.damage_type = HitBox.DamageType.LASER
	_root.add_child(hb)
	hb.global_position = part.global_position + Vector2(0.0, 40.0)
	part.hurt_box.area_entered.emit(hb)
	hb.queue_free()


func _fire(target: Vector2) -> Node2D:
	var p: Node2D = BULLET_SCENE.instantiate()
	_root.add_child(p)
	p.global_position = target + Vector2.DOWN * SHOT
	p.rotation = Vector2.UP.angle_to(Vector2.UP)
	if p.has_signal("expired"):
		p.expired.connect(p.queue_free)
	return p


# ---------------------------------------------------------------------------------------------
# 1. One bubble per live protected part
# ---------------------------------------------------------------------------------------------

func test_one_bubble_per_live_protected_part_with_the_params() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var round_part := _part(host, &"round", Vector2.ZERO)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30.0, 40.0)
	var square_part := _part(host, &"square", Vector2(80, 0), rect)
	var sector := ShieldSector.new(gen, _typed([round_part, square_part]), PARAMS)

	assert_eq(sector.shields().size(), 2, "one bubble per protected part")
	assert_eq(sector.generator(), gen)
	assert_eq(sector.protected_ids(), [&"round", &"square"])
	assert_false(sector.is_exposed())
	for id in [&"round", &"square"]:
		var s := sector.shield_of(id)
		assert_not_null(s, "%s has a bubble" % id)
		assert_eq(s.arc_deg, 360.0, "a bubble, not an arc")
		assert_false(s.sustain_mode, "no sustain mode")
		assert_eq(s.capacity, 100)
		assert_eq(s.regen_delay, 2.5)
		assert_eq(s.regen_seconds, 1.25)
		assert_eq(s.reboot_seconds, 100.0)
		assert_eq(s.get_parent(), host.get_node("Modules/" + String(id)), "a child of its part")
		assert_true(s.is_up())
	assert_almost_eq(sector.shield_of(&"round").radius, 20.0, 0.001, "circle radius 12 + pad 8")
	assert_almost_eq(sector.shield_of(&"square").radius, 25.0 + 8.0, 0.001, "half-diagonal of 30 x 40 is 25, + pad 8")
	assert_null(sector.shield_of(&"nobody"))


func test_a_part_already_destroyed_gets_no_bubble() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var live := _part(host, &"live", Vector2.ZERO)
	var wreck := _part(host, &"wreck", Vector2(80, 0))
	wreck.destroy()
	var sector := ShieldSector.new(gen, _typed([live, wreck]), PARAMS)
	assert_not_null(sector.shield_of(&"live"))
	assert_null(sector.shield_of(&"wreck"), "a wreck is not shielded")
	assert_eq(sector.shields().size(), 1)
	assert_eq(sector.protected_ids(), [&"live", &"wreck"], "the id list is what was given")


func test_a_destroyed_generator_at_construction_leaves_the_sector_exposed() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var part := _part(host, &"part", Vector2.ZERO)
	gen.destroy()
	var sector := ShieldSector.new(gen, _typed([part]), PARAMS)
	assert_true(sector.is_exposed())
	assert_eq(sector.shields().size(), 0)
	assert_false(part.hurt_box.has_absorber())


# ---------------------------------------------------------------------------------------------
# 2. The generator's death frees its sector, for good
# ---------------------------------------------------------------------------------------------

func test_destroying_the_generator_frees_its_bubbles_in_the_same_call_and_spares_another_sector() -> void:
	var host := _host()
	var gen_a := _part(host, &"gen_a", Vector2(-120, 0))
	var a1 := _part(host, &"a1", Vector2(-60, 0))
	var a2 := _part(host, &"a2", Vector2(0, 0))
	var gen_b := _part(host, &"gen_b", Vector2(60, 0))
	var b1 := _part(host, &"b1", Vector2(120, 0))
	var sector_a := ShieldSector.new(gen_a, _typed([a1, a2]), PARAMS)
	var sector_b := ShieldSector.new(gen_b, _typed([b1]), PARAMS)
	var bubble_a1 := sector_a.shield_of(&"a1")
	var bubble_b1 := sector_b.shield_of(&"b1")

	gen_a.destroy()

	assert_true(sector_a.is_exposed(), "exposed for good")
	assert_null(sector_a.shield_of(&"a1"))
	assert_null(sector_a.shield_of(&"a2"))
	assert_eq(sector_a.shields().size(), 0)
	assert_true(bubble_a1.is_queued_for_deletion(), "freed")
	assert_false(a1.hurt_box.has_absorber(), "the slot is free this instant, not at the end of the frame")
	assert_false(a2.hurt_box.has_absorber())
	assert_false(sector_b.is_exposed(), "the other sector is untouched")
	assert_eq(sector_b.shield_of(&"b1"), bubble_b1)
	assert_false(bubble_b1.is_queued_for_deletion())
	assert_true(b1.hurt_box.has_absorber())

	# A hit later in the same physics frame is not absorbed.
	_hit(a1, 30)
	assert_eq(_hp(a1), PART_HP - 30, "the first hit after the generator died damages the part")


# ---------------------------------------------------------------------------------------------
# 3. A protected part's death frees only its own bubble
# ---------------------------------------------------------------------------------------------

func test_destroying_a_protected_part_frees_only_its_own_bubble() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var p1 := _part(host, &"p1", Vector2.ZERO)
	var p2 := _part(host, &"p2", Vector2(80, 0))
	var sector := ShieldSector.new(gen, _typed([p1, p2]), PARAMS)
	var bubble_p2 := sector.shield_of(&"p2")

	p1.destroy()

	assert_null(sector.shield_of(&"p1"))
	assert_eq(sector.shields().size(), 1)
	assert_eq(sector.shield_of(&"p2"), bubble_p2)
	assert_true(p2.hurt_box.has_absorber(), "the sibling keeps its bubble")
	assert_false(sector.is_exposed(), "the generator lives")


# ---------------------------------------------------------------------------------------------
# 4. A taken absorber slot is never displaced
# ---------------------------------------------------------------------------------------------

func test_a_part_whose_absorber_slot_is_taken_keeps_its_absorber() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var taken := _part(host, &"taken", Vector2.ZERO)
	var free := _part(host, &"free", Vector2(80, 0))
	var own := EnemyShield.new()
	taken.add_child(own)
	assert_true(own.attach(taken.hurt_box))

	var sector := ShieldSector.new(gen, _typed([taken, free]), PARAMS)

	assert_null(sector.shield_of(&"taken"), "no bubble on a part that already has an absorber")
	assert_eq(taken.hurt_box._absorber, own, "the existing absorber stays")
	assert_not_null(sector.shield_of(&"free"), "the other part is still shielded")
	assert_eq(sector.shields().size(), 1)
	gen.destroy()
	assert_eq(taken.hurt_box._absorber, own, "and the generator's death does not touch it either")


# ---------------------------------------------------------------------------------------------
# 5. A locked part's bubble absorbs nothing
# ---------------------------------------------------------------------------------------------

func test_a_locked_parts_bubble_absorbs_nothing_and_an_unlocked_part_absorbs() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var locked := _part(host, &"locked", Vector2.ZERO, null, true)
	var open := _part(host, &"open", Vector2(80, 0))
	var sector := ShieldSector.new(gen, _typed([locked, open]), PARAMS)
	var deflected := [0]
	locked.deflected.connect(func(_m: EnemyModule) -> void: deflected[0] += 1)

	_hit(locked, 30)
	assert_eq(sector.shield_of(&"locked").points(), 100, "a locked part's bubble takes nothing")
	assert_eq(deflected[0], 1, "the part itself deflects the hit")
	assert_eq(_hp(locked), PART_HP)

	_hit(open, 30)
	assert_eq(sector.shield_of(&"open").points(), 70, "an unlocked part's bubble absorbs")
	assert_eq(_hp(open), PART_HP, "so the part takes nothing")

	locked.set_vulnerable(true)
	_hit(locked, 30)
	assert_eq(sector.shield_of(&"locked").points(), 70, "unlocked, the bubble absorbs too")


# ---------------------------------------------------------------------------------------------
# 6. Real physics: a bullet stream
# ---------------------------------------------------------------------------------------------

func test_real_bullets_are_absorbed_until_the_capacity_is_spent_then_damage_the_part() -> void:
	_scale_clock()
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var target := _part(host, &"target", Vector2.ZERO)
	var sector := ShieldSector.new(gen, _typed([target]), PARAMS)
	var bubble := sector.shield_of(&"target")

	var first := _fire(target.global_position)
	await _frames(20)
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(), "the bubble consumes the bullet")
	assert_eq(_hp(target), PART_HP, "absorbed")
	assert_eq(bubble.points(), 100 - BULLET_DAMAGE)

	_fire(target.global_position)
	await _frames(20)
	assert_eq(_hp(target), PART_HP, "the breaking hit is absorbed whole")
	assert_false(bubble.is_up(), "capacity spent")

	_fire(target.global_position)
	await _frames(20)
	assert_eq(_hp(target), PART_HP - BULLET_DAMAGE, "the first bullet past the bubble damages the part")


func test_real_bullet_with_the_generator_destroyed_first_damages_the_part() -> void:
	_scale_clock()
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var target := _part(host, &"target", Vector2.ZERO)
	var sector := ShieldSector.new(gen, _typed([target]), PARAMS)
	gen.destroy()
	assert_true(sector.is_exposed())

	_fire(target.global_position)
	await _frames(20)
	assert_eq(_hp(target), PART_HP - BULLET_DAMAGE, "no bubble: the first bullet damages")


# ---------------------------------------------------------------------------------------------
# 7. The generator's light
# ---------------------------------------------------------------------------------------------

func test_the_generators_light_is_shielded_while_it_lives_and_off_as_a_wreck() -> void:
	var host := _host()
	var gen := _part(host, &"gen", Vector2(-80, 0))
	var part := _part(host, &"part", Vector2.ZERO)
	var light := gen.get_node("Light") as StateLight
	assert_eq(light.get_state(), StateLight.State.OFF, "before the sector exists")
	var sector := ShieldSector.new(gen, _typed([part]), PARAMS)
	assert_not_null(sector)
	assert_eq(light.get_state(), StateLight.State.SHIELDED)
	assert_almost_eq(light.modulate.a, StateLight.MAX_ALPHA, 0.001, "visible")

	gen.destroy()
	assert_eq(light.get_state(), StateLight.State.OFF, "dark as a wreck")


func test_state_light_values_are_append_only() -> void:
	assert_eq(StateLight.State.OFF, 0)
	assert_eq(StateLight.State.ARMED, 1)
	assert_eq(StateLight.State.CHARGING, 2)
	assert_eq(StateLight.State.COMMIT, 3)
	assert_eq(StateLight.State.VENTING, 4)
	assert_eq(StateLight.State.SHIELDED, 5, "appended after VENTING")
