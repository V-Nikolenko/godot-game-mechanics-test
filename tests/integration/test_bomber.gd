## The Bomber shell (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4, §2.8; task t9-bomber-shell).
##
## What t9 pins: the scene's structure (three persistent ordnance pools as root children, one
## `RectangleShape2D` body shared by the contact hitbox and the hurtbox so the wings are shootable),
## the rail fallback (a gravity bomb DOWN every `rail_bomb_interval`, from config), that a bomb outlives
## its bomber, and the Assault budget's DISENGAGE exit. t10 adds the bombing runs and their tests.
##
## Everything is hand-stepped with a fixed delta (the harness world has no engine physics ticks for the
## bomber: `set_physics_process(false)`), never a `Timer`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const BOMBER_SCENE: PackedScene = preload("res://assault/scenes/enemies/bomber/bomber.tscn")
const SHIPPED: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")  # read only

const DT := 1.0 / 60.0
const POOLS := {
	"GravityBombPool": EnemyOrdnance.Kind.GRAVITY_BOMB,
	"MinePool": EnemyOrdnance.Kind.MINE,
	"PursuitBombPool": EnemyOrdnance.Kind.PURSUIT_BOMB,
}


func _spawn(harness, pos: Vector2) -> Bomber:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	bomber.global_position = pos
	harness.root.add_child(bomber)
	bomber.set_physics_process(false)  # hand-ticked
	bomber.set_process(false)          # the rail clock is hand-stepped too
	return bomber


func _tick(bomber: Bomber, delta: float) -> void:
	var before := bomber.global_position
	bomber._physics_process(delta)
	bomber.global_position = before + bomber.velocity * delta


func _ordnance_in(root: Node) -> Array[EnemyOrdnance]:
	var found: Array[EnemyOrdnance] = []
	for child in root.get_children():
		if child is EnemyOrdnance:
			found.append(child)
	return found


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_three_pools_are_root_children_that_let_ordnance_outlive_the_bomber() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	for pool_name: String in POOLS:
		var pool := bomber.get_node_or_null(pool_name) as BulletPool
		assert_not_null(pool, "%s is a direct child of the root" % pool_name)
		if pool == null:
			continue
		assert_true(pool.persist_after_owner_death, "%s: persist_after_owner_death" % pool_name)
		assert_gte(pool.pool_size, EnemyOrdnanceScenes.pool_size_for(POOLS[pool_name], bomber.config),
			"%s: sized for the config's run cadence and mine life" % pool_name)
		assert_eq(pool.bullet_scene, EnemyOrdnanceScenes.scene_for(POOLS[pool_name]),
			"%s feeds the matching ordnance scene" % pool_name)


func test_the_body_is_one_rectangle_shared_by_the_hurtbox_and_the_contact_hitbox() -> void:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	add_child_autofree(bomber)
	var body := bomber.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := bomber.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := bomber.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is RectangleShape2D, "the body is a RectangleShape2D")
	assert_same(hurt.shape, body.shape, "the hurtbox shares the body's shape sub-resource")
	assert_same(contact.shape, body.shape, "the contact hitbox shares it too")
	assert_eq(hurt.scale, body.scale, "hurtbox scale matches the body")
	assert_eq(contact.scale, body.scale, "contact hitbox scale matches the body")
	var sprite := bomber.get_node("Sprite2D") as Sprite2D
	var wingspan: float = (body.shape as RectangleShape2D).size.x * absf(body.scale.x)
	assert_gte(wingspan, 0.85 * sprite.texture.get_width(),
		"the wings are shootable: the body is at least 0.85 x the sprite's width")


func test_the_legacy_timer_physics_loop_and_bomb_scene_are_gone() -> void:
	var bomber := BOMBER_SCENE.instantiate() as Bomber
	add_child_autofree(bomber)
	for child in bomber.get_children():
		assert_false(child is Timer, "no Timer child (%s)" % child.name)
	# Read the source: `get_script_method_list()` also reports the inherited BaseEnemy tick.
	var source := FileAccess.get_file_as_string((bomber.get_script() as GDScript).resource_path)
	assert_false(source.contains("func _physics_process"), "bomber.gd leaves the physics tick to BaseEnemy")
	assert_false(FileAccess.file_exists("res://assault/scenes/enemies/bomber/bomb.tscn"), "bomb.tscn is deleted")
	assert_false(FileAccess.file_exists("res://assault/scenes/enemies/bomber/bomb.gd"), "bomb.gd is deleted")


func test_the_shipped_config_keeps_the_legacy_stats_and_a_wall_that_can_hurt_a_fast_player() -> void:
	assert_eq(SHIPPED.max_health, 150)
	assert_eq(SHIPPED.collision_damage, 35)
	assert_eq(SHIPPED.score_value, 80)
	# Review B1(a): a player crossing a mine at the top of the mine band must still be inside the blast
	# when the warning ends, or the wall is harmless at normal speeds.
	assert_gte((SHIPPED.trigger_radius + SHIPPED.mine_blast_radius) / SHIPPED.mine_warning,
		SHIPPED.mine_speed_max, "(trigger + blast) / mine_warning >= mine_speed_max")


