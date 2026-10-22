## INTENT tests for plan §2.3 (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md): the player feels the
## same wells and slow fields an enemy does.
##
## Open Space: `OpenSpacePlayerShip._step_hazards()` adds the field acceleration to the ship's own
## `velocity`; `hazard_speed_factor()` scales thrust, reverse, the speed ceiling and the boost exit
## speed. Assault: `AssaultPlayer._physics_process()` displaces the fighter by a `HazardDrift` and
## clamps it itself (its states run from the state machine's `_process`, after which nothing clamps
## an idle fighter), and `move_state` / `dash_state` scale their speeds by `hazard_speed_factor()`.
##
## Neither ship's `_physics_process` is left running in the tree (`set_physics_process(false)`): every
## step below is hand-ticked, and `Input.action_press()` stands in for held keys (headless cannot
## report a real key).
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")

const D: float = 1.0 / 60.0

## A well: a = WELL_PULL * WELL_CORE / r (1/r outside the core). a == 380 (thrust) at r = 123 px.
const WELL_CORE: float = 40.0
const WELL_PULL: float = 1168.5
const WELL_RADIUS: float = 500.0


## A duck-typed hazard (any node answering hazard_info() joins the registry).
class FixtureHazard extends Node2D:
	var info := HazardInfo.new()
	func hazard_info() -> HazardInfo:
		info.position = global_position
		return info
	func _enter_tree() -> void:
		Hazards.register(self)
	func _exit_tree() -> void:
		Hazards.unregister(self)


func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	DialogPlayer.is_active = false


func _well(at: Vector2) -> FixtureHazard:
	var h := FixtureHazard.new()
	h.info.kind = &"gravity_well"
	h.info.radius = WELL_RADIUS
	h.info.core_radius = WELL_CORE
	h.info.pull_force = WELL_PULL
	add_child_autofree(h)
	h.global_position = at
	return h


## A slow field (penalty 0.4 -> factor 0.6) that pulls nothing.
func _slow_field(at: Vector2) -> FixtureHazard:
	var h := FixtureHazard.new()
	h.info.kind = &"gravity_field"
	h.info.radius = 600.0
	h.info.core_radius = 100.0
	h.info.movement_penalty = 0.4
	add_child_autofree(h)
	h.global_position = at
	return h


func _ship(at: Vector2 = Vector2.ZERO) -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.global_position = at
	return ship


func _fighter(at: Vector2) -> AssaultPlayer:
	var f := FIGHTER_SCENE.instantiate() as AssaultPlayer
	add_child_autofree(f)
	f.set_physics_process(false)
	f.global_position = at
	return f


## One Open Space frame without move_and_slide (no world to collide with): thrust block, hazards,
## boost, then the displacement.
func _fly(ship: OpenSpacePlayerShip, frames: int) -> void:
	for i in range(frames):
		ship._handle_thrust(D)
		ship.global_position += ship.velocity * D


## The same frame with the boost held (level injected; same order as _handle_thrust: hazards, then boost).
func _fly_boosting(ship: OpenSpacePlayerShip, frames: int) -> void:
	for i in range(frames):
		ship._step_hazards(D)
		ship._step_boost(false, true, D)
		ship.global_position += ship.velocity * D


# --- Open Space: the pull ---------------------------------------------------------------------------


func test_open_space_idle_ship_drifts_toward_a_well() -> void:
	var ship := _ship()
	_well(Vector2(0, 300))
	_fly(ship, 30)
	assert_gt(ship.velocity.y, 0.0, "the well is below the ship: the pull must give it +y velocity")
	assert_almost_eq(ship.velocity.x, 0.0, 0.001, "a pure pull has no sideways component")
	assert_gt(ship.global_position.y, 0.0, "the ship must have moved toward the well")


func test_open_space_no_hazard_leaves_velocity_untouched() -> void:
	var ship := _ship()
	ship.velocity = Vector2(50, -20)
	ship._step_hazards(D)
	assert_eq(ship.velocity, Vector2(50, -20), "with no hazard registered _step_hazards is a no-op")


func test_open_space_thrust_escapes_at_140_px_but_not_at_100_px() -> void:
	# Ship faces up (rotation 0), well below it: thrust forward is directly away from the well.
	Input.action_press("move_up")
	var far := _ship(Vector2(0, 0))
	var far_well := _well(Vector2(0, 140))
	_fly(far, 120)
	var far_gap: float = far.global_position.distance_to(far_well.global_position)
	assert_gt(far_gap, 140.0 + 20.0, "380 px/s^2 of thrust beats the ~334 pull at 140 px: the ship escapes")

	var near := _ship(Vector2(2000, 0))
	var near_well := _well(Vector2(2000, 100))
	_fly(near, 60)
	var near_gap: float = near.global_position.distance_to(near_well.global_position)
	assert_lt(near_gap, 100.0, "the pull at 100 px (~467) beats thrust: the ship is dragged in")


