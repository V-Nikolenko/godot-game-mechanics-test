## The Carrier's shell: armoured hull, seven parts, core exposure, death through the core and movement in both modes (docs/plans/cmug23oo90029m52wae4clve0/
## 3-plan.md §2.6, §2.7; Phase 10 t6, task plan docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md, whose row numbers the section headers follow; t7 weapons, task
## plan docs/plans/cmwafsrb900ajqs2yb5jcl5ij/3-plan.md, rows W1-W9). Intent tests.
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
## `first_launch_delay` on a row's private config: no scheduled launch inside any row (s).
const HANGARS_QUIET := 1.0e6

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


## A hand-ticked carrier. [param props] are written on its private config copy before it enters the tree. Its hangars keep their doors shut
## (`first_launch_delay` HANGARS_QUIET) and launch nothing (both launch counts 0, so a PANIC row's emergency deployment puts out no ship) unless
## [param props] says otherwise: these rows are about the hull, its movement and its weapons, the hangars have their own file
## (`test_carrier_hangars.gd`), and a launch instantiates two ships (Phase 10 t8, the gate-time rule).
func _spawn(h, pos: Vector2, props: Dictionary = {}, engaged: bool = true) -> Carrier:
	var c := SCENE.instantiate() as Carrier
	(c.get_node("Brain") as CarrierBrain).start_engaged = engaged
	c.config.first_launch_delay = HANGARS_QUIET
	c.config.launch_count = 0
	c.config.assault_launch_count = 0
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
		"pulse_trigger_range": 340.0, "pulse_cooldown": 5.0, "missile_min_range": 450.0, "missile_cooldown": 7.0, "missile_pursuit_chance": 1.0,
		"panic_pulse_factor": 0.5, "panic_battery_factor": 0.7,
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


# ── Weapons (t7, §2.7; task plan docs/plans/cmwafsrb900ajqs2yb5jcl5ij/3-plan.md) ─────────────────────────────────────────────────────────
#
# Every row pins the hull (it writes the row's position, and where it says so its rotation, back after each tick) and re-places the player relative
# to it: unpinned, an Open Space carrier backs out of a close player and an Assault one descends out of the view, so no cooldown could be observed.
# Distances come from the shipped `.tres`. A control stops at its first evidence.

const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const RING_SCENE: PackedScene = preload("res://assault/scenes/enemies/carrier/carrier_pulse_ring.tscn")
const RingPhase := EnergyRing.Phase
const MountPhase := TurretMount.Phase
## Where a pinned weapons row holds the hull: inside the Assault view (the camera's view is y 0 .. 720), and the Open Space origin.
const ASSAULT_PIN := Vector2(640.0, 260.0)
const OPEN_SPACE_PIN := Vector2.ZERO
## The reaction time the ring's warning must cover (`test_energy_ring.gd`'s R).
const REACTION := 0.25
const VICTIM_RADIUS := 14.0
const VICTIM_HP := 1000
## The bow cannon's arc (§2.7), typed here on purpose: a row that read it off the mount would follow a widened arc.
const BOW_ARC_DEG := 70.0


func _pin_at(h) -> Vector2:
	return ASSAULT_PIN if h.is_assault else OPEN_SPACE_PIN


## A hand-ticked carrier pinned at [param at] (spawned there).
func _armed(h, at: Vector2) -> Carrier:
	return _spawn(h, at)


## One tick, then the hull written back to [param at] (and to [param rot] unless NAN).
func _tick_pinned(c: Carrier, at: Vector2, rot: float = NAN) -> void:
	_tick(c)
	c.global_position = at
	if not is_nan(rot):
		c.rotation = rot


func _all_mounts(c: Carrier) -> Array[TurretMount]:
	var out: Array[TurretMount] = []
	out.append_array(c.battery_mounts())
	out.append(c.bow_mount())
	out.append(c.missile_mount())
	return out


func _any_mount_in(c: Carrier, p: int) -> bool:
	for mount in _all_mounts(c):
		if mount.phase() == p:
			return true
	return false


