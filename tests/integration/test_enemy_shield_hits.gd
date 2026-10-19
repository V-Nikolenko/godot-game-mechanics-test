## Integration test for `EnemyShield` against REAL player projectiles on real collision layers.
##
## INTENT tests: they cover new code (Phase 5 t2, docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md
## §2.3). The premise the unit rows cannot prove: the shield is asked inside the hurtbox's own
## `area_entered`, so a real `Bullet` that overlaps a shielded side is consumed (the target answers
## neither `deflects_hit` nor `is_armored` for the shield) and the hull hears nothing, while the
## same bullet from behind lands as it always has. A direct `received_damage.emit()` (a beam)
## bypasses the shield, exactly as it bypasses an `ArmorPlate`.
##
## On `tests/helpers/fixture_enemy.tscn`. A default bullet deals 50 and the fixture has 10 HP, so
## every case raises the hull to 1000 HP and the shield's capacity to 1000 before they enter the
## tree, and reads HP deltas rather than deaths. The fixture's HurtBox has no shape: a 20 px circle
## is added here. Runs on the 8× clock (step kept at 1/60 game-second), restored in `after_each`.
## Budgeted in §4.3: at most 6 awaited cases, one scene build each.
extends GutTest

const FIXTURE_SCENE: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")

const ORIGIN := Vector2(400.0, 300.0)
const HULL_HP: int = 1000
const SHOT: float = 110.0
const _SPEEDUP: int = 8

var _container: Node2D
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8


func before_each() -> void:
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP
	_container = Node2D.new()
	add_child_autofree(_container)


