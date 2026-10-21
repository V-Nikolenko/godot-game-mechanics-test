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
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
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
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
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
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
	add_child_autofree(sniper)
	var body := sniper.get_node("CollisionShape2D") as CollisionShape2D
	var contact := sniper.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_same(contact.shape, body.shape, "the contact hitbox shares the body's shape sub-resource")
	assert_eq(contact.scale, body.scale, "and its scale")


func test_the_art_nose_points_up_so_the_muzzle_is_at_the_nose() -> void:
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
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
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
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
	var handed_over := -1
	for _i in 900:
		_tick(sniper, DT)
		if brain.phase != SniperBrain.Phase.ENTER:
			handed_over = brain.phase
			break
	assert_true(brain.arrived, "it reaches its point")
	assert_almost_eq(sniper.global_position.distance_to(harness.player.global_position),
		SHIPPED.preferred_range, SHIPPED.range_jitter + SHIPPED.arrive_radius + 1.0, "on the Open Space ring band")
	assert_eq(handed_over, SniperBrain.Phase.SETTLE, "and ENTER hands over to SETTLE there")
	var away: Vector2 = (Vector2(200.0, 200.0) - harness.player.global_position).normalized()
	var at: Vector2 = (sniper.global_position - harness.player.global_position).normalized()
	assert_gt(at.dot(away), 0.0, "on its own side of the player (the nearest legal point)")


