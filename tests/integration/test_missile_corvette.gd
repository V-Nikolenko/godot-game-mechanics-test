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


## t9: the hull art has its two launch tubes where `Tubes/TubeL` / `TubeR` are (an opaque pixel at each muzzle), and the
## lamps stay separate sprites on those markers.
func test_the_hull_art_has_a_launch_tube_at_each_tube_marker() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _spawn(harness, Vector2.ZERO)
	var sprite := corvette.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture.resource_path, "res://assault/assets/sprites/enemies/missile_corvette.png")
	var image := sprite.texture.get_image()
	var centre := Vector2(image.get_size()) * 0.5
	for side in ["L", "R"]:
		var marker := corvette.get_node("Tubes/Tube" + side) as Marker2D
		var lamp := corvette.get_node("Tubes/TubeLight" + side) as Sprite2D
		assert_eq(lamp.position, marker.position, "the lamp sits on its tube")
		assert_ne(lamp, marker, "separate nodes")
		var px := Vector2i(centre + marker.position + sprite.offset)
		assert_gt(image.get_pixelv(px).a, 0.9, "tube %s: the hull art is drawn at the muzzle %s" % [side, px])
		assert_gt(image.get_pixelv(px - Vector2i(0, 10)).a, 0.9, "tube %s: and along the barrel behind it" % side)
	# The hull is a wide one: opaque well past the body circle's 40 px on neither side beyond the 96 px canvas.
	assert_lt(image.get_used_rect().size.x, image.get_width())


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


