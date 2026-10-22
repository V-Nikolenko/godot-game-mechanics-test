## HazardField: the one field script behind every Phase 6 field (plan §2.1). Hand-ticked.
extends GutTest

class FixtureShip extends Node2D:
	var taken: Array[int] = []
	func _on_damage(d: int) -> void:
		taken.append(d)

const STEP := 0.25 ## exactly representable, so clocks sum without float drift

var _stressed_counts: Array[int] = []
var _phases: Array[int] = []


func before_each() -> void:
	_stressed_counts.clear()
	_phases.clear()


func _field(props: Dictionary = {}) -> HazardField:
	var f := HazardField.new()
	for key in props:
		f.set(key, props[key])
	f.phase_changed.connect(func(p: int) -> void: _phases.append(p))
	f.stressed.connect(func(n: int) -> void: _stressed_counts.append(n))
	add_child_autofree(f)
	return f


func _ship(at: Vector2) -> FixtureShip:
	var s := FixtureShip.new()
	var hb := HurtBox.new()
	hb.name = "HurtBox"
	hb.received_damage.connect(s._on_damage)
	s.add_child(hb)
	s.add_to_group(&"enemies")
	add_child_autofree(s)
	s.global_position = at
	return s


func _tick(f: HazardField, seconds: float) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		f._physics_process(STEP)


func test_registers_on_enter_and_count_is_zero_after_free() -> void:
	var f := _field()
	assert_eq(Hazards.count(), 1)
	remove_child(f)
	f.free()
	assert_eq(Hazards.count(), 0)


func test_info_mirrors_the_exports() -> void:
	var f := _field({kind = &"anomaly", radius = 200.0, core_radius = 30.0, pull_force = 90.0,
		tangential_force = -40.0, movement_penalty = 0.2, avoid_weight = 0.7, damage_radius = 25.0})
	f.global_position = Vector2(300, 400)
	var i := f.hazard_info()
	assert_eq(i.kind, &"anomaly")
	assert_eq(i.radius, 200.0)
	assert_eq(i.core_radius, 30.0)
	assert_eq(i.pull_force, 90.0)
	assert_eq(i.tangential_force, -40.0)
	assert_eq(i.movement_penalty, 0.2)
	assert_eq(i.avoid_weight, 0.7)
	assert_eq(i.damage_radius, 25.0)
	assert_eq(i.position, Vector2(300, 400))
	assert_eq(i.source, f)


func test_a_field_without_a_cycle_is_always_active() -> void:
	var f := _field({pull_force = 100.0})
	_tick(f, 10.0)
	assert_eq(f.phase(), HazardField.Phase.ACTIVE)
	assert_eq(f.hazard_info().pull_force, 100.0)
	assert_eq(_phases, [])


func test_cycle_runs_telegraph_active_quiet_with_the_configured_lengths() -> void:
	var f := _field({pull_force = 100.0, cycle_telegraph = 1.0, cycle_active = 2.0, cycle_quiet = 1.0})
	assert_eq(f.phase(), HazardField.Phase.TELEGRAPH)
	_tick(f, 0.75)
	assert_eq(f.phase(), HazardField.Phase.TELEGRAPH)
	_tick(f, 0.25)
	assert_eq(f.phase(), HazardField.Phase.ACTIVE)
	_tick(f, 1.75)
	assert_eq(f.phase(), HazardField.Phase.ACTIVE)
	_tick(f, 0.25)
	assert_eq(f.phase(), HazardField.Phase.QUIET)
	_tick(f, 1.0)
	assert_eq(f.phase(), HazardField.Phase.TELEGRAPH, "the cycle loops")
	assert_eq(_phases, [HazardField.Phase.ACTIVE, HazardField.Phase.QUIET, HazardField.Phase.TELEGRAPH])


func test_forces_are_zero_outside_active_and_avoid_weight_is_kept_while_telegraphing() -> void:
	var f := _field({pull_force = 100.0, tangential_force = 50.0, movement_penalty = 0.3, avoid_weight = 0.7,
		cycle_telegraph = 1.0, cycle_active = 1.0, cycle_quiet = 1.0})
	var i := f.hazard_info()
	assert_eq([i.pull_force, i.tangential_force, i.movement_penalty], [0.0, 0.0, 0.0])
	assert_eq(i.avoid_weight, 0.7, "TELEGRAPH keeps avoid_weight")
	_tick(f, 1.0)
	assert_eq([i.pull_force, i.tangential_force, i.movement_penalty, i.avoid_weight], [100.0, 50.0, 0.3, 0.7])
	_tick(f, 1.0)
	assert_eq([i.pull_force, i.tangential_force, i.movement_penalty, i.avoid_weight], [0.0, 0.0, 0.0, 0.0])
	assert_eq(Hazards.accel_at(f.global_position + Vector2(10, 0)), Vector2.ZERO)


