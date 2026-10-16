## Integration test for enemy-bullet lifetime (§2.9 of
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md, task t13-projectile-lifetime).
##
## Before this, `enemy_bullet.gd` expired at a hardcoded arena rectangle that only made sense in
## Assault, so an enemy bullet in Open Space (or any future mode) never expired at all.
## `ProjectileLifetime` (global/components/projectile_lifetime.gd) replaces that with world-space
## rules — max_time, max_distance from the origin, and an optional Assault world rect resolved
## through `EnemyWorld.projectile_world_rect()` — while reproducing today's Assault behaviour
## exactly: the legacy rect is x -164..1444, y -444..1164 (`ArenaCamera.projectile_world_rect()`,
## pinned by `tests/unit/test_enemy_world.gd`).
extends GutTest

const ENEMY_BULLET_SCENE: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
const SHIPPED_SNIPER: SniperConfig = preload("res://assault/scenes/enemies/sniper/sniper_config.tres")  # read only
const SNIPER_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/sniper/sniper.tscn")

func _ceil_to_100(v: float) -> float:
	return ceil(v / 100.0) * 100.0


## The legacy rect's diagonal, read from the real ArenaCamera rather than hardcoded, so this test
## re-derives from the authoritative source instead of a transcribed number (1608 x 1608 px per
## test_enemy_world.gd, diagonal ~2274.06 px).
func _legacy_rect_diagonal() -> float:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := cam.projectile_world_rect()
	return rect.size.length()


# ---------------------------------------------------------------------------------------------
# Derived defaults (F2): read every shipped speed source, recompute, and assert the shipped
# enemy_bullet.tscn / the derived defaults are >= the recomputed numbers (the rail round has its own, shorter caps and joins the per-round sweep below).
# ---------------------------------------------------------------------------------------------

## Every speed the Fighter fires at, by the round it fires: Pulse gets the AI aimed burst and both rail
## fallbacks (250 / 420, below the Pulse scene's 300), Scatter gets the AI forward burst. All are
## `FighterConfig` fields, so nothing here is typed by hand or read by regex.
func _fighter_speeds() -> Dictionary:
	var cfg: FighterConfig = load("res://assault/scenes/enemies/fighter/fighter_config.tres")
	return {
		"aimed": cfg.aimed_speed,
		"forward": cfg.forward_speed,
		"rail_aimed": cfg.rail_aimed_speed,
		"rail_forward": cfg.rail_forward_speed,
	}


## Every speed the Sniper fires Rail rounds at: the AI shot (`rail_speed`) and the rail fallback
## (`rail_fallback_speed`, today's 1400). Both are `SniperConfig` fields read from the shipped `.tres` (t12).
func _sniper_speeds() -> Dictionary:
	var cfg: SniperConfig = load("res://assault/scenes/enemies/sniper/sniper_config.tres")
	return {"rail": cfg.rail_speed, "rail_fallback": cfg.rail_fallback_speed}


## Every speed the Gatling Interceptor fires Gatling Stream rounds at: the AI stream (`round_speed`) and
## the rail fallback's legacy constant stream (`rail_stream_speed`, 220, below the round's 240 default).
## Both are `GatlingInterceptorConfig` fields read from the shipped `.tres` (t10).
func _gatling_speeds() -> Dictionary:
	var cfg: GatlingInterceptorConfig = \
			load("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")
	return {"stream": cfg.round_speed, "rail_stream": cfg.rail_stream_speed}


