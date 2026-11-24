## The Space Fortress shell: armoured ring hull, nine parts, sector shields, the phase ladder and its consequences, death, EMP and homing
## (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.5; Phase 11 t5, task plan docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md, whose rows 1-11 the
## section headers follow). Intent tests, every behaviour row in both harnesses (IDEAS §40).
##
## A. Projectile / beam / nova rows (2, 3) run on real physics at the 8x clock (`_scale_clock()`: ticks per second scaled, the step stays 1/60 s) with the
##    fortress's own physics off (no brain, no mover), so a shot meets the authored geometry exactly. A bullet is fired with a `range_px` that ends its
##    flight just past its target, so "flew on" (expired at its range) and "consumed" (expired on a hit) are told apart.
## B. The rest is hand-driven: scripted `destroy()` calls and damage emits, a frame awaited where an unlock is deferred.
##
## Frame: local bearing 0 degrees = +x, 90 = +y; the fortress spawns at rotation 0 and does not move (t6 adds movement).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
const SHIPPED: SpaceFortressConfig = preload("res://assault/scenes/enemies/space_fortress/space_fortress_config.tres")  # read only
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const LASER_MODE: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/mining_laser.tres")
const ESCORT_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const Role := EnemyModule.Role
const Change := BossPhase.Change

const MODES := ["open_space", "assault"]
const SPAWN := Vector2(640.0, 360.0)
const HULL_RADIUS := 176.0
const BULLET_DAMAGE := 50
const NOVA_DAMAGE := 50
## (node name, id, role, config HP field, starts vulnerable, local centre, hurtbox: circle radius or rectangle size) in tree order (§2.5.2).
const PARTS := [
	["BatterySpread", &"battery_spread", Role.WEAPON, "battery_health", true, Vector2(99, 99), 22.0],
	["BatteryPulse", &"battery_pulse", Role.WEAPON, "battery_health", true, Vector2(-99, 99), 22.0],
	["BatteryArtillery", &"battery_artillery", Role.WEAPON, "battery_health", true, Vector2(-99, -99), 22.0],
	["BatteryMissiles", &"battery_missiles", Role.WEAPON, "battery_health", true, Vector2(99, -99), 22.0],
	["BatterySweep", &"battery_sweep", Role.WEAPON, "battery_health", true, Vector2(150, 0), 22.0],
	["Hangar", &"hangar", Role.HANGAR, "hangar_health", false, Vector2(-150, 0), Vector2(36, 56)],
	["ShieldNorth", &"shield_north", Role.WEAK_POINT, "shield_node_health", false, Vector2(0, -120), 26.0],
	["ShieldSouth", &"shield_south", Role.WEAK_POINT, "shield_node_health", false, Vector2(0, 120), 26.0],
	["Core", &"core", Role.CORE, "core_health", false, Vector2.ZERO, 44.0],
]
const NORTH := [&"battery_artillery", &"battery_missiles", &"hangar"]
const SOUTH := [&"battery_spread", &"battery_pulse", &"battery_sweep"]
## The §25 keys built so far (t5 vulnerable and visuals, t6 movement; t7 / t16 add attacks and arena, t8 reinforcements).
const BUILT_KEYS := {Change.VULNERABLE: &"vulnerable", Change.VISUALS: &"visuals", Change.MOVEMENT: &"movement"}
const _SPEEDUP := 8  # tests/README.md -> Gate time rule 1

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

## A fresh harness world; an earlier world of this test leaves the tree first (its player would still be in group `player`, its camera an arena).
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = Vector2(640.0, 1000.0)
	return h


## A fortress with its physics off (hand-driven). [param props] are written on its private config copy before it enters the tree.
func _spawn(h, pos: Vector2 = SPAWN, props: Dictionary = {}) -> SpaceFortress:
	var f := SCENE.instantiate() as SpaceFortress
	for key in props:
		f.config.set(key, props[key])
	f.global_position = pos
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


func _part(f: SpaceFortress, id: StringName) -> EnemyModule:
	return f.part(id)


func _hp(part: EnemyModule) -> int:
	return part.health.current_health


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


## One physics frame and one idle frame: a deferred unlock queued in a kill's call has run.
func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame


## A real player bullet launched at [param target] from [param shot] px away along [param from_dir], whose `range_px` ends its flight [param beyond]
## px past the target. The record's `consumed` is set when it expires: true on a hit (it had range left), false at its range (it flew on).
func _shoot(target: Vector2, from_dir: Vector2, beyond: float, shot: float) -> Dictionary:
	var b := BULLET_SCENE.instantiate() as Bullet
	var notifier := b.get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier != null:
		b.remove_child(notifier)
		notifier.free()
	b.range_px = shot + beyond
	var rec := {"done": false, "consumed": false}
	b.expired.connect(func() -> void:
		rec["done"] = true
		rec["consumed"] = b._traveled < b.range_px)
	b.expired.connect(b.queue_free)
	_roots[-1].add_child(b)
	b.global_position = target + from_dir * shot
	b.rotation = Vector2.UP.angle_to(-from_dir)
	return rec


## Waits (at most [param limit] physics frames) until [param rec]'s bullet expired.
func _until_done(rec: Dictionary, limit: int = 120) -> void:
	for i in limit:
		if rec["done"]:
			return
		await get_tree().physics_frame


## Drives a real `BeamBehavior` from `_physics_process` (the `test_enemy_module.gd` driver).
class BeamDriver extends Node2D:
	var actor: Node2D
	var behavior: BeamBehavior
	var mode: WeaponModeResource
	var muzzles: Array[Marker2D] = []

	func _physics_process(delta: float) -> void:
		if behavior != null:
			behavior.tick(self, mode, muzzles, delta)


func _beam(from: Vector2, dir: Vector2) -> BeamDriver:
	var d := BeamDriver.new()
	d.behavior = BeamBehavior.new()
	d.mode = LASER_MODE
	var muzzle := Marker2D.new()
	d.add_child(muzzle)
	d.muzzles = [muzzle]
	d.actor = d
	_roots[-1].add_child(d)
	d.global_position = from
	d.rotation = Vector2.UP.angle_to(dir)
	return d


## One map-wide nova from the harness player (its flash layer freed at once).
func _nova(h) -> void:
	var before := get_tree().root.get_children()
	assert_true(PlasmaNovaModule.new().try_activate(h.player), "the nova fires")
	for child in get_tree().root.get_children():
		if child not in before:
			child.free()


## The local-space extent of [param part]'s hurtbox from the hull centre (its centre distance + radius, or + the farthest corner).
func _reach(f: SpaceFortress, part: EnemyModule) -> float:
	var cs := part.hurt_box.get_node("CollisionShape2D") as CollisionShape2D
	var centre := f.to_local(cs.global_position)
	if cs.shape is CircleShape2D:
		return centre.length() + (cs.shape as CircleShape2D).radius
	var half := (cs.shape as RectangleShape2D).size * 0.5
	var best := 0.0
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		best = maxf(best, (centre + corner).length())
	return best


