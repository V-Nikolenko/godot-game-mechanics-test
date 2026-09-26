## The same enemy behaviour spec runs automatically in both an Open Space and an Assault test
## world (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §4 row test_enemy_dual_mode.gd, P-17,
## task t12-dual-harness). `tests/helpers/enemy_ai_harness.gd`'s `open_space()` and `assault()`
## builders differ only in whether an `ArenaCamera` is in the tree; the spec itself never branches
## on the mode except to decide which pass criterion applies (P-17: assertions are stated relative
## to the constraint).
##
## Covers the fixture brain (`tests/helpers/fixture_brain.gd` / `fixture_enemy.tscn`, from t10) and,
## as of t14, the real ported Drone Interceptor
## (`assault/scenes/enemies/drone_interceptor/drone_interceptor_brain.gd`): the second proof that
## the harness — not just the fixture — carries a real enemy's behaviour spec across both modes.
## The interceptor runs with `EnemyMover.constraint_mode = NONE` in Phase 1 (plan §2.11, P-8), so
## its cases assert something stronger than "relative to the constraint": its Assault run and its
## Open Space run must produce IDENTICAL motion for identical inputs, because no constraint is ever
## resolved in either one.
##
## Every case drives its enemy by hand through `_tick()` (see below) with a fixed `delta`, never
## an engine frame or a `Timer` — deterministic per `docs/plans/.../3-plan.md`'s test-plan rules.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const INTERCEPTOR_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn")
const INTERCEPTOR_CONFIG: DroneInterceptorConfig = \
		preload("res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres")

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


func _interceptor_brain(entity: Node) -> DroneInterceptorBrain:
	return entity.get_node("Brain") as DroneInterceptorBrain


## Runs one manual physics tick, then replaces whatever `move_and_slide()` actually displaced the
## actor by with an exact `delta * velocity` integration. `move_and_slide()` reads
## `get_physics_process_delta_time()` internally rather than the `delta` passed in, and that value
## is not reliable when driven by hand outside a real physics substep
## (`test_drone_interceptor.gd`'s harness notes) — confirmed here too: an early version of the
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
	entity.set_physics_process(false)  # driven only by hand below (test_drone_interceptor.gd's technique)
	return entity


## Same shape as `_spawn_orbiter()`, for the real ported interceptor. `EnemyMover.constraint_mode`
## is `NONE` on this scene (plan §2.11), so it never resolves the harness's constraint either way —
## that is exactly the property these cases check by comparing the two modes directly.
func _spawn_interceptor(harness, pos: Vector2, rng_seed: int = 0) -> DroneInterceptor:
	var entity := INTERCEPTOR_SCENE.instantiate() as DroneInterceptor
	entity.global_position = pos
	if rng_seed != 0:
		_interceptor_brain(entity).rng_seed = rng_seed
	harness.root.add_child(entity)
	entity.set_physics_process(false)  # driven only by hand below (test_drone_interceptor.gd's technique)
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
## it is actively clamping; t14's ported interceptor drives an orbit near the corridor edge, where
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


# ── The ported Drone Interceptor: identical in both modes (t14) ────────────────────────────────

## ORBIT-phase comparison only: 30 frames (0.5 s) is safely under the brain's minimum 1.0 s dash
## delay regardless of the rng-drawn timer, so both runs are still orbiting when compared. The same
## `rng_seed` on both drones makes the (mode-independent) initial orbit angle identical too, so
## this is a true apples-to-apples comparison, not just "both hold roughly the same radius".
func test_ported_interceptor_orbit_is_identical_in_assault_and_open_space() -> void:
	var open_harness = HARNESS.open_space()
	add_child_autofree(open_harness.root)
	open_harness.player.global_position = Vector2(640.0, 360.0)

	var assault_harness = HARNESS.assault()
	add_child_autofree(assault_harness.root)
	assault_harness.player.global_position = Vector2(640.0, 360.0)

	var start := Vector2(640.0 + INTERCEPTOR_CONFIG.orbit_radius, 360.0)
	var open_drone := _spawn_interceptor(open_harness, start, 7)
	var assault_drone := _spawn_interceptor(assault_harness, start, 7)

	for _i in 30:
		_tick(open_drone, DT)
		_tick(assault_drone, DT)

	assert_almost_eq(open_drone.global_position.x, assault_drone.global_position.x, 0.01,
		"the interceptor's orbit must be identical in both modes: no constraint is ever resolved (constraint_mode = NONE)")
	assert_almost_eq(open_drone.global_position.y, assault_drone.global_position.y, 0.01)
	assert_almost_eq(open_drone.rotation, assault_drone.rotation, 0.0001)
	assert_almost_eq(open_drone.velocity.length(), assault_drone.velocity.length(), 0.01)


## The dash direction locks from `TargetInfo.player().predicted_position(...)`, which never
## consults the world provider — so it must come out identical whether an `ArenaCamera` is in the
## tree or not, for the same player state and the same drone position.
func test_ported_interceptor_dash_direction_is_identical_in_both_modes() -> void:
	var open_harness = HARNESS.open_space()
	add_child_autofree(open_harness.root)
	open_harness.player.global_position = Vector2(300.0, 200.0)
	open_harness.player.velocity = Vector2(50.0, -20.0)

	var assault_harness = HARNESS.assault()
	add_child_autofree(assault_harness.root)
	assault_harness.player.global_position = open_harness.player.global_position
	assault_harness.player.velocity = open_harness.player.velocity

	var start := Vector2(400.0, 200.0)
	var open_drone := _spawn_interceptor(open_harness, start)
	var assault_drone := _spawn_interceptor(assault_harness, start)

	_interceptor_brain(open_drone)._begin_dash()
	_interceptor_brain(assault_drone)._begin_dash()
	open_drone._physics_process(DT)
	assault_drone._physics_process(DT)

	assert_almost_eq(open_drone.velocity.x, assault_drone.velocity.x, 0.001)
	assert_almost_eq(open_drone.velocity.y, assault_drone.velocity.y, 0.001)
	assert_almost_eq(open_drone.velocity.length(), INTERCEPTOR_CONFIG.dash_speed, 0.001)


## Open Space has no provider, so `EnemyWorld.has_cull_rect()` is false and the brain's dash end
## falls back to `dash_max_distance` from the dash's own start (plan §2.11) — checked at the exact
## frame boundary, the same style as `test_drone_interceptor.gd`'s legacy-cull boundary case.
func test_ported_interceptor_open_space_dash_frees_past_dash_max_distance() -> void:
	var harness = HARNESS.open_space()
	add_child_autofree(harness.root)
	harness.player.global_position = Vector2(0.0, 0.0)

	var drone := _spawn_interceptor(harness, Vector2(INTERCEPTOR_CONFIG.orbit_radius, 0.0))
	var brain := _interceptor_brain(drone)
	brain._begin_dash()

	var frames_to_cover_max_distance := int(ceil(
		brain.dash_max_distance / INTERCEPTOR_CONFIG.dash_speed / DT))

	for _i in frames_to_cover_max_distance - 2:
		_tick(drone, DT)
	assert_false(drone.is_queued_for_deletion(),
		"sanity: not freed just short of covering dash_max_distance")

	for _i in 4:
		_tick(drone, DT)
	assert_true(drone.is_queued_for_deletion(),
		"an Open Space dash must free the drone once it has travelled dash_max_distance")