## One array, per the plan: add a new, slower bullet source here and the defaults must be
## re-derived (`3-plan.md` §2.9).
func _every_shipped_enemy_bullet_speed() -> Array[float]:
	var speeds: Array[float] = []

	# station_gunnery.gd's conservative no-config fallback (station_gunnery.gd:70,75).
	var gunnery := StationGunnery.new()
	speeds.append(gunnery.turret_bullet_speed)
	speeds.append(gunnery.core_bullet_speed)
	gunnery.free()

	# space_station_config.tres — the shipped tuning, not the script fallback above.
	var station_cfg: SpaceStationConfig = \
			load("res://assault/scenes/enemies/space_station/space_station_config.tres")
	speeds.append(station_cfg.turret_bullet_speed)
	speeds.append(station_cfg.core_bullet_speed)

	# Pattern resource defaults.
	speeds.append(RadialAttackPattern.new().bullet_speed)
	speeds.append(GatlingAttackPattern.new().bullet_speed)
	speeds.append(AimedAttackPattern.new().bullet_speed)

	# The Gatling Interceptor's shipped tuning: the AI stream and the rail fallback, config fields.
	for s in _gatling_speeds().values():
		speeds.append(s as float)

	# gunship_config.tres.
	var gunship_cfg: GunshipConfig = \
			load("res://assault/scenes/enemies/gunship/gunship_config.tres")
	speeds.append(gunship_cfg.bullet_speed)

	# EnemyBullet's own default `speed`.
	var default_bullet: EnemyBullet = ENEMY_BULLET_SCENE.instantiate()
	speeds.append(default_bullet.speed)
	default_bullet.free()

	# The Fighter's shipped tuning: AI rounds and the rail fallback's speeds, all config fields.
	for s in _fighter_speeds().values():
		speeds.append(s as float)

	# Racer weapon states (fired through RacerWeapon, which spawns EnemyBullet).
	var fang := FangHuntState.new()
	speeds.append(fang.bullet_speed)
	fang.free()
	var bg := BgReclaimState.new()
	speeds.append(bg.bullet_speed)
	bg.free()
	var isac := IsacSprayState.new()
	speeds.append(isac.bullet_speed)
	isac.free()

	# The Sniper's rail shots, by far the fastest, but enumerated for completeness (config fields).
	for s in _sniper_speeds().values():
		speeds.append(s as float)

	return speeds


func test_every_shipped_speed_source_is_at_or_above_150() -> void:
	## Sanity check on the source list itself: if a future change adds something slower than the
	## known 150 px/s fallback, this must be the test that goes red, not a silent min_speed drift.
	var speeds := _every_shipped_enemy_bullet_speed()
	assert_gt(speeds.size(), 0)
	assert_almost_eq(speeds.min() as float, 150.0, 0.001,
			"the slowest shipped source is station_gunnery.gd's no-config fallback (150 px/s)")


func test_enemy_bullet_defaults_are_derived_from_every_shipped_speed_source() -> void:
	var speeds := _every_shipped_enemy_bullet_speed()
	var min_speed: float = speeds.min() as float

	var diag := _legacy_rect_diagonal()
	var expected_max_time: float = ceil(diag / min_speed) + 2.0
	var expected_max_distance: float = _ceil_to_100(diag + 64.0)

	assert_almost_eq(expected_max_time, 18.0, 0.001, "sanity: matches the plan's derivation")
	assert_almost_eq(expected_max_distance, 2400.0, 0.001, "sanity: matches the plan's derivation")

	for scene: PackedScene in [ENEMY_BULLET_SCENE]:
		var bullet: EnemyBullet = scene.instantiate()
		var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
		assert_not_null(lifetime, "%s must carry a ProjectileLifetime child" % scene.resource_path)
		assert_gte(lifetime.max_time, expected_max_time,
				"%s's max_time must not be able to trip inside the legacy rect" % scene.resource_path)
		assert_gte(lifetime.max_distance, expected_max_distance,
				"%s's max_distance must not be able to trip inside the legacy rect" % scene.resource_path)
		bullet.free()


# ---------------------------------------------------------------------------------------------
# Per-round sweep (t2, 3-plan.md §2.2, review B5): max_distance / min_fired_speed <= max_time,
# plus a range floor (>= 1280px, except the Scatter Round, whose short range IS the design).
# A round with no shooter yet (all four this task) is checked at its own scene default speed.
# t8a gave the Fighter's rounds real config-field speeds, rail fallbacks included, and t10 the Gatling
# Interceptor's Gatling Stream; this sweep reads them, so no speed in it is hand-typed or regex-read.
# ---------------------------------------------------------------------------------------------

