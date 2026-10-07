## Integration tests for the enemy bullet family: Pulse, Scatter, Gatling Stream and Heavy Shell.
## Plan §2.2, task t2-rounds (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md, Revision 2).
##
## Each round is an inherited scene of enemy_bullet.tscn (rounds/*.tscn) — same script, same
## HitBox/HurtBox layers (256/128, inherited), a different Line2D visual, hitbox shape,
## ProjectileLifetime budget, default speed/damage and z_index. `EnemyRounds` holds the four
## scene paths plus `pool_size_for()`, the pool-sizing helper every future consumer of a round
## reuses instead of retuning one bullet.
extends GutTest


class _RoundSpec:
	var scene: PackedScene
	var speed: float
	var damage: int
	var max_time: float
	var max_distance: float
	var z_index: int


func _spec(scene: PackedScene, speed: float, damage: int, max_time: float, max_distance: float,
		z_index: int) -> _RoundSpec:
	var s := _RoundSpec.new()
	s.scene = scene
	s.speed = speed
	s.damage = damage
	s.max_time = max_time
	s.max_distance = max_distance
	s.z_index = z_index
	return s


## The table in 3-plan.md §2.2. Add a round here the day it ships.
func _every_round_spec() -> Array[_RoundSpec]:
	return [
		_spec(EnemyRounds.PULSE, 300.0, 8, 8.0, 1400.0, 0),
		_spec(EnemyRounds.SCATTER, 420.0, 6, 2.0, 450.0, 0),
		_spec(EnemyRounds.GATLING_STREAM, 240.0, 4, 8.0, 1400.0, 1),
		_spec(EnemyRounds.HEAVY_SHELL, 160.0, 20, 12.0, 1800.0, -1),
	]


# ---------------------------------------------------------------------------------------------
# Every round is an EnemyBullet with the table's shape.
# ---------------------------------------------------------------------------------------------

func test_every_round_is_an_enemy_bullet_with_the_tables_values() -> void:
	for spec: _RoundSpec in _every_round_spec():
		var path: String = spec.scene.resource_path
		var bullet: EnemyBullet = spec.scene.instantiate()
		add_child_autofree(bullet)

		assert_almost_eq(bullet.speed, spec.speed, 0.001, path)
		assert_eq(bullet.z_index, spec.z_index, path)

		var hit_box := bullet.get_node_or_null("HitBox") as HitBox
		assert_not_null(hit_box, "%s must carry a HitBox" % path)
		assert_eq(hit_box.collision_layer, CollisionLayers.ENEMY_HITBOX, path)
		assert_eq(hit_box.collision_mask, CollisionLayers.PLAYER_HURTBOX, path)
		assert_eq(hit_box.damage, spec.damage, path)

		var lifetime := bullet.get_node_or_null("ProjectileLifetime") as ProjectileLifetime
		assert_not_null(lifetime, "%s must carry a ProjectileLifetime" % path)
		assert_almost_eq(lifetime.max_time, spec.max_time, 0.001, path)
		assert_almost_eq(lifetime.max_distance, spec.max_distance, 0.001, path)


# ---------------------------------------------------------------------------------------------
# reset() restores THIS round's own speed/damage, not the legacy 250 / whatever a pattern left.
# ---------------------------------------------------------------------------------------------

func test_reset_restores_the_scenes_authored_speed_and_damage_after_a_pattern_changed_them() -> void:
	for spec: _RoundSpec in _every_round_spec():
		var path: String = spec.scene.resource_path
		var bullet: EnemyBullet = spec.scene.instantiate()
		add_child_autofree(bullet)
		var hit_box := bullet.get_node("HitBox") as HitBox

		# Simulate an AttackPatternResource.fire() overriding both for one shot.
		bullet.speed = 999.0
		hit_box.damage = 999

		bullet.reset()

		assert_almost_eq(bullet.speed, spec.speed, 0.001, path)
		assert_eq(hit_box.damage, spec.damage, path)


# ---------------------------------------------------------------------------------------------
# Boundary: the Scatter Round's short range is the design; the Pulse Round's is not.
# ---------------------------------------------------------------------------------------------

