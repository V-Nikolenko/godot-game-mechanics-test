## Turret mount variants SPREAD_CANNON and RAPID_PULSE (Phase 11 t3, docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.3) and the `pellets` fan on
## `BurstCannonMount`. INTENT tests, hand-ticked at 1/60 s like `test_turret_mount_traverse.gd`: a mount is built through the real
## `TurretMountBuilder` under a plain host and fed a `TargetInfo` per tick.
##
## `pellets` 1 is the bit-identity gate: the same 600-tick recording `test_turret_mount_traverse.gd` pins (`TRACE_360`), plus the round directions.
extends GutTest

const DT := 1.0 / 60.0
const OWNER := &"variants_test_owner"
const RANGE := 300.0
## The traverse gate's recording of a default burst cannon (rest 0, seed 7) - shared on purpose: `pellets` 1 must not move it.
const TRACE_360: Array[float] = [1.02339839935303, 1.65171682834625, 2.28003549575806, 2.90835404396057, 3.53667235374451, 4.16499137878418, 4.79330968856812, 5.42162799835205, 6.04994678497314, 6.67826509475708]
const TRACE_360_ROUNDS := 12
const SCATTER_PATH := "res://assault/scenes/projectiles/enemy_bullet/rounds/scatter_round.tscn"
const PULSE_PATH := "res://assault/scenes/projectiles/enemy_bullet/rounds/pulse_round.tscn"


class _Rig:
	extends RefCounted
	var root: Node2D
	var host: Node2D
	var mount: TurretMount
	var rounds: Array = []
	var directions: Array[float] = []
	var times: Array[float] = []
	var clock: float = 0.0


