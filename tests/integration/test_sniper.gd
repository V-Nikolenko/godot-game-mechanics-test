## The Sniper shell (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.5, §2.8, §4 row t12; task
## t12-sniper-shell).
##
## What t12 pins: the scene's structure (a rail pool on the root, the telegraph as the sniper's own node, a
## placeholder barrel and a muzzle marker), `SniperConfig` applied (HP 60, contact 20, score 50), that no
## fly-in timing constant is left anywhere in the project, the rail fallback (a legacy
## aim 2.0 s / lock 0.5 s cycle that fires a 1400 px/s round and never writes the ship's rotation), the
## ENTER seek to the nearest legal firing point, and the Assault budget's DISENGAGE exit. t13 adds the
## relocation loop and its tests.
##
## Everything is hand-stepped with a fixed delta (the harness world has no engine physics ticks for the
## sniper: `set_physics_process(false)`), never a `Timer`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/enemies/sniper/sniper.tscn")
const SHIPPED: SniperConfig = preload("res://assault/scenes/enemies/sniper/sniper_config.tres")  # read only

const DT := 1.0 / 60.0
## Directories whose code is not ours, and the project's own history, which may name a removed symbol.
const _SWEEP_SKIP := ["res://addons", "res://.godot", "res://docs"]


func _spawn(harness, pos: Vector2) -> Sniper:
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	sniper.global_position = pos
	harness.root.add_child(sniper)
	sniper.set_physics_process(false)  # hand-ticked
	return sniper


func _tick(sniper: Sniper, delta: float) -> void:
	var before := sniper.global_position
	sniper._physics_process(delta)
	sniper.global_position = before + sniper.velocity * delta


## Every EnemyBullet in `root` (the container the rail pool hands rounds to).
func _rounds_in(root: Node) -> Array[EnemyBullet]:
	var found: Array[EnemyBullet] = []
	for child in root.get_children():
		if child is EnemyBullet:
			found.append(child)
	return found


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_rail_pool_is_a_root_child_feeding_the_rail_round() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var pool := sniper.get_node_or_null("RailPool") as BulletPool
	assert_not_null(pool, "RailPool is a direct child of the root")
	if pool == null:
		return
	assert_eq(pool.bullet_scene, EnemyRounds.RAIL, "it feeds the rail round")
	assert_false(pool.persist_after_owner_death, "a rail round dies with its shooter (the trail owns the rest)")
	var round_ := EnemyRounds.RAIL.instantiate()
	var lifetime := round_.get_node("ProjectileLifetime") as ProjectileLifetime
	# One shot per `aim + lock` at the AI cadence; a round lives until it has flown `max_distance` at its
	# slowest speed (or `max_time`, if that is sooner).
	var life_s := minf(lifetime.max_time, lifetime.max_distance / minf(SHIPPED.rail_speed, SHIPPED.rail_fallback_speed))
	round_.free()
	assert_gte(pool.pool_size, EnemyRounds.pool_size_for(1, life_s, SHIPPED.aim_seconds + SHIPPED.lock_seconds),
		"the pool covers a shot's whole life at the AI cadence")
	assert_gte(pool.pool_size, 2, "and holds at least two rounds")


func test_the_scene_has_the_plan_s_children_and_no_timer() -> void:
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	add_child_autofree(sniper)
	assert_true(sniper.get_node("Telegraph") is SniperTelegraph, "the telegraph is the sniper's own Node2D")
	assert_true(sniper.get_node("Brain") is SniperBrain)
	assert_true(sniper.get_node("StateLight") is StateLight)
	assert_true(sniper.get_node("Muzzle") is Marker2D, "the muzzle is a marker, never a literal")
	assert_true(sniper.get_node("Sprite2D") is Sprite2D, "the hull")
	assert_true(sniper.get_node("Barrel") is Sprite2D, "the barrel (a placeholder until the sprite task)")
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.constraint_mode, EnemyMover.ConstraintMode.AUTO, "the mover resolves the mode's constraint")
	for child in sniper.get_children():
		assert_false(child is Timer, "no Timer child (%s)" % child.name)
	# Read the source: `get_script_method_list()` also reports the inherited BaseEnemy tick.
	var source := FileAccess.get_file_as_string((sniper.get_script() as GDScript).resource_path)
	assert_false(source.contains("func _physics_process"), "sniper.gd leaves the physics tick to BaseEnemy")
	assert_false(source.contains("func _process"), "and has no _process of its own")


