## The same enemy behaviour spec runs automatically in both an Open Space and an Assault test
## world (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §4 row test_enemy_dual_mode.gd, P-17,
## task t12-dual-harness). `tests/helpers/enemy_ai_harness.gd`'s `open_space()` and `assault()`
## builders differ only in whether an `ArenaCamera` is in the tree; the spec itself never branches
## on the mode except to decide which pass criterion applies (P-17: assertions are stated relative
## to the constraint).
##
## Covers the fixture brain (`tests/helpers/fixture_brain.gd` / `fixture_enemy.tscn`, from t10) and,
## as of t14, the real ported Razor Drone
## (`assault/scenes/enemies/razor_drone/razor_drone_brain.gd`): the second proof that
## the harness — not just the fixture — carries a real enemy's behaviour spec across both modes.
## Since Phase 2 (t10) the Razor Drone runs with the corridor on (`constraint_mode = AUTO`), so its
## cases assert "identical relative to the constraint": mid-corridor, where the constraint never
## engages, its Assault and Open Space runs still produce identical motion for identical inputs.
##
## Every case drives its enemy by hand through `_tick()` (see below) with a fixed `delta`, never
## an engine frame or a `Timer` — deterministic per `docs/plans/.../3-plan.md`'s test-plan rules.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const RAZOR_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/razor_drone/razor_drone.tscn")
const RAZOR_CONFIG: RazorDroneConfig = \
		preload("res://assault/scenes/enemies/razor_drone/razor_drone_config.tres")

const DT := 1.0 / 60.0

const ORBIT_RADIUS := 100.0
const ORBIT_CORRECT_SPEED := 220.0
const ORBIT_ANGULAR_SPEED := 2.0  # rad/s
const ORBIT_STEPS := 240  # 4 s: several revolutions at ORBIT_ANGULAR_SPEED

## An above-screen spawn (wave_manager.gd's real shape; see AssaultCorridorConstraint's class doc)
## well past the corridor's hard band, with a generous frame budget to reach the visible rect at
## the constraint's entry_speed floor (60 px/s needs ~480 frames to close 480 px).
const ABOVE_SCREEN_SPAWN := Vector2(500.0, -860.0)
const ENTRY_TIMEOUT_FRAMES := 600


func _brain(entity: Node) -> EnemyBrain:
	return entity.get_node("Brain") as EnemyBrain


func _razor_brain(entity: Node) -> RazorDroneBrain:
	return entity.get_node("Brain") as RazorDroneBrain


## Runs one manual physics tick, then replaces whatever `move_and_slide()` actually displaced the
## actor by with an exact `delta * velocity` integration. `move_and_slide()` reads
## `get_physics_process_delta_time()` internally rather than the `delta` passed in, and that value
## is not reliable when driven by hand outside a real physics substep
## (`test_razor_drone.gd`'s harness notes) — confirmed here too: an early version of the
## corridor-entry case below passed alone and failed inside the full suite, purely from that drift.
## `velocity` itself is unaffected (`EnemyMover` assigns it directly, before `move_and_slide` ever
## runs), so re-deriving position from it is exact and suite-order-independent.
func _tick(entity: BaseEnemy, delta: float) -> void:
	var before := entity.global_position
	entity._physics_process(delta)
	entity.global_position = before + entity.velocity * delta


## `harness.root` must already be in the tree (add_child_autofree) before this is called, so the
## fixture's AUTO EnemyMover resolves the harness's constraint (or none) the same way the real game
## does.
func _spawn_orbiter(harness, pos: Vector2) -> BaseEnemy:
	var entity := FIXTURE_ENEMY.instantiate() as BaseEnemy
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # driven only by hand below (test_razor_drone.gd's technique)
	return entity


## Same shape as `_spawn_orbiter()`, for the real Razor Drone. Its AUTO `EnemyMover` resolves the
## harness's constraint (or none) through the real lookup, exactly as in the game.
func _spawn_razor_drone(harness, pos: Vector2, rng_seed: int = 0) -> RazorDrone:
	var entity := RAZOR_SCENE.instantiate() as RazorDrone
	entity.global_position = pos
	if rng_seed != 0:
		_razor_brain(entity).rng_seed = rng_seed
	_razor_brain(entity).start_engaged = true  # pre-t11: predates the hub idle (test_razor_drone.gd)
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # driven only by hand below (test_razor_drone.gd's technique)
	return entity


## AssaultCorridorConstraint's own visible rect grown by its own soft_band, read from a probe
## instance rather than duplicated, so a tuning change to either number cannot desync this test.
func _soft_band_rect() -> Rect2:
	var probe := AssaultCorridorConstraint.new()
	return probe._visible_rect().grow(probe.soft_band)


## The shared spec (P-17): orbits a fixture enemy around the harness's player by driving
## `EnemyMover`'s `orbit()` formula (`Steering.orbit`) through the fixture brain every tick, for
## both harnesses in turn. The player sits dead centre of the corridor, far from every edge, so an
## Assault run's constraint never actually engages — proving the same spec, unmodified, produces
## the same held orbit in both modes. (The separate entry test below exercises the constraint while
## it is actively clamping; t14's ported Razor Drone drives an orbit near the corridor edge, where
## both branches of this assertion are exercised for real.)
func _run_orbit_spec(harness) -> void:
	add_child_autofree(harness.root)
	var player_pos := Vector2(640.0, 360.0)  # dead centre: far from every corridor edge
	harness.player.global_position = player_pos

	var entity := _spawn_orbiter(harness, player_pos + Vector2(ORBIT_RADIUS, 0.0))
	var brain := _brain(entity)

	var angle := 0.0
	var max_dist := 0.0
	var min_dist := INF
	for _i in ORBIT_STEPS:
		angle += ORBIT_ANGULAR_SPEED * DT
		brain.desired_velocity = Steering.orbit(
			entity.global_position, harness.player.global_position, ORBIT_RADIUS, angle, ORBIT_CORRECT_SPEED)
		_tick(entity, DT)
		var dist: float = entity.global_position.distance_to(harness.player.global_position)
		max_dist = maxf(max_dist, dist)
		min_dist = minf(min_dist, dist)

	var within_tolerance: bool = max_dist <= ORBIT_RADIUS + ORBIT_CORRECT_SPEED
	var clamped_but_contained: bool = harness.is_assault and _soft_band_rect().has_point(entity.global_position)
	assert_true(within_tolerance or clamped_but_contained,
		"%s: orbit must hold the radius within tolerance, or (Assault only) stay inside the " %
		harness.label +
		"corridor's soft band when clamped (max_dist=%s, radius=%s)" % [max_dist, ORBIT_RADIUS])
	assert_lt(min_dist, ORBIT_RADIUS,
		"%s: sanity — the correction actually moves the enemy, not frozen at the radius" % harness.label)


