## HazardInfo, Hazards and HazardDrift (plan docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md §2.1).
## Intent tests: the registry is the one shared description of a pull, a slow and a danger.
extends GutTest

## Duck-typed hazard that is NOT a HazardField (R6.2): any node answering hazard_info() joins the registry.
class FixtureHazard extends Node2D:
	var info := HazardInfo.new()
	func hazard_info() -> HazardInfo:
		info.position = global_position
		return info
	func _enter_tree() -> void:
		Hazards.register(self)
	func _exit_tree() -> void:
		Hazards.unregister(self)


## A ship stand-in: a group member with a child HurtBox that counts what it receives.
class FixtureShip extends Node2D:
	var taken: Array[int] = []
	func _on_damage(d: int) -> void:
		taken.append(d)


func _hazard(at: Vector2, radius: float = 100.0) -> FixtureHazard:
	var h := FixtureHazard.new()
	h.info.radius = radius
	h.info.core_radius = 20.0
	add_child_autofree(h)
	h.global_position = at
	return h


func _ship(at: Vector2, group: StringName) -> FixtureShip:
	var s := FixtureShip.new()
	var hb := HurtBox.new()
	hb.name = "HurtBox"
	hb.received_damage.connect(s._on_damage)
	s.add_child(hb)
	s.add_to_group(group)
	add_child_autofree(s)
	s.global_position = at
	return s


func _info(radius: float = 100.0, core: float = 20.0) -> HazardInfo:
	var i := HazardInfo.new()
	i.radius = radius
	i.core_radius = core
	return i


# --- falloff -------------------------------------------------------------------------------------

func test_falloff_is_one_in_the_core() -> void:
	var i := _info()
	assert_eq(i.falloff(0.0), 1.0)
	assert_eq(i.falloff(20.0), 1.0)


func test_falloff_is_core_over_r_outside_the_core() -> void:
	assert_almost_eq(_info().falloff(40.0), 0.5, 0.0001)


func test_falloff_is_zero_at_radius_and_beyond() -> void:
	var i := _info()
	assert_eq(i.falloff(100.0), 0.0)
	assert_eq(i.falloff(150.0), 0.0)


func test_falloff_is_continuous_at_the_taper_and_monotone_across_it() -> void:
	var i := _info()
	assert_almost_eq(i.falloff(85.0), 20.0 / 85.0, 0.0001)
	var prev := 2.0
	for r in range(0, 101, 5):
		var f := i.falloff(float(r))
		assert_true(f <= prev + 0.00001, "falloff rose at r=%d" % r)
		prev = f


# --- accel / penalty / contains -------------------------------------------------------------------

func test_accel_at_the_centre_is_finite_and_zero() -> void:
	var i := _info()
	i.pull_force = 500.0
	i.tangential_force = 200.0
	var a := i.accel_at(i.position)
	assert_eq(a, Vector2.ZERO)
	assert_false(is_nan(a.x) or is_nan(a.y))


func test_pull_points_at_the_centre() -> void:
	var i := _info()
	i.pull_force = 100.0
	var a := i.accel_at(Vector2(10, 0))
	assert_almost_eq(a.x, -100.0, 0.001)
	assert_almost_eq(a.y, 0.0, 0.001)


func test_tangential_is_perpendicular_and_its_sign_flips_the_swirl() -> void:
	var i := _info()
	i.tangential_force = 100.0
	var cw := i.accel_at(Vector2(10, 0))
	assert_almost_eq(cw.x, 0.0, 0.001)
	assert_gt(cw.y, 0.0, "clockwise on a y-down screen moves a point on the right downward")
	i.tangential_force = -100.0
	assert_lt(i.accel_at(Vector2(10, 0)).y, 0.0)


func test_accel_is_zero_beyond_radius() -> void:
	var i := _info()
	i.pull_force = 100.0
	assert_eq(i.accel_at(Vector2(100, 0)), Vector2.ZERO)


func test_penalty_inside_radius_only() -> void:
	var i := _info()
	i.movement_penalty = 0.3
	assert_eq(i.penalty_at(Vector2(100, 0)), 0.3)
	assert_eq(i.penalty_at(Vector2(101, 0)), 0.0)


func test_contains_honours_the_margin() -> void:
	var i := _info()
	assert_true(i.contains(Vector2(130, 0), 30.0))
	assert_false(i.contains(Vector2(131, 0), 30.0))


# --- registry ------------------------------------------------------------------------------------

func test_register_on_enter_and_unregister_on_exit() -> void:
	var before := Hazards.count()
	var h := FixtureHazard.new()
	add_child(h)
	assert_eq(Hazards.count(), before + 1)
	remove_child(h)
	assert_eq(Hazards.count(), before)
	h.free()


