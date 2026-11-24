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
	var rec := {"tele": {}, "rounds": {}, "live": [], "t": 0.0}
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


## Returns every round whose life is over to its pool at once (the real round does this on its own physics step, which a hand-ticked row never runs).
func _expire(f: SpaceFortress, rec: Dictionary) -> void:
	var live: Array = rec["live"]
	for i in range(live.size() - 1, -1, -1):
		if rec["t"] < float(live[i][1]):
			continue
		var round_node: Node = live[i][0]
		live.remove_at(i)
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
	while brain.phase != FortressBrain.Phase.HOLD and ticks < 400:
		_tick_full(f, rec)
		ticks += 1
		saw_noticing = saw_noticing or brain.phase == FortressBrain.Phase.NOTICING
		if brain.phase != FortressBrain.Phase.HOLD:
			assert_true(_all_in_phase(f, Phase.SCAN), "every mount scans in brain phase %d" % brain.phase)
	assert_true(saw_noticing, "sanity: it noticed the player first")
	assert_eq(_total(rec, "tele"), 0, "nothing telegraphed while idle or noticing")
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


# ══ 6. The §25 attacks key ══════════════════════════════════════════════════════════════════════

## The battery fields of `attacks` (`[cooldown_factor, max_concurrent_attacks, ...]`; the spoke and core-ring fields are t16's), typed here.
func test_the_attacks_key_carries_the_cooldown_factor_and_the_gate_cap(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var before_critical := [1.0, 2, 0, 0.0, false, 0.0]
	assert_eq(f.phase_snapshot()[&"attacks"], before_critical, "%s: batteries" % mode)
	_ladder_to(f, &"shields_exposed")
	assert_eq(f.phase_snapshot()[&"attacks"], before_critical, "%s: shields_exposed (the spokes are t16's)" % mode)
	_ladder_to(f, &"core_exposed")
	assert_eq(f.phase_snapshot()[&"attacks"], before_critical, "%s: core_exposed" % mode)
	_ladder_to(f, &"critical")
	await get_tree().process_frame
	assert_eq(f.phase_driver().current_id(), &"critical")
	assert_eq(f.phase_snapshot()[&"attacks"], [0.6, 3, 0, 0.0, false, 0.0], "%s: critical: cooldowns x 0.6 and a gate of three" % mode)
	assert_eq(SHIPPED.critical_cooldown_factor, 0.6, "the shipped factor")
	assert_eq(SHIPPED.max_concurrent_attacks, 2)
	assert_eq(SHIPPED.critical_max_concurrent_attacks, 3)