## The keys of two snapshots whose values differ.
func _changed(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for key in before:
		if before[key] != after[key]:
			out.append(key)
	return out


## Asserts every change [param phase] declares among the keys this task builds was observed between [param before] and [param after].
func _assert_declared_changes(phase: BossPhase, before: Dictionary, after: Dictionary, label: String) -> void:
	var changed := _changed(before, after)
	var owned := 0
	for bit in BUILT_KEYS:
		if phase.changes & bit == 0:
			continue
		owned += 1
		assert_has(changed, BUILT_KEYS[bit], "%s: the declared %s change shows in the snapshot" % [label, BUILT_KEYS[bit]])
	var seen := changed.filter(func(k) -> bool: return BUILT_KEYS.values().has(k)).size()
	assert_gte(seen, mini(2, owned), "%s: at least min(2, declared) of the built keys changed (%s)" % [label, changed])


## §2.6 row 8: the `movement` key in boss phase [param index] equals the literal (typed here, not read off the config).
func _assert_movement(f: SpaceFortress, mode: String, index: int) -> void:
	var open_space := [
		[&"hold", &"face", 0.0, 0.0], [&"hold", &"volley", 0.0, 0.0], [&"reposition", &"volley", 8.0, 60.0], [&"reposition", &"continuous", 5.0, 90.0],
	]
	var assault := [
		[&"hold", &"face", 0.0, 0.0], [&"hold", &"volley", 0.0, 0.0], [&"bob", &"volley", 0.0, 35.0], [&"bob", &"continuous", 0.0, 55.0],
	]
	var expected: Array = (assault if mode == "assault" else open_space)[index]
	assert_eq(f.phase_snapshot()[&"movement"], expected, "%s: the movement key in boss phase %d" % [mode, index])


# ══ 1. Geometry ═════════════════════════════════════════════════════════════════════════════════

func test_the_ring_hull_and_its_nine_parts_as_authored(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var body := f.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := f.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := f.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is CircleShape2D, "%s: the hull is a circle" % mode)
	assert_almost_eq((body.shape as CircleShape2D).radius, HULL_RADIUS, 0.001, "%s: r 176" % mode)
	assert_eq(hurt.shape, body.shape, "%s: the hurtbox shares the body shape" % mode)
	assert_eq(contact.shape, body.shape, "%s: so does the contact box" % mode)
	assert_eq([body.scale, hurt.scale, contact.scale], [Vector2.ONE, Vector2.ONE, Vector2.ONE], "%s: unscaled" % mode)
	assert_eq([f.collision_layer, f.collision_mask], [0, 0], "%s: the root blocks nothing (the mining laser passes)" % mode)
	assert_eq(f.hull_radius(), HULL_RADIUS)

	var parts := f.modular_hull().modules()
	assert_eq(parts.size(), PARTS.size(), "%s: nine parts" % mode)
	for i in mini(parts.size(), PARTS.size()):
		var row: Array = PARTS[i]
		var part := parts[i]
		var label := "%s: %s" % [mode, row[0]]
		assert_eq([String(part.name), part.module_id, part.role, part.is_vulnerable(), part.hull_share], [row[0], row[1], row[2], row[4], 0.0], label)
		assert_eq(part.get_parent().name, &"Modules", "%s under Modules" % label)
		assert_almost_eq(f.to_local(part.global_position).x, (row[5] as Vector2).x, 0.01, "%s centre x" % label)
		assert_almost_eq(f.to_local(part.global_position).y, (row[5] as Vector2).y, 0.01, "%s centre y" % label)
		assert_eq(part.max_health, SHIPPED.get(row[3]), "%s HP from the config" % label)
		var shape := (part.hurt_box.get_node("CollisionShape2D") as CollisionShape2D).shape
		if row[6] is float:
			assert_true(shape is CircleShape2D and is_equal_approx((shape as CircleShape2D).radius, row[6]), "%s: circle r %s" % [label, row[6]])
		else:
			assert_true(shape is RectangleShape2D and (shape as RectangleShape2D).size == row[6], "%s: rect %s" % [label, row[6]])
		assert_lte(_reach(f, part), HULL_RADIUS + 0.001, "%s lies inside the hull circle" % label)
		assert_not_null(part.get_node_or_null("HomingPoint"), "%s has a HomingPoint" % label)
		assert_true(part.get_node_or_null("Light") is StateLight, "%s has a state light" % label)
	assert_eq(f.contact_hit_box.damage, SHIPPED.collision_damage, "%s: contact 40" % mode)
	assert_eq([f.contact_profile.mode, f.contact_profile.shove_speed], [ContactProfile.Mode.ARMOR, 260.0], "%s: ARMOR, 260" % mode)

	# Boundary: the inside-the-hull check reports a part pushed out to r 170.
	var moved := SCENE.instantiate() as SpaceFortress
	moved.get_node("Modules/BatterySweep").position = Vector2(170.0, 0.0)
	h.root.add_child(moved)
	moved.set_physics_process(false)
	assert_gt(_reach(moved, _part(moved, &"battery_sweep")), HULL_RADIUS, "%s: boundary: a part at r 170 pokes out" % mode)


# ══ 2. Armour and lanes (real physics, 8x) ══════════════════════════════════════════════════════

func test_bare_hull_deflects_and_a_battery_lane_meets_the_bubble_first(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var f := _spawn(h)
	var c := f.global_position
	var core := _part(f, &"core")
	var spread := _part(f, &"battery_spread")

	# Down local x 60: clear of every part (shields 26 at x 0, batteries 22 at x +-99) for the whole 352 px crossing.
	var refused := _count_damage(f.armor_deflected, BULLET_DAMAGE)
	var bare := _shoot(c + Vector2(60.0, 0.0), Vector2.UP, 260.0, 300.0)
	await _until_done(bare)
	assert_true(bare["done"] and not bare["consumed"], "%s: a bullet across bare hull flies on" % mode)
	assert_gte(refused[0], 1, "%s: the hull refused it (armor_deflected 50)" % mode)
	assert_eq(f.health.current_health, SHIPPED.core_health, "%s: the root bar never moves" % mode)

	# The spread battery's diagonal lane, one bullet at a time from outside the hull; each ends 10 px past the battery centre, short of the core.
	var lane := Vector2(1.0, 1.0).normalized()
	var absorbed := _count(spread.hurt_box.hit_absorbed)
	var results: Array = []
	for i in 4:
		var rec := _shoot(spread.global_position, lane, 10.0, 300.0)
		await _until_done(rec)
		results.append([rec["consumed"], absorbed[0], _hp(spread)])
	assert_eq(results, [
		[true, 1, SHIPPED.battery_health],
		[true, 2, SHIPPED.battery_health],
		[true, 3, SHIPPED.battery_health],
		[true, 3, SHIPPED.battery_health - BULLET_DAMAGE],
	], "%s: three bullets break the 120-point bubble (consumed: a shield stops a bullet), the fourth hits the battery" % mode)
	assert_eq(_hp(core), SHIPPED.core_health, "%s: the core behind the lane never takes anything" % mode)


# ══ 3. Locked parts (real physics, 8x) ══════════════════════════════════════════════════════════

func test_locked_core_generators_and_hangar_ignore_bullets_beam_and_nova(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var f := _spawn(h)
	var c := f.global_position
	var locked := [&"shield_north", &"core", &"shield_south", &"hangar"]
	var pings := {}
	for id in locked:
		pings[id] = _count(_part(f, id).deflected)

	# Down x 0 through the north generator, the core and the south generator; along y 0 from the left through the hangar and the core, ending 6 px
	# past the core's edge (short of the sweep battery's 128).
	var down := _shoot(c, Vector2.UP, 300.0, 300.0)
	var across := _shoot(c + Vector2(-150.0, 0.0), Vector2.LEFT, 200.0, 200.0)
	await _until_done(down)
	await _until_done(across)
	assert_true(down["done"] and not down["consumed"], "%s: a bullet across the locked generators and core flies on" % mode)
	assert_true(across["done"] and not across["consumed"], "%s: a bullet across the closed hangar and the core flies on" % mode)
	for id in locked:
		assert_gte(pings[id][0], 1, "%s: %s pinged the bullet" % [mode, id])
		assert_eq(_hp(_part(f, id)), _part(f, id).max_health, "%s: %s took nothing from bullets" % [mode, id])

	# The player beam up x 0 for 60 frames: it burns every part whose centre lies within 12 px of its line, so the three locked parts on x 0 at once.
	var on_line := [&"shield_north", &"core", &"shield_south"]
	var line_pings := on_line.map(func(id: StringName) -> int: return pings[id][0])
	var beam := _beam(c + Vector2(0.0, 300.0), Vector2.UP)
	await _frames(60)
	beam.behavior = null
	beam.queue_free()
	for i in on_line.size():
		assert_gt(pings[on_line[i]][0], line_pings[i], "%s: the beam pings %s" % [mode, on_line[i]])
	for id in locked:
		assert_eq(_hp(_part(f, id)), _part(f, id).max_health, "%s: %s took nothing from the beam" % [mode, id])

	# One nova: each locked part pings once and keeps its HP; an open battery takes the nova through its bubble (a direct emitter).
	var before := {}
	for id in locked:
		before[id] = pings[id][0]
	var sweep := _part(f, &"battery_sweep")
	var sweep_hp := _hp(sweep)
	_nova(h)
	for id in locked:
		assert_eq(pings[id][0], before[id] + 1, "%s: the nova pings %s once" % [mode, id])
		assert_eq(_hp(_part(f, id)), _part(f, id).max_health, "%s: %s took nothing from the nova" % [mode, id])
	assert_eq(_hp(sweep), sweep_hp - NOVA_DAMAGE, "%s: an open battery takes the nova through its bubble" % mode)
	assert_eq(f.health.current_health, SHIPPED.core_health, "%s: the root bar never moves" % mode)


# ══ 4. Sector shields (wiring) ══════════════════════════════════════════════════════════════════

func _hit(h, part: EnemyModule, damage: int) -> void:
	var hb := HitBox.new()
	hb.damage = damage
	h.root.add_child(hb)
	hb.global_position = part.global_position + Vector2(0.0, 30.0)
	part.hurt_box.area_entered.emit(hb)
	hb.free()


func test_two_sector_shields_wired_from_the_config(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	# Values unlike both the shipped ones and `EnemyShield`'s defaults, so a sector built without the config fails.
	var props := {
		"sector_shield_capacity": 77, "sector_shield_regen_delay": 1.5, "sector_shield_regen_seconds": 0.75, "sector_shield_reboot_seconds": 9.0,
		"sector_shield_pad": 4.0,
	}
	var f := _spawn(h, SPAWN, props)
	var north := f.north_sector()
	var south := f.south_sector()
	assert_eq([north.generator(), south.generator()], [_part(f, &"shield_north"), _part(f, &"shield_south")], "%s: the generators" % mode)
	assert_eq(north.protected_ids(), NORTH, "%s: north covers artillery, missiles, hangar" % mode)
	assert_eq(south.protected_ids(), SOUTH, "%s: south covers spread, pulse, sweep" % mode)
	for id in NORTH + SOUTH:
		var sector := north if NORTH.has(id) else south
		var s := sector.shield_of(id)
		assert_not_null(s, "%s: %s has a bubble" % [mode, id])
		if s == null:
			continue
		assert_eq([s.arc_deg, s.capacity, s.regen_delay, s.regen_seconds, s.reboot_seconds],
				[360.0, props["sector_shield_capacity"], props["sector_shield_regen_delay"], props["sector_shield_regen_seconds"],
				props["sector_shield_reboot_seconds"]], "%s: %s bubble from the config" % [mode, id])
		var expected := 22.0 if id != &"hangar" else Vector2(36.0, 56.0).length() * 0.5
		assert_almost_eq(s.radius, expected + float(props["sector_shield_pad"]), 0.001, "%s: %s radius = hurtbox + pad" % [mode, id])
	for id in [&"shield_north", &"shield_south", &"core"]:
		assert_false(_part(f, id).hurt_box.has_absorber(), "%s: %s carries no bubble" % [mode, id])
	assert_eq([SHIPPED.sector_shield_capacity, SHIPPED.sector_shield_reboot_seconds], [120, 5.0])

	# A hit on the closed hangar is not absorbed (the part is armoured while locked): it pings and costs nothing. Control: an open north battery absorbs.
	var hangar := _part(f, &"hangar")
	var hangar_absorbed := _count(hangar.hurt_box.hit_absorbed)
	var hangar_pings := _count(hangar.deflected)
	_hit(h, hangar, 30)
	assert_eq([hangar_absorbed[0], hangar_pings[0], _hp(hangar)], [0, 1, SHIPPED.hangar_health], "%s: the closed hangar's bubble absorbs nothing" % mode)
	var artillery := _part(f, &"battery_artillery")
	var artillery_absorbed := _count(artillery.hurt_box.hit_absorbed)
	_hit(h, artillery, 30)
	assert_eq([artillery_absorbed[0], _hp(artillery)], [1, SHIPPED.battery_health], "%s: control: an open battery's bubble absorbs" % mode)

	# The north generator's death frees every north bubble in the same call and leaves the south ones; a battery's death frees its own.
	_part(f, &"shield_north").destroy()
	assert_true(north.is_exposed(), "%s: north exposed" % mode)
	for id in NORTH:
		assert_null(north.shield_of(id), "%s: %s bare at once" % [mode, id])
		assert_false(_part(f, id).hurt_box.has_absorber(), "%s: %s's absorber slot is free in the same call" % [mode, id])
	for id in SOUTH:
		assert_not_null(south.shield_of(id), "%s: %s keeps its bubble" % [mode, id])
	_part(f, &"battery_spread").destroy()
	assert_null(south.shield_of(&"battery_spread"), "%s: a destroyed battery's bubble is freed" % mode)
	assert_not_null(south.shield_of(&"battery_pulse"), "%s: its neighbours keep theirs" % mode)


# ══ 5. Phase ladder ═════════════════════════════════════════════════════════════════════════════

func test_the_ladder_batteries_shields_core_critical(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var driver := f.phase_driver()
	assert_eq(driver.validate(f.modular_hull()), PackedStringArray(), "%s: the shipped ladder validates" % mode)
	assert_eq(driver.phases.map(func(p: BossPhase) -> StringName: return p.phase_id),
			[&"batteries", &"shields_exposed", &"core_exposed", &"critical"], "%s: the four phases in order" % mode)
	assert_eq(driver.phase(1).count, SHIPPED.shields_exposed_battery_losses, "%s: the scene's battery count is the config's" % mode)
	assert_eq(driver.phase(1).roles, [Role.WEAPON] as Array[int], "%s: counted among WEAPON parts" % mode)
	assert_eq(driver.phase(2).module_ids, [&"shield_north", &"shield_south"] as Array[StringName], "%s: both generators" % mode)
	assert_eq([driver.phase(3).health_module, driver.phase(3).health_ratio], [&"core", SHIPPED.critical_core_ratio], "%s: core at the config ratio" % mode)
	assert_eq(driver.current_id(), &"batteries", "%s: starts in batteries" % mode)

	var north := _part(f, &"shield_north")
	var south := _part(f, &"shield_south")
	_part(f, &"battery_sweep").destroy()
	await _settle()
	assert_eq(driver.current_id(), &"batteries", "%s: boundary: one battery is not enough" % mode)
	assert_false(north.is_vulnerable() or south.is_vulnerable(), "%s: the generators stay locked" % mode)

	_part(f, &"battery_missiles").destroy()
	assert_eq(driver.current_id(), &"shields_exposed", "%s: the second battery enters shields_exposed" % mode)
	assert_false(north.is_vulnerable(), "%s: the unlock is deferred (the kill may land in a physics flush)" % mode)
	await _settle()
	assert_true(north.is_vulnerable() and south.is_vulnerable(), "%s: both generators open a frame later" % mode)

	var core := _part(f, &"core")
	north.destroy()
	assert_eq(driver.current_id(), &"shields_exposed", "%s: one generator is not enough" % mode)
	south.destroy()
	assert_eq(driver.current_id(), &"core_exposed", "%s: both generators enter core_exposed" % mode)
	assert_false(core.is_vulnerable(), "%s: deferred" % mode)
	await _settle()
	assert_true(core.is_vulnerable(), "%s: the core opens a frame later" % mode)

	var threshold := roundi(SHIPPED.critical_core_ratio * SHIPPED.core_health)
	core.hurt_box.received_damage.emit(SHIPPED.core_health - threshold - 1)
	assert_eq(_hp(core), threshold + 1)
	assert_eq(driver.current_id(), &"core_exposed", "%s: boundary: one point above 40 %% is not critical" % mode)
	core.hurt_box.received_damage.emit(1)
	assert_eq(driver.current_id(), &"critical", "%s: exactly 40 %% enters critical" % mode)


# ══ 6. §25: every declared change shows in phase_snapshot() ═════════════════════════════════════

func test_each_phase_shows_its_declared_changes(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var driver := f.phase_driver()
	var keys := f.phase_snapshot().keys().map(func(k: StringName) -> String: return String(k))
	keys.sort()
	assert_eq(keys, ["arena", "attacks", "movement", "reinforcements", "visuals", "vulnerable"], "%s: six keys" % mode)

	# Boundary: one battery in `batteries` changes no key (a part's death alone is never a phase change).
	var s0 := f.phase_snapshot()
	_assert_movement(f, mode, 0)
	_part(f, &"battery_spread").destroy()
	await _settle()
	assert_eq(f.phase_snapshot(), s0, "%s: boundary: one battery lost changes nothing in the snapshot" % mode)

	# shields_exposed on the second battery.
	var before := f.phase_snapshot()
	_part(f, &"battery_pulse").destroy()
	await _settle()
	assert_eq(driver.current_id(), &"shields_exposed")
	_assert_declared_changes(driver.phase(1), before, f.phase_snapshot(), "%s shields_exposed" % mode)
	_assert_movement(f, mode, 1)
	for id in [&"shield_north", &"shield_south"]:
		var generator := _part(f, id)
		assert_eq(generator.sprite.texture, f.shutter_open_texture, "%s: %s shows its open shutter on screen" % [mode, id])
		assert_ne(generator.sprite.texture, generator.intact_texture, "%s: not the closed one" % mode)

	# core_exposed on the second generator (the first alone changes nothing either).
	before = f.phase_snapshot()
	_part(f, &"shield_north").destroy()
	await _settle()
	assert_eq(f.phase_snapshot(), before, "%s: one generator's death changes nothing in the snapshot" % mode)
	_part(f, &"shield_south").destroy()
	await _settle()
	assert_eq(driver.current_id(), &"core_exposed")
	_assert_declared_changes(driver.phase(2), before, f.phase_snapshot(), "%s core_exposed" % mode)
	_assert_movement(f, mode, 2)
	assert_eq(_part(f, &"core").sprite.texture, f.core_open_texture, "%s: the core shows its open plating on screen" % mode)
	assert_ne(f.core_open_texture, _part(f, &"core").intact_texture)
	assert_true((f.get_node("Thrusters") as CanvasItem).visible, "%s: thrusters shown" % mode)

	# critical on the core at 40 %, the hangar alive (t8's surge needs it).
	assert_false(_part(f, &"hangar").is_destroyed(), "the pinned path keeps the hangar alive")
	var core := _part(f, &"core")
	before = f.phase_snapshot()
	core.hurt_box.received_damage.emit(SHIPPED.core_health - roundi(SHIPPED.critical_core_ratio * SHIPPED.core_health))
	await _settle()
	assert_eq(driver.current_id(), &"critical")
	_assert_declared_changes(driver.phase(3), before, f.phase_snapshot(), "%s critical" % mode)
	_assert_movement(f, mode, 3)
	assert_true((f.get_node("CriticalOverlay") as CanvasItem).visible, "%s: the critical overlay is shown" % mode)

	# The critical core light blinks COMMIT / OFF on the config period (hand-stepped; nothing awaited in between).
	var light := core.get_node("Light") as StateLight
	var period := SHIPPED.core_blink_period
	f.set_process(false)  # the real idle tick toggled it while the frames above ran: start the hand-stepped blink from its entry state
	f._blink_left = 0.0
	f._blink_lit = false
	f._process(0.0)
	var states: Array = [light.get_state()]
	f._process(period * 0.5)
	states.append(light.get_state())
	f._process(period * 0.5)
	states.append(light.get_state())
	f._process(period)
	states.append(light.get_state())
	assert_eq(states, [StateLight.State.COMMIT, StateLight.State.COMMIT, StateLight.State.OFF, StateLight.State.COMMIT], "%s: the blink" % mode)
	var during := f.phase_snapshot()
	f._process(period)
	assert_eq(f.phase_snapshot(), during, "%s: the blink itself never changes the snapshot" % mode)


# ══ 7. Death ════════════════════════════════════════════════════════════════════════════════════

func test_the_cores_death_is_the_fortresses_with_a_timed_wreck(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	f.death_duration = 0.2  # mid-sequence is checked two frames in, never by a timed wait one slow frame could overshoot
	var container := EscortContainer.ensure(f)
	var escort := ESCORT_SCENE.instantiate() as BaseEnemy
	container.add_child(escort)
	escort.set_physics_process(false)
	watch_signals(f)
	_part(f, &"core").destroy()
	assert_signal_emit_count(f, "died", 1, "%s: died once" % mode)
	assert_signal_emit_count(f, "death_started", 1, "%s: death_started once" % mode)
	assert_true(f.was_killed and f.is_dying(), "%s: killed and dying" % mode)
	assert_false(f.is_queued_for_deletion(), "%s: the wreck stays for the sequence" % mode)
	assert_true(f.is_ai_suspended(), "%s: the AI is suspended" % mode)
	assert_true(escort.is_queued_for_deletion(), "%s: every escort is scuttled when the death starts" % mode)
	f.health.set_health(0)
	assert_signal_emit_count(f, "died", 1, "%s: a later hit re-emits nothing" % mode)
	await _settle()
	assert_true(is_instance_valid(f), "%s: still in the tree mid-sequence" % mode)
	if not is_instance_valid(f):
		return
	assert_eq(f.contact_hit_box.collision_layer, 0, "%s: the corpse cannot ram (contact 256 -> 0)" % mode)
	assert_false(f.hurt_box.monitoring, "%s: nor take hits" % mode)
	await wait_seconds(0.25)
	assert_false(is_instance_valid(f), "%s: freed after death_duration" % mode)
	assert_false(is_instance_valid(container), "%s: the escort container goes with it" % mode)

	var g := _spawn(h)
	g.death_duration = 0.0
	_part(g, &"core").destroy()
	assert_true(g.is_queued_for_deletion(), "%s: death_duration 0 frees in the same call" % mode)

	# A core killed in the call that exposes it keeps its wreck: the deferred plating swap never lands on a wreck (the Carrier R2-4 rule).
	var k := _spawn(h, SPAWN + Vector2(0.0, 600.0))
	for id in [&"battery_spread", &"battery_pulse"]:
		_part(k, id).destroy()
	await _settle()
	var core := _part(k, &"core")
	_part(k, &"shield_north").destroy()
	_part(k, &"shield_south").destroy()
	core.destroy()
	await _settle()
	assert_true(k.is_dying(), "%s: dead" % mode)
	assert_ne(core.sprite.texture, k.core_open_texture, "%s: the open plating never replaces the wreck" % mode)


# ══ 8. EMP ══════════════════════════════════════════════════════════════════════════════════════

func test_every_emp_is_scaled_and_one_while_dying_does_nothing(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	assert_true(f.answers_emp(), "%s: it answers EMP" % mode)
	f.velocity = Vector2(40.0, 0.0)
	assert_gte(EmpPulse.emit(get_tree(), f.global_position, 50.0, 5.0, null, EmpPulse.TARGET_ENEMIES), 1, "%s: an EMP pulse reaches it" % mode)
	assert_almost_eq(f.emp_seconds_left(), 5.0 * SHIPPED.emp_factor, 0.0001, "%s: a 5 s pulse is a 2 s window" % mode)
	assert_eq(f.velocity, Vector2.ZERO, "%s: the mover halted" % mode)
	var battery := _part(f, &"battery_pulse")
	assert_true(battery.hurt_box.monitoring and battery.hurt_box.monitorable, "%s: still tangible" % mode)
	battery.hurt_box.received_damage.emit(BULLET_DAMAGE)
	assert_eq(_hp(battery), SHIPPED.battery_health - BULLET_DAMAGE, "%s: a battery still takes a hit" % mode)
	f.apply_emp(10.0, null)
	assert_almost_eq(f.emp_seconds_left(), 10.0 * SHIPPED.emp_factor, 0.0001, "%s: every source is scaled (the longest window wins)" % mode)

	# While dying: a real EMP Blast leaves the wreck processing (no process-disable, no window) and it is freed on time.
	var g := _spawn(h, SPAWN + Vector2(0.0, 600.0))
	g.death_duration = 0.2  # mid-sequence is checked two frames in, never by a timed wait one slow frame could overshoot
	_part(g, &"core").destroy()
	assert_true(g.is_dying())
	assert_true(g.is_in_group(&"enemies"), "%s: the wreck is still an enemy the blast sweeps" % mode)
	assert_true(g.answers_emp(), "%s: a dying fortress still answers (else the blast would process-disable it)" % mode)
	assert_true(EMPBlastModule.new().try_activate(h.player), "%s: the blast fires" % mode)
	assert_eq(g.process_mode, Node.PROCESS_MODE_INHERIT, "%s: the wreck is not process-disabled" % mode)
	assert_false(g.is_emp_disrupted(), "%s: no EMP window starts on a wreck" % mode)
	await _settle()
	assert_true(is_instance_valid(g), "%s: mid-sequence" % mode)
	await wait_seconds(0.25)
	assert_false(is_instance_valid(g), "%s: freed death_duration after the core's death" % mode)


# ══ 9. Homing ═══════════════════════════════════════════════════════════════════════════════════

func test_homing_steers_at_the_nearest_live_vulnerable_part(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var c := f.global_position
	var spread := _part(f, &"battery_spread")
	assert_eq(f.homing_point(c + Vector2(300.0, 300.0)), spread.homing_point(), "%s: the nearest battery" % mode)
	assert_eq(f.homing_point(c + Vector2(0.0, -400.0)), _part(f, &"battery_artillery").homing_point(),
			"%s: a locked generator is never the point (the nearest open battery wins; tree order breaks the tie)" % mode)
	for id in SOUTH + [&"battery_artillery", &"battery_missiles"]:
		_part(f, id).destroy()
	assert_eq(f.homing_point(c + Vector2(0.0, -400.0)), _part(f, &"core").homing_point(),
			"%s: nothing open (the unlocks are deferred, the hangar shut): the core's centre" % mode)
	await _settle()
	assert_eq(f.homing_point(c + Vector2(0.0, -400.0)), _part(f, &"shield_north").homing_point(), "%s: the open north generator" % mode)


# ══ 10. Config ══════════════════════════════════════════════════════════════════════════════════

func test_the_config_wins_and_the_children_read_the_private_copy(mode: String = use_parameters(MODES)) -> void:
	var expected := {
		"max_health": 1500, "collision_damage": 40, "score_value": 1500, "counts_toward_wave_clear": true, "counts_as_escape": true,
		"wreck_chance": 0.0, "battery_health": 260, "hangar_health": 300, "shield_node_health": 360, "core_health": 1500,
		"sector_shield_capacity": 120, "sector_shield_regen_delay": 3.0, "sector_shield_regen_seconds": 2.0, "sector_shield_reboot_seconds": 5.0,
		"sector_shield_pad": 8.0, "shields_exposed_battery_losses": 2, "critical_core_ratio": 0.4, "core_blink_period": 0.25,
		"death_sequence_duration": 2.4, "death_blast_count": 10, "emp_factor": 0.4, "escort_cap_open_space": 6, "escort_cap_assault": 4,
		"turn_rate": 0.22, "assault_turn_rate": 0.3, "beam_spin_rate": 0.5, "critical_spin_rate": 0.6, "idle_spin_rate": 0.08,
		"perceive_radius": 1400.0, "lose_radius": 2600.0, "notice_time": 0.8, "home_radius": 8.0, "zone_radius": 600.0, "station_ring_factor": 0.6,
		"reposition_min_step": 250.0, "reposition_lookahead": 1.0, "reposition_period": 8.0, "critical_reposition_period": 5.0,
		"reposition_speed": 60.0, "critical_reposition_speed": 90.0, "hold_tolerance": 24.0, "hold_speed": 40.0, "assault_enter_speed": 90.0,
		"assault_hold_y": 180.0, "assault_bob_amplitude": 100.0, "assault_bob_speed": 35.0, "critical_bob_speed": 55.0, "assault_x_correct_speed": 20.0,
		"escort_boost_speed": 300.0, "escort_boost_seconds": 0.4,
	}
	for key in expected:
		assert_eq(SHIPPED.get(key), expected[key], "space_fortress_config.tres %s" % key)
	var h = _world(mode)
	var f := _spawn(h, SPAWN, {"battery_health": 999, "core_health": 1234, "death_blast_count": 7})
	assert_ne(f.config, SHIPPED, "%s: a private copy" % mode)
	assert_true(f.config.resource_path.is_empty(), "%s: not the cached resource" % mode)
	assert_eq(_hp(_part(f, &"battery_spread")), 999, "%s: the config wins over the scene's part HP" % mode)
	assert_eq(_part(f, &"battery_spread").max_health, 999)
	assert_eq([_hp(_part(f, &"core")), f.health.max_health, f.health.current_health], [1234, 1234, 1234], "%s: core and root bar" % mode)
	assert_eq(SHIPPED.battery_health, 260, "%s: the shipped resource is untouched" % mode)
	assert_eq((f.get_node("DeathSequence") as BossDeathSequence)._blast_count, 7, "%s: the death sequence read the private copy in its _ready()" % mode)
	assert_eq(autofree(BossDeathSequence.new())._blast_count, 3, "the script default differs, so the row can fail")
	assert_almost_eq(f.death_duration, SHIPPED.death_sequence_duration, 0.0001)
	assert_eq([f.score_value, f.counts_toward_wave_clear, f.counts_as_escape], [1500, true, true])
	var cap := SHIPPED.escort_cap_assault if h.is_assault else SHIPPED.escort_cap_open_space
	assert_eq(f.is_assault(), h.is_assault, "%s: the mode" % mode)
	assert_eq(f.reinforcements().bay_ids(), [] as Array[StringName], "%s: no bays until t8" % mode)
	assert_eq(cap, 4 if h.is_assault else 6)


# ══ 11. Builder and duck-typed answers ══════════════════════════════════════════════════════════

func test_the_builder_the_brain_shell_and_the_refusals() -> void:
	assert_eq(WaveBuilder.SPACE_FORTRESS, "res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
	assert_not_null(WaveBuilder.new().space_fortress(), "space_fortress() builds a spawn config")
	var probe := (load(WaveBuilder.SPACE_FORTRESS) as PackedScene).instantiate()
	assert_true(probe is SpaceFortress, "SPACE_FORTRESS loads a SpaceFortress")
	assert_true((probe as SpaceFortress).world_anchored_x, "world-anchored in x by default")
	probe.free()
	assert_eq(FortressBrain.Phase.keys(), ["IDLE", "NOTICING", "RETURNING", "ENTER", "HOLD", "REPOSITION"], "the append-only brain phases")

	var h = _world("open_space")
	var f := _spawn(h)
	var brain := f.get_node("Brain") as FortressBrain
	assert_false(brain.is_engaged(), "not engaged before its first tick (the hub idle)")
	assert_false(brain.attack_gate(), "no battery may fire until t7")
	assert_true(f.deflects_hit(null) and f.is_armored(), "the hull is armour")
	assert_false(f.is_laser_blocking(), "the beam passes over it")
	assert_false(f.can_be_repaired() or f.accepts_ward() or f.accept_tow(Vector2(50.0, 0.0)), "never repaired, warded or towed")
	assert_almost_eq(f.rocket_clear_radius(), HULL_RADIUS + 8.0, 0.001)
	assert_eq(f.launch_velocity(), f.velocity)
	assert_true(f.is_in_group(&"enemies") and f.is_in_group(f.owner_group()), "in enemies and its owner group")
	assert_eq(String(f.owner_group()), "fortress_%d" % f.get_instance_id())


# ══ Movement (t6, plan §2.6; task plan docs/plans/cmwt4y3hk00ssqs2ybengu81w/3-plan.md, whose rows 1-9 the headers follow) ══════════════════════
#
# Hand-ticked with the Carrier's `_tick` (`_physics_process(DT)`, then the position written from the velocity: outside a physics frame
# `move_and_slide()` moves by the idle delta). Expected values (rates, candidates, speeds) are computed here from the shipped config, never by calling
# the brain's own helpers. Open Space spawns at (640, 360); Assault on the hold line (640, 180) unless the row is about the entry.

const DT := 1.0 / 60.0
const Phase := FortressBrain.Phase
## The local bearings of the two sector centres (north 270 degrees = local -y, south 90 = local +y), typed here on purpose.
const NORTH_BEARING := -PI / 2.0
const SOUTH_BEARING := PI / 2.0
const OPEN_SPACE_PLAYER: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const ASSAULT_PLAYER: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")


## A hand-ticked fortress; Open Space ones start engaged unless [param engaged] is false.
func _mover_spawn(h, pos: Vector2 = Vector2.INF, engaged: bool = true) -> SpaceFortress:
	var f := SCENE.instantiate() as SpaceFortress
	(f.get_node("Brain") as FortressBrain).start_engaged = engaged
	if not pos.is_finite():
		pos = Vector2(640.0, SHIPPED.assault_hold_y) if h.is_assault else SPAWN
	f.global_position = pos
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


func _tick(f: SpaceFortress, delta: float = DT) -> void:
	var before := f.global_position
	f._physics_process(delta)
	f.global_position = before + f.velocity * delta


func _brain(f: SpaceFortress) -> FortressBrain:
	return f.get_node("Brain") as FortressBrain


## The mode's facing-rule turn rate, read from the shipped config.
func _turn_rate(h) -> float:
	return SHIPPED.assault_turn_rate if h.is_assault else SHIPPED.turn_rate


## Steps the ladder by scripted kills (synchronous: `destroy()` never checks the lock, and the core is unlocked by hand before its damage).
func _ladder_to(f: SpaceFortress, phase_id: StringName) -> void:
	var order := [&"shields_exposed", &"core_exposed", &"critical"]
	if not order.has(phase_id):
		return
	var driver := f.phase_driver()
	for step in order:
		if order.find(driver.current_id()) >= order.find(step):
			continue
		match step:
			&"shields_exposed":
				_part(f, &"battery_sweep").destroy()
				_part(f, &"battery_artillery").destroy()
			&"core_exposed":
				_part(f, &"shield_north").destroy()
				_part(f, &"shield_south").destroy()
			&"critical":
				var core := _part(f, &"core")
				core.set_vulnerable(true)
				core.hurt_box.received_damage.emit(SHIPPED.core_health - roundi(SHIPPED.critical_core_ratio * SHIPPED.core_health))
		assert_eq(driver.current_id(), step, "sanity: the ladder reached %s" % step)
		if step == phase_id:
			return


## The world bearing [param local] (a local bearing) points along.
func _side_bearing(f: SpaceFortress, local: float) -> float:
	return f.rotation + local


## |angle between [param f]'s [param local] side and the bearing to [param at]|.
func _side_error(f: SpaceFortress, local: float, at: Vector2) -> float:
	return absf(angle_difference(_side_bearing(f, local), (at - f.global_position).angle()))


## The reposition rule, recomputed from the shipped config: the 8 points on the 0.6 x zone circle, those >= `reposition_min_step` from [param old],
## the farthest from [param ahead] (lowest index within 0.001 px).
func _expected_pick(anchor: Vector2, old: Vector2, ahead: Vector2) -> Vector2:
	var best := old
	var best_d := -INF
	for k in 8:
		var c := anchor + Vector2.from_angle(k * TAU / 8.0) * SHIPPED.station_ring_factor * SHIPPED.zone_radius
		if c.distance_to(old) < SHIPPED.reposition_min_step:
			continue
		var d := c.distance_to(ahead)
		if d > best_d + 0.001:
			best = c
			best_d = d
	return best


## The player scene's own top cruise speed (instantiated, never added to the tree).
func _player_speed(mode: String) -> float:
	var p := (ASSAULT_PLAYER if mode == "assault" else OPEN_SPACE_PLAYER).instantiate()
	var speed: float = p.cruise_speed()
	p.free()
	return speed


# ── M1. Open Space idle ─────────────────────────────────────────────────────────────────────────

func test_open_space_idle_holds_the_anchor_spins_and_notices() -> void:
	var h = _world("open_space")
	var f := _mover_spawn(h, SPAWN, false)
	var b := _brain(f)
	h.player.global_position = SPAWN + Vector2(1450.0, 0.0)
	var max_off := 0.0
	var bad_turns := 0
	var left_idle := false
	var rot := f.rotation
	for i in 1200:  # 20 s
		_tick(f)
		max_off = maxf(max_off, f.global_position.distance_to(SPAWN))
		if absf(angle_difference(rot, f.rotation) - SHIPPED.idle_spin_rate * DT) > 1e-6:
			bad_turns += 1
		rot = f.rotation
		left_idle = left_idle or b.phase != Phase.IDLE
	assert_false(left_idle, "a player at 1450 px (beyond perceive_radius 1400) is never noticed")
	assert_lte(max_off, SHIPPED.home_radius, "the anchor is held within home_radius for 20 s")
	assert_eq(bad_turns, 0, "the hub idle spin turns exactly idle_spin_rate per tick")
	assert_false(b.is_engaged(), "idle is not engaged")

	h.player.global_position = f.global_position + Vector2(1390.0, 0.0)
	_tick(f)
	assert_eq(b.phase, Phase.NOTICING, "inside 1400 px: noticing")
	assert_false(b.is_engaged(), "not engaged while noticing")
	var ticks := 1
	while not b.is_engaged() and ticks < 200:
		_tick(f)
		ticks += 1
	var notice := roundi(SHIPPED.notice_time / DT)
	assert_between(ticks, notice, notice + 2, "engaged notice_time after the first tick inside (float accumulation: one tick either way)")
	assert_eq(b.phase, Phase.HOLD, "engaged in batteries = HOLD")


# ── M2. Facing ──────────────────────────────────────────────────────────────────────────────────

## Ticks until [param local]'s side is on [param at] (within 0.01 rad); returns [ticks, per-tick turns that missed the rate on a full step].
func _turn_until_facing(f: SpaceFortress, local: float, at: Vector2, rate: float, limit: int) -> Array:
	var misses := 0
	var ticks := 0
	while _side_error(f, local, at) > 0.01 and ticks < limit:
		var remaining := _side_error(f, local, at)
		var rot := f.rotation
		_tick(f)
		ticks += 1
		if remaining > rate * DT + 1e-4 and absf(absf(angle_difference(rot, f.rotation)) - rate * DT) > 1e-5:
			misses += 1
	return [ticks, misses]


func test_the_strongest_sector_turns_to_the_player_at_exactly_the_turn_rate(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _mover_spawn(h)
	var b := _brain(f)
	var rate := _turn_rate(h)
	var at := f.global_position + Vector2.from_angle(deg_to_rad(30.0)) * 600.0
	h.player.global_position = at
	_part(f, &"battery_spread").destroy()
	_part(f, &"battery_pulse").destroy()
	assert_eq(b.present_side(), FortressBrain.NORTH, "%s: north 2 > south 1" % mode)
	var run := _turn_until_facing(f, NORTH_BEARING, at, rate, 3000)
	assert_lt(run[0], 3000, "%s: the north side reached the player" % mode)
	assert_eq(run[1], 0, "%s: every full step of the turn is exactly the mode's rate (%.2f rad/s)" % [mode, rate])
	assert_gt(run[0], roundi(2.0 / (rate * DT)) - 2, "%s: sanity: a 120 degree turn took as long as the rate allows" % mode)

	_part(f, &"battery_artillery").destroy()
	_part(f, &"battery_missiles").destroy()
	assert_eq(b.present_side(), FortressBrain.SOUTH, "%s: both north batteries lost: north 0 < south 1, the weak side changes" % mode)
	run = _turn_until_facing(f, SOUTH_BEARING, at, rate, 3000)
	assert_lt(run[0], 3000, "%s: the south side reached the player" % mode)
	assert_eq(run[1], 0, "%s: the 180 degree turn runs at exactly the rate" % mode)


func test_sector_strength_halving_and_ties(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _mover_spawn(h)
	assert_eq(_brain(f).present_side(), FortressBrain.SOUTH, "%s: start: south 3 vs north 2" % mode)

	var g := _mover_spawn(h, SPAWN + Vector2(0.0, 900.0))
	_part(g, &"shield_south").destroy()
	assert_almost_eq(_brain(g).sector_strength(FortressBrain.SOUTH), 1.5, 0.0001, "%s: a dead generator halves its sector" % mode)
	assert_eq(_brain(g).present_side(), FortressBrain.NORTH, "%s: halving flips the side (south 1.5 < north 2)" % mode)

	var a := _mover_spawn(h, SPAWN + Vector2(0.0, 1800.0))
	assert_eq(_brain(a).present_side(), FortressBrain.SOUTH)
	_part(a, &"battery_spread").destroy()
	assert_eq(_brain(a).present_side(), FortressBrain.SOUTH, "%s: a 2 vs 2 tie keeps south" % mode)

	var n := _mover_spawn(h, SPAWN + Vector2(0.0, 2700.0))
	_part(n, &"battery_spread").destroy()
	_part(n, &"battery_pulse").destroy()
	assert_eq(_brain(n).present_side(), FortressBrain.NORTH, "%s: north 2 > south 1" % mode)
	_part(n, &"shield_north").destroy()
	assert_almost_eq(_brain(n).sector_strength(FortressBrain.NORTH), 1.0, 0.0001)
	assert_eq(_brain(n).present_side(), FortressBrain.NORTH, "%s: a 1.0 vs 1.0 tie keeps north" % mode)


## Circles the player round [param f] at 500 px and [param omega] rad/s for [param ticks], from the presented (south) side; the side errors every
## 0.5 s.
func _circle(h, f: SpaceFortress, omega: float, ticks: int) -> Array[float]:
	var c := f.global_position
	var a := SOUTH_BEARING
	var errors: Array[float] = []
	for i in ticks:
		a += omega * DT
		h.player.global_position = c + Vector2.from_angle(a) * 500.0
		h.player.velocity = Vector2.from_angle(a + PI / 2.0) * omega * 500.0
		_tick(f)
		if (i + 1) % 30 == 0:
			errors.append(_side_error(f, SOUTH_BEARING, h.player.global_position))
	return errors


func test_circling_out_turns_the_fortress(mode: String = use_parameters(MODES)) -> void:
	var speed := _player_speed(mode)
	var h = _world(mode)
	var rate := _turn_rate(h)
	assert_gt(speed, 0.0, "%s: the player scene's cruise speed was read" % mode)
	assert_lt(rate * 500.0, 0.5 * speed, "%s: the turn rate at 500 px is under half the player's speed (%.0f px/s)" % [mode, speed])
	var f := _mover_spawn(h)
	var errors := _circle(h, f, speed / 500.0, 240)
	for i in range(1, errors.size()):
		assert_gt(errors[i], errors[i - 1], "%s: the angle to the presented side grows (sample %d: %s)" % [mode, i, errors])
	assert_gt(errors[-1], 1.5, "%s: after 4 s the player is on the flank (%.2f rad)" % [mode, errors[-1]])

	var g := _mover_spawn(h, f.global_position + Vector2(0.0, 2000.0))
	var slow := _circle(h, g, 0.5 * rate, 240)
	assert_lt(slow.max(), 0.1, "%s: boundary: a player circling at half the turn rate never gets round (%s)" % [mode, slow])


# ── M3. Translation by phase ────────────────────────────────────────────────────────────────────

func test_no_translation_while_batteries_or_shields_hold(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _mover_spawn(h)
	var b := _brain(f)
	var x0 := f.global_position.x
	var c := f.global_position
	var worst := 0.0
	for step in [&"batteries", &"shields_exposed"]:
		_ladder_to(f, step)
		for i in 600:
			h.player.global_position = c + Vector2.from_angle(i * 0.01) * 700.0
			_tick(f)
			if h.is_assault:
				worst = maxf(worst, maxf(absf(f.global_position.x - x0), absf(f.global_position.y - SHIPPED.assault_hold_y)))
			else:
				worst = maxf(worst, f.global_position.distance_to(b.station_point()))
		assert_eq(b.phase, Phase.HOLD, "%s %s: HOLD" % [mode, step])
	if h.is_assault:
		assert_lte(worst, 1.0, "assault: held at (anchor x, hold y) within 1 px")
	else:
		assert_lte(worst, SHIPPED.hold_tolerance, "open_space: within hold_tolerance of the station point")
		assert_eq(b.station_point(), c, "open_space: the station point is the anchor")


func test_open_space_repositions_by_the_rule_inside_the_zone() -> void:
	var h = _world("open_space")
	var f := _mover_spawn(h)
	var b := _brain(f)
	var anchor := f.global_position
	_ladder_to(f, &"core_exposed")
	var p := anchor + Vector2(900.0, 0.0)
	var picks := 0
	var worst_zone := 0.0
	var mismatches: Array = []
	for i in 3600:  # 60 s, a chasing stub
		var to_f := f.global_position - p
		var v := to_f.normalized() * 300.0 if to_f.length() > 300.0 else Vector2.ZERO
		h.player.global_position = p
		h.player.velocity = v
		var old := b.station_point()
		var ahead := p + v * SHIPPED.reposition_lookahead
		_tick(f)
		p += v * DT
		worst_zone = maxf(worst_zone, f.global_position.distance_to(anchor))
		if b.station_point() != old:
			picks += 1
			var expected := _expected_pick(anchor, old, ahead)
			if b.station_point().distance_to(expected) > 0.01:
				mismatches.append([i, b.station_point(), expected])
			assert_gte(b.station_point().distance_to(old), SHIPPED.reposition_min_step, "a new point is >= 250 px from the old one")
			assert_lte(b.station_point().distance_to(anchor), SHIPPED.zone_radius, "a new point lies inside the zone")
	assert_eq(mismatches, [], "every station point is the rule's own pick")
	assert_eq(picks, 8, "one pick at entry and one every reposition_period over 60 s")
	assert_lte(worst_zone, SHIPPED.zone_radius, "the hull never leaves the zone")
	assert_eq(b.phase, Phase.REPOSITION)


func test_the_pick_can_be_nearer_the_player_and_critical_repositions_faster() -> void:
	var h = _world("open_space")
	var f := _mover_spawn(h)
	var b := _brain(f)
	var anchor := f.global_position
	var p := anchor + Vector2(900.0, 0.0)
	h.player.global_position = p
	h.player.velocity = Vector2.ZERO
	_ladder_to(f, &"core_exposed")
	_tick(f)
	var farthest := _expected_pick(anchor, anchor, p)
	assert_eq(b.station_point(), farthest, "sanity: the first pick is the farthest candidate")
	var period := roundi(SHIPPED.reposition_period / DT)
	for i in period:
		_tick(f)
	var second := b.station_point()
	assert_ne(second, farthest, "a second pick")
	assert_almost_eq(second.distance_to(_expected_pick(anchor, farthest, p)), 0.0, 0.01, "boundary: the rule's pick")
	assert_lt(second.distance_to(p), farthest.distance_to(p), "boundary: from the farthest point the winner is nearer the player")

	_ladder_to(f, &"critical")
	var changes: Array[int] = []
	var bad_speed: Array = []
	var old := b.station_point()
	for i in 1000:
		_tick(f)
		if b.station_point() != old:
			changes.append(i)
			old = b.station_point()
		if b.is_travelling() and absf(f.velocity.length() - SHIPPED.critical_reposition_speed) > 0.01:
			bad_speed.append([i, f.velocity.length()])
	assert_eq(changes.size(), 4, "critical: a pick at entry, then every 5 s (%s)" % [changes])
	for k in range(1, changes.size()):
		assert_between(changes[k] - changes[k - 1], 299, 301, "critical picks 300 +/- 1 ticks apart")
	assert_eq(bad_speed, [], "critical travels at critical_reposition_speed")


# ── M4. Leash ───────────────────────────────────────────────────────────────────────────────────

func test_open_space_leash_returns_home_keeping_the_boss_phase() -> void:
	var h = _world("open_space")
	var f := _mover_spawn(h, SPAWN, false)
	var b := _brain(f)
	h.player.global_position = SPAWN + Vector2(1000.0, 0.0)
	for i in 80:
		_tick(f)
	assert_true(b.is_engaged(), "sanity: engaged")
	_ladder_to(f, &"core_exposed")
	for i in 180:
		_tick(f)
	assert_gt(f.global_position.distance_to(SPAWN), 100.0, "sanity: a reposition moved it off the anchor")
	var phase_id := f.phase_driver().current_id()
	h.player.global_position = SPAWN + Vector2(3400.0, 0.0)
	_tick(f)
	assert_eq(b.phase, Phase.RETURNING, "beyond lose_radius: returning")
	var engaged_returning := false
	var ticks := 0
	while b.phase == Phase.RETURNING and ticks < 900:
		_tick(f)
		ticks += 1
		engaged_returning = engaged_returning or b.is_engaged()
	assert_false(engaged_returning, "not engaged while returning")
	assert_eq(b.phase, Phase.IDLE, "home: idle")
	assert_lte(f.global_position.distance_to(SPAWN), SHIPPED.home_radius, "within home_radius of the anchor")
	assert_eq(b.station_point(), SPAWN, "the station point is the anchor again")
	assert_eq(f.phase_driver().current_id(), phase_id, "the boss phase is kept")


# ── M5. Assault ─────────────────────────────────────────────────────────────────────────────────

func test_assault_enters_holds_bobs_and_never_moves_x() -> void:
	var h = _world("assault")
	h.player.global_position = Vector2(640.0, 600.0)
	var f := _mover_spawn(h, Vector2(640.0, -260.0))
	var b := _brain(f)
	var x0 := f.global_position.x
	var bad_enter := 0
	var ticks := 0
	_tick(f)
	assert_eq(b.phase, Phase.ENTER, "above the hold line: entering")
	assert_false(b.is_engaged(), "entering is not engaged")
	while b.phase == Phase.ENTER and ticks < 600:
		if absf(f.velocity.y - SHIPPED.assault_enter_speed) > 0.001:
			bad_enter += 1
		_tick(f)
		ticks += 1
	assert_eq(bad_enter, 0, "it enters at assault_enter_speed")
	assert_eq(b.phase, Phase.HOLD, "then holds")
	for i in 30:
		_tick(f)
	assert_almost_eq(f.global_position.y, SHIPPED.assault_hold_y, 1.0, "at the hold line")

	var worst_x := 0.0
	var y_min := INF
	var y_max := -INF
	for step in [&"batteries", &"shields_exposed", &"core_exposed", &"critical"]:
		if step == &"shields_exposed":
			# The player below: killing two south batteries presents north, which turns the long way round at the Assault rate.
			_part(f, &"battery_spread").destroy()
			_part(f, &"battery_pulse").destroy()
			assert_eq(b.present_side(), FortressBrain.NORTH, "the side changes when the south sector weakens")
		else:
			_ladder_to(f, step)
		var max_turn := 0.0
		for i in 900:  # 15 s per phase, 60 s in all
			var rot := f.rotation
			_tick(f)
			max_turn = maxf(max_turn, absf(angle_difference(rot, f.rotation)))
			worst_x = maxf(worst_x, absf(f.global_position.x - x0))
			if step == &"core_exposed" or step == &"critical":
				y_min = minf(y_min, f.global_position.y)
				y_max = maxf(y_max, f.global_position.y)
		if step == &"shields_exposed":
			assert_lt(_side_error(f, NORTH_BEARING, h.player.global_position), 0.01, "the north side was turned to the player")
			assert_lte(max_turn, SHIPPED.assault_turn_rate * DT + 1e-6, "at most the Assault turn rate")
		elif step == &"batteries":
			assert_lt(_side_error(f, SOUTH_BEARING, h.player.global_position), 0.01, "batteries: the south side faces the player")
	assert_lte(worst_x, 1.0, "x never moves (60 s, every phase)")
	var top := SHIPPED.assault_hold_y - SHIPPED.assault_bob_amplitude
	var bottom := SHIPPED.assault_hold_y + SHIPPED.assault_bob_amplitude
	assert_gte(y_min, top - 0.01, "the bob stays at or below its top")
	assert_lte(y_max, bottom + 0.01, "and at or above its bottom")
	assert_lt(y_min, top + 0.5, "it reaches the top")
	assert_gt(y_max, bottom - 0.5, "and the bottom")
	assert_eq(b.phase, Phase.REPOSITION, "bobbing is REPOSITION")

	f.global_position.x = x0 + 30.0
	var worst_vx := 0.0
	for i in 180:
		_tick(f)
		worst_vx = maxf(worst_vx, absf(f.velocity.x))
	assert_lte(worst_vx, SHIPPED.assault_x_correct_speed + 0.001, "the x correction is at most assault_x_correct_speed")
	assert_gt(worst_vx, SHIPPED.assault_x_correct_speed - 0.001, "and it ran")
	assert_almost_eq(f.global_position.x, x0, 1.0, "back on the anchored x")


# ── M6. Spins ───────────────────────────────────────────────────────────────────────────────────

## [param n] ticks; the per-tick signed turns.
func _turns(f: SpaceFortress, n: int, h = null) -> Array[float]:
	var out: Array[float] = []
	for i in n:
		if h != null:
			h.player.global_position = f.global_position + Vector2.from_angle(i * 0.05) * 600.0
		var rot := f.rotation
		_tick(f)
		out.append(angle_difference(rot, f.rotation))
	return out


func _all_near(values: Array[float], expected: float) -> bool:
	return values.all(func(x: float) -> bool: return absf(x - expected) < 1e-6)


func test_spins_volley_alternating_and_critical_continuous(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _mover_spawn(h)
	var b := _brain(f)
	assert_eq((f.get_node("EnemyMover") as EnemyMover).turn_lerp, 0.0, "%s: the fortress mover's turn_lerp is 0 (the cap alone sets the rate)" % mode)
	_ladder_to(f, &"shields_exposed")
	_tick(f)
	b.begin_spin()
	assert_eq(b.spin_direction(), 1, "%s: the first volley spin is +1" % mode)
	assert_true(_all_near(_turns(f, 60), SHIPPED.beam_spin_rate * DT), "%s: a volley spin turns at beam_spin_rate" % mode)
	b.end_spin()
	b.begin_spin()
	assert_eq(b.spin_direction(), -1, "%s: the next one turns the other way" % mode)
	assert_true(_all_near(_turns(f, 60), -SHIPPED.beam_spin_rate * DT), "%s: at the same rate" % mode)
	b.end_spin()
	assert_false(b.spinning(), "%s: end_spin returns to the facing rule" % mode)
	var after := _turns(f, 60)
	assert_true(after.all(func(x: float) -> bool: return absf(x) <= _turn_rate(h) * DT + 1e-6), "%s: at the facing rule's rate" % mode)

	_ladder_to(f, &"critical")
	var crit := _turns(f, 180, h)
	var sign_ := signf(crit[0])
	assert_true(_all_near(crit, sign_ * SHIPPED.critical_spin_rate * DT), "%s: critical spins continuously at critical_spin_rate, whatever the player does" % mode)
	assert_true(b.spinning(), "%s: spinning" % mode)

	var g := _mover_spawn(h, f.global_position + Vector2(0.0, 2000.0))
	(g.get_node("EnemyMover") as EnemyMover).turn_lerp = 0.3
	_ladder_to(g, &"shields_exposed")
	_tick(g)
	_brain(g).begin_spin()
	var lerped := _turns(g, 60)
	var mean: float = lerped.reduce(func(acc: float, x: float) -> float: return acc + x, 0.0) / (60.0 * DT)
	assert_almost_eq(mean, 0.3, 0.02, "%s: boundary: with turn_lerp 0.3 the spin turns at ~0.3 rad/s, not 0.5 (the lerp runs before the cap)" % mode)


# ── M7. EMP ─────────────────────────────────────────────────────────────────────────────────────

func test_emp_stops_motion_and_rotation_for_the_window(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.global_position = Vector2(640.0, 1000.0)
	var f := _mover_spawn(h)
	var b := _brain(f)
	_ladder_to(f, &"core_exposed")
	b.begin_spin()
	for i in 30:
		_tick(f)
	assert_gt(f.velocity.length(), 1.0, "%s: sanity: under way" % mode)
	f.apply_emp(5.0, null)
	var pos := f.global_position
	var rot := f.rotation
	var moved := 0
	var ticks := 0
	while f.is_emp_disrupted() and ticks < 400:
		_tick(f)
		ticks += 1
		# The tick the window ends resumes the brain in the same call (the base rule): only ticks still inside it count.
		if f.is_emp_disrupted() and (f.global_position.distance_to(pos) > 1e-4 or absf(angle_difference(rot, f.rotation)) > 1e-5):  # writing the position re-derives rotation from the float32 basis (~3e-8)
			moved += 1
	assert_between(ticks, 119, 121, "%s: the 2 s window (5 s x emp_factor)" % mode)
	assert_eq(moved, 0, "%s: no motion and no rotation for the window" % mode)
	for i in 10:
		_tick(f)
	assert_ne(f.global_position, pos, "%s: it moves again after the window" % mode)
	assert_ne(f.rotation, rot, "%s: and turns again" % mode)


# ── M9. Thrusters ───────────────────────────────────────────────────────────────────────────────

func test_thrusters_burn_while_travelling_without_touching_the_snapshot(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _mover_spawn(h, Vector2(640.0, -260.0) if h.is_assault else SPAWN)
	var b := _brain(f)
	var thrusters := f.get_node("Thrusters") as CanvasItem
	_tick(f)
	if h.is_assault:
		assert_eq(b.phase, Phase.ENTER)
		assert_eq(thrusters.modulate.a, 1.0, "assault: full while entering")
		while b.phase == Phase.ENTER:
			_tick(f)
	_tick(f)
	assert_eq(b.phase, Phase.HOLD)
	assert_almost_eq(thrusters.modulate.a, FortressBrain.THRUSTER_IDLE_ALPHA, 0.0001, "%s: dimmed while holding" % mode)
	_ladder_to(f, &"core_exposed")
	var visible_before := thrusters.visible
	_tick(f)
	assert_true(b.is_travelling(), "%s: under way (reposition / bob)" % mode)
	assert_eq(thrusters.modulate.a, 1.0, "%s: full while travelling" % mode)
	if not h.is_assault:
		var ticks := 0
		while b.is_travelling() and ticks < 900:
			_tick(f)
			ticks += 1
		assert_false(b.is_travelling(), "open_space: arrived")
		assert_almost_eq(thrusters.modulate.a, FortressBrain.THRUSTER_IDLE_ALPHA, 0.0001, "open_space: dimmed once held")
	assert_eq(thrusters.visible, visible_before, "%s: travel never changes Thrusters.visible (the snapshot's)" % mode)
	assert_true(thrusters.visible, "%s: shown from core_exposed" % mode)
