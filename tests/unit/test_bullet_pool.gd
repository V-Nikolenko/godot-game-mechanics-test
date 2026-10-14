## Unit tests for BulletPool (global/components/bullet_pool.gd), focused on who owns a bullet when
## the pool's owner ship leaves the tree: `persist_after_owner_death` off frees in-flight bullets
## (today's behaviour, pinned), on hands them over to be self-owned. Plan §2.2.3 / §4 of
## docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md.
##
## Hierarchy mirrors a real ship: container -> ship -> pool, with bullets reparented to the
## container while in flight.
extends GutTest

const BulletFixture := preload("res://tests/helpers/pool_bullet_fixture.gd")

var _container: Node2D
var _ship: Node2D
var _pool: BulletPool
var _scene: PackedScene


func before_all() -> void:
	var proto := Node2D.new()
	proto.set_script(BulletFixture)
	_scene = PackedScene.new()
	_scene.pack(proto)
	proto.free()


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)


## Builds ship + pool under the container. Must run after before_each.
func _make_pool(persist: bool, size: int = 3) -> void:
	_ship = Node2D.new()
	_container.add_child(_ship)
	_pool = BulletPool.new()
	_pool.bullet_scene = _scene
	_pool.pool_size = size
	_pool.persist_after_owner_death = persist
	_ship.add_child(_pool)


## Takes the ship out of the tree (the pool's _exit_tree fires synchronously) and frees it.
func _kill_ship() -> void:
	_container.remove_child(_ship)
	_ship.queue_free()


func test_flag_defaults_off() -> void:
	var pool := BulletPool.new()
	assert_false(pool.persist_after_owner_death)
	pool.free()


func test_acquire_reparents_to_container_and_counts_as_in_flight() -> void:
	_make_pool(false)
	var b: Node = _pool.acquire(Vector2(5, 6))
	assert_eq(b.get_parent(), _container)
	assert_eq(b.reset_count, 1)
	assert_eq(_pool._idle.size(), 2)
	assert_eq(_pool._active.size(), 1)


func test_flag_off_owner_death_frees_in_flight_bullets() -> void:
	_make_pool(false)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_kill_ship()
	await wait_frames(2)
	assert_false(is_instance_valid(b), "flag off: a bullet in flight dies with its owner")


func test_flag_on_owner_death_leaves_in_flight_bullet_live() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_kill_ship()
	await wait_frames(2)
	assert_true(is_instance_valid(b), "flag on: the bullet outlives its owner")
	assert_false(b.is_queued_for_deletion())
	assert_eq(b.get_parent(), _container, "it stays in the container, not in the dead pool")
	assert_true(b.visible)


func test_flag_on_handed_over_bullet_frees_itself_on_expired() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_kill_ship()
	await wait_frames(1)
	b.expired.emit()
	await wait_frames(2)
	assert_false(is_instance_valid(b), "expired -> queue_free once self-owned")


func test_flag_on_handed_over_bullet_never_returns_to_a_pool() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	var recycle_call: Callable = _pool._recycle_calls[b]
	assert_true(b.expired.is_connected(recycle_call), "wired to the pool while owned")
	_kill_ship()
	assert_false(b.expired.is_connected(recycle_call), "the pool's recycle callable is disconnected")
	assert_eq(_pool._active.size(), 0, "the pool no longer lists it as active")


func test_flag_on_only_in_flight_bullets_are_handed_over() -> void:
	_make_pool(true, 3)
	var flying: Node = _pool.acquire(Vector2.ZERO)
	var idle: Array[Node] = _pool._idle.duplicate()
	_kill_ship()
	await wait_frames(2)
	assert_true(is_instance_valid(flying))
	for node: Node in idle:
		assert_false(is_instance_valid(node), "idle bullets are freed with the pool")


func test_flag_on_same_frame_expire_and_owner_death_frees_exactly_once() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	b.expired.emit()  # queues the deferred _recycle
	_kill_ship()      # owner dies before it runs
	await wait_frames(2)
	assert_false(is_instance_valid(b), "an already-expired bullet ends with its owner")


func test_flag_on_same_frame_expire_twice_and_owner_death_is_harmless() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	b.expired.emit()
	b.expired.emit()
	_kill_ship()
	await wait_frames(2)
	assert_false(is_instance_valid(b))


func test_flag_off_same_frame_expire_and_owner_death_frees_once() -> void:
	_make_pool(false)
	var b: Node = _pool.acquire(Vector2.ZERO)
	b.expired.emit()
	_kill_ship()
	await wait_frames(2)
	assert_false(is_instance_valid(b))


func test_recycle_ignores_a_bullet_it_does_not_own() -> void:
	_make_pool(false)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_pool._recycle(b)
	assert_eq(_pool._idle.size(), 3, "owned bullet recycled normally")
	# A second, stale recycle (a deferred call that lost the race) changes nothing.
	_pool._recycle(b)
	assert_eq(_pool._idle.size(), 3)
	assert_eq(_pool._active.size(), 0)
	assert_eq(b.get_parent(), _pool)


func test_expired_bullet_returns_to_its_pool_while_owner_lives() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	b.expired.emit()
	await wait_frames(2)
	assert_true(is_instance_valid(b))
	assert_eq(b.get_parent(), _pool, "flag on does not change normal recycling")
	assert_false(b.visible)
	assert_eq(_pool._idle.size(), 3)


func test_cancel_active_frees_everything_with_flag_on() -> void:
	_make_pool(true)
	var b1: Node = _pool.acquire(Vector2.ZERO)
	var b2: Node = _pool.acquire(Vector2.ZERO)
	_pool.cancel_active()
	await wait_frames(2)
	assert_false(is_instance_valid(b1))
	assert_false(is_instance_valid(b2))
	assert_eq(_pool._active.size(), 0)


func test_cancel_active_then_owner_death_with_flag_on_does_not_error() -> void:
	_make_pool(true)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_pool.cancel_active()
	_kill_ship()
	await wait_frames(2)
	assert_false(is_instance_valid(b))


func test_cancel_active_frees_everything_with_flag_off() -> void:
	_make_pool(false)
	var b: Node = _pool.acquire(Vector2.ZERO)
	_pool.cancel_active()
	await wait_frames(2)
	assert_false(is_instance_valid(b))
