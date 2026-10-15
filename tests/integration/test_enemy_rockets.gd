## Enemy rockets, DUMB and PURSUIT (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.6, §2.7, task t5; the task's own
## plan and review: docs/plans/cmv9szqlf001nqs2xlf0nad51/). Intent tests.
##
## Two kinds of row:
##   - HAND-TICKED (guidance, dodging, the straight rocket, the moving launcher, fizzle): the rocket's and its
##     `ProjectileLifetime`'s physics process are switched off and the test calls `_tick(DT)` then the lifetime's
##     `_physics_process(DT)` (tree order). Dual-mode rows build `enemy_ai_harness.gd` in the body; in Assault a long
##     row ends at the 1608 x 1608 projectile rect, and every assertion holds in both modes.
##   - REAL PHYSICS (shoot-down, friendly fire, plates, the asteroid, the real player scenes, the pool hand-over): only
##     where a real overlap is the point, on the 8x clock (`Engine.time_scale`, `physics_ticks_per_second` and
##     `max_physics_steps_per_frame` scaled together, restored in `after_each`; `_seconds()` counts game time).
##
## Rocket numbers are read from the rocket scenes' exports, never typed. The launcher's numbers come from
## `missile_corvette_config.tres` once it exists; until t7 they are the plan's constants below.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const LAUNCHER: GDScript = preload("res://tests/helpers/rocket_launcher_fixture.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const _MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0

# until t7: MissileCorvetteConfig max_speed / acceleration / salvo numbers (plan §2.9 table).
const _CORVETTE_MAX_SPEED := 210.0  # until t7
const _CORVETTE_ACCEL := 240.0  # until t7
const _CORVETTE_SALVO_COUNT := 3  # until t7
const _CORVETTE_WARHEAD_SALVO_COUNT := 2  # until t7
const _CORVETTE_SALVO_PERIOD_MIN := 4.0  # until t7

## The largest real player hurtbox radius: `player_fighter.tscn`'s 5 px circle at scale 2.7 (the ship's is 5 x 2.2).
const PLAYER_HURT_RADIUS := 13.5
const FIXTURE_HP := 1000

var _sandbox := SaveSandbox.new()
var _container: Node2D
var _blasts: Array[Vector2] = []

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func before_each() -> void:
	_blasts = []
	_container = null


func after_each() -> void:
	_restore_clock()


# ---------------------------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------------------------

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


## Waits `s` game seconds of physics (frames counted at the unscaled tick rate).
func _seconds(s: float) -> void:
	var ticks := _saved_ticks if _clock_scaled else Engine.physics_ticks_per_second
	await wait_physics_frames(maxi(1, roundi(s * ticks)))