const _ROUNDS_RANGE_FLOOR_PX: float = 1280.0


## True when a round fired at its slowest speed reaches max_distance before max_time runs out -
## distance ends the bullet first, exactly like the legacy scene today.
func _round_clears_its_lifetime(max_distance: float, min_fired_speed: float, max_time: float) -> bool:
	return max_distance / min_fired_speed <= max_time


func test_every_round_clears_its_own_lifetime_at_its_slowest_fired_speed() -> void:
	var fs := _fighter_speeds()
	var gs := _gatling_speeds()
	var ss := _sniper_speeds()
	var entries: Array[Dictionary] = [
		{"scene": EnemyRounds.PULSE, "floor": _ROUNDS_RANGE_FLOOR_PX,
			"speeds": [fs["aimed"], fs["rail_aimed"], fs["rail_forward"]]},
		{"scene": EnemyRounds.GATLING_STREAM, "floor": _ROUNDS_RANGE_FLOOR_PX,
			"speeds": [gs["stream"], gs["rail_stream"]]},
		{"scene": EnemyRounds.RAIL, "floor": _ROUNDS_RANGE_FLOOR_PX,
			"speeds": [ss["rail"], ss["rail_fallback"]]},
		{"scene": EnemyRounds.HEAVY_SHELL, "floor": _ROUNDS_RANGE_FLOOR_PX},
		{"scene": EnemyRounds.SCATTER, "floor": 0.0, "speeds": [fs["forward"]]},
	]
	for entry: Dictionary in entries:
		var scene: PackedScene = entry["scene"]
		var bullet: EnemyBullet = scene.instantiate()
		add_child_autofree(bullet)
		var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
		# The slowest speed any shooter fires this round at; a round nobody fires yet (Heavy Shell) is
		# checked at its own scene default.
		var min_fired_speed: float = bullet.speed
		if entry.has("speeds"):
			min_fired_speed = (entry["speeds"] as Array).min() as float

		assert_true(_round_clears_its_lifetime(lifetime.max_distance, min_fired_speed, lifetime.max_time),
				"%s must not run out of max_time before max_distance at its slowest fired speed"
				% scene.resource_path)
		assert_gte(lifetime.max_distance, entry["floor"] as float, scene.resource_path)


func test_a_synthetic_100px_per_s_round_fails_the_sweep() -> void:
	# The shared legacy budget (18s / 2400px, this file's own derived defaults above) at a
	# hypothetical 100px/s: 2400 / 100 = 24 > 18 - this round would time out short of its range.
	assert_false(_round_clears_its_lifetime(2400.0, 100.0, 18.0),
			"a round this slow would time out before it reaches its own max_distance")


# ---------------------------------------------------------------------------------------------
# Enemy ordnance (3-plan.md of cmufs7ele0015nm2xvag3vrwc §2.3, task t6): a separate family with its
# own explicit caps, so it gets per-KIND rows instead of joining the round sweep above. Its speeds
# (120 and 90 px/s) must never enter `_every_shipped_enemy_bullet_speed()`: they would trip the
# >= 150 px/s rule and shift the derived 18 s / 2400 px round defaults.
#
# Speeds and times are read from the shipped `BomberConfig` ordnance fields (bomber_config.tres).
# ---------------------------------------------------------------------------------------------

const _SHIPPED_BOMBER: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")  # read only


func _ordnance_lifetime(kind: EnemyOrdnance.Kind) -> ProjectileLifetime:
	var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
	add_child_autofree(o)
	return o.get_node("ProjectileLifetime") as ProjectileLifetime


## Constant-speed kind: its distance cap is reached before its time cap.
func _constant_speed_kind_clears(max_distance: float, slowest_speed: float, max_time: float) -> bool:
	return max_distance / slowest_speed <= max_time


