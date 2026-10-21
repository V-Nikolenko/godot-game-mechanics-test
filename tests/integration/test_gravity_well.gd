## INTENT tests for plan §2.5 (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md): the real Gravity Well scene
## drags ships of both sides toward a crushing core. Every row uses `gravity_well.tscn` itself, not a
## fixture `HazardField`, so a scene whose exports drift from the plan's numbers fails here.
##
## The well is hand-ticked (`_physics_process(d)`, its own tick switched off) so the stress clock is exact;
## enemies are hand-ticked like `test_enemy_dual_mode.gd` does. "Dual-mode" rows run in both harnesses.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const WELL_SCENE: PackedScene = preload("res://assault/scenes/hazards/gravity_well/gravity_well.tscn")
const SWARM_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")

const D := 1.0 / 60.0
const CENTRE := Vector2(640.0, 360.0)


func after_each() -> void:
	Input.action_release("move_up")


func _well(at: Vector2 = CENTRE) -> HazardField:
	var w := WELL_SCENE.instantiate() as HazardField
	add_child_autofree(w)
	w.set_physics_process(false)
	w.global_position = at
	return w


func _world(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = CENTRE
	return harness


func _tick(entity: BaseEnemy, delta: float) -> void:
	var before := entity.global_position
	entity._physics_process(delta)
	entity.global_position = before + entity.velocity * delta


func _enemy(harness, scene: PackedScene, at: Vector2) -> BaseEnemy:
	var entity := scene.instantiate() as BaseEnemy
	entity.global_position = at
	(entity.get_node("Brain") as EnemyBrain).set(&"start_engaged", true)
	harness.root.add_child(entity)
	entity.set_physics_process(false)
	return entity


func _health(entity: Node) -> int:
	return (entity.get_node("Health") as Health).current_health


## One full stress period is enough for exactly one pulse.
func _pulse(well: HazardField) -> void:
	well._physics_process(well.stress_period)


func _ship(at: Vector2) -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.global_position = at
	return ship


func _fly(ship: OpenSpacePlayerShip, frames: int) -> void:
	for i in range(frames):
		ship._handle_thrust(D)
		ship.global_position += ship.velocity * D


# --- the scene's numbers ------------------------------------------------------------------------------


func test_the_scene_carries_the_plan_values() -> void:
	var w := _well()
	assert_eq(w.kind, &"gravity_well")
	assert_eq([w.radius, w.core_radius, w.pull_force], [420.0, 90.0, 520.0])
	assert_eq([w.damage_radius, w.stress_damage, w.stress_period], [150.0, 5, 0.5])
	assert_eq(w.avoid_weight, 1.0)
	assert_eq(w.duration, 0.0, "permanent")
	assert_eq(w.movement_penalty, 0.0, "a well pulls, it does not slow")
	var info := w.hazard_info()
	assert_false(info.line_of_sight_blocker, "a well does not block sight")
	assert_almost_eq(info.accel_at(CENTRE + Vector2(90.0, 0.0)).length(), 520.0, 0.01)
	assert_almost_eq(info.accel_at(CENTRE + Vector2(140.0, 0.0)).length(), 334.3, 0.5)
	assert_almost_eq(info.accel_at(CENTRE + Vector2(420.0, 0.0)).length(), 0.0, 0.001)


func test_the_well_has_no_physics_body_and_registers_itself() -> void:
	var w := _well()
	assert_eq(Hazards.count(), 1, "registered on entering the tree")
	for child in w.get_children():
		assert_false(child is CollisionObject2D, "no physics body: ships and shots pass through")
	assert_eq(w.get_class(), "Node2D", "the root is not an Area2D or a body")


func test_the_well_draws_a_ring_and_a_sprite() -> void:
	# (the ring is `_draw()` code, so a script-method check stands in for a render, which no gate step does)
	var w := _well()
	var sprite := w.get_node("Sprite") as AnimatedSprite2D
	assert_not_null(sprite, "the t5 art")
	assert_eq(sprite.animation, &"swirl")
	var drawn := false
	for m in (w.get_script() as Script).get_script_method_list():
		drawn = drawn or m["name"] == "_draw"
	assert_true(drawn, "the faint radius ring is drawn in code")


func test_the_glow_is_read_only_and_scales_with_the_players_field_strength() -> void:
	var w := _well()
	var player := CharacterBody2D.new()
	player.add_to_group(&"player")
	add_child_autofree(player)
	player.global_position = CENTRE + Vector2(60.0, 0.0)
	w._process(D)
	var strong: float = w.glow_strength()
	player.global_position = CENTRE + Vector2(300.0, 0.0)
	w._process(D)
	var weak: float = w.glow_strength()
	player.global_position = CENTRE + Vector2(900.0, 0.0)
	w._process(D)
	assert_gt(strong, weak, "stronger field at the player: brighter glow")
	assert_gt(weak, w.glow_strength(), "no field at the player: the dimmest glow")
	assert_eq(w.glow_strength(), GravityWell.GLOW_MIN, "the floor, not zero")
	assert_eq(player.global_position, CENTRE + Vector2(900.0, 0.0), "presentation only: nothing is written")


# --- hull stress ---------------------------------------------------------------------------------------


func test_stress_lands_on_a_real_swarm_drone_inside_150_px_and_not_at_151(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var well := _well()
	var inside := _enemy(harness, SWARM_SCENE, CENTRE + Vector2(150.0, 0.0))
	var outside := _enemy(harness, SWARM_SCENE, CENTRE + Vector2(0.0, 151.0))
	var before := _health(inside)
	_pulse(well)
	assert_eq(_health(inside), before - 5, "%s: 150 px (centre distance) is stressed" % mode)
	assert_eq(_health(outside), before, "%s: 151 px is not" % mode)


## Health plus shield charges: the player's shield absorbs a hit before health does, so either one dropping
## means the stress landed.
func _protection(ship: OpenSpacePlayerShip) -> int:
	return ship.health_component.current_health + ship.shield_component.permanent_active + ship.shield_component.temporary_count


func test_stress_lands_on_the_player_inside_150_px_and_not_at_151() -> void:
	var well := _well()
	var inside := _ship(CENTRE + Vector2(150.0, 0.0))
	var outside := _ship(CENTRE + Vector2(0.0, 151.0))
	var before_in := _protection(inside)
	var before_out := _protection(outside)
	_pulse(well)
	assert_lt(_protection(inside), before_in, "150 px: the player is stressed")
	assert_eq(_protection(outside), before_out, "151 px: not")


func test_a_swarm_drone_left_in_the_core_stays_inside_150_px_and_dies_to_stress(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var well := _well()
	var drone := _enemy(harness, SWARM_SCENE, CENTRE + Vector2(40.0, 0.0))
	var farthest := 0.0
	var ticks := 0
	while is_instance_valid(drone) and not drone.is_queued_for_deletion() and ticks < 600:
		well._physics_process(D)
		_tick(drone, D)
		ticks += 1
		if is_instance_valid(drone):
			farthest = maxf(farthest, drone.global_position.distance_to(CENTRE))
	assert_lt(farthest, 150.0, "%s: never left the stress radius" % mode)
	assert_true(not is_instance_valid(drone) or drone.is_queued_for_deletion(), "%s: killed by stress" % mode)
	assert_lt(ticks * D, 4.0, "%s: 30 hp at 10 per second" % mode)


func test_stress_bypasses_an_enemy_shield(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var well := _well()
	var drone := _enemy(harness, SWARM_SCENE, CENTRE + Vector2(50.0, 0.0))
	var before := _health(drone)
	var shield := EnemyShield.new()
	shield.arc_deg = 360.0
	drone.add_child(shield)
	assert_true(shield.attach(Hazards.hurt_box_of(drone)), "sanity: the shield is up on the hull")
	var points := shield.points()
	_pulse(well)
	assert_eq(_health(drone), before - 5, "%s: a direct emit never meets the shield" % mode)
	assert_eq(shield.points(), points, "%s: and the shield loses nothing" % mode)


func test_a_plated_ram_takes_no_stress_while_a_plate_lives(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var well := _well()
	var ram := _enemy(harness, RAM_SCENE, CENTRE + Vector2(60.0, 0.0))
	assert_true(ram.is_armored(), "sanity: plated")
	var before := _health(ram)
	_pulse(well)
	_pulse(well)
	assert_eq(_health(ram), before, "%s: the armour deflects stress" % mode)


# --- escaping ------------------------------------------------------------------------------------------


func test_a_real_fighter_seeking_outward_from_100_px_gets_out(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _world(mode)
	var well := _well()
	var fighter := _enemy(harness, FIGHTER_SCENE, CENTRE + Vector2(100.0, 0.0))
	var mover := fighter.get_node("EnemyMover") as EnemyMover
	for _i in 240:
		well._physics_process(D)
		mover.request_velocity(Vector2.RIGHT * FIGHTER_CONFIG.max_speed)
		_tick_mover_only(fighter)
	assert_gt(fighter.global_position.distance_to(CENTRE), 150.0, "%s: out of the stress radius" % mode)


func _tick_mover_only(entity: BaseEnemy) -> void:
	var before := entity.global_position
	var mover := entity.get_node("EnemyMover") as EnemyMover
	mover.step(D)
	entity.global_position = before + entity.velocity * D


func test_the_open_space_player_cannot_thrust_out_from_100_px_but_boosts_out() -> void:
	Input.action_press("move_up")
	var ship := _ship(CENTRE)
	var well := _well(CENTRE + Vector2(0.0, 100.0))
	_fly(ship, 60)
	assert_lt(ship.global_position.distance_to(well.global_position), 100.0, "thrust loses to the core's pull")
	Input.action_release("move_up")

	var booster := _ship(Vector2(3000.0, 0.0))
	var well2 := _well(Vector2(3000.0, 100.0))
	booster._step_boost(true, true, D)
	for i in 30:
		booster._step_hazards(D)
		booster._step_boost(false, true, D)
		booster.global_position += booster.velocity * D
	assert_gt(booster.global_position.distance_to(well2.global_position), 200.0, "a held boost clears the core")