## The parameter is a bare label, never the harness itself: GDScript re-evaluates a default
## argument expression on every call, including calls `use_parameters()` discards after the first,
## so building `EnemyAIHarness`'s Node2D subtree directly inside the `use_parameters([...])` array
## constructs (and immediately abandons) a second, unparented copy on every later call — a real,
## silent Node leak `scripts/check-test-leaks.sh` catches. Building the harness from the label
## inside the test body means exactly one is ever constructed per call, and it is always the one
## `add_child_autofree` frees at that call's teardown.
func test_orbit_behaviour_matches_the_constraint(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	_run_orbit_spec(harness)


## Assault-only (P-17's second requirement): a spawn above the screen, well past the corridor's
## hard band, must be pulled into the visible rect even though the brain keeps requesting further
## away (outward) every tick — the constraint's "not yet entered" rule discards the outward request
## and floors the inward one at entry_speed, regardless of what the brain asks for.
func test_assault_harness_above_screen_spawn_enters_the_corridor() -> void:
	var harness = HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)

	var entity := _spawn_orbiter(harness, ABOVE_SCREEN_SPAWN)
	var brain := _brain(entity)
	brain.desired_velocity = Vector2(0.0, -999.0)  # keep requesting further away, straight up

	var visible := AssaultCorridorConstraint.new()._visible_rect()
	assert_false(visible.has_point(entity.global_position), "sanity: the spawn starts outside the corridor")

	var entered := false
	for _i in ENTRY_TIMEOUT_FRAMES:
		_tick(entity, DT)
		if visible.has_point(entity.global_position):
			entered = true
			break

	assert_true(entered,
		"an above-screen spawn must enter the corridor within %d frames despite an outward request" %
		ENTRY_TIMEOUT_FRAMES)


# ── The Razor Drone: identical relative to the constraint (t10) ──────────────────────────────────

## Phase 2 turned the corridor on for the Razor Drone (`constraint_mode = AUTO`, DECISIONS D5), so the
## Phase 1 claim "identical in both modes" became "identical relative to the constraint": mid-corridor
## the constraint never engages and the orbit-centre clamp is a no-op, so the same seed still flies the
## same orbit. Near an edge the two modes differ on purpose (test_razor_drone.gd covers that case). 30
## frames (0.5 s) is safely under the 1 s minimum orbit window, so both runs are still orbiting.
func test_razor_drone_orbit_mid_corridor_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	add_child_autofree(open_harness.root)
	open_harness.player.global_position = Vector2(640.0, 360.0)

	var assault_harness = HARNESS.assault()
	add_child_autofree(assault_harness.root)
	assault_harness.player.global_position = Vector2(640.0, 360.0)

	var start := Vector2(640.0 + RAZOR_CONFIG.orbit_radius - 1.0, 360.0)
	var open_drone := _spawn_razor_drone(open_harness, start, 7)
	var assault_drone := _spawn_razor_drone(assault_harness, start, 7)
	assert_true(_razor_brain(assault_drone).mover.constraint is AssaultCorridorConstraint,
		"sanity: the Assault run really has the corridor")

	for _i in 30:
		_tick(open_drone, DT)
		_tick(assault_drone, DT)

	assert_eq(_razor_brain(open_drone).phase, RazorDroneBrain.Phase.ORBIT, "sanity: still orbiting")
	assert_almost_eq(open_drone.global_position.x, assault_drone.global_position.x, 0.01,
		"mid-corridor the Razor Drone's orbit is identical in both modes")
	assert_almost_eq(open_drone.global_position.y, assault_drone.global_position.y, 0.01)
	assert_almost_eq(open_drone.rotation, assault_drone.rotation, 0.0001)
	assert_almost_eq(open_drone.velocity.length(), assault_drone.velocity.length(), 0.01)


## The dash direction locks from `TargetInfo.player().predicted_position(...)`, which never consults
## the world provider — so it comes out identical whether an `ArenaCamera` is in the tree or not.
func test_razor_drone_dash_direction_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	add_child_autofree(open_harness.root)
	open_harness.player.global_position = Vector2(300.0, 200.0)
	open_harness.player.velocity = Vector2(50.0, -20.0)

	var assault_harness = HARNESS.assault()
	add_child_autofree(assault_harness.root)
	assault_harness.player.global_position = open_harness.player.global_position
	assault_harness.player.velocity = open_harness.player.velocity

	var start := Vector2(400.0, 200.0)
	var open_drone := _spawn_razor_drone(open_harness, start)
	var assault_drone := _spawn_razor_drone(assault_harness, start)

	_razor_brain(open_drone).enter_phase(RazorDroneBrain.Phase.DASH)
	_razor_brain(assault_drone).enter_phase(RazorDroneBrain.Phase.DASH)
	_tick(open_drone, DT)
	_tick(assault_drone, DT)

	assert_almost_eq(open_drone.velocity.x, assault_drone.velocity.x, 0.001)
	assert_almost_eq(open_drone.velocity.y, assault_drone.velocity.y, 0.001)
	assert_almost_eq(open_drone.velocity.length(), RAZOR_CONFIG.dash_speed, 0.001)


## Replaces Phase 1's "an Open Space dash frees the drone past dash_max_distance": the Razor Drone now
## survives its dash in both modes and comes back round to orbit.
func test_razor_drone_survives_its_dash_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)

	var drone := _spawn_razor_drone(harness, Vector2(640.0 - RAZOR_CONFIG.orbit_radius, 360.0))
	var brain := _razor_brain(drone)
	brain.enter_phase(RazorDroneBrain.Phase.DASH)

	var back_in_orbit := false
	for _i in 240:
		_tick(drone, DT)
		if brain.phase == RazorDroneBrain.Phase.ORBIT:
			back_in_orbit = true
			break
	assert_true(back_in_orbit, "%s: the drone comes back round to orbit after its dash" % mode)
	assert_false(drone.is_queued_for_deletion(), "%s: a dash never frees the drone" % mode)


# ── The Fighter (Phase 3, t8a) ───────────────────────────────────────────────────────────────────

const FIGHTER_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const FIGHTER_CONFIG: FighterConfig = \
		preload("res://assault/scenes/enemies/fighter/fighter_config.tres")


func _spawn_fighter(harness, pos: Vector2) -> Fighter:
	var entity := FIGHTER_SCENE.instantiate() as Fighter
	entity.global_position = pos
	(entity.get_node("Brain") as FighterBrain).start_engaged = true  # pre-t12: predates the hub idle
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Razor Drone above
	return entity


