## INTENT tests for the brain + mover contract on `BaseEnemy` (docs/plans/cmug33ldn00d3m52wfe1j6fct/
## 3-plan.md): the physics tick (brain, then mover, once per frame), `suspend_ai()`, suspension by an
## `EnemyPathMover` rail, the seedable rng, and the "no brain → inert" legacy path.
##
## Fixture: `tests/helpers/fixture_enemy.tscn` — a `BaseEnemy` root with an `EnemyMover` and a
## configurable `fixture_brain.gd`. Every case except the real-frames one calls
## `entity._physics_process(dt)` directly and never awaits, so no engine frame interleaves with the
## hand-driven ones.
extends GutTest

const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BONUS_DRONE: PackedScene = preload("res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn")

const DT := 1.0 / 60.0
## Exact in binary floating point, so accumulated decision clocks land on their boundaries.
const DT_EXACT := 1.0 / 64.0


func _spawn(configure: Callable = Callable(), pos: Vector2 = Vector2.ZERO) -> BaseEnemy:
	var entity := FIXTURE_ENEMY.instantiate() as BaseEnemy
	entity.global_position = pos
	if configure.is_valid():
		configure.call(entity)
	add_child_autofree(entity)
	return entity


func _brain(entity: Node) -> EnemyBrain:
	return entity.get_node("Brain") as EnemyBrain


# ── Resolution ─────────────────────────────────────────────────────────────────

func test_brain_resolves_actor_mover_and_no_attack_by_type() -> void:
	var entity := _spawn()
	var brain := _brain(entity)
	assert_same(brain.actor, entity)
	assert_same(brain.mover, entity.get_node("EnemyMover"))
	assert_null(brain.attack, "the fixture has no AttackController")


func test_brain_resolves_an_attack_controller_sibling() -> void:
	var controller := AttackController.new()
	var entity := _spawn(func(e: Node) -> void: e.add_child(controller))
	assert_same(_brain(entity).attack, controller)


# ── The tick ───────────────────────────────────────────────────────────────────

## The brain requests (k * 10, 0) on its k-th tick; with no accel limit the velocity after frame k
## is exactly that request — so the mover stepped AFTER the brain in the same frame. A mover-first
## loop would lag one tick behind.
func test_brain_ticks_before_the_mover_in_the_same_frame() -> void:
	var entity := _spawn()
	var brain := _brain(entity)
	brain.desired_velocity = Vector2(10, 0)
	brain.ramp = true
	for k in range(1, 6):
		entity._physics_process(DT)
		assert_eq(entity.velocity, Vector2(10.0 * k, 0), "frame %d" % k)


func test_one_brain_tick_per_physics_call_with_that_delta() -> void:
	var entity := _spawn()
	for _i in 7:
		entity._physics_process(DT)
	var brain := _brain(entity)
	assert_eq(brain.tick_count, 7)
	for d: float in brain.tick_log:
		assert_eq(d, DT)


func test_the_engine_drives_exactly_one_tick_per_physics_frame() -> void:
	var entity := _spawn()
	var brain := _brain(entity)
	await wait_physics_frames(1)  # let any first-frame setup settle
	# GUT's awaiter can resume a frame late, so count real frames with the engine's own counter.
	var ticks_before: int = brain.tick_count
	var frames_before := Engine.get_physics_frames()
	await wait_physics_frames(3)
	var frames := Engine.get_physics_frames() - frames_before
	assert_gt(frames, 0, "sanity: real physics frames ran")
	assert_eq(brain.tick_count - ticks_before, frames,
		"exactly one tick per physics frame (a brain that also ticked itself would show double)")
	assert_true(entity.is_physics_processing())


# ── suspend_ai() ───────────────────────────────────────────────────────────────

func test_suspend_ai_stops_the_brain_and_mover_and_zeroes_velocity() -> void:
	var entity := _spawn()
	var brain := _brain(entity)
	brain.desired_velocity = Vector2(200, 0)
	entity._physics_process(DT)
	assert_eq(entity.velocity, Vector2(200, 0), "sanity: moving before suspension")

	entity.suspend_ai()
	assert_true(entity.is_ai_suspended())
	assert_eq(entity.velocity, Vector2.ZERO)
	var pos := entity.global_position
	var ticks: int = brain.tick_count
	for _i in 5:
		entity._physics_process(DT)
	assert_eq(brain.tick_count, ticks, "no tick after suspension")
	assert_eq(entity.global_position, pos, "no mover step after suspension")


