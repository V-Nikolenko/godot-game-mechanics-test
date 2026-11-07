## Homing rocket lifetime (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.4, task t3). Intent tests.
##
## The player's `homing_missile` used to hard-code the Assault arena box, so in Open Space it died
## on its first tick anywhere away from the origin. It now carries a `ProjectileLifetime` child
## (`max_time` 6.0, `max_distance` 2400, world rect) and a single `expired -> _on_expired()` handler.
##
## Hand-ticked in both harnesses: the rocket's and its lifetime's physics are switched off and the
## test calls `_physics_process(DT)` on the rocket then on the lifetime (tree order). The "keep a
## rocket alive for a long time" setup is a hurtbox-less static `Node2D` target: the rocket reaches
## it and re-crosses it (direct pursuit overshoots by one step and turns back), so it hovers.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const DT := 1.0 / 60.0
const MAX_TIME := 6.0
const MAX_DISTANCE := 2400.0

var _expired_count: int = 0


func before_each() -> void:
	_expired_count = 0


func _on_expired_seen() -> void:
	_expired_count += 1


func _world(label: String) -> RefCounted:
	var h: RefCounted = HARNESS.assault() if label == "assault" else HARNESS.open_space()
	add_child_autofree(h.root)
	return h


func _rocket(h: RefCounted, at: Vector2, target: Node = null) -> homing_missile:
	var r: homing_missile = HOMING_SCENE.instantiate()
	h.root.add_child(r)
	r.global_position = at
	r.locked_target = target
	r.set_physics_process(false)
	_lifetime(r).set_physics_process(false)
	r.expired.connect(_on_expired_seen)
	return r


func _lifetime(r: homing_missile) -> ProjectileLifetime:
	return r.get_node("ProjectileLifetime") as ProjectileLifetime


func _tick(r: homing_missile) -> void:
	r._physics_process(DT)
	_lifetime(r)._physics_process(DT)


func _static_target(h: RefCounted, at: Vector2) -> Node2D:
	var t := Node2D.new()
	h.root.add_child(t)
	t.global_position = at
	return t


func test_the_rocket_carries_the_lifetime_component_numbers() -> void:
	var r: homing_missile = HOMING_SCENE.instantiate()
	add_child_autofree(r)
	var lt := _lifetime(r)
	assert_not_null(lt, "the rocket has a ProjectileLifetime child")
	assert_eq(lt.max_time, MAX_TIME)
	assert_eq(lt.max_distance, MAX_DISTANCE)
	assert_true(lt.use_world_rect)
	assert_true(r.has_signal("expired"), "the rocket declares `expired`")
	assert_true(r.expired.is_connected(r._on_expired), "expired is wired to the single handler")


func test_an_open_space_rocket_far_from_the_origin_lives_and_reaches_its_target() -> void:
	var h := _world("open_space")
	var at := Vector2(20000.0, 15000.0)
	var target := _static_target(h, at + Vector2(0.0, -600.0))
	var r := _rocket(h, at, target)
	var closest := INF
	for i in 120:
		_tick(r)
		closest = minf(closest, r.global_position.distance_to(target.global_position))
	assert_lt(closest, 10.0, "the rocket reached its target (it died on its first tick before)")
	assert_false(r.is_queued_for_deletion(), "and is still alive")
	assert_eq(_expired_count, 0)


func test_an_assault_rocket_leaving_the_world_rect_expires_once() -> void:
	var h := _world("assault")
	var r := _rocket(h, Vector2(640.0, 360.0))  # no target: flies up
	var ticks := 0
	while not r.is_queued_for_deletion() and ticks < 600:
		_tick(r)
		ticks += 1
	assert_true(r.is_queued_for_deletion(), "freed after leaving the rect")
	assert_eq(_expired_count, 1, "expired once")
	assert_lt(ticks * DT, MAX_TIME, "only the rect rule can trip in Assault: it is gone before max_time")
	for i in 5:
		_tick(r)
	assert_eq(_expired_count, 1, "and stays at once")


func test_a_rocket_hovering_on_a_hurtbox_less_target_expires_once_at_max_time(
		label: String = use_parameters(["open_space", "assault"])) -> void:
	var h := _world(label)
	var at := Vector2(640.0, 360.0)
	var target := _static_target(h, at + Vector2(0.0, -300.0))
	var r := _rocket(h, at, target)
	var ticks := 0
	var reached := false
	while not r.is_queued_for_deletion() and ticks < 600:
		_tick(r)
		ticks += 1
		if r.global_position.distance_to(target.global_position) < 10.0:
			reached = true
		if reached and not r.is_queued_for_deletion():
			assert_lt(r.global_position.distance_to(target.global_position), 40.0,
					"%s: the rocket stays near the target (tick %d)" % [label, ticks])
	assert_true(reached, "%s: the rocket reached the target" % label)
	assert_true(r.is_queued_for_deletion(), "%s: freed" % label)
	assert_eq(_expired_count, 1, "%s: expired once" % label)
	assert_almost_eq(float(ticks), MAX_TIME / DT, 1.5, "%s: at max_time 6.0 (+-1 tick), got tick %d" % [label, ticks])
	for i in 5:
		_tick(r)
	assert_eq(_expired_count, 1, "%s: still once" % label)


func test_an_open_space_rocket_with_no_target_expires_once_at_max_distance() -> void:
	var h := _world("open_space")
	var r := _rocket(h, Vector2(20000.0, 15000.0))
	var origin := Vector2.ZERO
	var ticks := 0
	while not r.is_queued_for_deletion() and ticks < 600:
		_tick(r)
		ticks += 1
		if ticks == 1:
			origin = r.global_position  # the lifetime arms after the first tick's movement
	assert_true(r.is_queued_for_deletion(), "freed")
	assert_eq(_expired_count, 1, "expired once")
	assert_almost_eq(float(ticks), 4.8 / DT, 2.5, "at 2400 px, 4.8 s (+-1 tick of arming), got tick %d" % ticks)
	assert_gte(origin.distance_to(r.global_position), MAX_DISTANCE, "it had flown the full distance")
