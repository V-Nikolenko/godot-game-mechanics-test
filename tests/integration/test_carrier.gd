## The Carrier's shell: armoured hull, seven parts, core exposure, death through the core and movement in both modes (docs/plans/cmug23oo90029m52wae4clve0/
## 3-plan.md §2.6; Phase 10 t6, task plan docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md, whose row numbers the section headers follow). Intent tests.
##
## A. The projectile / beam / nova rows run on real physics at the 16x clock (`_scale_clock()`: ticks per second are scaled, the step stays 1/60 s) with
##    every carrier's physics off (no brain, no mover), so a shot meets the authored geometry exactly and the mode cannot change a result. They share
##    three carriers side by side (x 300 / 900 / 1500: no vertical beam crosses another hull) and run their windows concurrently. A bullet is fired
##    with a `range_px` that ends its flight just past its target, so "flew on" (it expired at its range) and "consumed" (it expired on a hit) are
##    told apart without a free-flying round crossing a later window.
## B. The rest is hand-ticked at 1/60 (`_tick`: `_physics_process(dt)`, then the position integrated from the velocity), in both harnesses unless a
##    row says otherwise; the test moves the harness player itself.
##
## Frame: the art is nose-down, so the nose is local +y, port (the hull's left) local +x, the stern local -y.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/carrier/carrier.tscn")
const SHIPPED: CarrierConfig = preload("res://assault/scenes/enemies/carrier/carrier_config.tres")  # read only
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const Phase := CarrierBrain.Phase
const Role := EnemyModule.Role

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const ASSAULT_PLAYER := Vector2(640.0, 620.0)
## (node name, id, role, max_health, starts_vulnerable) in tree order.
const PARTS := [
	["EnginePort", &"engine_port", Role.ENGINE, 180, true],
	["EngineStarboard", &"engine_starboard", Role.ENGINE, 180, true],
	["GunPort", &"gun_port", Role.WEAPON, 160, true],
	["GunStarboard", &"gun_starboard", Role.WEAPON, 160, true],
	["HangarPort", &"hangar_port", Role.HANGAR, 220, false],
	["HangarStarboard", &"hangar_starboard", Role.HANGAR, 220, false],
	["Core", &"core", Role.CORE, 600, false],
]
## A projectile row's shot starts this far from its target (px).
const SHOT := 110.0
const BULLET_DAMAGE := 50
const NOVA_DAMAGE := 50
## The real-physics row's y and its 2 s beam (in physics frames).
const ROW_Y := 400.0
const BEAM_FRAMES := 120
## Half the 176 x 280 body.
const HULL_HALF_HEIGHT := 140.0
const _SPEEDUP := 16  # tests/README.md -> Gate time rule 1: the A rows wait a count of physics frames, never seconds

var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()
	_roots.clear()


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


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

## A fresh harness world. Any earlier world of this test is taken out of the tree first (its player would still be in group `player`, its camera
## an arena); it is still freed with the test.
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = ASSAULT_PLAYER if h.is_assault else Vector2.ZERO
	return h


## A hand-ticked carrier. [param props] are written on its private config copy before it enters the tree.
func _spawn(h, pos: Vector2, props: Dictionary = {}, engaged: bool = true) -> Carrier:
	var c := SCENE.instantiate() as Carrier
	(c.get_node("Brain") as CarrierBrain).start_engaged = engaged
	for key in props:
		c.config.set(key, props[key])
	c.global_position = pos
	h.root.add_child(c)
	c.set_physics_process(false)  # hand-ticked
	return c


func _tick(c: Carrier, delta: float = DT) -> void:
	var before := c.global_position
	c._physics_process(delta)
	c.global_position = before + c.velocity * delta


func _brain(c: Carrier) -> CarrierBrain:
	return c.get_node("Brain") as CarrierBrain


func _mover(c: Carrier) -> EnemyMover:
	return c.get_node("EnemyMover") as EnemyMover


func _part(c: Node, part_name: String) -> EnemyModule:
	return c.get_node("Modules/" + part_name) as EnemyModule


func _core(c: Carrier) -> EnemyModule:
	return _part(c, "Core")


func _hp(part: EnemyModule) -> int:
	return part.health.current_health


func _nose(c: Node2D) -> Vector2:
	return Vector2.DOWN.rotated(c.rotation)


func _port(c: Node2D) -> Vector2:
	return Vector2.RIGHT.rotated(c.rotation)


## Counts emissions of a signal with up to two arguments.
func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


## Counts emissions of a one-int signal carrying exactly [param amount].
func _count_damage(sig: Signal, amount: int) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(d: int) -> void:
		if d == amount:
			n[0] += 1)
	return n


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A real player bullet launched at [param target] from [param shot] px away along [param from_dir], nose toward it, whose `range_px` ends its
## flight [param beyond] px past the target. The returned record's `consumed` is set when it expires: true on a hit (it had range left), false at
## its range (it flew on). Its screen notifier is removed, so leaving the headless view never ends it early.
func _shoot(target: Vector2, from_dir: Vector2, beyond: float, shot: float = SHOT) -> Dictionary:
	var b := BULLET_SCENE.instantiate() as Bullet
	var notifier := b.get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier != null:
		b.remove_child(notifier)
		notifier.free()
	b.range_px = shot + beyond
	var rec := {"done": false, "consumed": false}
	var on_expired := func() -> void:
		rec["done"] = true
		rec["consumed"] = b._traveled < b.range_px
	b.expired.connect(on_expired)
	b.expired.connect(b.queue_free)
	_roots[0].add_child(b)
	b.global_position = target + from_dir * shot
	b.rotation = Vector2.UP.angle_to(-from_dir)
	return rec