func _rig(variant: int) -> _Rig:
	var r := _Rig.new()
	r.root = Node2D.new()
	add_child_autofree(r.root)
	r.host = Node2D.new()
	r.root.add_child(r.host)
	var slots := Node2D.new()
	r.host.add_child(slots)
	var slot := TurretMountSlot.new()
	slot.variant = variant
	slot.rest_bearing_deg = 0.0
	slots.add_child(slot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	r.mount = TurretMountBuilder.build(r.host, slot, 0, rng, OWNER)
	r.mount.round_fired.connect(func(p: Node2D) -> void:
		r.rounds.append(p)
		r.directions.append((p as EnemyBullet).rotation + PI / 2.0)
		r.times.append(r.clock))
	return r


func _target(pos: Vector2) -> TargetInfo:
	var t := TargetInfo.new()
	t.has_target = true
	t.position = pos
	return t


## Ticks the rig at a still target dead ahead until [param n] rounds are out (or 600 ticks).
func _fire_until(r: _Rig, n: int) -> void:
	var t := _target(Vector2(RANGE, 0.0))
	for i in 600:
		r.clock += DT
		r.mount.tick(DT, t, true)
		if r.rounds.size() >= n:
			break


func _orbit(i: int) -> TargetInfo:
	var a := TAU * float(i) / 600.0
	var t := _target(Vector2.from_angle(a) * RANGE)
	t.velocity = Vector2.from_angle(a + PI * 0.5) * RANGE * TAU / 10.0
	return t


func _scene_round_max_distance(round_scene: PackedScene) -> float:
	var b := round_scene.instantiate() as EnemyBullet
	var d := (b.get_node("ProjectileLifetime") as ProjectileLifetime).max_distance
	b.free()
	return d


# ── SPREAD_CANNON ───────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_spread_burst_is_two_volleys_of_five_scatter_rounds_across_forty_degrees() -> void:
	var r := _rig(TurretMount.Variant.SPREAD_CANNON)
	var m := r.mount as BurstCannonMount
	assert_eq(m.pellets, 5)
	assert_eq(m.burst_count, 2)
	_fire_until(r, 10)
	for i in 120:
		r.clock += DT
		r.mount.tick(DT, _target(Vector2(RANGE, 0.0)), true)
	assert_eq(r.rounds.size(), 10, "2 x 5 rounds in the burst and no more inside the cooldown")
	for p in r.rounds:
		assert_eq(p.scene_file_path, SCATTER_PATH, "each pellet is a Scatter round")
		assert_eq((p as EnemyBullet).speed, 260.0, "at the mount's round speed")
	var aim := r.mount.global_rotation
	for volley in 2:
		var angles: Array[float] = []
		for k in 5:
			angles.append(r.directions[volley * 5 + k])
		var lo: float = angles.min()
		var hi: float = angles.max()
		assert_almost_eq(rad_to_deg(hi - lo), 40.0, 0.5, "volley %d spans 40 degrees" % volley)
		assert_almost_eq(rad_to_deg(hi - aim), 20.0, 3.0, "the outer pellets are +20 off the aim")
		assert_almost_eq(rad_to_deg(lo - aim), -20.0, 3.0, "and -20")
		var sorted := angles.duplicate()
		sorted.sort()
		assert_almost_eq(rad_to_deg(sorted[2] - aim), 0.0, 3.0, "the middle pellet is on the aim")
		assert_almost_eq(rad_to_deg(sorted[3] - sorted[2]), 10.0, 0.5, "evenly spaced at 10 degrees")


func test_the_two_volleys_of_a_spread_burst_are_a_burst_gap_apart() -> void:
	var r := _rig(TurretMount.Variant.SPREAD_CANNON)
	_fire_until(r, 10)
	assert_eq(r.rounds.size(), 10)
	assert_almost_eq(r.times[5] - r.times[0], 0.45, DT * 1.5)
	assert_almost_eq(r.times[4] - r.times[0], 0.0, 1e-9, "a volley leaves on one tick")


func test_a_spread_mounts_pool_holds_a_whole_burst_and_scales_with_pellets() -> void:
	var r := _rig(TurretMount.Variant.SPREAD_CANNON)
	var spec: Dictionary = r.mount.pool_specs()[0]
	var m := r.mount as BurstCannonMount
	var max_time := float(EnemyBeamScenes.export_of_scene(m.round_scene, &"max_time", 18.0, ^"ProjectileLifetime"))
	var period := m.charge_seconds + (m.burst_count - 1) * m.burst_gap + m.cooldown_seconds
	assert_eq(int(spec["size"]), EnemyRounds.pool_size_for(10, max_time, period), "burst_count x pellets rounds")
	assert_gte(int(spec["size"]), 10)
	m.pellets = 1
	assert_eq(int(m.pool_specs()[0]["size"]), EnemyRounds.pool_size_for(2, max_time, period), "one pellet is the old size")


func test_a_pellet_the_pool_cannot_supply_is_counted_refused_and_the_rest_still_leave() -> void:
	var r := _rig(TurretMount.Variant.SPREAD_CANNON)
	var pool := r.host.get_child(r.host.get_child_count() - 1) as BulletPool
	assert_not_null(pool)
	for i in pool.pool_size - 3:
		pool.acquire(Vector2.ZERO)
	_fire_until(r, 3)
	assert_eq(r.rounds.size(), 3, "only three rounds were left in the pool")
	assert_gt((r.mount as BurstCannonMount).shots_refused, 0)


# ── RAPID_PULSE ─────────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_rapid_burst_is_ten_pulse_rounds_seventy_milliseconds_apart() -> void:
	var r := _rig(TurretMount.Variant.RAPID_PULSE)
	_fire_until(r, 10)
	assert_eq(r.rounds.size(), 10)
	for p in r.rounds:
		assert_eq(p.scene_file_path, PULSE_PATH, "a Pulse round")
		assert_eq((p as EnemyBullet).speed, 340.0)
	for i in range(1, 10):
		assert_almost_eq(r.times[i] - r.times[i - 1], 0.07, DT * 1.01, "round %d" % i)
	for i in 100:
		r.clock += DT
		r.mount.tick(DT, _target(Vector2(RANGE, 0.0)), true)
	assert_eq(r.rounds.size(), 10, "no eleventh inside the cooldown")


# ── pellets = 1 stays bit-identical ─────────────────────────────────────────────────────────────────────────────────

func test_pellets_one_is_the_recorded_trace_and_every_round_leaves_along_the_aim() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON)
	assert_eq((r.mount as BurstCannonMount).pellets, 1)
	assert_eq((r.mount as BurstCannonMount).pellet_spread_deg, 0.0)
	var got: Array[float] = []
	var aims: Array[float] = []
	r.mount.round_fired.connect(func(_p: Node2D) -> void: aims.append(r.mount.global_rotation))
	for i in 600:
		r.mount.tick(DT, _orbit(i), true)
		if i % 60 == 59:
			got.append(r.mount.rotation)
	assert_eq(got.size(), TRACE_360.size())
	for i in mini(got.size(), TRACE_360.size()):
		assert_almost_eq(got[i], TRACE_360[i], 1e-9, "sample %d" % i)
	assert_eq(r.rounds.size(), TRACE_360_ROUNDS)
	for i in r.directions.size():
		assert_almost_eq(wrapf(r.directions[i] - aims[i], -PI, PI), 0.0, 1e-6, "round %d leaves exactly along the aim (float32 rotation)" % i)


func test_a_pellet_count_of_zero_is_read_as_one() -> void:
	var r := _rig(TurretMount.Variant.BURST_CANNON)
	(r.mount as BurstCannonMount).pellets = 0
	_fire_until(r, 4)
	assert_eq(r.rounds.size(), 4)


# ── builder, exports, reach ─────────────────────────────────────────────────────────────────────────────────────────

func test_the_builder_builds_both_variants_with_their_pools(variant: int = use_parameters([TurretMount.Variant.SPREAD_CANNON, TurretMount.Variant.RAPID_PULSE])) -> void:
	var r := _rig(variant)
	assert_true(r.mount is BurstCannonMount)
	var pools: Array[BulletPool] = []
	for c in r.host.get_children():
		if c is BulletPool:
			pools.append(c)
	assert_eq(pools.size(), 1, "one pool")
	assert_eq(pools[0].get_parent(), r.host, "a root child of the host")
	assert_eq(pools[0].bullet_scene, (r.mount as BurstCannonMount).round_scene)
	assert_eq(pools[0].pool_size, int(r.mount.pool_specs()[0]["size"]))
	assert_false(pools[0].persist_after_owner_death)
	assert_eq(r.mount.owner_group(), OWNER)


