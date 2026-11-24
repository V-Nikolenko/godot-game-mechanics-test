## The Space Fortress batteries: five distinct guns firing diagonal crossfire from the corners, never more than two attacking at once, each lane going quiet
## when its battery dies (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.7.1, §2.7.5 mount half, rows §2.7.7 A; Phase 11 t7). Intent tests, every row in
## both harnesses (IDEAS §40). t16 appends the geometry-weapon rows (spokes, ring pulse, core ring, fairness, density) to this file.
##
## Hand-ticked: the fortress's own physics is off and the BRAIN is ticked (`_brain(f).tick(DT)`), so the hull never turns (the facing rule is the mover's
## and the mover is not stepped) and a bearing in a row is the bearing the part table gives. Rounds are never given a physics step, so a fired round is
## returned to its pool by the row at its own `max_time` (`_expire`): that is what keeps a pool's count honest. Local bearing 0 degrees = +x, 90 = +y.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
const SHIPPED: SpaceFortressConfig = preload("res://assault/scenes/enemies/space_fortress/space_fortress_config.tres")  # read only
const Variant := TurretMount.Variant
const Phase := TurretMount.Phase

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const SPAWN := Vector2(640.0, 360.0)
## (id, variant, rest bearing, traverse, part centre) in module order: the order the builder indexes the pools in (§2.5.2).
const BATTERIES := [
	[&"battery_spread", Variant.SPREAD_CANNON, 45.0, 100.0, Vector2(99, 99)],
	[&"battery_pulse", Variant.RAPID_PULSE, 135.0, 100.0, Vector2(-99, 99)],
	[&"battery_artillery", Variant.HEAVY_CANNON, 225.0, 100.0, Vector2(-99, -99)],
	[&"battery_missiles", Variant.ROCKET_BATTERY, 315.0, 100.0, Vector2(99, -99)],
	[&"battery_sweep", Variant.SWEEP_BEAM, 0.0, 140.0, Vector2(150, 0)],
]
## The corner diagonals and a player 300 px out on each: inside only that corner's arc (the sweep's 140 degrees about +x stops short of all four).
const DIAGONALS := [[&"battery_spread", 45.0], [&"battery_pulse", 135.0], [&"battery_artillery", 225.0], [&"battery_missiles", 315.0]]

var _roots: Array[Node] = []


func after_each() -> void:
	_restore_clock()
	_roots.clear()


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


## An engaged fortress (the hold line in Assault, the spawn point in Open Space), physics off. [param props] are written on its private config copy.
func _spawn(h, props: Dictionary = {}, pos: Vector2 = Vector2.INF, engaged: bool = true) -> SpaceFortress:
	var f := SCENE.instantiate() as SpaceFortress
	f.config.escort_cap_open_space = 0  # quiet bays (t8): the density and weapon rows measure the fortress, not the escorts a lost battery would call
	f.config.escort_cap_assault = 0
	for key in props:
		f.config.set(key, props[key])
	(f.get_node("Brain") as FortressBrain).start_engaged = engaged
	if not pos.is_finite():
		pos = Vector2(640.0, SHIPPED.assault_hold_y) if h.is_assault else SPAWN
	f.global_position = pos
	h.root.add_child(f)
	f.set_physics_process(false)
	return f


func _brain(f: SpaceFortress) -> FortressBrain:
	return f.get_node("Brain") as FortressBrain


func _mount(f: SpaceFortress, id: StringName) -> TurretMount:
	return f.modular_hull().mounts_of(id)[0]


## Puts the player [param dist] px from the hull centre along the local bearing [param local_deg] (the hull has not turned).
func _stub(h, f: SpaceFortress, local_deg: float, dist: float) -> void:
	h.player.global_position = f.global_position + Vector2.from_angle(f.rotation + deg_to_rad(local_deg)) * dist
	h.player.velocity = Vector2.ZERO


## Widens every battery's arc to a full circle on the INSTANCED mounts (never the scene), so every gun wants the same target at once.
func _open_arcs(f: SpaceFortress) -> void:
	for b in BATTERIES:
		_mount(f, b[0]).traverse_deg = 360.0


func _life(round_node: Node) -> float:
	if round_node is EnemyRocket:
		return (round_node as EnemyRocket).max_time
	var lifetime := round_node.get_node_or_null(^"ProjectileLifetime")
	return float(lifetime.max_time) if lifetime != null else 18.0


## Counters for one fortress: telegraphs and rounds per battery id, the rounds in flight with the sim time they expire at, and the sim clock.
func _watch(f: SpaceFortress) -> Dictionary:
	var rec := {"tele": {}, "rounds": {}, "live": [], "t": 0.0, "core_seen": {}, "core_rounds": 0}
	for b in BATTERIES:
		var id: StringName = b[0]
		rec["tele"][id] = 0
		rec["rounds"][id] = 0
		var mount := _mount(f, id)
		mount.phase_changed.connect(func(p: int) -> void:
			if p == Phase.TELEGRAPH:
				rec["tele"][id] += 1)
		mount.round_fired.connect(func(r: Node2D) -> void:
			rec["rounds"][id] += 1
			rec["live"].append([r, rec["t"] + _life(r)]))
	return rec


func _total(rec: Dictionary, key: String) -> int:
	var n := 0
	for id in rec[key]:
		n += int(rec[key][id])
	return n


## The core ring's round life: min(`max_time`, `max_distance` / `core_ring_speed`), read off `enemy_bullet.tscn` the way the root sizes its pool (t16).
func _core_life() -> float:
	var scene := SpaceFortress.CORE_RING_ROUND
	var max_time := float(EnemyBeamScenes.export_of_scene(scene, &"max_time", 18.0, ^"ProjectileLifetime"))
	var max_distance := float(EnemyBeamScenes.export_of_scene(scene, &"max_distance", 2400.0, ^"ProjectileLifetime"))
	return minf(max_time, max_distance / SHIPPED.core_ring_speed)


## Records every core-ring round launched since the last call (they come from no mount, so `round_fired` never sees them) with its expiry (t16).
func _track_core(f: SpaceFortress, rec: Dictionary) -> void:
	var pool := f.core_ring_pool()
	if pool == null:
		return
	var seen: Dictionary = rec["core_seen"]
	for round_node in pool._active:
		if not seen.has(round_node):
			seen[round_node] = true
			rec["core_rounds"] += 1
			rec["live"].append([round_node, rec["t"] + _core_life()])


## Returns every round whose life is over to its pool at once (the real round does this on its own physics step, which a hand-ticked row never runs).
func _expire(f: SpaceFortress, rec: Dictionary) -> void:
	_track_core(f, rec)
	var live: Array = rec["live"]
	for i in range(live.size() - 1, -1, -1):
		if rec["t"] < float(live[i][1]):
			continue
		var round_node: Node = live[i][0]
		live.remove_at(i)
		rec["core_seen"].erase(round_node)
		if not is_instance_valid(round_node):
			continue
		round_node.expired.emit()
		for child in f.get_children():
			if child is BulletPool:
				(child as BulletPool)._recycle(round_node)


## [param seconds] of brain ticks of [param step] s; [param until] (a Callable returning bool) ends it early once true.
func _run(f: SpaceFortress, rec: Dictionary, seconds: float, until: Callable = Callable(), step: float = DT) -> void:
	for i in int(round(seconds / step)):
		_brain(f).tick(step)
		rec["t"] += step
		_expire(f, rec)
		if until.is_valid() and until.call():
			return


func _attacking(f: SpaceFortress) -> int:
	var n := 0
	for b in BATTERIES:
		var p := _mount(f, b[0]).phase()
		if p == Phase.TELEGRAPH or p == Phase.FIRE:
			n += 1
	return n


func _all_in_phase(f: SpaceFortress, phase: int) -> bool:
	for b in BATTERIES:
		if _mount(f, b[0]).phase() != phase:
			return false
	return true