func test_open_space_boost_escapes_from_100_px() -> void:
	var ship := _ship(Vector2(0, 0))
	var well := _well(Vector2(0, 100))
	# Not Input.action_press("boost"): its just-pressed edge leaks into later tests in the same frame.
	ship._step_boost(true, true, D)  # the trigger edge; headless Input cannot report it
	assert_true(ship._boosting, "sanity: the boost started")
	_fly_boosting(ship, 30)
	var gap: float = ship.global_position.distance_to(well.global_position)
	assert_gt(gap, 100.0 + 100.0, "a held boost (700 px/s) pulls clear of a well's core")


func test_open_space_pull_never_rotates_the_ship() -> void:
	var ship := _ship()
	ship.rotation = 0.7
	var before: float = ship.rotation
	_well(Vector2(300, 300))
	for i in range(30):
		ship._step_hazards(D)
	assert_eq(ship.rotation, before,"a pull must not write the hull's rotation (ShipTurnController owns it)")


func test_open_space_pull_is_bounded_by_the_speed_ceiling() -> void:
	var ship := _ship()
	_well(Vector2(0, 60))
	for i in range(240):
		ship._handle_thrust(D)
	assert_lte(ship.velocity.length(), ship.max_speed + 0.01, "_step_boost's ceiling clamp bounds a pull")


func test_open_space_pull_is_skipped_during_an_engine_boost() -> void:
	var ship := _ship()
	_well(Vector2(0, 300))
	ship.engine_boost_active = true
	ship._handle_thrust(D)
	assert_eq(ship.velocity, Vector2.ZERO, "the module owns velocity during an engine boost")


# --- Open Space: the slow ----------------------------------------------------------------------------


func test_open_space_hazard_speed_factor_is_one_without_hazards_and_point_six_in_a_field() -> void:
	var ship := _ship()
	assert_eq(ship.hazard_speed_factor(), 1.0, "no hazard: factor 1.0")
	_slow_field(Vector2.ZERO)
	assert_almost_eq(ship.hazard_speed_factor(), 0.6, 0.0001, "penalty 0.4 -> factor 0.6")


func test_open_space_thrust_scales_by_the_factor() -> void:
	var ship := _ship()
	Input.action_press("move_up")
	ship._handle_thrust(D)
	var free: float = ship.velocity.length()
	ship.velocity = Vector2.ZERO
	_slow_field(Vector2.ZERO)
	ship._handle_thrust(D)
	assert_almost_eq(ship.velocity.length(), free * 0.6, 0.001, "thrust in a slow field is 0.6x")


func test_open_space_reverse_scales_by_the_factor() -> void:
	var ship := _ship()
	Input.action_press("move_down")
	ship._handle_thrust(D)
	var free: float = ship.velocity.length()
	ship.velocity = Vector2.ZERO
	_slow_field(Vector2.ZERO)
	ship._handle_thrust(D)
	assert_almost_eq(ship.velocity.length(), free * 0.6, 0.001, "reverse thrust in a slow field is 0.6x")


func test_open_space_boost_exit_speed_scales_by_the_factor() -> void:
	var ship := _ship()
	_slow_field(Vector2.ZERO)
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed * 0.6, 0.01,
			"boost exit speed in a slow field is 0.6x")
	assert_eq(ship.boost_exit_speed, 700.0, "the exported value is read, never written")


func test_open_space_speed_ceiling_scales_by_the_factor() -> void:
	var ship := _ship()
	_slow_field(Vector2.ZERO)
	ship.velocity = Vector2(0, -ship.max_speed)
	ship._step_boost(false, false, D)
	assert_almost_eq(ship.velocity.length(), ship.max_speed * 0.6, 0.01, "the ceiling is 0.6x in a field")
	assert_eq(ship.max_speed, 420.0, "max_speed itself is never written")


# --- Assault: the drift ------------------------------------------------------------------------------


func test_assault_idle_fighter_drifts_toward_a_well() -> void:
	var f := _fighter(Vector2(640, 300))
	_well(Vector2(640, 600))
	var y0: float = f.global_position.y
	for i in range(30):
		f._physics_process(D)
	assert_gt(f.global_position.y, y0 + 1.0, "an idle fighter must be dragged toward the well")
	assert_almost_eq(f.global_position.x, 640.0, 0.01, "no sideways drift")
	assert_eq(f.velocity, Vector2.ZERO, "the drift displaces the fighter; it never writes velocity")


