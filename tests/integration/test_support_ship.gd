## The Support Ship shell (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.11; task t10). Intent tests.
##
## What t10 pins: the scene's structure (one r 34 circle shared by body, hurtbox and contact box; a folded
## `Projector`; a world-space hidden `Tether`; a `ContactProfile` in mode NONE), the config (every §2.11 field at its
## value, `ward_min_score` 20), that touching it hurts nobody in either mode, `can_be_repaired() == false` (supports
## never repair each other), the minimal brain (hold near the nearest live ally at `follow_distance`, drift in place
## with none) and the Assault budget's DISENGAGE exit, and `suspend_ai()` (drops the ward, folds the projector, hides
## the tether). Ward choice, repair, shield and escort are t11-t13.
##
## Hand-stepped with a fixed delta (`set_physics_process(false)`), never a `Timer`, except the contact row, which is
## real physics (it needs a real overlap).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const Fixture := preload("res://tests/helpers/contact_fixture.gd")
const SUPPORT_SCENE: PackedScene = preload("res://assault/scenes/enemies/support_ship/support_ship.tscn")
const SHIPPED: SupportShipConfig = preload("res://assault/scenes/enemies/support_ship/support_ship_config.tres")  # read only
const ALLY_SCENE: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")

const DT := 1.0 / 60.0

## Plan §2.11's table, field by field.
const CONFIG_VALUES := {
	&"max_health": 55, &"collision_damage": 0, &"score_value": 60,
	&"max_speed": 270.0, &"acceleration": 700.0, &"max_turn_rate": 4.0, &"jink_strength": 60.0, &"jink_period": 0.8,
	&"follow_distance": 150.0, &"follow_lateral": 40.0, &"evade_radius": 300.0, &"evade_speed": 240.0,
	&"ward_min_score": 20, &"ward_search_radius": 900.0, &"ward_keep_radius": 1100.0, &"min_ward_seconds": 2.0,
	&"ward_switch_margin": 1.3, &"no_ward_grace": 1.5,
	&"beam_range": 380.0, &"repair_period": 1.5, &"repair_fraction": 0.06, &"repair_budget": 150,
	&"shield_arc_deg": 110.0, &"assault_shield_arc_deg": 90.0, &"shield_capacity": 40, &"shield_regen_delay": 3.0,
	&"shield_regen_seconds": 1.5, &"shield_reboot_seconds": 4.0, &"shield_turn_rate": 1.6,
	&"projector_unfold_seconds": 0.4, &"projector_fold_seconds": 0.25,
	&"escort_hp_ratio": 0.35, &"escort_release_ratio": 0.5, &"escort_tow_ratio": 1.25, &"interpose_distance": 90.0,
	&"escort_max_seconds": 4.0, &"escort_safe_distance": 700.0, &"escort_cooldown": 6.0,
	&"engage_seconds": 9.0, &"exit_speed": 300.0, &"view_margin": 48.0, &"view_band": 24.0, &"ward_view_band": 120.0,
}


func _spawn(harness, pos: Vector2) -> SupportShip:
	var ship := SUPPORT_SCENE.instantiate() as SupportShip
	(ship.get_node("Brain") as SupportShipBrain).start_engaged = true  # pre-t15: rows assume combat from spawn
	ship.global_position = pos
	harness.root.add_child(ship)
	ship.set_physics_process(false)  # hand-ticked
	ship.set_process(false)
	return ship


## A still stand-in ally: a fixture enemy in group `enemies`.
func _ally(harness, pos: Vector2) -> BaseEnemy:
	var ally := ALLY_SCENE.instantiate() as BaseEnemy
	ally.global_position = pos
	harness.root.add_child(ally)
	ally.set_physics_process(false)
	ally.add_to_group("enemies")
	return ally


func _tick(ship: BaseEnemy, delta: float) -> void:
	var before := ship.global_position
	ship._physics_process(delta)
	ship.global_position = before + ship.velocity * delta


func _harness(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	return harness


# ── Structure and config ─────────────────────────────────────────────────────────────────────────

func test_one_r34_circle_is_shared_by_body_hurtbox_and_contact_box() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	var body := ship.get_node("CollisionShape2D") as CollisionShape2D
	var hurt := ship.get_node("HurtBox/CollisionShape2D") as CollisionShape2D
	var contact := ship.get_node("ContactHitBox/CollisionShape2D") as CollisionShape2D
	assert_true(body.shape is CircleShape2D)
	assert_eq((body.shape as CircleShape2D).radius, 34.0)
	assert_eq(hurt.shape, body.shape, "hurtbox shares the body shape")
	assert_eq(contact.shape, body.shape, "contact box shares the body shape")
	assert_eq(ship.get_node("Sprite2D").get_class(), "Sprite2D")


func test_the_projector_starts_folded_and_the_tether_is_a_hidden_world_space_line() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	var projector := ship.get_node("Projector") as Sprite2D
	assert_almost_eq(projector.scale.y, 0.0, 0.001, "folded: scale.y 0 (Godot clamps a zero scale to an epsilon)")
	var tether := ship.get_node("Tether") as Line2D
	assert_true(tether.top_level, "drawn in world space")
	assert_false(tether.visible, "hidden when idle")
	assert_not_null(ship.get_node_or_null("Brain") as SupportShipBrain)
	assert_not_null(ship.get_node_or_null("EnemyMover") as EnemyMover)
	assert_null(ship.get_node_or_null("StateLight"), "its state is the projector and the tether")


func test_every_config_field_of_plan_2_11_is_authored() -> void:
	for field: StringName in CONFIG_VALUES:
		var value: Variant = SHIPPED.get(field)
		assert_not_null(value, "%s exists" % field)
		assert_eq(value, CONFIG_VALUES[field], "%s" % field)
	assert_eq(SHIPPED.ward_min_score, 20)


func test_the_live_ship_carries_its_config_onto_hitbox_health_mover_and_score() -> void:
	var harness = _harness("assault")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	assert_eq(ship.health.max_health, 55)
	assert_eq(ship.health.current_health, 55)
	assert_eq(ship.score_value, 60)
	assert_eq(ship.contact_hit_box.damage, 0)
	var mover := ship.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.max_speed, 270.0)
	assert_eq(mover.acceleration, 700.0)
	assert_eq(mover.max_turn_rate, 4.0)
	assert_eq(ship.sprite_forward_angle, PI / 2.0)
	assert_true(ship.is_in_group("enemies"))


# ── Contact: NONE ────────────────────────────────────────────────────────────────────────────────

func test_the_contact_profile_is_none_and_the_hitbox_is_closed() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	await get_tree().physics_frame  # the profile closes the box with set_deferred
	assert_eq(ship.contact_profile.mode, ContactProfile.Mode.NONE)
	assert_false(ship.contact_hit_box.monitoring)
	assert_false(ship.contact_hit_box.monitorable)


func test_touching_the_player_deals_nothing_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	var player := Fixture.build_player(ship.global_position + Vector2(0.0, 20.0))
	harness.root.add_child(player)
	var health := player.get_node("Health") as Health
	for _i in 4:
		await get_tree().physics_frame
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "%s: a touch deals 0" % mode)
	assert_eq(ship.health.current_health, 55, "%s: and the touch does not hurt the ship" % mode)
	assert_false(ship.is_queued_for_deletion())


## The control: the same overlap hurts once the box is opened with damage, so the row above can fail.
func test_the_touch_row_can_fail_a_hitbox_that_is_open_and_armed_hurts() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	await get_tree().physics_frame  # the profile's deferred close lands first
	ship.contact_hit_box.damage = 20
	ship.contact_hit_box.monitoring = true
	ship.contact_hit_box.monitorable = true
	var player := Fixture.build_player(ship.global_position + Vector2(0.0, 20.0))
	harness.root.add_child(player)
	var health := player.get_node("Health") as Health
	for _i in 6:
		await get_tree().physics_frame
	assert_lt(health.current_health, Fixture.PLAYER_MAX_HEALTH, "an opened, armed box hurts")


func test_supports_do_not_repair_each_other() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	assert_false(ship.can_be_repaired())
	ship.health.decrease(20)
	assert_eq(ship.repair(10), 0, "repair() returns 0 on a support")
	assert_eq(ship.health.current_health, 35)


# ── The minimal brain: hold near an ally ─────────────────────────────────────────────────────────

## Open Space only since t11: the ally (score 0) is no ward candidate, so this is the SEEK_WARD fallback, and in Assault a
## support with no ward goes home after `no_ward_grace` (the grace rows below).
func test_it_holds_near_an_ally_at_follow_distance() -> void:
	var mode := "open_space"
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var ally := _ally(harness, Vector2(640.0, 250.0))
	var ship := _spawn(harness, Vector2(640.0, 560.0))
	var start := ship.global_position.distance_to(ally.global_position)
	for _i in 360:
		_tick(ship, DT)
	var d := ship.global_position.distance_to(ally.global_position)
	assert_lt(start, 400.0, "sanity: begins well outside the hold")
	assert_almost_eq(d, SHIPPED.follow_distance, 25.0, "%s: settles at follow_distance" % mode)
	assert_lt(ship.velocity.length(), 20.0, "%s: and stays put" % mode)
	assert_false(ship.is_queued_for_deletion())


## Open Space only since t11 (see above): the SEEK_WARD fallback with non-candidate allies.
func test_it_closes_on_a_far_ally_and_picks_the_nearest_of_two() -> void:
	var mode := "open_space"
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var near := _ally(harness, Vector2(300.0, 300.0))
	var far := _ally(harness, Vector2(1000.0, 300.0))
	var ship := _spawn(harness, Vector2(420.0, 420.0))
	for _i in 360:
		_tick(ship, DT)
	assert_lt(ship.global_position.distance_to(near.global_position), 200.0, "%s: held near the nearer ally" % mode)
	assert_gt(ship.global_position.distance_to(far.global_position), 400.0, "%s: not the far one" % mode)


func test_it_moves_to_the_next_ally_when_the_one_it_held_dies() -> void:
	var harness = _harness("open_space")
	var first := _ally(harness, Vector2(300.0, 300.0))
	var second := _ally(harness, Vector2(900.0, 300.0))
	var ship := _spawn(harness, Vector2(320.0, 460.0))
	for _i in 240:
		_tick(ship, DT)
	assert_lt(ship.global_position.distance_to(first.global_position), 200.0)
	first.free()
	for _i in 600:
		_tick(ship, DT)
	assert_lt(ship.global_position.distance_to(second.global_position), 200.0, "now holds the survivor")