func after_each() -> void:
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _circle(radius: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	return shape


## The fixture enemy at ORIGIN with a 1000 HP hull and a shaped HurtBox.
func _enemy() -> BaseEnemy:
	var e: BaseEnemy = FIXTURE_SCENE.instantiate()
	var health := e.get_node("Health") as Health
	health.max_health = HULL_HP
	health.current_health = HULL_HP
	e.get_node("HurtBox").add_child(_circle(20.0))
	_container.add_child(e)
	e.global_position = ORIGIN
	return e


## A shield on `host`, attached to `hurt_box`, facing `facing` (toward the shooter).
func _shield(host: Node2D, hurt_box: HurtBox, arc_deg: float, facing: Vector2 = Vector2.DOWN) -> EnemyShield:
	var s := EnemyShield.new()
	s.arc_deg = arc_deg
	s.capacity = HULL_HP
	host.add_child(s)
	assert_true(s.attach(hurt_box), "the shield takes the hurtbox's slot")
	s.face(facing)
	return s


## A real projectile launched at `target` from `SHOT` px away along `from_dir`, nose toward it
## (both player projectiles fly along `Vector2.UP.rotated(rotation)`). Its flight ends the way
## `WeaponBehavior._launch()` ends it: `expired -> queue_free`.
func _fire(scene: PackedScene, target: Vector2, from_dir: Vector2) -> Node2D:
	var p: Node2D = scene.instantiate()
	_container.add_child(p)
	p.global_position = target + from_dir * SHOT
	p.rotation = Vector2.UP.angle_to(-from_dir)
	if p.has_signal("expired"):
		p.expired.connect(p.queue_free)
	return p


func _is_consumed(node: Variant) -> bool:
	return not is_instance_valid(node) or node.is_queued_for_deletion()


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


# ---------------------------------------------------------------------------------------------

func test_a_bullet_from_the_front_is_eaten_and_one_from_behind_hurts_the_hull() -> void:
	var e := _enemy()
	var shield := _shield(e, e.hurt_box, 110.0)
	var absorbed := _count(e.hurt_box.hit_absorbed)

	var front := _fire(BULLET_SCENE, ORIGIN, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(front), "the shield eats the bullet: no deflection, so it is spent")
	assert_eq(e.health.current_health, HULL_HP, "the hull took nothing")
	assert_eq(absorbed[0], 1)
	assert_eq(shield.points(), HULL_HP - 50, "the shield paid the bullet's damage")

	var rear := _fire(BULLET_SCENE, ORIGIN, Vector2.UP)
	await _frames(20)
	assert_true(_is_consumed(rear))
	assert_eq(e.health.current_health, HULL_HP - 50, "from behind it lands on the hull")
	assert_eq(absorbed[0], 1)
	assert_eq(shield.points(), HULL_HP - 50, "a hit outside the arc costs the shield nothing")


func test_player_rockets_from_the_front_detonate_on_the_shield() -> void:
	var e := _enemy()
	var shield := _shield(e, e.hurt_box, 110.0)
	var warhead := _fire(WARHEAD_SCENE, ORIGIN, Vector2.DOWN)
	var homing := _fire(HOMING_SCENE, ORIGIN + Vector2(4.0, 0.0), Vector2.DOWN) as homing_missile
	homing.locked_target = e
	await _frames(30)
	assert_true(_is_consumed(warhead), "the warhead detonated on the shield")
	assert_true(_is_consumed(homing), "so did the homing rocket")
	assert_eq(e.health.current_health, HULL_HP, "neither reached the hull")
	assert_eq(shield.points(), HULL_HP - 150, "the shield paid both: warhead 50 + homing 100")


func test_a_beam_bypasses_the_shield() -> void:
	var e := _enemy()
	var shield := _shield(e, e.hurt_box, 360.0)
	# BeamBehavior, the plasma nova, dash, shield overload and the laser ray all emit directly.
	e.hurt_box.received_damage.emit(30)
	assert_eq(e.health.current_health, HULL_HP - 30, "a direct emitter never passes the absorber")
	assert_eq(shield.points(), HULL_HP)


func test_a_local_module_shield_protects_its_part_only() -> void:
	var e := _enemy()
	# A plain part (never an ArmorPlate, which damages itself in its own area_entered): its own
	# HurtBox -> received_damage -> its own Health, 60 px to the side, clear of the hull's circle.
	var part := Node2D.new()
	var part_health := Health.new()
	part_health.max_health = HULL_HP
	part_health.current_health = HULL_HP
	part.add_child(part_health)
	var part_hurt := HurtBox.new()
	part_hurt.collision_layer = CollisionLayers.ENEMY_HURTBOX
	part_hurt.collision_mask = 96
	part_hurt.add_child(_circle(12.0))
	part.add_child(part_hurt)
	part_hurt.received_damage.connect(part_health.decrease)
	e.add_child(part)
	part.position = Vector2(60.0, 0.0)
	var shield := _shield(part, part_hurt, 110.0)
	var part_at := part.global_position

	var on_part := _fire(BULLET_SCENE, part_at, Vector2.DOWN)
	var on_hull := _fire(BULLET_SCENE, ORIGIN, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(on_part))
	assert_true(_is_consumed(on_hull))
	assert_eq(part_health.current_health, HULL_HP, "the shielded part took nothing")
	assert_eq(shield.points(), HULL_HP - 50)
	assert_eq(e.health.current_health, HULL_HP - 50, "the hull beside it is not shielded")
	assert_false(e.hurt_box.has_absorber())


func test_a_bubble_eats_bullets_from_four_directions() -> void:
	var e := _enemy()
	var shield := _shield(e, e.hurt_box, 360.0)
	var absorbed := _count(e.hurt_box.hit_absorbed)
	var shots: Array[Node2D] = []
	for dir in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		shots.append(_fire(BULLET_SCENE, ORIGIN, dir))
	await _frames(20)
	for i in shots.size():
		assert_true(_is_consumed(shots[i]), "shot %d was eaten" % i)
	assert_eq(absorbed[0], 4)
	assert_eq(e.health.current_health, HULL_HP, "no direction reached the hull")
	assert_eq(shield.points(), HULL_HP - 200)