func _harness(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	_watch_blasts(harness.root)
	return harness


## A real-physics container (Open Space: no arena camera).
func _real_container() -> Node2D:
	_scale_clock()
	_container = Node2D.new()
	add_child_autofree(_container)
	_watch_blasts(_container)
	return _container


func _watch_blasts(parent: Node) -> void:
	parent.child_entered_tree.connect(func(node: Node) -> void:
		if node is ContactBlast:
			_blasts.append((node as ContactBlast).global_position))


func _scene(kind: EnemyRocket.Kind) -> PackedScene:
	return EnemyRocketScenes.scene_for(kind)


## An unpooled rocket in `parent`, physics on (real-physics rows): `expired -> queue_free`, counted in `ends`.
func _live_rocket(parent: Node, kind: EnemyRocket.Kind, at: Vector2, dir: Vector2, ends: Array = []) -> EnemyRocket:
	var r: EnemyRocket = _scene(kind).instantiate()
	parent.add_child(r)
	r.global_position = at
	r.reset()
	r.expired.connect(func() -> void: ends.append(r))
	r.expired.connect(r.queue_free)
	r.launch(dir, at + dir * 400.0, null)
	return r


## An unpooled rocket in `parent` with its own and its lifetime's physics off: the test ticks it.
func _hand_rocket(parent: Node, kind: EnemyRocket.Kind, at: Vector2, dir: Vector2, aim: Vector2,
		launcher: Node = null) -> EnemyRocket:
	var r: EnemyRocket = _scene(kind).instantiate()
	parent.add_child(r)
	r.global_position = at
	r.reset()
	_freeze(r)
	r.launch(dir, aim, launcher)
	return r


func _freeze(r: EnemyRocket) -> void:
	r.set_physics_process(false)
	_lifetime(r).set_physics_process(false)


func _lifetime(r: EnemyRocket) -> ProjectileLifetime:
	return r.get_node("ProjectileLifetime") as ProjectileLifetime


func _tick(r: EnemyRocket) -> void:
	r._tick(DT)
	_lifetime(r)._physics_process(DT)


func _circle(radius: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	return shape


## `fixture_enemy.tscn` with 1000 HP and a shaped HurtBox (the `test_enemy_shield_hits.gd` pattern).
func _fixture_enemy(at: Vector2, radius: float = 16.0) -> BaseEnemy:
	var e: BaseEnemy = FIXTURE_ENEMY.instantiate()
	var health := e.get_node("Health") as Health
	health.max_health = FIXTURE_HP
	health.current_health = FIXTURE_HP
	e.get_node("HurtBox").add_child(_circle(radius))
	_container.add_child(e)
	e.global_position = at
	return e


## A bare enemy-layer area the rocket's HitBox detonates on (its parent answers no armour question).
func _target_point(parent: Node, at: Vector2, radius: float = 4.0) -> Area2D:
	var holder := Node2D.new()
	parent.add_child(holder)
	holder.global_position = at
	var area := Area2D.new()
	area.collision_layer = CollisionLayers.ENEMY_HURTBOX
	area.collision_mask = 0
	area.add_child(_circle(radius))
	holder.add_child(area)
	return area


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


# ---------------------------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------------------------

func test_scene_shape_and_layers_match_the_contract() -> void:
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT]:
		var r: EnemyRocket = _scene(kind).instantiate()
		add_child_autofree(r)
		assert_eq(r.kind, kind)
		assert_eq(r.collision_layer, 0, "the root is on no layer")
		assert_eq(r.collision_mask, 0)
		var hb := r.get_node("HitBox") as HitBox
		assert_eq(hb.collision_layer, CollisionLayers.PLAYER_ROCKETS, "impact HitBox on 32 only")
		assert_eq(hb.collision_mask, CollisionLayers.PLAYER_HURTBOX | CollisionLayers.ENEMY_HURTBOX, "mask 640")
		assert_eq(hb.damage_type, HitBox.DamageType.ROCKET)
		assert_eq(hb.damage, r.impact_damage)
		assert_false(hb.monitoring, "closed until armed")
		assert_false(hb.monitorable, "closed until armed")
		var hurt := r.get_node("HurtBox") as HurtBox
		assert_eq(hurt.collision_layer, CollisionLayers.ENEMY_HURTBOX, "shoot-down HurtBox on 512")
		assert_eq(hurt.collision_mask, CollisionLayers.PLAYER_ROCKETS | CollisionLayers.PLAYER_HITBOX, "mask 96")
		assert_eq(hurt.received_damage.get_connections().size(), 0, "received_damage is never connected")
		assert_not_null(r.get_node_or_null("RocketTrail") as RocketTrail, "a RocketTrail")
		assert_false(r.is_in_group(&"enemies"), "a rocket is never an enemy")
		assert_false("score_value" in r, "a rocket is never scored")


func test_config_inequalities_against_the_corvette() -> void:
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT]:
		var r: EnemyRocket = _scene(kind).instantiate()
		add_child_autofree(r)
		assert_gte(r.cruise_speed, 1.1 * _CORVETTE_MAX_SPEED, "kind %d: a launcher never catches its coasting rocket" % kind)
		assert_gt(r.launch_speed, _CORVETTE_ACCEL * r.boost_seconds, "kind %d: the launcher cannot out-accelerate the boost" % kind)
		if kind == EnemyRocket.Kind.PURSUIT:
			assert_gte(r.cruise_speed / r.turn_rate, 250.0, "PURSUIT turn radius")
	# Boundary: a 200 px/s cruise is caught by the corvette.
	assert_false(200.0 >= 1.1 * _CORVETTE_MAX_SPEED, "a synthetic 200 px/s cruise fails the first inequality")


class _CfgStub:
	var salvo_count: int
	var warhead_salvo_count: int
	var salvo_period_min: float


func test_pool_size_for_dumb_and_pursuit() -> void:
	var cfg := _CfgStub.new()
	cfg.salvo_count = _CORVETTE_SALVO_COUNT
	cfg.warhead_salvo_count = _CORVETTE_WARHEAD_SALVO_COUNT
	cfg.salvo_period_min = _CORVETTE_SALVO_PERIOD_MIN
	assert_eq(EnemyRocketScenes.pool_size_for(EnemyRocket.Kind.DUMB, cfg), 3, "3 x ceil(4.0 / 4.0)")
	assert_eq(EnemyRocketScenes.pool_size_for(EnemyRocket.Kind.PURSUIT, cfg), 6, "3 x ceil(6.0 / 4.0)")


