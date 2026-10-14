## Intent tests for the Ram Corvette's armour and charge (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.6.1-
## §2.6.3 and the t16 / t17 rows of §4; task plans docs/plans/cmuyk2qq8008xoa2xxoq1frgn/3-plan.md (armour) and
## docs/plans/cmuyk2qqb0091oa2xy7yn9sxa/3-plan.md (the charge, from "t17" down)).
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
	(ram.get_node("Brain") as RamCorvetteBrain).start_engaged = true  # pre-t19: predates the hub idle
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
	(ram.get_node("Brain") as RamCorvetteBrain).enter_phase(RamCorvetteBrain.Phase.CHARGE)  # exposed, it hurts only in CHARGE (t17)
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


# ── t17: the charge (task plan docs/plans/cmuyk2qqb0091oa2xy7yn9sxa/3-plan.md; epic §2.6.2, §4 t17) ──
#
# The Corvette is hand-ticked here (`set_physics_process(false)`, then `_physics_process(DT)` and
# `position = before + velocity * DT`), the same technique as test_sniper.gd: deterministic, no `Timer`. The
# player stub moves by its own `velocity` every step. "dual" cases run in both harnesses; the Assault budget is
# lifted (`engage_seconds`) unless the case is about the budget.

const DT := 1.0 / 60.0
const Phase := RamCorvetteBrain.Phase