## Steps the ladder by scripted kills to [param phase_id] (synchronous).
func _ladder_to(f: SpaceFortress, phase_id: StringName) -> void:
	var order := [&"shields_exposed", &"core_exposed", &"critical"]
	var driver := f.phase_driver()
	for step in order:
		if order.find(driver.current_id()) >= order.find(step):
			if step == phase_id:
				return  # already there (the density row enters shields_exposed by its own kills)
			continue
		match step:
			&"shields_exposed":
				f.part(&"battery_sweep").destroy()
				f.part(&"battery_artillery").destroy()
			&"core_exposed":
				f.part(&"shield_north").destroy()
				f.part(&"shield_south").destroy()
			&"critical":
				var core := f.part(&"core")
				core.set_vulnerable(true)
				core.hurt_box.received_damage.emit(SHIPPED.core_health - roundi(SHIPPED.critical_core_ratio * SHIPPED.core_health))
		if step == phase_id:
			return


## The pool size a burst mount of [param variant] needs at [param factor] x its period, from the scene's authored exports (never typed, never the mount's own spec).
func _burst_pool_size(variant: int, factor: float) -> int:
	var burst := int(TurretMountScenes.export_of(variant, &"burst_count", 4))
	var pellets := int(TurretMountScenes.export_of(variant, &"pellets", 1))
	var gap := float(TurretMountScenes.export_of(variant, &"burst_gap", 0.12))
	var charge := float(TurretMountScenes.export_of(variant, &"charge_seconds", 0.4))
	var cooldown := float(TurretMountScenes.export_of(variant, &"cooldown_seconds", 2.2))
	var round_scene := TurretMountScenes.export_of(variant, &"round_scene", EnemyRounds.PULSE) as PackedScene
	var max_time := float(EnemyBeamScenes.export_of_scene(round_scene, &"max_time", 18.0, ^"ProjectileLifetime"))
	return EnemyRounds.pool_size_for(burst * pellets, max_time, (charge + (burst - 1) * gap + cooldown) * factor)


func _rocket_pool_size(kind: EnemyRocket.Kind, factor: float) -> int:
	var count := int(TurretMountScenes.export_of(Variant.ROCKET_BATTERY, &"salvo_count", 2))
	var gap := float(TurretMountScenes.export_of(Variant.ROCKET_BATTERY, &"salvo_gap", 0.35))
	var charge := float(TurretMountScenes.export_of(Variant.ROCKET_BATTERY, &"charge_seconds", 0.5))
	var cooldown := float(TurretMountScenes.export_of(Variant.ROCKET_BATTERY, &"cooldown_seconds", 2.2))
	return EnemyRocketScenes.pool_size_for(kind, {"salvo_count": count, "warhead_salvo_count": 0, "salvo_period_min": (charge + (count - 1) * gap + cooldown) * factor})


# ══ 1. The five mounts and the gate ═════════════════════════════════════════════════════════════