func test_it_never_chooses_another_support_ship_as_its_ally() -> void:
	var harness = _harness("open_space")
	var other := _spawn(harness, Vector2(300.0, 300.0))
	var ship := _spawn(harness, Vector2(700.0, 300.0))
	var before := ship.global_position
	for _i in 120:
		_tick(ship, DT)
	assert_almost_eq(ship.global_position.x, before.x, 1.0, "no ally: drifts in place")
	assert_almost_eq(ship.global_position.y, before.y, 1.0)
	assert_true(is_instance_valid(other))


## Open Space only since t11: in Assault a support with no ward comes into view and goes home after the grace.
func test_with_no_ally_it_drifts_in_place() -> void:
	var mode := "open_space"
	var harness = _harness(mode)
	var ship := _spawn(harness, Vector2(640.0, 300.0))
	var before := ship.global_position
	for _i in 240:
		_tick(ship, DT)
	assert_lt(ship.global_position.distance_to(before), 5.0, "%s: stays where it is" % mode)
	assert_false(ship.is_queued_for_deletion())


# ── Assault: the budget and DISENGAGE ────────────────────────────────────────────────────────────

func test_assault_budget_expiry_enters_disengage_and_frees_it_outside_the_world_rect() -> void:
	var harness = _harness("assault")
	_ally(harness, Vector2(640.0, 300.0))
	var ship := _spawn(harness, Vector2(640.0, 450.0))
	ship.config.engage_seconds = 0.2
	var brain := ship.get_node("Brain") as SupportShipBrain
	_tick(ship, DT)
	assert_eq(brain.phase, SupportShipBrain.Phase.SEEK_WARD, "starts in SEEK_WARD")
	for _i in 20:
		_tick(ship, DT)
	assert_eq(brain.phase, SupportShipBrain.Phase.DISENGAGE, "the budget ran out")
	var freed := false
	for _i in 1500:
		_tick(ship, DT)
		if ship.is_queued_for_deletion():
			freed = true
			break
	assert_true(freed, "freed once outside the world rect")
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	assert_false(rect.has_point(ship.global_position), "and it left through the edge, not in the middle")


func test_open_space_has_no_budget_so_it_never_disengages() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(640.0, 300.0))
	ship.config.engage_seconds = 0.2
	var brain := ship.get_node("Brain") as SupportShipBrain
	for _i in 600:
		_tick(ship, DT)
	assert_ne(brain.phase, SupportShipBrain.Phase.DISENGAGE)
	assert_false(ship.is_queued_for_deletion())


# ── Suspension ───────────────────────────────────────────────────────────────────────────────────

func test_suspend_folds_the_projector_drops_the_ward_and_hides_the_tether() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	var ally := _ally(harness, Vector2(300.0, 100.0))
	var brain := ship.get_node("Brain") as SupportShipBrain
	var projector := ship.get_node("Projector") as Sprite2D
	var tether := ship.get_node("Tether") as Line2D
	# Put it in the supporting look, as a later task will.
	projector.scale.y = 1.0
	tether.visible = true
	brain.ward = ally
	ship.suspend_ai()
	assert_true(ship.is_ai_suspended())
	assert_null(brain.ward, "the ward is dropped")
	assert_almost_eq(projector.scale.y, 0.0, 0.001, "the projector is folded")
	assert_false(tether.visible, "the tether is hidden")
	assert_false(ship.is_ai_driven())


# ── Spawning ─────────────────────────────────────────────────────────────────────────────────────

func test_wave_builder_spawns_it_through_the_shipped_scene() -> void:
	var b := WaveBuilder.new()
	assert_not_null(b.support_ship(), "support_ship() builds a spawn config")
	assert_eq(WaveBuilder.SUPPORT_SHIP, "res://assault/scenes/enemies/support_ship/support_ship.tscn")
	var probe := (load(WaveBuilder.SUPPORT_SHIP) as PackedScene).instantiate()
	assert_true(probe is SupportShip)
	probe.free()


# ══ t11: ward selection, follow, retarget, Assault clamp (plan §2.12) ═════════════════════════════
#
# Candidates stand still (physics off); only the support is hand-ticked. Real scenes where §2.12 names them, otherwise a
# fixture enemy (AI-driven, 10 HP) whose `score_value` the test sets.

const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const BOMBER_SCENE: PackedScene = preload("res://assault/scenes/enemies/bomber/bomber.tscn")
const SWARM_SCENE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const GUNSHIP_SCENE: PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")
const BONUS_DRONE_SCENE: PackedScene = preload("res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn")
const FOLLOW_SEED := 424242


## A still real enemy in group `enemies` (its own `_ready()` joins it).
func _real(harness, scene: PackedScene, pos: Vector2) -> BaseEnemy:
	var e := scene.instantiate() as BaseEnemy
	e.global_position = pos
	harness.root.add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	return e


## A still fixture candidate worth `score`.
func _candidate(harness, pos: Vector2, score: int) -> BaseEnemy:
	var e := _ally(harness, pos)
	e.score_value = score
	return e


func _brain(ship: SupportShip) -> SupportShipBrain:
	return ship.get_node("Brain") as SupportShipBrain


## A support whose brain draws from a fixed seed, so a follow row reproduces.
func _seeded(harness, pos: Vector2) -> SupportShip:
	var ship := _spawn(harness, pos)
	_brain(ship).rng.seed = FOLLOW_SEED
	return ship


func _ticks(ship: BaseEnemy, n: int) -> void:
	for _i in n:
		_tick(ship, DT)


func _camera(harness) -> ArenaCamera:
	return harness.root.get_node("ArenaCamera") as ArenaCamera


# ── Selection ────────────────────────────────────────────────────────────────────────────────────

func test_picks_the_bomber_over_the_fighter(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var fighter := _real(harness, FIGHTER_SCENE, Vector2(440.0, 300.0))
	var bomber := _real(harness, BOMBER_SCENE, Vector2(840.0, 300.0))
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, bomber, "%s: 80 beats 25 at equal distance" % mode)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.FOLLOW)
	assert_true(_brain(ship).is_candidate(fighter), "%s: the fighter was a candidate too" % mode)


