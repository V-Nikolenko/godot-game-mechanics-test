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