## Every launch of [param mount]: [projectile, muzzle, global direction, the player's position then].
func _launch_log(h, mount: TurretMount) -> Array:
	var log: Array = []
	mount.round_fired.connect(func(p: Node2D) -> void:
		log.append([p, mount.muzzle_position(), Vector2.RIGHT.rotated(mount.global_rotation), h.player.global_position]))
	return log


## Tick indices on which [param ring] entered TELEGRAPH, read through [param clock] (the row's tick counter, `[0]`).
func _ring_starts(ring: EnergyRing, clock: Array[int]) -> Array[int]:
	var starts: Array[int] = []
	ring.phase_changed.connect(func(p: int) -> void:
		if p == RingPhase.TELEGRAPH:
			starts.append(clock[0]))
	return starts


func _hull_light(c: Carrier) -> StateLight:
	return c.get_node("StateLight") as StateLight


func _core_light(c: Carrier) -> StateLight:
	return c.get_node("Modules/Core/Light") as StateLight


func _expose_core(c: Carrier) -> void:
	for part_name in ["EnginePort", "HangarPort", "HangarStarboard"]:
		_part(c, part_name).destroy()


## W1. Module death disables an attack: with `GunPort` dead and the player re-placed every tick 400 px off the carrier's CURRENT port side, no battery
## round is fired in 20 s and no round of any mount leaves toward the port half-plane. Control: both guns alive, the port battery puts a round on the player.
func test_a_dead_port_battery_leaves_the_port_side_safe(mode: String = use_parameters(MODES)) -> void:
	for port_dead in [true, false]:
		var h = _world(mode)
		var at := _pin_at(h)
		var c := _armed(h, at)
		if port_dead:
			_part(c, "GunPort").destroy()
		var logs := {}
		for mount in _all_mounts(c):
			logs[mount] = _launch_log(h, mount)
		var port_log: Array = logs[c.modular_hull().mounts_of(CarrierBrain.GUN_PORT)[0]]
		var on_target := false
		for i in int(20.0 / DT):
			h.player.global_position = c.global_position + _port(c) * 400.0
			_tick_pinned(c, at)
			if not port_dead:
				for rec in port_log:
					var to_player: Vector2 = rec[3] - rec[1]
					var along: float = to_player.dot(rec[2])
					if along > 0.0 and absf(to_player.cross(rec[2])) <= 24.0:
						on_target = true
				if on_target:
					break
		if port_dead:
			var battery_rounds := 0
			for mount in c.battery_mounts():
				battery_rounds += (logs[mount] as Array).size()
			assert_eq(battery_rounds, 0, "%s: no battery round with the port gun dead and the player on the port side" % mode)
			for mount in logs:
				for rec in logs[mount]:
					var local: Vector2 = (rec[2] as Vector2).rotated(-c.rotation)
					assert_lte(local.x, 1e-3, "%s: no round leaves toward the port half-plane" % mode)
		else:
			assert_true(on_target, "%s: control: the live port battery puts a round on the player" % mode)


## W2. The bow heavy cannon fires only inside its 70 degree arc, bearings and range measured from its own pivot: 0 and 30 degrees fire, 40 and -40 do not
## (30 / 40 straddle the 35 degree edge). Every Heavy Shell leaves within 35 degrees + half the fire cone of the nose.
func test_the_bow_cannon_fires_only_inside_its_70_degree_arc(mode: String = use_parameters(MODES)) -> void:
	for bearing in [0.0, 30.0, 40.0, -40.0]:
		var h = _world(mode)
		var at := _pin_at(h)
		var c := _armed(h, at)
		var bow := c.bow_mount()
		var log := _launch_log(h, bow)
		assert_eq(bow.traverse_deg, BOW_ARC_DEG, "%s: the bow mount has the §2.7 70 degree arc" % mode)
		var half_arc := BOW_ARC_DEG * 0.5
		var pivot := bow.global_position
		for i in int(4.0 / DT):
			h.player.global_position = pivot + Vector2.DOWN.rotated(deg_to_rad(bearing)) * 600.0
			_tick_pinned(c, at, 0.0)
			if not log.is_empty() and absf(bearing) < half_arc:
				break
		if absf(bearing) < half_arc:
			assert_gt(log.size(), 0, "%s: the bow fires at a player %.0f degrees off the nose" % [mode, bearing])
		else:
			assert_eq(log.size(), 0, "%s: the bow never fires at a player %.0f degrees off the nose" % [mode, bearing])
		for rec in log:
			assert_true((rec[0] as Node).scene_file_path.ends_with("heavy_shell.tscn"), "%s: the bow fires Heavy Shells" % mode)
			var off := rad_to_deg(absf(Vector2.DOWN.angle_to(rec[2])))
			assert_lte(off, half_arc + bow.fire_cone_deg * 0.5 + 0.01, "%s: a shell leaves inside the arc (%.1f degrees)" % [mode, off])


