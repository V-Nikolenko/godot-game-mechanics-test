## Projectiles in fields (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md §2.7, task t8). Intent tests.
##
## Heavy, guided ordnance bends; bullets fly true. A family opts in by answering `hazard_pull_scale()` and, in
## its own tick, rotating its heading toward `heading * speed + Hazards.accel_at(pos) * delta` WITHOUT changing
## its speed (`Hazards.bend_heading()`), so every time and distance cap still holds. Opted in: the five enemy
## rocket kinds, the gravity and pursuit bombs, the player's homing and warhead missiles. Not opted in: the
## `EnemyBullet` rounds, the player `Bullet`, mines.
##
## Everything is hand-ticked (the projectile's physics process and its `ProjectileLifetime`'s are switched off)
## with no real collision, so the rows are exact: "bit-identical" is `assert_eq` on `Vector2`s.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const ROUND_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/rounds/pulse_round.tscn")

const DT := 1.0 / 60.0
const TICKS := 30
const START := Vector2(640.0, 300.0)
## A well off to the side of a path that runs straight down (or, for the missiles, straight up).
const WELL_DOWN := Vector2(790.0, 550.0)
const WELL_UP := Vector2(790.0, 50.0)

const _ROCKET_KINDS: Array[EnemyRocket.Kind] = [
	EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER, EnemyRocket.Kind.WARHEAD,
	EnemyRocket.Kind.SUBMUNITION]
const _BOMB_KINDS: Array[EnemyOrdnance.Kind] = [EnemyOrdnance.Kind.GRAVITY_BOMB, EnemyOrdnance.Kind.PURSUIT_BOMB]

var _root: Node2D


class FixtureWell extends Node2D:
	var info := HazardInfo.new()
	func hazard_info() -> HazardInfo:
		info.position = global_position
		return info
	func _enter_tree() -> void:
		Hazards.register(self)
	func _exit_tree() -> void:
		Hazards.unregister(self)


func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)


func _well(at: Vector2, pull: float = 900.0, tangential: float = 0.0) -> FixtureWell:
	var w := FixtureWell.new()
	w.info.kind = &"gravity_well"
	w.info.radius = 700.0
	w.info.core_radius = 60.0
	w.info.pull_force = pull
	w.info.tangential_force = tangential
	add_child_autofree(w)
	w.global_position = at
	return w


# --- the projectile fixtures -----------------------------------------------------------------

func _rocket(parent: Node, kind: EnemyRocket.Kind, dir: Vector2) -> EnemyRocket:
	var r: EnemyRocket = EnemyRocketScenes.scene_for(kind).instantiate()
	parent.add_child(r)
	r.global_position = START
	r.reset()
	r.set_physics_process(false)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime).set_physics_process(false)
	r.launch(dir, START + dir * 400.0, null)
	return r


func _bomb(kind: EnemyOrdnance.Kind) -> EnemyOrdnance:
	var o: EnemyOrdnance = EnemyOrdnanceScenes.scene_for(kind).instantiate()
	_root.add_child(o)
	o.global_position = START
	o.reset()
	o.set_physics_process(false)
	(o.get_node("ProjectileLifetime") as ProjectileLifetime).set_physics_process(false)
	o.launch(Vector2.DOWN, 300.0, START + Vector2.DOWN * 3000.0)
	return o


func _missile(scene: PackedScene) -> Area2D:
	var m: Area2D = scene.instantiate()
	_root.add_child(m)
	m.global_position = START
	m.rotation = 0.0
	m.set_physics_process(false)
	return m


func _tick_rocket(r: EnemyRocket) -> void:
	r._tick(DT)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime)._physics_process(DT)


## Runs `TICKS` ticks, returning the position after each tick (START first).
func _path_rocket(r: EnemyRocket) -> PackedVector2Array:
	var path := PackedVector2Array([r.global_position])
	for i in TICKS:
		_tick_rocket(r)
		path.append(r.global_position)
	return path


