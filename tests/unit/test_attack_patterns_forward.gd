## Unit tests for docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.3 / X7:
## - AimedAttackPattern / GatlingAttackPattern's forward (non-aimed) branch reads the actor's
##   nose from EnemyMover.sprite_forward_angle_of() instead of assuming nose-down art;
## - both patterns' new aim_point override and per-instance rng jitter;
## - EnemyPathMover's facing formula, now expressed the same way;
## - EnemyMover.sprite_forward_angle_of() as the ONE shared reader of the convention — a source
##   sweep asserts no other `get(&"sprite_forward_angle")` remains project-wide.
##
## Angles are compared with angle_difference() and vectors component-wise with assert_almost_eq(),
## never bit-for-bit (review should-fix 2) — Vector2.RIGHT.rotated(r + PI/2) only equals
## Vector2.DOWN.rotated(r) within float epsilon, and vel.angle() - PI/2 can differ from the legacy
## atan2(-vel.x, vel.y) by 2*PI for the same heading (e.g. vel = (-1, -1)).
extends GutTest

const ENEMY_BULLET_SCENE: PackedScene = \
		preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
const PathMoverActor := preload("res://tests/helpers/path_mover_actor.gd")

const EPS := 1e-5
const _DT := 1.0 / 60.0

## Skirts the full circle in 8 steps; includes the (-1, -1)-direction boundary the plan names
## (StraightMovement.angle = -3*PI/4 gives sample direction (sin, cos) = (-0.707, -0.707)).
const _HEADING_ANGLES: Array[float] = [
	0.0, PI / 4.0, PI / 2.0, 3.0 * PI / 4.0, PI, -3.0 * PI / 4.0, -PI / 2.0, -PI / 4.0,
]

## Skipped when sweeping the project for `.gd` files: `tests/` holds the one legitimate direct
## reader left (test_enemy_mover.gd's own probe of the duck-typed property), which the sweep is
## not meant to police (N2 resolution).
const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import", "tests"]


# ── harness ──────────────────────────────────────────────────────────────────

var _container: Node2D
var _ship: Node2D
var _pool: BulletPool


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_ship = Node2D.new()
	_container.add_child(_ship)
	_ship.global_position = Vector2(400.0, 300.0)
	_pool = _make_pool(_ship, 8)


func _make_pool(ship: Node2D, size: int) -> BulletPool:
	var pool := BulletPool.new()
	pool.bullet_scene = ENEMY_BULLET_SCENE
	pool.pool_size = size
	ship.add_child(pool)
	return pool


func _fired_in(container: Node2D) -> Array:
	var out: Array = []
	for child in container.get_children():
		if child is EnemyBullet:
			out.append(child)
	return out


func _fired() -> Array:
	return _fired_in(_container)


## A rig with its own container/ship/pool, where the ship's `sprite_forward_angle` is a real
## duck-typed property (via a tiny inline script), for the travel-direction identity checks.
func _rig_with_forward_angle(angle: float) -> Dictionary:
	var container := Node2D.new()
	add_child_autofree(container)
	var ship: Node2D = _script("extends Node2D\nvar sprite_forward_angle: float = 0.0\n").new()
	ship.sprite_forward_angle = angle
	container.add_child(ship)
	ship.global_position = Vector2(400.0, 300.0)
	var pool := _make_pool(ship, 8)
	return {"container": container, "ship": ship, "pool": pool}


## A `CharacterBody2D` with `sprite_forward_angle` as a real duck-typed property, for the
## EnemyPathMover facing cases.
func _path_actor_with_forward_angle(angle: float) -> CharacterBody2D:
	var actor: CharacterBody2D = \
			_script("extends CharacterBody2D\nvar sprite_forward_angle: float = 0.0\n").new()
	actor.sprite_forward_angle = angle
	add_child_autofree(actor)
	return actor


