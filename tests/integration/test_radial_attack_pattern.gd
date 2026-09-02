## Integration test for RadialAttackPattern (EPIC sub-item 4a).
##
## NOT characterization: the resource is new code, so these assert intended behaviour.
## Plan: `docs/plans/station-bullet-hell/3-plan.md`.
##
## Lives in `integration/`, not `unit/`, because it loads `enemy_bullet.tscn` through a real
## `BulletPool` and needs a live tree — `tests/README.md:16` reserves `unit/` for "one file per
## autoload or `global/components/` component. No scene loading."
##
## The pool is parented pool -> ship -> container so `bullet_pool.gd:47`'s
## `_container = get_parent().get_parent()` resolves to a node this test owns.
extends GutTest

const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _container: Node2D
var _ship: Node2D
var _pool: BulletPool


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_ship = Node2D.new()
	_container.add_child(_ship)
	_ship.global_position = Vector2(400.0, 300.0)
	_pool = _make_pool(32)


func _make_pool(size: int) -> BulletPool:
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	pool.bullet_scene = BULLET_SCENE
	pool.pool_size = size
	_ship.add_child(pool)
	return pool


## Bullets the pool handed out land in the container, not under the ship.
func _fired() -> Array:
	var out: Array = []
	for child in _container.get_children():
		if child is EnemyBullet:
			out.append(child)
	return out


func _directions() -> Array[float]:
	var out: Array[float] = []
	for b in _fired():
		out.append((b as EnemyBullet)._direction.angle())
	return out


func _pattern() -> RadialAttackPattern:
	return RadialAttackPattern.new()


# ── Ring and arc geometry ─────────────────────────────────────────────────────

func test_a_full_ring_is_evenly_spaced() -> void:
	var p := _pattern()
	p.bullet_count = 10
	p.arc = TAU
	p.fire(_ship, _pool)

	var dirs := _directions()
	assert_eq(dirs.size(), 10, "a full ring fires bullet_count bullets")
	dirs.sort()
	var spacing := TAU / 10.0
	for i in dirs.size() - 1:
		assert_almost_eq(dirs[i + 1] - dirs[i], spacing, 0.001,
			"consecutive ring bullets must be TAU/count apart")
	## The wrap gap is the assertion that catches a seam duplicate: an implementation that
	## used arc/(count-1) for a full ring puts two bullets on the same angle and this goes to 0.
	assert_almost_eq(dirs[0] + TAU - dirs[dirs.size() - 1], spacing, 0.001,
		"the last-to-first wrap gap must also be TAU/count — no duplicate at the seam")


func test_an_arc_is_centred_on_the_base_angle() -> void:
	var p := _pattern()
	p.bullet_count = 3
	p.arc = 0.35
	p.base_angle = 0.0
	p.fire(_ship, _pool)

	var dirs := _directions()
	assert_eq(dirs.size(), 3, "a 3-bullet fan fires 3 bullets")
	dirs.sort()
	assert_almost_eq(dirs[0], -0.175, 0.001, "fan must straddle the base angle")
	assert_almost_eq(dirs[1], 0.0, 0.001, "the centre bullet sits on the base angle")
	assert_almost_eq(dirs[2], 0.175, 0.001, "fan must straddle the base angle")


## BOUNDARY. A naive `arc / (count - 1)` divides by zero here.
func test_a_single_bullet_arc_does_not_divide_by_zero() -> void:
	var p := _pattern()
	p.bullet_count = 1
	p.arc = 0.35
	p.base_angle = 0.5
	p.fire(_ship, _pool)

	var dirs := _directions()
	assert_eq(dirs.size(), 1, "count 1 fires exactly one bullet")
	assert_almost_eq(dirs[0], 0.5, 0.001, "the lone bullet sits on the base angle")


## BOUNDARY. Nothing to fire must fire nothing, rather than falling back to one bullet.
func test_a_zero_bullet_count_fires_nothing() -> void:
	var p := _pattern()
	p.bullet_count = 0
	p.fire(_ship, _pool)
	assert_eq(_fired().size(), 0, "count 0 must produce no bullets")


# ── Aiming ────────────────────────────────────────────────────────────────────

