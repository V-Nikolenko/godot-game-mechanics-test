## INTENT tests for the open-space Shift boost — step 1 of the boost epic
## (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`).
## New code, so these assert what the verb MUST do, not what it happens to do today.
##
## The whole model lives in `OpenSpacePlayerShip._step_boost(boost_pressed, delta)`, which
## takes the press as an injected bool and reads no `Input`. That is not a style choice:
## `Input.is_action_just_pressed()` can never return true in a headless GUT run, so a boost
## that read the key itself would be untestable by this gate. `_handle_thrust()` does the one
## `Input` read and hands the result down.
##
## **Every case parents the ship** (`add_child_autofree`) before touching it: `_handle_thrust`
## dereferences `_thruster`, which only exists once `_setup_effects()` has run from `_ready()`.
## Parenting also runs `PlayerBase._setup_components()` → `SessionState.apply_to()`, which is why
## the `user://` sandbox below is here even though no case writes a save on purpose.
##
## No meter yet — step 2 adds `BoostMeter` and the charge half of the retrigger case below.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


## In the tree (see the header), but with its own _physics_process off: otherwise the real
## physics frames run _handle_rotation + _handle_thrust + move_and_slide against whatever
## the headless mouse position is, racing every hand-driven step below.
func _spawn_ship(start_rotation: float = 0.0) -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	ship.rotation = start_rotation
	ship.velocity = Vector2.ZERO
	return ship


## ── Regression: the hidden flip-boost is gone ────────────────────────────────────────────
## Written first, and it fails on the pre-boost build. `_trigger_flip_boost()` was a boost in
## name only — `velocity = forward * 200` against `max_speed = 420` is a brake — with no key of
## its own, fired invisibly when `move_up` was pressed while reversing at >= 180 px/s. Its job
## is now the Shift boost's, and leaving the old path in place would mean two things writing
## `velocity` off the same W press.
func test_the_hidden_flip_boost_is_gone() -> void:
	var ship := _spawn_ship()
	assert_false(ship.has_method("_trigger_flip_boost"),
			"_trigger_flip_boost() must be deleted — the Shift boost absorbed it")
	assert_false("boost_speed_threshold" in ship,
			"boost_speed_threshold was the flip trigger's angle/speed test; it has no reader left")
	assert_false("boost_redirect_speed" in ship,
			"boost_redirect_speed (200) is replaced by boost_exit_speed (700)")
	assert_true("boost_hold_sec" in ship,
			"boost_duration_sec is renamed boost_hold_sec — it is now the retrigger floor too")


## The verb needs a key, and nothing else in the project would notice if the action vanished.
## Shift is deliberately the third action on that key (`dash`, `race_brake`, `boost`): the three
## consumers are separate scenes that each read only their own action name.
func test_the_boost_action_is_bound_to_shift() -> void:
	assert_true(InputMap.has_action(&"boost"), "project.godot [input] must declare a `boost` action")
	var on_shift := false
	for ev: InputEvent in InputMap.action_get_events(&"boost"):
		var key := ev as InputEventKey
		if key != null and key.physical_keycode == KEY_SHIFT:
			on_shift = true
	assert_true(on_shift, "`boost` must be bound to physical Shift (4194325)")


## ── The redirect ─────────────────────────────────────────────────────────────────────────
func test_boost_from_rest_launches_along_the_nose() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.x, 0.0, 0.5, "no sideways component")
	assert_almost_eq(ship.velocity.y, -ship.boost_exit_speed, 0.5, "UP * boost_exit_speed")


## THE HEADLINE CASE. Flying backwards at cruise, one press, and the momentum is on the nose's
## heading at boost speed in a single frame — the ~3.0 s manual reversal this epic exists to kill.
func test_boost_reverses_momentum_in_one_frame() -> void:
	var ship := _spawn_ship(0.0)
	ship.velocity = Vector2.DOWN * ship.max_speed
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.y, -ship.boost_exit_speed, 0.5,
			"a single frame must flip -420 to +700 along the nose")


## BOUNDARY: boosting while already at cruise must not brake. This is the case that fails on the
## old build — `boost_redirect_speed = 200` made a boost from 420 px/s a 52% speed *cut*.
func test_boost_at_cruise_speeds_up_rather_than_braking() -> void:
	var ship := _spawn_ship(0.0)
	ship.velocity = Vector2.UP * ship.max_speed
	ship._step_boost(true, D)
	assert_gt(ship.velocity.length(), ship.max_speed,
			"a boost from cruise must leave the ship faster than cruise, not slower")


## Facing, never velocity, picks the direction — that is what makes turn-then-boost a redirect.
func test_facing_not_velocity_sets_the_boost_direction() -> void:
	var ship := _spawn_ship(PI)
	ship.velocity = Vector2.UP * 300.0
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.y, ship.boost_exit_speed, 0.5, "nose points DOWN at rotation PI")


## BOUNDARY: from a dead stop there is no velocity to take an angle from. The direction must come
## from the hull's `rotation`, so `Vector2.ZERO.angle()`'s 0.0 singularity is never consulted and
## the result is always finite.
func test_boost_from_zero_velocity_uses_the_hull_rotation() -> void:
	var ship := _spawn_ship(PI / 2.0)
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, D)
	assert_true(is_finite(ship.velocity.x) and is_finite(ship.velocity.y), "no NaN from a zero vector")
	assert_almost_eq(ship.velocity.x, ship.boost_exit_speed, 0.5, "nose points RIGHT at rotation PI/2")