## Drives a real `BeamBehavior` from `_physics_process` (the `test_enemy_module.gd` driver).
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []

	func _physics_process(delta: float) -> void:
		if behavior != null:
			behavior.tick(self, mode, muzzles, delta)


## A beam driver at [param from] firing along [param dir].
func _beam(from: Vector2, dir: Vector2) -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	_roots[0].add_child(d)
	d.global_position = from
	d.rotation = Vector2.UP.angle_to(dir)
	return d


func _stop_beams(beams: Array) -> void:
	for d: BeamDriver in beams:
		d.behavior = null
		d.queue_free()


## One map-wide nova from the harness player (its flash layer freed at once).
func _nova(h) -> void:
	var before := get_tree().root.get_children()
	assert_true(PlasmaNovaModule.new().try_activate(h.player), "the nova fires")
	for child in get_tree().root.get_children():
		if child not in before:
			child.free()


## R2-1: every live, open part except the core back to full HP (the novas and beam burns are test wear, not the subject of a window).
func _restore_open_parts(cars: Array) -> void:
	for c: Carrier in cars:
		for part in c.modular_hull().modules():
			if part.role != Role.CORE and not part.is_destroyed() and part.is_vulnerable():
				part.health.set_health(part.max_health)


## Each part hurtbox's x extent relative to the hull centre (from its shape's corners, so a moved part or a changed shape shows): the parts whose
## extent passes [param extent].
func _x_extent_violations(c: Carrier, extent: float) -> Array:
	var out: Array = []
	for part in c.modular_hull().modules():
		var cs := part.hurt_box.get_node("CollisionShape2D") as CollisionShape2D
		var rect := cs.shape as RectangleShape2D
		var half := rect.size * 0.5
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			var local_x := c.to_local(cs.global_transform * corner).x
			if absf(local_x) > extent + 0.001:
				out.append(part.module_id)
				break
	return out


## The set of parts whose `Sprite` shows its wreck texture (the silhouette, review finding 4).
func _wrecked_sprites(c: Carrier) -> Array:
	var out: Array = []
	for part in c.modular_hull().modules():
		if part.sprite.texture == part.wreck_texture:
			out.append(part.module_id)
	return out


# ══ A. Real physics ═════════════════════════════════════════════════════════════════════════════

## One locked-core window on every carrier of [param cars] (rows A1, A2): a bullet up into each core flies on with the core's HP unchanged, the beam
## held on each hull centre for 2 s pings the core and is refused by the root, and a nova pings each core and is refused by each root exactly once.
func _locked_core_window(h, cars: Array, count: int, label: String) -> void:
	for c: Carrier in cars:
		assert_eq(c.modular_hull().destroyed_count(Carrier.OUTER_ROLES), count, "%s: %d outer parts down" % [label, count])
	var hp: Array = cars.map(func(c: Carrier) -> int: return _hp(_core(c)))
	var pings: Array = cars.map(func(c: Carrier) -> Array[int]: return _count(_core(c).deflected))
	var armor: Array = cars.map(func(c: Carrier) -> Array[int]: return _count(c.armor_deflected))
	var shots: Array = cars.map(func(c: Carrier) -> Dictionary: return _shoot(_core(c).global_position, Vector2.DOWN, 60.0))
	var beams: Array = cars.map(func(c: Carrier) -> BeamDriver: return _beam(c.global_position + Vector2(0.0, 300.0), Vector2.UP))
	await _frames(BEAM_FRAMES)
	_stop_beams(beams)
	for i in cars.size():
		var c: Carrier = cars[i]
		assert_true(shots[i]["done"] and not shots[i]["consumed"], "%s carrier %d: a bullet at the plated core flies on" % [label, i])
		assert_eq(_hp(_core(c)), hp[i], "%s carrier %d: the core takes nothing from bullet or beam" % [label, i])
		assert_gt(pings[i][0], 1, "%s carrier %d: the core pings (bullet and beam)" % [label, i])
		assert_gt(armor[i][0], 1, "%s carrier %d: the hull refuses bullet and beam (armor_deflected)" % [label, i])
		assert_false(_core(c).is_vulnerable(), "%s carrier %d: still plated" % [label, i])
		assert_false(c.is_core_exposed(), "%s carrier %d: not exposed" % [label, i])
	var pings_before: Array = pings.map(func(n: Array[int]) -> int: return n[0])
	var armor_before: Array = armor.map(func(n: Array[int]) -> int: return n[0])
	_nova(h)
	for i in cars.size():
		var c: Carrier = cars[i]
		assert_eq(_hp(_core(c)), hp[i], "%s carrier %d: the nova leaves the plated core unchanged" % [label, i])
		assert_eq(pings[i][0], pings_before[i] + 1, "%s carrier %d: the nova pings the core once" % [label, i])
		assert_eq(armor[i][0], armor_before[i] + 1, "%s carrier %d: the hull refuses the nova once" % [label, i])
		assert_eq(c.health.current_health, SHIPPED.max_health, "%s carrier %d: the hull bar never moves" % [label, i])
	_restore_open_parts(cars)


