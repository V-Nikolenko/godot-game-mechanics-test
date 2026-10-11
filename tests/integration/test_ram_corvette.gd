## Intent tests for the Ram Corvette's armour (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.6.1,
## §2.6.3 and the t16 row of §4; task plan docs/plans/cmuyk2qq8008xoa2xxoq1frgn/3-plan.md).
##
## INTENT, not characterization: the legacy Ram (a narrowed hurtbox mask, "the first missile arms it")
## is gone. Three `ArmorPlate`s sit on a full-size hull. Bullets glance off the plates and the hull and
## fly on; each rocket breaks exactly the plate it meets; a Sniper Shot chips a plate and flies on; only
## once all three are gone does the hull (120 HP) take damage from anything.
##
## Every real-projectile case is parameterised over `tests/helpers/enemy_ai_harness.gd`'s Open Space and
## Assault worlds, with the Corvette's own physics tick switched off (it stays put, its brain never
## ticks), so the projectiles - not the AI - are under test. Signal counts use connected counters: a
## broken plate frees itself, and GUT's `watch_signals` / `assert_signal_*` then crash on it.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const Fixture := preload("res://tests/helpers/contact_fixture.gd")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const RAM_CONFIG: RamCorvetteConfig = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/sniper_bullet.tscn")
const SNIPER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/sniper_shot.tres")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")

const MODES := ["open_space", "assault"]
## Where the Corvette sits: on screen in both worlds.
const RAM_POS := Vector2(640.0, 300.0)
## How far from it a test projectile starts.
const STANDOFF := 160.0
## The outer rockets of `RocketState._launch_warhead()` sit this far either side of the axis
## (`warhead_missile_shooting_state.gd`: offsets (+-16, 26), (0, 36)).
const WARHEAD_OUTER_OFFSET_X := 16.0
const PLATE_NAMES: Array[StringName] = [&"PlateFront", &"PlateLeft", &"PlateRight"]

var _root: Node2D


## Builds the world for `mode` and a stationary Corvette in it.
func _world(mode: String) -> RamCorvette:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	_root = harness.root
	harness.player.global_position = Vector2(80.0, 80.0)  # off every test line
	var ram := RAM_SCENE.instantiate() as RamCorvette
	ram.global_position = RAM_POS
	_root.add_child(ram)
	ram.set_physics_process(false)
	return ram


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _is_consumed(node: Variant) -> bool:
	return not is_instance_valid(node) or node.is_queued_for_deletion()


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null) -> void: n[0] += 1)
	return n


func _plate(ram: RamCorvette, plate_name: StringName) -> ArmorPlate:
	return ram.get_node_or_null(NodePath("Plates/%s" % plate_name)) as ArmorPlate


func _alive(ram: RamCorvette, plate_name: StringName) -> bool:
	var p := _plate(ram, plate_name)
	return p != null and is_instance_valid(p) and p.is_alive()


## A projectile at `pos` (world) flying along `dir`. `setup` runs before it enters the tree.
func _shoot(scene: PackedScene, pos: Vector2, dir: Vector2, setup: Callable = Callable()) -> Node2D:
	var node: Node2D = scene.instantiate()
	node.rotation = Vector2.UP.angle_to(dir)
	if setup.is_valid():
		setup.call(node)
	_root.add_child(node)
	node.global_position = pos
	return node


## Breaks `plate_name` with a real warhead fired along `dir` from STANDOFF out, and waits for it.
func _rocket_plate(ram: RamCorvette, plate_name: StringName) -> void:
	var p := _plate(ram, plate_name)
	var dir := (p.global_position - ram.global_position).normalized()
	_shoot(WARHEAD_SCENE, p.global_position + dir * STANDOFF, -dir)
	for i in 60:
		await get_tree().physics_frame
		if not _alive(ram, plate_name):
			break