## Two-speed kind (steers at the launch speed for a window, then runs at the final speed): the
## constant-speed formula does not model it.
func _two_speed_kind_clears(window: float, launch_speed: float, final_speed: float,
		max_distance: float, max_time: float) -> bool:
	return window + (max_distance - launch_speed * window) / final_speed <= max_time


func test_the_gravity_bomb_clears_its_lifetime_at_its_slowest_fired_speed() -> void:
	var cfg: BomberConfig = _SHIPPED_BOMBER
	var lt := _ordnance_lifetime(EnemyOrdnance.Kind.GRAVITY_BOMB)
	assert_true(_constant_speed_kind_clears(lt.max_distance,
			minf(cfg.gravity_bomb_speed, cfg.rail_bomb_speed), lt.max_time),
			"gravity bomb: max_distance / slowest speed must fit max_time (1800 / 120 = 15 <= 16)")


func test_the_pursuit_bomb_clears_its_lifetime_through_both_of_its_speeds() -> void:
	var cfg: BomberConfig = _SHIPPED_BOMBER
	var lt := _ordnance_lifetime(EnemyOrdnance.Kind.PURSUIT_BOMB)
	assert_true(_two_speed_kind_clears(cfg.pursuit_steer_window, cfg.pursuit_launch_speed,
			cfg.pursuit_final_speed, lt.max_distance, lt.max_time),
			"pursuit bomb: steer window + the rest at the final speed must fit max_time (7.46 <= 10)")


func test_the_mine_is_time_bound_only() -> void:
	var cfg: BomberConfig = _SHIPPED_BOMBER
	var lt := _ordnance_lifetime(EnemyOrdnance.Kind.MINE)
	assert_eq(lt.max_distance, 0.0, "a stationary mine has no distance cap")
	assert_lt(cfg.mine_life, lt.max_time, "the mine fizzles before its backstop")


func test_a_synthetic_100px_per_s_gravity_bomb_fails_its_row() -> void:
	var lt := _ordnance_lifetime(EnemyOrdnance.Kind.GRAVITY_BOMB)
	assert_false(_constant_speed_kind_clears(lt.max_distance, 100.0, lt.max_time),
			"1800 / 100 = 18 s > the 16 s backstop: the row can reject")


func test_no_ordnance_speed_is_in_the_round_speed_list() -> void:
	var cfg: BomberConfig = _SHIPPED_BOMBER
	var speeds := _every_shipped_enemy_bullet_speed()
	for s: float in [cfg.gravity_bomb_speed, cfg.rail_bomb_speed, cfg.pursuit_launch_speed]:
		assert_false(speeds.has(s),
				"%s px/s is ordnance, which has its own rows - it must not shift the round defaults" % s)


# ---------------------------------------------------------------------------------------------
# Enemy rockets (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.6, t5): the straight-line time to
# cover `max_distance` with zero inheritance (the slowest case) - `boost_seconds` at `launch_speed`,
# then accelerating at `accel` to `cruise_speed`, then the rest at `cruise_speed` - must fit `max_time`,
# so the distance cap, not the clock, ends a straight rocket. Every number is the rocket scene's export.
# ---------------------------------------------------------------------------------------------

func _rocket(kind: EnemyRocket.Kind) -> EnemyRocket:
	var r: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
	add_child_autofree(r)
	return r


## Seconds a straight rocket takes to cover `distance` from a standing launch.
func _rocket_straight_time(launch: float, cruise: float, boost: float, accel: float, distance: float) -> float:
	var boost_d := launch * boost
	if boost_d >= distance:
		return distance / launch
	var ramp_t := absf(cruise - launch) / accel if accel > 0.0 else 0.0
	var ramp_d := (launch + cruise) * 0.5 * ramp_t
	if boost_d + ramp_d >= distance:
		# Solve launch*t + 0.5*a*t^2 = rest for the ramp time actually used.
		var rest := distance - boost_d
		var t := (-launch + sqrt(launch * launch + 2.0 * accel * rest)) / accel
		return boost + t
	return boost + ramp_t + (distance - boost_d - ramp_d) / cruise