func test_count_is_zero_after_the_node_is_freed() -> void:
	var h := _hazard(Vector2.ZERO)
	assert_eq(Hazards.count(), 1)
	remove_child(h)
	h.free()
	assert_eq(Hazards.count(), 0)


func test_registering_twice_counts_once() -> void:
	var h := _hazard(Vector2.ZERO)
	Hazards.register(h)
	assert_eq(Hazards.count(), 1)


func test_around_includes_radius_plus_reach_and_excludes_one_px_beyond() -> void:
	var h := _hazard(Vector2.ZERO, 100.0)
	assert_eq(Hazards.around(Vector2(150, 0), 50.0).size(), 1)
	assert_eq(Hazards.around(Vector2(151, 0), 50.0).size(), 0)
	assert_eq(Hazards.around(Vector2(150, 0), 50.0)[0], h.info)


func test_a_duck_typed_fixture_hazard_joins_around() -> void:
	_hazard(Vector2(500, 0), 60.0)
	var found := Hazards.around(Vector2(500, 0), 0.0)
	assert_eq(found.size(), 1)
	assert_true(found[0] is HazardInfo)


func test_accel_at_sums_two_wells() -> void:
	var a := _hazard(Vector2(-10, 0))
	var b := _hazard(Vector2(10, 0))
	a.info.pull_force = 100.0
	b.info.pull_force = 100.0
	# Equal and opposite at the midpoint.
	assert_almost_eq(Hazards.accel_at(Vector2.ZERO).length(), 0.0, 0.001)
	var p := Vector2(0, 5)
	var expect := a.info.accel_at(p) + b.info.accel_at(p)
	assert_eq(Hazards.accel_at(p), expect)
	assert_gt(expect.length(), 0.0)


func test_penalty_is_strongest_only_not_stacked() -> void:
	var a := _hazard(Vector2.ZERO)
	var b := _hazard(Vector2.ZERO)
	a.info.movement_penalty = 0.4
	b.info.movement_penalty = 0.3
	assert_eq(Hazards.penalty_at(Vector2.ZERO), 0.4)


func test_penalty_is_capped() -> void:
	var a := _hazard(Vector2.ZERO)
	a.info.movement_penalty = 0.8
	assert_eq(Hazards.penalty_at(Vector2.ZERO), Hazards.MAX_PENALTY)


func test_penalty_with_no_hazard_is_zero() -> void:
	assert_eq(Hazards.penalty_at(Vector2.ZERO), 0.0)
	assert_eq(Hazards.accel_at(Vector2.ZERO), Vector2.ZERO)


func test_container_is_the_first_node_in_the_group() -> void:
	assert_null(Hazards.container(get_tree()))
	var c := Node2D.new()
	c.add_to_group(Hazards.CONTAINER_GROUP)
	add_child_autofree(c)
	assert_eq(Hazards.container(get_tree()), c)


func test_no_physics_layer_is_allocated_for_hazards() -> void:
	# Plan: bit 12 (value 2048) stays free.
	assert_eq(ProjectSettings.get_setting("layer_names/2d_physics/layer_12", ""), "")


# --- hurt_box_of / pulse_damage -------------------------------------------------------------------

func test_hurt_box_of_finds_the_named_child() -> void:
	var s := _ship(Vector2.ZERO, &"enemies")
	assert_eq(Hazards.hurt_box_of(s), s.get_node("HurtBox"))
	assert_null(Hazards.hurt_box_of(null))
	assert_null(Hazards.hurt_box_of(autofree(Node2D.new())))


func test_pulse_damage_hits_at_exactly_radius_and_not_one_px_beyond() -> void:
	var near := _ship(Vector2(100, 0), &"enemies")
	var far := _ship(Vector2(101, 0), &"enemies")
	assert_eq(Hazards.pulse_damage(get_tree(), Vector2.ZERO, 100.0, 7), 1)
	assert_eq(near.taken, [7])
	assert_eq(far.taken, [])


func test_pulse_damage_hits_the_player_group_too() -> void:
	var p := _ship(Vector2(10, 0), &"player")
	assert_eq(Hazards.pulse_damage(get_tree(), Vector2.ZERO, 50.0, 3), 1)
	assert_eq(p.taken, [3])


func test_pulse_damage_hits_a_node_in_both_groups_once() -> void:
	var s := _ship(Vector2.ZERO, &"enemies")
	s.add_to_group(&"player")
	Hazards.pulse_damage(get_tree(), Vector2.ZERO, 50.0, 3)
	assert_eq(s.taken, [3])


func test_pulse_damage_ignores_nodes_outside_both_groups() -> void:
	var s := _ship(Vector2.ZERO, &"bystanders")
	assert_eq(Hazards.pulse_damage(get_tree(), Vector2.ZERO, 50.0, 3), 0)
	assert_eq(s.taken, [])


