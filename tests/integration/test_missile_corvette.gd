## The Missile Corvette shell (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.9; task t7). Intent tests.
##
## What t7 pins: the scene's structure (one circle shared by body, hurtbox and contact box; two tubes; four rocket
## pools as root children that let a rocket outlive the corvette, sized by `EnemyRocketScenes.pool_size_for()` and
## equal to 3 / 6 / 3 / 4), `fire()` (alternates tubes, returns an unarmed rocket and sets none of its fields), the
## launcher answers (`launch_velocity()` and `rocket_clear_radius()`), the rail fallback (a Dumb rocket DOWN every
## `rail_rocket_interval`, and a real railed corvette never hitting itself), and the Assault budget's DISENGAGE exit.
## The fight (HOLD_ARC / TELEGRAPH / SALVO) is t8.
##
## Hand-stepped with a fixed delta (`set_physics_process(false)`), never a `Timer`, except the one railed row, which
## is real physics on the 8x clock (the pattern `test_bomber.gd` uses), restored in `after_each`.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const CORVETTE_SCENE: PackedScene = preload("res://assault/scenes/enemies/missile_corvette/missile_corvette.tscn")
const SHIPPED: MissileCorvetteConfig = preload("res://assault/scenes/enemies/missile_corvette/missile_corvette_config.tres")  # read only

const DT := 1.0 / 60.0
const POOLS := {
	"DumbPool": EnemyRocket.Kind.DUMB,
	"PursuitPool": EnemyRocket.Kind.PURSUIT,
	"ClusterPool": EnemyRocket.Kind.CLUSTER,
	"WarheadPool": EnemyRocket.Kind.WARHEAD,
}
const POOL_SIZES := {"DumbPool": 3, "PursuitPool": 6, "ClusterPool": 3, "WarheadPool": 4}
## The rocket exports `fire()` must leave exactly as the scene authors them.
const ROCKET_FIELDS: Array[StringName] = [
	&"launch_speed", &"cruise_speed", &"boost_seconds", &"accel", &"turn_rate", &"guidance_seconds", &"lead_max",
	&"impact_damage", &"blast_radius", &"blast_damage", &"blast_frames", &"arm_clearance", &"body_radius",
	&"max_time", &"max_distance",
]

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()


func _spawn(harness, pos: Vector2) -> MissileCorvette:
	var corvette := CORVETTE_SCENE.instantiate() as MissileCorvette
	(corvette.get_node("Brain") as MissileCorvetteBrain).start_engaged = true
	corvette.global_position = pos
	harness.root.add_child(corvette)
	corvette.set_physics_process(false)  # hand-ticked
	corvette.set_process(false)          # the rail clock is hand-stepped too
	return corvette


func _tick(corvette: MissileCorvette, delta: float) -> void:
	var before := corvette.global_position
	corvette._physics_process(delta)
	corvette.global_position = before + corvette.velocity * delta


func _rockets_in(root: Node) -> Array[EnemyRocket]:
	var found: Array[EnemyRocket] = []
	for child in root.get_children():
		if child is EnemyRocket:
			found.append(child)
	return found


# ── Structure ────────────────────────────────────────────────────────────────────────────────────

func test_the_four_pools_are_root_children_sized_3_6_3_4_that_let_rockets_outlive_the_corvette() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	for pool_name: String in POOLS:
		var pool := corvette.get_node_or_null(pool_name) as BulletPool
		assert_not_null(pool, "%s is a direct child of the root" % pool_name)
		if pool == null:
			continue
		assert_true(pool.persist_after_owner_death, "%s: persist_after_owner_death" % pool_name)
		assert_eq(pool.pool_size, EnemyRocketScenes.pool_size_for(POOLS[pool_name], corvette.config),
			"%s: sized by pool_size_for" % pool_name)
		assert_eq(pool.pool_size, POOL_SIZES[pool_name], "%s: the pinned size" % pool_name)
		assert_same(pool.bullet_scene, EnemyRocketScenes.scene_for(POOLS[pool_name]), "%s: its kind's scene" % pool_name)


