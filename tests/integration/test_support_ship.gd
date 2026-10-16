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

func test_it_holds_near_an_ally_at_follow_distance(mode: String = use_parameters(["open_space", "assault"])) -> void:
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


func test_it_closes_on_a_far_ally_and_picks_the_nearest_of_two(mode: String = use_parameters(["open_space", "assault"])) -> void:
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


func test_with_no_ally_it_drifts_in_place(mode: String = use_parameters(["open_space", "assault"])) -> void:
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
