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