func _rocket_clears(r: EnemyRocket) -> bool:
	return _rocket_straight_time(r.launch_speed, r.cruise_speed, r.boost_seconds, r.accel, r.max_distance) \
			<= r.max_time


func test_the_dumb_rocket_clears_its_lifetime_through_boost_ramp_and_cruise() -> void:
	var r := _rocket(EnemyRocket.Kind.DUMB)
	var t := _rocket_straight_time(r.launch_speed, r.cruise_speed, r.boost_seconds, r.accel, r.max_distance)
	assert_almost_eq(t, 3.80, 0.01, "DUMB: 0.25 + 0.42 + 3.13 s to cover 1800 px")
	assert_true(_rocket_clears(r), "DUMB: %.2f s must fit max_time %.1f" % [t, r.max_time])
	var lt := r.get_node("ProjectileLifetime") as ProjectileLifetime
	assert_eq(lt.max_time, r.max_time, "the lifetime child carries the rocket's own max_time")
	assert_eq(lt.max_distance, r.max_distance, "the lifetime child carries the rocket's own max_distance")


func test_the_pursuit_rocket_clears_its_lifetime_through_boost_ramp_and_cruise() -> void:
	var r := _rocket(EnemyRocket.Kind.PURSUIT)
	var t := _rocket_straight_time(r.launch_speed, r.cruise_speed, r.boost_seconds, r.accel, r.max_distance)
	assert_almost_eq(t, 5.90, 0.01, "PURSUIT: 0.35 + 0.53 + 5.02 s to cover 2400 px")
	assert_true(_rocket_clears(r), "PURSUIT: %.2f s must fit max_time %.1f" % [t, r.max_time])
	var lt := r.get_node("ProjectileLifetime") as ProjectileLifetime
	assert_eq(lt.max_time, r.max_time)
	assert_eq(lt.max_distance, r.max_distance)


func test_the_cluster_submunition_and_warhead_clear_their_lifetimes_through_boost_ramp_and_cruise() -> void:
	for row: Array in [
			[EnemyRocket.Kind.CLUSTER, 3.55, "CLUSTER: 0.35 + 0.43 + 2.77 s to cover 1200 px"],
			[EnemyRocket.Kind.SUBMUNITION, 1.15, "SUBMUNITION: 600 px at 520 px/s, no boost, no ramp"],
			[EnemyRocket.Kind.WARHEAD, 5.76, "WARHEAD: 0.35 + 0.47 + 4.94 s to cover 1300 px"]]:
		var r := _rocket(row[0])
		var t := _rocket_straight_time(r.launch_speed, r.cruise_speed, r.boost_seconds, r.accel, r.max_distance)
		assert_almost_eq(t, float(row[1]), 0.02, str(row[2]))
		assert_true(_rocket_clears(r), "%s: %.2f s must fit max_time %.1f" % [row[2], t, r.max_time])
		var lt := r.get_node("ProjectileLifetime") as ProjectileLifetime
		assert_eq(lt.max_time, r.max_time, "the lifetime child carries the rocket's own max_time")
		assert_eq(lt.max_distance, r.max_distance, "the lifetime child carries the rocket's own max_distance")


func test_a_slow_cruising_rocket_fails_its_row() -> void:
	var r := _rocket(EnemyRocket.Kind.PURSUIT)
	r.cruise_speed = 380.0
	assert_false(_rocket_clears(r), "2400 px at a 380 px/s cruise takes ~6.7 s > 6.0 s: the row can reject")

	# A submunition that flew 20 px/s slower would outlive its 1.2 s.
	var sub := _rocket(EnemyRocket.Kind.SUBMUNITION)
	sub.launch_speed = 480.0
	sub.cruise_speed = 480.0
	assert_false(_rocket_clears(sub), "600 px at 480 px/s takes 1.25 s > 1.2 s: the submunition row can reject")