## W3. The missile bank fires only at a player beyond `missile_min_range` (10 px either side), PURSUIT rockets only, at the configured cooldown.
func test_the_missile_bank_fires_only_beyond_its_min_range(mode: String = use_parameters(MODES)) -> void:
	assert_gt(SHIPPED.missile_min_range - 10.0, SHIPPED.pulse_trigger_range, "precondition: the inside case does not trigger the pulse")
	for dist in [SHIPPED.missile_min_range - 10.0, SHIPPED.missile_min_range + 10.0]:
		var h = _world(mode)
		var at := _pin_at(h)
		var c := _armed(h, at)
		var bank := c.missile_mount()
		assert_eq(bank.cooldown_seconds, SHIPPED.missile_cooldown, "%s: the bank's cooldown is the config's" % mode)
		assert_eq(bank.get(&"pursuit_chance"), SHIPPED.missile_pursuit_chance, "%s: and so is its pursuit chance" % mode)
		var log := _launch_log(h, bank)
		for i in int(8.0 / DT):
			h.player.global_position = at + Vector2.DOWN * dist
			_tick_pinned(c, at, 0.0)
			if not log.is_empty():
				break
		if dist < SHIPPED.missile_min_range:
			assert_eq(log.size(), 0, "%s: no rocket at a player %.0f px off" % [mode, dist])
		else:
			assert_gt(log.size(), 0, "%s: rockets at a player %.0f px off" % [mode, dist])
		for rec in log:
			assert_eq((rec[0] as EnemyRocket).kind, EnemyRocket.Kind.PURSUIT, "%s: a PURSUIT rocket" % mode)
			assert_gt((rec[3] as Vector2).distance_to(at), SHIPPED.missile_min_range, "%s: launched only beyond the min range" % mode)