func test_enter_in_assault_stays_inside_the_corridor_shrunk_by_the_fire_margin() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 560.0)
	var sniper := _spawn(harness, Vector2(640.0, 80.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	assert_true(mover.constraint is AssaultCorridorConstraint, "sanity: the Assault sniper runs under the corridor")
	var legal := mover.constraint.inner_rect().grow(-SHIPPED.fire_margin)
	for _i in 480:  # stops at AIM: from there the cycle (rightly) breaks contact out of the grown rect
		_tick(sniper, DT)
		if brain.phase == SniperBrain.Phase.AIM:
			break
	assert_eq(brain.phase, SniperBrain.Phase.AIM, "sanity: it reaches AIM")
	assert_true(legal.grow(0.001).has_point(brain.target_point),
		"the chosen point is inside the corridor, a fire margin from its edge")
	# The arrival latch (12 px) plus what SETTLE needs to brake from the arrival speed.
	assert_true(legal.grow(SHIPPED.arrive_radius + 24.0).has_point(sniper.global_position),
		"and the sniper aims from inside it")


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


# ── t13: the relocation cycle (task plan docs/plans/cmuyk2qq0008loa2xqwco8raj/3-plan.md) ─────────────
#
# "dual" cases run in both harnesses. The Assault budget is lifted (`engage_seconds`) wherever a case runs
# several cycles, so DISENGAGE never cuts one short; the budget's own cases set it on purpose.

const _MODES := ["open_space", "assault"]


func _harness(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	return harness


## A seeded sniper with the budget lifted. Player at (640, 560), stationary, facing up.
func _cycle_sniper(harness, pos: Vector2 = Vector2(640.0, 80.0), seed_: int = 4242, decoy: bool = false) -> Sniper:
	harness.player.global_position = Vector2(640.0, 560.0)
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	(sniper.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
	(sniper.get_node("Brain") as SniperBrain).rng_seed = seed_
	sniper.config.engage_seconds = 1000.0
	sniper.config.decoy_telegraph = decoy
	sniper.global_position = pos
	harness.root.add_child(sniper)
	sniper.set_physics_process(false)
	return sniper


## Returns every in-flight round to its pool the way an expiry does (`expired`, then the deferred recycle run
## now), so the two-round pool never runs dry in a hand-ticked run where rounds never fly.
func _recycle_rounds(sniper: Sniper) -> void:
	var pool := sniper.get_node("RailPool") as BulletPool
	for r in pool._active.duplicate():
		r.expired.emit()
		pool._recycle(r)


## Ticks until `brain.phase == p` (true) or `limit` seconds pass (false). Rounds are recycled as they come.
func _run_to(sniper: Sniper, p: int, limit: float) -> bool:
	var brain := sniper.get_node("Brain") as SniperBrain
	var t := 0.0
	while t < limit:
		_tick(sniper, DT)
		t += DT
		_recycle_rounds(sniper)
		if brain.phase == p:
			return true
	return false


## Ticks until `brain.shots_fired` reaches `shots` (true) or `limit` seconds pass. Rounds are NOT recycled on the
## tick the last one is fired, so the caller can still look at it.
func _run_to_shot(sniper: Sniper, shots: int, limit: float) -> bool:
	var brain := sniper.get_node("Brain") as SniperBrain
	var t := 0.0
	while t < limit:
		_tick(sniper, DT)
		t += DT
		if brain.shots_fired >= shots:
			return true
		_recycle_rounds(sniper)
	return false


func _asteroid(harness, pos: Vector2, radius: float) -> StaticBody2D:
	var rock := StaticBody2D.new()
	rock.add_to_group(&"asteroids")
	rock.collision_layer = CollisionLayers.ENVIRONMENT
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	rock.add_child(shape)
	rock.global_position = pos
	harness.root.add_child(rock)
	return rock


func _legal(c: Dictionary) -> bool:
	return c["rect_ok"] and c["cone_ok"] and c["path_ok"] and c["los"] != false


func test_the_first_point_is_the_nearest_legal_candidate(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_true(brain.target_point.is_finite(), "%s: ENTER chose a point" % mode)
	var nearest: Dictionary = {}
	for c in brain.last_candidates:
		if c["rect_ok"] and c["cone_ok"] and c["path_ok"] and (nearest.is_empty() or c["travel"] < nearest["travel"]):
			nearest = c
	assert_false(nearest.is_empty(), "%s: sanity: some candidate passed the filters" % mode)
	if nearest.is_empty():
		return
	assert_eq(brain.target_point, nearest["point"], "%s: the first point is the legal one with the least travel" % mode)
	assert_eq(nearest["los"], true, "%s: and a ray confirmed it" % mode)
	assert_false(brain.last_choice_fallback, "%s: with no last bearing there is no fallback to report" % mode)
	assert_eq(brain.last_candidates.size(), SniperBrain.SEED_BEARINGS.size() + SHIPPED.random_candidates,
		"%s: seven seeds plus the random candidates" % mode)


func test_consecutive_firing_bearings_differ_by_45_degrees(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var player_pos: Vector2 = harness.player.global_position
	var bearings: Array[float] = []
	var range_ := SHIPPED.assault_preferred_range if mode == "assault" else SHIPPED.preferred_range
	var closest := INF
	for shot in range(1, 5):
		var t := 0.0
		while brain.shots_fired < shot and t < 30.0:
			_tick(sniper, DT)
			t += DT
			if brain.shots_fired < shot:
				_recycle_rounds(sniper)
			if brain.has_last_bearing:  # every relocation after the first shot
				closest = minf(closest, sniper.global_position.distance_to(player_pos))
		assert_eq(brain.shots_fired, shot, "%s: shot %d is fired" % [mode, shot])
		if brain.shots_fired < shot:
			return
		# Measured independently of the brain: a stationary player's frame is its facing (up).
		bearings.append(Vector2.UP.angle_to(sniper.global_position - player_pos))
		_recycle_rounds(sniper)
	var report: Array[String] = []
	for i in range(1, bearings.size()):
		var diff := rad_to_deg(absf(angle_difference(bearings[i - 1], bearings[i])))
		report.append("%.1f" % diff)
		assert_gte(diff, SHIPPED.min_bearing_change, "%s: shot %d is %.1f deg from shot %d" % [mode, i + 1, diff, i])
	gut.p("%s: bearing changes between consecutive shots: %s deg" % [mode, ", ".join(report)])
	assert_gte(closest, SHIPPED.pass_clearance_ratio * range_ - 1.0,
		"%s: no relocation passes closer than the clearance (closest %.0f px)" % [mode, closest])
	gut.p("%s: closest approach after the first shot: %.0f px" % [mode, closest])


## Boundary: a player in the bottom-right corner of the Assault corridor leaves a legal arc of about 80 degrees
## (up-left of it). From the middle of that arc no legal candidate is 45 degrees away, so the fallback is
## taken; from its edge one always is, so it is not.
func test_corner_takes_the_fallback_only_when_no_45_degree_candidate_exists() -> void:
	var harness = _harness("assault")
	var sniper := _cycle_sniper(harness, Vector2(900.0, 500.0))
	harness.player.global_position = Vector2(1300.0, 1020.0)
	var brain := sniper.get_node("Brain") as SniperBrain
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	_tick(sniper, DT)
	var legal_rect := mover.constraint.inner_rect().grow(-SHIPPED.fire_margin)
	var cases := {"middle": deg_to_rad(-45.0), "edge": deg_to_rad(0.0)}
	var took := {}
	for label in cases:
		brain.last_bearing = cases[label]
		brain.has_last_bearing = true
		var point := brain.choose_firing_point()
		assert_true(point.is_finite(), "%s: some point is legal" % label)
		assert_true(legal_rect.has_point(point), "%s: the point is inside the corridor, a fire margin in" % label)
		var any_45 := false
		for c in brain.last_candidates:
			if _legal(c) and c["delta"] >= deg_to_rad(SHIPPED.min_bearing_change):
				any_45 = true
		assert_eq(brain.last_choice_fallback, not any_45,
			"%s: the fallback is taken exactly when no legal candidate is 45 degrees away" % label)
		took[label] = brain.last_choice_fallback
	assert_true(took["middle"], "from the middle of the arc the fallback is needed")
	assert_false(took["edge"], "from its edge it is not")


## Ahead of a 300 px/s player, with enough random candidates that some always fall inside the cone: every one of
## those is rejected, and no chosen point lies in it. At 100 px/s the filter is off.
func test_the_forward_cone_is_empty_for_a_fast_player() -> void:
	var harness = _harness("open_space")
	var sniper := _cycle_sniper(harness, Vector2(1500.0, 560.0))  # ahead of a player flying right
	sniper.config.random_candidates = 40
	var brain := sniper.get_node("Brain") as SniperBrain
	var cone := deg_to_rad(SHIPPED.forward_cone)
	harness.player.velocity = Vector2(300.0, 0.0)
	_tick(sniper, DT)
	assert_eq(brain.player_frame(), Vector2.RIGHT, "sanity: the frame is the fast player's velocity")
	var in_cone := 0
	for _i in 8:
		var point := brain.choose_firing_point()
		assert_true(point.is_finite())
		assert_gte(absf(Vector2.RIGHT.angle_to(point - harness.player.global_position)), cone - 0.0001,
			"no point within the cone of a 300 px/s player's heading")
		for c in brain.last_candidates:
			if absf(c["bearing"]) < cone:
				in_cone += 1
				assert_false(c["cone_ok"], "a candidate inside the cone is rejected")
			else:
				assert_true(c["cone_ok"], "one outside it is not")
	assert_gt(in_cone, 0, "sanity: some candidates fell inside the cone")
	harness.player.velocity = Vector2(100.0, 0.0)
	brain._player_vel_seeded = false  # re-seed the smoothed velocity from the slow player
	_tick(sniper, DT)
	brain.choose_firing_point()
	for c in brain.last_candidates:
		assert_true(c["cone_ok"], "at 100 px/s the cone filter is off")


## Boundary: a player inside a big asteroid cannot be seen from anywhere. The choice spends exactly
## `max_los_rays` rays and finds nothing, and a sniper in BREAK_CONTACT stays there rather than relocating -
## and stops once it is past its range band instead of flying off for ever.
func test_an_enclosed_player_spends_at_most_six_rays_and_holds_break_contact() -> void:
	var harness = _harness("open_space")
	var sniper := _cycle_sniper(harness, Vector2(640.0, -300.0))  # 860 px out: inside the range band
	var brain := sniper.get_node("Brain") as SniperBrain
	# StaticBody2D's default layer is ENVIRONMENT, one of LineOfSight.BLOCK_MASK's layers: keep it there.
	_asteroid(harness, harness.player.global_position, 220.0)
	await wait_physics_frames(1)
	_tick(sniper, DT)
	var point := brain.choose_firing_point()
	assert_false(point.is_finite(), "nothing is legal")
	assert_eq(brain.last_los_rays, SHIPPED.max_los_rays, "and it stopped at the ray cap")
	brain.enter_phase(SniperBrain.Phase.BREAK_CONTACT)
	var player_pos: Vector2 = harness.player.global_position
	var farthest := 0.0
	var band_edge := SHIPPED.preferred_range + SHIPPED.range_jitter
	for _i in int((SHIPPED.break_cap * 3.0) / DT):
		_tick(sniper, DT)
		farthest = maxf(farthest, sniper.global_position.distance_to(player_pos))
	assert_eq(brain.phase, SniperBrain.Phase.BREAK_CONTACT, "it holds BREAK_CONTACT past break_cap")
	# One `break_min` of breaking (at most break_speed * break_min), then it stops requesting past the band's far
	# edge and brakes (320 px/s at 700 px/s^2: about 73 px). Without the hold it would break again on every retry.
	assert_lt(farthest, maxf(860.0 + SHIPPED.break_speed * SHIPPED.break_min, band_edge) + 80.0,
		"and does not fly off (farthest %.0f px)" % farthest)
	assert_lt(sniper.velocity.length(), 1.0, "it waits, still")


func test_the_sniper_is_still_from_settle_end_to_the_shot(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.AIM, 15.0), "%s: the sniper reaches AIM" % mode)
	var anchor := sniper.global_position
	var worst_speed := sniper.velocity.length()
	var worst_drift := 0.0
	var ticks := 0
	while brain.shots_fired == 0 and ticks < int(5.0 / DT):
		_tick(sniper, DT)
		ticks += 1
		worst_speed = maxf(worst_speed, sniper.velocity.length())
		worst_drift = maxf(worst_drift, sniper.global_position.distance_to(anchor))
	assert_eq(brain.shots_fired, 1, "%s: the shot is fired" % mode)
	assert_lt(worst_speed, SHIPPED.settle_epsilon, "%s: under 2 px/s from SETTLE's end to the shot" % mode)
	assert_lt(worst_drift, 1.0, "%s: and it drifts under 1 px" % mode)


func test_after_the_shot_the_sniper_opens_the_range(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to_shot(sniper, 1, 15.0), "%s: the shot is fired" % mode)
	assert_eq(brain.phase, SniperBrain.Phase.BREAK_CONTACT, "%s: FIRE hands over to BREAK_CONTACT" % mode)
	var player_pos: Vector2 = harness.player.global_position
	var d0 := sniper.global_position.distance_to(player_pos)
	var prev := d0
	var at_quarter := -1.0
	var ticks := int(round(1.0 / DT))
	for i in range(1, ticks + 1):
		_tick(sniper, DT)
		_recycle_rounds(sniper)
		var d := sniper.global_position.distance_to(player_pos)
		assert_gte(d, prev - 0.0001, "%s: the range never shrinks (tick %d)" % [mode, i])
		assert_lte(sniper.velocity.dot(player_pos - sniper.global_position), 0.0001,
			"%s: no velocity toward the player (tick %d)" % [mode, i])
		prev = d
		if i == int(round(0.25 / DT)):
			at_quarter = d
	assert_gt(at_quarter, d0, "%s: farther after 0.25 s" % mode)
	assert_gt(prev, d0, "%s: farther after 1.0 s" % mode)


func test_commit_is_shown_only_in_lock_and_the_barrel_unfolds(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var light := sniper.get_node("StateLight") as StateLight
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var barrel := sniper.get_node("Barrel") as Sprite2D
	var seen := {}
	var t := 0.0
	while brain.shots_fired < 2 and t < 30.0:
		_tick(sniper, DT)
		t += DT
		_recycle_rounds(sniper)
		var p := brain.phase
		seen[p] = true
		assert_eq(light.get_state() == StateLight.State.COMMIT, p == SniperBrain.Phase.LOCK,
			"%s: COMMIT exactly in LOCK (phase %d)" % [mode, p])
		if light.get_state() == StateLight.State.CHARGING:
			assert_eq(p, SniperBrain.Phase.AIM, "%s: CHARGING only in AIM" % mode)
		assert_eq(telegraph.line_visible and telegraph.line_locked, p == SniperBrain.Phase.LOCK,
			"%s: the bright line exactly in LOCK" % mode)
		if p == SniperBrain.Phase.LOCK:
			assert_almost_eq(barrel.scale.y, 1.0, 0.001, "%s: the barrel is unfolded in LOCK" % mode)
		if p == SniperBrain.Phase.RELOCATE:
			assert_lt(barrel.scale.y, 0.5, "%s: and folded while it relocates" % mode)
	assert_eq(brain.shots_fired, 2, "%s: two whole cycles ran" % mode)
	assert_true(seen.has(SniperBrain.Phase.RELOCATE), "%s: sanity: it relocated between them" % mode)


# ── The decoy (t14, plan §2.5) ───────────────────────────────────────────────────────────────────

## The angle (deg) between the telegraph line and the straight line from the muzzle to the player.
func _line_offset_from_player(sniper: Sniper) -> float:
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var pts := telegraph.line_points()
	var muzzle := sniper.get_node("Muzzle") as Marker2D
	var to_player: Vector2 = TargetInfo.player(get_tree()).position - muzzle.global_position
	return rad_to_deg(absf((pts[1] - pts[0]).angle_to(to_player)))


func test_the_decoy_flag_is_off_in_the_shipped_config() -> void:
	assert_false(SHIPPED.decoy_telegraph, "the shipped game never shows the decoy")


func test_flag_off_never_enters_decoy_over_three_cycles(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var t := 0.0
	while brain.shots_fired < 3 and t < 60.0:
		_tick(sniper, DT)
		t += DT
		_recycle_rounds(sniper)
		assert_ne(brain.phase, SniperBrain.Phase.DECOY, "%s: no DECOY with the flag off" % mode)
		assert_ne(telegraph.line_color, SniperTelegraph.DECOY_COLOR, "%s: no orange line either" % mode)
	assert_eq(brain.shots_fired, 3, "%s: sanity: three whole cycles ran" % mode)


func test_flag_on_decoy_precedes_aim_off_the_player_and_never_looks_like_a_lock(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness, Vector2(640.0, 80.0), 4242, true)
	var brain := sniper.get_node("Brain") as SniperBrain
	var light := sniper.get_node("StateLight") as StateLight
	var telegraph := sniper.get_node("Telegraph") as SniperTelegraph
	var pool := sniper.get_node("RailPool") as BulletPool
	var phases: Array[int] = []
	brain.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var decoy_ticks := 0
	var t := 0.0
	while brain.shots_fired < 3 and t < 60.0:
		var rounds_before := pool._active.size()
		_tick(sniper, DT)
		t += DT
		if brain.phase == SniperBrain.Phase.DECOY:
			decoy_ticks += 1
			assert_eq(light.get_state(), StateLight.State.CHARGING, "%s: DECOY shows CHARGING" % mode)
			assert_true(telegraph.line_visible and not telegraph.line_locked, "%s: a dim line" % mode)
			assert_eq(telegraph.line_color, SniperTelegraph.DECOY_COLOR, "%s: the orange decoy colour" % mode)
			assert_ne(telegraph.line_color, SniperTelegraph.LOCKED_COLOR, "%s: never the lock colour" % mode)
			assert_eq(telegraph.line_width, SniperTelegraph.DECOY_WIDTH, "%s: width 1" % mode)
			var offset := _line_offset_from_player(sniper)
			assert_between(offset, 25.0 - 0.5, 35.0 + 0.5, "%s: the line is 25-35 deg off the player" % mode)
			assert_eq(pool._active.size(), rounds_before, "%s: no round is acquired during DECOY" % mode)
		_recycle_rounds(sniper)
	assert_eq(brain.shots_fired, 3, "%s: sanity: three whole cycles ran" % mode)
	var decoys := 0
	for i in phases.size():
		if phases[i] == SniperBrain.Phase.DECOY:
			decoys += 1
			assert_eq(phases[i - 1], SniperBrain.Phase.SETTLE, "%s: DECOY follows SETTLE" % mode)
		if phases[i] == SniperBrain.Phase.AIM:
			assert_eq(phases[i - 1], SniperBrain.Phase.DECOY, "%s: every AIM is preceded by a DECOY" % mode)
	assert_eq(decoys, 3, "%s: one decoy per cycle" % mode)
	assert_almost_eq(decoy_ticks * DT, 3.0 * sniper.config.decoy_seconds, 0.1, "%s: each lasts decoy_seconds" % mode)


func test_the_decoy_picks_both_sides(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness, Vector2(640.0, 80.0), 4242, true)
	var brain := sniper.get_node("Brain") as SniperBrain
	var sides := {}
	var t := 0.0
	while sides.size() < 2 and t < 120.0:
		_tick(sniper, DT)
		t += DT
		_recycle_rounds(sniper)
		if brain.phase == SniperBrain.Phase.DECOY:
			sides[signf(brain.decoy_angle)] = true
	assert_eq(sides.size(), 2, "%s: both a left and a right decoy were drawn" % mode)


func test_a_budget_expiry_in_decoy_disengages_without_a_shot() -> void:
	var harness = _harness("assault")
	var sniper := _cycle_sniper(harness, Vector2(640.0, 80.0), 4242, true)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.DECOY, 20.0), "sanity: reached DECOY")
	brain.budget.seconds = 0.0
	_tick(sniper, DT)
	assert_eq(brain.phase, SniperBrain.Phase.DISENGAGE, "a fake aim is not finished: it leaves at once")
	assert_eq(brain.shots_fired, 0, "and nothing was fired")


func test_the_lock_point_is_the_full_intercept(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	harness.player.global_position = Vector2(360.0, 560.0)
	harness.player.velocity = Vector2(120.0, 0.0)
	var lock_error := -1.0
	var t := 0.0
	while brain.shots_fired == 0 and t < 15.0:
		harness.player.global_position += harness.player.velocity * DT
		_tick(sniper, DT)
		t += DT
		if brain.phase == SniperBrain.Phase.LOCK and lock_error < 0.0:
			var want: Vector2 = TargetInfo.player(get_tree()).intercept(brain.lock_origin, SHIPPED.rail_speed)["point"]
			lock_error = brain.lock_point.distance_to(want)
	assert_gte(lock_error, 0.0, "%s: LOCK was reached" % mode)
	assert_lte(lock_error, 2.0, "%s: the frozen point is the full intercept, not the player's position" % mode)
	assert_gt(brain.lock_point.distance_to(harness.player.global_position), 10.0,
		"%s: sanity: the intercept leads a moving player" % mode)
	var round_ := brain.last_round
	assert_not_null(round_, "%s: a round was fired" % mode)
	if round_ == null:
		return
	var heading := Vector2.DOWN.rotated(round_.rotation)
	assert_gt(heading.dot((brain.lock_point - round_.global_position).normalized()), 0.9999,
		"%s: along the locked line" % mode)
	assert_eq(round_.speed, SHIPPED.rail_speed, "%s: at rail_speed" % mode)
	assert_eq((round_.get_node("HitBox") as HitBox).damage, SHIPPED.rail_damage, "%s: for rail_damage" % mode)


## Boundary: a rock dropped on the line during AIM refuses the shot at the end of LOCK; with it gone, the next
## cycle fires.
func test_a_rock_on_the_line_refuses_the_shot(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var light := sniper.get_node("StateLight") as StateLight
	var pool := sniper.get_node("RailPool") as BulletPool
	assert_true(_run_to(sniper, SniperBrain.Phase.AIM, 15.0), "%s: AIM reached" % mode)
	var muzzle := (sniper.get_node("Muzzle") as Marker2D).global_position
	var rock := _asteroid(harness, muzzle.lerp(harness.player.global_position, 0.5), 30.0)
	await wait_physics_frames(1)
	var left_lock_to := -1
	var t := 0.0
	while t < 5.0:
		var was_lock := brain.phase == SniperBrain.Phase.LOCK
		_tick(sniper, DT)
		t += DT
		if was_lock and brain.phase != SniperBrain.Phase.LOCK:
			left_lock_to = brain.phase
			break
	assert_eq(brain.shots_fired, 0, "%s: no round" % mode)
	assert_eq(pool._active.size(), 0, "%s: none was acquired" % mode)
	assert_eq(brain.refusals, 1, "%s: one refusal" % mode)
	assert_eq(left_lock_to, SniperBrain.Phase.BREAK_CONTACT, "%s: LOCK gives way to BREAK_CONTACT" % mode)
	assert_ne(light.get_state(), StateLight.State.COMMIT, "%s: the light drops" % mode)
	rock.queue_free()
	await wait_physics_frames(2)
	assert_true(_run_to_shot(sniper, 1, 20.0), "%s: with the rock gone the next cycle fires" % mode)


func test_a_fighter_body_on_the_line_does_not_block(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.AIM, 15.0), "%s: AIM reached" % mode)
	var muzzle := (sniper.get_node("Muzzle") as Marker2D).global_position
	var body := CharacterBody2D.new()
	body.collision_layer = CollisionLayers.ENVIRONMENT
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0
	shape.shape = circle
	body.add_child(shape)
	body.global_position = muzzle.lerp(harness.player.global_position, 0.5)
	harness.root.add_child(body)
	body.set_physics_process(false)
	await wait_physics_frames(1)
	assert_true(_run_to_shot(sniper, 1, 5.0), "%s: the round is fired through a non-blocking body" % mode)
	assert_eq(brain.refusals, 0, "%s: no refusal" % mode)


## The trail follows its round until `expired`, then stops on the spot the round expired at even though the
## recycled round is still a valid object, and fades out on its own clock.
func test_the_trail_stops_on_the_rounds_expired_and_fades(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var pool := sniper.get_node("RailPool") as BulletPool
	assert_true(_run_to_shot(sniper, 1, 15.0), "%s: a round is fired" % mode)
	var trail := brain.last_trail
	var round_ := brain.last_round
	assert_not_null(trail, "%s: with a trail" % mode)
	if trail == null:
		return
	trail.set_physics_process(false)  # hand-stepped
	assert_same(trail.get_parent(), round_.get_parent(), "%s: in the round's container" % mode)
	assert_true(trail.following)
	round_.global_position += Vector2(0.0, 300.0)
	trail.step(DT)
	assert_eq(trail.global_points()[1], round_.global_position, "%s: the far end follows the round" % mode)
	var expired_at := round_.global_position
	round_.expired.emit()
	pool._recycle(round_)
	assert_true(is_instance_valid(round_) and round_.get_parent() == pool, "%s: sanity: the round is parked" % mode)
	assert_false(trail.following, "%s: expired stops it following" % mode)
	round_.global_position = Vector2(-5000.0, -5000.0)
	var ticks := 0
	var limit := int(ceil(SHIPPED.trail_fade / DT)) + 2
	while not trail.is_queued_for_deletion() and ticks < limit + 5:
		trail.step(DT)
		ticks += 1
		assert_eq(trail.global_points()[1], expired_at, "%s: it never follows the parked round" % mode)
	assert_true(trail.is_queued_for_deletion(), "%s: the trail frees itself" % mode)
	assert_lte(ticks, limit, "%s: within trail_fade + 2 ticks" % mode)


func test_the_trail_fades_when_the_owner_dies() -> void:
	var harness = _harness("open_space")
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to_shot(sniper, 1, 15.0), "a round is fired")
	var trail := brain.last_trail
	if trail == null:
		fail_test("no trail")
		return
	trail.set_physics_process(false)
	(sniper.get_node("RailPool") as BulletPool).cancel_active()  # what the owner's death does, no `expired`
	var ticks := 0
	var limit := int(ceil(SHIPPED.trail_fade / DT)) + 2
	while not trail.is_queued_for_deletion() and ticks < limit + 5:
		trail.step(DT)
		ticks += 1
	assert_true(trail.is_queued_for_deletion(), "the trail frees itself after the round is freed")
	assert_lte(ticks, limit, "within trail_fade + 2 ticks")


## Boundary: expiry 0.2 s into AIM waits for the shot (at most aim + lock late); expiry in RELOCATE leaves at once.
func test_budget_expiry_in_aim_defers_disengage_to_the_shot() -> void:
	var harness = _harness("assault")
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.AIM, 15.0), "AIM reached")
	brain.budget.seconds = (brain.budget.seconds - brain.budget.remaining()) + 0.2
	var expired_at := -1.0
	var disengaged_at := -1.0
	var t := 0.0
	while t < 5.0:
		_tick(sniper, DT)
		t += DT
		if expired_at < 0.0 and brain.budget.remaining() <= 0.0:
			expired_at = t
		if brain.phase == SniperBrain.Phase.DISENGAGE:
			disengaged_at = t
			break
		assert_true(brain.phase == SniperBrain.Phase.AIM or brain.phase == SniperBrain.Phase.LOCK,
			"until the shot it stays in AIM / LOCK")
	assert_gt(expired_at, 0.0, "sanity: the budget expired")
	assert_eq(brain.shots_fired, 1, "the shot was fired")
	assert_gt(disengaged_at, 0.0, "then it disengages")
	assert_lte(disengaged_at - expired_at, SHIPPED.aim_seconds + SHIPPED.lock_seconds,
		"no later than aim + lock after expiry")


func test_budget_expiry_in_relocate_disengages_on_that_tick() -> void:
	var harness = _harness("assault")
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.RELOCATE, 25.0), "RELOCATE reached")
	brain.budget.seconds = brain.budget.seconds - brain.budget.remaining()  # expires on the next update
	_tick(sniper, DT)
	assert_eq(brain.phase, SniperBrain.Phase.DISENGAGE, "expiry in RELOCATE disengages on that tick")


# ── Attack in budget (epic plan §2.9.4; review N3, N9: classes from the live rows, harness local) ────
#
# `EngagementBudget` counts from spawn, so a level-1 sniper must reach AIM (after which the shot is always
# fired: expiry there is deferred) before its budget runs out. Every sniper offset in the live
# `Level1Director._build_sections()` is spawned through a real `WaveManager` under a real `ArenaCamera`, rails and
# delays stripped (t21/t22 take level 1 off rails; this row is the sniper's half of that gate). The snipers are
# hand-ticked: each one's physics tick is switched off from its `ready` signal.

const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const _BUDGET_SEED := 3301

var _budget_snipers: Array[Sniper] = []
var _budget_tweak: Callable = Callable()


## Every distinct design-unit offset a level-1 sniper spawns at (formations expanded).
func _level1_sniper_offsets() -> Array[Vector2]:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	var out: Array[Vector2] = []
	for s in d._build_sections():
		for w in (s as LevelSection).waves:
			for e in (w as WaveResource).entries:
				var entry: SpawnEntryResource = e
				if entry.ship_scene == null or entry.ship_scene.resource_path != WaveBuilder.SNIPER:
					continue
				var offsets: Array[Vector2] = [entry.base_offset]
				if entry.formation != null:
					offsets = []
					for slot in entry.formation.compute_slots():
						offsets.append(entry.base_offset + slot.offset)
				for o in offsets:
					if not out.has(o):
						out.append(o)
	return out


static func _spawn_class(offset: Vector2) -> String:
	if absf(offset.x) >= 400.0:
		return "side"
	return "top" if offset.y < 0.0 else "bottom"


func _on_budget_child(node: Node) -> void:
	if not node is Sniper:
		return
	var sniper := node as Sniper
	(sniper.get_node("Brain") as SniperBrain).rng_seed = _BUDGET_SEED + _budget_snipers.size()
	if _budget_tweak.is_valid():
		_budget_tweak.call(sniper)
	sniper.ready.connect(func() -> void: sniper.set_physics_process(false), CONNECT_ONE_SHOT)
	_budget_snipers.append(sniper)


## Spawns one sniper per offset at t = 0 through a real WaveManager, the player stub at `stub` from the camera
## centre, and hand-ticks them for at most `limit` s (stopping early once all have aimed, unless
## `until_gone`). Returns one `{offset, aim_at, remaining, shots}` per sniper (`aim_at` -1 when it never aimed).
func _budget_run(offsets: Array[Vector2], stub: Vector2, limit: float, until_gone: bool) -> Array[Dictionary]:
	_budget_snipers = []
	var harness = HARNESS.assault()
	add_child(harness.root)  # freed at the end of the run: a later run must not see this player
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	harness.player.global_position = cam.global_position + stub
	var container := Node2D.new()
	container.name = "EnemyContainer"
	harness.root.add_child(container)
	container.child_entered_tree.connect(_on_budget_child)
	var wm := WaveManager.new()
	wm.enemy_container = container
	harness.root.add_child(wm)
	var wave := WaveResource.new()
	wave.trigger_time = 0.0
	var entries: Array[SpawnEntryResource] = []
	for o in offsets:
		var entry := SpawnEntryResource.new()
		entry.ship_scene = load(WaveBuilder.SNIPER)
		entry.base_offset = o
		entries.append(entry)
	wave.entries = entries
	var waves: Array[WaveResource] = [wave]
	wm.load_section(waves)
	var t := 0.0
	while _budget_snipers.size() < offsets.size() and t < 1.0:
		await get_tree().process_frame
		t += 1.0 / 60.0
	wm.set_process(false)
	assert_eq(_budget_snipers.size(), offsets.size(), "sanity: every sniper spawned")
	var results: Array[Dictionary] = []
	for i in _budget_snipers.size():
		results.append({"offset": offsets[i], "aim_at": -1.0, "remaining": -1.0, "shots": 0, "disengaged": false})
	t = 0.0
	while t < limit:
		t += DT
		var all_aimed := true
		var all_gone := true
		for i in _budget_snipers.size():
			var sniper := _budget_snipers[i]
			if not is_instance_valid(sniper) or sniper.is_queued_for_deletion():
				continue
			all_gone = false
			_tick(sniper, DT)
			var brain := sniper.get_node("Brain") as SniperBrain
			if brain.phase == SniperBrain.Phase.AIM and results[i]["aim_at"] < 0.0:
				results[i]["aim_at"] = t
				results[i]["remaining"] = brain.budget.remaining()
			results[i]["shots"] = brain.shots_fired
			if brain.phase == SniperBrain.Phase.DISENGAGE:
				results[i]["disengaged"] = true
			if results[i]["aim_at"] < 0.0:
				all_aimed = false
			_recycle_rounds(sniper)
		if until_gone and all_gone:
			break
		if not until_gone and all_aimed:
			break
	# Out of the tree before the next run, so its player is the only one `TargetInfo.player()` can find.
	harness.root.queue_free()
	await get_tree().process_frame
	return results


func test_every_level1_sniper_spawn_class_aims_inside_its_budget() -> void:
	var offsets := _level1_sniper_offsets()
	var classes := {}
	for o in offsets:
		classes[_spawn_class(o)] = true
	assert_true(classes.has("top") and classes.has("bottom") and classes.has("side"),
		"sanity: level 1 spawns snipers from the top, the bottom and the sides (%s)" % [offsets])
	assert_true(offsets.has(Vector2(-120.0, -500.0)) and offsets.has(Vector2(120.0, -500.0)),
		"the far (+-120, -500) spawns are included (review N3)")
	# The camera-centre run, until every sniper has left: time to AIM and shots per life.
	var centre := await _budget_run(offsets, Vector2.ZERO, 30.0, true)
	for r in centre:
		assert_gt(r["aim_at"], 0.0, "%s (%s), stub at centre: AIM reached" % [r["offset"], _spawn_class(r["offset"])])
		assert_gt(r["remaining"], 0.0, "%s: before its budget expired" % [r["offset"]])
		gut.p("sniper %s %-6s stub centre: AIM at %.2f s (%.2f s of budget left), %d shot(s) per life"
			% [r["offset"], _spawn_class(r["offset"]), r["aim_at"], r["remaining"], r["shots"]])
	# One run per offset, the stub 200 px past the camera centre, away from that spawn.
	for o in offsets:
		var away: Vector2 = -o.normalized() * 200.0
		var one: Array[Vector2] = [o]
		var results := await _budget_run(one, away, SHIPPED.engage_seconds + 1.0, false)
		var r: Dictionary = results[0]
		assert_gt(r["aim_at"], 0.0, "%s (%s), stub %s: AIM reached" % [o, _spawn_class(o), away])
		assert_gt(r["remaining"], 0.0, "%s (%s): before its budget expired" % [o, _spawn_class(o)])
		gut.p("sniper %s %-6s stub %s: AIM at %.2f s (%.2f s of budget left)"
			% [o, _spawn_class(o), away.round(), r["aim_at"], r["remaining"]])


## Boundary: the same row with a 20 px/s sniper on a top spawn never aims before its budget runs out.
func test_the_attack_in_budget_row_can_fail() -> void:
	_budget_tweak = func(s: Sniper) -> void:
		s.config.relocate_speed = 20.0
		s.config.max_speed = 20.0
	var offsets: Array[Vector2] = [Vector2(-260.0, -400.0)]
	var results := await _budget_run(offsets, Vector2(0.0, 200.0), SHIPPED.engage_seconds + 1.0, false)
	_budget_tweak = Callable()
	assert_lt(results[0]["aim_at"], 0.0, "a 20 px/s sniper does not reach AIM before its budget expires")
	assert_true(results[0]["disengaged"], "it disengaged instead")


# ── t13 review round 1: the break's side, the corridor, the two refusal paths ─────────────────────────

## A sniper that has just fired at `pos`, player stationary at `player_pos` (or moving at `player_vel`): BREAK_CONTACT
## entered with the player already sensed, the way FIRE hands over.
func _breaking_sniper(harness, pos: Vector2, player_pos: Vector2, player_vel: Vector2 = Vector2.ZERO) -> Sniper:
	var sniper := _cycle_sniper(harness, pos)
	harness.player.global_position = player_pos
	harness.player.velocity = player_vel
	var brain := sniper.get_node("Brain") as SniperBrain
	brain._sense(DT)
	brain.enter_phase(SniperBrain.Phase.BREAK_CONTACT)
	return sniper


## The break leaves on the side of the player's line it is already on, never across the player's nose: against a
## player flying right at 200 px/s, the sniper's signed distance from the line through the player along its
## velocity keeps its sign and never shrinks, from above the line and from below it.
func test_break_contact_never_crosses_the_players_line(mode: String = use_parameters(_MODES)) -> void:
	for above in [true, false]:
		var harness = _harness(mode)
		# 520 px from the corridor edge it breaks toward in Assault: room to open before the edge rule stops it.
		var player_pos := Vector2(300.0, 560.0 if above else 160.0)
		var pos := player_pos + Vector2(250.0, -420.0 if above else 420.0)
		var sniper := _breaking_sniper(harness, pos, player_pos, Vector2(200.0, 0.0))
		var brain := sniper.get_node("Brain") as SniperBrain
		var side := -1.0 if above else 1.0  # screen y grows downward
		var prev := absf(pos.y - player_pos.y)
		var ticks := 0
		while brain.phase == SniperBrain.Phase.BREAK_CONTACT and ticks < int(SHIPPED.break_cap / DT):
			harness.player.global_position += harness.player.velocity * DT
			_tick(sniper, DT)
			ticks += 1
			var signed: float = sniper.global_position.y - harness.player.global_position.y
			assert_eq(signf(signed), side, "%s %s: still on its own side of the line" % [mode, "above" if above else "below"])
			assert_gte(absf(signed), prev - 0.0001, "%s: and never closer to it" % mode)
			prev = absf(signed)
		assert_gt(ticks, int(SHIPPED.break_min / DT) - 2, "%s: sanity: a whole break ran" % mode)
		# The lateral share is what moves it off the line: with the side flipped the away term alone gains ~50 px.
		assert_gt(prev, 420.0 + 150.0, "%s: it opened the distance from the line (%.0f px)" % [mode, prev])
		harness.root.queue_free()
		await get_tree().process_frame


## Boundary: Assault BREAK_CONTACT near the corridor's edge. The corridor pushes anything outside its visible rect
## back in - possibly toward the player - so the break must stay inside it: (a) breaking outward at the top edge,
## (b) the outward axis zeroed leaves a remainder toward the player, which is turned round, (c) in a corner, where
## it stops. On every tick: inside `inner_rect()`, the range never shrinks, no velocity toward the player.
func test_assault_break_contact_stays_inside_the_corridor() -> void:
	var setups := {
		"edge": [Vector2(640.0, -120.0), Vector2(640.0, 560.0)],
		"turned": [Vector2(1250.0, 700.0), Vector2(640.0, 400.0)],
		"corner": [Vector2(1330.0, -330.0), Vector2(640.0, 560.0)],
	}
	for label in setups:
		var harness = _harness("assault")
		var pos: Vector2 = setups[label][0]
		var player_pos: Vector2 = setups[label][1]
		var sniper := _breaking_sniper(harness, pos, player_pos)
		var brain := sniper.get_node("Brain") as SniperBrain
		var rect := (sniper.get_node("EnemyMover") as EnemyMover).constraint.inner_rect()
		var prev := pos.distance_to(player_pos)
		var ticks := 0
		while brain.phase == SniperBrain.Phase.BREAK_CONTACT and ticks < int(SHIPPED.break_cap / DT):
			_tick(sniper, DT)
			ticks += 1
			var x := sniper.global_position
			assert_true(rect.has_point(x), "%s: inside the visible rect (tick %d, %s)" % [label, ticks, x])
			var d := x.distance_to(player_pos)
			assert_gte(d, prev - 0.0001, "%s: the range never shrinks (tick %d)" % [label, ticks])
			assert_lte(sniper.velocity.dot(player_pos - x), 0.0001, "%s: no velocity toward the player" % label)
			prev = d
		if label == "corner":
			assert_lt(sniper.global_position.distance_to(pos), 8.0, "corner: it stops where it is")
		else:
			assert_gt(prev, pos.distance_to(player_pos) + 20.0, "%s: it still opened the range" % label)
		harness.root.queue_free()
		await get_tree().process_frame


## A rock that appears while the sniper relocates is caught when it settles: no AIM, no CHARGING, a break instead.
func test_a_rock_at_settle_end_sends_it_back_to_break_contact(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	var light := sniper.get_node("StateLight") as StateLight
	assert_true(_run_to(sniper, SniperBrain.Phase.RELOCATE, 25.0), "%s: RELOCATE reached" % mode)
	# Dropped near the end of the relocation, so no `relocate_cap` re-pick can steer round it.
	var near := 0
	while brain.phase == SniperBrain.Phase.RELOCATE and sniper.global_position.distance_to(brain.target_point) > 100.0 \
			and near < 600:
		_tick(sniper, DT)
		near += 1
	assert_eq(brain.phase, SniperBrain.Phase.RELOCATE, "%s: still relocating, 100 px out" % mode)
	var player_pos: Vector2 = harness.player.global_position
	# Close to the player, on the new point's line: off the relocation path, which keeps its clearance.
	_asteroid(harness, player_pos.lerp(brain.target_point, 0.15), 30.0)
	await wait_physics_frames(1)
	var shots := brain.shots_fired
	var settled := false
	var t := 0.0
	while t < 10.0:
		var was := brain.phase
		_tick(sniper, DT)
		t += DT
		assert_ne(brain.phase, SniperBrain.Phase.AIM, "%s: never AIM" % mode)
		assert_ne(light.get_state(), StateLight.State.CHARGING, "%s: never CHARGING" % mode)
		if was == SniperBrain.Phase.SETTLE and brain.phase != SniperBrain.Phase.SETTLE:
			settled = true
			assert_eq(brain.phase, SniperBrain.Phase.BREAK_CONTACT, "%s: SETTLE gives way to BREAK_CONTACT" % mode)
			break
	assert_true(settled, "%s: it settled" % mode)
	assert_eq(brain.refusals, 1, "%s: one refusal" % mode)
	assert_eq(brain.shots_fired, shots, "%s: no shot" % mode)


## Boundary: the budget runs out in LOCK and the shot is then refused: the refusal ends the deferral (DISENGAGE),
## with no round.
func test_a_refusal_resolves_a_budget_expired_in_lock() -> void:
	var harness = _harness("assault")
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.LOCK, 15.0), "LOCK reached")
	brain.budget.seconds = brain.budget.seconds - brain.budget.remaining() + 0.1
	var muzzle := (sniper.get_node("Muzzle") as Marker2D).global_position
	_asteroid(harness, muzzle.lerp(harness.player.global_position, 0.5), 30.0)
	await wait_physics_frames(1)
	var t := 0.0
	while brain.phase == SniperBrain.Phase.LOCK and t < 2.0:
		_tick(sniper, DT)
		t += DT
	assert_true(brain.disengage_pending == false, "the pending exit was taken")
	assert_eq(brain.phase, SniperBrain.Phase.DISENGAGE, "the refusal hands over to DISENGAGE")
	assert_eq(brain.shots_fired, 0, "with no round")
	assert_eq(brain.refusals, 1)


## The relocation path keeps its clearance: from a sniper that has just broken contact at bearing 0, the best
## separation is the far side of the player (180 degrees), whose straight path runs through the player. Over many
## seeded choices, every chosen path stays `pass_clearance_ratio * range` clear, and some candidate was refused
## for it.
func test_no_relocation_path_passes_through_the_player() -> void:
	var harness = _harness("open_space")
	var sniper := _cycle_sniper(harness, Vector2(640.0, 560.0 - 1000.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	var player_pos: Vector2 = harness.player.global_position
	_tick(sniper, DT)
	var clearance := SHIPPED.pass_clearance_ratio * SHIPPED.preferred_range
	var refused := 0
	for _i in 20:
		brain.last_bearing = 0.0
		brain.has_last_bearing = true
		var point := brain.choose_firing_point()
		assert_true(point.is_finite())
		var closest := Geometry2D.get_closest_point_to_segment(player_pos, sniper.global_position, point)
		assert_gte(closest.distance_to(player_pos), clearance - 0.001,
			"the path to %s passes %.0f px from the player" % [point, closest.distance_to(player_pos)])
		for c in brain.last_candidates:
			if not c["path_ok"]:
				refused += 1
	assert_gt(refused, 0, "sanity: far-side candidates were refused for their path")


# ══ t19: hub idle (epic §2.10; task cmuyk2qqh0099oa2xbltzoust) ═══════════════════════════════════════════════════
#
# Cold-start helpers: unlike `_spawn()` (which sets `start_engaged = true`, so every case above keeps assuming
# combat-from-spawn as before this task), these leave the brain to decide for itself - Open Space starts IDLE,
# Assault starts in combat. The stub player is stationary unless a case moves it.

const FAR_AWAY := Vector2(100000.0, 100000.0)
const SP := SniperBrain.Phase


func _cold_sniper(harness, pos: Vector2, player_pos: Vector2, anchor: Vector2 = Vector2.INF) -> Sniper:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	var sniper := SNIPER_SCENE.instantiate() as Sniper
	var brain := sniper.get_node("Brain") as SniperBrain
	brain.rng_seed = 4242
	brain.patrol_anchor = anchor
	sniper.global_position = pos
	harness.root.add_child(sniper)
	sniper.set_physics_process(false)
	return sniper


func _sbrain(sniper: Sniper) -> SniperBrain:
	return sniper.get_node("Brain") as SniperBrain


func _s_calm(p: int) -> bool:
	return p == SP.IDLE or p == SP.NOTICING or p == SP.RETURNING


func test_the_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(SP.ENTER, 0)
	assert_eq(SP.DISENGAGE, 8)
	assert_eq(SP.IDLE, 9)
	assert_eq(SP.NOTICING, 10)
	assert_eq(SP.RETURNING, 11)


## §2.10: lose_radius >= preferred_range + range_jitter + 200, read from fields.
func test_the_idle_radii_clear_the_largest_distance_the_loop_opens() -> void:
	var c: SniperConfig = SHIPPED
	assert_gte(c.lose_radius, c.preferred_range + c.range_jitter + 200.0, "lose_radius %.0f" % c.lose_radius)
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")
	assert_eq(c.perceive_radius, 700.0)
	assert_eq(c.lose_radius, 1300.0)


func test_open_space_cold_start_begins_idle_and_assault_starts_in_combat() -> void:
	var h = _harness("open_space")
	var sniper := _cold_sniper(h, Vector2(321.0, -654.0), FAR_AWAY)
	_tick(sniper, DT)
	assert_eq(_sbrain(sniper).phase, SP.IDLE, "Open Space starts on patrol")
	assert_not_null(_sbrain(sniper).anchor_idle)
	assert_eq(_sbrain(sniper).patrol_anchor, Vector2(321.0, -654.0), "an unset anchor defaults to the spawn position")
	var a = _harness("assault")
	var sniper2 := _cold_sniper(a, Vector2(640.0, -100.0), Vector2(640.0, 560.0))
	_tick(sniper2, DT)
	assert_eq(_sbrain(sniper2).phase, SP.ENTER, "Assault always starts in combat")
	assert_null(_sbrain(sniper2).anchor_idle, "no AnchorIdle is built in Assault")


func test_idle_never_aims_or_fires_and_stays_on_its_ring() -> void:
	var h = _harness("open_space")
	var anchor := Vector2(500.0, -400.0)
	var sniper := _cold_sniper(h, anchor + Vector2(20.0, 0.0), anchor + Vector2(SHIPPED.perceive_radius + SHIPPED.idle_radius + 80.0, 0.0), anchor)
	var worst := 0.0
	for _i in int(20.0 / DT):
		_tick(sniper, DT)
		assert_eq(_sbrain(sniper).phase, SP.IDLE)
		worst = maxf(worst, sniper.global_position.distance_to(anchor))
	assert_lte(worst, SHIPPED.idle_radius + 30.0, "worst %.1f px from the anchor" % worst)
	assert_eq(_sbrain(sniper).shots_fired, 0)
	assert_eq(_rounds_in(h.root).size(), 0)


func test_perceiving_the_player_notices_for_a_beat_then_enters() -> void:
	var h = _harness("open_space")
	var sniper := _cold_sniper(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius - 100.0))
	var seen: Array[int] = []
	for _i in int(1.0 / DT):
		_tick(sniper, DT)
		if seen.is_empty() or seen[-1] != _sbrain(sniper).phase:
			seen.append(_sbrain(sniper).phase)
	assert_eq(seen[0], SP.NOTICING, "NOTICING for a beat first")
	assert_eq(seen[1], SP.ENTER, "then the loop starts (phases %s)" % [seen])


func test_beyond_lose_radius_it_goes_home_and_can_fight_again() -> void:
	var h = _harness("open_space")
	var anchor := Vector2.ZERO
	var sniper := _cold_sniper(h, anchor + Vector2(100.0, 0.0), Vector2(400.0, 0.0), anchor)
	for _i in int(2.0 / DT):
		_tick(sniper, DT)
		if not _s_calm(_sbrain(sniper).phase):
			break
	assert_false(_s_calm(_sbrain(sniper).phase), "it reached combat")
	sniper.global_position += Vector2(0.0, 700.0)  # well away from home, so there is a way back to walk
	h.player.global_position = FAR_AWAY
	var saw_returning := false
	var home := false
	for _i in int(60.0 / DT):
		_tick(sniper, DT)
		_recycle_rounds(sniper)
		saw_returning = saw_returning or _sbrain(sniper).phase == SP.RETURNING
		if _sbrain(sniper).phase == SP.IDLE:
			home = true
			break
	assert_true(saw_returning, "it passes through RETURNING on the way home")
	assert_true(home, "and reaches IDLE")
	h.player.global_position = sniper.global_position + Vector2(SHIPPED.perceive_radius - 50.0, 0.0)
	for _i in int(1.0 / DT):
		_tick(sniper, DT)
	assert_false(_s_calm(_sbrain(sniper).phase), "and fights again")


## RETURNING never interrupts an AIM or a LOCK: the player vanishes (beyond lose_radius) mid-aim, and the shot is
## still delivered before the sniper turns for home.
func test_returning_never_interrupts_an_aim_or_a_lock() -> void:
	var h = _harness("open_space")
	var sniper := _cold_sniper(h, Vector2(640.0, 80.0), Vector2(640.0, 560.0))
	assert_true(_run_to(sniper, SP.AIM, 12.0), "it settles and aims")
	h.player.global_position = FAR_AWAY
	var brain := _sbrain(sniper)
	var seen: Array[int] = []
	for _i in int(8.0 / DT):
		_tick(sniper, DT)
		if seen.is_empty() or seen[-1] != brain.phase:
			seen.append(brain.phase)
		if brain.shots_fired > 0 and _s_calm(brain.phase):
			break
	assert_eq(brain.shots_fired, 1, "the locked shot was fired (phases %s)" % [seen])
	assert_true(seen.has(SP.LOCK), "through the lock (phases %s)" % [seen])
	assert_eq(seen[-1], SP.RETURNING, "and then it goes home (phases %s)" % [seen])
	for p in [SP.AIM, SP.LOCK]:
		assert_ne(seen[seen.find(p) + 1] if seen.find(p) + 1 < seen.size() else -1, SP.RETURNING, "no cut-off %s" % p)


## A hub sniper's whole loop - BREAK_CONTACT -> RELOCATE -> SETTLE -> AIM -> LOCK -> FIRE -> BREAK_CONTACT - against
## a stationary player never reads as losing it: COMBAT on every tick, and the range never reaches lose_radius.
func test_a_hub_sniper_stays_in_combat_through_a_full_cycle() -> void:
	var h = _harness("open_space")
	var sniper := _cold_sniper(h, Vector2(640.0, 80.0), Vector2(640.0, 560.0))
	var brain := _sbrain(sniper)
	var visited := {}
	var in_combat := false
	var worst := 0.0
	for _i in int(60.0 / DT):
		_tick(sniper, DT)
		_recycle_rounds(sniper)
		if brain.phase == SP.ENTER:
			in_combat = true
		if in_combat:
			assert_false(_s_calm(brain.phase), "combat tick %d is phase %s" % [_i, brain.phase])
			worst = maxf(worst, sniper.global_position.distance_to(h.player.global_position))
		visited[brain.phase] = true
		if brain.shots_fired >= 3:
			break
	assert_gte(brain.shots_fired, 3, "three full cycles ran")
	for p in [SP.BREAK_CONTACT, SP.RELOCATE, SP.SETTLE, SP.AIM, SP.LOCK]:
		assert_true(visited.has(p), "phase %s was visited" % p)
	assert_lt(worst, SHIPPED.lose_radius, "the loop opened %.0f px against lose_radius %.0f" % [worst, SHIPPED.lose_radius])


# ── Cover (Phase 6 t13; plan cmug23om70001m52wqfwclf3l §2.11) ───────────────────────────────────────
# A sniper hides behind a wreck and peeks out to shoot, never fires through one, and with no hazard in play picks
# exactly as it always did. Dual-mode cases run in both harnesses; a real `Wreck` is a solid body on layer 1, so
# these rows await a physics frame after placing one (a body added this frame is not in the broadphase yet).

const FIXTURE_WRECK := preload("res://tests/helpers/fixture_wreck.gd")
const WRECK_MEDIUM: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn")


func _range_of(mode: String) -> float:
	return SHIPPED.assault_preferred_range if mode == "assault" else SHIPPED.preferred_range


## A real medium wreck (r 25), held still: its own drift and lifetime clock are off.
func _wreck(harness, pos: Vector2) -> Wreck:
	var wreck := WRECK_MEDIUM.instantiate() as Wreck
	wreck.set_physics_process(false)
	harness.root.add_child(wreck)
	wreck.global_position = pos
	return wreck


## A point `distance_from_range` short of the mode's firing range from the player (640, 560), `deg` off straight up.
func _spot(mode: String, deg: float, short_of_range: float = 75.0) -> Vector2:
	return Vector2(640.0, 560.0) + Vector2.UP.rotated(deg_to_rad(deg)) * (_range_of(mode) - short_of_range)


## A non-blocking hazard (a well stand-in) of `radius` at `pos`: the fixture's info with the blocker flag off.
func _well(harness, pos: Vector2, radius: float) -> Node2D:
	var well := FIXTURE_WRECK.new() as Node2D
	well.info.line_of_sight_blocker = false
	well.info.kind = &"gravity_well"
	well.info.radius = radius
	harness.root.add_child(well)
	well.global_position = pos
	return well


func _clear_between(sniper: Sniper, a: Vector2, b: Vector2) -> bool:
	var exclude: Array[RID] = [sniper.get_rid()]
	return LineOfSight.clear(sniper.get_world_2d().direct_space_state, a, b, exclude)


func test_a_wreck_near_gives_a_cover_point_on_its_far_side_with_a_clear_line(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	var info := wreck.hazard_info()
	assert_eq(brain.last_cover, info, "%s: the winner is the wreck's cover candidate" % mode)
	var point := brain.target_point
	assert_true(point.is_finite(), "%s: a point was chosen" % mode)
	assert_lte(point.distance_to(wreck.global_position), SHIPPED.cover_radius, "%s: within cover_radius of the wreck" % mode)
	assert_gt((point - wreck.global_position).dot(wreck.global_position - harness.player.global_position), 0.0,
		"%s: on the far side from the player" % mode)
	assert_true(_clear_between(sniper, point, harness.player.global_position), "%s: the peek has a clear line" % mode)
	assert_true(info.is_claimed_by(sniper), "%s: the wreck is claimed once the point is taken" % mode)


func test_with_no_wreck_the_pick_and_the_next_draw_match_the_control(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var control := _cycle_sniper(harness)
	var control_brain := control.get_node("Brain") as SniperBrain
	_tick(control, DT)
	var control_point := control_brain.target_point
	var control_next := control_brain.rng.randf()
	# A hazard live but nowhere near: the hazard path runs, finds nothing, and must change nothing.
	var far := FIXTURE_WRECK.new() as Node2D
	harness.root.add_child(far)
	far.global_position = Vector2(9000.0, 9000.0)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_eq(Hazards.count(), 1, "%s: sanity: a hazard is live" % mode)
	assert_eq(brain.target_point, control_point, "%s: the same point as with no hazard at all" % mode)
	assert_null(brain.last_cover, "%s: no cover candidate" % mode)
	assert_eq(brain.rng.randf(), control_next, "%s: the same next draw" % mode)


func test_a_wreck_near_changes_the_point_but_not_how_many_draws_were_made(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var control := _cycle_sniper(harness)
	var control_brain := control.get_node("Brain") as SniperBrain
	_tick(control, DT)
	var control_next := control_brain.rng.randf()
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_not_null(brain.last_cover, "%s: sanity: the wreck was used" % mode)
	assert_eq(brain.rng.randf(), control_next, "%s: cover candidates draw no rng" % mode)
	assert_true(is_instance_valid(wreck))


func test_a_candidate_inside_a_well_is_never_chosen(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var control := _cycle_sniper(harness)
	_tick(control, DT)
	var control_point := (control.get_node("Brain") as SniperBrain).target_point
	_well(harness, control_point, 100.0)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_true(brain.target_point.is_finite(), "%s: another point was found" % mode)
	assert_ne(brain.target_point, control_point, "%s: not the one inside the well" % mode)
	assert_gt(brain.target_point.distance_to(control_point), 100.0 + SHIPPED.hazard_margin, "%s: and clear of its margin" % mode)
	var rejected := 0
	for c in brain.last_candidates:
		if (c["point"] as Vector2).distance_to(control_point) <= 100.0 + SHIPPED.hazard_margin:
			assert_false(c["hazard_ok"], "%s: a candidate in the well's reach is marked" % mode)
			rejected += 1
	assert_gt(rejected, 0, "%s: sanity: some candidate was in the well" % mode)


func test_a_second_sniper_is_refused_the_claimed_wreck(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var first := _cycle_sniper(harness)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	_tick(first, DT)
	var info := wreck.hazard_info()
	assert_true(info.is_claimed_by(first), "%s: sanity: the first sniper holds it" % mode)
	var second := _cycle_sniper(harness, Vector2(700.0, 90.0), 777)
	var brain := second.get_node("Brain") as SniperBrain
	_tick(second, DT)
	assert_null(brain.last_cover, "%s: the claimed wreck offers the second sniper no cover" % mode)
	assert_true(brain.target_point.is_finite(), "%s: it still picked somewhere" % mode)
	assert_false(info.is_claimed_by(second), "%s: and holds nothing" % mode)
	assert_true(info.is_claimed_by(first), "%s: the first still holds it" % mode)
	first.free()
	assert_false(info.is_claimed(), "%s: a freed sniper frees its claim" % mode)


func test_the_claim_is_released_on_break_contact_and_on_disengage(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_true(wreck.hazard_info().is_claimed_by(sniper), "%s: sanity: claimed" % mode)
	brain.enter_phase(SniperBrain.Phase.BREAK_CONTACT)
	assert_false(wreck.hazard_info().is_claimed(), "%s: BREAK_CONTACT releases" % mode)
	brain.last_cover = wreck.hazard_info()
	brain.last_cover_point = Vector2(1.0, 2.0)
	brain._set_target_point(Vector2(1.0, 2.0))
	assert_true(wreck.hazard_info().is_claimed_by(sniper), "%s: claimed again" % mode)
	brain.enter_phase(SniperBrain.Phase.DISENGAGE)
	assert_false(wreck.hazard_info().is_claimed(), "%s: DISENGAGE releases" % mode)


func test_a_real_sniper_reaches_its_cover_point_and_holds_it_into_aim(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	var brain := sniper.get_node("Brain") as SniperBrain
	var mover := sniper.get_node("EnemyMover") as EnemyMover
	assert_gt(mover.hazard_avoidance, 0.0, "%s: sanity: the avoidance stage is on for the sniper" % mode)
	var settled_slow := false
	var t := 0.0
	var reached := false
	while t < 12.0:
		_tick(sniper, DT)
		t += DT
		_recycle_rounds(sniper)
		if brain.phase == SniperBrain.Phase.SETTLE and mover.own_velocity().length() < SHIPPED.settle_epsilon:
			settled_slow = true
		if brain.phase == SniperBrain.Phase.AIM:
			reached = true
			break
	assert_true(reached, "%s: the sniper reaches AIM" % mode)
	assert_true(settled_slow or reached, "%s: and was slow enough to settle" % mode)
	assert_not_null(brain.claimed_cover, "%s: still holding the wreck" % mode)
	assert_lte(sniper.global_position.distance_to(brain.target_point), SHIPPED.arrive_radius * 2.0, "%s: at its cover point" % mode)
	assert_lte(sniper.global_position.distance_to(wreck.global_position), SHIPPED.cover_radius + SHIPPED.arrive_radius * 2.0,
		"%s: beside the wreck" % mode)
	assert_true(brain.can_see_player(), "%s: and sees the player from there" % mode)


func test_no_shot_goes_through_a_wreck_that_drifts_across_the_locked_line(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	assert_true(_run_to(sniper, SniperBrain.Phase.LOCK, 15.0), "%s: LOCK reached" % mode)
	var muzzle := (sniper.get_node("Muzzle") as Marker2D).global_position
	var wreck := _wreck(harness, muzzle.lerp(harness.player.global_position, 0.5))
	await wait_physics_frames(2)
	var left_to := -1
	var t := 0.0
	while t < 2.0:
		var was_lock := brain.phase == SniperBrain.Phase.LOCK
		_tick(sniper, DT)
		t += DT
		if was_lock and brain.phase != SniperBrain.Phase.LOCK:
			left_to = brain.phase
			break
	assert_eq(brain.shots_fired, 0, "%s: no round" % mode)
	assert_eq(brain.refusals, 1, "%s: one refusal" % mode)
	assert_eq(left_to, SniperBrain.Phase.BREAK_CONTACT, "%s: LOCK gives way to BREAK_CONTACT" % mode)
	assert_true(is_instance_valid(wreck))


func test_cover_hysteresis_keeps_a_cover_point_against_a_slightly_better_pick(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	await wait_physics_frames(2)
	var brain := sniper.get_node("Brain") as SniperBrain
	_tick(sniper, DT)
	assert_not_null(brain.claimed_cover, "%s: sanity: a cover point is held" % mode)
	var current := brain._score_of(brain.target_point)
	var elsewhere := Vector2(5.0, 5.0)
	brain.last_choice_score = current + SHIPPED.cover_hysteresis * 0.5
	assert_true(brain._keeps_cover(elsewhere), "%s: a pick better by less than the margin is not taken" % mode)
	brain.last_choice_score = current + SHIPPED.cover_hysteresis * 2.0
	assert_false(brain._keeps_cover(elsewhere), "%s: a clearly better pick is" % mode)
	brain.last_choice_score = current
	var rock := _asteroid(harness, brain.target_point.lerp(harness.player.global_position, 0.5), 30.0)
	await wait_physics_frames(2)
	assert_false(brain._keeps_cover(elsewhere), "%s: a point whose line is blocked is not kept" % mode)
	rock.free()
	await wait_physics_frames(2)
	assert_true(brain._keeps_cover(elsewhere), "%s: control: with the line clear again it is kept" % mode)
	wreck.free()
	assert_false(brain._keeps_cover(elsewhere), "%s: a vanished wreck is not kept" % mode)


func test_hysteresis_never_changes_a_pick_with_no_wreck(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var picks: Array[Vector2] = []
	for margin in [0.15, 1000.0]:
		var sniper := _cycle_sniper(harness)
		sniper.config.cover_hysteresis = margin
		var brain := sniper.get_node("Brain") as SniperBrain
		_tick(sniper, DT)
		brain._phase_time = 100.0  # the travel cap: a re-pick
		_tick(sniper, DT)
		assert_null(brain.claimed_cover, "%s: no cover held" % mode)
		assert_false(brain._keeps_cover(Vector2(1.0, 1.0)), "%s: nothing to keep" % mode)
		picks.append(brain.target_point)
	assert_eq(picks[0], picks[1], "%s: the re-pick is the same whatever the margin" % mode)


func test_can_see_player_is_false_without_a_player(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	var brain := sniper.get_node("Brain") as SniperBrain
	await wait_physics_frames(2)
	assert_true(brain.can_see_player(), "%s: control: sees the player over open space" % mode)
	harness.player.remove_from_group(&"player")
	assert_false(brain.can_see_player(), "%s: no player, no sight" % mode)


# A live-physics row: the hand-ticked rows above overwrite the position after `move_and_slide`, so none of them feels the
# wreck's body. Here the sniper runs on the engine's own physics (8x clock) and has to get round the solid wreck it has
# claimed to the far-side point.
const _LIVE_SPEEDUP := 8
var _live_saved := [1.0, 60, 8]
var _live_scaled := false


func after_each() -> void:
	if _live_scaled:
		_live_scaled = false
		Engine.time_scale = _live_saved[0]
		Engine.physics_ticks_per_second = _live_saved[1]
		Engine.max_physics_steps_per_frame = _live_saved[2]


func test_on_real_physics_the_sniper_gets_round_its_wreck_to_the_cover_point(mode: String = use_parameters(_MODES)) -> void:
	var harness = _harness(mode)
	var sniper := _cycle_sniper(harness)
	sniper.set_physics_process(true)
	var wreck := _wreck(harness, _spot(mode, 50.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	await wait_physics_frames(2)
	_live_saved = [Engine.time_scale, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame]
	_live_scaled = true
	Engine.physics_ticks_per_second = _live_saved[1] * _LIVE_SPEEDUP
	Engine.max_physics_steps_per_frame = _live_saved[2] * _LIVE_SPEEDUP
	Engine.time_scale = _live_saved[0] * _LIVE_SPEEDUP
	var frames := 0
	while brain.phase != SniperBrain.Phase.AIM and frames < 60 * _LIVE_SPEEDUP * 14:
		await wait_physics_frames(8)
		frames += 8
	assert_eq(brain.phase, SniperBrain.Phase.AIM, "%s: it settled in cover and is aiming" % mode)
	assert_not_null(brain.claimed_cover, "%s: holding the wreck" % mode)
	assert_gt(sniper.global_position.distance_to(wreck.global_position), 25.0, "%s: outside the wreck's body" % mode)
	assert_eq(brain.refusals, 0, "%s: with no refusal on the way" % mode)