func _script(source: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = source
	s.reload()
	return s


# ── Forward branch: no property on the actor -> legacy DOWN.rotated(rotation) ──────────────────

func test_aimed_pattern_forward_with_no_sprite_forward_angle_matches_legacy_down_rotated() -> void:
	assert_null(_ship.get(&"sprite_forward_angle"), "sanity: a plain Node2D has no such property")
	_ship.rotation = 0.7
	var p := AimedAttackPattern.new()
	p.aim_at_player = false
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = Vector2.DOWN.rotated(_ship.rotation)
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	assert_almost_eq(dir.x, expected.x, EPS)
	assert_almost_eq(dir.y, expected.y, EPS)


func test_gatling_pattern_forward_with_no_sprite_forward_angle_matches_legacy_down_rotated() -> void:
	_ship.rotation = -1.1
	var p := GatlingAttackPattern.new()
	p.aim_at_player = false
	p.spread_angle = 0.0  # isolate direction from the random scatter
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = Vector2.DOWN.rotated(_ship.rotation)
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	assert_almost_eq(dir.x, expected.x, EPS)
	assert_almost_eq(dir.y, expected.y, EPS)


# ── Forward branch: the shot goes out of the nose, whichever way art was drawn ─────────────────

## rotation is set via the same convention EnemyMover/EnemyPathMover use
## (rotation = heading.angle() - sprite_forward_angle_of(actor)), so a forward-fired shot must
## come out exactly along `vel`, regardless of how the sprite's forward offset is authored.
func _assert_forward_matches_travel(forward_angle: float, use_gatling: bool = false) -> void:
	var rig := _rig_with_forward_angle(forward_angle)
	var ship: Node2D = rig.ship
	var vel := Vector2(120.0, -75.0)
	ship.rotation = vel.angle() - EnemyMover.sprite_forward_angle_of(ship)

	var p: AttackPatternResource
	if use_gatling:
		var g := GatlingAttackPattern.new()
		g.spread_angle = 0.0
		p = g
	else:
		p = AimedAttackPattern.new()
	p.aim_at_player = false
	p.fire(ship, rig.pool)

	var bullets := _fired_in(rig.container)
	assert_eq(bullets.size(), 1)
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	var expected := vel.normalized()
	assert_almost_eq(dir.x, expected.x, 1e-4, "sprite_forward_angle=%.4f" % forward_angle)
	assert_almost_eq(dir.y, expected.y, 1e-4, "sprite_forward_angle=%.4f" % forward_angle)


func test_aimed_pattern_forward_matches_travel_direction_for_sprite_forward_angle_pi_over_2() -> void:
	_assert_forward_matches_travel(PI / 2.0)


func test_aimed_pattern_forward_matches_travel_direction_for_sprite_forward_angle_negative_pi_over_2() -> void:
	_assert_forward_matches_travel(-PI / 2.0)


func test_gatling_pattern_forward_matches_travel_direction_for_sprite_forward_angle_negative_pi_over_2() -> void:
	_assert_forward_matches_travel(-PI / 2.0, true)


# ── aim_point overrides TargetInfo ──────────────────────────────────────────────────────────────

func test_aimed_pattern_aim_point_overrides_target_info() -> void:
	var player := Node2D.new()
	_container.add_child(player)
	player.add_to_group(&"player")
	player.global_position = _ship.global_position + Vector2(500.0, 500.0)

	var p := AimedAttackPattern.new()
	p.aim_at_player = true
	p.aim_point = _ship.global_position + Vector2(0.0, 200.0)  # straight down, ignoring the player
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = (p.aim_point - (_ship.global_position + p.spawn_offset)).normalized()
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	assert_almost_eq(absf(angle_difference(dir.angle(), expected.angle())), 0.0, 1e-4)

	var toward_player: Vector2 = (player.global_position - _ship.global_position).normalized()
	assert_gt(absf(angle_difference(dir.angle(), toward_player.angle())), 0.1,
			"aim_point must actually override TargetInfo, not just coincide with it")


func test_gatling_pattern_aim_point_overrides_target_info() -> void:
	var player := Node2D.new()
	_container.add_child(player)
	player.add_to_group(&"player")
	player.global_position = _ship.global_position + Vector2(-500.0, 500.0)

	var p := GatlingAttackPattern.new()
	p.aim_at_player = true
	p.spread_angle = 0.0  # isolate direction from the random scatter
	p.aim_point = _ship.global_position + Vector2(0.0, 200.0)
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = (p.aim_point - (_ship.global_position + p.spawn_offset)).normalized()
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	assert_almost_eq(absf(angle_difference(dir.angle(), expected.angle())), 0.0, 1e-4)


# ── Seeded rng jitter: reproducible, and stays within ±spread_angle ─────────────────────────────

func test_aimed_pattern_seeded_rng_jitter_is_reproducible_and_within_spread() -> void:
	_ship.rotation = 0.0
	var p1 := AimedAttackPattern.new()
	p1.aim_at_player = false
	p1.spread_angle = 0.3
	p1.rng = RandomNumberGenerator.new()
	p1.rng.seed = 42
	var p2 := AimedAttackPattern.new()
	p2.aim_at_player = false
	p2.spread_angle = 0.3
	p2.rng = RandomNumberGenerator.new()
	p2.rng.seed = 42

	p1.fire(_ship, _pool)
	p2.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 2)
	var dir1: Vector2 = (bullets[0] as EnemyBullet)._direction
	var dir2: Vector2 = (bullets[1] as EnemyBullet)._direction
	assert_almost_eq(dir1.angle(), dir2.angle(), 1e-6, "the same seed must reproduce the same jitter")

	var base: Vector2 = Vector2.RIGHT.rotated(_ship.rotation + EnemyMover.sprite_forward_angle_of(_ship))
	assert_lte(absf(angle_difference(dir1.angle(), base.angle())), p1.spread_angle + 1e-6,
			"jitter must stay within spread_angle")