func test_no_rocket_speed_is_in_the_round_speed_list() -> void:
	var speeds := _every_shipped_enemy_bullet_speed()
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER,
			EnemyRocket.Kind.SUBMUNITION, EnemyRocket.Kind.WARHEAD]:
		var r := _rocket(kind)
		# The Delayed Warhead cruises at 240 px/s, which a round also fires at: a value match proves nothing about
		# the list, so its cruise is exempt and the launch speed (100) still has to stay out.
		var checked: Array[float] = [r.launch_speed]
		if kind != EnemyRocket.Kind.WARHEAD:
			checked.append(r.cruise_speed)
		for s: float in checked:
			assert_false(speeds.has(s), "%s px/s is a rocket speed; rockets have their own rows" % s)


# ---------------------------------------------------------------------------------------------
# Boundary: x = 1444 lives, x = 1444.1 expires, with the Assault provider. No provider: both live.
# ---------------------------------------------------------------------------------------------

func test_boundary_x_1444_lives_and_1444_1_expires_with_the_assault_provider() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)

	var bullet: EnemyBullet = ENEMY_BULLET_SCENE.instantiate()
	add_child_autofree(bullet)
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	bullet.global_position = Vector2(1444.0, 300.0)
	lifetime.reset()  # arms with the provider's rect

	watch_signals(bullet)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 0, "x = 1444 is the rect's own right edge — lives")

	bullet.global_position = Vector2(1444.1, 300.0)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 1, "x = 1444.1 is past the right edge — expires")


func test_boundary_position_lives_with_no_provider_in_the_tree() -> void:
	var bullet: EnemyBullet = ENEMY_BULLET_SCENE.instantiate()
	add_child_autofree(bullet)
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	bullet.global_position = Vector2(1444.1, 300.0)
	lifetime.reset()

	watch_signals(bullet)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 0,
			"with no Assault provider, the rect rule is a no-op — only time/distance apply")


# ---------------------------------------------------------------------------------------------
# A pooled bullet is recycled, never freed.
# ---------------------------------------------------------------------------------------------

## Deliberately drives the recycle through the real `expired -> _recycle` wiring
## (`bullet_pool.gd:56`), the same wiring `test_player_bullet_lifetime.gd`'s pooled-bullet test
## guards for the player's own bullet — checked by reuse through `acquire()`, never by `_idle.size()`
## (see that file's header for why a size check reads healthy on a broken build).
func test_a_pooled_bullet_is_recycled_never_freed_when_its_lifetime_expires() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var ship := Node2D.new()
	container.add_child(ship)
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	pool.bullet_scene = ENEMY_BULLET_SCENE
	pool.pool_size = 2
	ship.add_child(pool)

	var bullet := pool.acquire(Vector2(100.0, 100.0)) as EnemyBullet
	assert_not_null(bullet, "the pool should hand out a bullet")
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	watch_signals(bullet)

	lifetime.expire_now()
	assert_signal_emit_count(bullet, "expired", 1, "expired must fire exactly once per life")
	await get_tree().process_frame  # _recycle() is call_deferred

	assert_true(is_instance_valid(bullet),
			"a pooled bullet's lifetime rule must recycle it, never free it")
	assert_false(bullet.is_queued_for_deletion())

	var reacquired := pool.acquire(Vector2(140.0, 100.0)) as EnemyBullet
	assert_same(reacquired, bullet,
			"the pool must hand the SAME recycled instance back out — a freed bullet would come "
			+ "back as a brand-new object, which acquire() would still return, hiding the bug")


# ---------------------------------------------------------------------------------------------
# The Sniper's pooled rail round, through the REAL fallback fire path (`SniperTelegraph._fire_rail_shot`).
# ---------------------------------------------------------------------------------------------