func test_phase_progress_runs_zero_to_one_through_the_phase() -> void:
	var f := _field({cycle_telegraph = 1.0, cycle_active = 2.0, cycle_quiet = 1.0})
	assert_eq(f.phase_progress(), 0.0)
	_tick(f, 0.5)
	assert_almost_eq(f.phase_progress(), 0.5, 0.0001)
	_tick(f, 1.0)
	assert_almost_eq(f.phase_progress(), 0.25, 0.0001)
	assert_eq(_field().phase_progress(), 0.0, "no cycle: 0")


func test_stress_pulses_once_per_period_inside_damage_radius() -> void:
	var f := _field({damage_radius = 50.0, stress_damage = 4, stress_period = 1.0})
	var inside := _ship(Vector2(50, 0))
	var outside := _ship(Vector2(51, 0))
	_tick(f, 0.75)
	assert_eq(inside.taken, [], "no pulse before the first period")
	_tick(f, 0.25)
	assert_eq(inside.taken, [4])
	_tick(f, 2.0)
	assert_eq(inside.taken, [4, 4, 4])
	assert_eq(outside.taken, [])
	assert_eq(_stressed_counts, [1, 1, 1])


func test_stress_does_not_pulse_outside_active() -> void:
	var f := _field({damage_radius = 50.0, stress_damage = 4, stress_period = 0.5,
		cycle_telegraph = 1.0, cycle_active = 1.0, cycle_quiet = 2.0})
	var s := _ship(Vector2.ZERO)
	_tick(f, 1.0)
	assert_eq(s.taken, [], "telegraph")
	_tick(f, 1.0)
	assert_eq(s.taken, [4, 4], "active: two pulses")
	_tick(f, 2.0)
	assert_eq(s.taken, [4, 4], "quiet")


func test_stressed_is_not_emitted_when_nobody_was_hit() -> void:
	var f := _field({damage_radius = 50.0, stress_damage = 4, stress_period = 1.0})
	_tick(f, 3.0)
	assert_eq(_stressed_counts, [])


func test_damage_per_second_is_stress_over_period_while_active() -> void:
	var f := _field({damage_radius = 50.0, stress_damage = 6, stress_period = 2.0})
	assert_eq(f.hazard_info().damage_per_second, 3.0)
	assert_eq(_field().hazard_info().damage_per_second, 0.0)


func test_duration_frees_the_node() -> void:
	var f := _field({duration = 2.0})
	_tick(f, 1.75)
	assert_false(f.is_queued_for_deletion())
	_tick(f, 0.25)
	assert_true(f.is_queued_for_deletion())
	await get_tree().process_frame
	assert_eq(Hazards.count(), 0)


func test_claims_delegate_to_the_info() -> void:
	var f := _field()
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	assert_true(f.try_claim(a))
	assert_false(f.try_claim(b))
	assert_true(f.hazard_info().is_claimed_by(a))
	f.release(a)
	assert_true(f.try_claim(b))


func test_spawn_into_attaches_on_the_next_idle_frame_at_the_stored_transform() -> void:
	var container := Node2D.new()
	container.position = Vector2(1000, 1000)
	add_child_autofree(container)
	var f := HazardField.new()
	f.spawn_into(container, Vector2(40, 60), 1.5)
	assert_null(f.get_parent(), "deferred: not attached synchronously")
	await get_tree().process_frame
	assert_eq(f.get_parent(), container)
	assert_eq(f.global_position, Vector2(40, 60))
	assert_eq(f.rotation, 1.5)
	assert_eq(Hazards.count(), 1)


func test_spawn_into_frees_itself_when_the_container_was_freed_first() -> void:
	var container := Node2D.new()
	add_child(container)
	var f := HazardField.new()
	f.spawn_into(container, Vector2.ZERO)
	container.free()
	await get_tree().process_frame
	assert_false(is_instance_valid(f), "an orphan field must free itself")
	assert_eq(Hazards.count(), 0)


func test_spawn_into_is_safe_inside_a_physics_callback() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var f := HazardField.new()
	var probe := Area2D.new()
	probe.monitoring = true
	probe.monitorable = true
	probe.add_child(CollisionShape2D.new())
	(probe.get_child(0) as CollisionShape2D).shape = CircleShape2D.new()
	add_child_autofree(probe)
	f.spawn_into(container, Vector2(5, 5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(f.get_parent(), container)