func test_the_body_hurtbox_and_contact_hitbox_share_one_shape() -> void:
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	add_child_autofree(sniper)
	var body := sniper.get_node("CollisionShape2D") as CollisionShape2D
	var contact := sniper.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_same(contact.shape, body.shape, "the contact hitbox shares the body's shape sub-resource")
	assert_eq(contact.scale, body.scale, "and its scale")


func test_the_art_nose_points_up_so_the_muzzle_is_at_the_nose() -> void:
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	add_child_autofree(sniper)
	assert_almost_eq(sniper.sprite_forward_angle, -PI / 2.0, 0.0001)
	assert_lt((sniper.get_node("Muzzle") as Marker2D).position.y, 0.0, "the muzzle is up the sprite")


func test_the_rail_round_scene() -> void:
	var round_ := EnemyRounds.RAIL.instantiate() as EnemyBullet
	add_child_autofree(round_)
	assert_eq(round_.speed, SHIPPED.rail_speed, "the AI rail speed (2200) is the scene's own")
	assert_eq(round_.speed, 2200.0)
	assert_eq((round_.get_node("HitBox") as HitBox).damage, SHIPPED.rail_damage, "damage 28 from the config")
	var shape := (round_.get_node("HitBox/CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	assert_almost_eq(shape.radius, 1.5, 0.0001)
	assert_almost_eq(shape.height, 24.0, 0.0001)
	var lifetime := round_.get_node("ProjectileLifetime") as ProjectileLifetime
	assert_eq(lifetime.max_time, 4.0)
	assert_eq(lifetime.max_distance, 2400.0)
	assert_true(round_.get_node("Visual") is Line2D and round_.get_node("Glow") is Line2D, "core and glow")
	for child in round_.get_children():
		assert_false(child is WorldEnvironment, "the old scene's WorldEnvironment is not copied")
	assert_false(FileAccess.file_exists("res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn"),
			"enemy_sniper_bullet.tscn is deleted")


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

func test_the_shipped_config_keeps_the_legacy_stats_and_the_plan_s_shot_numbers() -> void:
	assert_eq(SHIPPED.max_health, 60)
	assert_eq(SHIPPED.collision_damage, 20)
	assert_eq(SHIPPED.score_value, 50)
	assert_eq(SHIPPED.rail_speed, 2200.0)
	assert_eq(SHIPPED.rail_damage, 28)
	assert_eq(SHIPPED.rail_fallback_speed, 1400.0, "the rail fallback is today's shot")
	assert_false(SHIPPED.decoy_telegraph, "the decoy flag ships off")
	assert_eq(SHIPPED.rail_aim_seconds, 2.0)
	assert_eq(SHIPPED.rail_lock_seconds, 0.5)
	assert_eq(SHIPPED.rail_shot_count, 5)


func test_the_config_reaches_the_mover_the_brain_the_telegraph_and_the_hitbox() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, SHIPPED.max_speed)
	assert_eq(mover.acceleration, SHIPPED.acceleration)
	assert_eq(mover.braking, SHIPPED.braking)
	assert_eq(mover.max_turn_rate, SHIPPED.max_turn_rate)
	assert_eq(sniper.health.max_health, 60)
	assert_eq(sniper.score_value, 50)
	assert_eq((sniper.get_node("ContactHitBox") as HitBox).damage, 20)
	assert_same((sniper.get_node("Brain") as SniperBrain).config, sniper.config)
	assert_same((sniper.get_node("Telegraph") as SniperTelegraph).config, sniper.config)
	assert_not_same(sniper.config, SHIPPED, "the sniper holds a private copy of the shipped config")


func test_a_changed_config_value_wins_over_the_scene() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	sniper.config.max_health = 77
	sniper.config.collision_damage = 31
	sniper.config.score_value = 123
	harness.root.add_child(sniper)
	assert_eq(sniper.health.max_health, 77)
	assert_eq(sniper.health.current_health, 77)
	assert_eq((sniper.get_node("ContactHitBox") as HitBox).damage, 31)
	assert_eq(sniper.score_value, 123)


# ── No fly-in coupling ───────────────────────────────────────────────────────────────────────────

func _gather(dir_path: String, out: Array[String]) -> void:
	for skip in _SWEEP_SKIP:
		if dir_path.begins_with(skip):
			return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_gather(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if file.get_extension() in ["gd", "tscn", "tres"]:
			out.append(dir_path.path_join(file))


## The needle is built from two halves so this file does not match itself.
func test_no_fly_in_time_constant_survives_anywhere_in_the_project() -> void:
	var needle := "FLY_IN" + "_TIME"
	var files: Array[String] = []
	_gather("res://", files)
	assert_gt(files.size(), 100, "sanity: the sweep found the project")
	var hits: Array[String] = []
	for path in files:
		if FileAccess.get_file_as_string(path).contains(needle):
			hits.append(path)
	assert_eq(hits, [], "the sniper no longer needs its path's fly-in step to match a constant")


# ── The rail fallback (§2.8) ─────────────────────────────────────────────────────────────────────

## Suspends `sniper` (a rail takes over) and hand-steps its telegraph until it has fired `shots` rounds, or
## `limit` seconds pass. Returns the seconds taken to the first round, or -1.0 if none came.
func _run_rail(harness, sniper: Sniper, shots: int, limit: float) -> float:
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	sniper.suspend_ai()
	telegraph.set_process(false)  # hand-stepped
	var first := -1.0
	var elapsed := 0.0
	while elapsed < limit and telegraph.rail_shots_fired < shots:
		telegraph._process(DT)
		elapsed += DT
		if first < 0.0 and telegraph.rail_shots_fired >= 1:
			first = elapsed
		# Return each round to its pool the way an expiry does, so the two-round pool never runs dry.
		for r in _rounds_in(harness.root):
			r.expired.emit()
		if not _rounds_in(harness.root).is_empty():
			await wait_frames(1)
	return first


func test_a_suspended_sniper_fires_a_1400_round_within_2_6_s_and_never_writes_rotation() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(300.0, 900.0)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var rotation_before := sniper.rotation
	sniper.suspend_ai()
	telegraph.set_process(false)
	var fired_at := -1.0
	var round_: EnemyBullet = null
	var elapsed := 0.0
	while elapsed < 3.0 and round_ == null:
		telegraph._process(DT)
		elapsed += DT
		var rounds := _rounds_in(harness.root)
		if not rounds.is_empty():
			round_ = rounds[0]
			fired_at = elapsed
	assert_not_null(round_, "a round is fired")
	if round_ == null:
		return
	assert_lte(fired_at, 2.6, "within 2.6 s of suspend_ai()")
	assert_gte(fired_at, 2.4, "after the legacy 2.0 s aim and 0.5 s lock, not before")
	assert_eq(round_.speed, SHIPPED.rail_fallback_speed, "at the fallback's 1400 px/s")
	assert_eq((round_.get_node("HitBox") as HitBox).damage, SHIPPED.rail_fallback_damage, "for today's damage")
	var muzzle_pos := (sniper.get_node("Muzzle") as Marker2D).global_position
	var to_player: Vector2 = (harness.player.global_position - muzzle_pos).normalized()
	var heading := Vector2.DOWN.rotated(round_.rotation)  # `set_direction()`: rotation = angle - PI / 2
	assert_gt(heading.dot(to_player), 0.99, "along the locked line toward the player")
	assert_eq(sniper.rotation, rotation_before, "the cycle never writes the ship's rotation")


func test_the_rail_cycle_telegraphs_dim_then_bright_and_wide() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(300.0, 900.0)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	sniper.suspend_ai()
	telegraph.set_process(false)
	for i in int(1.0 / DT):
		telegraph._process(DT)
	assert_true(telegraph.line_visible, "the line shows while aiming")
	assert_false(telegraph.line_locked)
	assert_eq(telegraph.line_width, SniperTelegraph.TRACKING_WIDTH, "dim and thin while tracking")
	var pts := telegraph.line_points()
	assert_gte(pts[0].distance_to(pts[1]), SniperTelegraph.MIN_LENGTH, "long enough to reach past the player")
	for i in int(1.2 / DT):  # 2.2 s in: inside the 0.5 s lock
		telegraph._process(DT)
	assert_true(telegraph.line_locked, "locked")
	assert_eq(telegraph.line_width, SniperTelegraph.LOCKED_WIDTH, "bright and wide once locked")
	assert_gt(telegraph.line_color.g, 0.9, "near-white")


func test_the_rail_cycle_fires_five_shots_then_stops() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(300.0, 900.0)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	await _run_rail(harness, sniper, SHIPPED.rail_shot_count + 1, 20.0)
	assert_eq(telegraph.rail_shots_fired, SHIPPED.rail_shot_count, "rail_shot_count shots, no more")
	assert_eq(telegraph.rail_phase, SniperTelegraph.RailPhase.OFF, "then the cycle ends")
	assert_false(telegraph.line_visible, "and the line is gone")


func test_an_unsuspended_sniper_runs_no_rail_cycle() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var sniper := _spawn(harness, Vector2(300.0, 100.0))
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	for i in 400:
		telegraph._process(DT)
	assert_eq(telegraph.rail_phase, SniperTelegraph.RailPhase.OFF)
	assert_eq(_rounds_in(harness.root).size(), 0, "the cycle is a rail fallback only")


func test_no_sniper_script_writes_rotation() -> void:
	for path in ["res://assault/scenes/enemies/sniper/sniper.gd",
			"res://assault/scenes/enemies/sniper/sniper_telegraph.gd",
			"res://assault/scenes/enemies/sniper/sniper_brain.gd"]:
		var re := RegEx.create_from_string("(?m)^[^#\\n]*\\brotation\\s*([+\\-*]?=)[^=]")
		var source := FileAccess.get_file_as_string(path)
		assert_null(re.search(source), "%s never assigns a rotation" % path)


# ── ENTER ────────────────────────────────────────────────────────────────────────────────────────

func test_enter_seeks_the_ring_point_on_its_own_side_and_then_holds_open_space() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(900.0, 360.0)
	var sniper := _spawn(harness, Vector2(200.0, 200.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	var start := sniper.global_position.distance_to(harness.player.global_position)
	assert_lt(start, SHIPPED.preferred_range, "sanity: it starts inside its range")
	for _i in 900:
		_tick(sniper, DT)
	assert_true(brain.arrived, "it reaches its point")
	assert_almost_eq(sniper.global_position.distance_to(harness.player.global_position),
		SHIPPED.preferred_range, SHIPPED.arrive_radius + 1.0, "on the Open Space ring")
	assert_lt(sniper.velocity.length(), 2.0, "and holds there")
	assert_eq(brain.phase, SniperBrain.Phase.ENTER, "ENTER is the only phase t12 plays")


func test_enter_in_assault_stays_inside_the_corridor_shrunk_by_the_fire_margin() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 560.0)
	var sniper := _spawn(harness, Vector2(640.0, 80.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	assert_true(mover.constraint is AssaultCorridorConstraint, "sanity: the Assault sniper runs under the corridor")
	var legal := mover.constraint.inner_rect().grow(-SHIPPED.fire_margin)
	for _i in 480:
		_tick(sniper, DT)
	assert_true(legal.grow(1.0).has_point(brain.nearest_firing_point(harness.player.global_position)),
		"the chosen point is inside the corridor, a fire margin from its edge")
	assert_true(legal.grow(SHIPPED.arrive_radius + 1.0).has_point(sniper.global_position),
		"and the sniper holds inside it")


# ── Assault: the budget and DISENGAGE ────────────────────────────────────────────────────────────

func test_assault_disengage_frees_the_sniper_only_outside_the_world_rect() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var sniper := _spawn(harness, Vector2(640.0, 60.0))
	sniper.config.engage_seconds = 0.2
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var freed_at := Vector2.INF
	for _i in 1500:
		_tick(sniper, DT)
		if sniper.is_queued_for_deletion():
			freed_at = sniper.global_position
			break
	assert_true(freed_at.is_finite(), "the budget disengages it")
	assert_false(rect.has_point(freed_at), "and it is freed only once outside the world rect")
	assert_eq((sniper.get_node("Brain") as SniperBrain).phase, SniperBrain.Phase.DISENGAGE)


func test_open_space_has_no_budget_so_the_sniper_stays() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var sniper := _spawn(harness, Vector2(640.0, 60.0))
	sniper.config.engage_seconds = 0.2
	for _i in 600:
		_tick(sniper, DT)
	assert_false(sniper.is_queued_for_deletion())
	assert_ne((sniper.get_node("Brain") as SniperBrain).phase, SniperBrain.Phase.DISENGAGE)