func test_the_body_the_hurtbox_and_the_contact_box_share_one_40_px_circle() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	var body := corvette.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := corvette.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := corvette.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is CircleShape2D)
	assert_eq((body.shape as CircleShape2D).radius, 40.0)
	assert_same(hurt.shape, body.shape)
	assert_same(contact.shape, body.shape)
	assert_eq(corvette.rocket_clear_radius(), 40.0, "the hull radius the rocket clears before it arms")
	assert_eq(corvette.sprite_forward_angle, PI / 2.0, "nose-down hull art")


func test_the_tubes_sit_at_the_nose() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2.ZERO)
	assert_eq((corvette.get_node("Tubes/TubeL") as Marker2D).position, Vector2(-18.0, 30.0))
	assert_eq((corvette.get_node("Tubes/TubeR") as Marker2D).position, Vector2(18.0, 30.0))
	assert_not_null(corvette.get_node("Tubes/TubeLightL"))
	assert_not_null(corvette.get_node("Tubes/TubeLightR"))
	assert_not_null(corvette.get_node("StateLight"))


func test_the_config_is_applied_to_the_nodes_that_use_it() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	var mover := corvette.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, SHIPPED.max_speed)
	assert_eq(mover.acceleration, SHIPPED.acceleration)
	assert_eq(mover.max_turn_rate, SHIPPED.max_turn_rate)
	assert_eq(corvette.health.max_health, SHIPPED.max_health)
	assert_eq((corvette.get_node("ContactHitBox") as HitBox).damage, SHIPPED.collision_damage)
	assert_same((corvette.get_node("Brain") as MissileCorvetteBrain).config, corvette.config)
	assert_not_same(corvette.config, SHIPPED, "the corvette holds a private copy of the shipped config")
	assert_true(corvette.is_in_group("enemies"))


func test_the_shipped_config_carries_the_plan_values() -> void:
	assert_eq(SHIPPED.max_health, 160)
	assert_eq(SHIPPED.collision_damage, 30)
	assert_eq(SHIPPED.score_value, 70)
	assert_eq(SHIPPED.max_speed, 210.0)
	assert_eq(SHIPPED.acceleration, 240.0)
	assert_eq(SHIPPED.salvo_count, 3)
	assert_eq(SHIPPED.warhead_salvo_count, 2)
	assert_eq(SHIPPED.warhead_offset, 90.0)
	assert_eq(SHIPPED.salvo_period_min, 4.0)
	assert_eq(SHIPPED.rail_rocket_interval, 2.5)


# ── fire() ───────────────────────────────────────────────────────────────────────────────────────

func test_fire_alternates_tubes_and_returns_an_unarmed_rocket_with_unchanged_exports() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	var tube_l := corvette.get_node("Tubes/TubeL") as Marker2D
	var tube_r := corvette.get_node("Tubes/TubeR") as Marker2D
	var aim := Vector2(300.0, 700.0)
	var first := corvette.fire(EnemyRocket.Kind.DUMB, aim)
	var second := corvette.fire(EnemyRocket.Kind.DUMB, aim)
	assert_not_null(first)
	assert_not_null(second)
	assert_eq(first.global_position, tube_l.global_position, "the first rocket leaves TubeL")
	assert_eq(second.global_position, tube_r.global_position, "the second leaves TubeR")
	assert_eq(first.heading(), (aim - tube_l.global_position).normalized(), "launched at the aim point")
	assert_eq(first.aim_point(), aim)
	assert_false(first.is_armed(), "unarmed: the rocket arms itself once clear of the hull")
	assert_false(first.is_in_group("enemies"))
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER, EnemyRocket.Kind.WARHEAD]:
		var rocket := corvette.fire(kind, aim)
		var authored: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
		add_child_autofree(authored)
		assert_eq(rocket.kind, kind)
		for field in ROCKET_FIELDS:
			assert_eq(rocket.get(field), authored.get(field), "kind %d: %s is the scene's own" % [kind, field])
	for field in ROCKET_FIELDS:
		var authored: EnemyRocket = EnemyRocketScenes.scene_for(EnemyRocket.Kind.DUMB).instantiate()
		add_child_autofree(authored)
		assert_eq(first.get(field), authored.get(field), "DUMB: %s is the scene's own" % field)


