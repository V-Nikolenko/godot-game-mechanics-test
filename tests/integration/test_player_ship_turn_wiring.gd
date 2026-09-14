## INTENT tests for the wiring between OpenSpacePlayerShip and ShipTurnController —
## the anti-inert gate for this epic.
##
## Every case in tests/unit/test_ship_turn_controller.gd is green on a build where the
## feature is never plugged in: the controller node is missing from player_ship.tscn,
## `_handle_rotation` still runs its old body, and the ship still turns at a flat
## 220 °/s with the mouse doing nothing. `test_project_load_integrity.gd` proves the
## scene loads and nothing more. THIS is the file that fails on an unwired build.
##
## It never tries to place a cursor — `Input.warp_mouse()` does nothing in a headless
## run, which is the whole reason the controller takes the cursor as an argument.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

var _sandbox := SaveSandbox.new()
var _saved_scheme: StringName


func before_all() -> void:
	_sandbox.capture()
	_saved_scheme = SettingsState.get_open_space_scheme()


func after_all() -> void:
	## Restored directly rather than through set_open_space_scheme(), which is a no-op
	## (and emits nothing) when the value already matches — exactly the case on the run
	## where the suite left the live scheme where it started.
	SettingsState._open_space_scheme = _saved_scheme
	_sandbox.restore()


## Instantiates the ship with `rotation` already set, so that _ready()'s seed is
## observable, and puts it in the tree because _ready() is part of what is under test.
##
## `set_physics_process(false)` immediately after: once the ship is in the tree,
## player_ship.gd's _physics_process runs _handle_rotation + _handle_thrust +
## move_and_slide on every real physics frame, against whatever
## get_global_mouse_position() returns headlessly — racing the hand-called
## _handle_rotation below. This is tests/README.md's "keep _physics_process out of the
## tree and call it by hand", applied to a node that cannot be kept out of it.
func _spawn_ship(start_rotation: float = 0.0) -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	ship.rotation = start_rotation
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func _controller_of(ship: Node) -> ShipTurnController:
	## By CLASS, never by node path: a renamed node must not silently pass.
	for child: Node in ship.get_children():
		if child is ShipTurnController:
			return child as ShipTurnController
	return null


## The scheme is seeded from SettingsState, not the controller's own @export default —
## a build where the setting is cosmetic would still pass every other case here.
func test_scheme_is_seeded_from_settings_state_on_ready() -> void:
	SettingsState.set_open_space_scheme(&"keys")
	var ship := _spawn_ship()
	var ctl := _controller_of(ship)
	assert_eq(ctl.scheme, SettingsState.get_open_space_scheme(),
			"the controller's scheme must come from SettingsState, not its own default")
	assert_eq(ctl.scheme, &"keys")
	SettingsState.set_open_space_scheme(&"mouse")


## Flipping the setting mid-flight (e.g. from a future settings panel) must reach the
## LIVE controller without a scene reload.
func test_scheme_signal_reseeds_the_live_controller() -> void:
	SettingsState.set_open_space_scheme(&"mouse")
	var ship := _spawn_ship()
	var ctl := _controller_of(ship)
	assert_eq(ctl.scheme, &"mouse")

	SettingsState.set_open_space_scheme(&"keys")
	assert_eq(ctl.scheme, &"keys",
			"open_space_scheme_changed must re-seed the controller without a reload")
	SettingsState.set_open_space_scheme(&"mouse")


func test_ship_scene_carries_a_turn_controller() -> void:
	var ship := _spawn_ship()
	assert_not_null(_controller_of(ship),
			"player_ship.tscn must have a ShipTurnController child, or the feature ships inert")


## Alt-tab: NOTIFICATION_APPLICATION_FOCUS_OUT must freeze the controller's target and
## FOCUS_IN must resume it — otherwise the ship keeps turning toward a cursor position
## the OS stopped updating the moment the window lost focus. Driven by calling
## _notification() directly (legal in Godot) rather than a real OS focus event, which a
## headless run cannot generate.
func test_focus_out_disables_steering_and_focus_in_re_enables() -> void:
	var ship := _spawn_ship(0.7)
	var ctl := _controller_of(ship)
	ctl.set_scheme(&"mouse", 0.7)

	ship._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	ctl.set_aim_target(Vector2.ZERO, Vector2(1000.0, 0.0))
	assert_almost_eq(ctl.get_target_angle(), 0.7, 1e-6,
			"focus-out must freeze the target against a moving cursor")

	ship._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	ctl.set_aim_target(Vector2.ZERO, Vector2(1000.0, 0.0))
	assert_ne(ctl.get_target_angle(), 0.7,
			"focus-in must resume steering")


## The delegation itself. Compared against what the LIVE controller instance returns for
## the same inputs — not against a hard-coded 220 °/s — so a ship that kept its own turn
## maths and merely happens to agree on the number still fails.
func test_handle_rotation_delegates_to_the_controller() -> void:
	var ship := _spawn_ship()
	var ctl := _controller_of(ship)
	ctl.set_scheme(&"keys", ship.rotation)

	var before: float = ship.rotation
	var expected: float = ctl.step(before, 1.0, 1.0)

	Input.action_press("move_right")
	ship._handle_rotation(1.0)
	Input.action_release("move_right")

	assert_almost_eq(ship.rotation, expected, 1e-6,
			"rotation must come from ShipTurnController.step(), not from the ship")
	assert_ne(ship.rotation, before, "and the A/D axis must actually reach it")


## BOUNDARY: the controller's target angle is seeded from the hull's ACTUAL facing in
## _ready(), rather than the ship and the controller both happening to default to 0.0.
## This is what the deletion of player_ship.gd's `rotation = 0.0` bought — with that line
## still there the hull angle is wiped before the seed can read it and this case cannot
## pass. Do not "fix" a failure here by asserting after _ready() sets its own angle.
func test_target_angle_is_seeded_from_the_hull_facing() -> void:
	var ship := _spawn_ship(0.7)
	var ctl := _controller_of(ship)
	assert_almost_eq(ctl.get_target_angle(), 0.7, 1e-6, "seeded from the hull, not from 0.0")

	## Behaviourally: with steering frozen there is nothing to chase, so a step from the
	## hull's own angle must return it unchanged. An unseeded controller turns toward 0.
	ctl.set_steering_enabled(false)
	assert_almost_eq(ctl.step(0.7, 0.0, 1.0), 0.7, 1e-6, "no phantom turn on the first frame")


## A half-finished migration that leaves both the old export and the new controller reads
## as done and quietly keeps a second, dead source of truth for the turn rate.
func test_old_rotation_speed_export_is_gone() -> void:
	var ship := _spawn_ship()
	for prop: Dictionary in ship.get_property_list():
		assert_ne(prop["name"], "rotation_speed_deg",
				"rotation_speed_deg moved to ShipTurnController.keyboard_turn_rate_deg")