func test_suspend_ai_is_idempotent() -> void:
	var entity := _spawn()
	entity.suspend_ai()
	entity.suspend_ai()
	assert_eq(_brain(entity).suspended_count, 1)


## The acceptance case: a rail attached AFTER the ship entered the tree (wave_manager.gd order)
## suspends the brain through the contract, keeps the actor's physics off, and is the only position
## writer — position equals the path sample exactly. The test never switches the entity's physics
## off itself; only the path mover's own ticking is disabled so it can be stepped by hand (as t2).
func test_path_mover_suspends_the_brain_and_owns_position() -> void:
	var spawn := Vector2(300, 200)
	var entity := _spawn(Callable(), spawn)
	var brain := _brain(entity)
	brain.desired_velocity = Vector2(0, -500)  # would fight the rail if it ever ran
	assert_true(entity.is_physics_processing(), "sanity: the fixture processes physics before the rail")

	var movement := StraightMovement.new()
	movement.speed = 60.0
	movement.angle = 0.0
	var rail := EnemyPathMover.new()
	rail.movement = movement
	entity.add_child(rail)
	rail.set_physics_process(false)

	assert_true(entity.is_ai_suspended())
	assert_eq(brain.suspended_count, 1)
	assert_false(entity.is_physics_processing(), "the rail still switches the actor's physics off")

	var elapsed := 0.0
	for _i in 20:
		rail._physics_process(DT)
		entity._physics_process(DT)  # even a stray call must not move it
		elapsed += DT
	assert_eq(brain.tick_count, 0)
	var expected: Vector2 = spawn + movement.sample(elapsed) * ArenaCamera.WORLD_SCALE
	assert_almost_eq(entity.global_position.x, expected.x, 0.001)
	assert_almost_eq(entity.global_position.y, expected.y, 0.001)


# ── The rng ────────────────────────────────────────────────────────────────────

func _decisions_for(seed_value: int, ticks: int) -> Array[float]:
	var entity := _spawn(func(e: Node) -> void: _brain(e).rng_seed = seed_value)
	for _i in ticks:
		entity._physics_process(DT_EXACT)
	return _brain(entity).decisions


func test_same_rng_seed_gives_the_same_decision_sequence() -> void:
	var a := _decisions_for(1234, 128)
	var b := _decisions_for(1234, 128)
	assert_eq(a.size(), 8, "0.25 s interval over exactly 2 s")
	assert_eq(a, b)


func test_a_different_seed_gives_a_different_sequence() -> void:
	assert_ne(_decisions_for(1234, 128), _decisions_for(99, 128))


## Boundary: the accumulated-delta clock fires on the 16th tick of 1/64, not the 15th.
func test_decision_clock_fires_exactly_at_its_interval() -> void:
	assert_eq(_decisions_for(7, 15).size(), 0)
	assert_eq(_decisions_for(7, 16).size(), 1)


# ── No brain → inert ───────────────────────────────────────────────────────────

## A mover stepped without a brain would zero this velocity (no request) — so a non-zero start
## velocity is what makes "inert" observable (review R5).
func test_enemy_without_a_brain_is_inert() -> void:
	var entity := FIXTURE_ENEMY.instantiate() as BaseEnemy
	var brain := entity.get_node("Brain")
	entity.remove_child(brain)
	brain.free()
	add_child_autofree(entity)
	entity.velocity = Vector2(50, 0)
	entity.global_position = Vector2(10, 10)
	entity._physics_process(DT)
	assert_eq(entity.velocity, Vector2(50, 0))
	assert_eq(entity.global_position, Vector2(10, 10))


## A legacy subclass with no `_physics_process` of its own now inherits BaseEnemy's, which must do
## nothing: the bonus drone keeps its position and velocity.
func test_legacy_subclass_without_its_own_physics_process_is_inert() -> void:
	var drone := BONUS_DRONE.instantiate() as BaseEnemy
	add_child_autofree(drone)
	drone.global_position = Vector2(400, 300)
	drone.velocity = Vector2(0, 75)
	drone._physics_process(DT)
	assert_eq(drone.global_position, Vector2(400, 300))
	assert_eq(drone.velocity, Vector2(0, 75))