func test_fire_returns_null_and_counts_the_refusal_when_a_pool_is_exhausted() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	var aim := Vector2(300.0, 700.0)
	for i in POOL_SIZES["DumbPool"]:
		assert_not_null(corvette.fire(EnemyRocket.Kind.DUMB, aim), "rocket %d" % i)
	assert_null(corvette.fire(EnemyRocket.Kind.DUMB, aim), "the fourth Dumb rocket is refused")
	assert_eq(corvette.rockets_refused, 1)


# ── launch_velocity() ────────────────────────────────────────────────────────────────────────────

func test_off_a_rail_launch_velocity_is_the_velocity() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	corvette.velocity = Vector2(30.0, 120.0)
	assert_eq(corvette.launch_velocity(), corvette.velocity)
	corvette.global_position += Vector2(5000.0, 0.0)
	corvette._observe_motion(DT)
	assert_eq(corvette.launch_velocity(), corvette.velocity, "the observed delta is for rails only")


func test_on_a_rail_launch_velocity_is_the_observed_position_change() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	corvette.suspend_ai()
	for i in 5:
		corvette.global_position += Vector2(0.0, 330.0 * DT)
		corvette._observe_motion(DT)
	assert_eq(corvette.velocity, Vector2.ZERO, "sanity: a rail leaves velocity at 0")
	assert_almost_eq(corvette.launch_velocity().x, 0.0, 0.5)
	assert_almost_eq(corvette.launch_velocity().y, 330.0, 0.5)


# ── The rail fallback ────────────────────────────────────────────────────────────────────────────

func test_a_rail_corvette_fires_one_dumb_rocket_straight_down_after_the_interval() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	corvette.suspend_ai()
	for i in int(2.6 / DT):
		corvette._process(DT)
	var rockets := _rockets_in(harness.root)
	assert_eq(rockets.size(), 1, "one rocket in 2.6 s at a 2.5 s interval")
	if rockets.is_empty():
		return
	assert_eq(rockets[0].kind, EnemyRocket.Kind.DUMB)
	assert_almost_eq(rockets[0].heading().x, 0.0, 0.05)
	assert_gt(rockets[0].heading().y, 0.99, "launched DOWN")


func test_an_unsuspended_corvette_fires_nothing_from_the_rail_clock() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	for i in int(SHIPPED.rail_rocket_interval * 3.0 / DT):
		corvette._process(DT)
	assert_eq(_rockets_in(harness.root).size(), 0, "the clock is a rail fallback only")


func test_a_rocket_in_flight_survives_its_corvette_dying() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2(300.0, 100.0))
	var rocket := corvette.fire(EnemyRocket.Kind.PURSUIT, Vector2(300.0, 700.0))
	assert_not_null(rocket)
	corvette.health.decrease(corvette.health.current_health)
	await wait_frames(3)
	assert_true(is_instance_valid(rocket), "the rocket is still alive")
	assert_true(rocket.is_inside_tree(), "and still in the level")
	assert_false(rocket.is_queued_for_deletion(), "and not queued for deletion")


# ── Real physics, 8x: a corvette on a rail never hits itself ─────────────────────────────────────

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