func test_scatter_round_expires_by_450px_of_travel() -> void:
	var bullet: EnemyBullet = EnemyRounds.SCATTER.instantiate()
	add_child_autofree(bullet)
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	lifetime.reset()

	bullet.global_position = Vector2(0.0, 450.0)
	watch_signals(bullet)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 1,
			"the Scatter Round's short range (<= 450px) is deliberate, not a bug")


func test_pulse_round_is_still_alive_at_1280px() -> void:
	var bullet: EnemyBullet = EnemyRounds.PULSE.instantiate()
	add_child_autofree(bullet)
	var lifetime := bullet.get_node("ProjectileLifetime") as ProjectileLifetime
	lifetime.reset()

	bullet.global_position = Vector2(0.0, 1280.0)
	watch_signals(bullet)
	lifetime._physics_process(0.0)
	assert_signal_emit_count(bullet, "expired", 0,
			"every round but Scatter must clear at least 1280px")


# ---------------------------------------------------------------------------------------------
# pool_size_for: max_burst * ceil(round_lifetime / min_burst_period).
# ---------------------------------------------------------------------------------------------

func test_pool_size_for_an_ai_burst() -> void:
	# Fighter Pulse pool, AI cadence (3-plan.md §2.2): 5 rounds alive ~4.67s each, no more than
	# one burst every 2.5s -> ceil(4.67 / 2.5) = 2 cycles in flight at once -> 10.
	assert_eq(EnemyRounds.pool_size_for(5, 1400.0 / 300.0, 2.5), 10)


func test_pool_size_for_a_rail_cadence_is_a_burst_of_one() -> void:
	# A self-timed rail pattern has no burst grouping: max_burst = 1, and min_burst_period is its
	# own fire interval. Fighter FORWARD rail (3-plan.md §2.2): 1400/420 ~= 3.33s alive, fired
	# every 0.3s -> ceil(3.33 / 0.3) = 12.
	assert_eq(EnemyRounds.pool_size_for(1, 1400.0 / 420.0, 0.3), 12)


# ---------------------------------------------------------------------------------------------
# The Heavy Shell has no consumer this phase (S5) — proven with a bare fixture shooter instead
# of an enemy: a BulletPool + AimedAttackPattern, the shape 3-plan.md §2.2 asks for.
# ---------------------------------------------------------------------------------------------

func test_heavy_shell_fired_by_a_fixture_shooter_hits_a_hurtbox_for_20() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var ship := Node2D.new()
	container.add_child(ship)
	ship.global_position = Vector2(400.0, 100.0)
	ship.rotation = 0.0  # Vector2.DOWN.rotated(0) == Vector2.DOWN

	var pool := BulletPool.new()
	pool.bullet_scene = EnemyRounds.HEAVY_SHELL
	pool.pool_size = 1
	ship.add_child(pool)

	var pattern := AimedAttackPattern.new()
	pattern.aim_at_player = false
	pattern.bullet_damage = 20
	pattern.bullet_speed = 160.0
	pattern.spawn_offset = Vector2.ZERO

	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = pool
	ship.add_child(controller)

	# A player-hurtbox stand-in: layer/mask reciprocal to the round's HitBox (256 hitting 128).
	var hurtbox := HurtBox.new()
	hurtbox.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurtbox.collision_mask = CollisionLayers.ENEMY_HITBOX
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	hurtbox.add_child(shape)
	container.add_child(hurtbox)
	hurtbox.global_position = ship.global_position + Vector2(0.0, 60.0)

	watch_signals(hurtbox)
	controller.fire_now()

	var hit := false
	for _i in 60:  # 1s at 60fps; 60px at 160px/s takes ~0.375s
		await get_tree().physics_frame
		if get_signal_emit_count(hurtbox, "received_damage") > 0:
			hit = true
			break
	assert_true(hit, "the Heavy Shell must reach and hit the hurtbox stand-in")
	assert_signal_emitted_with_parameters(hurtbox, "received_damage", [20], 0)