func test_assault_no_hazard_means_no_displacement() -> void:
	var f := _fighter(Vector2(640, 300))
	for i in range(10):
		f._physics_process(D)
	assert_eq(f.global_position, Vector2(640, 300), "pass-through: nothing moves an idle fighter")


func test_assault_drift_stops_at_the_world_clamp() -> void:
	var f := _fighter(Vector2(1300, 300))
	_well(Vector2(1700, 300))  # beyond the x <= 1380 edge
	for i in range(240):
		f._physics_process(D)
	assert_lte(f.global_position.x, 1380.0, "the drift is clamped to the world bounds")
	assert_almost_eq(f.global_position.x, 1380.0, 0.5, "it must have reached the clamp")


func test_assault_no_drift_during_dialog_and_the_drift_is_reset() -> void:
	var f := _fighter(Vector2(640, 300))
	_well(Vector2(640, 600))
	for i in range(20):
		f._physics_process(D)
	assert_ne(f._drift.velocity, Vector2.ZERO, "sanity: a drift has built up")
	DialogPlayer.is_active = true
	var held: Vector2 = f.global_position
	f._physics_process(D)
	assert_eq(f._drift.velocity, Vector2.ZERO, "a dialog resets the drift")
	for i in range(20):
		f._physics_process(D)
	assert_eq(f.global_position, held, "no drift while a dialog is active")


func test_assault_no_drift_during_knockback() -> void:
	var f := _fighter(Vector2(640, 300))
	_well(Vector2(640, 600))
	f.apply_knockback(Vector2(200, 0))  # shove along x; the well pulls along y
	f._physics_process(D)
	assert_true(f.global_position.x > 640.0, "sanity: the shove moved the fighter")
	assert_almost_eq(f.global_position.y, 300.0, 0.001, "the shove owns movement: no pull on y")


func test_assault_no_drift_during_an_engine_boost() -> void:
	var f := _fighter(Vector2(640, 300))
	_well(Vector2(640, 600))
	f.engine_boost_active = true
	for i in range(10):
		f._physics_process(D)
	assert_almost_eq(f.global_position.y, 300.0, 0.001, "the boost escapes a well: no drift while it is active")


# --- Assault: the slow -------------------------------------------------------------------------------


func test_assault_hazard_speed_factor() -> void:
	var f := _fighter(Vector2(640, 300))
	assert_eq(f.hazard_speed_factor(), 1.0, "no hazard: factor 1.0")
	_slow_field(Vector2(640, 300))
	assert_almost_eq(f.hazard_speed_factor(), 0.6, 0.0001, "penalty 0.4 -> factor 0.6")


func test_assault_move_speed_scales_by_the_factor() -> void:
	var f := _fighter(Vector2(640, 300))
	var move_state := f.get_node("MovementStateMachine/MoveState")
	move_state.move(Vector2.RIGHT)
	assert_almost_eq(f.velocity.x, move_state.move_speed, 0.01, "sanity: free speed")
	f.global_position = Vector2(640, 300)
	_slow_field(Vector2(640, 300))
	move_state.move(Vector2.RIGHT)
	assert_almost_eq(f.velocity.x, move_state.move_speed * 0.6, 0.01, "move speed in a slow field is 0.6x")


func test_assault_dash_speed_scales_by_the_factor() -> void:
	var f := _fighter(Vector2(640, 300))
	var dash: DashState = f.get_node("MovementStateMachine/DashState")
	dash.dashing_direction = Vector2.RIGHT
	dash.dashing_timer.start()
	dash.process_physics(D)
	assert_almost_eq(f.velocity.x, dash.dash_speed, 0.01, "sanity: free dash speed")
	f.global_position = Vector2(640, 300)
	_slow_field(Vector2(640, 300))
	dash.process_physics(D)
	assert_almost_eq(f.velocity.x, dash.dash_speed * 0.6, 0.01, "dash speed in a slow field is 0.6x")


func test_assault_dash_is_clamped_to_the_world() -> void:
	var f := _fighter(Vector2(1379.0, 300))
	var dash: DashState = f.get_node("MovementStateMachine/DashState")
	dash.dashing_direction = Vector2.RIGHT
	dash.dashing_timer.start()
	for i in range(10):
		dash.process_physics(D)
	assert_lte(f.global_position.x, 1380.0, "a dash never leaves the world bounds")