func test_the_config_reaches_the_mover_the_brain_and_the_hitbox() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	var mover := bomber.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, SHIPPED.max_speed)
	assert_eq(mover.acceleration, SHIPPED.acceleration)
	assert_eq(mover.max_turn_rate, SHIPPED.max_turn_rate)
	assert_eq((bomber.get_node("ContactHitBox") as HitBox).damage, SHIPPED.collision_damage)
	assert_same((bomber.get_node("Brain") as BomberBrain).config, bomber.config)
	assert_not_same(bomber.config, SHIPPED, "the bomber holds a private copy of the shipped config")


# ── The rail fallback ────────────────────────────────────────────────────────────────────────────

func test_a_rail_bomber_drops_a_gravity_bomb_straight_down_every_interval() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	bomber.suspend_ai()
	var drop_times: Array[float] = []
	var seen := 0
	var steps := int((SHIPPED.rail_bomb_interval * 3.0 + 0.3) / DT)
	for i in steps:
		bomber._process(DT)
		var now := _ordnance_in(harness.root).size()
		if now > seen:
			drop_times.append((i + 1) * DT)
			seen = now
	assert_eq(drop_times.size(), 3, "three bombs in three intervals and a bit")
	for n in drop_times.size():
		assert_almost_eq(drop_times[n], SHIPPED.rail_bomb_interval * (n + 1), DT * 2.0,
			"bomb %d drops on the interval" % n)
	var bomb := _ordnance_in(harness.root)[0]
	assert_eq(bomb.kind, EnemyOrdnance.Kind.GRAVITY_BOMB)
	assert_eq(bomb.heading(), Vector2.DOWN, "launched DOWN")
	var before := bomb.global_position
	bomb._physics_process(0.5)
	assert_almost_eq(bomb.global_position.distance_to(before), SHIPPED.rail_bomb_speed * 0.5, 0.01,
		"at rail_bomb_speed")
	assert_eq(bomb.blast_damage, SHIPPED.gravity_blast_damage, "its blast comes from the config")


func test_an_unsuspended_bomber_drops_nothing_from_the_rail_clock() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	for i in int(SHIPPED.rail_bomb_interval * 3.0 / DT):
		bomber._process(DT)
	assert_eq(_ordnance_in(harness.root).size(), 0, "the clock is a rail fallback only")


func test_a_bomb_in_flight_survives_its_bomber_dying() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var bomber := _spawn(harness, Vector2(300.0, 100.0))
	bomber.suspend_ai()
	for i in int((SHIPPED.rail_bomb_interval + 0.1) / DT):
		bomber._process(DT)
	var bombs := _ordnance_in(harness.root)
	assert_eq(bombs.size(), 1, "sanity: one bomb in flight")
	var bomb := bombs[0]
	bomber.health.decrease(bomber.health.current_health)
	await wait_frames(3)
	assert_true(is_instance_valid(bomber) == false or bomber.is_queued_for_deletion() or not bomber.is_inside_tree(),
		"sanity: the bomber is gone")
	assert_true(is_instance_valid(bomb), "the bomb is still alive")
	assert_true(bomb.is_inside_tree(), "and still in the level")
	assert_false(bomb.is_queued_for_deletion(), "and not queued for deletion")


# ── Assault: the budget and DISENGAGE ────────────────────────────────────────────────────────────

func test_assault_disengage_frees_the_bomber_only_outside_the_world_rect() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var bomber := _spawn(harness, Vector2(640.0, 60.0))
	bomber.config.engage_seconds = 0.2
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var freed_at := Vector2.INF
	for _i in 1500:
		_tick(bomber, DT)
		if bomber.is_queued_for_deletion():
			freed_at = bomber.global_position
			break
	assert_true(freed_at.is_finite(), "the budget disengages it")
	assert_false(rect.has_point(freed_at), "and it is freed only once outside the world rect")
	assert_eq((bomber.get_node("Brain") as BomberBrain).phase, BomberBrain.Phase.DISENGAGE)


func test_open_space_has_no_budget_so_the_bomber_stays() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var bomber := _spawn(harness, Vector2(640.0, 60.0))
	bomber.config.engage_seconds = 0.2
	for _i in 600:
		_tick(bomber, DT)
	assert_false(bomber.is_queued_for_deletion())
	assert_eq((bomber.get_node("Brain") as BomberBrain).phase, BomberBrain.Phase.APPROACH)


func test_approach_closes_on_the_player() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(900.0, 360.0)
	var bomber := _spawn(harness, Vector2(100.0, 100.0))
	var start := bomber.global_position.distance_to(harness.player.global_position)
	for _i in 60:
		_tick(bomber, DT)
	assert_lt(bomber.global_position.distance_to(harness.player.global_position), start,
		"APPROACH is a plain intercept toward the player")