func _harness(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	_root = harness.root
	return harness


## A hand-ticked Corvette at `pos` with its budget lifted, the player stub stationary at `player_pos`, facing
## up. `tweak` runs on the Corvette's private config copy before it enters the tree.
func _live_ram(harness, pos: Vector2, player_pos: Vector2, tweak: Callable = Callable()) -> RamCorvette:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	harness.player.rotation = 0.0
	var ram := RAM_SCENE.instantiate() as RamCorvette
	(ram.get_node("Brain") as RamCorvetteBrain).start_engaged = true  # pre-t19: predates the hub idle
	ram.config.engage_seconds = 1000.0
	(ram.get_node("Brain") as RamCorvetteBrain).rng_seed = 1717
	if tweak.is_valid():
		tweak.call(ram)
	ram.global_position = pos
	_root.add_child(ram)
	ram.set_physics_process(false)
	return ram


## Frees a harness mid-test, so the next one's player is the only one `TargetInfo.player()` can find.
func _drop(harness) -> void:
	harness.root.queue_free()
	await get_tree().process_frame


func _brain(ram: RamCorvette) -> RamCorvetteBrain:
	return ram.get_node("Brain") as RamCorvetteBrain


func _gone(ram: RamCorvette) -> bool:
	return not is_instance_valid(ram) or ram.is_queued_for_deletion()


## One step: the stub moves, then the Corvette's own tick, then its velocity is integrated.
func _step(ram: RamCorvette, player: CharacterBody2D) -> void:
	player.global_position += player.velocity * DT
	if _gone(ram):
		return
	var before := ram.global_position
	ram._physics_process(DT)
	ram.global_position = before + ram.velocity * DT


## Steps until the brain is in `p` (true) or `limit` seconds pass (false).
func _run_to(ram: RamCorvette, player: CharacterBody2D, p: int, limit: float) -> bool:
	var brain := _brain(ram)
	var t := 0.0
	while t < limit:
		if brain.phase == p:
			return true
		_step(ram, player)
		t += DT
	return brain.phase == p


## A rocket-typed HitBox straight into `plate_name`'s classifier: breaks it at once (the plate's own path).
func _break_plate(ram: RamCorvette, plate_name: StringName) -> void:
	var hb := HitBox.new()
	hb.damage_type = HitBox.DamageType.ROCKET
	hb.damage = 9999
	add_child_autofree(hb)
	_plate(ram, plate_name)._on_hurt_box_area_entered(hb)


## The player's `predicted_position` the brain uses, from the Corvette at `from` (the brain's own formula,
## with the shipped numbers - the test's independent copy).
func _expected_aim(from: Vector2, player: CharacterBody2D, speed: float) -> Vector2:
	var lead := clampf(from.distance_to(player.global_position) / speed, RAM_CONFIG.lead_min, RAM_CONFIG.lead_max)
	return player.global_position + player.velocity * lead


func _deg(a: Vector2, b: Vector2) -> float:
	return absf(rad_to_deg(a.angle_to(b)))


func test_the_charge_config_is_the_epic_plans() -> void:
	assert_eq(RAM_CONFIG.cruise_speed, 280.0)
	assert_eq(RAM_CONFIG.exposed_cruise_speed, 340.0)
	assert_eq(RAM_CONFIG.acceleration, 500.0)
	assert_eq(RAM_CONFIG.charge_speed, 620.0)
	assert_eq(RAM_CONFIG.exposed_charge_speed, 700.0)
	assert_eq(RAM_CONFIG.engage_range, 420.0)
	assert_eq(RAM_CONFIG.assault_side_offset, 240.0)
	assert_eq(RAM_CONFIG.line_up_cap, 0.5)
	assert_eq(RAM_CONFIG.lead_min, 0.15)
	assert_eq(RAM_CONFIG.lead_max, 0.6)
	assert_eq(RAM_CONFIG.wind_up_seconds, 0.65)
	assert_eq(RAM_CONFIG.windup_track_fraction, 0.6)
	assert_eq(RAM_CONFIG.overshoot, 220.0)
	assert_eq(RAM_CONFIG.charge_max_time, 1.45)
	assert_eq(RAM_CONFIG.wide_turn_rate, 1.4)
	assert_almost_eq(RAM_CONFIG.wind_up_seconds + RAM_CONFIG.charge_max_time, 2.1, 0.0001,
			"the Assault deferral bound t21/t22 rely on")
	assert_lte(RAM_CONFIG.engage_range + RAM_CONFIG.lead_max * 420.0 + RAM_CONFIG.overshoot,
			RAM_CONFIG.charge_speed * RAM_CONFIG.charge_max_time,
			"the designed worst case (420 range + a 0.6 s lead on a 420 px/s player + overshoot) fits the cap")
	assert_lte((maxf(RAM_CONFIG.charge_speed, RAM_CONFIG.exposed_charge_speed) - 30.0) / RAM_CONFIG.braking,
			RAM_CONFIG.line_up_cap, "the hard brake takes even a full-speed charge down to a crawl inside line_up_cap")


# ── t17 1. The charge follows the frozen predicted point ─────────────────────────────────────────

func test_the_charge_follows_the_frozen_predicted_point(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(400.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	h.player.velocity = Vector2(150.0, 0.0)
	brain.enter_phase(Phase.LINE_UP)
	var expected := Vector2.INF
	var t := 0.0
	while brain.phase != Phase.CHARGE and t < 3.0:
		var before := ram.global_position
		_step(ram, h.player)
		t += DT
		if brain.aim_frozen and expected == Vector2.INF:
			expected = _expected_aim(before, h.player, RAM_CONFIG.charge_speed)
			assert_gt(_deg(h.player.global_position - before, expected - before), 5.0,
					"sanity: the predicted point is well off where the player is now")
			h.player.velocity = Vector2(-300.0, 0.0)  # reverse after the freeze
	assert_eq(brain.phase, Phase.CHARGE, "%s: it charged" % mode)
	assert_ne(expected, Vector2.INF, "%s: the aim froze first" % mode)
	_step(ram, h.player)
	assert_lt(_deg(ram.velocity, expected - brain.charge_origin), 5.0,
			"%s: the charge points at the predicted point captured at the freeze" % mode)
	var heading := ram.velocity
	var ticks := 0
	while brain.phase == Phase.CHARGE and ticks < 200:
		assert_lt(_deg(ram.velocity, heading), 0.5, "%s: the line is never re-aimed" % mode)
		_step(ram, h.player)
		ticks += 1


# ── t17 2. WIND_UP: 0.65 s, a crawl, the glow to 1 ───────────────────────────────────────────────

func test_the_wind_up_crawls_and_glows_for_its_full_length(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(300.0, 100.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	var light := ram.get_node("StateLight") as StateLight
	assert_true(_run_to(ram, h.player, Phase.WIND_UP, 6.0), "%s: it reached WIND_UP from a real approach" % mode)
	var ticks := 0
	var max_speed := ram.velocity.length()
	var last_glow := -1.0
	var rising := true
	while brain.phase == Phase.WIND_UP and ticks < 200:
		assert_eq(light.get_state(), StateLight.State.CHARGING, "%s: CHARGING through the wind-up" % mode)
		if brain.glow < last_glow:
			rising = false
		last_glow = brain.glow
		_step(ram, h.player)
		ticks += 1
		if brain.phase == Phase.WIND_UP:
			max_speed = maxf(max_speed, ram.velocity.length())
	assert_almost_eq(ticks * DT, RAM_CONFIG.wind_up_seconds, DT + 0.0001, "%s: 0.65 s +- a tick" % mode)
	assert_lte(max_speed, 30.0, "%s: at most a crawl" % mode)
	assert_true(rising, "%s: the glow only rises" % mode)
	assert_gt(last_glow, 0.9, "%s: nearly full at the last wind-up tick" % mode)
	assert_eq(brain.phase, Phase.CHARGE)
	assert_eq(brain.glow, 1.0, "%s: full glow in CHARGE" % mode)
	assert_eq(light.get_state(), StateLight.State.COMMIT, "%s: COMMIT in CHARGE" % mode)
	for plate_name in PLATE_NAMES:
		assert_eq(_plate(ram, plate_name).sprite.modulate, ArmorPlate._GLOW_COLOR, "%s: %s glows" % [mode, plate_name])


## Review R1-N2: the fastest way into LINE_UP is a capped exposed charge (700 px/s) whose WIDE_TURN ends on its first
## tick, the player still dead ahead. The wind-up after it is still a crawl.
func test_a_line_up_straight_out_of_a_full_speed_charge_still_winds_up_at_a_crawl(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(-40.0, 360.0), Vector2(1360.0, 360.0))
	var brain := _brain(ram)
	await _strip(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 3.0))
	assert_true(_run_to(ram, h.player, Phase.LINE_UP, 3.0), "%s: straight back into LINE_UP" % mode)
	assert_gt(ram.velocity.length(), 600.0, "%s: sanity: at charge speed as LINE_UP starts" % mode)
	assert_gt(brain.glow, 0.9, "%s: sanity: the last charge's glow is still up" % mode)
	# Review R2-N4: from here the glow fades, then the wind-up ramps it from wherever it is - it never snaps down.
	var biggest_drop := 0.0
	var t := 0.0
	while brain.phase == Phase.LINE_UP and t < 1.0:
		var g := brain.glow
		_step(ram, h.player)
		t += DT
		biggest_drop = maxf(biggest_drop, g - brain.glow)
	assert_eq(brain.phase, Phase.WIND_UP)
	assert_lte(biggest_drop, DT / RAM_CONFIG.glow_fade_seconds + 0.0001, "%s: the glow fades, never snaps to 0" % mode)
	var max_speed := ram.velocity.length()
	var ticks := 0
	while brain.phase == Phase.WIND_UP and ticks < 120:
		_step(ram, h.player)
		ticks += 1
		if brain.phase == Phase.WIND_UP:
			max_speed = maxf(max_speed, ram.velocity.length())
	assert_lte(max_speed, 30.0, "%s: <= 30 px/s through the wind-up" % mode)


# ── t17 3. Overshoot; 4. the boost cap ───────────────────────────────────────────────────────────

func test_the_charge_overshoots_the_point_by_at_least_200_px(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(640.0, 100.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 3.0))
	var end := ram.global_position
	var t := 0.0
	while brain.phase == Phase.CHARGE and t < 3.0:
		_step(ram, h.player)
		t += DT
		if brain.phase == Phase.CHARGE:
			end = ram.global_position
	assert_eq(brain.phase, Phase.WIDE_TURN, "%s: CHARGE ends in WIDE_TURN" % mode)
	var along := (brain.charge_point - brain.charge_origin).dot(brain.charge_dir)
	assert_lte(along + RAM_CONFIG.overshoot, RAM_CONFIG.charge_speed * RAM_CONFIG.charge_max_time,
			"%s: inside the envelope, so the cap never cut this charge" % mode)
	assert_gte((end - brain.charge_point).dot(brain.charge_dir), 200.0, "%s: >= 200 px past the point" % mode)


func test_a_far_aim_point_is_cut_at_charge_max_time(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(-40.0, 360.0), Vector2(1360.0, 360.0))
	var brain := _brain(ram)
	var mover := ram.get_node("EnemyMover") as EnemyMover
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 3.0))
	assert_almost_eq(brain.charge_duration, RAM_CONFIG.charge_max_time, 0.0001,
			"%s: 1400 px + overshoot would need 2.6 s; the boost is cut" % mode)
	var boosting := 0
	var t := 0.0
	while brain.phase == Phase.CHARGE and t < 4.0:
		if mover.is_boosting():
			boosting += 1
		_step(ram, h.player)
		t += DT
	assert_lte(boosting * DT, RAM_CONFIG.charge_max_time + DT + 0.0001, "%s: never longer than charge_max_time" % mode)


# ── t17 5. The LINE_UP cap ───────────────────────────────────────────────────────────────────────

func test_line_up_never_outlasts_its_cap(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var centre := Vector2(640.0, 360.0)
	var radius := 300.0
	# The stub orbits the stationary Corvette at 4 rad/s, faster than its 2.2 rad/s nose, starting under the nose (it
	# rests pointing down) and running ahead of it: the aim (led ahead of the stub) stays out of the 8 deg window, so
	# only the cap can end the line-up.
	var omega := 4.0
	var angle := PI / 2.0
	var ram := _live_ram(h, centre, centre + Vector2.RIGHT.rotated(angle) * radius)
	h.player.velocity = Vector2.RIGHT.rotated(angle + PI / 2.0) * radius * omega
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	var ticks := 0
	while brain.phase == Phase.LINE_UP and ticks < 120:
		angle += omega * DT
		h.player.global_position = centre + Vector2.RIGHT.rotated(angle) * radius
		h.player.velocity = Vector2.RIGHT.rotated(angle + PI / 2.0) * radius * omega
		var before := ram.global_position
		ram._physics_process(DT)
		ram.global_position = before + ram.velocity * DT
		ticks += 1
	assert_eq(brain.phase, Phase.WIND_UP, "%s: LINE_UP hands over to WIND_UP" % mode)
	assert_lte(ticks * DT, RAM_CONFIG.line_up_cap + DT + 0.0001, "%s: within line_up_cap + a tick" % mode)
	assert_gte(ticks * DT, RAM_CONFIG.line_up_cap - DT, "%s: sanity: it was the cap, not the nose, that ended it" % mode)


# ── t17 6. A miss and the wide turn ──────────────────────────────────────────────────────────────

func test_a_missed_charge_survives_and_turns_wide(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	# High in the corridor, so the charge, the slow-down and the turn all stay inside the visible rect, where the
	# Assault corridor adds nothing to the velocity (review R2-N1).
	var ram := _live_ram(h, Vector2(640.0, -200.0), Vector2(640.0, 260.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	var t := 0.0
	while not brain.aim_frozen and t < 2.0:
		_step(ram, h.player)
		t += DT
	h.player.global_position += Vector2(260.0, 0.0)  # sidestep after the freeze
	assert_true(_run_to(ram, h.player, Phase.WIDE_TURN, 3.0), "%s: the miss ends in WIDE_TURN" % mode)
	assert_false(_gone(ram), "%s: a miss never kills it" % mode)
	assert_eq(ram.health.current_health, 120)
	var prev := brain.turn_dir
	var max_step := 0.0
	# The flown arc: from the first tick at cruise, the velocity heading turns no further than the commanded heading
	# did, plus the lag it started with (the velocity follows `turn_dir` through the mover's acceleration).
	var flown := 0.0
	var commanded := 0.0
	var lag := -1.0
	t = 0.0
	while brain.phase == Phase.WIDE_TURN and t < 6.0:
		var v_before := ram.velocity
		var turn_before := brain.turn_dir
		_step(ram, h.player)
		t += DT
		if brain.phase == Phase.WIDE_TURN:
			max_step = maxf(max_step, absf(prev.angle_to(brain.turn_dir)))
			prev = brain.turn_dir
			if lag < 0.0 and absf(v_before.length() - RAM_CONFIG.cruise_speed) < 0.02 * RAM_CONFIG.cruise_speed:
				lag = absf(v_before.angle_to(turn_before))
			if lag >= 0.0:
				flown += absf(v_before.angle_to(ram.velocity))
				commanded += absf(turn_before.angle_to(brain.turn_dir))
	assert_gt(max_step, 0.0, "sanity: it turned")
	assert_lte(max_step, RAM_CONFIG.wide_turn_rate * DT + 0.0001, "%s: at most wide_turn_rate per tick" % mode)
	assert_gte(lag, 0.0, "sanity: it settled at cruise during the turn")
	assert_lte(flown, commanded + lag + 0.02, "%s: the flown arc turns no further than commanded (+ its initial lag)" % mode)
	assert_true(brain.phase == Phase.LINE_UP or brain.phase == Phase.APPROACH, "%s: then goes again" % mode)
	assert_true(_run_to(ram, h.player, Phase.LINE_UP, 6.0), "%s: and lines up again" % mode)


# ── t17 7. Contact by phase ──────────────────────────────────────────────────────────────────────

func test_contact_is_armed_in_every_phase_while_armoured_and_only_in_charge_once_exposed(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var brain := _brain(ram)
	var phases := [Phase.APPROACH, Phase.LINE_UP, Phase.WIND_UP, Phase.CHARGE, Phase.WIDE_TURN, Phase.STAGGER]
	for p in phases:
		brain.enter_phase(p)
		assert_true(ram.contact_profile.is_armed(), "%s armoured: armed in %s" % [mode, Phase.keys()[p]])
	brain.enter_phase(Phase.APPROACH)
	await _strip(ram)
	assert_false(ram.contact_profile.is_armed(), "%s exposed: disarmed outside CHARGE" % mode)
	phases = [Phase.LINE_UP, Phase.WIND_UP, Phase.CHARGE, Phase.WIDE_TURN, Phase.CHARGE, Phase.STAGGER, Phase.CHARGE, Phase.APPROACH]
	for p in phases:
		brain.enter_phase(p)
		assert_eq(ram.contact_profile.is_armed(), p == Phase.CHARGE, "%s exposed: armed only in CHARGE (%s)" % [mode, Phase.keys()[p]])


## Review R1-N1 / R2-N5: the hard brake is on only while it stops to aim; everywhere else the mover's own
## acceleration governs, so the post-charge slow-down and the wide turn stay wide.
func test_the_hard_brake_is_on_only_while_it_stops_to_aim() -> void:
	var ram := _world("open_space")
	var brain := _brain(ram)
	var mover := ram.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.braking, 0.0, "at spawn (APPROACH): the mover's acceleration")
	for p in [Phase.LINE_UP, Phase.WIND_UP, Phase.CHARGE, Phase.WIDE_TURN, Phase.STAGGER, Phase.APPROACH, Phase.DISENGAGE]:
		brain.enter_phase(p)
		var stopping: bool = p == Phase.LINE_UP or p == Phase.WIND_UP or p == Phase.STAGGER
		assert_eq(mover.braking, RAM_CONFIG.braking if stopping else 0.0, "braking in %s" % Phase.keys()[p])


func test_an_exposed_touch_outside_the_charge_does_nothing(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	await _strip(ram)
	_brain(ram).enter_phase(Phase.WIDE_TURN)
	var player := _knockback_player(ram.global_position + Vector2(0.0, -30.0))
	await _frames(3)
	assert_eq(player.health.current_health, Fixture.PLAYER_MAX_HEALTH, "%s: no contact damage outside CHARGE" % mode)
	assert_eq(player.impulses.size(), 0)


func test_exposure_mid_charge_keeps_the_contact_armed_until_the_charge_ends(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	var brain := _brain(ram)
	brain.enter_phase(Phase.CHARGE)
	await _strip(ram)
	assert_true(brain.exposed, "sanity: exposed")
	assert_eq(brain.phase, Phase.CHARGE, "%s: a plate broken in CHARGE changes nothing" % mode)
	assert_true(ram.contact_profile.is_armed(), "%s: still armed for the rest of the charge" % mode)
	brain.enter_phase(Phase.WIDE_TURN)
	assert_false(ram.contact_profile.is_armed(), "%s: disarmed once it ends" % mode)


## Review R1-B1: a rail suspends the brain, and the rail fallback is the ARMOR profile armed for life - stripping
## the plates must not disarm it through the (never-ticking) brain.
func test_on_a_rail_a_stripped_corvette_keeps_its_contact(mode: String = use_parameters(MODES)) -> void:
	var ram := _world(mode)
	ram.suspend_ai()
	var changes := _count(_brain(ram).phase_changed)
	await _strip(ram)
	assert_false(ram.is_armored(), "sanity: exposed")
	assert_true(ram.contact_profile.is_armed(), "%s: still armed on its rail" % mode)
	var player := _knockback_player(ram.global_position + Vector2(0.0, -30.0))
	await _frames(3)
	assert_eq(player.health.current_health, Fixture.PLAYER_MAX_HEALTH - 60, "%s: and lands the exposed 60" % mode)
	assert_eq(player.impulses.size(), 0, "%s: without the armour's shove" % mode)
	assert_eq(changes[0], 0, "%s: the suspended brain changed no phase" % mode)


# ── t17 8. Stagger ───────────────────────────────────────────────────────────────────────────────

func test_a_plate_broken_in_wind_up_staggers_and_cancels_the_charge(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.WIND_UP, 2.0))
	_break_plate(ram, &"PlateLeft")
	assert_eq(brain.phase, Phase.STAGGER, "%s: the wind-up is cancelled" % mode)
	assert_eq(brain.glow, 0.0, "%s: the glow drops" % mode)
	var changes := _count(brain.phase_changed)
	var ticks := 0
	var charged := false
	while brain.phase == Phase.STAGGER and ticks < 120:
		_step(ram, h.player)
		ticks += 1
		if ticks == 6:
			_break_plate(ram, &"PlateRight")
			assert_eq(changes[0], 0, "%s: a plate broken mid-stagger restarts nothing" % mode)
		charged = charged or brain.phase == Phase.CHARGE
	assert_false(charged, "%s: no charge out of the stagger" % mode)
	assert_almost_eq(ticks * DT, RAM_CONFIG.stagger_seconds, DT + 0.0001, "%s: a 0.4 s stagger" % mode)
	assert_eq(brain.phase, Phase.LINE_UP, "%s: then it lines up again" % mode)


func test_a_plate_broken_in_line_up_staggers_too(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	_step(ram, h.player)
	_break_plate(ram, &"PlateFront")
	assert_eq(brain.phase, Phase.STAGGER, "%s" % mode)


func test_a_plate_broken_mid_charge_does_not_stop_it(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(640.0, 100.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 3.0))
	_step(ram, h.player)
	_break_plate(ram, &"PlateRight")
	assert_eq(brain.phase, Phase.CHARGE, "%s: the committed charge carries on" % mode)
	_step(ram, h.player)
	assert_eq(brain.phase, Phase.CHARGE)
	assert_almost_eq(ram.velocity.length(), RAM_CONFIG.charge_speed, 0.01)


func test_a_stagger_after_the_budget_expired_ends_in_disengage() -> void:
	var h = _harness("assault")
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.WIND_UP, 2.0))
	brain.budget.seconds = brain.budget.seconds - brain.budget.remaining()  # expires on the next update
	_step(ram, h.player)
	assert_eq(brain.phase, Phase.WIND_UP, "the expiry is deferred in WIND_UP")
	assert_true(brain.disengage_pending)
	_break_plate(ram, &"PlateLeft")
	assert_eq(brain.phase, Phase.STAGGER)
	var t := 0.0
	while brain.phase == Phase.STAGGER and t < 2.0:
		_step(ram, h.player)
		t += DT
	assert_eq(brain.phase, Phase.DISENGAGE, "the stagger hands over to DISENGAGE, not a new line-up")


# ── t17 9. Exposed ───────────────────────────────────────────────────────────────────────────────

func test_an_exposed_corvette_is_faster_and_hits_harder(mode: String = use_parameters(MODES)) -> void:
	var h = _harness(mode)
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	var mover := ram.get_node("EnemyMover") as EnemyMover
	await _strip(ram)
	assert_true(brain.exposed, "%s: the brain was told" % mode)
	assert_eq(ram.contact_hit_box.damage, 60, "%s: contact 60" % mode)
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 3.0))
	_step(ram, h.player)
	assert_almost_eq(ram.velocity.length(), 700.0, 0.01, "%s: the exposed charge is 700" % mode)
	brain.enter_phase(Phase.APPROACH)
	ram.global_position = Vector2(640.0, -100.0)
	_step(ram, h.player)
	assert_eq(mover.max_speed, 340.0, "%s: the exposed cruise cap" % mode)


## The Corvette's offset from the player's aim line (the line from the player along its facing).
func _off_aim_line(ram: RamCorvette, player: CharacterBody2D) -> Vector2:
	var f := Vector2.UP.rotated(player.rotation)
	var to_me := ram.global_position - player.global_position
	return to_me - f * to_me.dot(f)


## Runs an APPROACH (engage_range shrunk so it stays there) for 0.5 s with the player's nose `facing_deg` off the
## Corvette. Returns {off_before, off_after, nudged, nudge_away}: the aim-line offsets at the start and end, whether
## any nudge was offered, and whether every offered nudge pointed away from the aim line.
func _evasion_run(mode: String, strip: bool, facing_deg: float) -> Dictionary:
	var h = _harness(mode)
	var player_pos := Vector2(640.0, 760.0)
	var start := player_pos + Vector2(0.0, -550.0).rotated(deg_to_rad(10.0))
	var ram := _live_ram(h, start, player_pos, func(r: RamCorvette) -> void: r.config.engage_range = 50.0)
	if strip:
		await _strip(ram)
	h.player.rotation = Vector2.UP.angle_to(start - player_pos) + deg_to_rad(facing_deg)
	var off_before := _off_aim_line(ram, h.player)
	var nudged := false
	var nudge_away := true
	for i in 30:
		var off := _off_aim_line(ram, h.player)
		_step(ram, h.player)
		assert_eq(_brain(ram).phase, Phase.APPROACH, "%s: still approaching (tick %d)" % [mode, i])
		var nudge := _brain(ram).evade_nudge
		if nudge != Vector2.ZERO:
			nudged = true
			nudge_away = nudge_away and nudge.dot(off.normalized()) > 0.0
	var result := {"off_before": off_before, "off_after": _off_aim_line(ram, h.player), "nudged": nudged, "nudge_away": nudge_away}
	await _drop(h)
	return result


func test_an_exposed_corvette_jinks_out_of_the_aim_line_only_when_aimed_at(mode: String = use_parameters(MODES)) -> void:
	var aimed: Dictionary = await _evasion_run(mode, true, 8.0)
	var away: Dictionary = await _evasion_run(mode, true, 90.0)
	var armoured: Dictionary = await _evasion_run(mode, false, 8.0)
	assert_true(aimed["nudged"], "%s: aimed at (8 deg off its nose), exposed: it strafes" % mode)
	assert_true(aimed["nudge_away"], "%s: every strafe points away from the aim line" % mode)
	if mode == "open_space":
		var before: Vector2 = aimed["off_before"]
		var after: Vector2 = aimed["off_after"]
		assert_gt(after.length(), before.length() + 20.0, "it ends further from the aim line than it started")
		assert_gt(after.dot(before), 0.0, "on the same side it started on")
	assert_false(away["nudged"], "%s: not aimed at: no strafe" % mode)
	assert_false(armoured["nudged"], "%s: armoured: never" % mode)


# ── t17 10. Assault: the diagonal charge ─────────────────────────────────────────────────────────

func _assault_charge_dir(spawn_x: float) -> Vector2:
	var h = _harness("assault")
	var ram := _live_ram(h, Vector2(spawn_x, -440.0), Vector2(640.0, 360.0))
	assert_true(_run_to(ram, h.player, Phase.CHARGE, 6.0), "spawn x %.0f: it charged" % spawn_x)
	var dir := _brain(ram).charge_dir
	await _drop(h)
	return dir


func test_in_assault_the_charge_is_diagonal_even_from_straight_above() -> void:
	var dir: Vector2 = await _assault_charge_dir(640.0)
	assert_gte(rad_to_deg(absf(dir.angle_to(Vector2.DOWN))), 20.0, "a centred spawn still charges >= 20 deg off vertical")
	var right: Vector2 = await _assault_charge_dir(740.0)
	assert_gte(rad_to_deg(absf(right.angle_to(Vector2.DOWN))), 20.0)
	assert_lt(right.x, 0.0, "a spawn right of the player comes in from the right")


## Review R1-N3 / R2-N2: a LINE_UP the gate lets in with just `line_up_cap + ATTACK_GATE_MARGIN` left runs to its cap
## (the stub orbits faster than the nose turns, as in the cap test) and still becomes a wind-up before the budget
## expires; 10 ms less and the gate stays shut.
func test_a_line_up_at_the_edge_of_the_gate_still_winds_up() -> void:
	for short in [false, true]:
		var h = _harness("assault")
		var centre := Vector2(640.0, 360.0)
		var angle := PI / 2.0
		var ram := _live_ram(h, centre, centre + Vector2.RIGHT.rotated(angle) * 300.0)
		var brain := _brain(ram)
		brain.enter_phase(Phase.APPROACH)  # builds the budget
		var left := RAM_CONFIG.line_up_cap + RamCorvetteBrain.ATTACK_GATE_MARGIN + (-0.01 if short else 0.000001)
		brain.budget.seconds = left + DT  # `left` remains after the next tick's update
		var line_up_ticks := 0
		var seen := []
		for i in 240:
			if _gone(ram):
				break
			angle += 4.0 * DT
			h.player.global_position = centre + Vector2.RIGHT.rotated(angle) * 300.0
			h.player.velocity = Vector2.RIGHT.rotated(angle + PI / 2.0) * 1200.0
			var before := ram.global_position
			ram._physics_process(DT)
			ram.global_position = before + ram.velocity * DT
			if not seen.has(brain.phase):
				seen.append(brain.phase)
			if brain.phase == Phase.LINE_UP:
				line_up_ticks += 1
		if short:
			assert_false(seen.has(Phase.LINE_UP), "10 ms under the margin: the gate stays shut")
			assert_true(seen.has(Phase.DISENGAGE), "and it leaves")
		else:
			assert_eq(seen.slice(0, 3), [Phase.LINE_UP, Phase.WIND_UP, Phase.CHARGE], "at the margin: line-up, wind-up, charge")
			assert_gte(line_up_ticks * DT, RAM_CONFIG.line_up_cap - DT, "sanity: the line-up ran to its cap")
			assert_eq(brain.charges, 1)
		await _drop(h)


# ── t17 11. Assault expiry by state ──────────────────────────────────────────────────────────────

func test_expiry_in_wind_up_defers_to_the_charge_end_then_exits_straight() -> void:
	var h = _harness("assault")
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	assert_true(_run_to(ram, h.player, Phase.WIND_UP, 2.0))
	brain.budget.seconds = brain.budget.seconds - brain.budget.remaining()
	var t := 0.0
	var phases := []
	var disengaged_at := -1.0
	while brain.phase != Phase.DISENGAGE and t < 4.0:
		_step(ram, h.player)
		t += DT
		if not phases.has(brain.phase):
			phases.append(brain.phase)
	disengaged_at = t
	assert_eq(phases, [Phase.WIND_UP, Phase.CHARGE, Phase.DISENGAGE], "the charge runs, then it leaves")
	assert_lte(disengaged_at, RAM_CONFIG.wind_up_seconds + RAM_CONFIG.charge_max_time + DT,
			"deferred at most wind_up_seconds + charge_max_time")
	var dir := brain.charge_dir
	t = 0.0
	while not _gone(ram) and t < 6.0:
		_step(ram, h.player)
		t += DT
		if not _gone(ram):
			assert_lt(_deg(ram.velocity, dir), 1.0, "straight on along the charge heading")
	assert_true(_gone(ram), "and freed once out of the world rect")


func test_with_less_budget_than_a_line_up_it_never_lines_up() -> void:
	var h = _harness("assault")
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0),
			func(r: RamCorvette) -> void: r.config.engage_seconds = RAM_CONFIG.line_up_cap - 0.05)
	var brain := _brain(ram)
	var seen: Array[int] = []
	var t := 0.0
	while not _gone(ram) and t < 4.0:
		_step(ram, h.player)
		t += DT
		if not _gone(ram) and not seen.has(brain.phase):
			seen.append(brain.phase)
	assert_false(seen.has(Phase.LINE_UP), "in range, but remaining() < line_up_cap: never LINE_UP")
	assert_true(seen.has(Phase.DISENGAGE), "it just leaves")


func test_expiry_on_the_first_line_up_tick_disengages_that_tick() -> void:
	var h = _harness("assault")
	var ram := _live_ram(h, Vector2(640.0, 200.0), Vector2(640.0, 560.0))
	var brain := _brain(ram)
	brain.enter_phase(Phase.LINE_UP)
	brain.budget.seconds = brain.budget.seconds - brain.budget.remaining()
	_step(ram, h.player)
	assert_eq(brain.phase, Phase.DISENGAGE, "no deferral in LINE_UP")
	assert_false(brain.disengage_pending)


func test_expiry_in_approach_or_wide_turn_disengages_that_tick() -> void:
	for p in [Phase.APPROACH, Phase.WIDE_TURN]:
		var h = _harness("assault")
		var ram := _live_ram(h, Vector2(200.0, 100.0), Vector2(1000.0, 900.0))
		var brain := _brain(ram)
		brain.enter_phase(p)
		brain.budget.seconds = brain.budget.seconds - brain.budget.remaining()
		_step(ram, h.player)
		assert_eq(brain.phase, Phase.DISENGAGE, "%s: disengages that tick" % Phase.keys()[p])
		await _drop(h)


# ── t17 12. Open Space: no budget, charge after charge ──────────────────────────────────────────

func test_in_open_space_it_keeps_charging_and_never_leaves() -> void:
	var h = _harness("open_space")
	var ram := _live_ram(h, Vector2(300.0, 100.0), Vector2(640.0, 560.0),
			func(r: RamCorvette) -> void: r.config.engage_seconds = 4.5)
	var brain := _brain(ram)
	var left := false
	var t := 0.0
	while t < 12.0:
		_step(ram, h.player)
		t += DT
		left = left or brain.phase == Phase.DISENGAGE
	assert_false(left, "no budget in Open Space")
	assert_false(_gone(ram))
	assert_gte(brain.charges, 2, "at least two charges in 12 s (%d)" % brain.charges)


# ── t17 13. Attack in budget (epic plan §2.9.4; review N9: harness local) ────────────────────────
#
# `EngagementBudget` counts from spawn, so a level-1 ram must reach WIND_UP (after which the charge always
# follows: expiry there is deferred) before its budget runs out. Every ram offset in the live
# `Level1Director._build_sections()` is spawned through a real `WaveManager` under a real `ArenaCamera`, rails and
# delays stripped (t21/t22 take level 1 off rails). The Corvettes are hand-ticked from their `ready` signal.

const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

var _budget_rams: Array[RamCorvette] = []
var _budget_tweak: Callable = Callable()


## Every distinct design-unit offset a level-1 ram spawns at (formations expanded).
func _level1_ram_offsets() -> Array[Vector2]:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	var out: Array[Vector2] = []
	for s in d._build_sections():
		for w in (s as LevelSection).waves:
			for e in (w as WaveResource).entries:
				var entry: SpawnEntryResource = e
				if entry.ship_scene == null or entry.ship_scene.resource_path != WaveBuilder.RAM:
					continue
				var offsets: Array[Vector2] = [entry.base_offset]
				if entry.formation != null:
					offsets = []
					for slot in entry.formation.compute_slots():
						offsets.append(entry.base_offset + slot.offset)
				for o in offsets:
					if not out.has(o):
						out.append(o)
	return out


static func _ram_class(offset: Vector2) -> String:
	var wide := absf(offset.x) >= 100.0
	if offset.y < 0.0:
		return "top-wide" if wide else "top"
	return "bottom-wide" if wide else "bottom"


func _on_budget_child(node: Node) -> void:
	if not node is RamCorvette:
		return
	var ram := node as RamCorvette
	(ram.get_node("Brain") as RamCorvetteBrain).rng_seed = 1700 + _budget_rams.size()
	if _budget_tweak.is_valid():
		_budget_tweak.call(ram)
	ram.ready.connect(func() -> void: ram.set_physics_process(false), CONNECT_ONE_SHOT)
	_budget_rams.append(ram)


## Spawns one ram per offset at t = 0 through a real WaveManager, the player stub at `stub` from the camera
## centre, and hand-ticks them for `limit` s. Returns one `{offset, wind_up_at, remaining, charges}` per ram
## (`wind_up_at` -1 when it never wound up).
func _budget_run(offsets: Array[Vector2], stub: Vector2, limit: float) -> Array[Dictionary]:
	_budget_rams = []
	var harness = HARNESS.assault()
	add_child(harness.root)  # freed at the end of the run: a later run must not see this player
	_root = harness.root
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	harness.player.global_position = cam.global_position + stub
	var container := Node2D.new()
	container.name = "EnemyContainer"
	harness.root.add_child(container)
	container.child_entered_tree.connect(_on_budget_child)
	var wm := WaveManager.new()
	wm.enemy_container = container
	harness.root.add_child(wm)
	var wave := WaveResource.new()
	wave.trigger_time = 0.0
	var entries: Array[SpawnEntryResource] = []
	for o in offsets:
		var entry := SpawnEntryResource.new()
		entry.ship_scene = load(WaveBuilder.RAM)
		entry.base_offset = o
		entries.append(entry)
	wave.entries = entries
	var waves: Array[WaveResource] = [wave]
	wm.load_section(waves)
	var t := 0.0
	while _budget_rams.size() < offsets.size() and t < 1.0:
		await get_tree().process_frame
		t += DT
	wm.set_process(false)
	assert_eq(_budget_rams.size(), offsets.size(), "sanity: every ram spawned")
	var results: Array[Dictionary] = []
	for i in _budget_rams.size():
		results.append({"offset": offsets[i], "wind_up_at": -1.0, "remaining": -1.0, "charges": 0, "charge_dir": Vector2.ZERO})
	t = 0.0
	while t < limit:
		t += DT
		var all_gone := true
		for i in _budget_rams.size():
			var ram := _budget_rams[i]
			if _gone(ram):
				continue
			all_gone = false
			_step(ram, harness.player)
			if _gone(ram):
				continue
			var brain := _brain(ram)
			if brain.phase == Phase.WIND_UP and results[i]["wind_up_at"] < 0.0:
				results[i]["wind_up_at"] = t
				results[i]["remaining"] = brain.budget.remaining()
			if brain.charges > 0 and results[i]["charges"] == 0:
				results[i]["charge_dir"] = brain.charge_dir
			results[i]["charges"] = brain.charges
		if all_gone:
			break
	harness.root.queue_free()
	await get_tree().process_frame
	return results


func test_every_level1_ram_spawn_class_winds_up_inside_its_budget() -> void:
	var offsets := _level1_ram_offsets()
	var classes := {}
	for o in offsets:
		classes[_ram_class(o)] = true
	for c in ["top", "top-wide", "bottom", "bottom-wide"]:
		assert_true(classes.has(c), "sanity: level 1 spawns a %s ram (%s)" % [c, offsets])
	for o in offsets:
		for stub in [Vector2.ZERO, -o.normalized() * 200.0]:
			var one: Array[Vector2] = [o]
			var r: Dictionary = (await _budget_run(one, stub, RAM_CONFIG.engage_seconds + 3.0))[0]
			assert_gt(r["wind_up_at"], 0.0, "%s (%s), stub %s: WIND_UP reached" % [o, _ram_class(o), stub.round()])
			assert_gt(r["remaining"], 0.0, "%s (%s), stub %s: before its budget expired" % [o, _ram_class(o), stub.round()])
			var dir: Vector2 = r["charge_dir"]
			var off_vertical := rad_to_deg(asin(clampf(absf(dir.normalized().x), 0.0, 1.0)))
			assert_gte(off_vertical, 20.0, "%s (%s), stub %s: the charge is diagonal (%.1f deg)" % [o, _ram_class(o), stub.round(), off_vertical])
			gut.p("ram %s %-11s stub %s: WIND_UP at %.2f s (%.2f s of budget left), charge %.0f deg off vertical, %d charge(s) per life"
				% [o, _ram_class(o), stub.round(), r["wind_up_at"], r["remaining"], off_vertical, r["charges"]])


## Boundary: Revision 1's 160 px/s cruise on the top-wide class (stub away) never winds up before its budget ends.
func test_the_attack_in_budget_row_can_fail() -> void:
	_budget_tweak = func(r: RamCorvette) -> void: r.config.cruise_speed = 160.0
	var o := Vector2(270.0, -400.0)
	assert_true(_level1_ram_offsets().has(o), "sanity: a live top-wide offset")
	var one: Array[Vector2] = [o]
	var r: Dictionary = (await _budget_run(one, -o.normalized() * 200.0, RAM_CONFIG.engage_seconds + 3.0))[0]
	_budget_tweak = Callable()
	assert_lt(r["wind_up_at"], 0.0, "at 160 px/s the top-wide ram runs out of budget first")
	assert_eq(r["charges"], 0)


# ══ t19: hub idle (epic §2.10; task cmuyk2qqh0099oa2xbltzoust) ═══════════════════════════════════════════════════
#
# Cold-start helpers: unlike `_live_ram()` (which sets `start_engaged = true`, so every case above keeps assuming
# combat-from-spawn as before this task), these leave the brain to decide for itself - Open Space starts IDLE,
# Assault starts in combat. The stub player is stationary unless a case moves it.

const FAR_AWAY := Vector2(100000.0, 100000.0)


func _cold_ram(harness, pos: Vector2, player_pos: Vector2, anchor: Vector2 = Vector2.INF) -> RamCorvette:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	var ram := RAM_SCENE.instantiate() as RamCorvette
	var brain := ram.get_node("Brain") as RamCorvetteBrain
	brain.rng_seed = 1717
	brain.patrol_anchor = anchor
	ram.global_position = pos
	_root.add_child(ram)
	ram.set_physics_process(false)
	return ram


func _calm(p: int) -> bool:
	return p == Phase.IDLE or p == Phase.NOTICING or p == Phase.RETURNING


func test_the_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(Phase.APPROACH, 0)
	assert_eq(Phase.STAGGER, 6)
	assert_eq(Phase.IDLE, 7)
	assert_eq(Phase.NOTICING, 8)
	assert_eq(Phase.RETURNING, 9)


## §2.10: lose_radius >= engage_range + overshoot + 2 * exposed_cruise_speed / wide_turn_rate + 100, read from fields.
func test_the_idle_radii_clear_the_largest_distance_the_charge_cycle_opens() -> void:
	var c: RamCorvetteConfig = RAM_CONFIG
	var opened := c.engage_range + c.overshoot + 2.0 * c.exposed_cruise_speed / c.wide_turn_rate
	assert_gte(c.lose_radius, opened + 100.0, "lose_radius %.0f vs the distance the cycle opens %.0f + 100" % [c.lose_radius, opened])
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")
	assert_eq(c.perceive_radius, 600.0)
	assert_eq(c.lose_radius, 1300.0)
	assert_gte(c.perceive_radius, c.engage_range, "it notices the player before it can line up")


func test_open_space_cold_start_begins_idle_and_assault_starts_in_combat() -> void:
	var h = _harness("open_space")
	var ram := _cold_ram(h, Vector2(321.0, -654.0), FAR_AWAY)
	_step(ram, h.player)
	assert_eq(_brain(ram).phase, Phase.IDLE, "Open Space starts on patrol")
	assert_not_null(_brain(ram).anchor_idle)
	assert_eq(_brain(ram).patrol_anchor, Vector2(321.0, -654.0), "an unset anchor defaults to the spawn position")
	await _drop(h)
	var a = _harness("assault")
	var ram2 := _cold_ram(a, Vector2(640.0, -100.0), Vector2(640.0, 560.0))
	_step(ram2, a.player)
	assert_eq(_brain(ram2).phase, Phase.APPROACH, "Assault always starts in combat")
	assert_null(_brain(ram2).anchor_idle, "no AnchorIdle is built in Assault")


func test_idle_never_lines_up_winds_up_or_charges_and_stays_on_its_ring() -> void:
	var h = _harness("open_space")
	var anchor := Vector2(500.0, -400.0)
	var ram := _cold_ram(h, anchor + Vector2(20.0, 0.0), anchor + Vector2(RAM_CONFIG.perceive_radius + RAM_CONFIG.idle_radius + 80.0, 0.0), anchor)
	var worst := 0.0
	for _i in int(20.0 / DT):
		_step(ram, h.player)
		assert_eq(_brain(ram).phase, Phase.IDLE)
		worst = maxf(worst, ram.global_position.distance_to(anchor))
	assert_lte(worst, RAM_CONFIG.idle_radius + 30.0, "worst %.1f px from the anchor" % worst)
	assert_eq(_brain(ram).charges, 0)


func test_perceiving_the_player_notices_for_a_beat_then_fights() -> void:
	var h = _harness("open_space")
	var ram := _cold_ram(h, Vector2(640.0, 0.0), Vector2(640.0, RAM_CONFIG.perceive_radius - 100.0))
	var seen: Array[int] = []
	for _i in int(1.0 / DT):
		_step(ram, h.player)
		if seen.is_empty() or seen[-1] != _brain(ram).phase:
			seen.append(_brain(ram).phase)
	assert_eq(seen[0], Phase.NOTICING, "NOTICING for a beat first")
	assert_eq(seen[1], Phase.APPROACH, "then the fight starts (phases %s)" % [seen])


func test_beyond_lose_radius_it_goes_home_and_can_fight_again() -> void:
	var h = _harness("open_space")
	var anchor := Vector2.ZERO
	var ram := _cold_ram(h, anchor + Vector2(100.0, 0.0), Vector2(100.0 + RAM_CONFIG.engage_range + 40.0, 0.0), anchor)
	for _i in int(2.0 / DT):
		_step(ram, h.player)
		if not _calm(_brain(ram).phase):
			break
	assert_false(_calm(_brain(ram).phase), "it reached combat")
	assert_false(_brain(ram).phase == Phase.WIND_UP, "and is not yet committed")
	ram.global_position += Vector2(0.0, 700.0)  # well away from home, so there is a way back to walk
	h.player.global_position = FAR_AWAY
	var saw_returning := false
	var home := false
	for _i in int(60.0 / DT):
		_step(ram, h.player)
		saw_returning = saw_returning or _brain(ram).phase == Phase.RETURNING
		if _brain(ram).phase == Phase.IDLE:
			home = true
			break
	assert_true(saw_returning, "it passes through RETURNING on the way home")
	assert_true(home, "and reaches IDLE")
	h.player.global_position = ram.global_position + Vector2(RAM_CONFIG.perceive_radius - 50.0, 0.0)
	for _i in int(1.0 / DT):
		_step(ram, h.player)
	assert_true(not _calm(_brain(ram).phase), "and fights again")


## RETURNING never interrupts a WIND_UP or a CHARGE: the player vanishes (beyond lose_radius) mid wind-up, and the
## charge is still delivered before the Corvette turns for home.
func test_returning_never_interrupts_a_wind_up_or_a_charge() -> void:
	var h = _harness("open_space")
	var ram := _cold_ram(h, Vector2(640.0, 0.0), Vector2(640.0, 380.0))
	assert_true(_run_to(ram, h.player, Phase.WIND_UP, 8.0), "it lines up and winds up")
	h.player.global_position = FAR_AWAY
	var seen: Array[int] = []
	for _i in int(8.0 / DT):
		_step(ram, h.player)
		if seen.is_empty() or seen[-1] != _brain(ram).phase:
			seen.append(_brain(ram).phase)
		if _calm(_brain(ram).phase):
			break
	assert_eq(seen[0], Phase.WIND_UP)
	assert_true(seen.has(Phase.CHARGE), "the charge is delivered (phases %s)" % [seen])
	for i in seen.size() - 1:
		assert_false(seen[i] == Phase.WIND_UP and seen[i + 1] == Phase.RETURNING, "no cut-off wind-up")
	assert_true(seen[-1] == Phase.RETURNING or seen[-1] == Phase.IDLE, "and then it goes home (phases %s)" % [seen])


## A hub Corvette's missed charge (a stationary stub is passed through) and WIDE_TURN never read as losing the
## player: it stays in combat on every tick, and never opens more than lose_radius.
func test_a_hub_ram_stays_in_combat_through_a_missed_charge_and_the_wide_turn() -> void:
	var h = _harness("open_space")
	var ram := _cold_ram(h, Vector2(640.0, 0.0), Vector2(640.0, 380.0))
	var seen: Array[int] = []
	var in_combat := false
	var worst := 0.0
	var wide_turns := 0
	for _i in int(40.0 / DT):
		_step(ram, h.player)
		var p := _brain(ram).phase
		if seen.is_empty() or seen[-1] != p:
			seen.append(p)
			if p == Phase.WIDE_TURN:
				wide_turns += 1
		if p == Phase.APPROACH:
			in_combat = true
		if in_combat:
			assert_false(_calm(p), "combat tick %d is %s" % [_i, p])
			worst = maxf(worst, ram.global_position.distance_to(h.player.global_position))
		if wide_turns >= 2 and p == Phase.LINE_UP:
			break
	assert_gte(wide_turns, 2, "two missed charges and their wide turns (phases %s)" % [seen])
	assert_lt(worst, RAM_CONFIG.lose_radius, "the cycle opened %.0f px against lose_radius %.0f" % [worst, RAM_CONFIG.lose_radius])