## ── The decaying ceiling ─────────────────────────────────────────────────────────────────
## The old hard `max_speed` clamp would have killed a 700 px/s boost on the same frame. It is
## replaced by a ceiling that starts at boost speed, holds, then ramps back down.
func test_the_ceiling_permits_during_the_hold_then_closes() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)

	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec * 0.5:
		ship._step_boost(false, D)
		elapsed += D
	assert_gt(ship.velocity.length(), ship.max_speed, "still above cruise inside the hold window")

	var total: float = ship.boost_hold_sec + ship.boost_exit_speed / ship.boost_ceiling_decay + 0.1
	while elapsed < total:
		ship._step_boost(false, D)
		elapsed += D
	assert_lte(ship.velocity.length(), ship.max_speed + 0.5,
			"once the ceiling has fully decayed the ship is back under the normal cap")


## The ceiling only ever PERMITS — it is floored at cruise, so normal handling is untouched the
## moment the window closes and no amount of extra decay can drag the ship below max_speed.
func test_the_ceiling_never_falls_below_cruise() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)
	for _i in 300:
		ship._step_boost(false, D)
	assert_eq(ship._speed_ceiling, ship.max_speed, "_speed_ceiling settles exactly at max_speed")
	assert_almost_eq(ship.velocity.length(), ship.max_speed, 0.5, "and the clamp follows it down")


## There is exactly ONE speed clamp when this is done, and it is the ceiling inside
## `_step_boost()`. If `_handle_thrust()` kept its own tail `max_speed` clamp, a real frame of
## thrust handling would cut the boost straight back to 420.
func test_handle_thrust_no_longer_clamps_the_boost_away() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)
	## Headless, every Input.is_action_pressed() is false, so this is a "no keys held" frame:
	## damping only, plus whatever _step_boost() does at the tail.
	ship._handle_thrust(D)
	assert_gt(ship.velocity.length(), ship.max_speed,
			"a normal frame after a boost must not re-clamp the ship to cruise")


## ── The retrigger floor ──────────────────────────────────────────────────────────────────
## Order inside `_step_boost()` is part of the contract: the `boost_hold_sec` floor is checked
## BEFORE any spend, so mashing Shift inside the window costs nothing. Step 2 adds the charge
## half of this assertion (`charges` down by exactly 1.0); here we pin the velocity half.
func test_a_second_boost_inside_the_hold_window_does_not_reslam_velocity() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)
	## Stand in for a frame or two of decay so a re-slam would be unmistakable.
	ship.velocity = Vector2.UP * 300.0
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.length(), 300.0, 0.5,
			"the boost is on cooldown for boost_hold_sec; velocity stays on its curve")


func test_the_floor_expires_and_a_later_boost_fires_again() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, D)
	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, D)
		elapsed += D
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed, 0.5,
			"once the hold window has closed the verb is available again")


## ── Module precedence ────────────────────────────────────────────────────────────────────
## THE CASE THE DOUBLED GUARD EXISTS FOR. `_handle_thrust()` already returns early while
## `engine_boost_active`, but this calls `_step_boost()` directly and so bypasses that return —
## exactly like every other case in this file. `_step_boost()` therefore repeats the guard as its
## own first line. If this fails, ADD THE GUARD; do not weaken the case.
##
## `engine_boost_active` is READ here and never written by the boost — it stays owned by
## `global/ship_modules/engine_boost_module.gd`.
func test_a_module_boost_wins_over_the_core_boost() -> void:
	var ship := _spawn_ship(0.0)
	ship.velocity = Vector2.RIGHT * 1500.0
	ship.engine_boost_active = true
	ship._step_boost(true, D)
	assert_eq(ship.velocity, Vector2.RIGHT * 1500.0,
			"EngineBoostModule owns velocity while it is active — the core boost must not write it")
	ship.engine_boost_active = false


func test_a_boost_refused_by_a_module_leaves_no_hold_window_behind() -> void:
	var ship := _spawn_ship(0.0)
	ship.engine_boost_active = true
	ship._step_boost(true, D)
	ship.engine_boost_active = false
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed, 0.5,
			"the refused press must not have started a cooldown (step 2: nor spent a charge)")


## ── The flame ────────────────────────────────────────────────────────────────────────────
## `_step_boost()`'s one tree touch, and the epic's "reuse the blue boost flames" bullet made
## assertable: the trigger branch plays the cyan `flame_boost` animation and drives both
## ThrusterEffects to BOOST, following engine_boost_module.gd:15,63-67.
func test_a_boost_plays_the_cyan_flame_on_both_engines() -> void:
	var ship := _spawn_ship(0.0)
	var sprite := ship.get_node("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	ship._step_boost(true, D)
	assert_eq(sprite.animation, &"flame_boost", "the hull plays the cyan boost animation")
	assert_eq(ship._thruster._current_state, ThrusterEffect.State.BOOST, "left engine")
	assert_eq(ship._thruster_right._current_state, ThrusterEffect.State.BOOST, "right engine")


## …and gives it back. `flame_boost` has `loop = false`, so without a restore the hull would sit
## on the animation's last frame for the rest of the scene.
func test_the_flame_is_released_when_the_hold_window_closes() -> void:
	var ship := _spawn_ship(0.0)
	var sprite := ship.get_node("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	ship._step_boost(true, D)
	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, D)
		elapsed += D
	assert_eq(sprite.animation, &"idle", "the hull returns to idle after boost_hold_sec")