## The rail round is pooled, so its single owner is the sniper's `RailPool`: it must be positioned at the
## muzzle and armed by `reset()` (the pool calls it in `acquire()`), see the legacy rect, expire on crossing
## it, and be RECYCLED - never freed - well under its 4 s `max_time`. This replaces the unpooled
## `enemy_sniper_bullet.tscn` case (`Sniper._phase_fire()` is gone with the scene).
func test_the_pooled_rail_round_expires_and_is_recycled_after_crossing_the_legacy_rect() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)

	var container := Node2D.new()
	add_child_autofree(container)
	var sniper: Sniper = SNIPER_SCENE.instantiate()
	container.add_child(sniper)

	# The muzzle sits at local (0, -20); rotation = PI/2 puts it 20 px to the right of the ship, and the
	# round flies right - inside the legacy rect (right edge x = 1444) it crosses in a couple of physics
	# frames at the fallback's 1400 px/s.
	sniper.global_position = Vector2(1400.0, 300.0)
	sniper.rotation = PI / 2.0
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var pool := sniper.get_node("RailPool") as BulletPool
	telegraph._rail_lock_point = telegraph.muzzle.global_position + Vector2.RIGHT * 100.0

	var bullet := telegraph._fire_rail_shot(telegraph.muzzle.global_position)
	assert_not_null(bullet, "the fallback must have taken a real rail round from the pool")
	assert_eq(bullet.speed, SHIPPED_SNIPER.rail_fallback_speed, "fired at the fallback speed")

	var left := false
	for _i in 30:  # 30 physics frames at 60 fps = 0.5 s, far short of the 4 s max_time
		await get_tree().physics_frame
		if bullet.get_parent() == pool:
			left = true
			break
	assert_true(left,
			"the rail round must be recycled into its pool on crossing the legacy rect, well under its 4 s "
			+ "max_time - a build that only arms on reset() would keep it flying instead")
	assert_true(is_instance_valid(bullet) and not bullet.is_queued_for_deletion(),
			"and recycled, never freed")


# ---------------------------------------------------------------------------------------------
# Race regression: race_level_1.tscn's Camera2D already carries the ArenaCamera script, so an
# enemy bullet fired in a race scene gets the legacy rect with NO race-specific wiring.
# ---------------------------------------------------------------------------------------------

func test_race_level_1_camera_is_already_an_arena_camera_provider() -> void:
	var race_scene: PackedScene = load("res://assault/scenes/levels/race/race_level_1.tscn")
	var state := race_scene.get_state()
	var cam_script: Script = null
	for i in state.get_node_count():
		if state.get_node_name(i) == "Camera2D":
			for p in state.get_node_property_count(i):
				if state.get_node_property_name(i, p) == "script":
					cam_script = state.get_node_property_value(i, p)
	assert_not_null(cam_script, "race_level_1.tscn's Camera2D must carry a script")
	assert_eq(cam_script.resource_path, "res://assault/scenes/systems/arena_camera.gd",
			"the race gets the legacy rect through ArenaCamera with no race-specific wiring")


func test_a_race_bullet_still_expires_at_the_legacy_rect() -> void:
	# Reproduces race_level_1.tscn's own wiring: a bare Camera2D running arena_camera.gd, sibling
	# of a "Level1Background" node (ArenaCamera._ready() only skips its background-anchoring setup
	# without it — the group join itself is unconditional).
	var level := Node2D.new()
	add_child_autofree(level)
	var cam := Camera2D.new()
	cam.set_script(load("res://assault/scenes/systems/arena_camera.gd"))
	level.add_child(cam)

	var bullet: EnemyBullet = ENEMY_BULLET_SCENE.instantiate()
	level.add_child(bullet)
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	bullet.global_position = Vector2(1444.1, 300.0)
	lifetime.reset()

	watch_signals(bullet)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 1,
			"a race bullet outside the legacy rect must still expire")