func test_gatling_pattern_seeded_rng_jitter_is_reproducible_and_within_spread() -> void:
	_ship.rotation = 0.0
	var p1 := GatlingAttackPattern.new()
	p1.aim_at_player = false
	p1.spread_angle = 0.2
	p1.rng = RandomNumberGenerator.new()
	p1.rng.seed = 7
	var p2 := GatlingAttackPattern.new()
	p2.aim_at_player = false
	p2.spread_angle = 0.2
	p2.rng = RandomNumberGenerator.new()
	p2.rng.seed = 7

	p1.fire(_ship, _pool)
	p2.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 2)
	var dir1: Vector2 = (bullets[0] as EnemyBullet)._direction
	var dir2: Vector2 = (bullets[1] as EnemyBullet)._direction
	assert_almost_eq(dir1.angle(), dir2.angle(), 1e-6, "the same seed must reproduce the same jitter")

	var base: Vector2 = Vector2.RIGHT.rotated(_ship.rotation + EnemyMover.sprite_forward_angle_of(_ship))
	assert_lte(absf(angle_difference(dir1.angle(), base.angle())), p1.spread_angle + 1e-6,
			"jitter must stay within spread_angle")


func test_gatling_pattern_with_no_rng_still_uses_the_global_randf_range() -> void:
	## rng == null must keep today's behaviour (legacy rail streams and the station never set it).
	_ship.rotation = 0.0
	var p := GatlingAttackPattern.new()
	p.aim_at_player = false
	p.spread_angle = 0.2
	assert_null(p.rng)
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var base: Vector2 = Vector2.RIGHT.rotated(_ship.rotation + EnemyMover.sprite_forward_angle_of(_ship))
	var dir: Vector2 = (bullets[0] as EnemyBullet)._direction
	assert_lte(absf(angle_difference(dir.angle(), base.angle())), p.spread_angle + 1e-6)


# ── EnemyPathMover facing, expressed the same way ───────────────────────────────────────────────

func _run_path_mover(actor: CharacterBody2D, angle: float) -> Vector2:
	var movement := StraightMovement.new()
	movement.speed = 100.0
	movement.angle = angle
	var mover := EnemyPathMover.new()
	mover.movement = movement
	actor.add_child(mover)
	mover.set_physics_process(false)
	mover._physics_process(_DT)
	return movement.sample(_DT) * ArenaCamera.WORLD_SCALE  # sample(0) == Vector2.ZERO


func test_enemy_path_mover_facing_matches_legacy_atan2_for_pi_over_2_over_8_headings() -> void:
	for a: float in _HEADING_ANGLES:
		var actor := PathMoverActor.new()
		add_child_autofree(actor)
		var vel := _run_path_mover(actor, a)
		var expected := atan2(-vel.x, vel.y)
		assert_true(absf(angle_difference(actor.rotation, expected)) < 1e-5,
				"heading angle=%.4f: actor.rotation=%.8f expected=%.8f" % [a, actor.rotation, expected])


## BOUNDARY (review round 1, B/should-fix 2): this heading's raw atan2 value and vel.angle() - PI/2
## differ by a full 2*PI, so a bit-for-bit comparison here would wrongly fail.
func test_enemy_path_mover_facing_matches_legacy_atan2_for_the_minus_one_minus_one_heading() -> void:
	var actor := PathMoverActor.new()
	add_child_autofree(actor)
	var vel := _run_path_mover(actor, -3.0 * PI / 4.0)
	assert_lt(vel.x, 0.0, "sanity: this heading's velocity is (-, -)")
	assert_lt(vel.y, 0.0, "sanity: this heading's velocity is (-, -)")
	var raw_new := vel.angle() - PI / 2.0
	var raw_legacy := atan2(-vel.x, vel.y)
	assert_gt(absf(raw_new - raw_legacy), 6.0, "sanity: the raw values really do differ by ~2*PI")
	assert_true(absf(angle_difference(actor.rotation, raw_legacy)) < 1e-5)


func test_enemy_path_mover_facing_is_correct_for_sprite_forward_angle_negative_pi_over_2() -> void:
	var actor := _path_actor_with_forward_angle(-PI / 2.0)
	var vel := _run_path_mover(actor, PI / 4.0)
	var expected := vel.angle() - (-PI / 2.0)
	assert_true(absf(angle_difference(actor.rotation, expected)) < 1e-5)


# ── EnemyMover.sprite_forward_angle_of() is the only reader ─────────────────────────────────────

func _collect_gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not (entry.begins_with(".") or SKIPPED_DIRS.has(entry)):
				found.append_array(_collect_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func test_source_sweep_finds_a_non_zero_number_of_gd_files() -> void:
	## Boundary: a broken walk that silently matches nothing must not read as a pass.
	assert_gt(_collect_gd_files("res://").size(), 0)


func test_sprite_forward_angle_of_is_the_only_get_reader() -> void:
	var needle := 'get(&"sprite_forward_angle")'
	var offenders: Array[String] = []
	for path: String in _collect_gd_files("res://"):
		if path == "res://global/enemy_ai/enemy_mover.gd":
			continue  # the one function allowed to read it this way
		var text := FileAccess.get_file_as_string(path)
		if text.find(needle) != -1:
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
			"only EnemyMover.sprite_forward_angle_of() may read sprite_forward_angle via get()")
