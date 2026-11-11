## INTENT tests for the destructible-part framework: `EnemyModule` (`global/components/enemy_module.gd`) and `ModularHull`
## (`global/components/modular_hull.gd`), Phase 10 t2 (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.1, §2.2; task plan
## docs/plans/cmwafsrau009zqs2yc1rli3sj/3-plan.md, whose row numbers the section headers below follow).
##
## On `tests/helpers/fixture_modular_host.tscn`: a `BaseEnemy` whose root deflects every projectile and refuses every damage, with three
## 12 px parts 80 px apart under `Modules` — `Open` (-80, 0) WEAPON, `Locked` (0, 0) CORE and not vulnerable, `Laser` (80, 0) ENGINE with a
## `DefenseProfile` accepting LASER only — each 100 HP, `hull_share` 0, and a `ModularHull`. A default bullet deals 50.
##
## Projectile, beam and laser-ray rows run on real physics at the 8x clock (`_scale_clock()` / `_restore_clock()`, the
## `test_level1_drone_exit.gd` pair: the step stays 1/60 game-second). The host never moves in a t2 row, so those rows run in one world;
## the direct-emitter rows that need no physics (nova, enemy energy weapons) run in both harnesses. Mount rows (`build_mounts`, unique
## pool names, mounts powered down) are t3's.
extends GutTest

const HOST_SCENE: PackedScene = preload("res://tests/helpers/fixture_modular_host.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const LASER_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")
const WRECK_TEXTURE: Texture2D = preload("res://assault/assets/sprites/enemies/station_turret_destroyed.png")
const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")

const MODES := ["open_space", "assault"]
const ORIGIN := Vector2(400.0, 300.0)
const SHOT: float = 110.0
const BULLET_DAMAGE: int = 50
const PART_HP: int = 100
const HOST_HP: int = 1000
const DT := 1.0 / 60.0
const _SPEEDUP: int = 8

var _root: Node2D
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_scale_clock()
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


## The fixture host at [param at] under [param parent] (the test container by default). [param prepare] runs on the instance BEFORE it
## enters the tree, so a row can change an export or connect a recorder ahead of `ModularHull._ready()`'s own connections.
func _host(parent: Node = null, at: Vector2 = ORIGIN, prepare: Callable = Callable()) -> BaseEnemy:
	var host := HOST_SCENE.instantiate() as BaseEnemy
	host.position = at
	if prepare.is_valid():
		prepare.call(host)
	(parent if parent != null else _root).add_child(host)
	return host


func _part(host: Node, part_name: String) -> EnemyModule:
	return host.get_node("Modules/" + part_name) as EnemyModule


func _hull(host: Node) -> ModularHull:
	return host.get_node("ModularHull") as ModularHull


func _hp(part: EnemyModule) -> int:
	return part.health.current_health


func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## A real projectile launched at [param target] from `SHOT` px away along [param from_dir], nose toward it (player projectiles fly along
## `Vector2.UP.rotated(rotation)`). Its flight ends the way `WeaponBehavior._launch()` ends it: `expired -> queue_free`.
func _fire(scene: PackedScene, target: Vector2, from_dir: Vector2) -> Node2D:
	var p: Node2D = scene.instantiate()
	_root.add_child(p)
	p.global_position = target + from_dir * SHOT
	p.rotation = Vector2.UP.angle_to(-from_dir)
	if p.has_signal("expired"):
		p.expired.connect(p.queue_free)
	return p


func _is_consumed(node: Variant) -> bool:
	return not is_instance_valid(node) or node.is_queued_for_deletion()


## Counts emissions of a signal with up to two arguments.
func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


func _hitbox(damage: int, type: HitBox.DamageType = HitBox.DamageType.LASER) -> HitBox:
	var hb := HitBox.new()
	hb.damage = damage
	hb.damage_type = type
	autofree(hb)
	return hb