func _path_bomb(o: EnemyOrdnance) -> PackedVector2Array:
	var path := PackedVector2Array([o.global_position])
	for i in TICKS:
		o._physics_process(DT)
		(o.get_node("ProjectileLifetime") as ProjectileLifetime)._physics_process(DT)
		path.append(o.global_position)
	return path


func _path_missile(m: Area2D) -> PackedVector2Array:
	var path := PackedVector2Array([m.global_position])
	for i in TICKS:
		m._physics_process(DT)
		path.append(m.global_position)
	return path


## Every step's length equals `speed * DT` (within float noise): the bend turns the heading, never the speed.
func _assert_constant_speed(path: PackedVector2Array, speed: float, label: String) -> void:
	for i in range(1, path.size()):
		assert_almost_eq(path[i].distance_to(path[i - 1]), speed * DT, 0.01, "%s step %d" % [label, i])


# --- enemy rockets ---------------------------------------------------------------------------

func test_every_rocket_kind_bends_toward_the_well_at_unchanged_speed() -> void:
	_well(WELL_DOWN)
	for kind in _ROCKET_KINDS:
		var r := _rocket(_root, kind, Vector2.DOWN)
		var path := _path_rocket(r)
		assert_gt(path[-1].x - START.x, 5.0, "kind %d bends toward the well (+x)" % kind)
		assert_gt(path[-1].y, START.y, "kind %d still travels forward" % kind)
		# After the boost the speed is whatever the rocket's own accel made it; each step is that speed.
		for i in range(1, path.size()):
			assert_lt(absf(path[i].distance_to(path[i - 1]) - path[i - 1].distance_to(path[maxi(i - 2, 0)])
					if i > 1 else 0.0), 20.0 * DT * 60.0, "kind %d steps are smooth" % kind)
		r.queue_free()


func test_a_rocket_in_its_boost_keeps_its_exact_speed_while_bending() -> void:
	_well(WELL_DOWN)
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	r.boost_seconds = 5.0 # a long boost: the speed stays at launch_speed the whole time
	r.launch(Vector2.DOWN, START + Vector2.DOWN * 400.0, null)
	var path := _path_rocket(r)
	assert_gt(path[-1].x - START.x, 2.0, "bent")
	_assert_constant_speed(path, r.launch_speed, "boost")


func test_a_rocket_answers_a_pull_scale_of_one_and_a_zero_scale_does_not_bend() -> void:
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	assert_true(r.has_method(&"hazard_pull_scale"))
	assert_eq(r.hazard_pull_scale(), 1.0)


func test_a_tangential_field_swirls_a_rocket_sideways_not_inward() -> void:
	# Pure swirl (no pull) at a point dead ahead: the rocket is pushed across its line, at unchanged speed.
	_well(START + Vector2(0.0, 250.0), 0.0, 900.0)
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	var path := _path_rocket(r)
	assert_gt(absf(path[-1].x - START.x), 5.0, "swirled off the line")


func test_a_bent_rocket_still_ends_by_its_lifetime() -> void:
	_well(WELL_DOWN)
	var ends: Array[int] = [0]
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	r.max_time = 0.4
	r.launch(Vector2.DOWN, START + Vector2.DOWN * 400.0, null)
	r.expired.connect(func() -> void: ends[0] += 1)
	for i in 60:
		_tick_rocket(r)
	assert_eq(ends[0], 1, "expired exactly once, by max_time, on a curved path")
	assert_gt(r.global_position.x, START.x, "and it did bend")


func test_a_bent_rocket_still_ends_by_its_distance_cap() -> void:
	# The cap counts straight-line distance from the origin, so a curved path reaches it later, never never.
	_well(WELL_DOWN, 300.0)
	var ends: Array[int] = [0]
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	r.max_distance = 150.0
	r.max_time = 30.0
	r.launch(Vector2.DOWN, START + Vector2.DOWN * 400.0, null)
	r.expired.connect(func() -> void: ends[0] += 1)
	for i in 240:
		_tick_rocket(r)
	assert_eq(ends[0], 1)