func test_reset_restores_exports_and_launch_applies_late_exports() -> void:
	var c := _real_container()
	var launcher: CharacterBody2D = LAUNCHER.build(Vector2(300, 300))
	c.add_child(launcher)
	var pool: BulletPool = launcher.pools[EnemyRocket.Kind.PURSUIT]
	var r := pool.acquire(Vector2(300, 300)) as EnemyRocket
	var authored_time := r.max_time
	r.max_time = 1.5
	r.body_radius = 9.0
	r.impact_damage = 7
	r.launch(Vector2.UP, Vector2(300, 0), launcher)
	var lt := _lifetime(r)
	assert_eq(lt.max_time, 1.5, "a max_time set between acquire() and launch() reaches the lifetime")
	assert_eq(((r.get_node("HitBox/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius, 9.0)
	assert_eq(((r.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius, 11.0)
	assert_eq((r.get_node("HitBox") as HitBox).damage, 7)
	r.reset()
	assert_eq(r.max_time, authored_time, "reset() restores the scene's own export")
	assert_eq(lt.max_time, authored_time)
	assert_eq(r.impact_damage, 18)
	assert_false(r.is_armed())
	assert_false(r.is_guiding())


# ---------------------------------------------------------------------------------------------
# Guidance (hand-ticked, both modes)
# ---------------------------------------------------------------------------------------------

func test_pursuit_converges_on_the_intercept_with_a_turn_cap_then_freezes(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	var player: CharacterBody2D = h.player
	player.global_position = Vector2(1000, 200)
	player.velocity = Vector2(-140, 50)
	var start := Vector2(300, 950)
	var dir := (player.global_position - start).normalized().rotated(-0.5)
	var r := _hand_rocket(h.root, EnemyRocket.Kind.PURSUIT, start, dir, player.global_position)
	var window_end := r.boost_seconds + r.guidance_seconds
	var prev_heading := r.heading()
	var prev_error := INF
	var converged := false
	var frozen_heading := Vector2.ZERO
	var clock := 0.0
	var monotonic_ok := true
	var cap_ok := true
	var frozen_ok := true
	var frozen_ticks := 0
	while clock < 5.0:
		var was_guiding := r.is_guiding()
		r._tick(DT)
		clock += DT
		player.global_position += player.velocity * DT
		var turned := absf(prev_heading.angle_to(r.heading()))
		if turned > r.turn_rate * DT + 1e-4:
			cap_ok = false
		prev_heading = r.heading()
		if was_guiding and not converged:
			var err := absf(r.heading().angle_to(r.aim_point() - r.global_position))
			if err > prev_error + 1e-6:
				monotonic_ok = false
			prev_error = err
			if err < deg_to_rad(3.0):
				converged = true
		if clock >= window_end + DT:
			if frozen_heading == Vector2.ZERO:
				frozen_heading = r.heading()
			elif (r.heading() - frozen_heading).length() > 1e-6:
				frozen_ok = false
			frozen_ticks += 1
	assert_true(cap_ok, "%s: never more than turn_rate x delta per tick" % mode)
	assert_true(monotonic_ok, "%s: the error to the aim shrinks every guided tick until < 3 deg" % mode)
	assert_true(converged, "%s: the heading converges within 3 deg of the intercept" % mode)
	assert_gt(frozen_ticks, 30, "%s: ticks after the window were checked" % mode)
	assert_true(frozen_ok, "%s: after boost + guidance the heading is constant" % mode)


func test_with_no_player_the_pursuit_rocket_keeps_its_heading(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	var player: CharacterBody2D = h.player
	player.global_position = Vector2(640, 100)
	# The aim point lies to the side of the launch heading: steering at it (the stale-aim bug) would turn the rocket.
	var r := _hand_rocket(h.root, EnemyRocket.Kind.PURSUIT, Vector2(640, 900), Vector2.UP, Vector2(1000, 600))
	var start_heading := r.heading()
	var window_end := r.boost_seconds + r.guidance_seconds
	var clock := 0.0
	var worst := 0.0
	while clock < window_end + 0.2:
		if clock >= 0.2 and player.is_in_group(&"player"):
			player.remove_from_group(&"player")
		r._tick(DT)
		clock += DT
		worst = maxf(worst, (r.heading() - start_heading).length())
	assert_lt(worst, 1e-6, "%s: no player, no turn" % mode)


func test_dodging_the_pursuit_rocket(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	var player: CharacterBody2D = h.player
	var touch := 0.0
	# (a) A runner at 420 px/s from 300 px ahead is never caught before the rocket expires.
	player.global_position = Vector2(640, 700)
	player.velocity = Vector2(0, -420)
	var r := _hand_rocket(h.root, EnemyRocket.Kind.PURSUIT, Vector2(640, 1000), Vector2.UP, player.global_position)
	touch = r.body_radius + PLAYER_HURT_RADIUS
	var closest_a := _fly_against(r, player, func(_t: float, _d: float) -> void: pass)
	assert_gt(closest_a, touch, "%s: (a) a straight 420 px/s runner escapes (closest %.1f px)" % [mode, closest_a])

	# (b) Head-on at 220 px/s, then a perpendicular 700 px/s boost (0.35 s hold, 400 px/s^2 decay to 420 - the Open
	# Space ship's boost numbers) when the rocket is 150 px away.
	player.global_position = Vector2(640, 250)
	player.velocity = Vector2(0, 220)
	r = _hand_rocket(h.root, EnemyRocket.Kind.PURSUIT, Vector2(640, 1000), Vector2.UP, player.global_position)
	var boost := {"at": -1.0}
	var closest_b := _fly_against(r, player, func(t: float, d: float) -> void:
		if boost["at"] < 0.0 and d <= 150.0:
			boost["at"] = t
		if boost["at"] >= 0.0:
			var since: float = t - float(boost["at"])
			var sp := 700.0 if since < 0.35 else maxf(420.0, 700.0 - 400.0 * (since - 0.35))
			player.velocity = Vector2(sp, 0.0))
	assert_gt(float(boost["at"]), 0.0, "%s: (b) the boost happened" % mode)
	assert_gt(closest_b, touch, "%s: (b) a late perpendicular boost escapes (closest %.1f px)" % [mode, closest_b])

	# (c) A stationary target 600 px away is hit - the same law can catch.
	player.global_position = Vector2(640, 400)
	player.velocity = Vector2.ZERO
	r = _hand_rocket(h.root, EnemyRocket.Kind.PURSUIT, Vector2(640, 1000), Vector2.UP.rotated(0.4), player.global_position)
	var closest_c := _fly_against(r, player, func(_t: float, _d: float) -> void: pass)
	assert_lt(closest_c, touch, "%s: (c) a stationary target is hit (closest %.1f px)" % [mode, closest_c])


## Flies `r` (hand-ticked, lifetime included) against the moving `player` until it expires or 8 s pass; `script`
## updates the player's velocity each tick from (time, distance). Returns the closest approach.
func _fly_against(r: EnemyRocket, player: CharacterBody2D, script: Callable) -> float:
	var done := {"v": false}
	r.expired.connect(func() -> void: done["v"] = true)
	var closest := INF
	var t := 0.0
	while not done["v"] and t < 8.0:
		var d := r.global_position.distance_to(player.global_position)
		script.call(t, d)
		_tick(r)
		player.global_position += player.velocity * DT
		t += DT
		closest = minf(closest, r.global_position.distance_to(player.global_position))
	assert_true(done["v"], "the rocket expired within 8 s")
	return closest


func test_the_dumb_rocket_flies_straight_nose_up_and_reaches_cruise(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	var player: CharacterBody2D = h.player
	player.global_position = Vector2(300, 300)
	player.velocity = Vector2(200, 0)
	var dir := Vector2(0.3, -1.0).normalized()
	var r := _hand_rocket(h.root, EnemyRocket.Kind.DUMB, Vector2(500, 1000), dir, Vector2(800, 0))
	var expired := {"v": false}
	r.expired.connect(func() -> void: expired["v"] = true)
	var start_heading := r.heading()
	var worst_heading := 0.0
	var worst_rotation := 0.0
	var ticks_to_cruise := -1
	var ticks := 0
	while not expired["v"] and ticks < 600:
		_tick(r)
		player.global_position += player.velocity * DT
		ticks += 1
		worst_heading = maxf(worst_heading, (r.heading() - start_heading).length())
		worst_rotation = maxf(worst_rotation, absf(angle_difference(r.rotation, r.heading().angle() + PI / 2.0)))
		if ticks_to_cruise < 0 and r.speed() >= r.cruise_speed - 1e-3:
			ticks_to_cruise = ticks
	assert_true(expired["v"], "%s: the rocket expired" % mode)
	assert_lt(worst_heading, 1e-6, "%s: DUMB keeps its launch heading" % mode)
	assert_lt(worst_rotation, 1e-5, "%s: rotation == heading.angle() + PI / 2 every tick" % mode)
	var bound := r.boost_seconds + (r.cruise_speed - r.launch_speed) / r.accel + 2.0 * DT
	assert_gt(ticks_to_cruise, 0, "%s: reached cruise" % mode)
	assert_lte(ticks_to_cruise * DT, bound + 1e-6, "%s: cruise within boost + ramp + 2 ticks" % mode)


# ---------------------------------------------------------------------------------------------
# Moving launcher: inherited speed and clearance arming (hand-ticked, both modes)
# ---------------------------------------------------------------------------------------------

func test_a_moving_launcher_never_overruns_its_rocket(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	h.player.global_position = Vector2(640, -300)
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT]:
		var launcher: CharacterBody2D = LAUNCHER.build(Vector2(640, 1000))
		h.root.add_child(launcher)
		launcher.velocity = Vector2(0, -_CORVETTE_MAX_SPEED)
		var r: EnemyRocket = launcher.fire(kind, Vector2.UP, Vector2(640, -300))
		_freeze(r)
		assert_almost_eq(r.speed(), r.launch_speed + _CORVETTE_MAX_SPEED, 1e-4,
				"%s kind %d: the rocket starts at launch_speed + the launcher's 210 px/s" % [mode, kind])
		var arm_at := LAUNCHER.CLEAR_RADIUS + r.body_radius + r.arm_clearance
		var prev := r.global_position.distance_to(launcher.global_position)
		var grows := true
		var arming_ok := true
		var armed_seen := false
		for i in 60:
			launcher.global_position += launcher.velocity * DT
			_tick(r)
			var d := r.global_position.distance_to(launcher.global_position)
			if d <= prev:
				grows = false
			prev = d
			if r.is_armed() != (d >= arm_at):
				arming_ok = false
			armed_seen = armed_seen or r.is_armed()
		assert_true(grows, "%s kind %d: the launcher-rocket distance grows every tick" % [mode, kind])
		assert_true(armed_seen, "%s kind %d: armed within 1 s" % [mode, kind])
		assert_true(arming_ok, "%s kind %d: armed exactly from the first tick at >= %.0f px" % [mode, kind, arm_at])

		# Control: the same launcher reporting no velocity overtakes its rocket - the row can fail.
		var control: CharacterBody2D = LAUNCHER.build(Vector2(300, 1000))
		h.root.add_child(control)
		control.velocity = Vector2(0, -_CORVETTE_MAX_SPEED)
		control.report_velocity = false
		var rc: EnemyRocket = control.fire(kind, Vector2.UP, Vector2(300, -300))
		_freeze(rc)
		var d0 := rc.global_position.distance_to(control.global_position)
		control.global_position += control.velocity * DT
		_tick(rc)
		assert_lt(rc.global_position.distance_to(control.global_position), d0,
				"%s kind %d: with no inherited speed the launcher closes on its rocket" % [mode, kind])


# ---------------------------------------------------------------------------------------------
# Fizzle (hand-ticked, both modes)
# ---------------------------------------------------------------------------------------------

func test_lifetime_expiry_is_a_fizzle_with_no_blast(mode: String = use_parameters(_MODES)) -> void:
	var h = _harness(mode)
	h.player.global_position = Vector2(-2000, -2000)
	h.player.remove_from_group(&"player")
	var r := _hand_rocket(h.root, EnemyRocket.Kind.DUMB, Vector2(640, 360), Vector2.RIGHT, Vector2(1640, 360))
	var count := {"n": 0}
	r.expired.connect(func() -> void: count["n"] += 1)
	var ticks := 0
	while count["n"] == 0 and ticks < 600:
		_tick(r)
		ticks += 1
	for i in 10:
		_tick(r)
	assert_eq(count["n"], 1, "%s: expired exactly once" % mode)
	if mode == "assault":
		assert_gt(r.global_position.x, 1444.0, "assault: it ended at the projectile rect's right edge")
	await wait_physics_frames(2)
	assert_eq(_blasts.size(), 0, "%s: a fizzle spawns no ContactBlast" % mode)

	# Positive control: an armed rocket's impact handler, given an enemy-layer area, does blast - counted the same way.
	var r2 := _hand_rocket(h.root, EnemyRocket.Kind.DUMB, Vector2(640, 600), Vector2.RIGHT, Vector2(1000, 600))
	for i in 10:
		_tick(r2)
	assert_true(r2.is_armed(), "%s: the control rocket armed" % mode)
	r2._on_hit_box_area_entered(_target_point(h.root, r2.global_position + Vector2(8, 0)))
	await wait_physics_frames(2)
	assert_eq(_blasts.size(), 1, "%s: a detonation is counted" % mode)


# ---------------------------------------------------------------------------------------------
# Shoot-down (real physics, Open Space)
# ---------------------------------------------------------------------------------------------

func test_a_player_bullet_and_the_rocket_destroy_each_other_and_contact_boxes_do_not() -> void:
	var c := _real_container()
	var ends: Array = []
	var r := _live_rocket(c, EnemyRocket.Kind.DUMB, Vector2(300, 300), Vector2.RIGHT, ends)
	var bullet: Bullet = BULLET_SCENE.instantiate()
	c.add_child(bullet)
	bullet.global_position = Vector2(600, 300)
	bullet.rotation = -PI / 2.0  # forward = UP.rotated(rotation) = LEFT
	bullet.expired.connect(bullet.queue_free)

	# A CONTACT HitBox on 64 (the ally fighter's ram box) in a second rocket's path does not defuse it.
	var ends2: Array = []
	var r2 := _live_rocket(c, EnemyRocket.Kind.DUMB, Vector2(300, 500), Vector2.RIGHT, ends2)
	var contact := HitBox.new()
	contact.collision_layer = CollisionLayers.PLAYER_HITBOX
	contact.collision_mask = 0
	contact.damage_type = HitBox.DamageType.CONTACT
	contact.add_child(_circle(12.0))
	c.add_child(contact)
	contact.global_position = Vector2(380, 500)

	await _seconds(0.6)
	assert_eq(ends.size(), 1, "the rocket expired exactly once")
	assert_false(is_instance_valid(bullet), "the bullet was consumed")
	assert_eq(_blasts.size(), 0, "a shoot-down never blasts")
	assert_eq(ends2.size(), 0, "a CONTACT HitBox never defuses a rocket")
	assert_true(is_instance_valid(r2) and r2.global_position.x > 420.0, "the second rocket flew on past it")


func test_a_homing_missile_and_the_rocket_destroy_each_other() -> void:
	var c := _real_container()
	var shielded := _fixture_enemy(Vector2(800, 300))
	var clear := _fixture_enemy(Vector2(800, 550))
	var ends: Array = []
	_live_rocket(c, EnemyRocket.Kind.DUMB, Vector2(560, 300), Vector2.LEFT, ends)
	var missiles: Array = []
	for pair in [[Vector2(250, 300), shielded], [Vector2(250, 550), clear]]:
		var m: Area2D = HOMING_SCENE.instantiate()
		m.locked_target = pair[1]
		c.add_child(m)
		m.global_position = pair[0]
		missiles.append(m)
	await _seconds(1.6)
	assert_eq(ends.size(), 1, "the rocket expired exactly once")
	assert_false(is_instance_valid(missiles[0]), "the missile that met the rocket was freed")
	assert_eq(_blasts.size(), 0, "no ContactBlast")
	assert_eq(_hp(shielded), FIXTURE_HP, "the enemy behind the rocket is untouched")
	assert_eq(_hp(clear), FIXTURE_HP - 100, "control: the same missile on a clear path hits its enemy for 100")


# ---------------------------------------------------------------------------------------------
# Friendly fire (real physics, Open Space)
# ---------------------------------------------------------------------------------------------

func test_the_impact_hurts_enemies_never_the_launcher_and_never_a_sibling() -> void:
	var c := _real_container()
	var target := _fixture_enemy(Vector2(520, 300))
	var launcher: CharacterBody2D = LAUNCHER.build(Vector2(200, 300))
	c.add_child(launcher)
	var r: EnemyRocket = launcher.fire(EnemyRocket.Kind.DUMB, Vector2.RIGHT, Vector2(520, 300))
	var impact := r.impact_damage
	var ends: Array = []
	r.expired.connect(func() -> void: ends.append(1))

	var twins: CharacterBody2D = LAUNCHER.build(Vector2(200, 650))
	c.add_child(twins)
	var a: EnemyRocket = twins.fire(EnemyRocket.Kind.DUMB, Vector2.RIGHT, Vector2(900, 650))
	twins.muzzle_offset += 2.0
	var b: EnemyRocket = twins.fire(EnemyRocket.Kind.DUMB, Vector2.RIGHT, Vector2(900, 650))
	var twin_log: Array = []
	a.expired.connect(func() -> void: twin_log.append(a))
	b.expired.connect(func() -> void: twin_log.append(b))

	await _seconds(1.2)
	assert_eq(ends.size(), 1, "the rocket detonated on the enemy")
	assert_eq(_hp(target), FIXTURE_HP - impact, "the enemy took exactly impact_damage; the blast added nothing")
	assert_eq(_blasts.size(), 1, "one blast")
	assert_eq(launcher.health.current_health, LAUNCHER.MAX_HEALTH, "the launcher is never hit by its own rocket")
	assert_eq(twins.health.current_health, LAUNCHER.MAX_HEALTH)
	assert_eq(twin_log.size(), 0, "two rockets 2 px apart ignore each other for 1.2 s")
	assert_true(a.is_armed() and b.is_armed(), "both armed while flying together")


func test_rockets_wear_down_ram_plates_through_the_armoured_hull_and_hurt_asteroids() -> void:
	var c := _real_container()
	var ram: RamCorvette = RAM_SCENE.instantiate()
	c.add_child(ram)
	ram.global_position = Vector2(600, 400)
	ram.rotation = 0.0
	ram.suspend_ai()
	ram.set_physics_process(false)
	var broken: Array[StringName] = []
	ram.plate_broken.connect(func(plate_name: StringName) -> void: broken.append(plate_name))
	var front := ram.get_node("Plates/PlateFront") as ArmorPlate
	var left := ram.get_node("Plates/PlateLeft") as ArmorPlate
	var hull_hp := ram.health.current_health
	var front_hp := front.health.current_health
	left.health.current_health = 10
	var asteroid: Node2D = ASTEROID_SCENE.instantiate()
	c.add_child(asteroid)
	asteroid.global_position = Vector2(250, 750)
	asteroid.set_physics_process(false)
	var asteroid_hp := _hp(asteroid)
	await _seconds(0.1)

	var logs: Array = []
	# From behind the hull along x = 0: it crosses the armoured hull (r 34) for several ticks before PlateFront (0, 36).
	var r1 := _live_rocket(c, EnemyRocket.Kind.DUMB, ram.global_position + Vector2(0, -200), Vector2.DOWN, logs)
	var impact := r1.impact_damage
	_live_rocket(c, EnemyRocket.Kind.DUMB, left.global_position + Vector2(0, -200), Vector2.DOWN, logs)
	_live_rocket(c, EnemyRocket.Kind.DUMB, asteroid.global_position + Vector2(-250, 0), Vector2.RIGHT, logs)
	await _seconds(1.2)
	assert_eq(front_hp, 50, "the shipped plate has 50 HP")
	assert_eq(front.health.current_health, front_hp - impact, "PlateFront 50 -> 34")
	assert_false(broken.has(&"PlateFront"), "one rocket does not break a plate")
	assert_eq(broken, [&"PlateLeft"] as Array[StringName], "a plate at <= impact_damage HP breaks once")
	assert_eq(ram.health.current_health, hull_hp, "the armoured hull takes nothing")
	assert_eq(logs.size(), 3, "every rocket was consumed")
	assert_eq(_hp(asteroid), asteroid_hp - impact, "the asteroid takes impact_damage")


# ---------------------------------------------------------------------------------------------
# The player takes the blast only (real physics, real player scenes, both modes)
# ---------------------------------------------------------------------------------------------

func test_the_player_takes_only_the_blast(mode: String = use_parameters(_MODES)) -> void:
	_scale_clock()
	var h = _harness(mode)
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var p := Vector2(640, 360)
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	h.root.add_child(player)
	player.global_position = p
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	var hurt := player.get_node("HurtBox") as HurtBox
	var hurt_centre := (hurt.get_child(0) as Node2D).global_position
	var received: Array[int] = []
	hurt.received_damage.connect(func(damage: int) -> void: received.append(damage))
	var hp0 := player.health_component.current_health
	await _seconds(0.1)

	# Direct hit, with an impact_damage distinct from blast_damage, so an impact that reached the player would show.
	var r := _scene(EnemyRocket.Kind.DUMB).instantiate() as EnemyRocket
	h.root.add_child(r)
	r.global_position = p + Vector2(-200, 0)
	r.reset()
	r.expired.connect(r.queue_free)
	var blast := r.blast_damage
	var blast_r := r.blast_radius
	var body := r.body_radius
	r.impact_damage = 3
	r.launch(Vector2.RIGHT, p, null)
	await _seconds(0.8)
	assert_eq(received, [blast] as Array[int], "%s: a direct hit is the blast alone" % mode)
	assert_eq(player.health_component.current_health, hp0 - blast, "%s: HP drops by blast_damage" % mode)

	# A detonation on a fixture ~30 px from the player: still exactly the blast.
	_blasts.clear()
	_target_point(h.root, p + Vector2(10, -30))
	_live_rocket(h.root, EnemyRocket.Kind.DUMB, p + Vector2(-200, -30), Vector2.RIGHT)
	await _seconds(0.8)
	assert_eq(_blasts.size(), 1, "%s: the near rocket blasted" % mode)
	var near := _blasts[0].distance_to(hurt_centre) if _blasts.size() > 0 else -1.0
	assert_between(near, 24.0, 30.0 + body, "%s: the near blast was ~30 px from the player (%.1f)" % [mode, near])
	assert_eq(received, [blast, blast] as Array[int], "%s: a near miss costs blast_damage" % mode)

	# blast_radius + 20 away: nothing.
	_blasts.clear()
	var far_y := blast_r + 20.0
	_target_point(h.root, p + Vector2(10, -far_y))
	_live_rocket(h.root, EnemyRocket.Kind.DUMB, p + Vector2(-200, -far_y), Vector2.RIGHT)
	await _seconds(0.8)
	assert_eq(_blasts.size(), 1, "%s: the far rocket blasted" % mode)
	var far := _blasts[0].distance_to(hurt_centre) if _blasts.size() > 0 else -1.0
	assert_gte(far, blast_r + 20.0 - 1.0, "%s: the far blast was blast_radius + 20 away (%.1f)" % [mode, far])
	assert_eq(received.size(), 2, "%s: a blast at blast_radius + 20 costs nothing" % mode)
	assert_eq(player.health_component.current_health, hp0 - 2 * blast)

	# With one shield charge, a direct hit spends exactly that charge.
	player.shield_component.add_temporary()
	var hp_before := player.health_component.current_health
	var r4 := _live_rocket(h.root, EnemyRocket.Kind.DUMB, p + Vector2(-200, 0), Vector2.RIGHT)
	r4.impact_damage = 3
	r4.launch(Vector2.RIGHT, p, null)
	await _seconds(0.8)
	assert_eq(received, [blast, blast, blast] as Array[int], "%s: the shielded hit is the blast alone" % mode)
	assert_eq(player.shield_component.temporary_count, 0, "%s: one charge spent" % mode)
	assert_eq(player.shield_component.permanent_active, 0)
	assert_eq(player.health_component.current_health, hp_before, "%s: the charge absorbed it" % mode)


# ---------------------------------------------------------------------------------------------
# Ownership: persist after the launcher dies (real physics, Open Space)
# ---------------------------------------------------------------------------------------------

func test_rockets_outlive_their_launcher_and_free_themselves() -> void:
	var c := _real_container()
	var launcher: CharacterBody2D = LAUNCHER.build(Vector2(200, 300))
	c.add_child(launcher)
	var a: EnemyRocket = launcher.fire(EnemyRocket.Kind.DUMB, Vector2.RIGHT, Vector2(1200, 300))
	await _seconds(0.4)
	assert_true(a.is_armed(), "the first rocket armed in flight")
	var b: EnemyRocket = launcher.fire(EnemyRocket.Kind.DUMB, Vector2.DOWN, Vector2(200, 1200))
	assert_false(b.is_armed(), "the second rocket is still at the muzzle, unarmed")
	launcher.queue_free()
	await _seconds(2.0 / 60.0)
	assert_false(is_instance_valid(launcher), "the launcher is gone")
	assert_true(is_instance_valid(a) and is_instance_valid(b), "its rockets fly on")
	assert_true(b.is_armed(), "a freed launcher arms its unarmed rocket on the next tick")
	assert_eq(a.get_parent(), c, "the rockets live in the container")
	var bx := b.global_position
	await _seconds(0.2)
	assert_true(is_instance_valid(b) and b.global_position.distance_to(bx) > 10.0, "still flying")
	await _seconds(4.2)
	assert_false(is_instance_valid(a), "the first rocket freed itself on expiry")
	assert_false(is_instance_valid(b), "the second rocket freed itself on expiry")
	assert_eq(_blasts.size(), 0, "expiry is a fizzle")