func test_pulse_damage_skips_a_ship_with_no_hurt_box() -> void:
	var s := Node2D.new()
	s.add_to_group(&"enemies")
	add_child_autofree(s)
	assert_eq(Hazards.pulse_damage(get_tree(), Vector2.ZERO, 50.0, 3), 0)


# --- claims --------------------------------------------------------------------------------------

func test_a_second_claimer_is_refused_and_the_claimer_may_reclaim() -> void:
	var i := _info()
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	assert_true(i.try_claim(a))
	assert_false(i.try_claim(b))
	assert_true(i.try_claim(a))
	assert_true(i.is_claimed_by(a))
	assert_false(i.is_claimed_by(b))
	assert_true(i.is_claimed())


func test_release_by_a_non_claimer_is_ignored() -> void:
	var i := _info()
	var a: Node = autofree(Node.new())
	var b: Node = autofree(Node.new())
	i.try_claim(a)
	i.release(b)
	assert_true(i.is_claimed_by(a))
	i.release(a)
	assert_false(i.is_claimed())
	assert_true(i.try_claim(b))


func test_a_freed_claimer_frees_the_claim() -> void:
	var i := _info()
	var a := Node.new()
	var b: Node = autofree(Node.new())
	i.try_claim(a)
	a.free()
	assert_false(i.is_claimed())
	assert_true(i.try_claim(b))
	assert_true(i.is_claimed_by(b))


func test_claims_store_an_instance_id_not_a_reference() -> void:
	var i := _info()
	var a: Node = autofree(Node.new())
	i.try_claim(a)
	assert_eq(i.claimer_id, a.get_instance_id())


# --- HazardDrift ---------------------------------------------------------------------------------

func test_drift_approaches_terminal_velocity_in_a_constant_field() -> void:
	var d := HazardDrift.new()
	var a := Vector2(100, 0)
	var k := log(2.0) / 0.35
	for i in 180:
		d.step(a, 0.0, 1.0 / 60.0)
	assert_almost_eq(d.velocity.x, a.x / k, a.x / k * 0.02)


func test_resistance_halves_the_drift() -> void:
	var free := HazardDrift.new()
	var half := HazardDrift.new()
	for i in 180:
		free.step(Vector2(100, 0), 0.0, 1.0 / 60.0)
		half.step(Vector2(100, 0), 0.5, 1.0 / 60.0)
	assert_almost_eq(half.velocity.x, free.velocity.x * 0.5, 0.001)


func test_full_resistance_never_drifts() -> void:
	var d := HazardDrift.new()
	for i in 60:
		d.step(Vector2(500, 0), 1.0, 1.0 / 60.0)
	assert_eq(d.velocity, Vector2.ZERO)


func test_drift_snaps_to_zero_once_the_field_is_gone() -> void:
	var d := HazardDrift.new()
	d.velocity = Vector2(80, 0)
	var ticks := 0
	while d.velocity != Vector2.ZERO and ticks < 600:
		d.step(Vector2.ZERO, 0.0, 1.0 / 60.0)
		ticks += 1
	assert_eq(d.velocity, Vector2.ZERO)
	assert_lt(ticks, 600)


func test_drift_decays_with_the_half_life() -> void:
	var d := HazardDrift.new()
	d.velocity = Vector2(100, 0)
	d.step(Vector2.ZERO, 0.0, 0.35)
	assert_almost_eq(d.velocity.x, 50.0, 0.001)


func test_reset_clears_the_drift() -> void:
	var d := HazardDrift.new()
	d.velocity = Vector2(10, 10)
	d.reset()
	assert_eq(d.velocity, Vector2.ZERO)


# --- minefield (plan §2.10) ----------------------------------------------------------------------

func test_a_minefield_adds_count_hazards_and_removes_them_when_freed() -> void:
	var before := Hazards.count()
	var field := (load("res://assault/scenes/hazards/minefield/minefield.tscn") as PackedScene).instantiate()
	field.count = 6
	field.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(field)
	await wait_process_frames(1)  # each placed mine registers on its own deferred launch
	assert_eq(Hazards.count(), before + 6, "one hazard per mine")
	remove_child(field)
	field.free()
	assert_eq(Hazards.count(), before, "and none left once the field is gone")


# --- segments (Phase 8, docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.6) ------------------------

## A wall from `at - half` to `at + half`, footprint `radius` (the twin beam's 14 + 24 px).
func _segment(at: Vector2, half: Vector2, radius: float = 38.0) -> HazardInfo:
	var i := HazardInfo.new()
	i.position = at
	i.segment_half = half
	i.radius = radius
	return i