## Mid-corridor the Assault constraint never engages, so the Fighter's APPROACH is the same curve in
## both modes for the same inputs (P-17: relative to the constraint).
func test_fighter_approach_mid_corridor_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	var assault_harness = HARNESS.assault()
	add_child_autofree(open_harness.root)
	add_child_autofree(assault_harness.root)
	open_harness.player.global_position = Vector2(640.0, 360.0)
	assault_harness.player.global_position = Vector2(640.0, 360.0)

	var start := Vector2(100.0, 60.0)  # 618 px out: beyond the standoff, inside the corridor
	var open_fighter := _spawn_fighter(open_harness, start)
	var assault_fighter := _spawn_fighter(assault_harness, start)
	assert_true((assault_fighter.get_node("EnemyMover") as EnemyMover).constraint is AssaultCorridorConstraint,
		"sanity: the Assault fighter runs under the corridor")
	for _i in 30:
		_tick(open_fighter, DT)
		_tick(assault_fighter, DT)

	assert_almost_eq(open_fighter.velocity.x, assault_fighter.velocity.x, 0.001)
	assert_almost_eq(open_fighter.velocity.y, assault_fighter.velocity.y, 0.001)
	assert_gt(open_fighter.velocity.length(), 0.0, "sanity: it is moving")


## The mode-specific half: DISENGAGE frees the fighter in Assault, and nothing ever forces it in Open Space.
func test_fighter_disengage_frees_it_in_assault_only(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var fighter := _spawn_fighter(harness, Vector2(640.0, 60.0))
	fighter.config.engage_seconds = 0.2
	var freed := false
	for _i in 1500:
		_tick(fighter, DT)
		if fighter.is_queued_for_deletion():
			freed = true
			break
	assert_eq(freed, mode == "assault",
		"%s: the fighter is freed by its budget in Assault and never in Open Space" % mode)


# ── The Gatling Interceptor (Phase 3, t10) ───────────────────────────────────────────────────────

const GATLING_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn")


func _spawn_gatling(harness, pos: Vector2) -> GatlingInterceptor:
	var entity := GATLING_SCENE.instantiate() as GatlingInterceptor
	entity.global_position = pos
	(entity.get_node("Brain") as GatlingInterceptorBrain).rng_seed = 3
	(entity.get_node("Brain") as GatlingInterceptorBrain).start_engaged = true  # pre-t12: predates the hub idle
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Razor Drone above
	return entity


## Mid-corridor, with the player below the corridor centre so both modes pick the same first flank
## (+1: the Open Space side it is on, and the Assault half opposite the player), the Gatling's
## APPROACH is the same curve in both modes for the same inputs (P-17: relative to the constraint).
func test_gatling_approach_mid_corridor_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	var assault_harness = HARNESS.assault()
	add_child_autofree(open_harness.root)
	add_child_autofree(assault_harness.root)
	open_harness.player.global_position = Vector2(560.0, 360.0)
	assault_harness.player.global_position = Vector2(560.0, 360.0)

	var start := Vector2(900.0, -200.0)
	var open_gatling := _spawn_gatling(open_harness, start)
	var assault_gatling := _spawn_gatling(assault_harness, start)
	assert_true((assault_gatling.get_node("EnemyMover") as EnemyMover).constraint is AssaultCorridorConstraint,
		"sanity: the Assault Gatling runs under the corridor")
	for _i in 30:
		_tick(open_gatling, DT)
		_tick(assault_gatling, DT)

	var open_brain := open_gatling.get_node("Brain") as GatlingInterceptorBrain
	var assault_brain := assault_gatling.get_node("Brain") as GatlingInterceptorBrain
	assert_eq(open_brain.phase, GatlingInterceptorBrain.Phase.APPROACH, "sanity: still approaching")
	assert_eq(open_brain.side, assault_brain.side, "the same first flank")
	assert_almost_eq(open_gatling.velocity.x, assault_gatling.velocity.x, 0.001)
	assert_almost_eq(open_gatling.velocity.y, assault_gatling.velocity.y, 0.001)
	assert_gt(open_gatling.velocity.length(), 0.0, "sanity: it is moving")


## The mode-specific half: the budget frees the Gatling in Assault, and nothing ever forces it out in
## Open Space.
func test_gatling_disengage_frees_it_in_assault_only(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var gatling := _spawn_gatling(harness, Vector2(640.0, 60.0))
	gatling.config.engage_seconds = 0.2
	var freed := false
	for _i in 1500:
		_tick(gatling, DT)
		if gatling.is_queued_for_deletion():
			freed = true
			break
	assert_eq(freed, mode == "assault",
		"%s: the Gatling is freed by its budget in Assault and never in Open Space" % mode)


# ── The Bomber (Phase 4, t9) ─────────────────────────────────────────────────────────────────────

const BOMBER_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/bomber/bomber.tscn")


func _spawn_bomber(harness, pos: Vector2) -> Bomber:
	var entity := BOMBER_SCENE.instantiate() as Bomber
	(entity.get_node("Brain") as BomberBrain).start_engaged = true  # pre-t19: predates the hub idle
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Razor Drone above
	entity.set_process(false)
	return entity


## Mid-corridor the Assault constraint never engages, so the Bomber's APPROACH is the same curve in
## both modes for the same inputs (P-17: relative to the constraint).
func test_bomber_approach_mid_corridor_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	var assault_harness = HARNESS.assault()
	add_child_autofree(open_harness.root)
	add_child_autofree(assault_harness.root)
	open_harness.player.global_position = Vector2(640.0, 360.0)
	assault_harness.player.global_position = Vector2(640.0, 360.0)

	var start := Vector2(100.0, 60.0)
	var open_bomber := _spawn_bomber(open_harness, start)
	var assault_bomber := _spawn_bomber(assault_harness, start)
	# Both worlds share one physics space and the two bombers start on the same point: without this their
	# `move_and_slide()` calls collide and nudge each other's velocity.
	open_bomber.add_collision_exception_with(assault_bomber)
	assault_bomber.add_collision_exception_with(open_bomber)
	# The same inputs include the brain's rng (t10: the angled line's side tie-break draws from it).
	(open_bomber.get_node("Brain") as BomberBrain).rng.seed = 77
	(assault_bomber.get_node("Brain") as BomberBrain).rng.seed = 77
	assert_true((assault_bomber.get_node("EnemyMover") as EnemyMover).constraint is AssaultCorridorConstraint,
		"sanity: the Assault bomber runs under the corridor")
	for _i in 30:
		_tick(open_bomber, DT)
		_tick(assault_bomber, DT)

	assert_almost_eq(open_bomber.velocity.x, assault_bomber.velocity.x, 0.001)
	assert_almost_eq(open_bomber.velocity.y, assault_bomber.velocity.y, 0.001)
	assert_gt(open_bomber.velocity.length(), 0.0, "sanity: it is moving")


## The mode-specific half: the budget frees the Bomber in Assault, and nothing ever forces it out in
## Open Space.
func test_bomber_disengage_frees_it_in_assault_only(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var bomber := _spawn_bomber(harness, Vector2(640.0, 60.0))
	bomber.config.engage_seconds = 0.2
	var freed := false
	for _i in 1500:
		_tick(bomber, DT)
		if bomber.is_queued_for_deletion():
			freed = true
			break
	assert_eq(freed, mode == "assault",
		"%s: the Bomber is freed by its budget in Assault and never in Open Space" % mode)



# ── The Missile Corvette (Phase 5, t7) ───────────────────────────────────────────────────────────

const MISSILE_CORVETTE_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/missile_corvette/missile_corvette.tscn")


func _spawn_missile_corvette(harness, pos: Vector2) -> MissileCorvette:
	var entity := MISSILE_CORVETTE_SCENE.instantiate() as MissileCorvette
	(entity.get_node("Brain") as MissileCorvetteBrain).start_engaged = true  # pre-t15: predates the hub idle
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Bomber above
	entity.set_process(false)
	return entity


## Spawns and moves in both harnesses: from far away it closes on the player in Open Space and in Assault.
func test_missile_corvette_closes_on_the_player_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 760.0)
	var corvette := _spawn_missile_corvette(harness, Vector2(640.0, 60.0))
	var start_distance := corvette.global_position.distance_to(harness.player.global_position)
	for _i in 60:
		_tick(corvette, DT)
	assert_gt(corvette.velocity.length(), 0.0, "%s: it is moving" % mode)
	assert_lt(corvette.global_position.distance_to(harness.player.global_position), start_distance,
		"%s: it closed on the player" % mode)
	assert_false(corvette.is_queued_for_deletion())

# ── The Support Ship (Phase 5, t10) ──────────────────────────────────────────────────────────────

const SUPPORT_SHIP_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/support_ship/support_ship.tscn")


func _spawn_support_ship(harness, pos: Vector2) -> SupportShip:
	var entity := SUPPORT_SHIP_SCENE.instantiate() as SupportShip
	(entity.get_node("Brain") as SupportShipBrain).start_engaged = true  # pre-t15: predates the hub idle
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Bomber above
	entity.set_process(false)
	return entity


## Spawns and works in both harnesses: with a ward in the world (an AI-driven ally worth >= ward_min_score) it takes up
## the soft anchor behind it, unarmed (t11).
func test_support_ship_holds_near_an_ally_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 760.0)
	var ally := FIXTURE_ENEMY.instantiate() as BaseEnemy
	ally.global_position = Vector2(640.0, 200.0)
	harness.root.add_child(ally)
	ally.set_physics_process(false)
	ally.add_to_group("enemies")
	ally.score_value = 25  # a ward: AI-driven and >= ward_min_score
	var support := _spawn_support_ship(harness, Vector2(640.0, 560.0))
	for _i in 300:
		_tick(support, DT)
	var brain := support.get_node("Brain") as SupportShipBrain
	assert_eq(brain.ward, ally, "%s: the ally is its ward" % mode)
	assert_lt(support.global_position.distance_to(brain.anchor), 60.0, "%s: on the soft anchor" % mode)
	assert_almost_eq(support.global_position.distance_to(ally.global_position), Vector2(150.0, 40.0).length(),
		60.0, "%s: held behind the ward" % mode)
	assert_eq(support.contact_hit_box.damage, 0, "%s: harmless to touch" % mode)
	assert_false(support.is_queued_for_deletion())

# ── The Sniper (Phase 4, t12) ────────────────────────────────────────────────────────────────────

const SNIPER_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/sniper/sniper.tscn")


func _spawn_sniper(harness, pos: Vector2) -> Sniper:
	var entity := SNIPER_SCENE.instantiate() as Sniper
	(entity.get_node("Brain") as SniperBrain).start_engaged = true  # pre-t19: predates the hub idle
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Bomber above
	return entity


## The mode-neutral half: ENTER closes on the player in both modes and comes to rest, with no fly-in timer
## to wait out. The mode-specific half (the firing range and the corridor margin) is in `test_sniper.gd`.
func test_sniper_enter_comes_to_rest_at_its_point_in_both_modes(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 560.0)
	var sniper := _spawn_sniper(harness, Vector2(640.0, 80.0))
	var brain := sniper.get_node("Brain") as SniperBrain
	for _i in 480:  # 8 s at most, inside the 9 s Assault budget; it stops at AIM, after it has come to rest
		_tick(sniper, DT)
		if brain.phase == SniperBrain.Phase.AIM:
			break
	assert_eq(brain.phase, SniperBrain.Phase.AIM, "%s: the sniper aims from its first point" % mode)
	assert_true(brain.arrived, "%s: the sniper reaches its firing point" % mode)
	assert_lt(sniper.velocity.length(), 2.0, "%s: and holds still there" % mode)
	assert_false(sniper.is_queued_for_deletion(), "%s: well inside its budget, it stays" % mode)


## The mode-specific half: the budget frees the Sniper in Assault, and nothing ever forces it out in Open Space.
func test_sniper_disengage_frees_it_in_assault_only(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var sniper := _spawn_sniper(harness, Vector2(640.0, 60.0))
	sniper.config.engage_seconds = 0.2
	var freed := false
	for _i in 1500:
		_tick(sniper, DT)
		if sniper.is_queued_for_deletion():
			freed = true
			break
	assert_eq(freed, mode == "assault",
		"%s: the Sniper is freed by its budget in Assault and never in Open Space" % mode)


# ── The Ram Corvette (Phase 4, t16) ──────────────────────────────────────────────────────────────

const RAM_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")


func _spawn_ram(harness, pos: Vector2) -> RamCorvette:
	var entity := RAM_SCENE.instantiate() as RamCorvette
	(entity.get_node("Brain") as RamCorvetteBrain).start_engaged = true  # pre-t19: predates the hub idle
	entity.global_position = pos
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # hand-ticked, same technique as the Bomber above
	return entity


## Mid-corridor the Assault constraint never engages, so the Corvette's APPROACH (an intercept; in Assault plus
## a side offset, zeroed here) is the same curve in both modes for the same inputs (P-17: relative to the constraint).
func test_ram_corvette_approach_mid_corridor_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	var assault_harness = HARNESS.assault()
	add_child_autofree(open_harness.root)
	add_child_autofree(assault_harness.root)
	open_harness.player.global_position = Vector2(640.0, 360.0)
	assault_harness.player.global_position = Vector2(640.0, 360.0)

	var start := Vector2(200.0, 120.0)
	var open_ram := _spawn_ram(open_harness, start)
	var assault_ram := _spawn_ram(assault_harness, start)
	# t17: the Assault approach aims beside the player (the diagonal charge); with that offset at 0 it is the
	# same intercept as Open Space, which is what this case compares (the offset has its own tests). Zeroed on
	# both: the two worlds share one tree, so the "open" Corvette's AUTO mover can also resolve the Assault
	# world's corridor.
	open_ram.config.assault_side_offset = 0.0
	assault_ram.config.assault_side_offset = 0.0
	assert_true((assault_ram.get_node("EnemyMover") as EnemyMover).constraint is AssaultCorridorConstraint,
		"sanity: the Assault Corvette runs under the corridor")
	for _i in 30:
		_tick(open_ram, DT)
		_tick(assault_ram, DT)

	assert_almost_eq(open_ram.velocity.x, assault_ram.velocity.x, 0.001)
	assert_almost_eq(open_ram.velocity.y, assault_ram.velocity.y, 0.001)
	assert_gt(open_ram.velocity.length(), 0.0, "sanity: it is moving")
	assert_gt(open_ram.velocity.dot(Vector2(640.0, 360.0) - start), 0.0, "and it closes on the player")


## The mode-specific half: the budget frees the Corvette in Assault, and nothing ever forces it out in
## Open Space.
func test_ram_corvette_disengage_frees_it_in_assault_only(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var ram := _spawn_ram(harness, Vector2(640.0, 60.0))
	ram.config.engage_seconds = 0.2
	var freed := false
	for _i in 1500:
		_tick(ram, DT)
		if ram.is_queued_for_deletion():
			freed = true
			break
	assert_eq(freed, mode == "assault",
		"%s: the Ram Corvette is freed by its budget in Assault and never in Open Space" % mode)


# ── Hazards: enemies are really pulled and slowed (Phase 6, t2; plan §2.2) ───────────────────────
#
# `Hazards` is a static registry, so every hazard here is `add_child_autofree`d: it is empty again
# after each test.

const SWARM_CONFIG: SwarmDroneConfig = \
		preload("res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres")

## [config path, avoidance, margin, resistance] — plan §2.2's table, one row per mover-driven enemy.
const HAZARD_PROFILES := [
	["swarm_drone", 1.0, 12.0, 0.0],
	["razor_drone", 1.0, 16.0, 0.0],
	["fighter", 0.8, 60.0, 0.1],
	["gatling_interceptor", 0.8, 60.0, 0.15],
	["sniper", 1.0, 90.0, 0.1],
	["support_ship", 1.0, 80.0, 0.1],
	["bomber", 0.6, 70.0, 0.4],
	["missile_corvette", 0.7, 80.0, 0.4],
	["ram_corvette", 0.5, 60.0, 0.5],
]


func _hazard_world(mode: String):
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	return harness


## A fixture gravity well (plan §2.5's numbers: pull 520, core 90, radius 420) at `at`.
func _fixture_well(at: Vector2, props: Dictionary = {}) -> HazardField:
	var f := HazardField.new()
	f.kind = &"gravity_well"
	f.radius = 420.0
	f.core_radius = 90.0
	f.pull_force = 520.0
	for key in props:
		f.set(key, props[key])
	add_child_autofree(f)
	f.global_position = at
	return f


func _set_limits(entity: BaseEnemy, acceleration: float, braking: float) -> void:
	var mover := entity.get_node("EnemyMover") as EnemyMover
	mover.acceleration = acceleration
	mover.braking = braking


## A fixture enemy whose brain requests `velocity` every tick and whose mover carries `resistance`.
func _fixture_enemy(harness, pos: Vector2, velocity: Vector2, resistance: float = 0.0) -> BaseEnemy:
	var entity := _spawn_orbiter(harness, pos)
	_brain(entity).desired_velocity = velocity
	(entity.get_node("EnemyMover") as EnemyMover).hazard_resistance = resistance
	return entity


func test_every_mover_driven_enemy_config_carries_its_hazard_profile() -> void:
	for row in HAZARD_PROFILES:
		var cfg := load("res://assault/scenes/enemies/%s/%s_config.tres" % [row[0], row[0]]) as ShipConfig
		assert_eq(cfg.hazard_avoidance, row[1], "%s hazard_avoidance" % row[0])
		assert_eq(cfg.hazard_margin, row[2], "%s hazard_margin" % row[0])
		assert_eq(cfg.hazard_resistance, row[3], "%s hazard_resistance" % row[0])
	var defaults := ShipConfig.new()
	assert_eq([defaults.hazard_avoidance, defaults.hazard_margin, defaults.hazard_resistance], [1.0, 60.0, 0.0])
	var bare: EnemyMover = autofree(EnemyMover.new())
	assert_eq(bare.hazard_avoidance, 0.0, "an unconfigured mover avoids nothing")


func test_base_enemy_copies_its_hazard_profile_onto_its_mover(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var ram := _spawn_ram(harness, Vector2(640.0, 300.0))
	var mover := ram.get_node("EnemyMover") as EnemyMover
	assert_eq(mover.hazard_avoidance, 0.5, "%s: avoidance" % mode)
	assert_eq(mover.hazard_margin, 60.0, "%s: margin" % mode)
	assert_eq(mover.hazard_resistance, 0.5, "%s: resistance" % mode)


func test_a_well_pulls_an_idle_enemy_in(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var centre := Vector2(640.0, 360.0)
	_fixture_well(centre)
	var entity := _fixture_enemy(harness, centre + Vector2(220.0, 0.0), Vector2.ZERO)
	for _i in 30:
		_tick(entity, DT)
	assert_lt(entity.global_position.x, centre.x + 220.0 - 10.0, "%s: dragged toward the centre" % mode)
	assert_lt(entity.velocity.x, -50.0, "%s: and moving that way" % mode)


## Capture table (plan §2.2): a Swarm Drone's own speed (220) is below the terminal drift in the core
## (~263), a Fighter's (300) is above its own (~236).
func test_a_swarm_config_cannot_leave_the_core_but_a_fighter_config_can(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var centre := Vector2(640.0, 360.0)
	_fixture_well(centre, {"damage_radius": 150.0})
	var swarm := _fixture_enemy(harness, centre + Vector2(40.0, 0.0), Vector2.RIGHT * SWARM_CONFIG.max_speed, SWARM_CONFIG.hazard_resistance)
	var fighter := _fixture_enemy(harness, centre + Vector2(40.0, 0.0), Vector2.RIGHT * FIGHTER_CONFIG.max_speed, FIGHTER_CONFIG.hazard_resistance)
	_set_limits(swarm, SWARM_CONFIG.acceleration, SWARM_CONFIG.braking)
	_set_limits(fighter, FIGHTER_CONFIG.acceleration, FIGHTER_CONFIG.braking)
	for _i in 180:  # 3 s of seeking straight out
		_tick(swarm, DT)
		_tick(fighter, DT)
	var swarm_r := swarm.global_position.distance_to(centre)
	var fighter_r := fighter.global_position.distance_to(centre)
	assert_lt(swarm_r, 90.0, "%s: the Swarm Drone is still inside the well's core" % mode)
	assert_gt(fighter_r, 200.0, "%s: the Fighter has clawed its way out of the core and beyond" % mode)


func test_a_ram_corvettes_line_up_inside_a_well_ends_on_the_line_up_test_not_the_cap(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var pos := Vector2(640.0, 300.0)
	_fixture_well(pos + Vector2(150.0, 0.0))
	harness.player.global_position = pos + Vector2(300.0, 300.0)  # 45 degrees off the resting nose
	var ram := _spawn_ram(harness, pos)
	ram.config.engage_seconds = 1000.0
	var brain := _brain(ram) as RamCorvetteBrain
	brain.enter_phase(RamCorvetteBrain.Phase.LINE_UP)
	var ticks := 0
	var drifting_at_hand_over := false
	while brain.phase == RamCorvetteBrain.Phase.LINE_UP and ticks < 120:
		_tick(ram, DT)
		ticks += 1
		if brain.phase == RamCorvetteBrain.Phase.LINE_UP:
			drifting_at_hand_over = ram.velocity.length() > ram.config.crawl_speed
	assert_eq(brain.phase, RamCorvetteBrain.Phase.WIND_UP, "%s: LINE_UP hands over" % mode)
	assert_true(drifting_at_hand_over, "%s: sanity: the well really was dragging it faster than crawl_speed" % mode)
	assert_lt(ticks * DT, ram.config.line_up_cap - 0.05, "%s: on the line-up test, before line_up_cap" % mode)


func test_a_slow_field_scales_an_enemys_speed_by_its_unresisted_share(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var centre := Vector2(640.0, 360.0)
	var field := HazardField.new()
	field.kind = &"gravity_field"
	field.radius = 500.0
	field.movement_penalty = 0.4
	add_child_autofree(field)
	field.global_position = centre
	for res in [0.0, 0.5]:
		var factor: float = 1.0 - 0.4 * (1.0 - res)
		var walker := _fixture_enemy(harness, centre, Vector2(200.0, 0.0), res)
		_tick(walker, DT)
		assert_almost_eq(walker.velocity.x, 200.0 * factor, 0.001, "%s: resistance %s scales the request" % [mode, res])
		var booster := _fixture_enemy(harness, centre, Vector2.ZERO, res)
		(booster.get_node("EnemyMover") as EnemyMover).boost(Vector2.RIGHT, 400.0, 10.0)
		_tick(booster, DT)
		assert_almost_eq(booster.velocity.x, 400.0 * factor, 0.001, "%s: resistance %s scales the boost" % [mode, res])


func test_a_rail_enemy_is_not_moved_by_a_well(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var control := _rail_position_after_one_second(mode, false)
	var with_well := _rail_position_after_one_second(mode, true)
	assert_eq(with_well, control, "%s: a rail owns position; the well never touches it" % mode)


func _rail_position_after_one_second(mode: String, well: bool) -> Vector2:
	var harness = _hazard_world(mode)
	var spawn := Vector2(300.0, 200.0)
	if well:
		_fixture_well(spawn + Vector2(100.0, 0.0))
	var entity := _fixture_enemy(harness, spawn, Vector2(0.0, -500.0))
	var movement := StraightMovement.new()
	movement.speed = 60.0
	movement.angle = 0.0
	var rail := EnemyPathMover.new()
	rail.movement = movement
	entity.add_child(rail)
	rail.set_physics_process(false)
	for _i in 60:
		rail._physics_process(DT)
		entity._physics_process(DT)  # a stray call must not move it either
	var at := entity.global_position
	harness.root.free()
	return at


## Assault only: the corridor's hard band holds against a well beyond it, because the filter runs
## after the drift is added.
func test_a_well_beyond_the_corridor_never_pulls_an_enemy_past_the_hard_band() -> void:
	var harness = _hazard_world("assault")
	var probe := AssaultCorridorConstraint.new()
	var rect := probe.inner_rect()
	_fixture_well(Vector2(rect.end.x + 300.0, rect.get_center().y))
	var entity := _fixture_enemy(harness, Vector2(rect.end.x - 10.0, rect.get_center().y), Vector2.ZERO)
	assert_true((entity.get_node("EnemyMover") as EnemyMover).constraint is AssaultCorridorConstraint, "sanity: the real corridor")
	var worst := 0.0
	for _i in 600:
		_tick(entity, DT)
		worst = maxf(worst, entity.global_position.x - rect.end.x)
	assert_gt(worst, 0.0, "sanity: the well did drag it out of the visible rect")
	assert_lt(worst, probe.hard_band, "but never past the hard band")


# ── Hazards: enemies steer round them with their own temperament (Phase 6, t4; plan §2.4) ────────

const FIXTURE_WRECK: GDScript = preload("res://tests/helpers/fixture_wreck.gd")
const SNIPER_CONFIG: SniperConfig = \
		preload("res://assault/scenes/enemies/sniper/sniper_config.tres")
const SWARM_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")


func _fixture_wreck(at: Vector2, radius: float) -> Node2D:
	var w: Node2D = FIXTURE_WRECK.new()
	w.info.radius = radius
	add_child_autofree(w)
	w.global_position = at
	return w


## A fixture enemy flying `config`'s hazard profile at `speed` with the given limits.
func _profiled_enemy(harness, pos: Vector2, config: ShipConfig, speed: float, accel: float, brake: float) -> BaseEnemy:
	var entity := _spawn_orbiter(harness, pos)
	var mover := entity.get_node("EnemyMover") as EnemyMover
	mover.hazard_avoidance = config.hazard_avoidance
	mover.hazard_margin = config.hazard_margin
	mover.hazard_resistance = config.hazard_resistance
	mover.max_speed = speed
	_set_limits(entity, accel, brake)
	return entity


func _spawn_swarm(harness, pos: Vector2) -> SwarmDrone:
	var drone := SWARM_SCENE.instantiate() as SwarmDrone
	drone.global_position = pos
	(drone.get_node("Brain") as SwarmDroneBrain).start_engaged = true  # pre-t8d: predates the hub idle
	harness.root.add_child(drone)
	drone.set_physics_process(false)
	return drone


## The ship's own cover is its destination (plan §2.4 "Cover points must be reachable"): with the Sniper's
## wide 90 px margin a cover point 50 px off a wreck's edge sits deep in the wreck's skirt, so only dropping a
## wreck the actor itself has claimed lets an `arrive()` settle there. The same wreck claimed by another node
## is avoided like any hazard: the ship never reaches that point at all.
func test_a_claimed_wreck_is_ignored_and_the_cover_point_beside_it_is_reachable(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var at := Vector2(640.0, 360.0)
	var radius := 60.0
	var wreck := _fixture_wreck(at, radius)
	var cover := at + Vector2(radius + 50.0, 0.0)
	var start := at + Vector2(480.0, 0.0)  # straight out from the cover point: the wreck is dead ahead
	for claimer in ["self", "other"]:
		var ship := _profiled_enemy(harness, start, SNIPER_CONFIG, SNIPER_CONFIG.max_speed,
				SNIPER_CONFIG.acceleration, SNIPER_CONFIG.braking)
		var brain := _brain(ship)
		brain.arrive_point = cover
		brain.arrive_speed = SNIPER_CONFIG.max_speed
		var holder: Node = ship if claimer == "self" else autofree(Node.new())
		assert_true(wreck.info.try_claim(holder), "%s: sanity: the claim is taken" % mode)
		var closest := INF
		for _i in 300:  # 5 s
			_tick(ship, DT)
			closest = minf(closest, ship.global_position.distance_to(at))
		if claimer == "self":
			assert_lt(ship.global_position.distance_to(cover), 10.0,
				"%s: its own cover: settled on the point (%s)" % [mode, ship.global_position])
		else:
			assert_gt(closest, radius + 50.0 + 10.0,
				"%s: another's wreck is avoided: it never gets within 10 px of the cover point's ring (closest %.1f)" % [mode, closest])
			assert_gt(ship.global_position.distance_to(cover), 10.0, "%s: and never settles on the point" % mode)
		wreck.info.release(holder)
		ship.free()


## The corridor runs after the stage (plan §2.2 step 6): an enemy with a full-avoidance profile (the Sniper's)
## flying straight down the right edge meets a pull-free hazard that straddles it, and the way round is out past
## the edge. In Open Space nothing stops it passing well beyond the corridor's `soft_band`; in Assault the corridor
## holds it inside that band (its 200 px/s is no more than the corridor's `edge_pressure`). With no stage it would
## fly straight down, never past the edge at all.
func test_the_corridor_still_bounds_an_avoiding_enemy(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var probe := AssaultCorridorConstraint.new()
	var rect := probe.inner_rect()
	var speed := probe.edge_pressure
	var centre := Vector2(rect.end.x - 100.0, rect.get_center().y)  # radius 300: its right edge 200 px past
	_fixture_well(centre, {"radius": 300.0, "core_radius": 10.0, "pull_force": 0.0})
	var ship := _profiled_enemy(harness, Vector2(rect.end.x - 20.0, centre.y - 500.0), SNIPER_CONFIG, speed,
			SNIPER_CONFIG.acceleration, SNIPER_CONFIG.braking)
	_brain(ship).desired_velocity = Vector2(0.0, speed)  # down the edge, past the hazard
	var furthest := -INF
	for _i in 480:  # 8 s
		_tick(ship, DT)
		furthest = maxf(furthest, ship.global_position.x - rect.end.x)
	if mode == "assault":
		assert_gt(furthest, 0.0, "assault: sanity: the stage did push it past the visible edge")
		assert_lt(furthest, probe.soft_band, "assault: the corridor holds it inside the soft band (%.1f)" % furthest)
	else:
		assert_gt(furthest, probe.soft_band, "open_space: unbounded, it leaves past the band (%.1f)" % furthest)


## One real Swarm Drone APPROACH run from (100, 360) toward a player at (1180, 360) past a well at (640, 360);
## `avoid = false` zeroes its profile's avoidance (the control). Returns the closest approach to the well's edge
## and where the drone was when APPROACH ended.
func _swarm_past_a_well(harness, well: HazardField, avoid: bool) -> Dictionary:
	var drone := _spawn_swarm(harness, Vector2(100.0, 360.0))
	if not avoid:
		(drone.get_node("EnemyMover") as EnemyMover).hazard_avoidance = 0.0
	var brain := _brain(drone) as SwarmDroneBrain
	var closest := INF
	for _i in 300:
		_tick(drone, DT)
		closest = minf(closest, drone.global_position.distance_to(well.global_position) - well.radius)
		if brain.phase != SwarmDroneBrain.Phase.APPROACH:
			break
	var result := {"closest": closest, "at": drone.global_position}
	drone.free()
	return result


## A real Swarm Drone (margin 12) flying APPROACH past a well skims its edge: never inside, and closer than the
## default 60 px margin would have let it. Control: the same run with avoidance 0 flies into it.
func test_a_swarm_drone_flying_past_a_well_skims_its_edge(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	harness.player.global_position = Vector2(1180.0, 360.0)
	var well := _fixture_well(Vector2(640.0, 360.0), {"radius": 120.0, "core_radius": 40.0, "pull_force": 200.0})
	var control := _swarm_past_a_well(harness, well, false)
	assert_lt(control.closest, 0.0, "%s: control: unavoiding, the drone's path crosses the well" % mode)
	var run := _swarm_past_a_well(harness, well, true)
	assert_gt(run.at.x, well.global_position.x + well.radius, "%s: past the well" % mode)
	assert_gt(run.closest, 0.0, "%s: never inside its radius (closest %.1f)" % [mode, run.closest])
	assert_lt(run.closest, 60.0, "%s: but skimming, inside the default 60 px margin (%.1f)" % [mode, run.closest])


## One real Fighter APPROACH run from (640, -360) toward a player at (640, 360): down, then west along y ~ -168,
## then round to its pass start (the two modes share the first ~110 ticks; each then curves to its own pass
## start). Its budget is lifted (a private config copy) so only the approach decides the run. `avoid = false` is
## the control. Returns the closest approach to the well's edge, the westernmost x before RUN_IN, and whether
## RUN_IN started.
func _fighter_past_a_well(harness, well: HazardField, avoid: bool) -> Dictionary:
	var fighter := _spawn_fighter(harness, Vector2(640.0, -360.0))
	fighter.config.engage_seconds = 1000.0
	if not avoid:
		(fighter.get_node("EnemyMover") as EnemyMover).hazard_avoidance = 0.0
	var brain := _brain(fighter) as FighterBrain
	var closest := INF
	var min_x := INF
	var reached := false
	for _i in 600:
		_tick(fighter, DT)
		closest = minf(closest, fighter.global_position.distance_to(well.global_position) - well.radius)
		min_x = minf(min_x, fighter.global_position.x)
		if brain.phase == FighterBrain.Phase.RUN_IN:
			reached = true
			break
	fighter.free()
	return {"closest": closest, "min_x": min_x, "reached": reached}


## A real Fighter (avoidance 0.8, margin 60) whose APPROACH to its pass start runs through a well on the westward
## leg goes round it — past it to the west — and still reaches RUN_IN. Control: with avoidance 0 the same approach
## flies into the well, almost through its centre. (A well on the leg's east half lets the Open Space fighter
## breach-pass at ~450 px from the player before it ever reaches the well; the `min_x` check rejects that.)
func test_a_fighter_approaching_through_a_wells_path_goes_round(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var well := _fixture_well(Vector2(320.0, -168.0), {"radius": 100.0, "core_radius": 30.0, "pull_force": 200.0})
	var control := _fighter_past_a_well(harness, well, false)
	assert_lt(control.closest, -50.0, "%s: control: unavoiding, the approach runs deep into the well (%.1f)" % [mode, control.closest])
	var run := _fighter_past_a_well(harness, well, true)
	assert_true(run.reached, "%s: the pass still starts" % mode)
	assert_lt(run.min_x, well.global_position.x - well.radius,
		"%s: it went past the well before its pass (min x %.1f)" % [mode, run.min_x])
	assert_gt(run.closest, 0.0, "%s: never inside the well (closest %.1f)" % [mode, run.closest])


## One real Swarm Drone BURST from 310 px left of `well_at` at a player 250 px right of it: the burst reaches the
## well's core. Returns the closest approach to `well_at` during the burst, whether the burst ever left its line,
## and, from the burst's end to the drone's next committed run (its next `boost()`), how long that took and how
## far from `well_at` it got.
func _swarm_burst_across(harness, well_at: Vector2) -> Dictionary:
	var start := well_at + Vector2(-310.0, 0.0)
	harness.player.global_position = well_at + Vector2(250.0, 0.0)
	var drone := _spawn_swarm(harness, start)
	var mover := drone.get_node("EnemyMover") as EnemyMover
	var brain := _brain(drone) as SwarmDroneBrain
	brain.aim = harness.player.global_position
	brain.enter_phase(SwarmDroneBrain.Phase.BURST)
	var dir: Vector2 = (harness.player.global_position - start).normalized()
	var log := {"avoidance": mover.hazard_avoidance, "straight": true, "closest": INF, "held": 0.0, "furthest": 0.0}
	while mover.is_boosting():
		_tick(drone, DT)
		log.straight = log.straight and absf(mover.own_velocity().normalized().cross(dir)) < 0.0001
		log.closest = minf(log.closest, drone.global_position.distance_to(well_at))
	while not mover.is_boosting() and log.held < 5.0:
		_tick(drone, DT)
		log.held += DT
		log.furthest = maxf(log.furthest, drone.global_position.distance_to(well_at))
	drone.free()
	return log


## R6.11 bait: a Swarm Drone's BURST is a `boost()`, so it ignores avoidance and flies straight into a well's
## core, and the well then holds it. Its own 220 px/s cannot out-fly the drift, so it stays inside the hull-stress
## radius from the burst's end until it commits again (its next BURST, over a second later: at least two 0.5 s
## stress pulses). Like the Razor's dash (plan §2.2: "captured at approach speed, escapes by dashing"), only a
## committed run gets it out. Control: the same burst with no well leaves that radius before its next burst.
func test_a_swarm_burst_across_a_well_is_captured(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var well_at := Vector2(640.0, 360.0)
	var harness = _hazard_world(mode)
	var control := _swarm_burst_across(harness, well_at)  # before the well exists
	var well := _fixture_well(well_at, {"damage_radius": 150.0})
	var run := _swarm_burst_across(harness, well_at)
	assert_gt(run.avoidance, 0.0, "%s: sanity: an avoiding profile" % mode)
	assert_true(run.straight, "%s: the burst is never steered round the well" % mode)
	assert_lt(run.closest, well.core_radius, "%s: it reaches the core (closest %.1f)" % [mode, run.closest])
	assert_gte(run.held, 1.0, "%s: sanity: over a second until its next committed run (%.2f s)" % [mode, run.held])
	assert_lt(run.furthest, well.damage_radius,
		"%s: captured: inside the damage radius until it commits again (furthest %.1f)" % [mode, run.furthest])
	assert_gt(control.furthest, well.damage_radius,
		"%s: control: with no well the same burst leaves that radius (%.1f)" % [mode, control.furthest])


# ── Hazards: the Bomber's Gravity Field slows an enemy (Phase 6, t17; plan §2.15) ─────────────────

const GRAVITY_FIELD_SCENE: PackedScene = preload("res://assault/scenes/hazards/gravity_field/gravity_field.tscn")


## A resistance-0.4 enemy (the Bomber's value) in the shipped Gravity Field moves at 1 - 0.4 * 0.6 = 0.76x of
## the speed it asked for; outside the radius it is unslowed.
func test_the_gravity_field_slows_a_bomber_resistance_enemy_to_0_76(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = _hazard_world(mode)
	var centre := Vector2(640.0, 360.0)
	var field: GravityField = GRAVITY_FIELD_SCENE.instantiate()
	add_child_autofree(field)
	field.global_position = centre
	field.set_physics_process(false)
	var inside := _fixture_enemy(harness, centre, Vector2(200.0, 0.0), 0.4)
	_tick(inside, DT)
	assert_almost_eq(inside.velocity.x, 200.0 * 0.76, 0.001, "%s: 0.4 * (1 - 0.4) slow" % mode)
	var outside := _fixture_enemy(harness, centre + Vector2(field.radius + 200.0, 0.0), Vector2(200.0, 0.0), 0.4)
	_tick(outside, DT)
	assert_almost_eq(outside.velocity.x, 200.0, 0.001, "%s: unslowed beyond the radius" % mode)


# ── The Mine Layer (Phase 7, t10; plan §2.11) ──────────────────────────────────────────────────────

const MINE_LAYER_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/mine_layer/mine_layer.tscn")


## APPROACH closes on its run-in point R in both modes, and in Assault the layer stays inside the corridor's soft band.
## (t10's row asserted the gap to the PLAYER closed; plan §2.12 (t11) makes APPROACH seek R, beside the line's start, so
## from (640, 60) the layer may fly away from a player at (640, 360). Recorded in DECISIONS, Phase 7, t11.)
func test_mine_layer_approach_closes_on_its_run_in_point(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var harness = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(640.0, 360.0)
	var layer := MINE_LAYER_SCENE.instantiate() as MineLayer
	layer.global_position = Vector2(640.0, 60.0)
	harness.root.add_child(layer)
	layer.set_physics_process(false)  # hand-ticked, same technique as the Bomber above
	layer.set_process(false)
	var brain := layer.get_node("Brain") as MineLayerBrain
	brain.start_engaged = true  # pre-t12: predates the hub idle
	_tick(layer, DT)  # the first tick plans the pass
	var start := layer.global_position.distance_to(brain.pass_run_in_point)
	for _i in 60:
		_tick(layer, DT)
	var closed := start - layer.global_position.distance_to(brain.pass_run_in_point)
	assert_gt(closed, 60.0, "%s: one second of APPROACH closes the gap to R (%.1f px)" % [mode, closed])
	assert_eq(brain.phase, MineLayerBrain.Phase.APPROACH)
	if harness.is_assault:
		assert_true(_soft_band_rect().has_point(layer.global_position), "assault: still inside the corridor")