func test_the_hull_refuses_and_the_core_opens_only_after_three_parts() -> void:
	_scale_clock()
	var h = _world("open_space")
	var a := _spawn(h, Vector2(300.0, ROW_Y))
	var b := _spawn(h, Vector2(900.0, ROW_Y))
	var c := _spawn(h, Vector2(1500.0, ROW_Y))
	var cars: Array = [a, b, c]
	assert_eq(SHIPPED.core_exposure_count, 3, "the shipped exposure count (read, never typed in a row)")

	# A1 extras, count 0: a bullet at bare hull (local (0, 100): inside the body, clear of every part; its range ends at local y 60, short of the core)
	# on every carrier, and a bullet and a beam along local y -56 from outboard on carrier A's closed hangars.
	var bare: Array = cars.map(func(k: Carrier) -> Dictionary: return _shoot(k.global_position + Vector2(0.0, 100.0), Vector2.DOWN, 40.0))
	var bare_hits: Array = cars.map(func(k: Carrier) -> Array[int]: return _count_damage(k.armor_deflected, BULLET_DAMAGE))
	var hangar := _part(a, "HangarPort")
	var hangar_pings := _count(hangar.deflected)
	var hangar_shot := _shoot(hangar.global_position, Vector2.RIGHT, 170.0, 300.0)
	var hangar_beam := _beam(hangar.global_position + Vector2(300.0, 0.0), Vector2.LEFT)
	await _locked_core_window(h, cars, 0, "count 0")
	_stop_beams([hangar_beam])
	for i in cars.size():
		assert_true(bare[i]["done"] and not bare[i]["consumed"], "carrier %d: a bullet at bare hull flies on" % i)
		assert_gte(bare_hits[i][0], 3, "carrier %d: the hull reports the refused bare-hull bullet, core bullet and nova (50 each)" % i)
	assert_true(hangar_shot["done"] and not hangar_shot["consumed"], "a bullet at a closed hangar flies on")
	assert_eq(_hp(hangar), 220, "a closed hangar takes nothing from bullet, beam or nova")
	assert_eq(_hp(_part(a, "HangarStarboard")), 220, "nor does the other one on the same line")
	assert_gt(hangar_pings[0], 2, "the closed hangar pings (bullet, beam, nova)")

	# A2: one, then two outer parts down, in the epic's three combinations.
	_part(a, "EnginePort").destroy()
	_part(b, "GunPort").destroy()
	_part(c, "EnginePort").destroy()
	await _frames(1)
	await _locked_core_window(h, cars, 1, "count 1")
	_part(a, "EngineStarboard").destroy()
	_part(b, "HangarPort").destroy()
	_part(c, "GunStarboard").destroy()
	await _frames(1)
	await _locked_core_window(h, cars, 2, "count 2")

	# A3: the third part. A and B by scripted destroy() at idle time; C's GunPort (160 HP) killed by four real bullets fired together, inside a
	# physics flush. A fourth carrier with a private exposure count of 4 has its core still plated after the same three losses (A5 boundary).
	var at_kill: Array = []
	var gun_c := _part(c, "GunPort")
	gun_c.destroyed.connect(func(_m: EnemyModule) -> void: at_kill.append([_core(c).is_vulnerable(), c.is_core_exposed()]))
	assert_eq(_hp(gun_c), 160, "R2-1: the gun is at full HP when the volley arrives")
	var volley: Array = []
	for i in 4:
		volley.append(_shoot(gun_c.global_position, Vector2.DOWN, 10.0))
	var d := _spawn(h, Vector2(2100.0, ROW_Y), {"core_exposure_count": 4})
	for part_name in ["EnginePort", "EngineStarboard", "GunPort"]:
		_part(d, part_name).destroy()
	_part(a, "GunPort").destroy()
	_part(b, "HangarStarboard").destroy()
	for i in 30:
		await get_tree().physics_frame
		if gun_c.is_destroyed():
			break
	assert_true(gun_c.is_destroyed(), "four 50-damage bullets kill the 160 HP gun")
	assert_eq(volley.filter(func(r: Dictionary) -> bool: return r["done"] and r["consumed"]).size(), 4, "all four bullets are consumed")
	assert_eq(at_kill, [[false, true]], "R2-2: in the kill's own call the core is still plated, the carrier already exposed")
	await _frames(1)
	for k: Carrier in cars:
		assert_true(k.is_core_exposed(), "exposed after the third loss")
		assert_true(_core(k).is_vulnerable(), "from the next physics frame the core is open")
		assert_eq(_core(k).sprite.texture, k.core_open_texture, "and its plating art is open (review finding 4)")
		assert_eq(k.modular_hull().destroyed_count(Carrier.OUTER_ROLES), 3)
	assert_false(d.is_core_exposed(), "boundary: an exposure count of 4 keeps the core shut after three losses")
	assert_false(_core(d).is_vulnerable(), "boundary: still plated")
	_restore_open_parts(cars)

	# A4: after exposure a bullet is consumed and costs 50, the beam burns, a nova costs exactly 50; the hull bar never moves.
	var hp: Array = cars.map(func(k: Carrier) -> int: return _hp(_core(k)))
	var shots: Array = cars.map(func(k: Carrier) -> Dictionary: return _shoot(_core(k).global_position, Vector2.DOWN, 60.0))
	await _frames(20)
	for i in cars.size():
		assert_true(shots[i]["done"] and shots[i]["consumed"], "carrier %d: the open core consumes the bullet" % i)
		assert_eq(_hp(_core(cars[i])), hp[i] - BULLET_DAMAGE, "carrier %d: and takes its 50" % i)
	hp = cars.map(func(k: Carrier) -> int: return _hp(_core(k)))
	var beams: Array = cars.map(func(k: Carrier) -> BeamDriver: return _beam(k.global_position + Vector2(0.0, 300.0), Vector2.UP))
	await _frames(BEAM_FRAMES)
	_stop_beams(beams)
	for i in cars.size():
		assert_lt(_hp(_core(cars[i])), hp[i], "carrier %d: the beam burns the open core" % i)
	hp = cars.map(func(k: Carrier) -> int: return _hp(_core(k)))
	_nova(h)
	for i in cars.size():
		var k: Carrier = cars[i]
		assert_eq(_hp(_core(k)), hp[i] - NOVA_DAMAGE, "carrier %d: a nova costs the open core exactly 50" % i)
		assert_eq(k.health.current_health, SHIPPED.max_health, "carrier %d: the hull bar is untouched (core hull_share 0)" % i)
		assert_false(k.is_queued_for_deletion(), "carrier %d: alive" % i)