## t8 changed what follows APPROACH: once within `range_tolerance` of the held range it hands over to HOLD_ARC, whose
## orbit radius drifts by up to `range_drift`, so the corvette no longer parks on R (the t7 form of this row).
func test_approach_closes_to_the_held_range_in_each_mode(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 660.0)
	var corvette := _spawn(harness, Vector2(640.0, -200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	corvette.config.engage_seconds = 999.0
	_tick(corvette, DT)
	var expected := SHIPPED.assault_preferred_range if mode == "assault" else SHIPPED.preferred_range
	assert_eq(brain.held_range(), expected, "%s: the held range" % mode)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.APPROACH, "%s: sanity, 860 px out it approaches" % mode)
	var handed_over_at := INF
	for _i in 900:
		_tick(corvette, DT)
		if brain.phase != MissileCorvetteBrain.Phase.APPROACH and handed_over_at == INF:
			handed_over_at = corvette.global_position.distance_to(harness.player.global_position)
	assert_true(handed_over_at < INF, "%s: it reached the held range" % mode)
	assert_almost_eq(handed_over_at, expected, SHIPPED.range_tolerance, "%s: HOLD_ARC takes over within range_tolerance" % mode)
	var distance := corvette.global_position.distance_to(harness.player.global_position)
	assert_almost_eq(distance, expected, SHIPPED.range_drift + SHIPPED.range_tolerance, "%s: and holds the range" % mode)


# ── t8: the fight (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.10) ──────────────────────────────────────────
#
# Hand-ticked, dual-mode unless the name says otherwise, every corvette seeded. Rockets a hand-ticked row fires stay
# where `fire()` put them (no frame passes inside a synchronous test), so a row reads each rocket's launch position
# (its tube) and `aim_point()` straight off it. The Assault budget is lifted wherever a row runs longer than the
# budget's own rows want.

const MODES := ["open_space", "assault"]
const _SEED := 8101


func _harness(mode: String):
	return HARNESS.open_space() if mode == "open_space" else HARNESS.assault()


func _range_for(mode: String) -> float:
	return SHIPPED.assault_preferred_range if mode == "assault" else SHIPPED.preferred_range


func _seeded(harness, pos: Vector2, rng_seed: int = _SEED, lift_budget: bool = true) -> MissileCorvette:
	var corvette := CORVETTE_SCENE.instantiate() as MissileCorvette
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	brain.start_engaged = true
	brain.rng_seed = rng_seed
	corvette.global_position = pos
	harness.root.add_child(corvette)
	corvette.set_physics_process(false)
	corvette.set_process(false)
	if lift_budget:
		corvette.config.engage_seconds = 999.0
	return corvette


## A row that builds several harnesses in one test calls this first: `TargetInfo.player()` takes the first node in
## group "player", which would otherwise be an earlier iteration's stub (still in the tree until the test ends).
func _retire_players() -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		node.remove_from_group(&"player")


func _nose(corvette: MissileCorvette) -> Vector2:
	return Vector2.RIGHT.rotated(corvette.rotation + corvette.sprite_forward_angle)


## The stub moves on its own velocity after each corvette tick.
func _step(corvette: MissileCorvette, player: CharacterBody2D) -> void:
	_tick(corvette, DT)
	player.global_position += player.velocity * DT


## One entry per rocket not yet in `known`: {rocket, kind, tick}.
func _new_rockets(root: Node, known: Array, tick: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for rocket in _rockets_in(root):
		if not known.has(rocket):
			known.append(rocket)
			found.append({"rocket": rocket, "kind": rocket.kind, "tick": tick, "from": rocket.global_position, "aim": rocket.aim_point()})
	return found


func test_holds_a_broad_arc_at_range_from_1200_px(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var stub := Vector2(640.0, 360.0)
	harness.player.global_position = stub
	var corvette := _seeded(harness, stub + Vector2(0.0, -1200.0))
	var r := _range_for(mode)
	var band := SHIPPED.range_drift + SHIPPED.range_tolerance
	for _i in int(6.0 / DT):
		_tick(corvette, DT)
	var worst := 0.0
	var swept := 0.0
	var bearing := (corvette.global_position - stub).angle()
	for _i in int(10.0 / DT):
		_tick(corvette, DT)
		var offset := corvette.global_position - stub
		worst = maxf(worst, absf(offset.length() - r))
		swept += absf(angle_difference(bearing, offset.angle()))
		bearing = offset.angle()
	assert_lte(worst, band, "%s: the distance stays within R ± (drift + tolerance)" % mode)
	assert_gte(rad_to_deg(swept), 60.0, "%s: it arcs round the player rather than parking" % mode)


func test_a_rushing_player_is_kept_at_bay(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var r := _range_for(mode)
	var stub := Vector2(640.0, 900.0)
	harness.player.global_position = stub
	# Assault: the corridor's top edge (y = -380) is >= 400 px behind the corvette.
	var corvette := _seeded(harness, stub + Vector2(0.0, -r))
	for _i in int(0.5 / DT):
		_tick(corvette, DT)
	assert_eq((corvette.get_node("Brain") as MissileCorvetteBrain).phase, MissileCorvetteBrain.Phase.HOLD_ARC,
		"%s: sanity, settled in HOLD_ARC" % mode)
	var dir: Vector2 = (corvette.global_position - harness.player.global_position).normalized()
	harness.player.velocity = dir * 200.0
	var closest := INF
	for _i in int(2.0 / DT):
		_step(corvette, harness.player)
		closest = minf(closest, corvette.global_position.distance_to(harness.player.global_position))
	harness.player.velocity = Vector2.ZERO
	var out_after := INF
	for i in int(3.0 / DT):
		_step(corvette, harness.player)
		var d := corvette.global_position.distance_to(harness.player.global_position)
		closest = minf(closest, d)
		if d > SHIPPED.min_range:
			out_after = (i + 1) * DT
			break
	assert_gte(closest, 0.6 * SHIPPED.min_range, "%s: the closest approach" % mode)
	assert_lte(out_after, 3.0, "%s: back outside min_range within 3 s of the stop" % mode)


## Boundary for the row above: a player faster than the corvette (350 px/s) does get inside `min_range`, so this row
## reaches the break-off blend (§2.10.2). While inside, the hull opens the range (outward radial velocity) and slides
## the way its arc turns (tangential velocity in `orbit_dir`'s sense) - the blend's sideways share; the orbit alone
## gives a slightly negative mean here, and `break_contact`'s side the other way gives a 147 px pass (Assault).
## Measured: closest approach 250 px (Assault) / 331 px (Open Space), mean sideways speed 34 / 39 px/s.
func test_a_faster_rusher_gets_inside_and_is_sidestepped(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var stub := Vector2(640.0, 900.0)
	harness.player.global_position = stub
	var corvette := _seeded(harness, stub + Vector2(0.0, -_range_for(mode)))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in int(0.5 / DT):
		_tick(corvette, DT)
	var dir: Vector2 = (corvette.global_position - harness.player.global_position).normalized()
	harness.player.velocity = dir * 350.0
	var closest := INF
	var inside_ticks := 0
	var sideways := 0.0
	var outward := 0.0
	for _i in int(2.0 / DT):
		_step(corvette, harness.player)
		var offset: Vector2 = corvette.global_position - harness.player.global_position
		closest = minf(closest, offset.length())
		if offset.length() < SHIPPED.min_range:
			inside_ticks += 1
			var arc_sense := Vector2(-offset.y, offset.x).normalized() * brain.orbit_dir  # the orbit's travel, +90°
			sideways += corvette.velocity.dot(arc_sense)
			outward += corvette.velocity.dot(offset.normalized())
	harness.player.velocity = Vector2.ZERO
	var out_after := INF
	for i in int(3.0 / DT):
		_step(corvette, harness.player)
		if corvette.global_position.distance_to(harness.player.global_position) > SHIPPED.min_range:
			out_after = (i + 1) * DT
			break
	assert_gt(inside_ticks, 0, "%s: sanity, a 350 px/s rusher gets inside min_range" % mode)
	if inside_ticks == 0:
		return
	assert_gt(outward / inside_ticks, 0.0, "%s: inside, it opens the range" % mode)
	assert_gte(sideways / inside_ticks, 15.0, "%s: inside, it slides the way its arc turns" % mode)
	assert_gte(closest, 0.5 * SHIPPED.min_range, "%s: sidestepped wide, not run through" % mode)
	assert_lte(out_after, 3.0, "%s: back outside min_range within 3 s of the stop" % mode)


func test_the_orbit_reverses_within_15_s() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var stub := Vector2(640.0, 360.0)
	harness.player.global_position = stub
	var corvette := _seeded(harness, stub + Vector2(0.0, -SHIPPED.preferred_range))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	_tick(corvette, DT)
	var first_dir := brain.orbit_dir
	var flipped := false
	var signs: Array[float] = []
	var bearing := (corvette.global_position - stub).angle()
	var window := 0.0
	for i in int(15.0 / DT):
		_tick(corvette, DT)
		flipped = flipped or brain.orbit_dir != first_dir
		var b := (corvette.global_position - stub).angle()
		window += angle_difference(bearing, b)
		bearing = b
		if (i + 1) % 30 == 0:
			if absf(window) > 0.01:
				signs.append(signf(window))
			window = 0.0
	var changes := 0
	for i in range(1, signs.size()):
		if signs[i] != signs[i - 1]:
			changes += 1
	assert_true(flipped, "orbit_dir flipped")
	assert_gte(changes, 1, "the measured bearing rate changed sign")


## The cone is the only thing that stops it: through the whole window the corvette is in HOLD_ARC, its cooldown is 0 and
## the budget gate is open, and the moment the stub is put in front of the nose it telegraphs (the control).
func test_no_salvo_at_a_player_held_behind_it(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var r := _range_for(mode)
	var corvette := _seeded(harness, Vector2(640.0, 360.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	harness.player.global_position = corvette.global_position - _nose(corvette) * r
	_tick(corvette, DT)
	brain.salvo_cooldown = 0.0  # after the first tick, which draws it
	var telegraphs := [0]
	brain.phase_changed.connect(func(p: int) -> void:
		if p == MissileCorvetteBrain.Phase.TELEGRAPH:
			telegraphs[0] += 1)
	var ready_ticks := 0
	var ticks := int(6.0 / DT)
	for _i in ticks:
		harness.player.global_position = corvette.global_position - _nose(corvette) * r
		_tick(corvette, DT)
		var gate_open := brain.budget.remaining() >= brain.attack_window() + MissileCorvetteBrain.ATTACK_GATE_MARGIN
		if brain.phase == MissileCorvetteBrain.Phase.HOLD_ARC and brain.salvo_cooldown == 0.0 and gate_open:
			ready_ticks += 1
	assert_eq(ready_ticks, ticks, "%s: sanity, HOLD_ARC, cooldown 0 and the gate open on every tick" % mode)
	assert_eq(telegraphs[0], 0, "%s: no telegraph at a player kept behind the nose" % mode)
	assert_eq(_rockets_in(harness.root).size(), 0, "%s: and no rocket" % mode)
	harness.player.global_position = corvette.global_position + _nose(corvette) * r
	_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.TELEGRAPH, "%s: control, in front it telegraphs at once" % mode)


func test_a_player_in_front_draws_a_telegraph_in_time(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var r := _range_for(mode)
	var corvette := _seeded(harness, Vector2(640.0, 200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	harness.player.global_position = corvette.global_position + _nose(corvette) * r
	var at := INF
	for i in int((SHIPPED.salvo_period_max + 1.0) / DT):
		_tick(corvette, DT)
		if brain.phase == MissileCorvetteBrain.Phase.TELEGRAPH:
			at = (i + 1) * DT
			break
	assert_lte(at, SHIPPED.salvo_period_max + 1.0, "%s: the first telegraph" % mode)


## Drives one forced salvo of `kind` at a still stub in front, from the first TELEGRAPH tick to 10 ticks after the
## return to HOLD_ARC. Returns {telegraph_tick, rockets: [{kind, tick, ...}], lights: [states], tow: [[phase, ok]]}.
func _run_salvo(harness, corvette: MissileCorvette, kind: EnemyRocket.Kind) -> Dictionary:
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var light := corvette.get_node("StateLight") as StateLight
	_tick(corvette, DT)
	brain.force_next_kind(kind)
	brain.salvo_cooldown = 0.0
	var out := {"telegraph_tick": -1, "rockets": [], "lights": [], "tow": []}
	var known: Array = []
	var after := -1
	for i in int(4.0 / DT):
		_step(corvette, harness.player)
		if out.telegraph_tick < 0 and brain.phase == MissileCorvetteBrain.Phase.TELEGRAPH:
			out.telegraph_tick = i
		out.rockets.append_array(_new_rockets(harness.root, known, i))
		out.lights.append(light.get_state())
		out.tow.append([brain.phase, brain.accepts_tow()])
		if out.telegraph_tick >= 0 and brain.phase == MissileCorvetteBrain.Phase.HOLD_ARC and after < 0:
			after = i
		if after >= 0 and i >= after + 10:
			break
	return out


func test_salvo_shape_per_kind(mode: String = use_parameters(MODES)) -> void:
	var r := _range_for(mode)
	var expected_counts := {
		EnemyRocket.Kind.DUMB: 3, EnemyRocket.Kind.PURSUIT: 3, EnemyRocket.Kind.CLUSTER: 3, EnemyRocket.Kind.WARHEAD: 2,
	}
	for kind: EnemyRocket.Kind in expected_counts:
		_retire_players()
		var harness = _harness(mode)
		add_child_autofree(harness.root)
		var corvette := _seeded(harness, Vector2(640.0, 200.0))
		var brain := corvette.get_node("Brain") as MissileCorvetteBrain
		harness.player.global_position = corvette.global_position + _nose(corvette) * r
		var run := _run_salvo(harness, corvette, kind)
		var label := "%s kind %d" % [mode, kind]
		assert_eq(brain.salvo_size(kind), expected_counts[kind], "%s: salvo_size" % label)
		assert_gte(run.telegraph_tick, 0, "%s: a telegraph started" % label)
		var rockets: Array = run.rockets
		assert_eq(rockets.size(), expected_counts[kind], "%s: rockets in the salvo" % label)
		if rockets.is_empty():
			continue
		for rocket: Dictionary in rockets:
			assert_eq(rocket.kind, kind, "%s: every rocket of the chosen kind" % label)
		var telegraph_s: float = (rockets[0].tick - run.telegraph_tick) * DT
		assert_almost_eq(telegraph_s, SHIPPED.salvo_telegraph, DT + 1e-4, "%s: the first rocket after the telegraph" % label)
		for i in range(1, rockets.size()):
			var gap: float = (rockets[i].tick - rockets[i - 1].tick) * DT
			assert_almost_eq(gap, SHIPPED.salvo_gap, DT + 1e-4, "%s: rocket %d at salvo_gap" % [label, i])
		var sequence: Array = []
		for state: int in run.lights:
			if sequence.is_empty() or sequence.back() != state:
				sequence.append(state)
		assert_eq(sequence, [StateLight.State.CHARGING, StateLight.State.ARMED, StateLight.State.OFF],
			"%s: CHARGING -> ARMED -> OFF" % label)
		assert_false(StateLight.State.COMMIT in run.lights, "%s: never COMMIT" % label)
		var refused_ok := true
		var hold_ok := true
		var hold_seen := 0
		for row: Array in run.tow:
			if row[0] == MissileCorvetteBrain.Phase.TELEGRAPH or row[0] == MissileCorvetteBrain.Phase.SALVO:
				refused_ok = refused_ok and not row[1]
			elif row[0] == MissileCorvetteBrain.Phase.HOLD_ARC:
				hold_ok = hold_ok and row[1]
				hold_seen += 1
		assert_true(refused_ok, "%s: accepts_tow() false through TELEGRAPH and SALVO" % label)
		assert_true(hold_ok and hold_seen > 0, "%s: and true in HOLD_ARC" % label)


func test_dumb_aim_points_lead_along_the_predicted_path(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var r := _range_for(mode)
	var corvette := _seeded(harness, Vector2(500.0, 200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var line_y := corvette.global_position.y + r
	harness.player.global_position = Vector2(500.0, line_y)
	harness.player.velocity = Vector2(250.0, 0.0)
	_tick(corvette, DT)
	brain.force_next_kind(EnemyRocket.Kind.DUMB)
	brain.salvo_cooldown = 0.0
	var cruise := float(EnemyRocketScenes.export_of(EnemyRocket.Kind.DUMB, &"cruise_speed", 0.0))
	var known: Array = []
	var shots: Array[Dictionary] = []
	for i in int(2.5 / DT):
		var stub_at: Vector2 = harness.player.global_position
		_step(corvette, harness.player)
		for shot in _new_rockets(harness.root, known, i):
			shot["stub"] = stub_at
			shots.append(shot)
	assert_eq(shots.size(), 3, "%s: three Dumb rockets" % mode)
	for i in shots.size():
		var target := TargetInfo.new()
		target.has_target = true
		target.position = shots[i].stub
		target.velocity = Vector2(250.0, 0.0)
		var hit := target.intercept(shots[i].from, cruise)
		assert_true(hit.ok, "%s: sanity, the intercept exists" % mode)
		var lead: float = float(hit.time) + i * SHIPPED.salvo_lead_step
		var expected := target.predicted_position(lead)
		var aim: Vector2 = shots[i].aim
		assert_almost_eq(aim.distance_to(expected), 0.0, 1.0, "%s: rocket %d leads by intercept + %d x salvo_lead_step" % [mode, i, i])
		assert_almost_eq(aim.y, line_y, 1.0, "%s: rocket %d on the predicted line" % [mode, i])


func test_kind_choice() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var brain := _seeded(harness, Vector2.ZERO).get_node("Brain") as MissileCorvetteBrain
	assert_eq(brain.choose_kind(600.0, 350.0, 350.0), EnemyRocket.Kind.PURSUIT, "fleeing at 350 px/s")
	assert_eq(brain.choose_kind(600.0, 350.0, -350.0), EnemyRocket.Kind.DUMB, "as fast but closing: not Pursuit")
	assert_eq(brain.choose_kind(300.0, 0.0, 0.0), EnemyRocket.Kind.WARHEAD, "300 px")
	assert_eq(brain.choose_kind(300.0, 350.0, 350.0), EnemyRocket.Kind.WARHEAD, "a close player gets Warheads first")
	assert_eq(brain.choose_kind(SHIPPED.warhead_range, 0.0, 0.0), EnemyRocket.Kind.DUMB, "the warhead edge is exclusive")
	assert_eq(brain.choose_kind(800.0, 250.0, 0.0), EnemyRocket.Kind.CLUSTER, "far and crossing")
	assert_eq(brain.choose_kind(650.0, 250.0, 0.0), EnemyRocket.Kind.DUMB, "crossing but inside cluster_min_range")
	assert_eq(brain.choose_kind(800.0, 250.0, 200.0), EnemyRocket.Kind.DUMB, "far but mostly radial")
	assert_eq(brain.choose_kind(600.0, 200.0, 200.0), EnemyRocket.Kind.DUMB, "fleeing slower than pursuit_flee_speed")
	assert_eq(brain.salvo_size(EnemyRocket.Kind.DUMB), 3)
	assert_eq(brain.salvo_size(EnemyRocket.Kind.PURSUIT), 3)
	assert_eq(brain.salvo_size(EnemyRocket.Kind.CLUSTER), 3)
	assert_eq(brain.salvo_size(EnemyRocket.Kind.WARHEAD), 2)


func test_a_fleeing_player_draws_a_pursuit_salvo(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var d := _range_for(mode) + 40.0
	var corvette := _seeded(harness, Vector2(640.0, 100.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var nose := _nose(corvette)
	harness.player.global_position = corvette.global_position + nose * d
	harness.player.velocity = nose * 350.0  # straight away from the corvette; position held for the snapshot
	_tick(corvette, DT)
	brain.salvo_cooldown = 0.0
	for _i in 10:
		_tick(corvette, DT)
		if brain.phase == MissileCorvetteBrain.Phase.TELEGRAPH:
			break
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.TELEGRAPH, "%s: sanity, telegraphing" % mode)
	assert_eq(brain.salvo_kind, EnemyRocket.Kind.PURSUIT, "%s: a Pursuit salvo at a player fleeing at 350 px/s" % mode)


func test_a_close_player_gets_a_warhead_pair_across_its_path(mode: String = use_parameters(MODES)) -> void:
	for moving: bool in [true, false]:
		_retire_players()
		var harness = _harness(mode)
		add_child_autofree(harness.root)
		var corvette := _seeded(harness, Vector2(640.0, 300.0))
		var brain := corvette.get_node("Brain") as MissileCorvetteBrain
		harness.player.global_position = corvette.global_position + _nose(corvette) * 300.0
		harness.player.velocity = Vector2(150.0, 0.0) if moving else Vector2.ZERO
		_tick(corvette, DT)
		brain.enter_phase(MissileCorvetteBrain.Phase.HOLD_ARC)
		brain.salvo_cooldown = 0.0
		var known: Array = []
		var shots: Array[Dictionary] = []
		for i in int(1.5 / DT):
			_step(corvette, harness.player)
			shots.append_array(_new_rockets(harness.root, known, i))
		var label := "%s %s" % [mode, "moving" if moving else "still"]
		assert_eq(brain.salvos_fired, 1, "%s: one salvo" % label)
		assert_eq(shots.size(), 2, "%s: a pair" % label)
		if shots.size() != 2:
			continue
		assert_eq(shots[0].kind, EnemyRocket.Kind.WARHEAD, "%s: Warheads at 300 px" % label)
		assert_eq(shots[1].kind, EnemyRocket.Kind.WARHEAD, "%s: Warheads at 300 px" % label)
		var apart: Vector2 = shots[0].aim - shots[1].aim
		if moving:
			assert_almost_eq(absf(apart.y), 2.0 * SHIPPED.warhead_offset, 1.0, "%s: 180 px apart across the velocity" % label)
		else:
			assert_almost_eq(apart.length(), 2.0 * SHIPPED.warhead_offset, 1.0, "%s: 180 px apart across the line of sight" % label)


## Puts an Assault corvette into HOLD_ARC with a still stub in front and a Dumb salvo forced, and the budget set so
## that `remaining()` reads `left` right after the NEXT tick's update.
func _assault_gate(left: float) -> Dictionary:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	var corvette := _seeded(harness, Vector2(640.0, 240.0), _SEED, false)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	harness.player.global_position = corvette.global_position + _nose(corvette) * SHIPPED.assault_preferred_range
	_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.HOLD_ARC, "sanity: holding the arc")
	brain.force_next_kind(EnemyRocket.Kind.DUMB)
	brain.salvo_cooldown = 0.0
	var elapsed := brain.budget.seconds - brain.budget.remaining()
	brain.budget.seconds = elapsed + DT + left
	return {"harness": harness, "corvette": corvette, "brain": brain}


func test_assault_salvo_started_with_1_2_s_left_completes() -> void:
	var w := _assault_gate(1.2)
	var corvette: MissileCorvette = w.corvette
	var brain: MissileCorvetteBrain = w.brain
	_tick(corvette, DT)
	assert_almost_eq(brain.budget.remaining(), 1.2, 1e-4, "sanity: 1.2 s left")
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.TELEGRAPH, "a telegraph starts with 1.2 s left")
	for _i in int(2.0 / DT):
		_tick(corvette, DT)
		if brain.phase == MissileCorvetteBrain.Phase.DISENGAGE:
			break
	assert_eq(_rockets_in(w.harness.root).size(), 3, "the whole salvo fired")
	assert_eq(brain.salvos_fired, 1)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.DISENGAGE, "then it disengages")


## The gate asks for the salvo's own length plus the margin: 1.0 s proves a gate exists, 1.17 s (between the 1.14 s
## salvo and the 1.19 s gate) proves the margin does.
func test_assault_no_salvo_starts_with_1_0_s_left() -> void:
	for left: float in [1.0, 1.17]:
		_retire_players()
		var w := _assault_gate(left)
		var corvette: MissileCorvette = w.corvette
		var brain: MissileCorvetteBrain = w.brain
		var telegraphs := [0]
		brain.phase_changed.connect(func(p: int) -> void:
			if p == MissileCorvetteBrain.Phase.TELEGRAPH:
				telegraphs[0] += 1)
		for _i in int(1.5 / DT):
			_tick(corvette, DT)
			if brain.phase == MissileCorvetteBrain.Phase.DISENGAGE:
				break
		assert_eq(telegraphs[0], 0, "no telegraph starts with %.2f s left" % left)
		assert_eq(_rockets_in(w.harness.root).size(), 0, "%.2f s: no rocket" % left)
		assert_eq(brain.phase, MissileCorvetteBrain.Phase.DISENGAGE, "%.2f s: the budget ran out" % left)


func test_the_attack_window_comes_from_the_config() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var brain := _seeded(harness, Vector2.ZERO).get_node("Brain") as MissileCorvetteBrain
	var expected := SHIPPED.salvo_telegraph + (maxi(SHIPPED.salvo_count, SHIPPED.warhead_salvo_count) - 1) * SHIPPED.salvo_gap
	assert_almost_eq(brain.attack_window(), expected, 1e-6)
	assert_almost_eq(brain.attack_window(), 1.14, 1e-6, "the §2.10.9 bound with the shipped config")


## §2.10.9: a TELEGRAPH the budget expires in still fires its whole salvo, and DISENGAGE follows within the deferral
## bound (`salvo_telegraph + (salvo_count - 1) x salvo_gap`, + 2 ticks) of the TELEGRAPH start.
func test_budget_expiry_mid_telegraph_defers_to_the_salvo() -> void:
	var w := _assault_gate(5.0)
	var corvette: MissileCorvette = w.corvette
	var brain: MissileCorvetteBrain = w.brain
	brain.enter_phase(MissileCorvetteBrain.Phase.TELEGRAPH)
	brain.budget.seconds = (brain.budget.seconds - brain.budget.remaining()) + 0.3
	var phases: Array[int] = []
	brain.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var rockets_at_disengage := -1
	var disengaged_after := INF
	for i in int(2.0 / DT):
		_tick(corvette, DT)
		if brain.phase == MissileCorvetteBrain.Phase.DISENGAGE:
			rockets_at_disengage = _rockets_in(w.harness.root).size()
			disengaged_after = (i + 1) * DT
			break
	assert_eq(brain.budget.remaining(), 0.0, "sanity: the budget expired mid-telegraph")
	assert_eq(phases, [MissileCorvetteBrain.Phase.SALVO, MissileCorvetteBrain.Phase.DISENGAGE],
		"the salvo, then DISENGAGE")
	assert_eq(rockets_at_disengage, 3, "the full salvo left before the exit")
	assert_lte(disengaged_after, SHIPPED.salvo_telegraph + (SHIPPED.salvo_count - 1) * SHIPPED.salvo_gap + 2.0 * DT + 1e-4,
		"DISENGAGE within the deferral bound")


func test_a_telegraph_cancels_when_the_player_leaves_the_cone_only_in_open_space(mode: String = use_parameters(MODES)) -> void:
	var harness = _harness(mode)
	add_child_autofree(harness.root)
	var r := _range_for(mode)
	var corvette := _seeded(harness, Vector2(640.0, 200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var light := corvette.get_node("StateLight") as StateLight
	harness.player.global_position = corvette.global_position + _nose(corvette) * r
	_tick(corvette, DT)
	brain.force_next_kind(EnemyRocket.Kind.DUMB)
	brain.salvo_cooldown = 0.0
	_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.TELEGRAPH, "%s: sanity, telegraphing" % mode)
	for _i in 10:
		_tick(corvette, DT)
	harness.player.global_position = corvette.global_position - _nose(corvette) * r
	_tick(corvette, DT)
	if mode == "open_space":
		assert_eq(brain.phase, MissileCorvetteBrain.Phase.HOLD_ARC, "cancelled: back to HOLD_ARC")
		assert_eq(light.get_state(), StateLight.State.OFF, "light OFF")
		for _i in int(0.8 / DT):
			_tick(corvette, DT)
		assert_eq(_rockets_in(harness.root).size(), 0, "no rocket left")
	else:
		for _i in int(1.0 / DT):
			_tick(corvette, DT)
		assert_eq(_rockets_in(harness.root).size(), 3, "Assault: a started salvo always fires")


## §2.10.4: a seeded `rng` swaps a Dumb choice for Pursuit one time in four; a Warhead or Cluster choice is never
## swapped. Each `enter_phase(TELEGRAPH)` rolls the kind once.
func test_one_dumb_choice_in_four_becomes_a_pursuit_salvo() -> void:
	var cases := [
		{"label": "dumb", "offset": 600.0, "velocity": Vector2.ZERO},
		{"label": "warhead", "offset": 300.0, "velocity": Vector2.ZERO},
		{"label": "cluster", "offset": 800.0, "velocity": Vector2(250.0, 0.0)},
	]
	for c: Dictionary in cases:
		_retire_players()
		var harness = HARNESS.open_space()
		add_child_autofree(harness.root)
		var corvette := _seeded(harness, Vector2(640.0, 0.0))
		var brain := corvette.get_node("Brain") as MissileCorvetteBrain
		harness.player.global_position = corvette.global_position + Vector2(0.0, c.offset)
		harness.player.velocity = c.velocity
		var counts := {}
		for _i in 200:
			brain.enter_phase(MissileCorvetteBrain.Phase.TELEGRAPH)
			counts[brain.salvo_kind] = int(counts.get(brain.salvo_kind, 0)) + 1
		match c.label:
			"dumb":
				var share := float(counts.get(EnemyRocket.Kind.PURSUIT, 0)) / 200.0
				assert_between(share, 0.15, 0.35, "a Dumb situation: Pursuit share %.2f" % share)
				assert_eq(int(counts.get(EnemyRocket.Kind.PURSUIT, 0)) + int(counts.get(EnemyRocket.Kind.DUMB, 0)), 200,
					"a Dumb situation only ever gives Dumb or Pursuit")
			"warhead":
				assert_eq(int(counts.get(EnemyRocket.Kind.WARHEAD, 0)), 200, "a Warhead choice is never swapped")
			"cluster":
				assert_eq(int(counts.get(EnemyRocket.Kind.CLUSTER, 0)), 200, "a Cluster choice is never swapped")


## §2.10.6-7: the tube lights ramp 0 -> 1 over the telegraph, flash to full on every launch and fall back between
## launches, and are dark afterwards. (`set_tube_glow` maps 1 to an alpha of 0.85.)
func test_the_tubes_glow_up_through_the_telegraph_and_flash_per_launch() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _seeded(harness, Vector2(640.0, 200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var lamp := corvette.get_node("Tubes/TubeLightL") as Sprite2D
	harness.player.global_position = corvette.global_position + _nose(corvette) * SHIPPED.preferred_range
	_tick(corvette, DT)
	brain.force_next_kind(EnemyRocket.Kind.DUMB)
	brain.salvo_cooldown = 0.0
	_tick(corvette, DT)
	assert_eq(brain.phase, MissileCorvetteBrain.Phase.TELEGRAPH, "sanity: telegraphing")
	assert_almost_eq(lamp.modulate.a, 0.0, 1e-4, "dark when the telegraph starts")
	var ramp: Array[float] = []
	var known: Array = []
	var launch_alphas: Array[float] = []
	var between: Array[float] = []
	for i in int(2.0 / DT):
		_tick(corvette, DT)
		var launched := _new_rockets(harness.root, known, i).size() > 0
		match brain.phase:
			MissileCorvetteBrain.Phase.TELEGRAPH:
				ramp.append(lamp.modulate.a)
			MissileCorvetteBrain.Phase.SALVO:
				if launched:
					launch_alphas.append(lamp.modulate.a)
				else:
					between.append(lamp.modulate.a)
			_:
				if launched:
					launch_alphas.append(-1.0)  # the last launch ends the salvo on its own tick
				break
	var rising := true
	for i in range(1, ramp.size()):
		rising = rising and ramp[i] >= ramp[i - 1] - 1e-6
	assert_true(rising, "the glow only rises through the telegraph")
	assert_gte(ramp.back(), 0.8, "and is near full at its end")
	assert_almost_eq(ramp[ramp.size() / 2], 0.85 * 0.5, 0.05, "a ramp: half-lit halfway through")
	assert_eq(launch_alphas.size(), 3, "three launches seen")
	for a in launch_alphas.slice(0, 2):
		assert_almost_eq(a, 0.85, 1e-4, "full on a launch")
	for a in between:
		assert_lt(a, 0.85, "falls back between launches")
		assert_gte(a, 0.35 * 0.85 - 1e-4, "but not below the salvo floor")
	assert_almost_eq(lamp.modulate.a, 0.0, 1e-4, "dark after the salvo")


func test_a_rail_taking_the_corvette_mid_telegraph_darkens_its_tubes() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	var corvette := _seeded(harness, Vector2(640.0, 200.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var lamp := corvette.get_node("Tubes/TubeLightL") as Sprite2D
	harness.player.global_position = corvette.global_position + _nose(corvette) * SHIPPED.preferred_range
	_tick(corvette, DT)
	brain.enter_phase(MissileCorvetteBrain.Phase.TELEGRAPH)
	for _i in 20:
		_tick(corvette, DT)
	assert_gt(lamp.modulate.a, 0.2, "sanity: glowing")
	corvette.suspend_ai()
	assert_almost_eq(lamp.modulate.a, 0.0, 1e-4, "dark once a rail owns it")
	assert_eq((corvette.get_node("StateLight") as StateLight).get_state(), StateLight.State.OFF, "light OFF")


func test_the_arc_is_within_the_hulls_turning_budget() -> void:
	for r: float in [SHIPPED.preferred_range, SHIPPED.assault_preferred_range]:
		assert_lte(SHIPPED.max_speed * SHIPPED.max_speed / r, SHIPPED.acceleration,
			"max_speed^2 / %.0f <= acceleration" % r)


func test_export_of_reads_a_rocket_scenes_export_without_instantiating_it() -> void:
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER, EnemyRocket.Kind.WARHEAD]:
		var authored: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
		add_child_autofree(authored)
		assert_eq(float(EnemyRocketScenes.export_of(kind, &"cruise_speed", -1.0)), authored.cruise_speed, "kind %d cruise_speed" % kind)
		assert_eq(EnemyRocketScenes.max_time_of(kind), authored.max_time, "kind %d max_time" % kind)
	assert_eq(float(EnemyRocketScenes.export_of(EnemyRocket.Kind.DUMB, &"cruise_speed", 0.0)), 520.0)
	assert_eq(EnemyRocketScenes.export_of(EnemyRocket.Kind.DUMB, &"no_such_export", 7.0), 7.0, "the fallback")


# ══ t15: hub idle (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.16; task cmv9szqmc002rqs2xfz6xg6v0) ═════════════
#
# Cold-start helpers: unlike `_seeded()` / `_spawn()` (which set `start_engaged = true`, so every row above keeps
# assuming combat-from-spawn), these leave the brain to decide for itself - Open Space starts IDLE, Assault starts in
# combat. The stub player is stationary unless a row moves it.

const FAR_AWAY := Vector2(100000.0, 100000.0)
const Phase := MissileCorvetteBrain.Phase


func _cold(harness, pos: Vector2, player_pos: Vector2, anchor: Vector2 = Vector2.INF) -> MissileCorvette:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	var corvette := CORVETTE_SCENE.instantiate() as MissileCorvette
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	brain.rng_seed = 1717
	brain.patrol_anchor = anchor
	corvette.global_position = pos
	harness.root.add_child(corvette)
	corvette.set_physics_process(false)
	corvette.set_process(false)
	return corvette


func _calm(p: int) -> bool:
	return p == Phase.IDLE or p == Phase.NOTICING or p == Phase.RETURNING


func test_the_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(Phase.APPROACH, 0)
	assert_eq(Phase.DISENGAGE, 4)
	assert_eq(Phase.IDLE, 5)
	assert_eq(Phase.NOTICING, 6)
	assert_eq(Phase.RETURNING, 7)


## §2.16: lose_radius > preferred_range + range_drift + range_tolerance (620 + 80 + 120 = 820), read from the fields.
func test_the_idle_radii_clear_the_largest_distance_its_own_cycle_opens() -> void:
	var c: MissileCorvetteConfig = SHIPPED
	assert_eq(c.perceive_radius, 720.0)
	assert_eq(c.lose_radius, 1500.0)
	assert_eq(c.notice_time, 0.35)
	assert_eq(c.idle_radius, 150.0)
	assert_eq(c.idle_speed, 0.5)
	var opened := c.preferred_range + c.range_drift + c.range_tolerance
	assert_eq(opened, 820.0)
	assert_gt(c.lose_radius, opened, "lose_radius %.0f vs the distance the cycle opens %.0f" % [c.lose_radius, opened])
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")
	assert_gte(c.perceive_radius, c.preferred_range, "it notices the player before it reaches its held range")


func test_open_space_cold_start_begins_idle_and_assault_starts_in_combat() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _cold(h, Vector2(321.0, -654.0), FAR_AWAY)
	_tick(corvette, DT)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	assert_eq(brain.phase, Phase.IDLE, "Open Space starts on patrol")
	assert_not_null(brain.anchor_idle)
	assert_eq(brain.patrol_anchor, Vector2(321.0, -654.0), "an unset anchor defaults to the spawn position")
	_retire_players()
	var a = HARNESS.assault()
	add_child_autofree(a.root)
	var corvette2 := _cold(a, Vector2(640.0, -100.0), Vector2(640.0, 560.0))
	_tick(corvette2, DT)
	var brain2 := corvette2.get_node("Brain") as MissileCorvetteBrain
	assert_eq(brain2.phase, Phase.APPROACH, "Assault always starts in combat")
	assert_null(brain2.anchor_idle, "no AnchorIdle is built in Assault")


func test_start_engaged_skips_the_idle() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _spawn(h, Vector2(100.0, 100.0))
	h.player.global_position = FAR_AWAY
	_tick(corvette, DT)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	assert_null(brain.anchor_idle)
	assert_false(_calm(brain.phase), "an engaged corvette never patrols")


func test_idle_stays_on_its_ring_and_never_fires() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var anchor := Vector2(500.0, -400.0)
	var corvette := _cold(h, anchor + Vector2(20.0, 0.0), FAR_AWAY, anchor)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var worst := 0.0
	for _i in int(20.0 / DT):
		_step(corvette, h.player)
		assert_eq(brain.phase, Phase.IDLE)
		# the first 4 s are the run-up from the anchor to the ring (it overshoots by ~40 px at 240 px/s²)
		if _i >= int(4.0 / DT):
			worst = maxf(worst, corvette.global_position.distance_to(anchor))
	assert_lte(worst, SHIPPED.idle_radius + 30.0, "worst %.1f px from the anchor once on the ring" % worst)
	assert_eq(brain.salvos_fired, 0)
	assert_eq(_rockets_in(h.root).size(), 0)


func test_perceiving_the_player_notices_for_a_beat_then_fights() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius - 100.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	var seen: Array[int] = []
	var noticing_ticks := 0
	for _i in int(1.0 / DT):
		_step(corvette, h.player)
		if brain.phase == Phase.NOTICING:
			noticing_ticks += 1
		if seen.is_empty() or seen[-1] != brain.phase:
			seen.append(brain.phase)
	assert_eq(seen[0], Phase.NOTICING, "NOTICING for a beat first")
	assert_false(_calm(seen[1]), "then the fight starts (phases %s)" % [seen])
	assert_almost_eq(noticing_ticks * DT, SHIPPED.notice_time, 2.0 * DT, "for notice_time")


func test_a_player_outside_perceive_radius_is_not_noticed() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius + SHIPPED.idle_radius + 100.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in int(3.0 / DT):
		_step(corvette, h.player)
		assert_eq(brain.phase, Phase.IDLE)


func test_beyond_lose_radius_it_goes_home_and_can_fight_again() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var anchor := Vector2.ZERO
	var corvette := _cold(h, anchor + Vector2(100.0, 0.0), Vector2(100.0, SHIPPED.preferred_range), anchor)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in int(3.0 / DT):
		_step(corvette, h.player)
		if not _calm(brain.phase):
			break
	assert_false(_calm(brain.phase), "it reached combat")
	corvette.global_position += Vector2(0.0, 700.0)  # well away from home, so there is a way back to walk
	h.player.global_position = FAR_AWAY
	var saw_returning := false
	var home := false
	for _i in int(60.0 / DT):
		_step(corvette, h.player)
		saw_returning = saw_returning or brain.phase == Phase.RETURNING
		if brain.phase == Phase.IDLE:
			home = true
			break
	assert_true(saw_returning, "it passes through RETURNING on the way home")
	assert_true(home, "and reaches IDLE")
	h.player.global_position = corvette.global_position + Vector2(SHIPPED.perceive_radius - 50.0, 0.0)
	for _i in int(1.0 / DT):
		_step(corvette, h.player)
	assert_false(_calm(brain.phase), "and fights again")


## Hysteresis: a player between perceive_radius and lose_radius never sends a fighting corvette home.
func test_a_player_between_the_radii_does_not_send_it_home() -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _cold(h, Vector2.ZERO, Vector2(0.0, SHIPPED.preferred_range), Vector2.ZERO)
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in int(3.0 / DT):
		_step(corvette, h.player)
	assert_false(_calm(brain.phase), "sanity: in combat")
	h.player.global_position = corvette.global_position + Vector2(SHIPPED.lose_radius - 50.0, 0.0)
	for _i in int(2.0 / DT):
		h.player.global_position = corvette.global_position + Vector2(SHIPPED.lose_radius - 50.0, 0.0)
		_step(corvette, h.player)
		assert_false(brain.phase == Phase.RETURNING, "inside lose_radius it keeps fighting")


## RETURNING never interrupts a TELEGRAPH or a SALVO: the player vanishes beyond lose_radius, straight ahead of the
## nose, and the whole salvo is delivered before the corvette turns for home.
func test_returning_never_interrupts_a_telegraph_or_a_salvo(started_in: int = use_parameters([Phase.TELEGRAPH, Phase.SALVO])) -> void:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	var corvette := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.preferred_range), Vector2(640.0, 0.0))
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	for _i in int(3.0 / DT):
		_step(corvette, h.player)
	assert_false(_calm(brain.phase), "sanity: in combat")
	brain.force_next_kind(EnemyRocket.Kind.DUMB)
	brain.enter_phase(Phase.TELEGRAPH)
	if started_in == Phase.SALVO:
		brain.enter_phase(Phase.SALVO)
	h.player.global_position = corvette.global_position + _nose(corvette) * (SHIPPED.lose_radius + 300.0)
	var seen: Array[int] = []
	for _i in int(6.0 / DT):
		_tick(corvette, DT)
		h.player.global_position = corvette.global_position + _nose(corvette) * (SHIPPED.lose_radius + 300.0)
		if seen.is_empty() or seen[-1] != brain.phase:
			seen.append(brain.phase)
		if _calm(brain.phase):
			break
	assert_true(seen.has(Phase.SALVO), "the salvo is delivered (phases %s)" % [seen])
	for i in seen.size() - 1:
		assert_false((seen[i] == Phase.TELEGRAPH or seen[i] == Phase.SALVO) and seen[i + 1] == Phase.RETURNING,
			"no cut-off attack (phases %s)" % [seen])
	assert_eq(seen[-1], Phase.RETURNING, "and then it goes home (phases %s)" % [seen])
	assert_eq(brain.salvos_fired, 1)
	assert_eq(_rockets_in(h.root).size(), brain.salvo_size(EnemyRocket.Kind.DUMB), "every rocket of the salvo left")
