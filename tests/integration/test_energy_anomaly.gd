## INTENT tests for plan §2.6 (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md): the real Energy Anomaly
## scene swirls ships sideways, but only while lit. Every row uses `energy_anomaly.tscn` itself.
##
## The anomaly is hand-ticked (`_physics_process(d)`, its own tick switched off) so the cycle is exact;
## movers are driven through `EnemyMover.step()` like `test_gravity_well.gd`. "Dual-mode" rows run in both
## harnesses.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/hazards/energy_anomaly/energy_anomaly.tscn")
const SWARM_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")

const D := 1.0 / 60.0
const CENTRE := Vector2(640.0, 360.0)
const AT_150 := CENTRE + Vector2(150.0, 0.0)


func _anomaly(at: Vector2 = CENTRE, swirl: float = NAN) -> HazardField:
	var a := SCENE.instantiate() as HazardField
	if not is_nan(swirl):
		a.tangential_force = swirl
	add_child_autofree(a)
	a.set_physics_process(false)
	a.global_position = at
	return a


func _world(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = CENTRE
	return harness


func _drone(harness) -> BaseEnemy:
	var entity := SWARM_SCENE.instantiate() as BaseEnemy
	entity.global_position = AT_150
	harness.root.add_child(entity)
	entity.set_physics_process(false)
	return entity


## Holds the mover at 150 px for [param ticks] ticks of an idle request and returns the velocity it ends with.
func _held_velocity(entity: BaseEnemy, anomaly: HazardField, ticks: int) -> Vector2:
	var mover := entity.get_node("EnemyMover") as EnemyMover
	for _i in ticks:
		anomaly._physics_process(D)
		entity.global_position = AT_150
		mover.step(D)
	return entity.velocity


func _advance(anomaly: HazardField, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var d := minf(D, left)
		anomaly._physics_process(d)
		left -= d


func _radial() -> Vector2:
	return (AT_150 - CENTRE).normalized()


func _clockwise() -> Vector2:
	return Vector2(-_radial().y, _radial().x)


# --- the scene's numbers ------------------------------------------------------------------------------


func test_the_scene_carries_the_plan_values() -> void:
	var a := _anomaly()
	assert_eq(a.kind, &"anomaly")
	assert_eq([a.radius, a.core_radius, a.tangential_force], [300.0, 80.0, 260.0])
	assert_eq([a.pull_force, a.movement_penalty, a.stress_damage], [0.0, 0.0, 0])
	assert_eq([a.cycle_telegraph, a.cycle_active, a.cycle_quiet], [1.0, 2.5, 3.0])
	assert_eq(a.avoid_weight, 0.7)
	assert_eq(a.duration, 0.0, "permanent")
	assert_false(a.hazard_info().line_of_sight_blocker, "an anomaly does not block sight")
	assert_eq(Hazards.count(), 1, "registered on entering the tree")
	for child in a.get_children():
		assert_false(child is CollisionObject2D, "no physics body")


# --- the cycle ------------------------------------------------------------------------------------------


func test_telegraph_always_precedes_active() -> void:
	var a := _anomaly()
	var seen: Array[int] = []
	a.phase_changed.connect(func(p: int) -> void: seen.append(p))
	assert_eq(a.phase(), HazardField.Phase.TELEGRAPH, "a fresh anomaly starts by warning")
	_advance(a, 20.0)
	assert_gt(seen.size(), 4, "sanity: several cycles")
	var last := HazardField.Phase.TELEGRAPH
	for p in seen:
		if p == HazardField.Phase.ACTIVE:
			assert_eq(last, HazardField.Phase.TELEGRAPH, "ACTIVE only ever follows TELEGRAPH")
		last = p


func test_avoid_weight_is_0_while_quiet_and_0_7_while_telegraph() -> void:
	var a := _anomaly()
	assert_almost_eq(a.hazard_info().avoid_weight, 0.7, 0.0001, "TELEGRAPH")
	_advance(a, 2.0)
	assert_eq(a.phase(), HazardField.Phase.ACTIVE)
	assert_almost_eq(a.hazard_info().avoid_weight, 0.7, 0.0001, "ACTIVE")
	_advance(a, 2.0)
	assert_eq(a.phase(), HazardField.Phase.QUIET)
	assert_eq(a.hazard_info().avoid_weight, 0.0, "QUIET")
	_advance(a, 3.0)
	assert_eq(a.phase(), HazardField.Phase.TELEGRAPH)
	assert_almost_eq(a.hazard_info().avoid_weight, 0.7, 0.0001, "TELEGRAPH again")


# --- ships --------------------------------------------------------------------------------------------


func test_an_active_anomaly_displaces_a_mover_sideways(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var a := _anomaly()
	var drone := _drone(harness)
	_advance(a, 1.0)
	assert_eq(a.phase(), HazardField.Phase.ACTIVE, "sanity")
	var v := _held_velocity(drone, a, 30)
	var tangential := v.dot(_clockwise())
	assert_gt(tangential, 30.0, "%s: swirled clockwise" % mode)
	assert_lt(absf(v.dot(_radial())), 0.1 * tangential, "%s: perpendicular to the centre direction" % mode)


func test_a_negative_tangential_force_swirls_the_other_way(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var a := _anomaly(CENTRE, -260.0)
	var drone := _drone(harness)
	_advance(a, 1.0)
	var v := _held_velocity(drone, a, 30)
	var tangential := v.dot(_clockwise())
	assert_lt(tangential, -30.0, "%s: counter-clockwise" % mode)
	assert_lt(absf(v.dot(_radial())), 0.1 * absf(tangential), "%s: still perpendicular" % mode)


func test_quiet_and_telegraph_displace_nothing(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var a := _anomaly()
	var drone := _drone(harness)
	assert_eq(a.phase(), HazardField.Phase.TELEGRAPH, "sanity")
	assert_eq(_held_velocity(drone, a, 30), Vector2.ZERO, "%s: TELEGRAPH" % mode)
	_advance(a, 3.2)
	assert_eq(a.phase(), HazardField.Phase.QUIET, "sanity")
	assert_eq(_held_velocity(drone, a, 30), Vector2.ZERO, "%s: QUIET" % mode)


func test_the_open_space_player_is_swirled_while_active_and_not_otherwise() -> void:
	var a := _anomaly()
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.global_position = AT_150
	for _i in 10:
		ship._handle_thrust(D)
	assert_eq(ship.velocity, Vector2.ZERO, "TELEGRAPH: nothing")
	var rotation_before := ship.rotation
	_advance(a, 1.0)
	for _i in 30:
		ship._handle_thrust(D)
	var tangential := ship.velocity.dot(_clockwise())
	assert_gt(tangential, 20.0, "ACTIVE: swirled")
	assert_lt(absf(ship.velocity.dot(_radial())), 0.1 * tangential, "perpendicular")
	assert_eq(ship.rotation, rotation_before, "a swirl never rotates the ship")


# --- art ----------------------------------------------------------------------------------------------


func test_the_sprite_follows_the_cycle() -> void:
	var a := _anomaly()
	var sprite := a.get_node("Sprite") as EnergyAnomalySprite
	assert_not_null(sprite)
	assert_eq(sprite.animation, &"dim", "TELEGRAPH: the dim frames, brightening")
	var early := sprite.brightness()
	_advance(a, 0.9)
	sprite._process(D)
	assert_gt(sprite.brightness(), early, "rings brighten through TELEGRAPH")
	_advance(a, 0.2)
	sprite._process(D)
	assert_eq(sprite.animation, &"lit", "ACTIVE: lit")
	assert_eq(sprite.brightness(), 1.0)
	var angle := sprite.rotation
	sprite._process(D)
	assert_gt(sprite.rotation, angle, "spins while ACTIVE")
	_advance(a, 2.6)
	sprite._process(D)
	assert_eq(sprite.animation, &"dim", "QUIET: dim")
	assert_lt(sprite.brightness(), 0.6)
	var still := sprite.rotation
	sprite._process(D)
	assert_eq(sprite.rotation, still, "does not spin while QUIET")