func test_export_of_returns_the_authored_values_not_the_script_defaults() -> void:
	var s := TurretMount.Variant.SPREAD_CANNON
	var p := TurretMount.Variant.RAPID_PULSE
	assert_eq(float(TurretMountScenes.export_of(s, &"round_speed", -1.0)), 260.0)
	assert_eq(float(TurretMountScenes.export_of(s, &"fire_range", -1.0)), 420.0)
	assert_eq(int(TurretMountScenes.export_of(s, &"pellets", -1)), 5)
	assert_eq(float(TurretMountScenes.export_of(s, &"pellet_spread_deg", -1.0)), 40.0)
	assert_eq(int(TurretMountScenes.export_of(s, &"burst_count", -1)), 2)
	assert_eq(float(TurretMountScenes.export_of(s, &"burst_gap", -1.0)), 0.45)
	assert_eq(float(TurretMountScenes.export_of(s, &"charge_seconds", -1.0)), 0.5)
	assert_eq(float(TurretMountScenes.export_of(s, &"cooldown_seconds", -1.0)), 2.8)
	assert_eq(float(TurretMountScenes.export_of(p, &"round_speed", -1.0)), 340.0)
	assert_eq(float(TurretMountScenes.export_of(p, &"fire_range", -1.0)), 760.0)
	assert_eq(int(TurretMountScenes.export_of(p, &"burst_count", -1)), 10)
	assert_eq(float(TurretMountScenes.export_of(p, &"burst_gap", -1.0)), 0.07)
	assert_eq(float(TurretMountScenes.export_of(p, &"charge_seconds", -1.0)), 0.3)
	assert_eq(float(TurretMountScenes.export_of(p, &"cooldown_seconds", -1.0)), 2.6)
	assert_eq(float(TurretMountScenes.export_of(p, &"turn_rate", -1.0)), 2.6)
	assert_eq(int(TurretMountScenes.export_of(p, &"pellets", -1)), 1, "the pulse mount is a single-round gun")
	assert_eq(TurretMountScenes.reach_of(s), 420.0)
	assert_eq(TurretMountScenes.reach_of(p), 760.0)


func test_both_new_scenes_are_standalone_and_author_their_own_round() -> void:
	for v in [TurretMount.Variant.SPREAD_CANNON, TurretMount.Variant.RAPID_PULSE]:
		var scene := TurretMountScenes.scene_for(v)
		assert_eq(scene.get_state().get_node_instance(0), null, "variant %d: the root is not an inherited scene" % v)
		var m := scene.instantiate() as BurstCannonMount
		assert_not_null(m.get_node_or_null("Muzzle"))
		assert_eq((m.get_node("Muzzle") as Marker2D).position, Vector2(28.0, 0.0))
		m.free()
	var spread := TurretMountScenes.scene_for(TurretMount.Variant.SPREAD_CANNON).instantiate() as BurstCannonMount
	var pulse := TurretMountScenes.scene_for(TurretMount.Variant.RAPID_PULSE).instantiate() as BurstCannonMount
	assert_eq(spread.round_scene, EnemyRounds.SCATTER)
	assert_eq(pulse.round_scene, EnemyRounds.PULSE)
	spread.free()
	pulse.free()


## A mount that stands off further than its round flies never hits: the muzzle sits `Muzzle.x` ahead and the round then travels `max_distance`.
## Every variant that fires `EnemyBullet` rounds is checked; the beams, the lance and the rocket launcher fire something else.
func _bullet_firing_variants() -> Array[int]:
	var out: Array[int] = []
	for v in TurretMount.Variant.values():
		var m := TurretMountScenes.scene_for(v).instantiate()
		if m is BurstCannonMount:
			out.append(v)
		m.free()
	return out


func _reach_fits(fire_range: float, max_distance: float) -> bool:
	return fire_range <= max_distance


func test_every_bullet_firing_variant_reaches_no_further_than_its_round_flies() -> void:
	var variants := _bullet_firing_variants()
	assert_true(variants.has(TurretMount.Variant.SPREAD_CANNON), "sanity: the sweep sees the new mounts")
	assert_true(variants.has(TurretMount.Variant.RAPID_PULSE))
	assert_true(variants.has(TurretMount.Variant.HEAVY_CANNON))
	for v in variants:
		var m := TurretMountScenes.scene_for(v).instantiate() as BurstCannonMount
		var max_distance := _scene_round_max_distance(m.round_scene)
		assert_true(_reach_fits(m.fire_range, max_distance), "%s: fire_range %.0f <= its round's max_distance %.0f" % [TurretMount.Variant.keys()[v], m.fire_range, max_distance])
		m.free()


func test_a_spread_mount_at_520_fails_the_reach_row() -> void:
	var m := TurretMountScenes.scene_for(TurretMount.Variant.SPREAD_CANNON).instantiate() as BurstCannonMount
	assert_false(_reach_fits(520.0, _scene_round_max_distance(m.round_scene)), "520 px outruns a Scatter round's 450")
	m.free()
