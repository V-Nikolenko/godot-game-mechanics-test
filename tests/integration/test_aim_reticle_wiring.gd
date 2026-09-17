## INTENT tests for the wiring between OpenSpacePlayerShip and AimReticle — the anti-inert
## gate for RET-2. Every case in tests/unit/test_aim_reticle.gd is green on a build where
## AimReticle exists only as a script that was never added to player_ship.tscn, and where
## player_ship.gd never calls set_aim(); this is the file that fails on that.
##
## Follows test_player_ship_turn_wiring.gd's pattern: set_physics_process(false) right after
## spawning, then drive _handle_rotation() by hand, so a real physics frame racing
## get_global_mouse_position() cannot flake the assertions. One case (the reparenting check)
## leaves physics running instead, matching test_boost_bar.gd's reason for doing the same.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

var _sandbox := SaveSandbox.new()
var _saved_scheme: StringName


func before_all() -> void:
	_sandbox.capture()
	_saved_scheme = SettingsState.get_open_space_scheme()


func after_all() -> void:
	## Restored directly, matching test_player_ship_turn_wiring.gd: set_open_space_scheme()
	## is a no-op (emits nothing) whenever the live value already matches.
	SettingsState._open_space_scheme = _saved_scheme
	_sandbox.restore()


func _spawn_ship(start_rotation: float = 0.0) -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	ship.rotation = start_rotation
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func _reticle_of(ship: Node) -> AimReticle:
	## By CLASS, never by node path: a renamed node must not silently pass.
	for child: Node in ship.get_children():
		if child is AimReticle:
			return child as AimReticle
	return null


func _turn_of(ship: Node) -> ShipTurnController:
	for child: Node in ship.get_children():
		if child is ShipTurnController:
			return child as ShipTurnController
	return null


func test_ship_scene_carries_a_reticle() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	assert_not_null(_reticle_of(ship),
			"player_ship.tscn must have an AimReticle child, or the feature ships inert")


## Physics is left running here (unlike every other case in this file), matching
## test_boost_bar.gd's "does not overlap" case: the reticle's global_position is only
## updated from OpenSpacePlayerShip._physics_process(), so a frozen ship never moves it off
## (0, 0), which would trivially "pass" a same-position check.
func test_reticle_is_reparented_over_the_ship_every_physics_frame() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	ship.global_position = Vector2(100.0, -40.0)
	ship.velocity = Vector2.ZERO
	add_child_autofree(ship)
	await wait_physics_frames(2)

	var reticle := _reticle_of(ship)
	assert_eq(reticle.global_position, ship.global_position,
			"top_level reinterprets local coords as global; the ship must reassign it every frame")


func test_ring_radius_is_read_from_the_controller_not_duplicated() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	var turn := _turn_of(ship)
	var reticle := _reticle_of(ship)
	turn.mouse_dead_zone_px = 77.0

	ship._handle_rotation(1.0 / 60.0)

	assert_eq(reticle._ring_radius, 77.0,
			"the ring radius must come from ShipTurnController.mouse_dead_zone_px, not a copy")


func test_hull_angle_fed_from_rotation_after_the_step() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	var reticle := _reticle_of(ship)

	ship._handle_rotation(1.0 / 60.0)

	assert_eq(reticle._hull_angle, ship.rotation,
			"the hull tick must track the ship's actual rotation, not a stale value")


## BOUNDARY: the dead zone guard in ShipTurnController.set_aim_target() holds the target
## angle when the cursor sits exactly on the ship, rather than recomputing it as
## to_cursor.angle() == 0 (world-right). Fed straight through, the reticle's target tick
## must not spin to that value either.
func test_target_tick_does_not_spin_to_world_right_when_cursor_is_on_the_ship() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship(0.9)
	var turn := _turn_of(ship)
	var reticle := _reticle_of(ship)
	turn.set_scheme(&"mouse", 0.9)

	turn.set_aim_target(Vector2(50.0, 50.0), Vector2(50.0, 50.0))  ## cursor exactly on ship
	reticle.set_aim(turn.mouse_dead_zone_px, turn.get_target_angle(), ship.rotation,
			turn.is_snap_held(), turn.is_steering_enabled())

	assert_almost_eq(reticle._target_angle, 0.9, 1e-6,
			"a zero-length cursor vector must hold the seeded angle, not snap to world-right")


func test_snap_held_reaches_the_reticle() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	var turn := _turn_of(ship)
	var reticle := _reticle_of(ship)
	turn.set_scheme(&"mouse", 0.0)

	ship.face_instant(1.2)
	ship._handle_rotation(1.0 / 60.0)

	assert_true(turn.is_snap_held())
	assert_eq(reticle._state, AimReticle.AimState.SNAP,
			"an honoured AI-Targeting snap must reach the ring (finding 6: assists must be visible)")


func test_steering_disabled_reaches_the_reticle() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	var turn := _turn_of(ship)
	var reticle := _reticle_of(ship)

	ship._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	ship._handle_rotation(1.0 / 60.0)

	assert_false(turn.is_steering_enabled())
	assert_eq(reticle._state, AimReticle.AimState.DISABLED,
			"the ring must show steering is frozen on focus loss")


func test_keys_scheme_hides_the_reticle() -> void:
	SettingsState._open_space_scheme = &"keys"
	var ship := _spawn_ship()

	assert_false(_reticle_of(ship).visible,
			"under keyboard steering there is no cursor aiming to call out")


func test_mouse_scheme_shows_the_reticle() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()

	assert_true(_reticle_of(ship).visible,
			"under mouse steering the ring must be visible")


## The mission-menu freeze (§6.5): MissionTrigger._open_menu() calls
## set_physics_process(false) on the SHIP, which does not stop a CHILD's own processing —
## the reticle must poll for that itself (plan review R2-N6) rather than trust the ship to
## hide it, or the ring is left mid-swing behind the menu.
func test_reticle_hides_itself_when_the_ships_physics_is_off() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()  ## already set_physics_process(false) by _spawn_ship()
	var reticle := _reticle_of(ship)

	reticle._process(0.0)

	assert_false(reticle.visible,
			"the ring must hide itself when the ship's physics is off, not just the mission menu")


func test_reticle_reappears_once_physics_resumes() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := _spawn_ship()
	var reticle := _reticle_of(ship)
	reticle._process(0.0)
	assert_false(reticle.visible)

	ship.set_physics_process(true)
	reticle._process(0.0)

	assert_true(reticle.visible, "closing the mission menu must let the ring reappear")