func test_aim_at_player_offsets_the_base_angle_toward_the_player() -> void:
	var player := Node2D.new()
	_container.add_child(player)
	player.add_to_group("player")
	player.global_position = _ship.global_position + Vector2(120.0, -160.0)

	var p := _pattern()
	p.bullet_count = 3
	p.arc = 0.35
	p.aim_at_player = true
	p.fire(_ship, _pool)

	var dirs := _directions()
	dirs.sort()
	var expected: float = (player.global_position - _ship.global_position).angle()
	assert_almost_eq(dirs[1], expected, 0.01, "the centre bullet must point at the player")


## BOUNDARY, and it matches AimedAttackPattern's shipped fallback (aimed_attack_pattern.gd:27).
func test_aim_at_player_falls_back_to_down_with_no_player() -> void:
	var p := _pattern()
	p.bullet_count = 1
	p.aim_at_player = true
	p.arc = 0.35
	p.fire(_ship, _pool)

	var dirs := _directions()
	assert_eq(dirs.size(), 1, "the fallback still fires")
	assert_almost_eq(dirs[0], Vector2.DOWN.angle(), 0.001,
		"with no player in the group the pattern must fall back to DOWN")


## The contract that makes this resource differ from its two siblings. Both
## `aimed_attack_pattern.gd:31` and `gatling_attack_pattern.gd:35` do
## `Vector2.DOWN.rotated(ship.rotation)`; this one must NOT, because `station_laser_phase.gd:123`
## rotates the station 0.5 rad/s during exactly the phase the ring fires in, which would swamp
## the designed per-ring precession. Goes red the moment someone "fixes" the divergence.
func test_the_pattern_ignores_ship_rotation() -> void:
	var p := _pattern()
	p.bullet_count = 6
	p.arc = TAU

	## Both volleys are left in the container and compared as two batches, rather than freeing
	## the first one — a queue_free()d node that is also removed from its parent shows up as a
	## GUT orphan for the rest of the test.
	_ship.rotation = 0.0
	p.fire(_ship, _pool)
	var before := _directions()
	before.sort()

	_ship.rotation = 1.0
	p.fire(_ship, _pool)
	var all_dirs := _directions()
	var after: Array[float] = []
	for i in range(before.size(), all_dirs.size()):
		after.append(all_dirs[i])
	after.sort()

	assert_eq(after.size(), before.size(), "same number of bullets either way")
	for i in before.size():
		assert_almost_eq(after[i], before[i], 0.001,
			"ring angles must not move when the ship rotates")


# ── Spawn geometry and bullet configuration ───────────────────────────────────

func test_spawn_radius_places_each_bullet_on_its_own_angle() -> void:
	var p := _pattern()
	p.bullet_count = 8
	p.arc = TAU
	p.spawn_radius = 130.0
	p.fire(_ship, _pool)

	for b in _fired():
		var bullet := b as EnemyBullet
		var offset: Vector2 = bullet.global_position - _ship.global_position
		assert_almost_eq(offset.length(), 130.0, 0.5,
			"every bullet spawns spawn_radius from the ship")
		## angle_to, not a difference of angle()s: the two are the same direction at +PI and -PI,
		## which a raw subtraction reports as a 2*PI error.
		assert_almost_eq(absf(offset.angle_to(bullet._direction)), 0.0, 0.001,
			"each bullet spawns along its own travel angle, not a shared offset")


func test_damage_and_speed_are_written_onto_the_bullet() -> void:
	var p := _pattern()
	p.bullet_count = 2
	p.arc = TAU
	p.bullet_damage = 12
	p.bullet_speed = 240.0
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 2, "two bullets fired")
	for b in bullets:
		var bullet := b as EnemyBullet
		assert_eq(bullet.speed, 240.0, "bullet_speed is written onto the bullet")
		var hb := bullet.get_node_or_null("HitBox") as HitBox
		assert_not_null(hb, "the bullet has a HitBox")
		assert_eq(hb.damage, 12, "bullet_damage is written onto the HitBox")


## BOUNDARY. `bullet_pool.gd:63-66` push_warnings and returns null once drained;
## `tests/README.md:85` confirms push_warning is not a GUT failure.
func test_it_returns_quietly_when_the_pool_is_exhausted() -> void:
	_pool.free()
	_pool = _make_pool(2)

	var p := _pattern()
	p.bullet_count = 10
	p.arc = TAU
	p.fire(_ship, _pool)

	assert_eq(_fired().size(), 2, "an exhausted pool yields what it has and does not crash")