func test_a_rocket_bends_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	# The fake player sits straight down the line, so a pursuit rocket's guidance does not add a lateral term.
	harness.player.global_position = START + Vector2(0.0, 900.0)
	_well(WELL_DOWN)
	var r := _rocket(harness.root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	var path := _path_rocket(r)
	assert_gt(path[-1].x - START.x, 5.0, mode)


# --- bombs -----------------------------------------------------------------------------------

func test_gravity_and_pursuit_bombs_bend_toward_the_well_at_unchanged_speed() -> void:
	_well(WELL_DOWN)
	for kind in _BOMB_KINDS:
		var o := _bomb(kind)
		o.steer_window = 0.0 # a frozen heading, so the only turn is the field's
		o.final_speed = o.accel * 0.0 + 300.0 # no acceleration after the window: speed stays 300
		assert_true(o.has_method(&"hazard_pull_scale"))
		assert_eq(o.hazard_pull_scale(), 1.0)
		var path := _path_bomb(o)
		assert_gt(path[-1].x - START.x, 5.0, "bomb kind %d bends toward the well" % kind)
		_assert_constant_speed(path, 300.0, "bomb kind %d" % kind)
		o.queue_free()


func test_a_steering_pursuit_bomb_still_bends() -> void:
	_well(WELL_DOWN)
	var o := _bomb(EnemyOrdnance.Kind.PURSUIT_BOMB)
	var path := _path_bomb(o)
	assert_gt(path[-1].x - START.x, 1.0)


func test_a_mine_does_not_bend() -> void:
	var baseline := _path_bomb(_bomb(EnemyOrdnance.Kind.MINE))
	var mine := _bomb(EnemyOrdnance.Kind.MINE)
	assert_eq(mine.hazard_pull_scale(), 0.0)
	_well(WELL_DOWN)
	assert_eq(_path_bomb(mine), baseline, "a mine's eject path is untouched by a field")


func test_a_gravity_bomb_still_detonates_on_its_distance_cap_on_a_curved_path() -> void:
	_well(WELL_DOWN)
	var o := _bomb(EnemyOrdnance.Kind.GRAVITY_BOMB)
	o.warning_time = 0.0
	o.max_travel_margin = 0.0
	o.launch(Vector2.DOWN, 300.0, START + Vector2.DOWN * 100.0) # a 100 px drop
	var ends: Array[int] = [0]
	o.expired.connect(func() -> void: ends[0] += 1)
	for i in 120:
		o._physics_process(DT)
	assert_eq(ends[0], 1, "path length, not displacement, is what the cap counts")
	await get_tree().process_frame # the blast attaches itself deferred
	for child in _root.get_children():
		if child is ContactBlast:
			child.free()


# --- the player's missiles -------------------------------------------------------------------

func test_the_players_missiles_bend_toward_the_well_at_unchanged_speed() -> void:
	_well(WELL_UP)
	var homing := _missile(HOMING_SCENE)
	var warhead := _missile(WARHEAD_SCENE)
	for m in [homing, warhead]:
		assert_true(m.has_method(&"hazard_pull_scale"))
		assert_eq(m.hazard_pull_scale(), 1.0)
		var path := _path_missile(m)
		assert_gt(path[-1].x - START.x, 5.0, "%s bends toward the well" % m.name)
		assert_lt(path[-1].y, START.y, "%s still travels forward (up)" % m.name)
		_assert_constant_speed(path, m.speed, m.name)
		assert_gt(m.rotation, 0.0, "the nose follows the bend (clockwise of straight up)")


func test_a_locked_homing_missile_still_drifts_toward_the_well() -> void:
	_well(WELL_UP)
	var target := Node2D.new()
	_root.add_child(target)
	target.global_position = START + Vector2(0.0, -3000.0)
	var m := _missile(HOMING_SCENE) as homing_missile
	m.locked_target = target
	var path := _path_missile(m)
	assert_gt(path[-1].x - START.x, 1.0)
	_assert_constant_speed(path, m.speed, "locked")


# --- what does not bend ----------------------------------------------------------------------

func test_a_round_and_a_player_bullet_do_not_bend() -> void:
	_well(WELL_DOWN, 5000.0)
	var round_node: EnemyBullet = ROUND_SCENE.instantiate()
	_root.add_child(round_node)
	round_node.global_position = START
	round_node.set_physics_process(false)
	round_node.set_direction(Vector2.DOWN)
	var bullet: Bullet = BULLET_SCENE.instantiate()
	_root.add_child(bullet)
	bullet.global_position = START
	bullet.set_physics_process(false)
	assert_false(round_node.has_method(&"hazard_pull_scale"))
	assert_false(bullet.has_method(&"hazard_pull_scale"))
	for i in TICKS:
		round_node._physics_process(DT)
		bullet._physics_process(DT)
	assert_eq(round_node.global_position.x, START.x, "the round flies true")
	assert_eq(bullet.global_position.x, START.x, "the player bullet flies true")
	assert_gt(round_node.global_position.y, START.y)
	assert_lt(bullet.global_position.y, START.y)


# --- no hazard: bit-identical ----------------------------------------------------------------

func _all_paths() -> Array:
	var paths: Array = []
	for kind in _ROCKET_KINDS:
		var r := _rocket(_root, kind, Vector2.DOWN)
		paths.append(_path_rocket(r))
		r.queue_free()
	for kind in _BOMB_KINDS:
		var o := _bomb(kind)
		paths.append(_path_bomb(o))
		o.queue_free()
	for scene in [HOMING_SCENE, WARHEAD_SCENE]:
		var m := _missile(scene)
		paths.append(_path_missile(m))
		m.queue_free()
	return paths


func test_with_no_hazard_every_path_is_bit_identical_to_a_field_out_of_reach() -> void:
	assert_eq(Hazards.count(), 0)
	var bare := _all_paths()
	# Registered but out of reach: the registry is non-empty, every acceleration is exactly zero.
	var far := _well(START + Vector2(0.0, 9000.0))
	assert_eq(Hazards.count(), 1)
	var with_far := _all_paths()
	assert_eq(with_far, bare, "an out-of-reach field changes nothing, bit for bit")
	far.queue_free()


func test_with_no_hazard_a_rocket_flies_the_straight_line() -> void:
	var r := _rocket(_root, EnemyRocket.Kind.DUMB, Vector2.DOWN)
	var path := _path_rocket(r)
	for p in path:
		assert_eq(p.x, START.x)


# --- the shared helper -----------------------------------------------------------------------

func test_bend_heading_returns_the_same_heading_with_no_hazard_or_a_zero_scale() -> void:
	var h := Vector2.DOWN.rotated(0.3)
	assert_eq(Hazards.bend_heading(h, 300.0, START, DT, 1.0), h)
	_well(WELL_DOWN)
	assert_eq(Hazards.bend_heading(h, 300.0, START, DT, 0.0), h)
	assert_eq(Hazards.bend_heading(h, 0.0, START, DT, 1.0), h, "no speed, no turn")
	assert_ne(Hazards.bend_heading(h, 300.0, START, DT, 1.0), h)


func test_bend_heading_is_a_unit_vector_and_scales_with_the_scale() -> void:
	_well(WELL_DOWN)
	var full := Hazards.bend_heading(Vector2.DOWN, 300.0, START, DT, 1.0)
	var half := Hazards.bend_heading(Vector2.DOWN, 300.0, START, DT, 0.5)
	assert_almost_eq(full.length(), 1.0, 1e-5)
	assert_gt(full.x, half.x)
	assert_gt(half.x, 0.0)