func test_a_badly_damaged_fighter_near_the_player_beats_a_healthy_one_far_away(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var far := _real(harness, FIGHTER_SCENE, Vector2(1200.0, 160.0))
	var near := _real(harness, FIGHTER_SCENE, Vector2(640.0, 600.0))
	near.health.decrease(near.health.max_health - near.health.max_health / 5)
	var ship := _spawn(harness, Vector2(640.0, 300.0))
	var brain := _brain(ship)
	assert_gt(brain.threat_score(near), brain.threat_score(far), "%s: closeness and damage weigh in" % mode)
	_tick(ship, DT)
	assert_eq(brain.ward, near, "%s: the hurt fighter by the player is the ward" % mode)


func test_never_another_support(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var other := _spawn(harness, Vector2(500.0, 300.0))
	var ship := _spawn(harness, Vector2(700.0, 300.0))
	_ticks(ship, 10)
	assert_false(_brain(ship).is_candidate(other), "%s: a support is never a candidate" % mode)
	assert_null(_brain(ship).ward, "%s: no ward" % mode)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.SEEK_WARD)


func test_never_a_rail_suspended_enemy(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var fighter := _real(harness, FIGHTER_SCENE, Vector2(440.0, 300.0))
	var bomber := _real(harness, BOMBER_SCENE, Vector2(840.0, 300.0))
	bomber.suspend_ai()
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	_tick(ship, DT)
	assert_false(_brain(ship).is_candidate(bomber), "%s: a railed bomber is no candidate" % mode)
	assert_eq(_brain(ship).ward, fighter, "%s: the fighter" % mode)


func test_skips_a_ward_claimed_by_another_live_support(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var fighter := _real(harness, FIGHTER_SCENE, Vector2(440.0, 300.0))
	var bomber := _real(harness, BOMBER_SCENE, Vector2(840.0, 300.0))
	var first := _spawn(harness, Vector2(600.0, 420.0))
	var second := _spawn(harness, Vector2(680.0, 420.0))
	_tick(first, DT)
	_tick(second, DT)
	assert_eq(_brain(first).ward, bomber, "%s: the first support takes the bomber" % mode)
	assert_eq(bomber.get_meta(SupportShipBrain.CLAIM_META), first.get_instance_id(), "%s: and claims it" % mode)
	assert_eq(_brain(second).ward, fighter, "%s: the second skips the claimed bomber" % mode)
	# Boundary: a stale claim (its support is gone) counts as free.
	first.free()
	var gone := Node.new()
	var stale_id := gone.get_instance_id()
	gone.free()
	bomber.set_meta(SupportShipBrain.CLAIM_META, stale_id)
	var third := _spawn(harness, Vector2(640.0, 420.0))
	_tick(third, DT)
	assert_eq(_brain(third).ward, bomber, "%s: a stale claim is free" % mode)


func test_a_lone_swarm_drone_is_no_ward(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var drone := _real(harness, SWARM_SCENE, Vector2(640.0, 250.0))
	var ship := _spawn(harness, Vector2(640.0, 450.0))
	_ticks(ship, 30)
	assert_eq(drone.score_value, 10)
	assert_null(_brain(ship).ward, "%s: 10 < ward_min_score" % mode)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.SEEK_WARD, "%s: it only holds near it" % mode)
	assert_lt(ship.global_position.distance_to(drone.global_position), 205.0, "%s: holding near it, not leaving" % mode)


func test_gunship_and_bonus_drone_beside_a_fighter_choose_the_fighter(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var gunship := _real(harness, GUNSHIP_SCENE, Vector2(440.0, 300.0))
	var bonus := _real(harness, BONUS_DRONE_SCENE, Vector2(840.0, 300.0))
	var fighter := _real(harness, FIGHTER_SCENE, Vector2(640.0, 200.0))
	var ship := _spawn(harness, Vector2(640.0, 420.0))
	# Both outscore the fighter on raw score_value, so a filter that fell back to it would pick one of them.
	assert_gt(gunship.score_value, fighter.score_value)
	assert_gt(bonus.score_value, fighter.score_value)
	_tick(ship, DT)
	assert_false(_brain(ship).is_candidate(gunship), "%s: the gunship is not AI-driven" % mode)
	assert_false(_brain(ship).is_candidate(bonus), "%s: the bonus drone is no combatant" % mode)
	assert_eq(_brain(ship).ward, fighter, "%s: the fighter" % mode)


## The Bonus Drone has no brain, so the row above holds even without the `counts_toward_wave_clear` clause; this one
## cannot.
func test_a_non_combatant_is_never_a_ward(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var reward := _candidate(harness, Vector2(840.0, 300.0), 500)
	reward.counts_toward_wave_clear = false
	assert_true(reward.is_ai_driven(), "sanity: AI-driven, so only the wave-clear clause can reject it")
	var fighter := _real(harness, FIGHTER_SCENE, Vector2(440.0, 300.0))
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, fighter, "%s: the fighter, not the 500-point reward" % mode)


func test_ward_search_radius_boundary() -> void:
	var harness = _harness("open_space")
	var ship := _spawn(harness, Vector2(100.0, 300.0))
	var far := _candidate(harness, Vector2(100.0 + 910.0, 300.0), 25)
	_tick(ship, DT)
	assert_null(_brain(ship).ward, "910 px > ward_search_radius 900")
	far.global_position = ship.global_position + Vector2(890.0, 0.0)
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, far, "890 px is inside it")


# ── Stability ────────────────────────────────────────────────────────────────────────────────────

func test_a_1_2x_challenger_does_not_take_over(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var held := _candidate(harness, Vector2(440.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, held)
	var challenger := _candidate(harness, Vector2(840.0, 300.0), 60)
	assert_almost_eq(_brain(ship).threat_score(challenger) / _brain(ship).threat_score(held), 1.2, 0.001)
	_ticks(ship, 240)
	assert_eq(_brain(ship).ward, held, "%s: 1.2x < ward_switch_margin 1.3" % mode)
	assert_eq(_brain(ship).wards_selected, 1)


func test_a_1_4x_challenger_takes_over_only_after_min_ward_seconds(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	var held := _candidate(harness, Vector2(440.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	var brain := _brain(ship)
	_tick(ship, DT)
	assert_eq(brain.ward, held)
	var challenger := _candidate(harness, Vector2(840.0, 300.0), 70)
	var held_at_switch := -1.0
	for _i in 180:
		var before := brain.ward_held_for
		_tick(ship, DT)
		if brain.ward == challenger:
			held_at_switch = before
			break
	assert_gt(held_at_switch, 0.0, "%s: 1.4x took over" % mode)
	assert_gte(held_at_switch, SHIPPED.min_ward_seconds - 0.001, "%s: never before min_ward_seconds" % mode)
	assert_lte(held_at_switch, SHIPPED.min_ward_seconds + 2.0 * DT, "%s: and within a tick after" % mode)
	assert_false(held.has_meta(SupportShipBrain.CLAIM_META), "%s: the old claim is released" % mode)
	assert_eq(challenger.get_meta(SupportShipBrain.CLAIM_META), ship.get_instance_id())


# ── Retarget ─────────────────────────────────────────────────────────────────────────────────────

## A ward worth 50 and a spare worth 30; returns [ship, ward, spare, changes].
func _retarget_world(harness) -> Array:
	harness.player.global_position = Vector2(640.0, 700.0)
	var held := _candidate(harness, Vector2(440.0, 300.0), 50)
	var spare := _candidate(harness, Vector2(840.0, 300.0), 30)
	var ship := _spawn(harness, Vector2(640.0, 400.0))
	var changes: Array = []
	_brain(ship).ward_changed.connect(func(w: Node) -> void: changes.append(w))
	_ticks(ship, 10)
	assert_eq(_brain(ship).ward, held, "sanity: the 50 is the ward")
	changes.clear()
	return [ship, held, spare, changes]


func test_freeing_the_ward_selects_a_new_one_on_the_next_tick(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _retarget_world(_harness(mode))
	var ship: SupportShip = w[0]
	w[1].free()
	assert_eq(w[3], [null], "%s: dropped at once (tree_exiting)" % mode)
	_tick(ship, DT)
	assert_eq(w[3], [null, w[2]], "%s: the spare on the next tick" % mode)
	assert_eq(_brain(ship).ward, w[2])


func test_killing_the_ward_through_health_selects_a_new_one_on_the_next_tick(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _retarget_world(_harness(mode))
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	held.health.decrease(held.health.max_health)
	assert_true(held.is_queued_for_deletion(), "sanity: killed, freed at the end of the frame")
	_tick(ship, DT)
	assert_eq(w[3], [null, w[2]], "%s: dropped and replaced on the next tick" % mode)


func test_suspending_the_ward_selects_a_new_one_on_the_next_tick(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var w := _retarget_world(_harness(mode))
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	held.suspend_ai()
	_tick(ship, DT)
	assert_eq(w[3], [null, w[2]], "%s: a rail took it; the spare on the next tick" % mode)
	assert_false(held.has_meta(SupportShipBrain.CLAIM_META), "%s: the claim is released" % mode)


func test_with_no_other_candidate_open_space_seeks() -> void:
	var harness = _harness("open_space")
	harness.player.global_position = Vector2(640.0, 700.0)
	var held := _candidate(harness, Vector2(640.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(640.0, 450.0))
	_ticks(ship, 10)
	held.free()
	_ticks(ship, 180)
	assert_null(_brain(ship).ward)
	assert_eq(_brain(ship).anchor, Vector2.INF, "no anchor without a ward")
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.SEEK_WARD, "Open Space has no grace")


func test_with_no_other_candidate_assault_disengages_after_the_grace() -> void:
	var harness = _harness("assault")
	harness.player.global_position = Vector2(640.0, 700.0)
	var held := _candidate(harness, Vector2(640.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(640.0, 450.0))
	_ticks(ship, 10)
	held.free()
	_ticks(ship, 84)
	assert_null(_brain(ship).ward)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.SEEK_WARD, "1.4 s: still within no_ward_grace")
	_ticks(ship, 12)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.DISENGAGE, "1.6 s: gone home")


func test_assault_grace_starts_only_once_the_support_is_in_view() -> void:
	var harness = _harness("assault")
	harness.player.global_position = Vector2(640.0, 700.0)
	var ship := _spawn(harness, Vector2(640.0, -200.0))
	var brain := _brain(ship)
	var band := EnemyWorld.view_rect(get_tree()).grow(SHIPPED.view_band)
	var entered := -1
	var left := -1
	for i in 400:
		_tick(ship, DT)
		if entered < 0 and band.has_point(ship.global_position):
			entered = i
		if brain.phase == SupportShipBrain.Phase.DISENGAGE:
			left = i
			break
	assert_gt(entered, 10, "sanity: it started out of view and came in (clamped hold point)")
	assert_gt(left, 0, "it disengaged")
	var waited := float(left - entered) * DT
	assert_almost_eq(waited, SHIPPED.no_ward_grace, 2.0 * DT, "the grace ran from entering the view, not from spawn")


func test_a_ward_beyond_keep_radius_is_dropped() -> void:
	var harness = _harness("open_space")
	var held := _candidate(harness, Vector2(500.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, held)
	held.global_position = ship.global_position + Vector2(1090.0, 0.0)
	_tick(ship, DT)
	assert_eq(_brain(ship).ward, held, "1090 px: kept (ward_keep_radius 1100)")
	held.global_position = ship.global_position + Vector2(1110.0, 0.0)
	_tick(ship, DT)
	assert_null(_brain(ship).ward, "1110 px: dropped")


func test_claim_is_released_on_exit() -> void:
	var harness = _harness("open_space")
	var held := _candidate(harness, Vector2(500.0, 300.0), 50)
	var ship := _spawn(harness, Vector2(300.0, 300.0))
	_tick(ship, DT)
	assert_eq(held.get_meta(SupportShipBrain.CLAIM_META), ship.get_instance_id(), "claimed while held")
	ship.free()
	assert_false(held.has_meta(SupportShipBrain.CLAIM_META), "released when the support leaves the tree")


# ── Follow ───────────────────────────────────────────────────────────────────────────────────────

## Ward (640, 360), player still at (640, 760); returns [ship, ward].
func _follow_world(harness, spawn := Vector2(700.0, 260.0)) -> Array:
	harness.player.global_position = Vector2(640.0, 760.0)
	var held := _candidate(harness, Vector2(640.0, 360.0), 50)
	var ship := _seeded(harness, spawn)
	return [ship, held]


func test_sits_within_60_px_of_the_anchor_behind_the_ward(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _follow_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 240)
	var brain := _brain(ship)
	assert_eq(brain.ward, held)
	assert_lt(ship.global_position.distance_to(brain.anchor), 60.0, "%s: on the soft anchor" % mode)
	var behind := (brain.anchor - held.global_position).dot(held.global_position - harness.player.global_position)
	assert_gt(behind, 0.0, "%s: the anchor is on the far side of the ward from the player" % mode)
	assert_almost_eq(brain.anchor.distance_to(held.global_position), Vector2(150.0, 40.0).length(), 0.5)


func test_it_jinks(mode: String = use_parameters(["open_space", "assault"])) -> void:
	for strength: float in [SHIPPED.jink_strength, 0.0]:
		var harness = _harness(mode)
		var w := _follow_world(harness)
		var ship: SupportShip = w[0]
		ship.config.jink_strength = strength
		_ticks(ship, 120)
		var lo := INF
		var hi := -INF
		for _i in 288:  # 6 jink periods; with the settle, 6.8 s < the 9 s Assault budget
			_tick(ship, DT)
			lo = minf(lo, ship.global_position.x)
			hi = maxf(hi, ship.global_position.x)
		if strength > 0.0:
			assert_gt(hi - lo, 15.0, "%s: it sways across the ward line" % mode)
			assert_lt(hi - lo, 120.0, "%s: but stays near its anchor" % mode)
		else:
			assert_lt(hi - lo, 3.0, "%s: control, no jink: it sits still" % mode)
		assert_eq(_brain(ship).phase, SupportShipBrain.Phase.FOLLOW, "%s: still following (inside the budget)" % mode)
		harness.root.free()


## The stub flies a straight line at 200 px/s for 3 s toward the settled support, crossing the ward.
func _evasion_min_distance(mode: String, evade_speed: float, rng_seed: int) -> float:
	var harness = _harness(mode)
	var w := _follow_world(harness)
	var ship: SupportShip = w[0]
	_brain(ship).rng.seed = rng_seed
	ship.config.evade_speed = evade_speed
	_ticks(ship, 180)
	var player: CharacterBody2D = harness.player
	var dir := (ship.global_position - player.global_position).normalized()
	player.velocity = dir * 200.0
	var closest := INF
	for _i in 180:
		player.global_position += player.velocity * DT
		_tick(ship, DT)
		closest = minf(closest, ship.global_position.distance_to(player.global_position))
	harness.root.free()
	return closest


func test_evades_an_approaching_player(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var limit := 0.8 * SHIPPED.evade_radius
	for rng_seed: int in [1, 2, 3, 7]:
		assert_gte(_evasion_min_distance(mode, SHIPPED.evade_speed, rng_seed), limit,
				"%s seed %d: never inside 0.8 x evade_radius" % [mode, rng_seed])
	assert_lt(_evasion_min_distance(mode, 0.0, 1), limit, "%s: control, no escape term: the stub gets inside it" % mode)


func test_never_moves_toward_the_player_by_more_than_50_px(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 700.0)
	_candidate(harness, Vector2(640.0, 300.0), 50)
	var ship := _seeded(harness, Vector2(500.0, 400.0))
	var start := ship.global_position.distance_to(harness.player.global_position)
	var closest := start
	for _i in 300:
		_tick(ship, DT)
		closest = minf(closest, ship.global_position.distance_to(harness.player.global_position))
	assert_gte(closest, start - 50.0, "%s: never closes on the player by more than 50 px" % mode)
	assert_eq(_brain(ship).phase, SupportShipBrain.Phase.FOLLOW)


func test_faces_the_ward(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _follow_world(harness)
	var ship: SupportShip = w[0]
	_ticks(ship, 180)
	var nose := Vector2.RIGHT.rotated(ship.rotation + ship.sprite_forward_angle)
	var to_ward: Vector2 = w[1].global_position - ship.global_position
	assert_lt(absf(nose.angle_to(to_ward)), 0.2, "%s: the projector points at the ward" % mode)


# ── Assault: the view clamp ──────────────────────────────────────────────────────────────────────

func test_assault_anchor_behind_a_ward_above_the_view_is_clamped_into_view() -> void:
	var harness = _harness("assault")
	harness.player.global_position = Vector2(640.0, 600.0)
	var held := _candidate(harness, Vector2(640.0, -80.0), 50)
	var ship := _seeded(harness, Vector2(640.0, 200.0))
	var brain := _brain(ship)
	var band := EnemyWorld.view_rect(get_tree()).grow(SHIPPED.view_band)
	var outside := 0
	for _i in 240:
		_tick(ship, DT)
		if not band.has_point(ship.global_position):
			outside += 1
	assert_eq(brain.ward, held, "a ward 80 px above the view is inside ward_view_band")
	assert_eq(outside, 0, "the support never left the view band")
	assert_gte(brain.anchor.y, SHIPPED.view_margin - 0.001, "the anchor (raw y -230) is clamped into the view")
	assert_true(brain.is_supporting())


func test_assault_ward_300_px_above_the_view_top_no_support_until_the_view_pans() -> void:
	var harness = _harness("assault")
	harness.player.global_position = Vector2(640.0, 600.0)
	var held := _candidate(harness, Vector2(640.0, -300.0), 50)
	var ship := _seeded(harness, Vector2(640.0, 120.0))
	var brain := _brain(ship)
	var band := EnemyWorld.view_rect(get_tree()).grow(SHIPPED.view_band)
	var outside := 0
	var supporting := 0
	for _i in 72:  # 1.2 s, inside no_ward_grace
		_tick(ship, DT)
		if not band.has_point(ship.global_position):
			outside += 1
		if brain.is_supporting():
			supporting += 1
	assert_null(brain.ward, "300 px above the view top: no candidate")
	assert_eq(outside, 0, "it never followed the ward out of the view")
	assert_eq(supporting, 0, "and supported nothing")
	assert_eq(brain.phase, SupportShipBrain.Phase.SEEK_WARD)
	_camera(harness).offset = Vector2(0.0, -300.0)  # the view pans up; no process step needed
	_tick(ship, DT)
	assert_eq(brain.ward, held, "the ward is in view now: selected on the next tick")
	assert_true(brain.is_supporting(), "support resumes")


func test_assault_a_ward_that_leaves_the_view_is_dropped() -> void:
	var harness = _harness("assault")
	var w := _follow_world(harness)
	var ship: SupportShip = w[0]
	var brain := _brain(ship)
	_ticks(ship, 120)
	assert_true(brain.is_supporting(), "sanity: supporting")
	var changes: Array = []
	brain.ward_changed.connect(func(n: Node) -> void: changes.append(n))
	_camera(harness).offset = Vector2(0.0, 600.0)  # the ward (y 360) is now above view.grow(ward_view_band)
	assert_false(brain.is_supporting(), "false in the same frame, before any tick")
	_tick(ship, DT)
	assert_eq(changes, [null], "dropped on the next tick")


func test_assault_support_pushed_out_of_view_does_not_support() -> void:
	var harness = _harness("assault")
	var w := _follow_world(harness)
	var ship: SupportShip = w[0]
	var brain := _brain(ship)
	_ticks(ship, 120)
	assert_true(brain.is_supporting(), "sanity: supporting")
	var sy := ship.global_position.y
	var cam := _camera(harness)
	cam.offset = Vector2(0.0, sy + SHIPPED.view_band + 1.0)  # view top 1 px past the band below the support
	assert_false(brain.is_supporting(), "the support is outside view.grow(view_band): no support")
	cam.offset = Vector2(0.0, sy + SHIPPED.view_band - 1.0)  # 1 px inside the band
	assert_true(brain.is_supporting(), "boundary: 1 px inside the band, it supports")


# ── Repair pulse and projected shield (t12, plan §2.13) ──────────────────────────────────────────

const UNREPAIRABLE: GDScript = preload("res://tests/helpers/fixture_enemy_unrepairable.gd")
const RAM_SCENE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")

const _SPEEDUP: int = 8

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_fast: bool = false


func after_each() -> void:
	if _clock_fast:
		Engine.time_scale = _saved_time_scale
		Engine.physics_ticks_per_second = _saved_ticks
		Engine.max_physics_steps_per_frame = _saved_max_steps
		_clock_fast = false


## The 8× clock with the step kept at 1/60 game-second; restored in `after_each`.
func _fast_clock() -> void:
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP
	_clock_fast = true


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Ward (640, 360) with `hp` of 100, player (640, 760), support seeded at (700, 260) - a support already in range.
func _repair_world(harness, hp: int) -> Array:
	var w := _follow_world(harness)
	var held: BaseEnemy = w[1]
	held.health.max_health = 100
	held.health.current_health = 100
	if hp < 100:
		held.health.decrease(100 - hp)  # through the signal, so the ward knows its last HP (a bare write leaves it unset)
	held.hit_flash_player.stop()  # that damage flashed; only a flash caused by a repair counts
	return w


func _projected(ward: Node) -> EnemyShield:
	return ward.get_node_or_null("ProjectedShield") as EnemyShield


func _hit_at(pos: Vector2, damage: int = 25) -> HitBox:
	var hb := HitBox.new()
	hb.damage = damage
	add_child_autofree(hb)
	hb.global_position = pos
	return hb


func test_a_pulse_restores_6_hp_per_period_and_never_flashes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _repair_world(harness, 50)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	var brain := _brain(ship)
	var pulses := _count(brain.repaired)
	_ticks(ship, 1)
	assert_eq(held.health.current_health, 50, "%s: nothing before the first period" % mode)
	_ticks(ship, 90)  # 1.5 s
	assert_between(held.health.current_health, 55, 56 + 0, "%s: one pulse of round(100 x 0.06) = 6 (+/- a tick)" % mode)
	_ticks(ship, 90)
	assert_between(held.health.current_health, 61, 62, "%s: a second" % mode)
	assert_between(pulses[0], 1, 2)
	assert_false(held.hit_flash_player.is_playing(), "%s: a repair never flashes the ward" % mode)


func test_repaired_signal_carries_the_ward_and_the_hp_gained() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 50)
	var ship: SupportShip = w[0]
	var brain := _brain(ship)
	var got: Array = []
	brain.repaired.connect(func(ward: Node, amount: int) -> void: got.append([ward, amount]))
	_ticks(ship, 95)
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], w[1])
	assert_eq(got[0][1], 6)


func test_a_pulse_never_lifts_the_ward_above_max() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 98)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 200)
	assert_eq(held.health.current_health, 100)


func test_the_budget_stops_repair_after_150_hp_but_the_shield_goes_on() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	var brain := _brain(ship)
	brain.config.repair_budget = 12
	held.health.current_health = 10
	_ticks(ship, 60 * 8)  # 5 periods at most
	assert_eq(held.health.current_health, 22, "exactly the 12 HP budget, not a pulse more")
	assert_eq(brain.repair_spent, 12)
	assert_not_null(_projected(held), "projection continues once the budget is spent")
	# the shipped budget: 25 pulses of 6 HP is the 150
	assert_eq(SHIPPED.repair_budget, 150)
	assert_eq(25 * roundi(100 * SHIPPED.repair_fraction), 150)


func test_a_ward_out_of_beam_range_is_not_pulsed() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 50)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	var brain := _brain(ship)
	brain.config.beam_range = 100.0  # the support sits ~155 px off
	_ticks(ship, 1)
	ship.global_position = held.global_position + Vector2(0.0, -300.0)
	for _i in 200:
		ship.velocity = Vector2.ZERO
		ship._physics_process(DT)
		ship.global_position = held.global_position + Vector2(0.0, -300.0)
	assert_false(brain.is_supporting())
	assert_eq(held.health.current_health, 50, "out of range: no pulse")
	assert_false(ship.tether.visible, "and no tether")


func test_a_ward_that_cannot_be_repaired_is_never_repaired(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 760.0)
	var scene_ward := ALLY_SCENE.instantiate() as BaseEnemy
	scene_ward.set_script(UNREPAIRABLE)
	scene_ward.global_position = Vector2(640.0, 360.0)
	harness.root.add_child(scene_ward)
	scene_ward.set_physics_process(false)
	scene_ward.add_to_group("enemies")
	scene_ward.score_value = 50
	scene_ward.health.max_health = 100
	scene_ward.health.current_health = 40
	var ship := _seeded(harness, Vector2(700.0, 260.0))
	var brain := _brain(ship)
	_ticks(ship, 240)
	assert_eq(brain.ward, scene_ward, "it still wards it")
	assert_false(scene_ward.can_be_repaired())
	assert_eq(scene_ward.health.current_health, 40, "%s: never repaired" % mode)
	assert_eq(brain.repair_spent, 0)


func test_a_blocked_line_means_no_pulse_and_a_dim_tether() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 50)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	var rock := StaticBody2D.new()
	rock.add_to_group(&"asteroids")
	rock.collision_layer = CollisionLayers.ENVIRONMENT
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	rock.add_child(shape)
	harness.root.add_child(rock)
	ship.global_position = held.global_position + Vector2(0.0, -150.0)
	rock.global_position = held.global_position + Vector2(0.0, -75.0)
	await _frames(2)  # the rock enters the physics world
	for _i in 120:
		ship.velocity = Vector2.ZERO
		ship._physics_process(DT)
		ship.global_position = held.global_position + Vector2(0.0, -150.0)
	assert_eq(held.health.current_health, 50, "a rock between them: no pulse")
	assert_lt(ship.tether.default_color.a, SupportShip.TETHER_COLOR.a, "the tether is drawn dim")


func test_each_pulse_flashes_the_tether_pale_green_then_back_to_cyan() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 50)
	var ship: SupportShip = w[0]
	_ticks(ship, 30)
	assert_true(ship.tether.visible, "projecting: the tether is up")
	assert_eq(ship.tether.default_color, SupportShip.TETHER_COLOR, "cyan while projecting")
	var saw_flash := false
	var after_flash_cyan := false
	for _i in 120:
		_tick(ship, DT)
		if ship.tether.default_color == SupportShip.TETHER_REPAIR_COLOR:
			saw_flash = true
		elif saw_flash and ship.tether.default_color == SupportShip.TETHER_COLOR:
			after_flash_cyan = true
	assert_true(saw_flash, "a pulse flashes the tether")
	assert_true(after_flash_cyan, "for 0.15 s only")


# ── Projection ───────────────────────────────────────────────────────────────────────────────────

func test_after_the_unfold_the_ward_has_one_projected_shield_facing_the_player(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 10)
	assert_null(_projected(held), "%s: nothing while the dish is still unfolding" % mode)
	assert_lt(ship.projector.scale.y, 1.0)
	_ticks(ship, 40)  # 0.83 s > projector_unfold_seconds 0.4
	var shield := _projected(held)
	assert_not_null(shield, "%s: the shield is up after the unfold" % mode)
	assert_eq(held.get_children().filter(func(c: Node) -> bool: return c is EnemyShield).size(), 1)
	assert_true(held.hurt_box.has_absorber())
	assert_true(shield.sustain_mode)
	assert_almost_eq(ship.projector.scale.y, 1.0, 0.001)
	assert_eq(shield.arc_deg, 90.0 if mode == "assault" else 110.0, "%s: the arc" % mode)
	assert_eq(shield.capacity, SHIPPED.shield_capacity)
	assert_eq(shield.turn_rate, SHIPPED.shield_turn_rate)
	assert_eq(shield.radius, 34.0 + 6.0 if held.get_node_or_null("CollisionShape2D") else shield.radius)
	var to_player: Vector2 = (harness.player.global_position - held.global_position).normalized()
	assert_gt(shield.facing().dot(to_player), 0.99, "%s: facing the player" % mode)


func test_the_arc_turns_toward_a_moving_player_at_the_shield_turn_rate() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(held)
	harness.player.global_position = Vector2(1200.0, 360.0)  # due east of the ward
	var before := shield.facing()
	for _i in 6:
		_tick(ship, DT)
		shield._tick(DT)
	var turned := absf(before.angle_to(shield.facing()))
	assert_gt(turned, 0.0, "it turns")
	assert_lte(turned, SHIPPED.shield_turn_rate * DT * 6.0 + 0.001, "no faster than shield_turn_rate")


func test_a_foreign_absorber_on_the_ward_skips_the_projection() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	var other := EnemyShield.new()
	held.add_child(other)
	assert_true(other.attach(held.hurt_box))
	_ticks(ship, 60)
	assert_null(_projected(held), "the slot is taken: no ProjectedShield")
	assert_eq(held.get_children().filter(func(c: Node) -> bool: return c is EnemyShield).size(), 1)


func test_a_real_bullet_from_the_players_side_is_eaten_and_one_from_the_flank_lands() -> void:
	_fast_clock()
	var harness = _harness("open_space")
	harness.player.global_position = Vector2(640.0, 760.0)
	var held := _candidate(harness, Vector2(640.0, 360.0), 50)
	held.health.max_health = 100
	held.health.current_health = 100
	var hull := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 20.0
	hull.shape = circle
	held.hurt_box.add_child(hull)
	var ship := _seeded(harness, Vector2(700.0, 260.0))
	ship.set_physics_process(true)  # real ticks keep the shield sustained
	await _frames(40)
	var shield := _projected(held)
	assert_not_null(shield)
	var absorbed := _count(held.hurt_box.hit_absorbed)
	var front: Node2D = BULLET_SCENE.instantiate()
	harness.root.add_child(front)
	front.global_position = held.global_position + Vector2(0.0, 110.0)
	front.rotation = Vector2.UP.angle_to(Vector2.UP)
	if front.has_signal("expired"):
		front.expired.connect(front.queue_free)
	await _frames(20)
	assert_true(not is_instance_valid(front) or front.is_queued_for_deletion(), "the shield consumed the bullet")
	assert_eq(held.health.current_health, 100, "ward HP unchanged")
	assert_eq(absorbed[0], 1)
	var flank: Node2D = BULLET_SCENE.instantiate()
	harness.root.add_child(flank)
	flank.global_position = held.global_position + Vector2(110.0, 0.0)
	flank.rotation = Vector2.UP.angle_to(Vector2.LEFT)
	if flank.has_signal("expired"):
		flank.expired.connect(flank.queue_free)
	await _frames(20)
	assert_lt(held.health.current_health, 100, "a shot from the flank lands on the hull")


# ── Lapse ────────────────────────────────────────────────────────────────────────────────────────

## Hand-ticks `shield` (it is a child of a ward that nothing frame-steps here) until `done` or `max_s` seconds.
func _tick_shield_until(shield: EnemyShield, max_s: float, done: Callable) -> float:
	var t := 0.0
	while t < max_s and not done.call():
		shield._tick(DT)
		t += DT
	return t


func test_freeing_the_support_lapses_the_shield_and_frees_the_slot() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(held)
	assert_true(held.hurt_box.has_absorber())
	ship.free()
	var t := _tick_shield_until(shield, 2.0, func() -> bool: return not held.hurt_box.has_absorber())
	assert_lte(t, shield.heartbeat + DT * 2.0, "the slot is free within the heartbeat")
	t += _tick_shield_until(shield, 2.0, func() -> bool: return shield.is_queued_for_deletion())
	assert_lte(t, shield.heartbeat + shield.fade_seconds + DT * 3.0, "and the shield frees within heartbeat + fade")


func test_an_emp_disabled_support_lets_the_shield_lapse() -> void:
	_fast_clock()
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(held)
	assert_true(held.hurt_box.has_absorber())
	ship.set_physics_process(true)
	ship.process_mode = Node.PROCESS_MODE_DISABLED  # EMP
	var frames := 0
	while held.hurt_box.has_absorber() and frames < 80:
		await _frames(1)
		frames += 1
	assert_false(held.hurt_box.has_absorber(), "the heartbeat stopped, so the slot is free")
	assert_lte(float(frames) * DT, shield.heartbeat + DT * 3.0)
	await _frames(30)
	assert_true(not is_instance_valid(shield) or shield.is_queued_for_deletion(), "and the shield faded out")


func test_switching_ward_lapses_the_old_shield_and_gives_the_new_ward_one() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var old_ward: BaseEnemy = w[1]
	_ticks(ship, 50)
	var old_shield := _projected(old_ward)
	assert_not_null(old_shield)
	var next_ward := _candidate(harness, Vector2(640.0, 330.0), 50)
	old_ward.queue_free()  # the ward is lost; the brain re-picks on the next tick
	await get_tree().process_frame
	for _i in 60:
		_tick(ship, DT)
		if is_instance_valid(old_shield):
			old_shield._tick(DT)
	assert_eq(_brain(ship).ward, next_ward)
	assert_not_null(_projected(next_ward), "the new ward gets one")
	assert_true(next_ward.hurt_box.has_absorber())


func test_a_ward_switch_without_a_death_lapses_the_old_shield() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var old_ward: BaseEnemy = w[1]
	var brain := _brain(ship)
	_ticks(ship, 50)
	var old_shield := _projected(old_ward)
	var next_ward := _candidate(harness, Vector2(640.0, 330.0), 500)  # far above the 1.3x margin
	_ticks(ship, 150)  # past min_ward_seconds
	assert_eq(brain.ward, next_ward)
	for _i in 60:
		old_shield._tick(DT)
		_tick(ship, DT)
	assert_false(old_ward.hurt_box.has_absorber(), "the old ward's slot is free")
	assert_not_null(_projected(next_ward))


# ── Support + Ram ────────────────────────────────────────────────────────────────────────────────

const _PLATES: Array[StringName] = [&"PlateFront", &"PlateLeft", &"PlateRight"]


## Breaks every live plate through its classifier (a ROCKET hit), then lets the deferred exposure land. The ram is
## typed `Node` and reached by `call`: a static `RamCorvette` reference leaks at exit (see `test_base_enemy.gd`).
func _strip_plates(ram: Node) -> void:
	for plate_name in _PLATES:
		var plate := ram.get_node_or_null(NodePath("Plates/%s" % plate_name))
		if plate != null and is_instance_valid(plate) and plate.call(&"is_alive"):
			var hb := HitBox.new()
			hb.damage_type = HitBox.DamageType.ROCKET
			hb.damage = 9999
			add_child_autofree(hb)
			plate.call(&"_on_hurt_box_area_entered", hb)
	await get_tree().process_frame
	await get_tree().process_frame


func _ram_world(harness) -> Array:
	harness.player.global_position = Vector2(640.0, 760.0)
	var ram := _real(harness, RAM_SCENE, Vector2(640.0, 360.0))
	var ship := _seeded(harness, Vector2(700.0, 260.0))
	return [ship, ram]


func test_pulses_heal_an_exposed_rams_hull_and_never_its_plates() -> void:
	var harness = _harness("open_space")
	var w := _ram_world(harness)
	var ship: SupportShip = w[0]
	var ram: BaseEnemy = w[1]
	await _strip_plates(ram)
	assert_eq(ram.call(&"live_plate_count"), 0)
	var max_hp := ram.health.max_health
	ram.health.current_health = max_hp - 20
	_ticks(ship, 200)
	assert_eq(_brain(ship).ward, ram, "a ram is an ordinary ward")
	assert_gt(ram.health.current_health, max_hp - 20, "the hull is repaired")
	assert_eq(ram.call(&"live_plate_count"), 0, "a broken plate stays broken")


func test_an_armoured_rams_shield_refuses_until_the_last_plate_breaks() -> void:
	var harness = _harness("open_space")
	var w := _ram_world(harness)
	var ship: SupportShip = w[0]
	var ram: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(ram)
	assert_not_null(shield, "the shield is attached to an armoured ram too")
	assert_gt(int(ram.call(&"live_plate_count")), 0)
	var absorbed := _count(shield.absorbed)
	var absorbed_at_hull := _count(ram.hurt_box.hit_absorbed)
	var points := shield.points()
	var hit := _hit_at(ram.global_position + Vector2(0.0, 80.0))  # the player's side
	assert_false(shield.absorbs_hit(hit), "armoured: it refuses")
	ram.hurt_box._on_area_entered(hit)
	assert_eq(shield.points(), points, "points unchanged")
	assert_eq(absorbed[0], 0, "no absorbed signal")
	assert_eq(absorbed_at_hull[0], 0)
	await _strip_plates(ram)
	assert_eq(ram.call(&"live_plate_count"), 0)
	var hit2 := _hit_at(ram.global_position + Vector2(0.0, 80.0))
	ram.hurt_box._on_area_entered(hit2)
	assert_eq(absorbed[0], 1, "exposed: the same hit is absorbed")
	assert_lt(shield.points(), points)


func test_projector_folds_when_the_support_stops_supporting() -> void:
	var harness = _harness("open_space")
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	assert_almost_eq(ship.projector.scale.y, 1.0, 0.001)
	held.free()
	_ticks(ship, 30)  # 0.5 s > projector_fold_seconds
	assert_almost_eq(ship.projector.scale.y, 0.0, 0.001)
	assert_false(ship.tether.visible)


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


# ── Emergency escort (t13, plan §2.14) ───────────────────────────────────────────────────────────

const SNIPER_SCENE: PackedScene = preload("res://assault/scenes/enemies/sniper/sniper.tscn")


## The brain's phase value by name (`Phase` is the brain's enum).
func _phase(name: String) -> int:
	return SupportShipBrain.Phase[name]


func _set_hp(e: BaseEnemy, hp: int) -> void:
	e.health.set_health(hp)


func _ward_mover(e: BaseEnemy) -> EnemyMover:
	return e.get_node("EnemyMover") as EnemyMover


## `_repair_world` (ward at 100/100, (640, 360); player (640, 760); support seeded at (700, 260)) with a mover cap on the
## ward, no repair pulses (they would move the HP the rows set) and no Assault budget.
func _escort_world(harness) -> Array:
	var w := _repair_world(harness, 100)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ward_mover(held).max_speed = 200.0
	ship.config.repair_budget = 0
	ship.config.engage_seconds = 1000.0
	return w


func _escort_phase(ship: SupportShip) -> int:
	return _brain(ship).phase


func test_escort_starts_at_34_percent_and_not_at_36(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 36)
	_ticks(ship, 10)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: 36 %% is no emergency" % mode)
	_set_hp(held, 34)
	_ticks(ship, 1)
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: 34 %% starts the escort on the next tick" % mode)
	var nudge: Vector2 = _ward_mover(held)._nudge
	var away: Vector2 = (held.global_position - harness.player.global_position).normalized()
	assert_lt(rad_to_deg(absf(nudge.angle_to(away))), 5.0, "%s: the nudge points away from the player" % mode)
	assert_almost_eq(nudge.length(), 1.25 * 200.0, 0.5, "%s: at 1.25x the ward's max speed" % mode)


## Distance gained (+) or lost (-) to the player over 1 s of a ward whose brain seeks the player at full speed.
func _seek_run(mode: String, with_support: bool) -> float:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(640.0, 760.0)
	var held := _candidate(harness, Vector2(640.0, 360.0), 50)
	held.health.max_health = 100
	held.health.current_health = 100
	_ward_mover(held).max_speed = 200.0
	(held.get_node("Brain") as Node).set("desired_velocity", Vector2(0.0, 200.0))
	_set_hp(held, 34)
	var ship: SupportShip = null
	if with_support:
		ship = _seeded(harness, Vector2(700.0, 260.0))
		ship.config.repair_budget = 0
		ship.config.engage_seconds = 1000.0
	var start := held.global_position.distance_to(harness.player.global_position)
	for _i in 60:
		if ship != null:
			_tick(ship, DT)
		_tick(held, DT)
	var gained := held.global_position.distance_to(harness.player.global_position) - start
	harness.root.free()
	return gained


func test_a_ward_seeking_the_player_gains_distance_during_the_escort_and_loses_it_without(mode: String = use_parameters(["open_space", "assault"])) -> void:
	assert_gt(_seek_run(mode, true), 10.0, "%s: towed away from the player" % mode)
	assert_lt(_seek_run(mode, false), -100.0, "%s: control: with no support it closes" % mode)


func test_the_support_reaches_the_interpose_point_within_1_5_s(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 30)
	_ticks(ship, 90)
	var point: Vector2 = held.global_position + (harness.player.global_position - held.global_position).normalized() * SHIPPED.interpose_distance
	if mode == "assault":
		var r := EnemyWorld.view_rect(get_tree()).grow(-SHIPPED.view_margin)
		point = Vector2(clampf(point.x, r.position.x, r.end.x), clampf(point.y, r.position.y, r.end.y))
	assert_eq(_escort_phase(ship), _phase("ESCORT"))
	assert_lt(ship.global_position.distance_to(point), 40.0, "%s: within 40 px of the interpose point" % mode)
	assert_lt(ship.global_position.distance_to(harness.player.global_position),
			held.global_position.distance_to(harness.player.global_position), "%s: between the ward and the player" % mode)


# ── Telegraphs are not moved ─────────────────────────────────────────────────────────────────────

## A real `scene` ward driven (hand-ticked, with a support beside it) to the first tick of one of `refusing`'s phases; its
## HP is then set to 30 %. Through those phases every tick the support's escort is checked: the tow is refused (nothing
## lands on the ward's mover), and the ward's position is recorded. `with_support` false runs the identical ward alone.
## Returns {reached, escorting, nudged, path, anchor_gap_start, anchor_gap_end, accepted_after, drift}.
func _telegraph_run(mode: String, scene: PackedScene, ward_pos: Vector2, rng_seed: int, refusing: Array[String],
		with_support: bool, check_release: bool) -> Dictionary:
	var harness = _harness(mode)
	harness.player.global_position = Vector2(300.0, 360.0) if scene == SNIPER_SCENE else Vector2(640.0, 560.0)
	var ward := scene.instantiate() as BaseEnemy
	var wbrain: Node = ward.get_node("Brain")
	wbrain.set("start_engaged", true)
	wbrain.set("rng_seed", rng_seed)
	ward.config.engage_seconds = 1000.0
	ward.global_position = ward_pos
	harness.root.add_child(ward)
	ward.set_physics_process(false)
	var ship: SupportShip = null
	if with_support:
		ship = _seeded(harness, ward_pos + Vector2(60.0, -40.0))
		ship.config.repair_budget = 0
		ship.config.engage_seconds = 1000.0
	var phases: Dictionary = (wbrain.get_script() as GDScript).get_script_constant_map()["Phase"]
	var refusing_ids: Array[int] = []
	for n in refusing:
		refusing_ids.append(int(phases[n]))
	var result := {"reached": false, "escorting": true, "nudged": 0, "path": [] as Array[Vector2],
			"gap_start": 0.0, "gap_end": 0.0, "accepted_after": false, "drift": 0.0}
	var t := 0.0
	while t < 15.0 and int(wbrain.get("phase")) != refusing_ids[0]:
		if ship != null:
			_tick(ship, DT)
		_tick(ward, DT)
		t += DT
	if int(wbrain.get("phase")) != refusing_ids[0]:
		harness.root.free()
		return result
	result["reached"] = true
	# A sniper settles far from the player (past `escort_safe_distance`, which would end the escort at once): bring the
	# player in once the telegraph has begun. Its lock point is already fixed.
	var to_player: Vector2 = harness.player.global_position - ward.global_position
	if to_player.length() > 450.0:
		harness.player.global_position = ward.global_position + to_player.normalized() * 400.0
	_set_hp(ward, int(ward.health.max_health * 0.3))
	var start := ward.global_position
	var n := 0
	while int(wbrain.get("phase")) in refusing_ids and n < 600:
		n += 1
		if ship != null:
			_tick(ship, DT)
			var brain := _brain(ship)
			result["escorting"] = result["escorting"] and brain.phase == _phase("ESCORT")
			if _ward_mover(ward)._nudge != Vector2.ZERO:
				result["nudged"] += 1
			if n == 1:
				result["gap_start"] = ship.global_position.distance_to(brain.anchor)
			result["gap_end"] = ship.global_position.distance_to(brain.anchor)
		_tick(ward, DT)
		result["path"].append(ward.global_position - start)
		result["drift"] = maxf(result["drift"], ward.global_position.distance_to(start))
	if check_release and ship != null:
		_tick(ship, DT)
		result["accepted_after"] = _ward_mover(ward)._nudge != Vector2.ZERO
	harness.root.free()
	return result


func test_a_locking_sniper_ward_refuses_the_tow_and_the_support_still_interposes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var run := _telegraph_run(mode, SNIPER_SCENE, Vector2(800.0, 360.0), 4242, ["LOCK", "FIRE"], true, true)
	assert_true(run["reached"], "%s: LOCK was reached" % mode)
	assert_true(run["escorting"], "%s: ESCORT held through LOCK and FIRE" % mode)
	assert_eq(run["nudged"], 0, "%s: the tow was refused every tick" % mode)
	assert_lte(run["drift"], 1.0, "%s: the muzzle stays within 1 px" % mode)
	assert_lt(run["gap_end"], run["gap_start"], "%s: the support still closes on its interpose point" % mode)
	assert_true(run["accepted_after"], "%s: the first tick after FIRE the tow is accepted again" % mode)


func test_a_winding_up_ram_ward_refuses_the_tow_and_stays_on_its_own_path(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var baseline := _telegraph_run(mode, RAM_SCENE, Vector2(300.0, 100.0), 1717, ["WIND_UP"], false, false)
	var run := _telegraph_run(mode, RAM_SCENE, Vector2(300.0, 100.0), 1717, ["WIND_UP"], true, false)
	assert_true(run["reached"] and baseline["reached"], "%s: WIND_UP was reached" % mode)
	assert_gt((run["path"] as Array).size(), 20, "%s: sanity: a real wind-up" % mode)
	assert_true(run["escorting"], "%s: ESCORT held through WIND_UP" % mode)
	assert_eq(run["nudged"], 0, "%s: the tow was refused every tick" % mode)
	assert_eq((run["path"] as Array).size(), (baseline["path"] as Array).size(), "%s: same length" % mode)
	var gap := 0.0
	for i in mini((run["path"] as Array).size(), (baseline["path"] as Array).size()):
		gap = maxf(gap, (run["path"][i] as Vector2).distance_to(baseline["path"][i]))
	assert_lte(gap, 1.0, "%s: within 1 px of its own untowed path" % mode)
	assert_lt(run["gap_end"], run["gap_start"], "%s: the support still closes on its interpose point" % mode)


## Control: the same refusal row fails when the ward answers true (a plain fixture brain in a telegraph-less phase).
func test_a_tow_is_accepted_when_the_ward_brain_allows_it(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 30)
	_ticks(ship, 1)
	assert_ne(_ward_mover(held)._nudge, Vector2.ZERO, "%s: a free ward is towed" % mode)


# ── The bubble ───────────────────────────────────────────────────────────────────────────────────

func test_the_escort_widens_the_shield_to_a_bubble_and_restores_it(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(held)
	assert_not_null(shield)
	var normal_arc := 90.0 if mode == "assault" else 110.0
	assert_eq(shield.arc_deg, normal_arc)
	var behind := held.global_position + Vector2(0.0, -80.0)
	var before := held.health.current_health
	held.hurt_box._on_area_entered(_hit_at(behind, 5))
	assert_eq(held.health.current_health, before - 5, "%s: outside the normal arc a hit from behind lands" % mode)
	_set_hp(held, 34)
	_ticks(ship, 1)
	assert_eq(_escort_phase(ship), _phase("ESCORT"))
	assert_eq(shield.arc_deg, 360.0, "%s: a bubble during the escort" % mode)
	var absorbed := _count(shield.absorbed)
	held.hurt_box._on_area_entered(_hit_at(behind, 5))
	assert_eq(held.health.current_health, 34, "%s: the same hit is now absorbed" % mode)
	assert_eq(absorbed[0], 1)
	_set_hp(held, 60)
	_ticks(ship, 1)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"))
	assert_eq(shield.arc_deg, normal_arc, "%s: restored after the escort" % mode)
	held.hurt_box._on_area_entered(_hit_at(behind, 5))
	assert_eq(held.health.current_health, 55, "%s: and the same hit lands again" % mode)


func test_a_ward_dropped_mid_escort_gets_its_arc_back() -> void:
	var harness = _harness("open_space")
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var shield := _projected(held)
	_set_hp(held, 34)
	_ticks(ship, 1)
	assert_eq(shield.arc_deg, 360.0)
	held.suspend_ai()  # a rail took it: the ward is lost
	_ticks(ship, 1)
	assert_ne(_escort_phase(ship), _phase("ESCORT"))
	assert_eq(shield.arc_deg, SHIPPED.shield_arc_deg, "the dropped ward's shield is back to its arc")


# ── The end ──────────────────────────────────────────────────────────────────────────────────────

func test_the_escort_ends_at_50_percent_and_the_cooldown_blocks_a_re_trigger(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 34)
	_ticks(ship, 30)
	assert_eq(_escort_phase(ship), _phase("ESCORT"))
	_set_hp(held, 49)
	_ticks(ship, 2)
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: 49 %% is not yet safe" % mode)
	_set_hp(held, 50)
	_ticks(ship, 1)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: 50 %% releases" % mode)
	_set_hp(held, 34)
	_ticks(ship, 300)  # 5 s of the 6 s cooldown
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: the cooldown holds" % mode)
	_ticks(ship, 80)
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: and expires" % mode)


func test_the_escort_ends_when_the_ward_is_700_px_from_the_player(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 34)
	_ticks(ship, 10)
	assert_eq(_escort_phase(ship), _phase("ESCORT"))
	harness.player.global_position = held.global_position + Vector2(0.0, 699.0)
	_ticks(ship, 2)
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: 699 px is not safe yet" % mode)
	harness.player.global_position = held.global_position + Vector2(0.0, 700.0)
	_ticks(ship, 1)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: 700 px ends it" % mode)


func test_the_escort_ends_after_4_s(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_set_hp(held, 34)
	_ticks(ship, 1 + 235)
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: still escorting at 3.9 s" % mode)
	_ticks(ship, 10)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: 4 s ends it" % mode)


func test_a_boosting_ward_refuses_the_tow_and_the_escort_waits(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _harness(mode)
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ward_mover(held).boost(Vector2.DOWN, 100.0, 100.0)
	_set_hp(held, 34)
	for _i in 200:  # 3.3 s
		_tick(ship, DT)
		assert_eq(_ward_mover(held)._nudge, Vector2.ZERO, "no nudge on a boosting ward")
	assert_eq(_escort_phase(ship), _phase("ESCORT"), "%s: the escort persists" % mode)
	_ward_mover(held)._boost_left = 0.0
	_ticks(ship, 1)
	assert_ne(_ward_mover(held)._nudge, Vector2.ZERO, "%s: the tow lands once it stops boosting" % mode)
	_ticks(ship, 60)
	assert_eq(_escort_phase(ship), _phase("FOLLOW"), "%s: and the timeout ends it" % mode)


func test_the_tow_beam_is_thicker_during_the_escort() -> void:
	var harness = _harness("open_space")
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	_ticks(ship, 50)
	var normal := ship.tether.width
	_set_hp(held, 34)
	_ticks(ship, 1)
	assert_gt(ship.tether.width, normal, "thicker while towing")
	_set_hp(held, 60)
	_ticks(ship, 1)
	assert_eq(ship.tether.width, normal, "back to normal after")


func test_escort_does_not_keep_a_budget_expiry_from_disengaging() -> void:
	var harness = _harness("assault")
	var w := _escort_world(harness)
	var ship: SupportShip = w[0]
	var held: BaseEnemy = w[1]
	ship.config.engage_seconds = 0.5
	_brain(ship).budget = null
	_brain(ship)._started = false
	_set_hp(held, 34)
	_ticks(ship, 60)
	assert_eq(_escort_phase(ship), _phase("DISENGAGE"), "the budget is not deferred by an escort")
	assert_eq(_projected(held).arc_deg if _projected(held) != null else 90.0, 90.0)


# ══ t15: hub idle (docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.16; task cmv9szqmc002rqs2xfz6xg6v0) ═════════════
#
# Cold-start helper: unlike `_spawn()` (which sets `start_engaged = true`), this leaves the brain to decide for itself -
# Open Space starts IDLE, Assault starts in combat. The stub player is stationary unless a row moves it.

const FAR_AWAY := Vector2(100000.0, 100000.0)
const IdlePhase := SupportShipBrain.Phase


func _cold(harness, pos: Vector2, player_pos: Vector2, anchor: Vector2 = Vector2.INF) -> SupportShip:
	harness.player.global_position = player_pos
	harness.player.velocity = Vector2.ZERO
	var ship := SUPPORT_SCENE.instantiate() as SupportShip
	var brain := _brain(ship)
	brain.rng.seed = FOLLOW_SEED
	brain.patrol_anchor = anchor
	ship.global_position = pos
	harness.root.add_child(ship)
	ship.set_physics_process(false)
	ship.set_process(false)
	return ship


func _calm(p: int) -> bool:
	return p == IdlePhase.IDLE or p == IdlePhase.NOTICING or p == IdlePhase.RETURNING


func test_the_idle_phases_are_appended_so_the_earlier_values_do_not_move() -> void:
	assert_eq(IdlePhase.SEEK_WARD, 0)
	assert_eq(IdlePhase.DISENGAGE, 3)
	assert_eq(IdlePhase.IDLE, 4)
	assert_eq(IdlePhase.NOTICING, 5)
	assert_eq(IdlePhase.RETURNING, 6)


## §2.16: lose_radius > escort_safe_distance + follow_distance + interpose_distance (700 + 150 + 90 = 940).
func test_the_idle_radii_clear_the_largest_distance_its_own_cycle_opens() -> void:
	var c: SupportShipConfig = SHIPPED
	assert_eq(c.perceive_radius, 600.0)
	assert_eq(c.lose_radius, 1300.0)
	assert_eq(c.notice_time, 0.35)
	assert_eq(c.idle_radius, 150.0)
	assert_eq(c.idle_speed, 0.5)
	var opened := c.escort_safe_distance + c.follow_distance + c.interpose_distance
	assert_eq(opened, 940.0)
	assert_gt(c.lose_radius, opened, "lose_radius %.0f vs the distance the cycle opens %.0f" % [c.lose_radius, opened])
	assert_gt(c.lose_radius, c.perceive_radius, "AnchorIdle's hysteresis margin")


func test_open_space_cold_start_begins_idle_and_assault_starts_in_combat() -> void:
	var h = _harness("open_space")
	var ship := _cold(h, Vector2(321.0, -654.0), FAR_AWAY)
	_tick(ship, DT)
	assert_eq(_brain(ship).phase, IdlePhase.IDLE, "Open Space starts on patrol")
	assert_not_null(_brain(ship).anchor_idle)
	assert_eq(_brain(ship).patrol_anchor, Vector2(321.0, -654.0), "an unset anchor defaults to the spawn position")
	for node in get_tree().get_nodes_in_group(&"player"):
		node.remove_from_group(&"player")
	var a = _harness("assault")
	var ship2 := _cold(a, Vector2(640.0, 100.0), Vector2(640.0, 560.0))
	_tick(ship2, DT)
	assert_eq(_brain(ship2).phase, IdlePhase.SEEK_WARD, "Assault always starts in combat")
	assert_null(_brain(ship2).anchor_idle, "no AnchorIdle is built in Assault")


func test_start_engaged_skips_the_idle() -> void:
	var h = _harness("open_space")
	var ship := _spawn(h, Vector2(100.0, 100.0))
	h.player.global_position = FAR_AWAY
	_tick(ship, DT)
	assert_null(_brain(ship).anchor_idle)
	assert_false(_calm(_brain(ship).phase), "an engaged support never patrols")


func test_idle_stays_on_its_ring_and_picks_no_ward() -> void:
	var h = _harness("open_space")
	var anchor := Vector2(500.0, -400.0)
	_candidate(h, anchor + Vector2(60.0, 0.0), 80)  # a candidate right beside it: patrolling ignores it
	var ship := _cold(h, anchor + Vector2(20.0, 0.0), FAR_AWAY, anchor)
	var worst := 0.0
	for _i in int(20.0 / DT):
		_tick(ship, DT)
		assert_eq(_brain(ship).phase, IdlePhase.IDLE)
		worst = maxf(worst, ship.global_position.distance_to(anchor))
	assert_lte(worst, SHIPPED.idle_radius + 30.0, "worst %.1f px from the anchor" % worst)
	assert_false(_brain(ship).has_ward(), "no ward while patrolling")


func test_perceiving_the_player_notices_for_a_beat_then_fights() -> void:
	var h = _harness("open_space")
	var ship := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius - 100.0))
	var seen: Array[int] = []
	var noticing_ticks := 0
	for _i in int(1.0 / DT):
		_tick(ship, DT)
		if _brain(ship).phase == IdlePhase.NOTICING:
			noticing_ticks += 1
		if seen.is_empty() or seen[-1] != _brain(ship).phase:
			seen.append(_brain(ship).phase)
	assert_eq(seen[0], IdlePhase.NOTICING, "NOTICING for a beat first")
	assert_eq(seen[1], IdlePhase.SEEK_WARD, "then it looks for a ward (phases %s)" % [seen])
	assert_almost_eq(noticing_ticks * DT, SHIPPED.notice_time, 2.0 * DT, "for notice_time")


func test_a_player_outside_perceive_radius_is_not_noticed() -> void:
	var h = _harness("open_space")
	var ship := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius + SHIPPED.idle_radius + 100.0))
	for _i in int(3.0 / DT):
		_tick(ship, DT)
		assert_eq(_brain(ship).phase, IdlePhase.IDLE)


func test_after_noticing_it_takes_a_ward_beside_it() -> void:
	var h = _harness("open_space")
	var ally := _candidate(h, Vector2(700.0, 0.0), 80)
	var ship := _cold(h, Vector2(640.0, 0.0), Vector2(640.0, SHIPPED.perceive_radius - 100.0))
	_ticks(ship, int(1.0 / DT))
	assert_eq(_brain(ship).phase, IdlePhase.FOLLOW)
	assert_eq(_brain(ship).ward, ally)


func test_beyond_lose_radius_it_goes_home_drops_its_ward_and_can_fight_again() -> void:
	var h = _harness("open_space")
	var anchor := Vector2.ZERO
	var ally := _candidate(h, Vector2(200.0, 0.0), 80)
	var ship := _cold(h, anchor + Vector2(100.0, 0.0), Vector2(100.0, 400.0), anchor)
	_ticks(ship, int(2.0 / DT))
	assert_eq(_brain(ship).phase, IdlePhase.FOLLOW, "sanity: in combat with a ward")
	ship.global_position += Vector2(0.0, 700.0)  # well away from home, so there is a way back to walk
	ally.global_position += Vector2(0.0, 700.0)
	h.player.global_position = FAR_AWAY
	var saw_returning := false
	var home := false
	for _i in int(60.0 / DT):
		_tick(ship, DT)
		saw_returning = saw_returning or _brain(ship).phase == IdlePhase.RETURNING
		if _brain(ship).phase == IdlePhase.IDLE:
			home = true
			break
	assert_true(saw_returning, "it passes through RETURNING on the way home")
	assert_true(home, "and reaches IDLE")
	assert_false(_brain(ship).has_ward(), "the ward was dropped")
	assert_almost_eq((ship.get_node("Projector") as Node2D).scale.y, 0.0, 1e-3, "the dish is folded")
	h.player.global_position = ship.global_position + Vector2(SHIPPED.perceive_radius - 50.0, 0.0)
	_ticks(ship, int(1.0 / DT))
	assert_false(_calm(_brain(ship).phase), "and fights again")


## Hysteresis: a player between perceive_radius and lose_radius never sends a fighting support home.
func test_a_player_between_the_radii_does_not_send_it_home() -> void:
	var h = _harness("open_space")
	_candidate(h, Vector2(60.0, 0.0), 80)
	var ship := _cold(h, Vector2.ZERO, Vector2(0.0, 400.0), Vector2.ZERO)
	_ticks(ship, int(2.0 / DT))
	assert_false(_calm(_brain(ship).phase), "sanity: in combat")
	for _i in int(2.0 / DT):
		h.player.global_position = ship.global_position + Vector2(SHIPPED.lose_radius - 50.0, 0.0)
		_tick(ship, DT)
		assert_false(_brain(ship).phase == IdlePhase.RETURNING, "inside lose_radius it keeps fighting")


## It has no protected phase: an escort in progress gives way to RETURNING the moment the player is lost.
func test_returning_interrupts_nothing_not_even_an_escort() -> void:
	var h = _harness("open_space")
	var ally := _candidate(h, Vector2(0.0, 0.0), 80)
	var ship := _cold(h, Vector2(60.0, -40.0), Vector2(0.0, 400.0), Vector2(560.0, -40.0))
	_ticks(ship, int(1.0 / DT))
	_set_hp(ally, 3)
	_ticks(ship, 5)
	assert_eq(_brain(ship).phase, IdlePhase.ESCORT, "sanity: escorting")
	h.player.global_position = FAR_AWAY
	_ticks(ship, 2)
	assert_eq(_brain(ship).phase, IdlePhase.RETURNING, "no protected phase")
	assert_false(_brain(ship).has_ward())


# ── Level 1 attack-in-budget (Phase 5 t17; epic plan §2.18, task plan docs/plans/cmv9szqmi002zqs2x3cd8f942/) ──────────
#
# Every support level 1 places has a `ProjectedShield` on a ward (`is_supporting()` true: ward valid, in `beam_range`,
# both inside the view bands) while its Assault budget still has time left. Each placed spawn replays only
# `rel - 1 s .. rel + engage_seconds + 2 s` of its own section through a real `WaveManager` at the 8x clock
# (`tests/helpers/level1_slice_replay.gd`) — the ram it is placed with arrives in the same wave — and stops as soon as
# the shield is up (or the budget has run out).

const Slice := preload("res://tests/helpers/level1_slice_replay.gd")


## Replays `row`'s slice and reports `{ "targets", "active", "supporting_at", "supporting_left", "ward", "expired" }`,
## times from the support's spawn. `tweak` edits the placed support's private config.
func _support_slice(row: Dictionary, tweak: Callable = Callable()) -> Dictionary:
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	var to: float = float(row["rel"]) + SHIPPED.engage_seconds + Slice.POST_ROLL
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, to)
	var seen := {}
	var observe := func(ship: BaseEnemy, t: float) -> bool:
		if ship == null:
			seen["left"] = true
			return true
		if not seen.has("spawn"):
			seen["spawn"] = t
		var b := ship.get_node("Brain") as SupportShipBrain
		if b.budget == null:
			return false
		seen["active"] = b.budget.active
		var left := b.budget.remaining()
		if left > 0.0 and b.is_supporting() and is_instance_valid(b.shield) and b.shield.name == &"ProjectedShield" \
				and b.shield.get_parent() == b.ward and b.ward.hurt_box.has_absorber():
			seen["supporting_at"] = t - float(seen["spawn"])
			seen["supporting_left"] = left
			seen["ward"] = b.ward.scene_file_path.get_file()
			return true
		if left <= 0.0 or b.phase == SupportShipBrain.Phase.DISENGAGE:
			seen["expired"] = true
			return true
		return false
	var out: Dictionary = await Slice.new().run(self, waves, to - from, WaveBuilder.SUPPORT_SHIP, observe, tweak)
	seen["targets"] = out["targets"]
	return seen


func test_every_level1_support_spawn_projects_a_shield_inside_its_budget() -> void:
	var rows := Slice.placed(WaveBuilder.SUPPORT_SHIP)
	assert_eq(rows.size(), 2, "sanity: level 1 places two supports")
	_fast_clock()
	for row: Dictionary in rows:
		var label := "%s support at %.1f s" % [row["section"], row["rel"]]
		var seen := await _support_slice(row)
		gut.p("%s: %s" % [label, seen])
		assert_eq(int(seen["targets"]), 1, "%s: exactly one support in its slice" % label)
		assert_true(bool(seen.get("active", false)), "%s: the Assault budget is live" % label)
		assert_true(seen.has("supporting_at"), "%s: projects a shield on a ward before its budget expires" % label)
		assert_gt(float(seen.get("supporting_left", 0.0)), 0.0, "%s: with budget left" % label)


## Boundary: the same predicate on the planet_approach spawn with a 2.5 s budget (private config) fails — the support
## needs about 3 s to reach its ram and unfold — so the row above can fail.
func test_a_level1_support_with_a_2_5_s_budget_never_shields_in_it() -> void:
	var rows := Slice.placed(WaveBuilder.SUPPORT_SHIP)
	assert_eq(rows[1]["section"], &"planet_approach", "sanity: the second placed support is planet_approach's")
	_fast_clock()
	var seen := await _support_slice(rows[1], func(ship: Node) -> void:
		(ship as SupportShip).config.engage_seconds = 2.5)
	gut.p("planet_approach support, engage 2.5: %s" % [seen])
	assert_eq(int(seen["targets"]), 1, "sanity: the support spawned once")
	assert_true(bool(seen.get("active", false)), "sanity: the Assault budget is live")
	assert_true(seen.has("expired"), "sanity: its budget ran out inside the run")
	assert_false(seen.has("supporting_at"), "no shield on a ward with budget left")
	assert_eq(SHIPPED.engage_seconds, 9.0, "the shipped config is untouched")