func _particles_under(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		if child is CPUParticles2D:
			n += 1
	return n


## Drives a real `BeamBehavior` from `_physics_process` (the `test_ram_corvette.gd` / `test_station_incoming_damage_paths.gd` driver):
## the code under test is `BeamBehavior.tick()`, which reads only `actor.rotation`, the world and `actor.damage_multiplier`.
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []

	func _physics_process(delta: float) -> void:
		if behavior != null:
			behavior.tick(self, mode, muzzles, delta)


## A beam driver 300 px below [param target], firing straight up through it.
func _beam_under(target: Vector2) -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	_root.add_child(d)
	d.global_position = target + Vector2(0.0, 300.0)
	return d


## A level `LaserRay` whose 56 px strip runs down through [param x] from 200 px above [param y], opened by hand (no `SceneTreeTimer`):
## `start()`, `_begin_increase()`, then `_on_animation_finished()` while the master segment plays `laser_increase` enters IDLE and
## switches the `HitZone` on. Its 0.1 s re-hit `Timer` is a child, freed with the ray.
func _lit_ray(x: float, y: float) -> LaserRay:
	var ray := LASER_SCENE.instantiate() as LaserRay
	ray.auto_start = false
	ray.warn_duration = 0.0
	ray.active_duration = 0.0
	_root.add_child(ray)
	ray.global_position = Vector2(x, y - 200.0)
	ray.start()
	ray._begin_increase()
	ray._on_animation_finished()
	return ray


# ---------------------------------------------------------------------------------------------
# 1–7. Real physics
# ---------------------------------------------------------------------------------------------

func test_a_bullet_into_the_open_part_is_consumed_and_hurts_only_that_part() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var b := _fire(BULLET_SCENE, open.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(b), "the open part consumes the bullet")
	assert_eq(_hp(open), PART_HP - BULLET_DAMAGE, "and takes its damage")
	assert_eq(host.health.current_health, HOST_HP, "the armoured root refused the crossing and hull_share is 0")
	assert_eq(_hp(_part(host, "Locked")), PART_HP)
	assert_eq(_hp(_part(host, "Laser")), PART_HP)


func test_a_bullet_through_the_locked_part_flies_on_until_the_part_is_made_vulnerable() -> void:
	var host := _host()
	var locked := _part(host, "Locked")
	var deflected := _count(locked.deflected)
	var b := _fire(BULLET_SCENE, locked.global_position, Vector2.DOWN)
	var expired := _count(b.expired)
	await _frames(20)
	assert_false(_is_consumed(b), "a locked part lets the bullet through")
	assert_eq(expired[0], 0, "no expired")
	assert_eq(_hp(locked), PART_HP, "and takes nothing")
	assert_eq(deflected[0], 1, "one white ping")

	var changes: Array = []
	locked.vulnerability_changed.connect(func(m: EnemyModule, on: bool) -> void: changes.append([m, on]))
	locked.set_vulnerable(true)
	assert_eq(changes, [[locked, true]], "vulnerability_changed once")
	var b2 := _fire(BULLET_SCENE, locked.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(b2), "once vulnerable the part consumes the next bullet")
	assert_eq(_hp(locked), PART_HP - BULLET_DAMAGE)
	assert_eq(deflected[0], 1, "no further ping")


func test_a_rocket_against_the_laser_only_part_flies_on_and_does_no_damage() -> void:
	var host := _host()
	var laser := _part(host, "Laser")
	var deflected := _count(laser.deflected)
	var rocket := _fire(WARHEAD_SCENE, laser.global_position, Vector2.DOWN)
	await _frames(25)
	assert_false(_is_consumed(rocket), "the type filter refuses a rocket, so it flies on")
	assert_eq(_hp(laser), PART_HP, "no damage")
	assert_eq(deflected[0], 1, "the refused type pings once")

	# Control: the same part takes a LASER-type bullet.
	var b := _fire(BULLET_SCENE, laser.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(b), "a bullet is accepted and consumed")
	assert_eq(_hp(laser), PART_HP - BULLET_DAMAGE)
	assert_eq(deflected[0], 1)


func test_the_wreck_stays_on_the_hull_and_lets_later_shots_through() -> void:
	var order: Array = []
	# Recorders connected before the host enters the tree, i.e. before `ModularHull._ready()` connects its own (Godot calls a signal's
	# callbacks in connection order), so the log shows the order each signal goes out in.
	var record := func(h: BaseEnemy) -> void:
		var o := _part(h, "Open")
		o.damaged.connect(func(_m: EnemyModule, _a: int) -> void: order.append("damaged"))
		o.destroyed.connect(func(_m: EnemyModule) -> void: order.append("destroyed"))
		_hull(h).module_damaged.connect(func(_m: EnemyModule, _a: int) -> void: order.append("module_damaged"))
		_hull(h).module_destroyed.connect(func(_m: EnemyModule) -> void: order.append("module_destroyed"))
	var host := _host(null, ORIGIN, record)
	var open := _part(host, "Open")
	var modules := host.get_node("Modules")

	var b1 := _fire(BULLET_SCENE, open.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(b1))
	assert_false(open.is_destroyed(), "50 of 100")
	var b2 := _fire(BULLET_SCENE, open.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(b2), "the killing shot is consumed")
	assert_true(open.is_destroyed())

	await _frames(120)  # 2 s of game time
	assert_eq(open.get_parent(), modules, "the wreck is still a child of Modules")
	assert_eq(open.visual_state(), EnemyModule.VisualState.WRECK)
	assert_eq(open.sprite.texture, WRECK_TEXTURE, "the sprite shows the wreck texture")
	assert_false(open.is_in_group(&"enemy_parts"), "out of enemy_parts")
	assert_false(open.hurt_box.monitoring, "the hurtbox no longer monitors")
	assert_false(open.hurt_box.monitorable)
	assert_true((open.hurt_box.get_node("CollisionShape2D") as CollisionShape2D).disabled, "and its shape is off")
	var b3 := _fire(BULLET_SCENE, open.global_position, Vector2.DOWN)
	await _frames(20)
	assert_false(_is_consumed(b3), "a later bullet flies through the wreck")
	assert_eq(order, ["damaged", "module_damaged", "damaged", "module_damaged", "destroyed", "module_destroyed"],
		"damage before destruction, each re-emitted by the hull right after the part, destroyed exactly once")
	assert_true(is_instance_valid(host) and not host.is_queued_for_deletion(), "the host lives on")
	assert_eq(host.health.current_health, HOST_HP)


func test_a_local_shield_on_a_part_eats_a_frontal_bullet_and_not_a_rear_one() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var locked := _part(host, "Locked")
	var shields: Array[EnemyShield] = []
	for part in [open, locked]:
		var s := EnemyShield.new()
		s.arc_deg = 110.0
		s.capacity = HOST_HP
		part.add_child(s)
		assert_true(s.attach(part.hurt_box), "the shield takes the part hurtbox's slot")
		s.face(Vector2.DOWN)
		shields.append(s)

	var front := _fire(BULLET_SCENE, open.global_position, Vector2.DOWN)
	var into_locked := _fire(BULLET_SCENE, locked.global_position, Vector2.DOWN)
	await _frames(20)
	assert_true(_is_consumed(front), "the shield eats the bullet: the part answered consume")
	assert_eq(_hp(open), PART_HP, "the part took nothing")
	assert_eq(shields[0].points(), HOST_HP - BULLET_DAMAGE, "the shield paid; the armoured root does not switch it off")
	assert_false(_is_consumed(into_locked), "a locked part answers is_armored(), so its shield absorbs nothing")
	assert_eq(shields[1].points(), HOST_HP, "and spends no points on a bullet the part lets through")
	assert_eq(_hp(locked), PART_HP)

	var rear := _fire(BULLET_SCENE, open.global_position, Vector2.UP)
	await _frames(20)
	assert_true(_is_consumed(rear))
	assert_eq(_hp(open), PART_HP - BULLET_DAMAGE, "from behind it lands on the part")
	assert_eq(shields[0].points(), HOST_HP - BULLET_DAMAGE, "outside the arc the shield pays nothing")


func test_the_beam_burns_the_open_part_and_never_the_locked_part_or_the_armoured_root() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var locked := _part(host, "Locked")
	var deflected := _count(locked.deflected)
	var on_open := _beam_under(open.global_position)
	var on_locked := _beam_under(locked.global_position)  # its line also crosses the root's centre
	await _frames(120)
	assert_lt(_hp(open), PART_HP, "the beam burns the open part (it passes over the non-blocking hull)")
	assert_gt(_hp(open), 0, "2 s of mining laser does not kill it")
	assert_eq(_hp(locked), PART_HP, "the locked part ignores the burn")
	assert_gt(deflected[0], 0, "and pings")
	assert_eq(host.health.current_health, HOST_HP, "the armoured root takes nothing")

	locked.destroy()  # no wreck_texture: the tint path
	open.destroy()  # the texture path
	await _frames(15)
	var behavior := on_locked.behavior
	on_open.behavior = null
	on_locked.behavior = null
	behavior.cool_targets(0.5)
	var heat := locked.modulate
	assert_almost_eq(Vector4(heat.r, heat.g, heat.b, heat.a), Vector4(1.0, 0.5, 0.5, 1.0), Vector4(0.001, 0.001, 0.001, 0.001),
		"the beam's heat lives on the part node (1.0 cooled to 0.5)")
	assert_eq(locked.sprite.modulate, EnemyModule.WRECK_TINT, "the wreck tint lives on the Sprite child, under the beam's")
	assert_eq(open.sprite.texture, WRECK_TEXTURE, "a wreck texture is kept")
	assert_eq(open.sprite.modulate, Color.WHITE, "and needs no tint")


func test_a_lit_laser_ray_destroys_the_open_part_and_spares_the_locked_one() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var locked := _part(host, "Locked")
	var open_damaged := _count(open.damaged)
	var deflected := _count(locked.deflected)
	_lit_ray(open.global_position.x, open.global_position.y)
	_lit_ray(locked.global_position.x, locked.global_position.y)
	await _frames(10)
	assert_true(open.is_destroyed(), "a lit column kills an open part")
	assert_gt(open_damaged[0], 0, "through received_damage")
	assert_false(locked.is_destroyed(), "a locked part survives it")
	assert_eq(_hp(locked), PART_HP)
	assert_gt(deflected[0], 0)
	assert_true(is_instance_valid(host) and not host.is_queued_for_deletion(), "the host lives")
	assert_eq(host.health.current_health, HOST_HP)
	assert_false(_part(host, "Laser").is_destroyed(), "the 56 px strips miss the part 80 px away")


# ---------------------------------------------------------------------------------------------
# 8–17. No physics
# ---------------------------------------------------------------------------------------------

func test_the_killing_shot_is_consumed_whichever_callback_runs_first() -> void:
	# Order A: the projectile asks first, then the hurtbox delivers the kill.
	var open_a := _part(_host(), "Open")
	var shot_a := _hitbox(PART_HP)
	assert_false(open_a.deflects_hit(shot_a), "A: asked first, the live part consumes")
	open_a.hurt_box.received_damage.emit(shot_a.damage)
	assert_true(open_a.is_destroyed(), "A: killed")
	assert_false(open_a.deflects_hit(shot_a), "A: the cached answer stands")

	# Order B: the hurtbox delivers the kill, then the projectile asks.
	var open_b := _part(_host(null, ORIGIN + Vector2(0.0, 200.0)), "Open")
	var shot_b := _hitbox(PART_HP)
	open_b.hurt_box.received_damage.emit(shot_b.damage)
	assert_true(open_b.is_destroyed(), "B: killed")
	assert_false(open_b.deflects_hit(shot_b), "B: destroyed this physics frame, the part still consumes its killing shot")
	assert_true(open_b.deflects_hit(null), "a null hit is never consumed")

	# Boundary: a wreck from an earlier physics frame deflects.
	await get_tree().physics_frame
	assert_true(open_b.deflects_hit(_hitbox(BULLET_DAMAGE)), "one frame later the wreck lets a new shot through")


func test_an_indestructible_part_is_never_destroyed_and_still_forwards_its_damage() -> void:
	var prepare := func(h: BaseEnemy) -> void:
		var o := _part(h, "Open")
		o.max_health = 0
		o.hull_share = 1.0
		var health := h.get_node("Health") as Health
		health.max_health = 20000
		health.current_health = 20000
	var host := _host(null, ORIGIN, prepare)
	var open := _part(host, "Open")
	var amounts: Array = []
	open.damaged.connect(func(_m: EnemyModule, a: int) -> void: amounts.append(a))
	open.hurt_box.received_damage.emit(10000)
	assert_false(open.is_destroyed(), "max_health 0 is never destroyed by damage")
	assert_eq(open.visual_state(), EnemyModule.VisualState.INTACT)
	assert_true(open.is_in_group(&"enemy_parts"))
	assert_eq(amounts, [10000], "damage is still reported")
	assert_eq(host.health.current_health, 10000, "and forwarded through hull_share")
	assert_eq(open.health.current_health, 10, "the authored Health is never consulted")
	assert_null(open.get_node_or_null("Sparks"), "and an indestructible part has no damage sparks")


func test_hull_share_forwards_the_rounded_share_to_the_host() -> void:
	var prepare := func(h: BaseEnemy) -> void:
		_part(h, "Open").hull_share = 1.0
		_part(h, "Laser").hull_share = 0.5
		_part(h, "Locked").starts_vulnerable = true
	var host := _host(null, ORIGIN, prepare)
	var amounts: Array = []
	_hull(host).module_damaged.connect(func(m: EnemyModule, a: int) -> void: amounts.append([m.module_id, a]))
	_part(host, "Open").hurt_box.received_damage.emit(50)
	assert_eq(host.health.current_health, HOST_HP - 50, "share 1.0: the whole hit")
	_part(host, "Laser").hurt_box.received_damage.emit(25)
	assert_eq(host.health.current_health, HOST_HP - 50 - 13, "share 0.5 of 25 rounds to 13")
	_part(host, "Locked").hurt_box.received_damage.emit(40)
	assert_eq(host.health.current_health, HOST_HP - 63, "share 0 forwards nothing")
	assert_eq(_hp(_part(host, "Locked")), PART_HP - 40, "but the part itself took it")
	assert_eq(amounts, [[&"open", 50], [&"laser", 25], [&"locked", 40]], "module_damaged re-emits every hit with the part's amount")


func test_a_parts_own_defense_profile_is_applied_to_its_hurtbox() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var laser := _part(host, "Laser")
	var profile := laser.get_node("DefenseProfile") as DefenseProfile
	# Every part HurtBox authors layer 0, mask 0 and no types, so what is read here was written by EnemyModule._ready().
	assert_eq(laser.hurt_box.collision_layer, CollisionLayers.ENEMY_HURTBOX)
	assert_eq(laser.hurt_box.collision_mask, profile.mask(), "the part's own profile mask")
	assert_eq(profile.mask(), 1121, "(default flags)")
	assert_eq(Array(laser.hurt_box.accepted_damage_types), [HitBox.DamageType.LASER], "the profile's types")
	assert_eq(open.hurt_box.collision_layer, CollisionLayers.ENEMY_HURTBOX)
	assert_eq(open.hurt_box.collision_mask,
		CollisionLayers.PLAYER_HITBOX | CollisionLayers.PLAYER_ROCKETS | CollisionLayers.HAZARD_CONTACT, "no profile: the §2.1 default")
	assert_true(open.hurt_box.accepted_damage_types.is_empty(), "every damage type")
	assert_eq(host.hurt_box.collision_mask, 1121, "the root keeps its own profile")
	assert_eq([open.health.max_health, open.health.current_health], [PART_HP, PART_HP], "an authored 10 / 10 Health takes max_health")
	assert_not_null(laser.health, "a part that authors no Health gets one")
	assert_eq(laser.health.get_parent(), laser)
	assert_eq([laser.health.max_health, laser.health.current_health], [PART_HP, PART_HP])


func test_the_nova_damages_every_live_part_on_the_map_and_never_a_locked_one(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var near := _host(h.root, Vector2(400.0, 300.0))
	var far := _host(h.root, Vector2(4400.0, 300.0))
	var far_wreck := _part(far, "Open")
	far_wreck.destroy()
	var pings := [_count(_part(near, "Locked").deflected), _count(_part(far, "Locked").deflected)]
	var before := get_tree().root.get_children()
	assert_true(PlasmaNovaModule.new().try_activate(h.player), "%s: the nova fires" % mode)
	for child in get_tree().root.get_children():
		if child not in before:
			child.free()  # the nova's full-screen flash layer and its tween
	assert_eq(_hp(_part(near, "Open")), PART_HP - 50, "%s: an open part takes 50" % mode)
	assert_eq(_hp(_part(near, "Laser")), PART_HP - 50, "%s: a direct emit skips the hurtbox's type filter" % mode)
	assert_eq(_hp(_part(far, "Laser")), PART_HP - 50, "%s: 4000 px away too: the nova is map-wide" % mode)
	assert_eq(_hp(_part(near, "Locked")), PART_HP, "%s: a locked part ignores it" % mode)
	assert_eq(_hp(_part(far, "Locked")), PART_HP, "%s" % mode)
	assert_eq([pings[0][0], pings[1][0]], [1, 1], "%s: and pings once each" % mode)
	assert_eq(_hp(far_wreck), PART_HP, "%s: a wreck is out of enemy_parts and untouched" % mode)
	assert_eq([near.health.current_health, far.health.current_health], [HOST_HP, HOST_HP], "%s: the armoured roots refuse it" % mode)


func test_enemy_energy_weapons_never_reach_a_part(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var host := _host(h.root, Vector2(600.0, 300.0))
	var parts: Array[EnemyModule] = [_part(host, "Open"), _part(host, "Locked"), _part(host, "Laser")]
	var damaged: Array[int] = [0]
	for part in parts:
		part.damaged.connect(func(_m: EnemyModule, _a: int) -> void: damaged[0] += 1)

	# A Pulse Ring centred on the host, gaps held at 90 / 270 degrees so the root (bearing 0) is never in one; no owner set.
	var ring := EnemyBeamScenes.ring_scene().instantiate() as EnergyRing
	h.root.add_child(ring)
	ring.global_position = host.global_position
	ring.gap_spin_deg = 0.0
	ring.setup(null, &"")
	var ring_hits: Array = []
	ring.target_hit.connect(func(t: Node2D, _d: int) -> void: ring_hits.append(t))
	ring.start(90.0)
	for i in 300:
		ring.tick(DT)
		if ring.phase() == EnergyRing.Phase.OFF:
			break
	assert_eq(ring.phase(), EnergyRing.Phase.OFF, "%s: the ring ran its whole cycle" % mode)
	assert_has(ring_hits, host, "%s: control: the ring reached the root" % mode)

	# A static beam from 300 px left of the host along +X, through the root and all three parts.
	var beam := EnemyBeamScenes.scene_for(EnemyBeam.Kind.BEAM).instantiate() as EnemyBeam
	h.root.add_child(beam)
	beam.global_position = host.global_position + Vector2(-300.0, 0.0)
	beam.global_rotation = 0.0
	beam.setup(null, &"")
	var beam_hits: Array = []
	beam.target_hit.connect(func(t: Node2D, _d: int) -> void: beam_hits.append(t))
	beam.start()
	for i in 600:
		beam.tick(DT)
		if beam.phase() == EnemyBeam.Phase.OFF:
			break
	assert_eq(beam.phase(), EnemyBeam.Phase.OFF, "%s: the beam ran its whole cycle" % mode)
	assert_has(beam_hits, host, "%s: control: the beam reached the root" % mode)

	for part in parts:
		assert_eq(_hp(part), PART_HP, "%s: %s untouched" % [mode, part.name])
		assert_does_not_have(ring_hits, part)
		assert_does_not_have(beam_hits, part)
	assert_eq(damaged[0], 0, "%s: no part heard a hit" % mode)
	assert_eq(host.health.current_health, HOST_HP, "%s: the root refused the hits it took" % mode)


func test_the_hull_collects_its_parts_in_tree_order_and_answers_queries() -> void:
	var host := _host()
	var hull := _hull(host)
	var open := _part(host, "Open")
	var locked := _part(host, "Locked")
	var laser := _part(host, "Laser")
	var got: Array = []
	got.assign(hull.modules())
	assert_eq(got, [open, locked, laser], "Modules/* in tree order")
	assert_eq(hull.module(&"locked"), locked)
	assert_null(hull.module(&"none"))
	assert_eq(_ids(hull.live(EnemyModule.Role.WEAPON)), [&"open"])
	assert_eq(_ids(hull.live(EnemyModule.Role.CORE)), [&"locked"])
	assert_eq(_ids(hull.live(EnemyModule.Role.ENGINE)), [&"laser"])
	assert_true(hull.live(EnemyModule.Role.HANGAR).is_empty())
	assert_eq(hull.destroyed_count([EnemyModule.Role.WEAPON]), 0)

	open.destroy()
	assert_true(hull.live(EnemyModule.Role.WEAPON).is_empty(), "live() drops the wreck")
	assert_eq(hull.destroyed_count([EnemyModule.Role.WEAPON]), 1)
	assert_eq(hull.destroyed_count([EnemyModule.Role.CORE, EnemyModule.Role.ENGINE]), 0, "a role set without the wreck's role")
	assert_eq(hull.destroyed_count([]), 1, "an empty set counts any role")
	assert_true(hull.mounts_of(&"open").is_empty(), "no mounts on the fixture (mount rows are t3's)")
	assert_true(hull.mounts_of(&"none").is_empty())


func _ids(parts: Array[EnemyModule]) -> Array:
	var out: Array = []
	for p in parts:
		out.append(p.module_id)
	return out


func test_destruction_is_once_only_and_reemitted_once() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var hull := _hull(host)
	var destroyed := _count(open.destroyed)
	var module_destroyed := _count(hull.module_destroyed)
	var damaged := _count(open.damaged)
	var vulnerability := _count(open.vulnerability_changed)
	var light := open.get_node("Light") as StateLight
	light.set_state(StateLight.State.ARMED)
	var bursts_before := _particles_under(_root)

	open.destroy()
	open.destroy()
	open.hurt_box.received_damage.emit(50)
	assert_eq(destroyed[0], 1, "destroyed once")
	assert_eq(module_destroyed[0], 1, "re-emitted once")
	assert_eq(damaged[0], 0, "a wreck takes no damage")
	assert_eq(_hp(open), PART_HP)
	assert_false(open.is_in_group(&"enemy_parts"))
	assert_true(hull.live(EnemyModule.Role.WEAPON).is_empty())
	open.set_vulnerable(false)
	open.set_vulnerable(true)
	assert_eq(vulnerability[0], 0, "set_vulnerable on a wreck emits nothing")
	assert_true(open.is_armored(), "a wreck refuses shields too")
	assert_eq(light.get_state(), StateLight.State.OFF, "its light goes dark")
	assert_eq(_particles_under(_root), bursts_before + 1, "the destruction burst goes into the host's parent")
	assert_eq(_particles_under(host.get_node("Modules")), 0, "not into Modules")
	assert_eq(open.get_parent(), host.get_node("Modules"), "the wreck stays")


func test_visual_state_goes_from_intact_to_damaged_to_wreck() -> void:
	var host := _host()
	var open := _part(host, "Open")
	var sparks := open.get_node("Sparks") as LowHealthSmoke
	assert_not_null(sparks, "a destructible part composes LowHealthSmoke as its damage sparks")
	assert_eq(sparks.threshold, open.damaged_ratio)
	assert_eq(open.visual_state(), EnemyModule.VisualState.INTACT)
	open.hurt_box.received_damage.emit(49)
	assert_eq(open.visual_state(), EnemyModule.VisualState.INTACT, "51 of 100 is above the 0.5 ratio")
	assert_false(sparks._particles.emitting)
	open.hurt_box.received_damage.emit(1)
	assert_eq(open.visual_state(), EnemyModule.VisualState.DAMAGED, "50 of 100 is at the ratio")
	assert_true(sparks._particles.emitting, "a damaged part sparks")
	open.hurt_box.received_damage.emit(50)
	assert_eq(open.visual_state(), EnemyModule.VisualState.WRECK)
	assert_false(sparks._particles.emitting, "a wreck stops sparking")

	# A scripted kill above 0 HP: Laser, damaged by a direct emit (which skips its type filter).
	var laser := _part(host, "Laser")
	var laser_sparks := laser.get_node("Sparks") as LowHealthSmoke
	laser.hurt_box.received_damage.emit(60)
	assert_eq(laser.visual_state(), EnemyModule.VisualState.DAMAGED)
	assert_true(laser_sparks._particles.emitting)
	laser.destroy()
	assert_eq(laser.visual_state(), EnemyModule.VisualState.WRECK)
	assert_false(laser_sparks._particles.emitting, "destroy() at 40 HP stops the sparks too")


func test_homing_point_is_the_marker_else_the_part_centre() -> void:
	var host := _host(null, Vector2(500.0, 200.0))
	var open := _part(host, "Open")
	var locked := _part(host, "Locked")
	assert_eq(open.homing_point(), (open.get_node("HomingPoint") as Marker2D).global_position, "the HomingPoint marker")
	assert_eq(open.homing_point(), Vector2(500.0 - 80.0, 212.0))
	assert_eq(locked.homing_point(), locked.global_position, "no marker: the part's centre")
	assert_eq(locked.homing_point(), Vector2(500.0, 200.0))