## W4. The pulse starts on the tick the player comes strictly inside `pulse_trigger_range` (not 10 px outside it), restarts exactly `pulse_cooldown` after
## its start and never earlier, starts again on re-entry once the cooldown has run, and in PANIC every `pulse_cooldown * panic_pulse_factor`. The hull light
## reads CHARGING through every ring telegraph, the PANIC strobe included.
func test_the_pulse_starts_on_approach_and_respects_its_cooldown(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := _pin_at(h)
	var c := _armed(h, at)
	var ring := c.pulse_ring()
	var light := _hull_light(c)
	var clock: Array[int] = [0]
	var starts := _ring_starts(ring, clock)
	# Astern: no gun arc reaches it and it is inside the bank's min range, so only the ring can light CHARGING.
	var outside := at + Vector2.UP * (SHIPPED.pulse_trigger_range + 10.0)
	var inside := at + Vector2.UP * (SHIPPED.pulse_trigger_range - 10.0)
	var cooldown_ticks := ceili(SHIPPED.pulse_cooldown / DT - 1e-3)
	var panic_ticks := ceili(SHIPPED.pulse_cooldown * SHIPPED.panic_pulse_factor / DT - 1e-3)
	var step := func(where: Vector2) -> void:
		h.player.global_position = where
		_tick_pinned(c, at, 0.0)
		if ring.phase() == RingPhase.TELEGRAPH:
			assert_eq(light.get_state(), StateLight.State.CHARGING, "%s: CHARGING through the telegraph (tick %d)" % [mode, clock[0]])
		clock[0] += 1
	for i in 60:
		step.call(outside)
	assert_eq(starts.size(), 0, "%s: 10 px outside the trigger range: no ring" % mode)
	step.call(inside)
	assert_eq(starts, [60] as Array[int], "%s: the ring starts on the tick the player comes inside" % mode)
	while clock[0] < 60 + cooldown_ticks + 10:
		step.call(inside)
	assert_eq(starts.size(), 2, "%s: one restart in the cooldown window" % mode)
	if starts.size() < 2:
		return
	assert_eq(starts[1] - starts[0], cooldown_ticks, "%s: the restart comes exactly one cooldown after the start" % mode)
	var back := starts[1] + cooldown_ticks + 20
	while clock[0] < back:
		step.call(outside if clock[0] >= starts[1] + 30 else inside)
	assert_eq(starts.size(), 2, "%s: out of range: no ring" % mode)
	step.call(inside)
	assert_eq(starts[-1], back, "%s: the ring starts on re-entry once the cooldown has run" % mode)
	_expose_core(c)
	var first_panic := -1
	var guard := clock[0] + cooldown_ticks + panic_ticks * 2
	while clock[0] < guard:
		step.call(inside)
		if _brain(c).phase == Phase.PANIC and first_panic < 0:
			first_panic = starts.size()
	assert_gt(first_panic, -1, "%s: precondition: PANIC" % mode)
	assert_gte(starts.size(), first_panic + 2, "%s: two rings in PANIC" % mode)
	if starts.size() >= first_panic + 2:
		assert_eq(starts[-1] - starts[-2], panic_ticks, "%s: PANIC halves the pulse cooldown" % mode)


## W5. The ring's fairness rule (Ph8) and the §2.7 numbers, read from an instance (an inherited scene's base exports resolve only there).
func test_the_carrier_pulse_ring_is_fair() -> void:
	var ring := RING_SCENE.instantiate() as EnergyRing
	var r_p := _player_r_p()
	assert_gt(r_p, 0.0, "precondition: the player hurtbox has a radius")
	var expected := {"max_radius": 420.0, "telegraph_seconds": 1.0, "ring_speed": 360.0, "band": 24.0, "gap_count": 2, "gap_deg": 50.0, "damage": 14}
	for key in expected:
		assert_eq(ring.get(key), expected[key], "carrier_pulse_ring.tscn %s" % key)
	assert_true(_gap_is_wide_enough(ring, r_p), "the gap arc at max_radius / 2 is >= 3 * r_p")
	assert_gte(ring.telegraph_seconds, REACTION, "the ring warns for at least the reaction time")
	ring.gap_deg = 15.0
	assert_false(_gap_is_wide_enough(ring, r_p), "boundary: a 15 degree gap fails the rule")
	ring.free()


func _gap_is_wide_enough(ring: EnergyRing, r_p: float) -> bool:
	return deg_to_rad(ring.gap_deg) * ring.max_radius * 0.5 >= 3.0 * r_p


## `r_p`: the larger of the two player hurtboxes' circumscribed radius (the `test_energy_ring.gd` method).
func _player_r_p() -> float:
	var r_p := 0.0
	for scene: PackedScene in [FIGHTER_SCENE, SHIP_SCENE]:
		var p := scene.instantiate() as PlayerBase
		var hurt := p.get_node("HurtBox") as Node2D
		for child in hurt.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			var xf := hurt.transform * cs.transform
			var rect := cs.shape.get_rect()
			var far := 0.0
			for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.end]:
				far = maxf(far, corner.length())
			var s := maxf(absf(xf.get_scale().x), absf(xf.get_scale().y))
			r_p = maxf(r_p, xf.origin.length() + far * s)
		p.free()
	return r_p


## A ring victim: `fixture_enemy.tscn` with a 14 px circle on its `HurtBox`, in group `enemies` (and in [param group] when set).
func _victim(h, at: Vector2, group: StringName = &"") -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = VICTIM_RADIUS
	cs.shape = circle
	e.get_node("HurtBox").add_child(cs)
	e.add_to_group(&"enemies")
	if group != &"":
		e.add_to_group(group)
	var health := e.get_node("Health") as Health
	health.max_health = VICTIM_HP
	health.current_health = VICTIM_HP
	h.root.add_child(e)
	e.set_physics_process(false)
	e.global_position = at
	return e