## Breaks every live plate directly through its classifier (a ROCKET HitBox), then lets the deferred
## exposure land.
func _strip(ram: RamCorvette) -> void:
	for plate_name in PLATE_NAMES:
		if _alive(ram, plate_name):
			var hb := HitBox.new()
			hb.damage_type = HitBox.DamageType.ROCKET
			hb.damage = 9999
			add_child_autofree(hb)
			_plate(ram, plate_name)._on_hurt_box_area_entered(hb)
	await _frames(2)


# ── 1. Scene and config ─────────────────────────────────────────────────────────────────────────

func test_scene_and_config() -> void:
	var ram := _world("open_space")
	var body := ram.get_node("CollisionShape2D") as CollisionShape2D
	var circle := body.shape as CircleShape2D
	assert_not_null(circle, "the body is a circle")
	assert_eq(circle.radius, 34.0, "the body circle (plan 2.6.1: r 34)")
	var front := ram.get_node("Plates/PlateFront") as Node2D
	var front_shape := (front.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	assert_between((front.position.y + front_shape.radius) * 2.0, 80.0, 88.0, "an 80-88 px hull, plates included")
	assert_eq((ram.hurt_box.get_node("CollisionShape2D") as CollisionShape2D).shape, body.shape,
			"the root HurtBox shares the body's shape")
	assert_eq((ram.contact_hit_box.get_node("CollisionShape2D") as CollisionShape2D).shape, body.shape,
			"the contact box shares the body's shape")
	assert_eq(ram.hurt_box.collision_mask, 1121, "the default DefenseProfile mask: bullets are NOT masked out")
	var profiles := ram.get_children().filter(func(c: Node) -> bool: return c is DefenseProfile)
	assert_eq(profiles.size(), 1, "only BaseEnemy's default DefenseProfile: the scene authors none")
	for child in ram.get_children():
		assert_false(child is ArmorPlate, "a plate is never a direct root child (hurtbox-geometry gate)")

	for plate_name in PLATE_NAMES:
		var p := _plate(ram, plate_name)
		assert_not_null(p, "%s exists under Plates" % plate_name)
		assert_eq(p.health.current_health, RAM_CONFIG.plate_health)
	assert_eq(RAM_CONFIG.plate_health, 50)
	assert_eq(ram.health.current_health, 120)
	assert_eq(ram.health.max_health, RAM_CONFIG.max_health)
	assert_eq(ram.contact_hit_box.damage, 50)
	assert_eq(ram.contact_profile.mode, ContactProfile.Mode.ARMOR)
	assert_true(ram.contact_profile.is_armed(), "ARMOR is armed at spawn")
	assert_eq(ram.contact_profile.shove_speed, 260.0)
	assert_true(ram.is_in_group("enemies"))
	assert_false(ram.is_in_group("ram_ships"), "the legacy group (and the bullet rule keyed on it) is gone")
	assert_true(ram.is_armored())


## Review N10: a frontal warhead volley's outer rockets reach (outer offset + the rocket's capsule radius)
## sideways, so each side plate's shape must stay clear of that band or "a frontal volley strips exactly
## the front plate" turns flaky. The two side plates must also sit on opposite sides (left = +x).
func test_side_plates_clear_the_frontal_volleys_lateral_reach() -> void:
	var ram := _world("open_space")
	var probe := WARHEAD_SCENE.instantiate()
	var rocket_shape := (probe.get_node("HitBox/CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	var reach := WARHEAD_OUTER_OFFSET_X + rocket_shape.radius
	probe.free()
	assert_almost_eq(reach, 23.0, 0.01, "sanity: 16 + 7, the figure review N10 states")
	assert_gt(_plate(ram, &"PlateLeft").position.x, 0.0, "the ship's left plate is on local +x")
	assert_lt(_plate(ram, &"PlateRight").position.x, 0.0, "the ship's right plate is on local -x")
	for plate_name in [&"PlateLeft", &"PlateRight"]:
		var p := _plate(ram, plate_name)
		var cs := p.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
		var xf: Transform2D = p.transform * (p.get_node("HurtBox") as Node2D).transform * cs.transform
		var r := cs.shape.get_rect()
		var min_abs_x := INF
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			min_abs_x = minf(min_abs_x, absf((xf * corner).x))
		assert_gt(min_abs_x, reach, "%s's inner edge clears the outer warheads" % plate_name)


# ── 2. Bullets glance off ───────────────────────────────────────────────────────────────────────

func test_bullets_glance_off_hull_and_plates(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var deflected := _count(ram.armor_deflected)
	var bullets: Array[Bullet] = []
	var expired: Array = []
	# One across the hull centre from the side, and one at each plate from outside it.
	bullets.append(_shoot(BULLET_SCENE, RAM_POS + Vector2(STANDOFF, 0.0), Vector2.LEFT) as Bullet)
	for plate_name in PLATE_NAMES:
		var p := _plate(ram, plate_name)
		var dir := (p.global_position - RAM_POS).normalized()
		bullets.append(_shoot(BULLET_SCENE, p.global_position + dir * STANDOFF, -dir) as Bullet)
	for b in bullets:
		expired.append(_count(b.expired))
	await _frames(30)

	assert_eq(ram.health.current_health, 120, "%s: the hull took nothing" % mode)
	for plate_name in PLATE_NAMES:
		assert_eq(_plate(ram, plate_name).health.current_health, 50, "%s: %s took nothing" % [mode, plate_name])
	assert_gt(deflected[0], 0, "%s: the hull reported the deflections" % mode)
	for i in bullets.size():
		assert_false(_is_consumed(bullets[i]), "%s: bullet %d flew on" % [mode, i])
		assert_eq(expired[i][0], 0, "%s: bullet %d never expired" % [mode, i])


# ── 3. Each rocket breaks exactly the plate it hits ─────────────────────────────────────────────

func _rocket_row(mode: String, from: Vector2, dir: Vector2, expect: StringName) -> void:
	var ram := _world(mode)
	var names: Array[StringName] = []
	ram.plate_broken.connect(func(n: StringName) -> void: names.append(n))
	var rocket := _shoot(WARHEAD_SCENE, RAM_POS + from, dir)
	await _frames(40)
	assert_eq(names, [expect] as Array[StringName], "%s: only %s broke" % [mode, expect])
	for plate_name in PLATE_NAMES:
		if plate_name != expect:
			assert_eq(_plate(ram, plate_name).health.current_health, 50, "%s: %s untouched" % [mode, plate_name])
	assert_true(_is_consumed(rocket), "%s: the rocket was spent on the plate" % mode)
	assert_eq(ram.health.current_health, 120, "%s: the hull took nothing" % mode)
	assert_true(ram.is_armored())


func test_a_rocket_from_the_front_breaks_only_the_front_plate(mode: String = use_parameters(MODES)) -> void:
	await _rocket_row(mode, Vector2(0.0, STANDOFF), Vector2.UP, &"PlateFront")


## "Left" is the ship's left: the nose points to local +y, so its left is local +x. Both sides, so a
## mirrored (or same-side) plate cannot pass.
func test_a_rocket_from_the_side_breaks_only_that_side_plate(mode: String = use_parameters(MODES)) -> void:
	await _rocket_row(mode, Vector2(STANDOFF, _plate_y(&"PlateLeft")), Vector2.LEFT, &"PlateLeft")


func test_a_rocket_from_the_other_side_breaks_only_that_side_plate(mode: String = use_parameters(MODES)) -> void:
	await _rocket_row(mode, Vector2(-STANDOFF, _plate_y(&"PlateRight")), Vector2.RIGHT, &"PlateRight")


## From the rear there is no plate: the rocket crosses the deflecting hull and breaks the front plate
## from the inside.
func test_a_rocket_from_the_rear_crosses_the_hull_and_breaks_the_front_plate(mode: String = use_parameters(MODES)) -> void:
	await _rocket_row(mode, Vector2(0.0, -STANDOFF), Vector2.DOWN, &"PlateFront")


func _plate_y(plate_name: StringName) -> float:
	var probe := RAM_SCENE.instantiate()
	var y: float = (probe.get_node(NodePath("Plates/%s" % plate_name)) as Node2D).position.y
	probe.free()
	return y


# ── 4. Plate-by-plate vulnerability ─────────────────────────────────────────────────────────────

func _bullet_at_hull(ram: RamCorvette) -> Array:
	# From the rear (no plate there), flying down the axis.
	var b := _shoot(BULLET_SCENE, ram.global_position + Vector2(0.0, -STANDOFF), Vector2.DOWN) as Bullet
	var expired := _count(b.expired)
	await _frames(20)
	return [b, expired[0]]


func test_plates_fall_one_by_one_and_only_then_the_hull_is_hurt(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var armor_broken := _count(ram.armor_broken)
	for i in 2:
		await _rocket_plate(ram, PLATE_NAMES[i])
		assert_false(_alive(ram, PLATE_NAMES[i]), "%s: %s broke" % [mode, PLATE_NAMES[i]])
		var shot: Array = await _bullet_at_hull(ram)
		assert_eq(ram.health.current_health, 120, "%s: with %d plate(s) left the hull takes 0" % [mode, 2 - i])
		assert_false(_is_consumed(shot[0]), "%s: and the bullet flies on" % mode)
		assert_eq(shot[1], 0, "%s: never expired" % mode)
		assert_true(ram.is_armored())
	assert_eq(armor_broken[0], 0)

	await _rocket_plate(ram, PLATE_NAMES[2])
	await _frames(1)
	assert_eq(ram.live_plate_count(), 0)
	assert_false(ram.is_armored(), "%s: exposed once the third plate is gone" % mode)
	assert_eq(armor_broken[0], 1, "%s: armor_broken fired once" % mode)
	var probe := BULLET_SCENE.instantiate() as Bullet
	var bullet_damage: int = probe.damage
	probe.free()
	var shot: Array = await _bullet_at_hull(ram)
	assert_eq(ram.health.current_health, 120 - bullet_damage, "%s: the bullet's full damage lands" % mode)
	assert_eq(shot[1], 1, "%s: and the bullet is spent (expired once)" % mode)
	assert_eq(armor_broken[0], 1)


# ── 5. Deferred exposure (boundary) ─────────────────────────────────────────────────────────────

## Within the step the last plate breaks, the hull is still armoured; the step after, it is not. This
## is what stops a rocket that breaks the last plate while overlapping the hull from also landing on it.
func test_exposure_lands_one_step_after_the_last_plate_breaks() -> void:
	var ram := _world("open_space")
	var deflected := _count(ram.armor_deflected)
	for plate_name in [&"PlateFront", &"PlateLeft"]:
		var hb := HitBox.new()
		hb.damage_type = HitBox.DamageType.ROCKET
		hb.damage = 50
		add_child_autofree(hb)
		_plate(ram, plate_name)._on_hurt_box_area_entered(hb)
	await _frames(2)
	assert_true(ram.is_armored())

	var last := HitBox.new()
	last.damage_type = HitBox.DamageType.ROCKET
	last.damage = 50
	add_child_autofree(last)
	_plate(ram, &"PlateRight")._on_hurt_box_area_entered(last)
	assert_eq(ram.live_plate_count(), 0, "the last plate is gone")
	ram.hurt_box.received_damage.emit(100)  # the same rocket, reported by the hull in the same step
	assert_eq(ram.health.current_health, 120, "still a deflection inside that step")
	assert_eq(deflected[0], 1)

	await _frames(1)
	assert_false(ram.is_armored())
	ram.hurt_box.received_damage.emit(30)
	assert_eq(ram.health.current_health, 90, "the next hit lands")


# ── 6 / 7. Real rocket volleys ──────────────────────────────────────────────────────────────────

## A real `RocketState` (the player's rocket weapon) with the actor STANDOFF*2 below the Corvette, facing
## it. Its MovementController is never in the tree: `_launch_*` is called directly.
func _rocket_state(ram: RamCorvette) -> RocketState:
	var actor := CharacterBody2D.new()
	_root.add_child(actor)
	actor.global_position = ram.global_position + Vector2(0.0, STANDOFF * 2.0)
	var controller := MovementController.new()
	autofree(controller)
	var state := RocketState.new()
	state.actor = actor
	state.movement_controller = controller
	var timer := Timer.new()
	timer.name = "CooldownTimer"
	state.add_child(timer)
	_root.add_child(state)
	return state


func _rockets(state: RocketState) -> Array[Node]:
	return state.get_children().filter(func(c: Node) -> bool: return not (c is Timer))


func test_one_homing_volley_strips_all_three_plates(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var state := _rocket_state(ram)
	state._launch_homing()
	var rockets := _rockets(state)
	assert_eq(rockets.size(), 3, "sanity: a volley is three rockets")
	for r in rockets:
		assert_eq((r as homing_missile).locked_target, ram, "%s: every rocket locks the lone Corvette" % mode)
	for i in 240:
		await get_tree().physics_frame
		if ram.live_plate_count() == 0:
			break
	await _frames(2)
	assert_eq(ram.live_plate_count(), 0, "%s: one homing volley strips all three plates" % mode)
	var spent := 0
	for r in rockets:
		spent += int(_is_consumed(r))
	assert_eq(spent, 3, "%s: each rocket was spent on a plate" % mode)
	assert_eq(ram.health.current_health, 120, "%s: none of them reached the hull" % mode)
	assert_false(ram.is_armored(), "%s: the Corvette is exposed" % mode)


func test_one_frontal_warhead_volley_strips_exactly_the_front_plate(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var state := _rocket_state(ram)
	state._launch_warhead()
	var rockets := _rockets(state)
	assert_eq(rockets.size(), 3, "sanity: a volley is three rockets")
	await _frames(45)
	assert_false(_alive(ram, &"PlateFront"), "%s: the front plate broke" % mode)
	for plate_name in [&"PlateLeft", &"PlateRight"]:
		assert_true(_alive(ram, plate_name), "%s: %s survives a frontal volley" % [mode, plate_name])
		assert_eq(_plate(ram, plate_name).health.current_health, 50)
	# 45 frames in, the two rockets that missed are past the Corvette but still on screen.
	var spent := 0
	for r in rockets:
		spent += int(_is_consumed(r))
	assert_eq(spent, 1, "%s: exactly one rocket was spent, on the front plate" % mode)
	assert_eq(ram.health.current_health, 120)
	assert_true(ram.is_armored())


# ── 8. The Sniper Shot ──────────────────────────────────────────────────────────────────────────

func _sniper_shot(from: Vector2, dir: Vector2) -> Bullet:
	var setup := func(b: Bullet) -> void:
		b.unlimited_pierce = true
		b.damage = SNIPER_MODE.damage
	return _shoot(SNIPER_SCENE, from, dir, setup) as Bullet


func test_a_sniper_shot_chips_a_plate_and_passes_the_armoured_hull(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	assert_eq(SNIPER_MODE.damage, 40, "sanity: the shipped Sniper Shot damage")
	var shot := _sniper_shot(RAM_POS + Vector2(0.0, STANDOFF), Vector2.UP)
	await _frames(25)
	assert_eq(_plate(ram, &"PlateFront").health.current_health, 10, "%s: the front plate lost 40" % mode)
	assert_eq(ram.health.current_health, 120, "%s: the armoured hull lost nothing" % mode)
	assert_false(_is_consumed(shot), "%s: the shot is not stopped (the ram_ships rule is gone)" % mode)
	assert_lt(shot.global_position.y, RAM_POS.y - 34.0, "%s: and is past the Corvette" % mode)


func test_a_sniper_shot_damages_an_exposed_hull_and_flies_on(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	await _strip(ram)
	assert_false(ram.is_armored())
	var shot := _sniper_shot(RAM_POS + Vector2(0.0, STANDOFF), Vector2.UP)
	await _frames(25)
	assert_eq(ram.health.current_health, 80, "%s: the exposed hull lost 40" % mode)
	assert_false(_is_consumed(shot), "%s: the shot flies on" % mode)


# ── 9. The beam ─────────────────────────────────────────────────────────────────────────────────

## Drives a real `BeamBehavior` from `_physics_process` (test_station_incoming_damage_paths.gd's driver).
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []

	func _physics_process(delta: float) -> void:
		if behavior != null:
			behavior.tick(self, mode, muzzles, delta)


func _beam(ram: RamCorvette) -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	_root.add_child(d)
	d.global_position = ram.global_position + Vector2(0.0, 300.0)
	return d


func _beam_endpoint(d: BeamDriver) -> Vector2:
	for child in d.get_children():
		var beam := child as PiercingBeam
		if beam != null:
			var line := beam.get_node("Line2D") as Line2D
			if line.points.size() >= 2:
				return line.points[1]
	return Vector2.INF


func test_the_beam_is_blocked_by_armour_and_burns_an_exposed_hull(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var d := _beam(ram)
	await _frames(40)
	var end := _beam_endpoint(d)
	assert_ne(end, Vector2.INF, "sanity: the beam drew")
	assert_gt(end.y, RAM_POS.y, "%s: an armoured Corvette stops the beam at its hull" % mode)
	assert_eq(ram.health.current_health, 120, "%s: and takes nothing" % mode)

	await _strip(ram)
	await _frames(40)
	end = _beam_endpoint(d)
	assert_lt(end.y, RAM_POS.y - 300.0, "%s: an exposed Corvette no longer blocks it" % mode)
	assert_lt(ram.health.current_health, 120, "%s: and burns" % mode)


# ── 10. Engine boost and EMP ────────────────────────────────────────────────────────────────────

func test_engine_boost_is_deflected_while_armoured_and_lands_once_exposed() -> void:
	var ram := _world("open_space")
	var deflected := _count(ram.armor_deflected)
	var player := Node2D.new()
	_root.add_child(player)
	player.global_position = ram.global_position + Vector2(10.0, 0.0)
	var boost := EngineBoostModule.new()
	assert_false(boost._is_immune(ram), "the Corvette is not on the boost's class list any more")

	boost._damage_nearby_enemies(player)
	assert_eq(ram.health.current_health, 120, "armoured: the boost deals 0")
	assert_eq(deflected[0], 1, "and the hull reports the deflection")

	await _strip(ram)
	var fresh := EngineBoostModule.new()
	fresh._damage_nearby_enemies(player)
	assert_eq(ram.health.current_health, 120 - fresh._DAMAGE, "exposed: the boost lands")


func test_emp_still_skips_the_corvette() -> void:
	var ram := _world("open_space")
	assert_true(EMPBlastModule.new()._is_immune(ram), "EMP immunity is kept")


# ── 11. Contact ─────────────────────────────────────────────────────────────────────────────────

## A real player HurtBox/Health pair (contact_fixture.gd's values: layer 128, mask 1281) on a root that
## records every `apply_knockback` impulse, so the ARMOR shove is observed end to end - through the
## ContactHitBox's own `area_entered`, which needs its mask to include the player hurtbox's layer.
class KnockbackPlayer extends Node2D:
	var impulses: Array[Vector2] = []
	var health: Health

	func apply_knockback(impulse: Vector2) -> void:
		impulses.append(impulse)


func _knockback_player(pos: Vector2) -> KnockbackPlayer:
	var p := KnockbackPlayer.new()
	p.health = Health.new()
	p.health.max_health = Fixture.PLAYER_MAX_HEALTH
	p.health.current_health = Fixture.PLAYER_MAX_HEALTH
	p.add_child(p.health)
	var hurt_box := HurtBox.new()
	hurt_box.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurt_box.collision_mask = 1281
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Fixture.PLAYER_RADIUS
	shape.shape = circle
	hurt_box.add_child(shape)
	p.add_child(hurt_box)
	hurt_box.received_damage.connect(p.health.decrease)
	_root.add_child(p)
	p.global_position = pos
	return p


func test_armoured_contact_hurts_and_shoves_the_player_and_never_the_corvette(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var touches := _count(ram.contact_profile.contact_made)
	var offset := Vector2(0.0, 30.0)
	var player := _knockback_player(ram.global_position + offset)
	await _frames(3)
	assert_eq(player.health.current_health, Fixture.PLAYER_MAX_HEALTH - 50, "%s: armoured contact deals 50" % mode)
	assert_eq(touches[0], 1, "%s: the ARMOR profile saw the touch (contact_made)" % mode)
	assert_eq(player.impulses.size(), 1, "%s: exactly one shove" % mode)
	if player.impulses.size() == 1:
		assert_almost_eq(player.impulses[0].length(), RAM_CONFIG.armor_shove_speed, 0.01, "%s: at armor_shove_speed" % mode)
		assert_gt(player.impulses[0].dot(offset), 0.0, "%s: pointing away from the hull" % mode)
	assert_eq(ram.health.current_health, 120, "%s: the contact never hurts its owner" % mode)
	assert_false(ram.is_queued_for_deletion())


func test_exposed_contact_hurts_more_and_no_longer_shoves(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	await _strip(ram)
	assert_eq(ram.contact_hit_box.damage, 60, "%s: exposed contact deals 60" % mode)
	var player := _knockback_player(ram.global_position + Vector2(0.0, -30.0))
	await _frames(3)
	assert_eq(player.health.current_health, Fixture.PLAYER_MAX_HEALTH - 60, "%s: and lands for 60" % mode)
	assert_eq(player.impulses.size(), 0, "%s: the armour is what shoved; exposed, nothing does" % mode)
	assert_eq(ram.health.current_health, 120)


# ── 12. homing_point ────────────────────────────────────────────────────────────────────────────

func test_homing_point_is_the_nearest_live_plate() -> void:
	var ram := _world("open_space")
	var below := RAM_POS + Vector2(0.0, 400.0)
	assert_eq(ram.homing_point(below), _plate(ram, &"PlateFront").global_position)
	var left_low := RAM_POS + Vector2(100.0, 300.0)
	assert_eq(ram.homing_point(left_low), _plate(ram, &"PlateFront").global_position,
			"sanity: the front plate is still nearer from below-left")

	var hb := HitBox.new()
	hb.damage_type = HitBox.DamageType.ROCKET
	hb.damage = 50
	add_child_autofree(hb)
	var left_pos := _plate(ram, &"PlateLeft").global_position
	_plate(ram, &"PlateFront")._on_hurt_box_area_entered(hb)
	assert_eq(ram.homing_point(left_low), left_pos, "with the front plate gone: the nearer side plate")

	await _strip(ram)
	assert_eq(ram.homing_point(below), ram.global_position, "with none left: the hull centre")


# ── 13. Rails ───────────────────────────────────────────────────────────────────────────────────

func test_on_a_rail_the_armor_contact_stays_armed_and_the_brain_is_idle() -> void:
	var ram := _world("assault")
	ram.suspend_ai()
	for i in 10:
		ram._physics_process(1.0 / 60.0)
	assert_true(ram.contact_profile.is_armed())
	assert_eq(ram.velocity, Vector2.ZERO, "a suspended brain never moves it")
