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
const SNIPER_BULLET_SCENE: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn")
const SNIPER_ENEMY_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn")

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
# enemy_bullet.tscn / enemy_sniper_bullet.tscn defaults are >= the recomputed numbers.
# ---------------------------------------------------------------------------------------------

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

	# interceptor_config.gd's default (the shipped .tres does not override bullet_speed).
	speeds.append(InterceptorConfig.new().bullet_speed)

	# gunship_config.tres.
	var gunship_cfg: GunshipConfig = \
			load("res://assault/scenes/enemies/gunship/gunship_config.tres")
	speeds.append(gunship_cfg.bullet_speed)

	# EnemyBullet's own default `speed`.
	var default_bullet: EnemyBullet = ENEMY_BULLET_SCENE.instantiate()
	speeds.append(default_bullet.speed)
	default_bullet.free()

	# light_assault_ship.gd:42 — `pattern.bullet_speed = 420.0 if forward else 250.0`, a literal,
	# not an export, so it is read out of the shipped source text rather than hardcoded here.
	var light_assault_src: String = FileAccess.get_file_as_string(
			"res://assault/scenes/enemies/light_assault_ship/light_assault_ship.gd")
	var m := RegEx.new()
	m.compile("bullet_speed\\s*=\\s*([0-9.]+)\\s*if forward else\\s*([0-9.]+)")
	var found := m.search(light_assault_src)
	assert_not_null(found, "light_assault_ship.gd's bullet_speed line must still match this shape")
	speeds.append(found.get_string(1).to_float())
	speeds.append(found.get_string(2).to_float())

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

	# The sniper shot — by far the fastest, but enumerated for completeness.
	var sniper_bullet: EnemyBullet = SNIPER_BULLET_SCENE.instantiate()
	speeds.append(sniper_bullet.speed)
	sniper_bullet.free()

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

	for scene: PackedScene in [ENEMY_BULLET_SCENE, SNIPER_BULLET_SCENE]:
		var bullet: EnemyBullet = scene.instantiate()
		var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
		assert_not_null(lifetime, "%s must carry a ProjectileLifetime child" % scene.resource_path)
		assert_gte(lifetime.max_time, expected_max_time,
				"%s's max_time must not be able to trip inside the legacy rect" % scene.resource_path)
		assert_gte(lifetime.max_distance, expected_max_distance,
				"%s's max_distance must not be able to trip inside the legacy rect" % scene.resource_path)
		bullet.free()


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
# The unpooled sniper shot, through the REAL SniperEnemy._phase_fire() path.
# ---------------------------------------------------------------------------------------------

## `sniper_enemy.gd:99-105` never calls reset() — the shot is positioned at the muzzle only after
## add_child(). This is exactly the case the lazy-arm rule (F1) exists for: if arming ever moved
## back into ProjectileLifetime._ready(), the shot would record the wrong origin at the parent's
## position and never see the Assault provider's rect, so it would fly for the full 18s instead of
## dying on this rect crossing.
func test_the_unpooled_sniper_shot_is_freed_after_crossing_the_legacy_rect() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)

	var container := Node2D.new()
	add_child_autofree(container)
	var sniper: SniperEnemy = SNIPER_ENEMY_SCENE.instantiate()
	container.add_child(sniper)

	# Muzzle sits at local (0, -20); rotation = PI/2 makes Vector2.UP.rotated(rotation) point at
	# +X, so the muzzle is 20px to the right of the ship and the shot flies further right — well
	# inside the legacy rect (right edge x = 1444), crossing it in a couple of physics frames at
	# the sniper shot's 1400 px/s.
	sniper.global_position = Vector2(1400.0, 300.0)
	sniper.rotation = PI / 2.0

	sniper._phase_fire()

	var bullet: EnemyBullet = null
	for child in container.get_children():
		if child is EnemyBullet:
			bullet = child as EnemyBullet
	assert_not_null(bullet, "_phase_fire() must have spawned the real enemy_sniper_bullet.tscn")
	assert_true(bullet.expired.is_connected(bullet.queue_free),
			"sniper_enemy.gd wires expired -> queue_free itself for its unpooled shot")

	var freed := false
	for _i in 30:  # 30 physics frames at 60fps = 0.5s, far short of the 18s max_time ceiling
		await get_tree().physics_frame
		if not is_instance_valid(bullet):
			freed = true
			break
	assert_true(freed,
			"the unpooled sniper shot must be freed on crossing the legacy rect, well under 18s — "
			+ "a build that only arms on reset() would keep it alive for the full max_time instead")


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