## W6. The ring never reaches its own carrier (hull exempt, parts never targets) or a launched child (owner group), and does hurt an outside enemy.
func test_the_ring_spares_its_own_carrier_and_its_children_but_not_other_enemies(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := _pin_at(h)
	var c := _armed(h, at)
	for part in c.modular_hull().modules():
		part.set_vulnerable(true)
	var hp := {}
	for part in c.modular_hull().modules():
		hp[part] = _hp(part)
	var hull_hp := c.health.current_health
	var refused := _count(c.armor_deflected)
	var outsiders: Array[BaseEnemy] = []
	var children: Array[BaseEnemy] = []
	for bearing in [0.0, 120.0, 240.0]:
		var dir := Vector2.from_angle(deg_to_rad(bearing))
		outsiders.append(_victim(h, at + dir * 300.0))
		children.append(_victim(h, at + dir * 320.0, c.owner_group()))
	var ring := c.pulse_ring()
	var started := false
	for i in int(4.0 / DT):
		h.player.global_position = at + Vector2.DOWN * (SHIPPED.pulse_trigger_range - 10.0)
		_tick_pinned(c, at, 0.0)
		started = started or ring.phase() != RingPhase.OFF
		if started and ring.phase() == RingPhase.OFF:
			break
	assert_true(started, "%s: precondition: one ring ran" % mode)
	for part in hp:
		assert_eq(_hp(part), hp[part], "%s: the ring leaves %s alone" % [mode, part.module_id])
	assert_eq(c.health.current_health, hull_hp, "%s: and the hull" % mode)
	assert_eq(refused[0], 0, "%s: the hull is exempt, not refused" % mode)
	for child in children:
		assert_eq((child.get_node("Health") as Health).current_health, VICTIM_HP, "%s: a launched child is passed" % mode)
	var hit := 0
	for e in outsiders:
		if (e.get_node("Health") as Health).current_health == VICTIM_HP - c.pulse_ring().damage:
			hit += 1
	assert_gte(hit, 2, "%s: the outside enemies are hurt (two gaps can cover at most one of three)" % mode)


## W7. PANIC on the tick after the third outer loss: battery cooldown x panic_battery_factor (bow and bank unchanged), the core light flashes; Open Space:
## it backs away from the player inside its leash.
func test_panic_entry_and_effects(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var at := Vector2(640.0, 200.0) if h.is_assault else Vector2(0.0, -500.0)
	var c := _spawn(h, at)
	var anchor := c.global_position
	for i in 6:
		_tick(c)
	var before := {}
	for mount in _all_mounts(c):
		before[mount] = mount.cooldown_seconds
	assert_eq(_core_light(c).get_state(), StateLight.State.OFF, "%s: the core light is dark before the panic" % mode)
	_expose_core(c)
	assert_ne(_brain(c).phase, Phase.PANIC, "%s: not in the same call" % mode)
	var d0 := c.global_position.distance_to(h.player.global_position)
	_tick(c)
	assert_eq(_brain(c).phase, Phase.PANIC, "%s: PANIC on the next tick" % mode)
	for mount in c.battery_mounts():
		assert_almost_eq(mount.cooldown_seconds, before[mount] * SHIPPED.panic_battery_factor, 1e-4, "%s: a battery cools down faster" % mode)
	assert_eq(c.bow_mount().cooldown_seconds, before[c.bow_mount()], "%s: the bow keeps its cooldown" % mode)
	assert_eq(c.missile_mount().cooldown_seconds, before[c.missile_mount()], "%s: the bank keeps its cooldown" % mode)
	var seen := {}
	var hull_seen := {}
	var furthest := 0.0
	for i in int((10.0 if not h.is_assault else 1.0) / DT):
		_tick(c)
		if h.is_assault:
			c.global_position = at
		seen[_core_light(c).get_state()] = true
		hull_seen[_hull_light(c).get_state()] = true
		furthest = maxf(furthest, c.global_position.distance_to(anchor))
	assert_true(seen.has(StateLight.State.ARMED) and seen.has(StateLight.State.OFF), "%s: the core light flashes red (%s)" % [mode, seen.keys()])
	assert_true(hull_seen.has(StateLight.State.OFF) and hull_seen.size() >= 2, "%s: the hull light strobes (%s)" % [mode, hull_seen.keys()])
	if not h.is_assault:
		assert_gt(c.global_position.distance_to(h.player.global_position), d0 + 50.0, "open_space: it backs away from the player")
		assert_lte(furthest, SHIPPED.leash_radius + 50.0, "open_space: inside its leash")


## W8. The turret rule in Assault: a hull held above the view never telegraphs a mount or starts a ring, the player inside every range; control: inside it does.
func test_in_assault_no_mount_or_pulse_fires_from_outside_the_view() -> void:
	for y in [-200.0, 260.0]:
		var h = _world("assault")
		var at := Vector2(640.0, y)
		var c := _armed(h, at)
		var telegraphed := false
		var ringed := false
		for i in int(3.0 / DT):
			h.player.global_position = at + Vector2.DOWN * (SHIPPED.pulse_trigger_range - 10.0)
			_tick_pinned(c, at, 0.0)
			telegraphed = telegraphed or _any_mount_in(c, MountPhase.TELEGRAPH)
			ringed = ringed or c.pulse_ring().phase() != RingPhase.OFF
			if telegraphed and ringed:
				break
		if y < 0.0:
			assert_false(telegraphed, "above the view: no mount telegraphs")
			assert_false(ringed, "above the view: no ring")
		else:
			assert_true(telegraphed and ringed, "control: inside the view both do")


## Ticks a pinned carrier with the player inside the trigger range until its ring reaches [param p].
func _ring_to(h, c: Carrier, at: Vector2, p: int) -> void:
	for i in int(3.0 / DT):
		h.player.global_position = at + Vector2.DOWN * (SHIPPED.pulse_trigger_range - 10.0)
		_tick_pinned(c, at, 0.0)
		if c.pulse_ring().phase() == p:
			return


## W9. An EMP (in TELEGRAPH and in EXPANDING), a rail and the carrier's death each end the ring at once; the EMP also drops every mount telegraph and the light.
func test_an_emp_a_rail_or_death_ends_the_ring_at_once(mode: String = use_parameters(MODES)) -> void:
	for ending in ["emp_telegraph", "emp_expanding", "rail", "death"]:
		var h = _world(mode)
		var at := _pin_at(h)
		var c := _armed(h, at)
		var ring := c.pulse_ring()
		var wanted: int = RingPhase.EXPANDING if ending in ["emp_expanding", "death"] else RingPhase.TELEGRAPH
		_ring_to(h, c, at, wanted)
		assert_eq(ring.phase(), wanted, "%s %s: precondition" % [mode, ending])
		match ending:
			"emp_telegraph", "emp_expanding":
				c.apply_emp(2.0, null)
				assert_eq(ring.phase(), RingPhase.OFF, "%s %s: the ring is gone" % [mode, ending])
				assert_false(_any_mount_in(c, MountPhase.TELEGRAPH), "%s %s: no mount telegraph survives" % [mode, ending])
				assert_eq(_hull_light(c).get_state(), StateLight.State.OFF, "%s %s: the light is off" % [mode, ending])
			"rail":
				var rounds: Array[int] = [0]
				for mount in _all_mounts(c):
					mount.round_fired.connect(func(_p: Node2D) -> void: rounds[0] += 1)
				c.suspend_ai()
				assert_eq(ring.phase(), RingPhase.OFF, "%s rail: the ring is gone" % mode)
				for i in int(3.0 / DT):
					_tick_pinned(c, at, 0.0)
				assert_eq(rounds[0], 0, "%s rail: a railed carrier fires nothing" % mode)
			"death":
				_core(c).destroy()
				assert_true(c.is_queued_for_deletion(), "%s death: precondition: the carrier died" % mode)
				assert_eq(ring.phase(), RingPhase.OFF, "%s death: the ring is gone in the same call" % mode)
				assert_false(ring.is_lethal(), "%s death: and not lethal" % mode)
