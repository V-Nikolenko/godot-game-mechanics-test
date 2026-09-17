## INTENT tests for FLY-1 — the hull's lean into a turn
## (`docs/plans/open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy/3-plan.md`, "FLY-1").
##
## A NEW file, not an extension of `test_open_space_boost_verb.gd` (that file's header scopes it
## to "the whole model lives in `_step_boost`" — banking is not the boost verb).
##
## `OpenSpacePlayerShip._step_bank(rotation_delta, delta) -> float` is the pure half: no Input, no
## node access, so the first block below drives it directly with injected rotation deltas, the
## same shape `test_open_space_boost_verb.gd` uses for `_step_boost()`.
##
## The second block is the wiring the plan's review flagged as the whole point (review B5): the
## draft skewed `$SpriteAnchor` itself, which shears `MuzzleLeft`/`MuzzleRight` (the bullet spawn
## points `WeaponState` reads) and `EngineLeft`/`EngineRight` along with the art, because
## `Node2D.skew` propagates to children. Skewing `$SpriteAnchor/ShipSprite2D` alone shears only
## the sprite. These cases fail on the anchor and pass on the sprite.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0


## `_step_bank()` touches no node and no Input — a freshly instantiated, unparented ship is
## enough to drive it, following the "pure step function" pattern (mirrors `_step_boost()`'s own
## tests) rather than the "spawn and disable physics" pattern the wiring cases below need.
func _new_ship() -> OpenSpacePlayerShip:
	return autofree(SHIP_SCENE.instantiate()) as OpenSpacePlayerShip


func test_step_bank_returns_zero_for_no_rotation_change() -> void:
	var ship := _new_ship()
	assert_eq(ship._step_bank(0.0, D), 0.0,
			"no turning this frame, and nothing carried over, must not produce any lean")


func test_step_bank_saturates_at_bank_max_rad() -> void:
	var ship := _new_ship()
	## Ten times the reference rate clamps the target to 1.0 on every frame; enough frames
	## (2 s, well past bank_half_life = 0.12 s many times over) lets the smoothing converge.
	var rotation_delta: float = deg_to_rad(ship.bank_rate_ref_deg * 10.0) * D
	var skew: float = 0.0
	for i in range(120):
		skew = ship._step_bank(rotation_delta, D)
	assert_almost_eq(skew, ship.bank_max_rad, 0.001,
			"a sustained hard turn must saturate the lean at bank_max_rad, not overshoot it")


func test_step_bank_is_sign_correct_both_directions() -> void:
	var ship := _new_ship()
	var rotation_delta: float = deg_to_rad(ship.bank_rate_ref_deg * 10.0) * D

	var right_skew: float = 0.0
	for i in range(120):
		right_skew = ship._step_bank(rotation_delta, D)
	assert_gt(right_skew, 0.0, "turning one way must lean positive")

	ship._bank_skew = 0.0
	var left_skew: float = 0.0
	for i in range(120):
		left_skew = ship._step_bank(-rotation_delta, D)
	assert_lt(left_skew, 0.0, "turning the other way must lean negative")


func test_step_bank_decays_to_zero_when_turning_stops() -> void:
	var ship := _new_ship()
	var rotation_delta: float = deg_to_rad(ship.bank_rate_ref_deg * 10.0) * D
	var skew: float = 0.0
	for i in range(120):
		skew = ship._step_bank(rotation_delta, D)
	assert_almost_eq(skew, ship.bank_max_rad, 0.001, "sanity: saturated before the release")

	for i in range(120):
		skew = ship._step_bank(0.0, D)
	assert_almost_eq(skew, 0.0, 0.001,
			"once turning stops the lean must decay back to level, not hold or oscillate")


## `set_physics_process(false)` immediately after spawning, same reason
## `test_player_ship_turn_wiring.gd` gives: once in the tree, the ship's real
## `_physics_process` would run `_handle_rotation` against whatever
## `get_global_mouse_position()` returns headlessly, racing the hand-driven calls below.
func _spawn_ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func _controller_of(ship: Node) -> ShipTurnController:
	## By CLASS, never by node path: a renamed node must not silently pass.
	for child: Node in ship.get_children():
		if child is ShipTurnController:
			return child as ShipTurnController
	return null


## BOUNDARY — the single-writer rule (plan, "FLY-1"). `test_ship_rotation_single_writer.gd`
## only sweeps `global/ship_modules/*.gd`, so it is this case that covers the ship script
## itself: after a bank-driving `_handle_rotation()` call, `rotation` is byte-identical to
## what `ShipTurnController.step()` returned, never touched again by the bank step that
## follows it in the same function.
func test_bank_step_does_not_touch_the_ships_rotation() -> void:
	var ship := _spawn_ship()
	var ctl := _controller_of(ship)
	ctl.set_scheme(&"keys", ship.rotation)
	var before: float = ship.rotation
	var expected: float = ctl.step(before, 1.0, D)

	Input.action_press("move_right")
	ship._handle_rotation(D)
	Input.action_release("move_right")

	assert_almost_eq(ship.rotation, expected, 1e-6,
			"rotation must come from ShipTurnController.step() alone, even with banking wired in")


## BOUNDARY (review B5) — the bank does not move the guns or the engine markers. Fails on
## the draft's `$SpriteAnchor.skew`, which shears every child of the anchor along with the
## art. Turns hard long enough to saturate the lean, then holds a fixed heading (rotation
## stays constant with no turn input) for a few more frames — exactly the window where the
## lean is still non-zero but mid-decay — and asserts the markers never move a bit.
func test_bank_does_not_move_the_guns_or_engines() -> void:
	var ship := _spawn_ship()
	var ctl := _controller_of(ship)
	ctl.set_scheme(&"keys", ship.rotation)

	Input.action_press("move_right")
	for i in range(60):
		ship._handle_rotation(D)
	Input.action_release("move_right")

	var muzzle_left: Marker2D = ship.get_node("SpriteAnchor/MuzzleLeft")
	var muzzle_right: Marker2D = ship.get_node("SpriteAnchor/MuzzleRight")
	var engine_left: Marker2D = ship.get_node("SpriteAnchor/EngineLeft")
	var engine_right: Marker2D = ship.get_node("SpriteAnchor/EngineRight")
	var sprite: AnimatedSprite2D = ship.get_node("SpriteAnchor/ShipSprite2D")

	var before_left: Vector2 = muzzle_left.global_position
	var before_right: Vector2 = muzzle_right.global_position
	var before_engine_left: Vector2 = engine_left.global_position
	var before_engine_right: Vector2 = engine_right.global_position

	for i in range(3):
		ship._handle_rotation(D)  ## turn_input == 0.0 now: rotation holds steady
		assert_eq(muzzle_left.global_position, before_left, "MuzzleLeft must not move")
		assert_eq(muzzle_right.global_position, before_right, "MuzzleRight must not move")
		assert_eq(engine_left.global_position, before_engine_left, "EngineLeft must not move")
		assert_eq(engine_right.global_position, before_engine_right, "EngineRight must not move")

	assert_ne(sprite.skew, 0.0,
			"the lean must still be non-zero here, or this case proves nothing")