## A6: touching the hull deals the config's 15 to the real player and shoves it once at 220 px/s away from the hull centre; the carrier takes
## nothing.
func test_touching_the_hull_shoves_the_player_and_deals_15(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var c := _spawn(h, Vector2(640.0, 300.0))
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	h.root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	player.global_position = c.global_position + Vector2(0.0, c.body_size().y * 0.5 - 4.0)  # 4 px inside the hull's lower edge
	player.velocity = Vector2.ZERO
	var received: Array[int] = []
	(player.get_node("HurtBox") as HurtBox).received_damage.connect(func(damage: int) -> void: received.append(damage))
	await _frames(4)
	assert_eq(received, [SHIPPED.collision_damage] as Array[int], "%s: one touch for the config's 15" % mode)
	assert_eq(SHIPPED.collision_damage, 15)
	var shove: Vector2 = player.velocity if mode == "open_space" else player.get("_knockback")
	assert_almost_eq(shove.length(), 220.0, 0.01, "%s: one 220 px/s shove" % mode)
	assert_gt(shove.normalized().dot(Vector2.DOWN), 0.99, "%s: away from the hull centre" % mode)
	if mode == "assault":
		assert_true(player.is_knockback_active(), "assault: the fighter's knockback runs")
	assert_eq(c.health.current_health, SHIPPED.max_health, "%s: the touch never hurts the carrier" % mode)


# ══ B. Hand-ticked ══════════════════════════════════════════════════════════════════════════════

## 7. Structure.
func test_seven_parts_as_authored_within_the_module_x_extent(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var c := _spawn(h, Vector2(640.0, 100.0))
	var parts := c.modular_hull().modules()
	assert_eq(parts.size(), PARTS.size(), "%s: seven parts" % mode)
	for i in mini(parts.size(), PARTS.size()):
		var row: Array = PARTS[i]
		var part := parts[i]
		assert_eq([String(part.name), part.module_id, part.role, part.max_health, part.is_vulnerable(), part.hull_share],
				[row[0], row[1], row[2], row[3], row[4], 0.0], "%s: %s as authored" % [mode, row[0]])
		assert_eq(part.get_parent().name, &"Modules", "%s: under Modules" % mode)
	assert_eq(c.contact_hit_box.damage, SHIPPED.collision_damage, "%s: contact 15" % mode)
	assert_eq([c.contact_profile.mode, c.contact_profile.shove_speed], [ContactProfile.Mode.ARMOR, 220.0], "%s: ARMOR, 220" % mode)
	assert_eq(SHIPPED.module_x_extent, 100.0)
	assert_eq(_x_extent_violations(c, SHIPPED.module_x_extent), [], "%s: every part within x +-module_x_extent" % mode)
	assert_true(c.deflects_hit(null) and c.is_armored(), "%s: the hull is armour" % mode)
	assert_false(c.is_laser_blocking(), "%s: the beam passes over it" % mode)
	assert_false(c.can_be_repaired() or c.accepts_ward() or c.accept_tow(Vector2(50.0, 0.0)), "%s: never repaired, warded or towed" % mode)
	assert_almost_eq(c.rocket_clear_radius(), c.body_size().length() * 0.5 + 4.0, 0.001)

	# homing_point (R2-3): from just nose-ward of the core, the nearer gun while the core is plated (tree order breaks the tie), the core once open.
	var probe := c.global_position + Vector2(0.0, 20.0)
	assert_eq(c.homing_point(probe), _part(c, "GunPort").global_position, "%s: a plated core is never the homing point" % mode)
	for part_name in ["EnginePort", "EngineStarboard", "HangarStarboard"]:
		_part(c, part_name).destroy()
	await get_tree().process_frame  # the deferred unplating
	assert_true(_core(c).is_vulnerable())
	assert_eq(c.homing_point(probe), _core(c).global_position, "%s: the open core is" % mode)

	# Boundary: the same check reports a part moved to x 120.
	var moved := SCENE.instantiate() as Carrier
	_part(moved, "GunPort").position.x = 120.0
	h.root.add_child(moved)
	moved.set_physics_process(false)
	assert_eq(_x_extent_violations(moved, SHIPPED.module_x_extent), [&"gun_port"], "%s: boundary: a part past the extent is reported" % mode)


## 8. Config and builder.
func test_the_config_the_builder_and_the_phase_order() -> void:
	var expected := {
		"max_health": 600, "collision_damage": 15, "score_value": 600, "counts_as_escape": true, "hazard_avoidance": 0.5, "hazard_margin": 120.0,
		"hazard_resistance": 1.0, "wreck_chance": 0.0, "max_speed": 70.0, "acceleration": 40.0, "braking": 40.0, "max_turn_rate": 0.35,
		"one_engine_turn": 0.5, "no_engine_turn": 0.15, "one_engine_speed": 0.8, "no_engine_speed": 0.4, "list_rate": 0.06, "list_hold_deg": 10.0,
		"screen_range_min": 600.0, "screen_range_max": 950.0, "leash_radius": 900.0, "core_exposure_count": 3, "assault_cross_speed": 90.0,
		"assault_max_speed": 110.0, "assault_sway_speed": 30.0, "one_engine_sway": 0.5, "no_engine_sway": 0.1, "assault_sway_leash": 30.0,
		"module_x_extent": 100.0, "perceive_radius": 1100.0, "lose_radius": 1800.0, "notice_time": 0.6, "idle_radius": 220.0, "idle_speed": 0.12,
	}
	for key in expected:
		assert_eq(SHIPPED.get(key), expected[key], "carrier_config.tres %s" % key)
	assert_eq(WaveBuilder.CARRIER, "res://assault/scenes/enemies/carrier/carrier.tscn")
	var spawn := WaveBuilder.new().carrier()
	assert_not_null(spawn, "carrier() builds a spawn config")
	var probe := (load(WaveBuilder.CARRIER) as PackedScene).instantiate()
	assert_true(probe is Carrier, "CARRIER loads a Carrier")
	probe.free()
	assert_eq(Phase.keys(), ["CRUISE", "SCREEN", "PANIC", "CROSS", "IDLE", "NOTICING", "RETURNING"], "the append-only phase order")
	var c := SCENE.instantiate() as Carrier
	assert_true(c.world_anchored_x, "a wave spawn is world-anchored by default")
	c.free()


## 9. Core death kills the carrier; R2-4: a core killed in the same call as the third loss keeps its wreck texture.
func test_the_cores_death_is_the_carriers(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var c := _spawn(h, Vector2(640.0, 100.0))
	watch_signals(c)
	_core(c).destroy()
	assert_signal_emit_count(c, "died", 1, "%s: died once" % mode)
	assert_true(c.was_killed, "%s: was_killed" % mode)
	assert_true(c.is_queued_for_deletion(), "%s: freed with its core" % mode)
	assert_eq(_core(c).sprite.texture, _core(c).wreck_texture, "%s: the core shows its wreck" % mode)

	var c2 := _spawn(h, Vector2(640.0, 400.0))
	var core := _core(c2)
	var textures: Array = []
	core.sprite.texture_changed.connect(func() -> void: textures.append(core.sprite.texture))
	for part_name in ["EnginePort", "GunPort", "HangarPort"]:
		_part(c2, part_name).destroy()
	core.destroy()
	assert_true(c2.is_queued_for_deletion(), "%s: killed in the same call" % mode)
	c2._open_core_plating()
	assert_eq(core.sprite.texture, core.wreck_texture, "%s: unplating a destroyed core keeps its wreck" % mode)
	var open_texture := c2.core_open_texture
	var wreck_texture := core.wreck_texture
	await get_tree().process_frame  # the pending deferred unplating runs (or is dropped with the freed carrier)
	var wreck_at := textures.find(wreck_texture)
	assert_gt(wreck_at, -1, "%s: the wreck texture was shown" % mode)
	assert_false(textures.slice(wreck_at + 1).has(open_texture), "%s: the open plating never replaced the wreck" % mode)


## 10. Engine loss slows turning and lists (Open Space; Assault's half is row 16's sway caps). Still player 760 px below the nose: the broadside
## turn is 90 degrees either way.
func _turn_time(dead: Array) -> float:
	var h = _world("open_space")
	var c := _spawn(h, Vector2(0.0, -760.0))
	for part_name in dead:
		_part(c, part_name).destroy()
	for i in 2400:
		_tick(c)
		var bearing: Vector2 = (h.player.global_position - c.global_position).normalized()
		if absf(absf(_nose(c).angle_to(bearing)) - PI / 2.0) <= 0.02:
			return (i + 1) * DT
	return INF


## Settles broadside with both engines, then destroys [param dead] (or nothing) and returns [rotation drift over 2 s, the gain of the nose along
## the dead side's direction, the carrier].
func _list_run(dead: String) -> Array:
	var h = _world("open_space")
	var c := _spawn(h, Vector2(0.0, -760.0))
	for i in 360:
		_tick(c)
	var side := Vector2.ZERO
	if dead != "":
		_part(c, dead).destroy()
		side = _port(c) if dead == "EnginePort" else -_port(c)
	var r0 := c.rotation
	var nose0 := _nose(c)
	for i in 120:
		_tick(c)
	return [absf(angle_difference(r0, c.rotation)), _nose(c).dot(side) - nose0.dot(side), c]


func test_engine_loss_slows_the_turn_and_one_engine_lists() -> void:
	var t2 := _turn_time([])
	var t1 := _turn_time(["EnginePort"])
	var t0 := _turn_time(["EnginePort", "EngineStarboard"])
	gut.p("broadside turn: %.2f / %.2f / %.2f s with 2 / 1 / 0 engines" % [t2, t1, t0])
	assert_lt(t2, 6.0, "both engines turn 90 degrees in about 4.5 s")
	assert_gte(t1, 1.8 * t2, "one engine lost: >= 1.8 t")
	assert_gte(t0, 5.0 * t2, "both lost: >= 5 t")

	var control: Array = _list_run("")
	assert_lt(control[0], 0.01, "control: with both engines the held heading stays put")
	var port: Array = _list_run("EnginePort")
	assert_gte(port[0], 0.10, "port engine lost: the heading drifts >= 0.05 rad/s with no turn request")
	assert_gt(port[1], 0.0, "toward port")
	var c: Carrier = port[2]
	assert_false((_part(c, "EnginePort").get_node("Light") as CanvasItem).visible, "the dead engine's plume is out")
	assert_true((_part(c, "EngineStarboard").get_node("Light") as CanvasItem).visible, "the live one burns on")
	var starboard: Array = _list_run("EngineStarboard")
	assert_gte(starboard[0], 0.10, "starboard engine lost: it drifts too")
	assert_gt(starboard[1], 0.0, "toward starboard")


## 11. Facing (Open Space): a live battery side to the player, the starboard side with the port gun dead, the bow with both dead.
func test_it_turns_a_live_battery_to_the_player_and_the_bow_with_none() -> void:
	var cases := [[[], "battery"], [["GunPort"], "starboard"], [["GunPort", "GunStarboard"], "bow"]]
	for row in cases:
		var h = _world("open_space")
		var c := _spawn(h, Vector2(0.0, -760.0))
		c.rotation = 1.0
		for part_name in row[0]:
			_part(c, part_name).destroy()
		for i in 480:
			_tick(c)
		var bearing: Vector2 = (h.player.global_position - c.global_position).normalized()
		var tol := deg_to_rad(20.0)
		match row[1]:
			"battery":
				assert_true(absf(_port(c).angle_to(bearing)) <= tol or absf((-_port(c)).angle_to(bearing)) <= tol, "both batteries: a side to the player")
			"starboard":
				assert_lt(absf((-_port(c)).angle_to(bearing)), tol, "port gun dead: the starboard side to the player")
			"bow":
				assert_lt(absf(_nose(c).angle_to(bearing)), tol, "no gun: the bow to the player")


## 12. SCREEN (Open Space).
func test_screen_holds_the_band_and_the_leash() -> void:
	# A still player inside the band is never closed on.
	var h = _world("open_space")
	var c := _spawn(h, Vector2(0.0, -760.0))
	var closest := INF
	for i in 1200:
		_tick(c)
		closest = minf(closest, c.global_position.distance_to(h.player.global_position))
	assert_eq(_brain(c).phase, Phase.SCREEN)
	assert_gte(closest, SHIPPED.screen_range_min, "a still player 760 px away: never closer than 600")

	# A player 450 px away: it opens to the band within 20 s and never closes in again.
	h = _world("open_space")
	c = _spawn(h, Vector2(0.0, -450.0))
	var reached := -1
	var after := INF
	for i in 1200:
		_tick(c)
		var dist := c.global_position.distance_to(h.player.global_position)
		if reached < 0 and dist >= SHIPPED.screen_range_min:
			reached = i
		elif reached >= 0:
			after = minf(after, dist)
	assert_gt(reached, -1, "opens to >= 600 within 20 s")
	assert_gte(after, SHIPPED.screen_range_min, "and never closes in after")

	# A player fleeing from the anchor at 120 px/s for 30 s: the leash holds.
	h = _world("open_space")
	c = _spawn(h, Vector2(0.0, -760.0))
	var anchor := c.global_position
	var furthest := 0.0
	for i in 1800:
		h.player.global_position += Vector2(0.0, 120.0 * DT)
		_tick(c)
		furthest = maxf(furthest, c.global_position.distance_to(anchor))
	gut.p("screen leash: furthest %.1f px from the anchor" % furthest)
	assert_gt(furthest, 100.0, "sanity: it followed")
	assert_lte(furthest, SHIPPED.leash_radius + 50.0, "never more than leash + 50 from its anchor")


## 13. PANIC (Open Space): core exposed with the engines alive (GunPort, GunStarboard, HangarPort down).
func test_panic_backs_away_inside_the_leash() -> void:
	# (a) A still player 500 px east of the anchor: the hull ends on the far side of its anchor, on the leash circle.
	var h = _world("open_space")
	var c := _spawn(h, Vector2(0.0, -760.0))
	var anchor := c.global_position
	h.player.global_position = anchor + Vector2(500.0, 0.0)
	for part_name in ["GunPort", "GunStarboard", "HangarPort"]:
		_part(c, part_name).destroy()
	var furthest := 0.0
	for i in 1800:
		_tick(c)
		furthest = maxf(furthest, c.global_position.distance_to(anchor))
	assert_eq(_brain(c).phase, Phase.PANIC, "the exposed core panics it")
	assert_lt(c.global_position.distance_to(anchor - Vector2(SHIPPED.leash_radius, 0.0)), 60.0, "on the far side of its anchor, on the leash")
	assert_lte(furthest, SHIPPED.leash_radius + 50.0, "never beyond leash + 50")

	# (b) A player chasing the hull at 120 px/s for 30 s: the leash still wins.
	h = _world("open_space")
	c = _spawn(h, Vector2(0.0, -760.0))
	anchor = c.global_position
	h.player.global_position = anchor + Vector2(400.0, 300.0)
	for part_name in ["GunPort", "GunStarboard", "HangarPort"]:
		_part(c, part_name).destroy()
	furthest = 0.0
	for i in 1800:
		var chase: Vector2 = c.global_position - h.player.global_position
		if chase.length() > 1.0:
			h.player.global_position += chase.normalized() * 120.0 * DT
		_tick(c)
		furthest = maxf(furthest, c.global_position.distance_to(anchor))
	assert_eq(_brain(c).phase, Phase.PANIC)
	assert_lte(furthest, SHIPPED.leash_radius + 50.0, "chased, never beyond leash + 50")


## 14. Wreckage stays and the silhouette changes with each loss; the third loss opens the core's plating.
func test_four_wrecks_stay_until_the_carrier_dies(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var c := _spawn(h, Vector2(640.0, -100.0))
	var modules := c.get_node("Modules")
	var schedule := {0: "EnginePort", 150: "GunPort", 300: "HangarStarboard", 450: "EngineStarboard"}
	var lost: Array = []
	for i in 600:
		if schedule.has(i):
			var part := _part(c, schedule[i])
			part.destroy()
			lost.append(part.module_id)
			var shown := _wrecked_sprites(c)
			shown.sort()
			var want := lost.duplicate()
			want.sort()
			assert_eq(shown, want, "%s: the silhouette changes by exactly %s" % [mode, part.module_id])
			if lost.size() == 3:
				await get_tree().process_frame  # the deferred unplating
				assert_eq(_core(c).sprite.texture, c.core_open_texture, "%s: the third loss opens the core's plating" % mode)
		_tick(c)
	for part_name in schedule.values():
		var part := _part(c, part_name)
		assert_eq(part.get_parent(), modules, "%s: %s is still on the hull at 10 s" % [mode, part_name])
		assert_eq(part.visual_state(), EnemyModule.VisualState.WRECK)
		assert_eq(part.sprite.texture, part.wreck_texture)
	assert_false(c.is_queued_for_deletion(), "%s: alive with four wrecks" % mode)
	_core(c).destroy()
	assert_true(c.is_queued_for_deletion(), "%s: the wrecks go with the hull" % mode)


## 15. Assault CROSS: a constant 90 px/s straight down, never rotated, through every engine count, PANIC with both engines then lost, a slow field,
## a 5 s EMP and a second EMP inside the first. One world, one carrier per variant, 900 px apart; ticked together.
func test_the_assault_crossing_holds_90_px_s_through_everything() -> void:
	var h = _world("assault")
	var labels := ["both engines", "one engine", "no engine", "panic then no engine", "slow field", "one EMP", "two EMPs"]
	var cars: Array[Carrier] = []
	for k in labels.size():
		cars.append(_spawn(h, Vector2(640.0 + 900.0 * (k - 3), -300.0)))
	_part(cars[1], "EnginePort").destroy()
	for part_name in ["EnginePort", "EngineStarboard"]:
		_part(cars[2], part_name).destroy()
	for part_name in ["GunPort", "GunStarboard", "HangarPort"]:
		_part(cars[3], part_name).destroy()
	var field := HazardField.new()
	field.kind = &"gravity_field"
	field.radius = 400.0
	field.movement_penalty = 0.6
	add_child_autofree(field)
	field.global_position = cars[4].global_position + Vector2(0.0, 270.0)
	var worst: Array = []
	var turned: Array = []
	worst.resize(cars.size())
	worst.fill(0.0)
	turned.resize(cars.size())
	turned.fill(0.0)
	var in_field := 0
	for i in 540:  # 9 s: the second EMP's window ends at 8 s
		if i == 1:
			cars[5].apply_emp(5.0, null)
			cars[6].apply_emp(5.0, null)
		if i == 60:
			for part_name in ["EnginePort", "EngineStarboard"]:
				_part(cars[3], part_name).destroy()
		if i == 181:
			cars[6].apply_emp(5.0, null)
			assert_almost_eq(cars[6].emp_seconds_left(), 5.0, 0.0001, "the second EMP extends the window to 8 s")
		if Hazards.penalty_at(cars[4].global_position) > 0.0:
			in_field += 1
		for k in cars.size():
			var y0 := cars[k].global_position.y
			_tick(cars[k])
			worst[k] = maxf(worst[k], absf((cars[k].global_position.y - y0) / DT - SHIPPED.assault_cross_speed))
			turned[k] = maxf(turned[k], absf(cars[k].rotation))
		if i == 120:
			assert_true(cars[5].is_emp_disrupted() and cars[6].is_emp_disrupted(), "sanity: both EMP windows run at 2 s")
		if i == 420:
			assert_false(cars[5].is_emp_disrupted(), "sanity: the single EMP is over by 7 s")
			assert_true(cars[6].is_emp_disrupted(), "sanity: the refreshed one still runs at 7 s")
	assert_gt(in_field, 400, "sanity: the slow carrier crossed inside the field")
	for k in cars.size():
		assert_lte(worst[k], 1.0, "%s: every tick at 90 +-1 px/s" % labels[k])
		assert_almost_eq(turned[k], 0.0, 0.000001, "%s: never rotated" % labels[k])
		assert_eq(_brain(cars[k]).phase, Phase.PANIC if k == 3 else Phase.CROSS, "%s: phase" % labels[k])
		assert_eq([_mover(cars[k]).hazard_avoidance, _mover(cars[k]).acceleration, _mover(cars[k]).max_speed], [0.0, 0.0, SHIPPED.assault_max_speed],
				"%s: the crossing's mover limits in every phase" % labels[k])
	assert_eq(cars[0].config.hazard_avoidance, 0.5, "the config's own avoidance is 0.5")


## 16. Sway: leashed to +-30 px of the anchored spawn x with the player held at either view edge for a whole crossing; capped 30 / 15 / 3 px/s.
func test_the_sway_stays_on_its_leash_and_is_capped_by_the_engines() -> void:
	for edge in [0.0, 1280.0]:
		var h = _world("assault")
		h.player.global_position = Vector2(edge, ASSAULT_PLAYER.y)
		var c := _spawn(h, Vector2(640.0, 360.0 - 260.0 * ArenaCamera.WORLD_SCALE))  # design y -260 at the resting view
		var anchor_x := c.global_position.x
		var widest := 0.0
		var ticks := 0
		while not c.is_queued_for_deletion() and ticks < 1500:
			_tick(c)
			ticks += 1
			widest = maxf(widest, absf(c.global_position.x - anchor_x))
		assert_eq(_brain(c).anchor_x(), anchor_x, "the sway's leash centre is the spawn x")
		assert_true(c.is_queued_for_deletion(), "player at x %d: the crossing ends below the rect" % edge)
		assert_lte(widest, SHIPPED.assault_sway_leash + 0.001, "player at x %d: x never leaves spawn x +-30" % edge)

	# Caps: the player straight below (outside both 65 degree arcs), one carrier per engine count stacked on x 640.
	var h = _world("assault")
	var cars: Array[Carrier] = []
	for k in 3:
		cars.append(_spawn(h, Vector2(640.0, -100.0 + 100.0 * k)))
	_part(cars[1], "EnginePort").destroy()
	for part_name in ["EnginePort", "EngineStarboard"]:
		_part(cars[2], part_name).destroy()
	var fastest := [0.0, 0.0, 0.0]
	for i in 60:
		for k in 3:
			_tick(cars[k])
			fastest[k] = maxf(fastest[k], absf(cars[k].velocity.x))
	assert_almost_eq(fastest[0], 30.0, 0.01, "two engines: 30 px/s")
	assert_almost_eq(fastest[1], 15.0, 0.01, "one engine: 15 px/s")
	assert_almost_eq(fastest[2], 3.0, 0.01, "none: 3 px/s")
	# The arc line it steers for lies 336 px off (beyond the leash): the leash binds, so it settles on spawn x +-30 and never passes it.
	var widest := 0.0
	for i in 180:
		_tick(cars[0])
		widest = maxf(widest, absf(cars[0].global_position.x - 640.0))
	assert_lte(widest, SHIPPED.assault_sway_leash + 0.001, "a target beyond the leash: x never leaves spawn x +-30")
	assert_almost_eq(absf(cars[0].global_position.x - 640.0), SHIPPED.assault_sway_leash, 0.5, "it settles on a leash edge (the two arc lines tie; either side covers)")

	# World-anchored x: with the view panned 100 px right, a spawn at x 700 lands at world x 600; un-anchored it stays.
	for anchored in [true, false]:
		var hw = _world("assault")
		var cam := hw.root.get_node("ArenaCamera") as ArenaCamera
		cam.offset = Vector2(100.0, 0.0)
		var c := SCENE.instantiate() as Carrier
		c.world_anchored_x = anchored
		c.global_position = Vector2(700.0, 0.0)
		hw.root.add_child(c)
		c.set_physics_process(false)
		assert_almost_eq(c.global_position.x, 600.0 if anchored else 700.0, 0.001, "world_anchored_x %s" % anchored)


## 17. Freed below the projectile rect on the first tick its top edge passes it, and an EMP window does not delay it: two carriers from the same
## y, the second EMP'd 1 s before that tick. Ticked inside real physics frames at the 16x clock, because the free check reads the position
## `move_and_slide()` reached, and outside a physics frame that call moves by the idle frame's delta instead of the 1/60 s step.
func test_it_frees_below_the_projectile_rect_even_inside_an_emp() -> void:
	_scale_clock()
	var h = _world("assault")
	var end_y := EnemyWorld.projectile_world_rect(get_tree()).end.y
	var y0 := end_y + HULL_HALF_HEIGHT - SHIPPED.assault_cross_speed * 2.0 + 0.5  # its top edge passes the rect on the 120th tick
	var a := _spawn(h, Vector2(640.0, y0))
	var b := _spawn(h, Vector2(640.0, y0))
	assert_almost_eq(a.body_size().y * 0.5, HULL_HALF_HEIGHT, 0.001, "sanity: the 280 px hull")
	var freed := {a: -1, b: -1}
	var tops := {a: [], b: []}
	for i in 200:
		await get_tree().physics_frame
		if i == 59:
			b.apply_emp(5.0, null)
		for c: Carrier in [a, b]:
			if freed[c] >= 0:
				continue
			_tick(c)
			tops[c].append(c.global_position.y - HULL_HALF_HEIGHT)
			if c.is_queued_for_deletion():
				freed[c] = i
		if freed[a] >= 0 and freed[b] >= 0:
			break
	var first_past: int = tops[a].find_custom(func(top: float) -> bool: return top > end_y)
	assert_eq(first_past, 119, "sanity: the top edge passes the rect on the 120th tick")
	assert_eq(freed[a], first_past, "freed on the first tick its top edge is below the rect, not one before")
	assert_true(b.is_emp_disrupted(), "sanity: the second one was inside its EMP window when freed")
	assert_eq(freed[b], freed[a], "an EMP window never delays the free")
