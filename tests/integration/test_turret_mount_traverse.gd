## Ship-mounted turrets (Phase 10 t3, docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.3): `TurretMount.traverse_deg` limits, the extracted
## `TurretMountBuilder` and the `HEAVY_CANNON` variant. INTENT tests, hand-ticked at 1/60 s: a mount is built through the real builder under a plain
## host, and each row feeds it a `TargetInfo` per tick (no brain, no physics world; line of sight is the row's `can_fire`).
##
## The 360 degree trace row is the bit-identity gate: `TRACE_360` was recorded from the unchanged `TurretMount` before this task touched it.
extends GutTest

const HEAVY_SCENE: PackedScene = preload("res://assault/scenes/enemies/heavy_emplacement/heavy_emplacement.tscn")
const TURRET_SCENE: PackedScene = preload("res://assault/scenes/enemies/defense_turret/defense_turret.tscn")
const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")

const DT := 1.0 / 60.0
const OWNER := &"traverse_test_owner"
const RADIUS := 300.0
## Float slack on an angle comparison, rad.
const EPS := 1e-4

## `rotation` of a default burst cannon (rest 0, seed 7, 360 degrees) every 60 ticks over 600, the target circling at 300 px once in 10 s; and the
## round count. Recorded before the traverse change.
const TRACE_360: Array[float] = [1.02339839935303, 1.65171682834625, 2.28003549575806, 2.90835404396057, 3.53667235374451, 4.16499137878418, 4.79330968856812, 5.42162799835205, 6.04994678497314, 6.67826509475708]
const TRACE_360_ROUNDS := 12


class _Rig:
	extends RefCounted
	var root: Node2D
	var host: Node2D
	var slot: TurretMountSlot
	var mount: TurretMount
	var rounds: Array = []


## A mount of [param variant] on a plain host at the origin of a fresh root. `traverse` (>= 0) goes through the slot override, as a ship's would.
func _rig(variant: int, rest_deg: float, traverse: float = -1.0, seed_value: int = 7) -> _Rig:
	var r := _Rig.new()
	r.root = Node2D.new()
	add_child_autofree(r.root)
	r.host = Node2D.new()
	r.root.add_child(r.host)
	var slots := Node2D.new()
	r.host.add_child(slots)
	r.slot = TurretMountSlot.new()
	r.slot.variant = variant
	r.slot.rest_bearing_deg = rest_deg
	r.slot.traverse_deg_override = traverse
	slots.add_child(r.slot)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	r.mount = TurretMountBuilder.build(r.host, r.slot, 0, rng, OWNER)
	r.mount.round_fired.connect(func(p: Node2D) -> void: r.rounds.append(p))
	return r


func _target(pos: Vector2, vel: Vector2 = Vector2.ZERO) -> TargetInfo:
	var t := TargetInfo.new()
	t.has_target = true
	t.position = pos
	t.velocity = vel
	return t


func _orbit(i: int) -> TargetInfo:
	var a := TAU * float(i) / 600.0
	return _target(Vector2.from_angle(a) * RADIUS, Vector2.from_angle(a + PI * 0.5) * RADIUS * TAU / 10.0)


## The mount's offset from its rest bearing, rad, in (-PI, PI].
func _offset(m: TurretMount) -> float:
	return wrapf(m.rotation - deg_to_rad(m.rest_bearing_deg), -PI, PI)


func _bearing_offset(m: TurretMount, p: Vector2) -> float:
	return wrapf((p - m.global_position).angle() - deg_to_rad(m.rest_bearing_deg), -PI, PI)


# ── traverse ────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_120_degree_mount_never_leaves_its_arc_and_never_fires_out_of_it_while_the_target_circles() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 120.0)
	var half := deg_to_rad(60.0)
	var worst := 0.0
	# Cells, not locals: a lambda captures a local by value.
	var fired := [0, 0]
	var current := [_orbit(0)]
	r.mount.round_fired.connect(func(_p: Node2D) -> void:
		var inside: bool = absf(_bearing_offset(r.mount, (current[0] as TargetInfo).position)) <= half + EPS
		fired[0 if inside else 1] += 1)
	for i in 600:
		current[0] = _orbit(i)
		r.mount.tick(DT, current[0], true)
		worst = maxf(worst, absf(_offset(r.mount)))
	assert_lte(worst, half + EPS, "the mount's offset from rest stays inside +-60 degrees on all 600 ticks (worst %.2f deg)" % rad_to_deg(worst))
	assert_gt(worst, half - 0.05, "sanity: the circling target does drive it to the edge of the arc")
	assert_eq(fired[1], 0, "no round leaves with the target outside the arc")
	assert_gt(fired[0], 0, "sanity: it does fire while the target is inside the arc")


func test_a_120_degree_mount_fires_normally_at_a_target_inside_the_arc() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 120.0)
	var t := _target(Vector2.from_angle(deg_to_rad(40.0)) * RADIUS)
	for i in 300:
		r.mount.tick(DT, t, true)
	assert_gte(r.rounds.size(), 4, "a full burst leaves at a target 40 degrees off rest")