func test_a_new_info_is_a_circle_and_exempts_no_one() -> void:
	var i := _info()
	i.position = Vector2(30.0, -20.0)
	assert_eq(i.segment_half, Vector2.ZERO, "every existing hazard is a circle")
	assert_eq(i.exempt_group, &"", "and exempts no one")
	for p in [Vector2.ZERO, Vector2(500.0, 7.0), Vector2(30.0, -20.0)]:
		assert_eq(i.closest_point(p), i.position, "a circle's closest point is its centre (%s)" % p)


func test_segment_closest_point_beside_the_middle_beyond_an_end_and_on_the_line() -> void:
	var s := _segment(Vector2(100.0, 50.0), Vector2(200.0, 0.0))
	assert_eq(s.closest_point(Vector2(150.0, 120.0)), Vector2(150.0, 50.0), "beside: the foot of the perpendicular")
	assert_eq(s.closest_point(Vector2(400.0, 80.0)), Vector2(300.0, 50.0), "beyond the +end: that end")
	assert_eq(s.closest_point(Vector2(-150.0, 50.0)), Vector2(-100.0, 50.0), "beyond the -end, on the line: that end")
	assert_eq(s.closest_point(Vector2(120.0, 50.0)), Vector2(120.0, 50.0), "on the segment: the point itself")


func test_segment_contains_measures_to_the_closest_point_and_honours_the_margin() -> void:
	var s := _segment(Vector2(100.0, 50.0), Vector2(200.0, 0.0))  # (-100, 50) .. (300, 50)
	assert_true(s.contains(Vector2(150.0, 88.0)), "38 px beside the middle: in")
	assert_false(s.contains(Vector2(150.0, 89.0)), "39 px: out")
	assert_true(s.contains(Vector2(150.0, 118.0), 30.0), "margin 30: 68 px in")
	assert_false(s.contains(Vector2(150.0, 119.0), 30.0), "69 px out")
	assert_true(s.contains(Vector2(338.0, 50.0)), "38 px beyond an end, along the line: in")
	assert_false(s.contains(Vector2(339.0, 50.0)), "39 px: out")
	assert_true(s.contains(Vector2(290.0, 80.0)), "190 px from the midpoint but 30 px from the wall: in (not a circle)")
	assert_false(s.contains(Vector2(100.0, 150.0)), "100 px straight off the midpoint: out")


func test_segment_penalty_at_uses_the_closest_point() -> void:
	var s := _segment(Vector2.ZERO, Vector2(0.0, 200.0))  # (0, -200) .. (0, 200)
	s.movement_penalty = 0.3
	assert_eq(s.penalty_at(Vector2(38.0, 190.0)), 0.3, "38 px beside, near an end: slowed")
	assert_eq(s.penalty_at(Vector2(39.0, 190.0)), 0.0, "39 px: not")
	assert_eq(s.penalty_at(Vector2(0.0, -238.0)), 0.3, "38 px beyond the other end: slowed")
	assert_eq(s.penalty_at(Vector2(0.0, -239.0)), 0.0)


func test_around_finds_a_segment_by_its_closest_point() -> void:
	var h := _hazard(Vector2.ZERO, 38.0)
	h.info.segment_half = Vector2(300.0, 0.0)  # (-300, 0) .. (300, 0)
	assert_eq(Hazards.around(Vector2(250.0, 100.0), 62.0).size(), 1, "beside: radius + reach from the wall")
	assert_eq(Hazards.around(Vector2(250.0, 101.0), 62.0).size(), 0, "1 px beyond")
	assert_eq(Hazards.around(Vector2(340.0, 0.0), 2.0).size(), 1, "beyond an end, along the line: radius + reach")
	assert_eq(Hazards.around(Vector2(341.0, 0.0), 2.0).size(), 0, "1 px beyond")
	var long := _hazard(Vector2(2000.0, -500.0), 38.0)
	long.info.segment_half = Vector2(0.0, 500.0)  # (2000, -1000) .. (2000, 0): its midpoint is 650 px off the query
	var found := Hazards.around(Vector2(2000.0, 150.0), 120.0)
	assert_eq(found.size(), 1, "a long wall whose end is in reach is found though its midpoint is not")
	assert_eq(found[0], long.info)


func test_a_segment_with_no_pull_has_no_accel_and_no_slow() -> void:
	var h := _hazard(Vector2(50.0, 50.0), 38.0)
	h.info.core_radius = 0.0
	h.info.segment_half = Vector2(0.0, 200.0)
	for p in [Vector2(60.0, 50.0), Vector2(50.0, 120.0), Vector2(50.0, 50.0), Vector2(80.0, 240.0)]:
		assert_eq(h.info.accel_at(p), Vector2.ZERO, "no pull at %s" % p)
		assert_eq(Hazards.accel_at(p), Vector2.ZERO, "and none through the registry")
		assert_eq(Hazards.penalty_at(p), 0.0, "and no slow")