## A real corvette on a `straight()` rail moving down at 330 px/s (`StraightMovement.speed` is in design units and
## the rail doubles it by `ArenaCamera.WORLD_SCALE`, so 165) fires its fallback for 3 s (rate raised to every 0.9 s
## so three rockets fly). Its rockets start at `launch_speed` plus the observed rail speed and arm only once clear of
## the hull: the corvette keeps its health, every rocket pulls away from it and every one arms.
func test_a_railed_corvette_never_hits_itself() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := CORVETTE_SCENE.instantiate() as MissileCorvette
	corvette.global_position = Vector2(300.0, -400.0)
	harness.root.add_child(corvette)
	corvette.config.rail_rocket_interval = 0.9
	var rail := EnemyPathMover.new()
	var movement := StraightMovement.new()
	movement.speed = 330.0 / ArenaCamera.WORLD_SCALE
	rail.movement = movement
	rail.exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
	rail.exit_time = 60.0
	corvette.add_child(rail)
	assert_true(corvette.is_ai_suspended(), "sanity: the rail took the corvette over")

	_scale_clock()
	var start_hp := corvette.health.current_health
	var elapsed := 0.0
	var seen: Dictionary = {}  # EnemyRocket -> last distance to the corvette
	var launch_speed_reads: Array[Vector2] = []
	var grew := true
	while elapsed < 3.4:
		await get_tree().physics_frame
		elapsed += DT  # the step stays 1/60 game-second
		if not is_instance_valid(corvette):
			break
		for rocket in _rockets_in(harness.root):
			var d := rocket.global_position.distance_to(corvette.global_position)
			if seen.has(rocket) and d < float(seen[rocket]) - 0.01:
				grew = false
			seen[rocket] = d
		if elapsed > 1.0 and launch_speed_reads.is_empty():
			launch_speed_reads.append(corvette.launch_velocity())
	var armed_all := true
	for rocket in seen:
		if is_instance_valid(rocket) and not (rocket as EnemyRocket).is_armed():
			armed_all = false
	_restore_clock()

	assert_true(is_instance_valid(corvette), "the corvette is still here")
	assert_eq(corvette.health.current_health, start_hp, "the corvette is not hit by its own rockets")
	assert_gte(seen.size(), 2, "several rockets flew")
	assert_true(grew, "every rocket's distance to the corvette only grows after launch")
	assert_true(armed_all, "each rocket armed")
	assert_eq(launch_speed_reads.size(), 1)
	if launch_speed_reads.size() == 1:
		assert_almost_eq(launch_speed_reads[0].x, 0.0, 5.0, "launch_velocity on the rail: x")
		assert_almost_eq(launch_speed_reads[0].y, 330.0, 5.0, "launch_velocity on the rail: y")


# ── Assault: the budget and DISENGAGE ────────────────────────────────────────────────────────────

func test_assault_budget_expiry_enters_disengage_and_frees_the_corvette_outside_the_world_rect() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var corvette := _spawn(harness, Vector2(640.0, 60.0))
	corvette.config.engage_seconds = 0.2
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.APPROACH, "starts in APPROACH")
	for _i in 20:
		_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.DISENGAGE, "the budget ran out")
	var freed := false
	for _i in 1500:
		_tick(corvette, DT)
		if corvette.is_queued_for_deletion():
			freed = true
			break
	assert_true(freed, "freed once outside the world rect")
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	assert_false(rect.has_point(corvette.global_position), "and it left through the edge, not in the middle")


func test_open_space_has_no_budget_so_it_never_disengages() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var corvette := _spawn(harness, Vector2(640.0, 60.0))
	corvette.config.engage_seconds = 0.2
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in 600:
		_tick(corvette, DT)
	assert_ne(brain.phase, MissileCorvetteBrain.Phase.DISENGAGE)
	assert_false(corvette.is_queued_for_deletion())


func test_approach_closes_to_the_held_range_in_each_mode(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 660.0)
	var corvette := _spawn(harness, Vector2(640.0, 60.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	corvette.config.engage_seconds = 999.0
	_tick(corvette, DT)
	var expected := SHIPPED.assault_preferred_range if mode == "assault" else SHIPPED.preferred_range
	assert_eq(brain.held_range(), expected, "%s: the held range" % mode)
	for _i in 900:
		_tick(corvette, DT)
	var distance := corvette.global_position.distance_to(harness.player.global_position)
	assert_almost_eq(distance, expected, 25.0, "%s: settled at the held range" % mode)