func test_a_target_two_degrees_outside_the_arc_is_never_fired_on_though_the_aim_error_is_inside_the_cone() -> void:
	# The mount pegs at +60; the target sits at 62, so the aim error (2 deg) is inside half the 8 degree cone: only the arc rule holds fire.
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 120.0)
	var out := _target(Vector2.from_angle(deg_to_rad(62.0)) * RADIUS)
	for i in 300:
		r.mount.tick(DT, out, true)
	assert_lt(r.mount.aim_error(), deg_to_rad(4.0), "sanity: the aim error alone would allow a shot")
	assert_eq(r.rounds.size(), 0, "no round leaves with the target outside the arc")
	var inside := _target(Vector2.from_angle(deg_to_rad(58.0)) * RADIUS)
	for i in 300:
		r.mount.tick(DT, inside, true)
	assert_gt(r.rounds.size(), 0, "control: at 58 degrees it fires")


func test_a_burst_in_progress_stops_when_the_target_leaves_the_arc() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 120.0)
	var inside := _target(Vector2.from_angle(deg_to_rad(40.0)) * RADIUS)
	var n := 0
	while r.rounds.is_empty() and n < 200:
		r.mount.tick(DT, inside, true)
		n += 1
	assert_eq(r.rounds.size(), 1, "the first round of the burst is out")
	var outside := _target(Vector2.from_angle(deg_to_rad(100.0)) * RADIUS)
	for i in 60:
		r.mount.tick(DT, outside, true)
	assert_eq(r.rounds.size(), 1, "the rest of the burst is cut: the target left the arc")


func test_a_300_degree_mount_stays_inside_plus_minus_150_while_the_target_circles_through_its_blocked_sector() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 300.0)
	var half := deg_to_rad(150.0)
	var worst := 0.0
	var worst_step := 0.0
	var prev := r.mount.rotation
	for i in 600:
		r.mount.tick(DT, _orbit(i), true)
		worst = maxf(worst, absf(_offset(r.mount)))
		worst_step = maxf(worst_step, absf(r.mount.rotation - prev))
		prev = r.mount.rotation
	assert_lte(worst, half + EPS, "never past +-150 degrees of rest on any of 600 ticks (worst %.2f deg)" % rad_to_deg(worst))
	assert_lte(worst_step, r.mount.turn_rate * DT + 1e-6, "and never faster than turn_rate")


func test_a_300_degree_mount_reaches_the_far_side_of_its_arc_by_turning_the_long_way() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 300.0)
	var left := _target(Vector2.from_angle(deg_to_rad(140.0)) * RADIUS)
	for i in 120:
		r.mount.tick(DT, left, false)
	assert_almost_eq(rad_to_deg(_offset(r.mount)), 140.0, 1.0, "it settles on the target at +140")
	var right := _target(Vector2.from_angle(deg_to_rad(-140.0)) * RADIUS)
	var crossed_rest := false
	var prev := _offset(r.mount)
	var always_decreasing := true
	for i in 240:
		r.mount.tick(DT, right, false)
		var o := _offset(r.mount)
		always_decreasing = always_decreasing and o <= prev + 1e-9
		crossed_rest = crossed_rest or (prev > 0.0 and o <= 0.0)
		prev = o
	assert_true(crossed_rest, "it went through rest, not through the blocked sector at 180")
	assert_true(always_decreasing, "the offset only ever decreased on the way")
	assert_almost_eq(rad_to_deg(_offset(r.mount)), -140.0, 1.0, "and it arrives at -140")


func test_a_limited_mounts_scan_stays_inside_its_arc() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 40.0)
	var worst := 0.0
	for i in 1200:
		r.mount.scan(DT)
		worst = maxf(worst, absf(_offset(r.mount)))
	assert_lte(worst, deg_to_rad(20.0) + EPS, "the 90 degree scan arc is clamped into the +-20 degree traverse")
	assert_gt(worst, deg_to_rad(15.0), "sanity: it does sweep")


func test_the_slot_override_wins_and_a_negative_one_keeps_the_scene_value() -> void:
	var a := _rig(TurretMount.Variant.BURST_CANNON, 0.0, 90.0)
	assert_eq(a.mount.traverse_deg, 90.0, "override applied")
	var b := _rig(TurretMount.Variant.BURST_CANNON, 0.0)
	assert_eq(b.mount.traverse_deg, 360.0, "default 360")
	var c := _rig(TurretMount.Variant.HEAVY_CANNON, 0.0)
	assert_eq(c.mount.traverse_deg, float(TurretMountScenes.export_of(TurretMount.Variant.HEAVY_CANNON, &"traverse_deg", 360.0)), "scene value kept")