func test_five_battery_mounts_as_built_with_root_child_pools_and_one_unbound_gate(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var brain := _brain(f)
	var index := 0
	for b in BATTERIES:
		var id: StringName = b[0]
		assert_eq(f.modular_hull().mounts_of(id).size(), 1, "%s: %s carries one mount" % [mode, id])
		var mount := _mount(f, id)
		assert_eq(mount.scene_file_path, TurretMountScenes.scene_for(b[1]).resource_path, "%s: %s is the %d variant" % [mode, id, b[1]])
		assert_eq(mount.rest_bearing_deg, b[2], "%s: %s rest bearing" % [mode, id])
		assert_eq(mount.traverse_deg, b[3], "%s: %s traverse" % [mode, id])
		assert_eq(mount.global_position, f.global_position + (b[4] as Vector2), "%s: %s sits on its part" % [mode, id])
		assert_eq(mount.telegraph_gate, brain.attack_gate, "%s: %s holds the fortress's gate" % [mode, id])
		assert_eq(mount.telegraph_gate.get_argument_count(), 0, "%s: the gate takes no argument" % mode)
		for spec in mount.pool_specs():
			var pool := f.get_node_or_null("%s_%d" % [spec["name"], index]) as BulletPool
			assert_not_null(pool, "%s: %s's %s pool is a root child of the fortress" % [mode, id, spec["name"]])
			if pool != null:
				assert_eq(pool.get_parent(), f)
				assert_eq(pool.get_parent().get_parent(), h.root, "%s: its container is the fortress's parent" % mode)
				assert_eq(pool.pool_size, int(spec["size"]), "%s: %s pool size is the mount's own spec" % [mode, id])
		index += 1
	assert_true(brain.attack_gate.call(), "%s: with nothing attacking the gate is open" % mode)
	assert_eq(f.modular_hull().destroyed_count([EnemyModule.Role.WEAPON]), 0)


## [param label] "batteries" (cap 2) or "critical" (cap 3, entered through the brain's own boss-phase hook so all five stay alive).
func _gate_peak(h, label: String, gated: bool) -> Dictionary:
	var f := _spawn(h)
	_open_arcs(f)
	_stub(h, f, 90.0, 250.0)
	var brain := _brain(f)
	if label == "critical":
		brain.on_boss_phase(&"critical")
	var asked := [0]
	for b in BATTERIES:
		var mount := _mount(f, b[0])
		if gated:
			mount.telegraph_gate = func() -> bool:
				asked[0] += 1
				return brain.attack_gate()
		else:
			mount.telegraph_gate = Callable()
	var rec := _watch(f)
	var peak := 0
	var over := 0
	var cap := SHIPPED.critical_max_concurrent_attacks if label == "critical" else SHIPPED.max_concurrent_attacks
	for i in 600:
		brain.tick(DT)
		rec["t"] += DT
		_expire(f, rec)
		var n := _attacking(f)
		peak = maxi(peak, n)
		if n > cap:
			over += 1
	return {"peak": peak, "over": over, "asked": asked[0], "tele": _total(rec, "tele"), "cap": cap}


func test_the_gate_never_lets_a_third_mount_telegraph_and_critical_a_fourth(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var gated := _gate_peak(h, "batteries", true)
	assert_gt(gated["asked"], 0, "%s: a real TRACK -> TELEGRAPH asks the gate through telegraph_gate.call()" % mode)
	assert_eq(gated["peak"], 2, "%s: two mounts attack at once and never a third" % mode)
	assert_eq(gated["over"], 0)
	assert_gte(gated["tele"], 5, "%s: the gate delays, it does not silence (every gun still telegraphs)" % mode)

	var crit := _gate_peak(h, "critical", true)
	assert_eq(crit["peak"], 3, "%s: critical allows three at once and never a fourth" % mode)
	assert_eq(crit["over"], 0)

	var free := _gate_peak(h, "batteries", false)
	assert_gt(free["peak"], 2, "%s: boundary: with no gate five guns would attack together (the gate is what holds it at 2)" % mode)


# ══ 2. Crossfire and dead lanes ═════════════════════════════════════════════════════════════════

func test_each_diagonal_is_fired_on_by_its_corner_only_and_goes_quiet_when_it_dies(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	for diag in DIAGONALS:
		var corner: StringName = diag[0]
		var f := _spawn(h)
		_stub(h, f, diag[1], 300.0)
		var rec := _watch(f)
		_run(f, rec, 10.0, func() -> bool: return rec["tele"][corner] > 0 and rec["rounds"][corner] > 0)
		assert_gt(rec["tele"][corner], 0, "%s: %s fires on its own diagonal" % [mode, corner])
		assert_gt(rec["rounds"][corner], 0, "%s: %s launches rounds on it" % [mode, corner])
		for b in BATTERIES:
			if b[0] != corner:
				assert_eq(rec["tele"][b[0]], 0, "%s: %s never fires on %s's diagonal" % [mode, b[0], corner])
		f.part(corner).destroy()
		var after := _watch(f)
		_run(f, after, 20.0, Callable(), 0.05)  # a coarser step: the dead lane is quiet at any step, and 20 s at 1/60 s is the row's dominant cost
		assert_eq(_total(after, "tele"), 0, "%s: with %s dead nothing telegraphs at its bearing for 20 s" % [mode, corner])
		assert_eq(_total(after, "rounds"), 0, "%s: and no round leaves" % mode)
		assert_eq(_mount(f, corner).phase(), Phase.UNPOWERED, "%s: the dead battery's mount is unpowered" % mode)
		f.queue_free()
		await get_tree().process_frame


# ══ 3. When the guns may fire ═══════════════════════════════════════════════════════════════════

func _tick_full(f: SpaceFortress, rec: Dictionary) -> void:
	var before := f.global_position
	f._physics_process(DT)
	f.global_position = before + f.velocity * DT
	rec["t"] += DT
	_expire(f, rec)


func test_assault_fires_nothing_until_enter_ends() -> void:
	var h = _world("assault")
	var f := _spawn(h, {}, Vector2(640.0, 40.0), false)
	h.player.global_position = Vector2(640.0 + 212.0, 180.0 + 212.0)  # the spread cannon's diagonal (straight south lies between two arcs)
	var rec := _watch(f)
	var brain := _brain(f)
	var ticks := 0
	while brain.phase != FortressBrain.Phase.HOLD and ticks < 400:
		_tick_full(f, rec)
		ticks += 1
		assert_true(_all_in_phase(f, Phase.SCAN) or brain.phase == FortressBrain.Phase.HOLD, "scanning while it descends")
	assert_eq(brain.phase, FortressBrain.Phase.HOLD, "sanity: the descent ended")
	assert_gt(ticks, 60, "sanity: the descent took a while")
	assert_eq(_total(rec, "tele"), 0, "nothing telegraphed during ENTER")
	_stub(h, f, 45.0, 300.0)  # the spread cannon's diagonal (straight south lies between two arcs)
	for i in 900:
		_tick_full(f, rec)
		if _total(rec, "tele") > 0:
			break
	assert_gt(_total(rec, "tele"), 0, "control: once on the hold line it fires")


func test_open_space_fires_nothing_while_idle_noticing_or_returning() -> void:
	var h = _world("open_space")
	var f := _spawn(h, {}, Vector2.INF, false)
	_stub(h, f, 45.0, 300.0)
	var rec := _watch(f)
	var brain := _brain(f)
	var ticks := 0
	var saw_noticing := false
	var tele_unengaged := 0
	while brain.phase != FortressBrain.Phase.HOLD and ticks < 400:
		_tick_full(f, rec)
		ticks += 1
		saw_noticing = saw_noticing or brain.phase == FortressBrain.Phase.NOTICING
		if brain.phase != FortressBrain.Phase.HOLD:
			assert_true(_all_in_phase(f, Phase.SCAN), "every mount scans in brain phase %d" % brain.phase)
			# Only ticks that end unengaged count: the tick that enters HOLD ticks the mounts engaged, and a mount whose (random) scan already
			# points at the player may telegraph on it (t16: this row flaked on exactly that).
			tele_unengaged = _total(rec, "tele")
	assert_true(saw_noticing, "sanity: it noticed the player first")
	assert_eq(tele_unengaged, 0, "nothing telegraphed while idle or noticing")
	for i in 900:
		_tick_full(f, rec)
		if _total(rec, "tele") > 0:
			break
	assert_gt(_total(rec, "tele"), 0, "control: engaged, it fires")
	# The player leaves the leash: RETURNING, every mount back to SCAN, nothing new.
	var before := _total(rec, "tele")
	h.player.global_position = f.global_position + Vector2(SHIPPED.lose_radius + 400.0, 0.0)
	_tick_full(f, rec)
	assert_eq(brain.phase, FortressBrain.Phase.RETURNING, "sanity: beyond the leash it heads home")
	assert_true(_all_in_phase(f, Phase.SCAN), "RETURNING: every mount scans")
	for i in 120:
		_tick_full(f, rec)
	assert_eq(_total(rec, "tele"), before, "nothing telegraphed while returning")


func test_assault_fires_nothing_with_the_hull_outside_the_view() -> void:
	var h = _world("assault")
	var outside := _spawn(h, {}, Vector2(640.0, 900.0))
	_stub(h, outside, 315.0, 300.0)
	assert_true(EnemyWorld.view_rect(get_tree()).has_point(h.player.global_position), "sanity: the player is in view")
	assert_false(EnemyWorld.view_rect(get_tree()).has_point(outside.global_position), "sanity: the hull is not")
	var rec_out := _watch(outside)
	_run(outside, rec_out, 10.0)
	assert_eq(_total(rec_out, "tele"), 0, "no battery fires from outside the view")
	assert_eq(_total(rec_out, "rounds"), 0)
	var inside := _spawn(h, {}, Vector2(640.0, 400.0))
	_stub(h, inside, 315.0, 300.0)
	var rec_in := _watch(inside)
	_run(inside, rec_in, 10.0, func() -> bool: return _total(rec_in, "tele") > 0)
	assert_gt(_total(rec_in, "tele"), 0, "control: the same geometry from inside the view fires")


# ══ 4. Critical: cooldowns and pools ════════════════════════════════════════════════════════════

func test_critical_cuts_each_live_cooldown_once_and_leaves_the_scene_alone(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var scene_value := {}
	for b in BATTERIES:
		var fresh := TurretMountScenes.scene_for(b[1]).instantiate() as TurretMount
		scene_value[b[0]] = fresh.cooldown_seconds
		fresh.free()
		assert_eq(_mount(f, b[0]).cooldown_seconds, scene_value[b[0]], "%s: before critical %s keeps the scene's cooldown" % [mode, b[0]])
	_ladder_to(f, &"critical")
	await get_tree().process_frame
	assert_eq(f.phase_driver().current_id(), &"critical", "%s: sanity: critical" % mode)
	for b in BATTERIES:
		var mount := _mount(f, b[0])
		var expected: float = scene_value[b[0]] * SHIPPED.critical_cooldown_factor if not f.part(b[0]).is_destroyed() else scene_value[b[0]]
		assert_almost_eq(mount.cooldown_seconds, expected, 1e-4, "%s: %s's cooldown after critical" % [mode, b[0]])
	_brain(f).on_boss_phase(&"critical")
	for b in BATTERIES:
		var expected: float = scene_value[b[0]] * SHIPPED.critical_cooldown_factor if not f.part(b[0]).is_destroyed() else scene_value[b[0]]
		assert_almost_eq(_mount(f, b[0]).cooldown_seconds, expected, 1e-4, "%s: entering critical again cuts nothing more" % mode)
		var fresh := TurretMountScenes.scene_for(b[1]).instantiate() as TurretMount
		assert_eq(fresh.cooldown_seconds, scene_value[b[0]], "%s: the shipped mount scene is unchanged" % mode)
		fresh.free()


func test_every_battery_pool_is_sized_for_the_critical_period(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var factor := SHIPPED.critical_cooldown_factor
	var index := 0
	for b in BATTERIES:
		var slot := f.part(b[0]).get_node("MountSlots/Slot0") as TurretMountSlot
		assert_eq(slot.pool_period_factor, factor, "%s: %s's slot authors the config's critical factor" % [mode, b[0]])
		assert_eq(_mount(f, b[0]).pool_period_factor, factor, "%s: and the mount carries it" % mode)
		var names: Array = []
		for spec in _mount(f, b[0]).pool_specs():
			names.append(spec["name"])
		for pool_name in names:
			var pool := f.get_node("%s_%d" % [pool_name, index]) as BulletPool
			var expected := 0
			match pool_name:
				BurstCannonMount.POOL_NAME:
					expected = _burst_pool_size(b[1], factor)
					assert_false(pool.persist_after_owner_death, "%s: rounds vanish with the fortress" % mode)
				RocketBatteryMount.DUMB_POOL:
					expected = _rocket_pool_size(EnemyRocket.Kind.DUMB, factor)
					assert_true(pool.persist_after_owner_death, "%s: rocket pools persist (the second bounded exception)" % mode)
				RocketBatteryMount.PURSUIT_POOL:
					expected = _rocket_pool_size(EnemyRocket.Kind.PURSUIT, factor)
					assert_true(pool.persist_after_owner_death)
			assert_eq(pool.pool_size, expected, "%s: %s's %s pool holds the critical period's rounds" % [mode, b[0], pool_name])
		index += 1
	# The heavy cannon is the one the plan names: the uncut period needs fewer shells than critical does.
	assert_gt(_burst_pool_size(Variant.HEAVY_CANNON, factor), _burst_pool_size(Variant.HEAVY_CANNON, 1.0), "%s: boundary: the critical period needs more shells" % mode)

	# A mount built from a slot with the default factor has today's pool size (bit-identical).
	var host := Node2D.new()
	h.root.add_child(host)
	var slot := TurretMountSlot.new()
	slot.variant = Variant.HEAVY_CANNON
	host.add_child(slot)
	var plain := TurretMountBuilder.build(host, slot, 0, RandomNumberGenerator.new(), &"plain_group")
	assert_eq(plain.pool_period_factor, 1.0)
	var pool := host.get_node("PulsePool_0") as BulletPool
	assert_eq(pool.pool_size, _burst_pool_size(Variant.HEAVY_CANNON, 1.0), "%s: a default slot keeps today's pool" % mode)


func test_thirty_seconds_of_critical_fire_refuses_no_shot(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	_brain(f).on_boss_phase(&"critical")
	var factor := SHIPPED.critical_cooldown_factor
	for b in BATTERIES:
		var id: StringName = b[0]
		_stub(h, f, b[2], 300.0)
		var mount := _mount(f, id)
		var rec := _watch(f)
		var target := TargetInfo.player(get_tree())
		for i in int(round(30.0 / DT)):
			mount.tick(DT, target, true)
			rec["t"] += DT
			_expire(f, rec)
		if mount is BurstCannonMount:
			assert_eq((mount as BurstCannonMount).shots_refused, 0, "%s: %s: no shot refused in 30 s of critical fire" % [mode, id])
		elif mount is RocketBatteryMount:
			assert_eq((mount as RocketBatteryMount).rockets_refused, 0, "%s: %s: no rocket refused" % [mode, id])
		assert_gte(rec["tele"][id], 4, "%s: %s keeps firing at the critical period (%s x its cooldown)" % [mode, id, factor])
		if id != &"battery_sweep":
			assert_gte(rec["rounds"][id], 4, "%s: %s launched rounds" % [mode, id])


# ══ 5. EMP and death ════════════════════════════════════════════════════════════════════════════

func test_an_emp_silences_every_mount_for_the_window(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	_open_arcs(f)
	_stub(h, f, 90.0, 250.0)
	var rec := _watch(f)
	_run(f, rec, 10.0, func() -> bool: return _attacking(f) > 0)
	assert_gt(_attacking(f), 0, "%s: sanity: a mount is mid-attack when the EMP lands" % mode)
	var seconds := 4.0
	f.apply_emp(seconds, null)
	assert_true(f.is_emp_disrupted(), "%s: sanity: the window runs" % mode)
	assert_true(_all_in_phase(f, Phase.SCAN), "%s: every mount is scanning at once (a telegraph never lands)" % mode)
	var tele := _total(rec, "tele")
	var rounds := _total(rec, "rounds")
	var window := int(seconds * SHIPPED.emp_factor / DT) - 2
	for i in window:
		f._physics_process(DT)
		rec["t"] += DT
		_expire(f, rec)
	assert_true(f.is_emp_disrupted(), "%s: still inside the window" % mode)
	assert_eq(_total(rec, "tele"), tele, "%s: no mount telegraphed for the window" % mode)
	assert_eq(_total(rec, "rounds"), rounds, "%s: and none fired" % mode)
	for i in 600:
		f._physics_process(DT)
		rec["t"] += DT
		_expire(f, rec)
		if _total(rec, "tele") > tele:
			break
	assert_gt(_total(rec, "tele"), tele, "%s: control: after the window the guns fire again" % mode)


func test_death_powers_every_mount_down_and_a_rocket_in_flight_outlives_the_fortress(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, {"death_sequence_duration": 0.0})
	_stub(h, f, 315.0, 300.0)
	var rec := _watch(f)
	_run(f, rec, 10.0, func() -> bool: return rec["rounds"][&"battery_missiles"] > 0)
	var rocket: EnemyRocket = null
	for entry in rec["live"]:
		if entry[0] is EnemyRocket:
			rocket = entry[0]
	assert_not_null(rocket, "%s: sanity: the missile battery has a rocket in flight" % mode)
	if rocket == null:
		return
	var life := rocket.max_time
	f.part(&"core").destroy()
	assert_true(f.is_dying(), "%s: the core's death is the fortress's" % mode)
	assert_true(_all_in_phase(f, Phase.UNPOWERED), "%s: every mount is unpowered" % mode)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(is_instance_valid(f), "%s: sanity: the wreck is gone (death_duration 0)" % mode)
	assert_true(is_instance_valid(rocket) and not rocket.is_queued_for_deletion(), "%s: the rocket in flight survives the fortress" % mode)
	# The hand-over: the pool made the rocket self-owned (`expired -> queue_free`), and its life is the rocket scene's own `max_time` (the lifetime itself is
	# gated by test_enemy_bullet_lifetime.gd / test_enemy_rockets.gd; waiting it out in real time would cost a second of gate for nothing).
	var frees := false
	for connection in rocket.expired.get_connections():
		frees = frees or (connection["callable"] as Callable).get_method() == &"queue_free"
	assert_true(frees, "%s: the surviving rocket frees itself on expired" % mode)
	assert_eq(life, EnemyRocketScenes.max_time_of(rocket.kind), "%s: its life is the rocket scene's max_time" % mode)
	rocket.expired.emit()
	assert_true(rocket.is_queued_for_deletion(), "%s: and one expiry ends it" % mode)


# ══ 6 / 12. The §25 attacks and arena keys ══════════════════════════════════════════════════════

## `attacks` = `[cooldown_factor, max_concurrent_attacks, spoke_count, spoke_period, core_ring_armed, core_ring_period]` and `arena` =
## `[ring_pulse_armed, ring_period]` per boss phase (t7 the battery fields, t16 the rest), typed here.
func test_the_attacks_and_arena_keys_per_boss_phase(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	assert_eq(f.phase_snapshot()[&"attacks"], [1.0, 2, 0, 0.0, false, 0.0], "%s: batteries: no spokes, no core ring" % mode)
	assert_eq(f.phase_snapshot()[&"arena"], [false, 0.0], "%s: batteries: no ring pulse" % mode)
	_ladder_to(f, &"shields_exposed")
	assert_eq(f.phase_snapshot()[&"attacks"], [1.0, 2, 2, 8.0, false, 0.0], "%s: shields_exposed: two spokes every 8 s" % mode)
	assert_eq(f.phase_snapshot()[&"arena"], [false, 0.0], "%s: shields_exposed: no ring pulse" % mode)
	_ladder_to(f, &"core_exposed")
	assert_eq(f.phase_snapshot()[&"attacks"], [1.0, 2, 2, 8.0, false, 0.0], "%s: core_exposed: attacks unchanged (the ring is ARENA)" % mode)
	assert_eq(f.phase_snapshot()[&"arena"], [true, 6.0], "%s: core_exposed: a ring pulse every 6 s" % mode)
	_ladder_to(f, &"critical")
	await get_tree().process_frame
	assert_eq(f.phase_driver().current_id(), &"critical")
	assert_eq(f.phase_snapshot()[&"attacks"], [0.6, 3, 4, 6.0, true, 2.0], "%s: critical: cooldowns x 0.6, a gate of three, four spokes every 6 s, the core ring every 2 s" % mode)
	assert_eq(f.phase_snapshot()[&"arena"], [true, 3.5], "%s: critical: a ring pulse every 3.5 s" % mode)
	assert_eq(SHIPPED.critical_cooldown_factor, 0.6, "the shipped factor")
	assert_eq(SHIPPED.max_concurrent_attacks, 2)
	assert_eq(SHIPPED.critical_max_concurrent_attacks, 3)


# ══ B (t16). The geometry weapons: spokes, ring pulse, core ring ════════════════════════════════
## docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.7.2-§2.7.6, rows §2.7.7 B; task plan docs/plans/cmwt4y3hq00t0qs2ysigzomnw/3-plan.md.

const BeamPhase := EnemyBeam.Phase
const RingPhase := EnergyRing.Phase
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SPOKE_BEAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/fortress_spoke_beam.tscn")
const PULSE_RING_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/fortress_pulse_ring.tscn")
## Each spoke's local bearing (degrees): Spoke0 270 (north), Spoke1 90 (south), Spoke2 0, Spoke3 180.
const SPOKE_BEARINGS := [270.0, 90.0, 0.0, 180.0]
## The coarse hand-tick step of the long geometry rows (gate time): every period here is a whole number of steps, and nothing they check is per-frame.
const STEP := 0.05
const _SPEEDUP := 8  # tests/README.md -> Gate time rule 1

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


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


## Every spoke's and the ring's phase transitions as `[t, "spokeN" / "ring", phase]`, on [param rec]'s sim clock.
func _watch_geometry(f: SpaceFortress, rec: Dictionary) -> Array:
	var events: Array = []
	var spokes := f.spoke_beams()
	for i in spokes.size():
		var label := "spoke%d" % i
		spokes[i].phase_changed.connect(func(p: int) -> void: events.append([rec["t"], label, p]))
	f.pulse_ring().phase_changed.connect(func(p: int) -> void: events.append([rec["t"], "ring", p]))
	return events


## The sim times at which [param label] entered TELEGRAPH (a start) at or after [param from].
func _starts(events: Array, label: String, from: float = 0.0) -> Array:
	var out: Array = []
	for e in events:
		if e[1] == label and int(e[2]) == 1 and float(e[0]) >= from - 1e-6:  # TELEGRAPH is 1 in both enums
			out.append(float(e[0]))
	return out


func _any_lit(spokes: Array[EnemyBeam], indices: Array) -> bool:
	for i in indices:
		if spokes[i].phase() == BeamPhase.ACTIVE:
			return true
	return false


## True while every spoke and the ring are OFF.
func _geometry_off(f: SpaceFortress) -> bool:
	for spoke in f.spoke_beams():
		if spoke.phase() != BeamPhase.OFF:
			return false
	return f.pulse_ring().phase() == RingPhase.OFF


# ── 7 / 8. Spokes and ring pulse by phase, period and spin ──────────────────────────────────────

func test_the_hull_spokes_and_the_ring_as_authored(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var spokes := f.spoke_beams()
	assert_eq(spokes.size(), 4, "%s: four hull spokes" % mode)
	for i in spokes.size():
		var emitter := f.get_node("HullBeams/Spoke%d" % i) as Node2D
		var bearing := deg_to_rad(float(SPOKE_BEARINGS[i]))
		assert_almost_eq(emitter.position.length(), f.hull_radius(), 0.01, "%s: Spoke%d sits on the hull edge (r %.0f)" % [mode, i, f.hull_radius()])
		assert_almost_eq(absf(angle_difference(emitter.position.angle(), bearing)), 0.0, 1e-4, "%s: Spoke%d on local %.0f degrees" % [mode, i, SPOKE_BEARINGS[i]])
		var out := Vector2.RIGHT.rotated(spokes[i].global_rotation)
		assert_almost_eq(out.dot((spokes[i].global_position - f.global_position).normalized()), 1.0, 1e-4, "%s: Spoke%d's beam points outward" % [mode, i])
		assert_eq(spokes[i].scene_file_path, SPOKE_BEAM_SCENE.resource_path, "%s: Spoke%d is the fortress spoke beam" % [mode, i])
	assert_eq(f.pulse_ring().scene_file_path, PULSE_RING_SCENE.resource_path, "%s: the ring pulse is the fortress ring" % mode)
	assert_eq(f.pulse_ring().global_position, f.global_position, "%s: centred on the hull" % mode)
	# The gated values are authored in the inherited scenes themselves (export_of_scene reads only a scene's own state).
	var beam_values := {&"telegraph_seconds": 1.2, &"active_seconds": 2.5, &"length": 900.0, &"damage": 14, &"rehit_interval": 0.55, &"registers_hazard": true,
			&"telegraph_width": 4.0, &"fade_seconds": 0.15}
	for key in beam_values:
		assert_eq(EnemyBeamScenes.export_of_scene(SPOKE_BEAM_SCENE, key, null), beam_values[key], "%s: fortress_spoke_beam.tscn authors %s" % [mode, key])
		assert_eq(spokes[0].get(key), beam_values[key], "%s: and the instance carries it" % mode)
	var ring_values := {&"max_radius": 640.0, &"ring_speed": 300.0, &"band": 24.0, &"gap_count": 2, &"gap_deg": 50.0, &"damage": 14, &"telegraph_seconds": 1.0,
			&"fade_seconds": 0.15}
	for key in ring_values:
		assert_eq(EnemyBeamScenes.export_of_scene(PULSE_RING_SCENE, key, null), ring_values[key], "%s: fortress_pulse_ring.tscn authors %s" % [mode, key])
		assert_eq(f.pulse_ring().get(key), ring_values[key], "%s: and the instance carries it" % mode)


func test_spokes_and_ring_pulse_by_phase_period_and_spin(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	_stub(h, f, 90.0, 400.0)
	var b := _brain(f)
	var spokes := f.spoke_beams()
	var rec := _watch(f)
	var events := _watch_geometry(f, rec)

	# batteries: nothing for 20 s (coarse step: one countdown, nothing per-frame).
	var stray := [0]
	var count_stray := func() -> bool:
		if not _geometry_off(f):
			stray[0] += 1
		return false
	_run(f, rec, 20.0, count_stray, STEP)
	assert_eq(stray[0], 0, "%s: batteries: no spoke and no ring for 20 s" % mode)

	# shields_exposed: Spoke0 + Spoke1 every 8.0 s; the hull spins exactly while they are lit, alternating.
	_ladder_to(f, &"shields_exposed")
	var t0: float = rec["t"]
	var mismatched := [0]
	var dirs: Array = []
	var check_spin := func() -> bool:
		var lit := _any_lit(spokes, [0, 1])
		if b.spinning() != lit:
			mismatched[0] += 1
		if lit and (dirs.is_empty() or dirs[-1] != b.spin_direction()):
			dirs.append(b.spin_direction())
		return false
	_run(f, rec, 18.0, check_spin, STEP)
	var s0 := _starts(events, "spoke0", t0)
	assert_eq(s0.size(), 2, "%s: two volleys in 18 s of shields_exposed (%s)" % [mode, s0])
	if s0.size() == 2:
		assert_almost_eq(s0[0] - t0, SHIPPED.spoke_period, STEP * 1.5, "%s: the first volley one period after the phase began" % mode)
		assert_almost_eq(s0[1] - s0[0], SHIPPED.spoke_period, STEP * 1.5, "%s: then every spoke_period" % mode)
	assert_eq(_starts(events, "spoke1", t0), s0, "%s: Spoke1 fires with Spoke0" % mode)
	assert_eq(_starts(events, "spoke2", t0).size() + _starts(events, "spoke3", t0).size(), 0, "%s: two spokes per volley before critical" % mode)
	assert_eq(_starts(events, "ring", t0).size(), 0, "%s: no ring pulse before core_exposed" % mode)
	assert_eq(mismatched[0], 0, "%s: the hull spins exactly while a volley spoke is lit" % mode)
	assert_eq(dirs.size(), 2, "%s: one spin per volley (%s)" % [mode, dirs])
	if dirs.size() == 2:
		assert_eq(int(dirs[1]), -int(dirs[0]), "%s: the second volley spins the other way" % mode)

	# core_exposed: the ring pulse every 6.0 s from the hull centre.
	_ladder_to(f, &"core_exposed")
	t0 = rec["t"]
	var centres: Array = []
	f.pulse_ring().phase_changed.connect(func(p: int) -> void:
		if p == RingPhase.TELEGRAPH:
			centres.append(f.pulse_ring().ring_centre().distance_to(f.global_position)))
	_run(f, rec, 12.5, Callable(), STEP)
	var r0 := _starts(events, "ring", t0)
	assert_eq(r0.size(), 2, "%s: two rings in 12.5 s of core_exposed (%s)" % [mode, r0])
	if r0.size() == 2:
		assert_almost_eq(r0[0] - t0, SHIPPED.ring_period, STEP * 1.5, "%s: the first ring one period after the phase began" % mode)
		assert_almost_eq(r0[1] - r0[0], SHIPPED.ring_period, STEP * 1.5, "%s: then every ring_period" % mode)
	for c in centres:
		assert_almost_eq(float(c), 0.0, 0.01, "%s: each ring is centred on the hull" % mode)

	# critical: all four spokes every 6.0 s, the ring every 3.5 s.
	_ladder_to(f, &"critical")
	t0 = rec["t"]
	_run(f, rec, 12.5, Callable(), STEP)
	var c0 := _starts(events, "spoke0", t0)
	assert_eq(c0.size(), 2, "%s: two critical volleys in 12.5 s (%s)" % [mode, c0])
	if c0.size() == 2:
		assert_almost_eq(c0[1] - c0[0], SHIPPED.critical_spoke_period, STEP * 1.5, "%s: every critical_spoke_period" % mode)
		for i in [1, 2, 3]:
			assert_eq(_starts(events, "spoke%d" % i, t0), c0, "%s: Spoke%d fires in every critical volley" % [mode, i])
	var cr := _starts(events, "ring", t0)
	assert_gte(cr.size(), 3, "%s: rings keep coming in critical (%s)" % [mode, cr])
	for i in range(1, cr.size()):
		assert_almost_eq(cr[i] - cr[i - 1], SHIPPED.critical_ring_period, STEP * 1.5, "%s: every critical_ring_period" % mode)
	assert_false(f.core_ring_pool()._warned_exhausted, "%s: sanity: the core ring's pool never ran dry" % mode)


## Real physics at 8x, one world for spokes and ring (task plan review B4): every battery is destroyed first (no battery round reaches the player), both
## generators next (core_exposed, south presented: `Spoke1` faces the player). Periods 0.3 s on the private config, so a volley and the rings follow at once.
func test_spokes_and_ring_hit_the_player_and_outsiders_never_the_owner_set(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	h.root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	player.health_component.max_health = 100000
	player.health_component.current_health = 100000

	var f := SCENE.instantiate() as SpaceFortress
	f.config.set(&"spoke_period", 0.3)
	f.config.set(&"ring_period", 0.3)
	var brain := f.get_node("Brain") as FortressBrain
	brain.start_engaged = true
	brain.rng_seed = 4  # chosen so the first ring's gaps miss both targets in both harnesses (deterministic: the ring draw is the brain rng's only use here)
	f.global_position = Vector2(640.0, SHIPPED.assault_hold_y) if h.is_assault else SPAWN
	h.root.add_child(f)
	for b in BATTERIES:
		f.part(b[0]).destroy()
	f.part(&"shield_north").destroy()
	f.part(&"shield_south").destroy()
	assert_eq(f.phase_driver().current_id(), &"core_exposed", "%s: sanity: core_exposed" % mode)
	player.global_position = f.global_position + Vector2(0.0, 400.0)  # local 90 degrees: Spoke1's line
	var own := _fixture(h, f.global_position + Vector2(0.0, 250.0))
	own.add_to_group(f.owner_group())
	var outsider := _fixture(h, f.global_position + Vector2(-400.0, 0.0))  # local 180 degrees: no core_exposed spoke sweeps it
	var part_hp := {}
	for p in f.modular_hull().modules():
		part_hp[p.module_id] = p.health.current_health

	var hits: Array = []
	for spoke in f.spoke_beams():
		spoke.target_hit.connect(func(target: Node2D, _d: int) -> void: hits.append(["spoke", target]))
	f.pulse_ring().target_hit.connect(func(target: Node2D, _d: int) -> void: hits.append(["ring", target]))
	var seen := func(kind: String, target: Node) -> bool:
		return hits.any(func(e: Array) -> bool: return e[0] == kind and e[1] == target)

	_scale_clock()
	var frames := 0
	while frames < 600:  # 10 s of sim at most
		await get_tree().physics_frame
		frames += 1
		if seen.call("spoke", player) and seen.call("ring", player) and seen.call("ring", outsider):
			break
	_restore_clock()
	if OS.is_stdout_verbose():
		print("[spoke-ring] %s %d frames" % [mode, frames])

	assert_true(seen.call("spoke", player), "%s: a spoke hits the real player (%d frames)" % [mode, frames])
	assert_true(seen.call("ring", player), "%s: the ring pulse hits the real player" % mode)
	assert_true(seen.call("ring", outsider), "%s: and an enemy outside the owner group" % mode)
	for e in hits:
		assert_ne(e[1], own, "%s: the %s never hits an escort in the owner group" % [mode, e[0]])
		assert_ne(e[1], f, "%s: nor the fortress" % mode)
		assert_false(e[1] is EnemyModule, "%s: nor a part" % mode)
	for p in f.modular_hull().modules():
		assert_eq(p.health.current_health, part_hp[p.module_id], "%s: %s's HP is untouched by its own beams" % [mode, p.module_id])


func _fixture(h, at: Vector2) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	cs.shape = circle
	e.get_node("HurtBox").add_child(cs)
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = 100000
	health.current_health = 100000
	h.root.add_child(e)
	e.global_position = at
	return e


# ── 9. The core bullet ring ─────────────────────────────────────────────────────────────────────

## [param offsets] (radians, each a ring's base angle mod the ring spacing): true when they fall on distinct lanes and the widest lane gap is under half
## the spacing (no bearing stays a safe lane).
func _covers_lanes(offsets: Array, spacing: float) -> bool:
	var sorted := offsets.map(func(o: float) -> float: return fposmod(o, spacing))
	sorted.sort()
	for i in range(1, sorted.size()):
		if sorted[i] - sorted[i - 1] < 1e-3:
			return false
	var widest: float = sorted[0] + spacing - sorted[-1]
	for i in range(1, sorted.size()):
		widest = maxf(widest, sorted[i] - sorted[i - 1])
	return widest < 0.5 * spacing


func test_core_ring_only_in_critical_precessing_from_the_parent_container(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	_stub(h, f, 90.0, 400.0)
	var pool := f.core_ring_pool()
	assert_eq(pool.get_parent(), f, "%s: CoreRingPool is a direct root child" % mode)
	assert_eq(pool.pool_size, 72, "%s: 12 x ceil(11.43 / 2.0) = 72 at the shipped values" % mode)
	assert_eq(pool.pool_size, EnemyRounds.pool_size_for(SHIPPED.core_ring_count, _core_life(), SHIPPED.core_ring_period), "%s: pool_size_for over the round's life" % mode)
	assert_gt(EnemyRounds.pool_size_for(SHIPPED.core_ring_count, 18.0, SHIPPED.core_ring_period), pool.pool_size, "%s: boundary: sized on max_time alone it would need more" % mode)

	var rec := _watch(f)
	_ladder_to(f, &"core_exposed")
	_run(f, rec, 30.0, Callable(), STEP)
	assert_eq(rec["core_rounds"], 0, "%s: no core ring before critical (30 s of core_exposed)" % mode)

	_ladder_to(f, &"critical")
	var t0: float = rec["t"]
	var rings: Array = []  # [t, count, bearings, speeds, damages, parents]
	var before := [0]  # a lambda captures locals by value: a holder
	var on_ring := func() -> bool:
		if rec["core_rounds"] > before[0]:
			var fresh: Array = rec["live"].slice(rec["live"].size() - (rec["core_rounds"] - before[0]))
			var ring := {"t": rec["t"], "n": fresh.size(), "bearings": [], "ok": true}
			for e in fresh:
				var bullet := e[0] as EnemyBullet
				ring["bearings"].append((bullet.global_position - f.global_position).angle())
				ring["ok"] = ring["ok"] and is_equal_approx(bullet.speed, SHIPPED.core_ring_speed) \
						and (bullet.get_node("HitBox") as HitBox).damage == SHIPPED.core_ring_damage and bullet.get_parent() == f.get_parent()
			rings.append(ring)
			before[0] = rec["core_rounds"]
		return false
	_run(f, rec, 30.0, on_ring, STEP)
	assert_eq(rings.size(), 15, "%s: one ring every 2.0 s over 30 s of critical" % mode)
	assert_false(pool._warned_exhausted, "%s: 30 s of core rings never empty the pool" % mode)
	if rings.size() < 6:
		return
	assert_almost_eq(rings[0]["t"] - t0, SHIPPED.core_ring_period, STEP * 1.5, "%s: the first ring one period into critical" % mode)
	var spacing := TAU / float(SHIPPED.core_ring_count)
	var offsets: Array = []
	for i in rings.size():
		assert_eq(rings[i]["n"], SHIPPED.core_ring_count, "%s: ring %d has 12 bullets" % [mode, i])
		assert_true(rings[i]["ok"], "%s: ring %d: 210 px/s, 10 damage, in the fortress's parent container" % [mode, i])
		if i > 0:
			assert_almost_eq(rings[i]["t"] - rings[i - 1]["t"], SHIPPED.core_ring_period, STEP * 1.5, "%s: every core_ring_period" % mode)
		var base: float = rings[i]["bearings"].reduce(func(acc: float, a: float) -> float: return minf(acc, fposmod(a, spacing)), INF)
		offsets.append(base)
		if i > 0:
			assert_almost_eq(fposmod(base - offsets[i - 1], spacing), fposmod(SHIPPED.core_ring_step, spacing), 1e-3, "%s: the base angle advances 0.24 per ring" % mode)
	assert_true(_covers_lanes(offsets.slice(0, 5), spacing), "%s: five consecutive rings leave no safe lane (%s)" % [mode, offsets.slice(0, 5)])
	for step in [spacing / 2.0, spacing / 3.0]:
		var synthetic: Array = []
		for k in 5:
			synthetic.append(k * step)
		assert_false(_covers_lanes(synthetic, spacing), "%s: boundary: a step of %.3f re-treads lanes and fails" % [mode, step])


# ── 10. EMP and death ───────────────────────────────────────────────────────────────────────────

## Short critical periods on the private config, so all three run at once: spokes ACTIVE, the ring EXPANDING and core-ring rounds in the air.
const BUSY := {"critical_spoke_period": 1.0, "critical_ring_period": 1.0, "core_ring_period": 1.0}


func _busy_critical(h, extra: Dictionary = {}) -> SpaceFortress:
	var props := BUSY.duplicate()
	props.merge(extra)
	var f := _spawn(h, props)
	_stub(h, f, 90.0, 400.0)
	_ladder_to(f, &"critical")
	var rec := _watch(f)
	_run(f, rec, 6.0, func() -> bool:
		return f.spoke_beams()[0].phase() == BeamPhase.ACTIVE and f.pulse_ring().phase() == RingPhase.EXPANDING and not f.core_ring_pool()._active.is_empty())
	return f


## Ticks the whole fortress (`_physics_process`) until every spoke and the ring are OFF; the ticks it took, or -1 past [param limit].
func _ticks_to_off(f: SpaceFortress, limit: int) -> int:
	for i in limit:
		if _geometry_off(f):
			return i
		f._physics_process(DT)
	return 0 if _geometry_off(f) else -1


func test_emp_silences_and_death_cancels_the_geometry_weapons(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _busy_critical(h)
	var b := _brain(f)
	assert_eq(f.spoke_beams()[0].phase(), BeamPhase.ACTIVE, "%s: sanity: a spoke is lit" % mode)
	assert_eq(f.pulse_ring().phase(), RingPhase.EXPANDING, "%s: sanity: the ring expands" % mode)
	assert_false(f.core_ring_pool()._active.is_empty(), "%s: sanity: core-ring rounds are in the air" % mode)
	var emp_seconds := 20.0
	var window := emp_seconds * SHIPPED.emp_factor
	for left in [b.spoke_countdown(), b.ring_countdown(), b.core_ring_countdown()]:
		assert_lt(float(left), window - 0.5, "%s: non-vacuous: every weapon is due inside the window" % mode)
	var fade := maxf(f.spoke_beams()[0].fade_seconds, f.pulse_ring().fade_seconds)
	f.apply_emp(emp_seconds, null)
	assert_true(f.is_emp_disrupted(), "%s: sanity: the window runs" % mode)
	var off_after := _ticks_to_off(f, 60)
	assert_between(off_after, 0, ceili(fade / DT) + 1, "%s: every spoke and the ring are OFF within fade_seconds (%d ticks)" % [mode, off_after])
	var acquired := f.core_ring_pool()._active.size()
	var restarted := 0
	var ticks := int(window / DT) - off_after - 3
	for i in ticks:
		f._physics_process(DT)
		if not _geometry_off(f):
			restarted += 1
	assert_true(f.is_emp_disrupted(), "%s: sanity: still inside the window" % mode)
	assert_eq(restarted, 0, "%s: no spoke or ring starts for the window" % mode)
	assert_eq(f.core_ring_pool()._active.size(), acquired, "%s: no core ring fires for the window (rounds already up keep flying)" % mode)
	var back := false
	for i in 300:
		f._physics_process(DT)
		if not _geometry_off(f) and f.core_ring_pool()._active.size() > acquired:
			back = true
			break
	assert_true(back, "%s: control: after the window they fire again" % mode)

	var g := _busy_critical(h, {"death_sequence_duration": 5.0})
	var in_air: Array = g.core_ring_pool()._active.duplicate()
	assert_false(in_air.is_empty(), "%s: sanity: core-ring rounds in the air" % mode)
	g.part(&"core").destroy()
	assert_true(g.is_dying(), "%s: the core's death is the fortress's" % mode)
	assert_true(g.core_ring_pool()._active.is_empty(), "%s: the core ring's pool lets go of every round" % mode)
	for r in in_air:
		assert_true(not is_instance_valid(r) or r.is_queued_for_deletion(), "%s: every core-ring round in flight is freed" % mode)
	var dead_off := _ticks_to_off(g, 60)
	assert_between(dead_off, 0, ceili(fade / DT) + 1, "%s: dying, every spoke and the ring are OFF within fade_seconds (%d ticks)" % [mode, dead_off])
	var stray := 0
	for i in 120:
		g._physics_process(DT)
		if not _geometry_off(g):
			stray += 1
	assert_eq(stray, 0, "%s: nothing starts while dying" % mode)


# ── 11. Fairness ────────────────────────────────────────────────────────────────────────────────

## The player hurtbox circle radius x the scale composed down from the player root to the shape (the scale sits on different nodes: the ship's HurtBox,
## the fighter's collision child), instantiated.
func _player_hurt_radius(scene: PackedScene) -> float:
	var p := scene.instantiate() as Node2D
	var hurt := p.get_node("HurtBox") as Node2D
	var r := 0.0
	for child in hurt.get_children():
		var cs := child as CollisionShape2D
		if cs == null or cs.disabled or not (cs.shape is CircleShape2D):
			continue
		var xf := hurt.transform * cs.transform
		r = maxf(r, (cs.shape as CircleShape2D).radius * absf(xf.get_scale().x))
	p.free()
	return r


func _player_speed(scene: PackedScene) -> float:
	var p := scene.instantiate()
	var speed: float = p.cruise_speed()
	p.free()
	return speed


func _player_iframes(scene: PackedScene) -> float:
	var p := scene.instantiate() as PlayerBase
	var s := p.invincibility_sec
	p.free()
	return s


## The narrowest gap arc (at the hull edge + the player's radius) fits two player widths.
func _gap_fits(gap_deg: float, hull_r: float, r_p: float) -> bool:
	return deg_to_rad(gap_deg) * (hull_r + r_p) >= 2.0 * (2.0 * r_p)


func test_spoke_fairness() -> void:
	var h = _world("open_space")
	var f := _spawn(h)
	var tip := f.hull_radius() + 250.0
	for scene in [FIGHTER_SCENE, SHIP_SCENE]:
		var speed := _player_speed(scene)
		assert_lte(SHIPPED.beam_spin_rate * tip, 0.8 * speed, "a player 250 px off the hull outruns a volley sweep (%s)" % scene.resource_path.get_file())
		assert_lte(SHIPPED.critical_spin_rate * tip, 0.8 * speed, "and a critical sweep (%s)" % scene.resource_path.get_file())
		for spoke in f.spoke_beams():
			assert_gt(spoke.rehit_interval, _player_iframes(scene), "a spoke's re-hit outlasts the i-frames (%s)" % scene.resource_path.get_file())
	for spoke in f.spoke_beams():
		assert_gte(spoke.telegraph_seconds, 1.0, "a spoke telegraphs for at least 1 s")
		assert_gte(spoke.telegraph_width, 3.0, "drawn at least 3 px wide")
	assert_gte(f.pulse_ring().telegraph_seconds, 1.0, "the ring pulse telegraphs for at least 1 s")
	assert_gte(f.pulse_ring().telegraph_width, 3.0)


func test_ring_gap_fairness_at_the_hull_edge() -> void:
	var h = _world("open_space")
	var f := _spawn(h)
	var hull_r := f.hull_radius()
	var gap := f.pulse_ring().gap_deg
	var r_ship := _player_hurt_radius(SHIP_SCENE)
	var r_fighter := _player_hurt_radius(FIGHTER_SCENE)
	assert_almost_eq(r_ship, 11.0, 0.01, "the Open Space ship's hurtbox: 5 x 2.2 on the HurtBox")
	assert_almost_eq(r_fighter, 13.5, 0.01, "the Assault fighter's: 5 x 2.7 on its collision child")
	assert_true(_gap_fits(gap, hull_r, r_ship), "a %.0f degree gap at the hull edge fits two ship widths" % gap)
	assert_true(_gap_fits(gap, hull_r, r_fighter), "and two fighter widths")
	# Boundary: 15 degrees fails the conjunction (the fighter; the smaller ship alone would still fit, so both facts are pinned).
	assert_false(_gap_fits(15.0, hull_r, r_fighter), "boundary: a 15 degree gap is too narrow for the fighter")
	assert_true(_gap_fits(15.0, hull_r, r_ship), "boundary: (the ship alone would still fit)")
	assert_false(_gap_fits(15.0, hull_r, r_fighter) and _gap_fits(15.0, hull_r, r_ship), "boundary: the both-players check fails at 15 degrees")


# ── 11. Assault density, measured ───────────────────────────────────────────────────────────────

## The five player positions round the hull at world (640, 180) (§2.7.6).
const DENSITY_POSITIONS := {"S": Vector2(640, 600), "SW": Vector2(240, 560), "SE": Vector2(1040, 560), "W": Vector2(160, 200), "E": Vector2(1120, 200)}
const DENSITY_MEAN_CEILING := 13.3  # 2.0 x the station's legacy turret rate (6.67 /s)
const DENSITY_PEAK_CEILING := 30  # 1.25 x the station's legacy 2 s peak (24)
const DENSITY_SETTLE := 1.0
const DENSITY_COUNT := 10.0


## One full hand tick of the fortress (brain + mover, position integrated by hand); returns the rounds it launched (every `BulletPool` child's
## `_active` after the tick: everything was returned the tick before), then returns each at once.
func _density_tick(f: SpaceFortress, pools: Array[BulletPool]) -> int:
	var before := f.global_position
	f._physics_process(DT)
	f.global_position = before + f.velocity * DT
	var n := 0
	for pool in pools:
		if pool._active.is_empty():
			continue
		n += pool._active.size()
		for round_node in pool._active.duplicate():
			round_node.expired.emit()
			pool._recycle(round_node)
	return n


func _measure(h, f: SpaceFortress, at: Vector2) -> Dictionary:
	var pools: Array[BulletPool] = []
	for child in f.get_children():
		if child is BulletPool:
			pools.append(child)
	h.player.global_position = at
	h.player.velocity = Vector2.ZERO
	for i in int(round(DENSITY_SETTLE / DT)):
		_density_tick(f, pools)
	var per_tick: Array[int] = []
	for i in int(round(DENSITY_COUNT / DT)):
		per_tick.append(_density_tick(f, pools))
	var total := 0
	var peak := 0
	var window := 0
	var span := int(round(2.0 / DT))
	for i in per_tick.size():
		total += per_tick[i]
		window += per_tick[i]
		if i >= span:
			window -= per_tick[i - span]
		peak = maxi(peak, window)
	var dry := false
	for pool in pools:
		dry = dry or pool._warned_exhausted
	var refused := 0
	for b in BATTERIES:
		var part := f.part(b[0])
		if part.is_destroyed():
			continue
		var mount := _mount(f, b[0])
		if mount is BurstCannonMount:
			refused += (mount as BurstCannonMount).shots_refused
		elif mount is RocketBatteryMount:
			refused += (mount as RocketBatteryMount).rockets_refused
	return {"mean": float(total) / DENSITY_COUNT, "peak": peak, "dry": dry, "refused": refused}


func test_assault_density_in_every_phase_at_five_positions() -> void:
	var h = _world("assault")
	for phase_id in [&"batteries", &"shields_exposed", &"core_exposed", &"critical"]:
		var f := _spawn(h, {}, Vector2(640.0, 180.0))
		if phase_id != &"batteries":
			# The worst live set (the three highest-rate batteries): sweep + missiles die first, which itself enters shields_exposed.
			f.part(&"battery_sweep").destroy()
			f.part(&"battery_missiles").destroy()
			_ladder_to(f, phase_id)
		assert_eq(f.phase_driver().current_id(), phase_id, "sanity: %s" % phase_id)
		var worst := {"mean": 0.0, "peak": 0, "at": ""}
		for label in DENSITY_POSITIONS:
			var m := _measure(h, f, DENSITY_POSITIONS[label])
			var where := "%s at %s: mean %.2f rounds/s, peak %d in 2 s" % [phase_id, label, m["mean"], m["peak"]]
			assert_lte(m["mean"], DENSITY_MEAN_CEILING, "mean ceiling: " + where)
			assert_lte(m["peak"], DENSITY_PEAK_CEILING, "peak ceiling: " + where)
			assert_false(m["dry"], "no pool ever empty: " + where)
			assert_eq(m["refused"], 0, "no mount refused a shot: " + where)
			if m["mean"] > worst["mean"] or (m["mean"] == worst["mean"] and m["peak"] > worst["peak"]):
				worst = {"mean": m["mean"], "peak": m["peak"], "at": label}
			if OS.is_stdout_verbose():
				print("[density] " + where)
		assert_eq(f.phase_driver().current_id(), phase_id, "sanity: still %s after the count" % phase_id)
		if OS.is_stdout_verbose():
			print("[density] %s worst: %s mean %.2f, peak %d" % [phase_id, worst["at"], worst["mean"], worst["peak"]])
		f.queue_free()
		await get_tree().process_frame