func test_a_360_degree_mounts_ten_second_trace_equals_the_pre_change_recording() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0)
	var got: Array[float] = []
	for i in 600:
		r.mount.tick(DT, _orbit(i), true)
		if i % 60 == 59:
			got.append(r.mount.rotation)
	if OS.is_stdout_verbose() or TRACE_360.is_empty():
		print("TRACE_360 ", got, " rounds ", r.rounds.size())
	assert_eq(got.size(), TRACE_360.size())
	for i in mini(got.size(), TRACE_360.size()):
		assert_almost_eq(got[i], TRACE_360[i], 1e-9, "sample %d" % i)
	assert_eq(r.rounds.size(), TRACE_360_ROUNDS, "and the round count")


# ── the builder ─────────────────────────────────────────────────────────────────────────────────────────────────────

func _pools(host: Node) -> Dictionary:
	var out := {}
	for c in host.get_children():
		if c is BulletPool:
			out[String(c.name)] = c
	return out


func test_the_builder_gives_a_defense_turret_the_pools_and_exports_it_always_had() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	t.set_physics_process(false)
	h.root.add_child(t)
	var m := t.mounts()[0] as BurstCannonMount
	var pools := _pools(t)
	assert_eq(pools.keys(), ["PulsePool_0"], "one pool, named by the pool spec and the slot index")
	var pool := pools["PulsePool_0"] as BulletPool
	assert_eq(pool.get_parent(), t, "a root child of the turret")
	assert_eq(pool.bullet_scene, EnemyRounds.PULSE)
	assert_eq(pool.pool_size, int(m.pool_specs()[0]["size"]), "sized by the mount's own spec")
	assert_false(pool.persist_after_owner_death)
	assert_eq(m.get_parent(), t.get_node("MountSlots/Slot0"), "under its slot")
	assert_eq(m.owner_group(), t.owner_group())
	assert_eq(m.traverse_deg, 360.0, "no limit on an authored turret")
	assert_eq(m.rest_bearing_deg, 90.0)


func test_the_builder_gives_the_heavy_emplacement_its_two_mounts_and_one_pool() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var t := HEAVY_SCENE.instantiate() as DefenseTurret
	t.set_physics_process(false)
	h.root.add_child(t)
	assert_eq(t.mounts().size(), 2)
	assert_eq(_pools(t).keys(), ["PulsePool_1"], "the beam cannon in slot 0 builds no pool; the burst cannon's carries its slot index")
	assert_true(t.mounts()[0] is BeamTurretMount)
	assert_true(t.mounts()[1] is BurstCannonMount)
	for m in t.mounts():
		assert_eq(m.traverse_deg, 360.0)


func test_the_builder_refuses_an_unbuilt_variant_without_a_pool() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON, 0.0)
	var slot := TurretMountSlot.new()
	slot.variant = 99 as TurretMount.Variant
	r.slot.get_parent().add_child(slot)
	var before := _pools(r.host).size()
	assert_null(TurretMountBuilder.build(r.host, slot, 3, RandomNumberGenerator.new(), OWNER))
	assert_eq(_pools(r.host).size(), before, "and builds nothing")


# ── HEAVY_CANNON ────────────────────────────────────────────────────────────────────────────────────────────────────

func test_every_mount_variant_has_a_scene_the_heavy_cannon_included(variant: int = use_parameters(TurretMount.Variant.values())) -> void:
	assert_not_null(TurretMountScenes.scene_for(variant), "variant %d is built" % variant)


func test_the_heavy_cannon_fires_two_heavy_shells_at_220_after_a_0_7_second_charge() -> void:
	var r := _rig(TurretMount.Variant.HEAVY_CANNON, 0.0)
	var m := r.mount as BurstCannonMount
	assert_eq(m.round_scene, EnemyRounds.HEAVY_SHELL)
	assert_eq(m.round_speed, 220.0)
	assert_eq(m.charge_seconds, 0.7)
	assert_eq(m.burst_count, 2)
	assert_eq(m.traverse_deg, 70.0, "the scene's own arc")
	var t := _target(Vector2.from_angle(deg_to_rad(10.0)) * 500.0)
	var clock := [0.0]
	var charge_start := [-1.0]
	var times: Array[float] = []
	m.phase_changed.connect(func(p: int) -> void:
		if p == TurretMount.Phase.TELEGRAPH:
			charge_start[0] = clock[0])
	m.round_fired.connect(func(p: Node2D) -> void:
		times.append(clock[0])
		assert_eq((p as EnemyBullet).speed, 220.0, "leaves at 220 px/s")
		assert_eq(p.scene_file_path, EnemyRounds.HEAVY_SHELL.resource_path, "a Heavy Shell"))
	for i in 600:
		clock[0] += DT
		m.tick(DT, t, true)
		if times.size() >= 2:
			break
	assert_eq(times.size(), 2, "a burst is two shells")
	assert_almost_eq(times[0] - charge_start[0], 0.7, DT * 1.5, "the first leaves 0.7 s after the charge begins")
	assert_almost_eq(times[1] - times[0], 0.35, DT * 1.5, "the second a burst gap later")
	for i in 120:
		m.tick(DT, t, true)
	assert_eq(r.rounds.size(), 2, "and no third within the 3.2 s cooldown")
