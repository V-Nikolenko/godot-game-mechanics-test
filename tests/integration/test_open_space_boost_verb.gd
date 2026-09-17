## INTENT tests for the open-space Shift boost — steps 1 and 2 of the boost epic
## (`docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`,
## `docs/plans/open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy/3-plan.md`).
## New code, so these assert what the verb MUST do, not what it happens to do today.
##
## The whole model lives in `OpenSpacePlayerShip._step_boost(boost_pressed, boost_held, delta)`,
## which takes the edge and the level as injected bools and reads no `Input`. That is not a
## style choice: neither `Input.is_action_just_pressed()` nor `Input.is_action_pressed()` can
## ever return true in a headless GUT run, so a boost that read the key itself would be
## untestable by this gate. `_handle_thrust()` does the two `Input` reads and hands them down.
##
## **Every case parents the ship** (`add_child_autofree`) before touching it: `_handle_thrust`
## dereferences `_thruster`, which only exists once `_setup_effects()` has run from `_ready()`.
## Parenting also runs `PlayerBase._setup_components()` → `SessionState.apply_to()`, which is why
## the `user://` sandbox below is here even though no case writes a save on purpose.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0

var _sandbox := SaveSandbox.new()

## Two-layer discipline (tests/README.md): SaveSandbox covers the user:// file ShipModuleState
## and ShipProgressionState write, but neither autoload re-reads its file after boot, so the
## BST-3 cases below also snapshot/restore the live in-memory state by hand, the same shape
## tests/integration/test_module_list_lock.gd uses.
var _saved_engine_equipped: StringName = &""
var _saved_engine_unlocked: Array = []
var _saved_boost_charge_count: int = 0


func before_all() -> void:
	_sandbox.capture()
	_saved_engine_equipped = ShipModuleState.get_equipped(&"engines")
	_saved_engine_unlocked = (ShipModuleState._unlocked[&"engines"] as Array).duplicate()
	_saved_boost_charge_count = ShipProgressionState.boost_charge_count


func after_all() -> void:
	ShipModuleState._equipped[&"engines"] = _saved_engine_equipped
	ShipModuleState._unlocked[&"engines"] = _saved_engine_unlocked
	ShipProgressionState._boost_charge_count = _saved_boost_charge_count
	_sandbox.restore()


## Runs before EVERY case in this file, not just the BST-3 ones below — resetting the engines
## slot to unequipped is a no-op for every earlier case, since none of them equips anything,
## and is what stops a BST-3 case that forgets to clean up from leaking into its neighbours.
func before_each() -> void:
	ShipModuleState._equipped[&"engines"] = &""
	(ShipModuleState._unlocked[&"engines"] as Array).clear()


## Real unlock()/equip() calls (not direct dict writes) so the signals OpenSpacePlayerShip
## connects to in _ready() actually fire — needed for the mid-hold re-partition case, which
## equips onto an already-spawned ship rather than a fresh one.
func _equip_engine_boost() -> void:
	ShipModuleState.unlock(&"engines", &"engine_boost")
	ShipModuleState.equip(&"engines", &"engine_boost")


func _unequip_engine_boost() -> void:
	ShipModuleState.equip(&"engines", &"")


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
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.x, 0.0, 0.5, "no sideways component")
	assert_almost_eq(ship.velocity.y, -ship.boost_exit_speed, 0.5, "UP * boost_exit_speed")


## THE HEADLINE CASE. Flying backwards at cruise, one press, and the momentum is on the nose's
## heading at boost speed in a single frame — the ~3.0 s manual reversal this epic exists to kill.
func test_boost_reverses_momentum_in_one_frame() -> void:
	var ship := _spawn_ship(0.0)
	ship.velocity = Vector2.DOWN * ship.max_speed
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.y, -ship.boost_exit_speed, 0.5,
			"a single frame must flip -420 to +700 along the nose")


## BOUNDARY: boosting while already at cruise must not brake. This is the case that fails on the
## old build — `boost_redirect_speed = 200` made a boost from 420 px/s a 52% speed *cut*.
func test_boost_at_cruise_speeds_up_rather_than_braking() -> void:
	var ship := _spawn_ship(0.0)
	ship.velocity = Vector2.UP * ship.max_speed
	ship._step_boost(true, true, D)
	assert_gt(ship.velocity.length(), ship.max_speed,
			"a boost from cruise must leave the ship faster than cruise, not slower")


## Facing, never velocity, picks the direction — that is what makes turn-then-boost a redirect.
func test_facing_not_velocity_sets_the_boost_direction() -> void:
	var ship := _spawn_ship(PI)
	ship.velocity = Vector2.UP * 300.0
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.y, ship.boost_exit_speed, 0.5, "nose points DOWN at rotation PI")


## BOUNDARY: from a dead stop there is no velocity to take an angle from. The direction must come
## from the hull's `rotation`, so `Vector2.ZERO.angle()`'s 0.0 singularity is never consulted and
## the result is always finite.
func test_boost_from_zero_velocity_uses_the_hull_rotation() -> void:
	var ship := _spawn_ship(PI / 2.0)
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, true, D)
	assert_true(is_finite(ship.velocity.x) and is_finite(ship.velocity.y), "no NaN from a zero vector")
	assert_almost_eq(ship.velocity.x, ship.boost_exit_speed, 0.5, "nose points RIGHT at rotation PI/2")


## ── Hold to sustain (BST-2) ───────────────────────────────────────────────────────────────
## THE CASE THAT FAILS ON A CEILING-ONLY SUSTAIN (plan review B4). `_speed_ceiling` is a clamp,
## never a force — the thrust/damping block in `_handle_thrust()` only ever REDUCES velocity —
## so a sustain that merely holds the ceiling up leaves the 1.16 s damping half-life free to
## slow the ship down underneath it while the bar keeps draining. This loop stands in for that
## damping block by hand (headless `Input` can never report `move_up` held), then drives the
## hold exactly as `_handle_thrust()` would call it afterward: the correct sustain must
## overwrite the damped value back to `boost_exit_speed` every single frame.
func test_holding_boost_with_no_thrust_input_keeps_the_speed() -> void:
	var ship := _spawn_ship(0.0)
	var start_charges: float = ship._boost_meter.charges
	ship._step_boost(true, true, D)
	var frames: int = 30
	for _i in frames:
		ship.velocity = ship.velocity.lerp(Vector2.ZERO, clamp(ship.damping * D, 0.0, 1.0))
		ship._step_boost(false, true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed, 1.0,
			"a held boost must re-assert full speed every frame, not just raise the ceiling")
	var elapsed: float = float(frames + 1) * D
	assert_almost_eq(ship._boost_meter.charges, start_charges - ship._boost_meter.drain_rate * elapsed,
			0.01, "the hold must actually pay for the sustained speed out of the meter")


## The redirect is re-asserted along the CURRENT nose every sustain frame, not a direction
## captured at the trigger (unlike `EngineBoostModule`'s `_boost_dir`) — so spinning the ship
## mid-hold carries the momentum with it inside one frame. This is the continuous form of the
## 180° flip: "spin the nose mid-hold and the momentum follows."
func test_steering_mid_hold_turns_the_momentum_within_a_frame() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.y, -ship.boost_exit_speed, 0.5, "launches along the original nose")
	ship.rotation = PI
	ship._step_boost(false, true, D)
	assert_almost_eq(ship.velocity.y, ship.boost_exit_speed, 0.5,
			"one sustain frame after the turn, momentum follows the new nose")
	assert_almost_eq(ship.velocity.x, 0.0, 0.5, "and stays purely along the (new) nose")


## The flame/thruster tell tracks `_boosting`, not the minimum-burn timer — `_boost_hold_left`
## reaches zero after `boost_hold_sec` even though a long hold is still running, and the tell
## must not drop out from under a boost that is still very much in progress and draining.
func test_the_tell_still_reads_boost_deep_into_a_long_hold() -> void:
	var ship := _spawn_ship(0.0)
	var sprite := ship.get_node("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	ship._step_boost(true, true, D)
	for _i in 30:
		ship._step_boost(false, true, D)
	assert_gt(30.0 * D, ship.boost_hold_sec, "sanity: 30 frames is well past the minimum burn")
	assert_eq(sprite.animation, &"flame_boost", "the hull is still on the boost animation")
	assert_eq(ship._thruster._current_state, ThrusterEffect.State.BOOST, "left engine still reads BOOST")
	assert_eq(ship._thruster_right._current_state, ThrusterEffect.State.BOOST, "right engine still reads BOOST")
	## Releasing now (past the minimum) drops the tell on the very next frame.
	ship._step_boost(false, false, D)
	assert_eq(sprite.animation, &"idle", "releasing past the minimum drops the tell immediately")


## ── The decaying ceiling ─────────────────────────────────────────────────────────────────
## The old hard `max_speed` clamp would have killed a 700 px/s boost on the same frame. It is
## replaced by a ceiling that starts at boost speed, holds, then ramps back down.
func test_the_ceiling_permits_during_the_hold_then_closes() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)

	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec * 0.5:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_gt(ship.velocity.length(), ship.max_speed, "still above cruise inside the hold window")

	var total: float = ship.boost_hold_sec + ship.boost_exit_speed / ship.boost_ceiling_decay + 0.1
	while elapsed < total:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_lte(ship.velocity.length(), ship.max_speed + 0.5,
			"once the ceiling has fully decayed the ship is back under the normal cap")


## The ceiling only ever PERMITS — it is floored at cruise, so normal handling is untouched the
## moment the window closes and no amount of extra decay can drag the ship below max_speed.
func test_the_ceiling_never_falls_below_cruise() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	for _i in 300:
		ship._step_boost(false, false, D)
	assert_eq(ship._speed_ceiling, ship.max_speed, "_speed_ceiling settles exactly at max_speed")
	assert_almost_eq(ship.velocity.length(), ship.max_speed, 0.5, "and the clamp follows it down")


## There is exactly ONE speed clamp when this is done, and it is the ceiling inside
## `_step_boost()`. If `_handle_thrust()` kept its own tail `max_speed` clamp, a real frame of
## thrust handling would cut the boost straight back to 420.
func test_handle_thrust_no_longer_clamps_the_boost_away() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	## Headless, every Input.is_action_pressed() is false, so this is a "no keys held" frame —
	## but the boost is still inside its minimum-burn window, so it keeps sustaining regardless.
	ship._handle_thrust(D)
	assert_gt(ship.velocity.length(), ship.max_speed,
			"a normal frame after a boost must not re-clamp the ship to cruise")


## ── The retrigger floor ──────────────────────────────────────────────────────────────────
## Order inside `_step_boost()` is part of the contract: `not _boosting` and the
## `boost_hold_sec` floor are both checked BEFORE anything else, so mashing Shift while a boost
## is already running never restarts the minimum-burn timer and never double-drains the meter.
func test_mashing_boost_while_already_boosting_does_not_reset_the_minimum_burn() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	var hold_after_start: float = ship._boost_hold_left
	var charges_after_start: float = ship._boost_meter.charges
	## A second "pressed" edge arriving while already boosting (a mashed key) must be a no-op:
	## the timer keeps counting down and the frame drains exactly once, not twice.
	ship._step_boost(true, true, D)
	assert_almost_eq(ship._boost_hold_left, hold_after_start - D, 0.001,
			"a mashed press mid-hold must not reset the minimum-burn timer back to boost_hold_sec")
	assert_almost_eq(ship._boost_meter.charges, charges_after_start - ship._boost_meter.drain_rate * D,
			0.001, "a mashed press mid-hold must not drain a second time in the same frame")


func test_the_floor_expires_and_a_later_boost_fires_again() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, false, D)
		elapsed += D
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed, 0.5,
			"once the hold window has closed the verb is available again")


## BOUNDARY: a tap (pressed once, released immediately) still burns the full minimum-burn
## window and no more — the hold sustains, it never ramps, so the floor is the only thing
## deciding how long a tap lasts.
func test_a_tap_burns_the_full_minimum_and_stops_exactly_there() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	var elapsed: float = D
	while elapsed < ship.boost_hold_sec * 0.5:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_true(ship._boosting, "still well inside the minimum-burn window at %.4fs" % elapsed)
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_false(ship._boosting, "the minimum-burn window has fully elapsed")


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
	ship._step_boost(true, true, D)
	assert_eq(ship.velocity, Vector2.RIGHT * 1500.0,
			"EngineBoostModule owns velocity while it is active — the core boost must not write it")
	ship.engine_boost_active = false


func test_a_boost_refused_by_a_module_leaves_no_hold_window_behind() -> void:
	var ship := _spawn_ship(0.0)
	ship.engine_boost_active = true
	ship._step_boost(true, true, D)
	ship.engine_boost_active = false
	ship.velocity = Vector2.ZERO
	ship._step_boost(true, true, D)
	assert_almost_eq(ship.velocity.length(), ship.boost_exit_speed, 0.5,
			"the refused press must not have started a cooldown, nor spent any charge")


## ── The flame ────────────────────────────────────────────────────────────────────────────
## `_step_boost()`'s one tree touch, and the epic's "reuse the blue boost flames" bullet made
## assertable: the trigger branch plays the cyan `flame_boost` animation and drives both
## ThrusterEffects to BOOST, following engine_boost_module.gd:15,63-67.
func test_a_boost_plays_the_cyan_flame_on_both_engines() -> void:
	var ship := _spawn_ship(0.0)
	var sprite := ship.get_node("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	ship._step_boost(true, true, D)
	assert_eq(sprite.animation, &"flame_boost", "the hull plays the cyan boost animation")
	assert_eq(ship._thruster._current_state, ThrusterEffect.State.BOOST, "left engine")
	assert_eq(ship._thruster_right._current_state, ThrusterEffect.State.BOOST, "right engine")


## …and gives it back. `flame_boost` has `loop = false`, so without a restore the hull would sit
## on the animation's last frame for the rest of the scene.
func test_the_flame_is_released_when_the_hold_window_closes() -> void:
	var ship := _spawn_ship(0.0)
	var sprite := ship.get_node("SpriteAnchor/ShipSprite2D") as AnimatedSprite2D
	ship._step_boost(true, true, D)
	var elapsed: float = 0.0
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_eq(sprite.animation, &"idle", "the hull returns to idle after boost_hold_sec")


## ── The camera punch (FLY-2) ─────────────────────────────────────────────────────────────
## CameraShake is a global autoload — its trauma is reset to 0.0 before each case here so an
## earlier test's decay-in-progress trauma cannot leak into these assertions.
func test_boost_start_adds_camera_shake_trauma() -> void:
	var ship := _spawn_ship(0.0)
	CameraShake._trauma = 0.0
	ship._step_boost(true, true, D)
	assert_almost_eq(CameraShake._trauma, ship.boost_shake_trauma, 0.0001,
			"a boost's start frame must punch the camera between the 0.35-on-a-hit and nothing")


func test_holding_boost_does_not_add_further_trauma_after_the_start_frame() -> void:
	var ship := _spawn_ship(0.0)
	CameraShake._trauma = 0.0
	ship._step_boost(true, true, D)
	var after_start: float = CameraShake._trauma
	ship._step_boost(false, true, D)
	assert_eq(CameraShake._trauma, after_start,
			"sustaining a hold must not re-punch the camera every frame")
	CameraShake._trauma = 0.0


## BOUNDARY (task): with the rig's _motion_scale at 0.0 (camera_motion = off), a boost start
## must add NO trauma at all — without this, camera_motion = off would still shake the screen
## outside the rig's own accessibility gate.
func test_boost_start_adds_no_trauma_when_camera_motion_is_off() -> void:
	var ship := _spawn_ship(0.0)
	ship._camera_rig.set_motion_scale(0.0)
	CameraShake._trauma = 0.0
	ship._step_boost(true, true, D)
	assert_eq(CameraShake._trauma, 0.0,
			"camera_motion = off must zero the boost punch, not just scale down the lead/zoom")
	CameraShake._trauma = 0.0


## BOUNDARY: a ship stripped of its OpenSpaceCameraRig child (the null-checked contract every
## other rig-touching line in this file already honours) must still punch the camera at full
## trauma, not throw — the fallback scale is 1.0, so a bare instantiated ship behaves exactly
## as it did before FLY-2 existed.
func test_boost_start_falls_back_to_full_trauma_with_no_camera_rig() -> void:
	var ship := _spawn_ship(0.0)
	ship._camera_rig = null
	CameraShake._trauma = 0.0
	ship._step_boost(true, true, D)
	assert_almost_eq(CameraShake._trauma, ship.boost_shake_trauma, 0.0001,
			"no rig must fall back to a scale of 1.0, not to zero trauma")


## The rig reports _boosting for the whole hold and clears the instant the hold ends — the
## signal FLY-2's zoom pull relies on (OpenSpaceCameraRig.get_zoom() reads it directly).
func test_camera_rig_reports_boosting_for_the_hold_and_clears_on_release() -> void:
	var ship := _spawn_ship(0.0)
	ship._step_boost(true, true, D)
	assert_true(ship._camera_rig._boosting, "the rig must know a boost is in progress")
	var elapsed: float = D
	while elapsed < ship.boost_hold_sec + D:
		ship._step_boost(false, false, D)
		elapsed += D
	assert_false(ship._camera_rig._boosting, "the rig must clear the flag once the hold ends")


## BOUNDARY: with the rig's _motion_scale at 0.0, the zoom stays Vector2.ONE for the whole
## boost, not just at rest — camera_motion = off must mean off even while boosting.
func test_zoom_stays_neutral_while_boosting_with_camera_motion_off() -> void:
	var ship := _spawn_ship(0.0)
	ship._camera_rig.set_motion_scale(0.0)
	ship._step_boost(true, true, D)
	assert_eq(ship._camera_rig.get_zoom(ship.velocity), Vector2.ONE,
			"camera_motion = off must keep the zoom neutral even mid-boost")


## ── Boundaries around the meter (BST-2) ──────────────────────────────────────────────────
## A meter short of `min_start_charge` refuses outright — no velocity write, no drain — the
## same "refuse, don't weaken" contract `BoostMeter.try_spend()`/`drain()` already use.
func test_a_press_below_min_start_charge_changes_nothing() -> void:
	var ship := _spawn_ship(0.0)
	ship._boost_meter.charges = ship._boost_meter.min_start_charge * 0.5
	## The meter still regenerates on this frame regardless of the press — that is `step()`'s
	## job and is unaffected by the refusal — so the expectation is "regen only", not "frozen".
	var expected: float = ship._boost_meter.charges + ship._boost_meter.recharge_rate * D
	ship._step_boost(true, true, D)
	assert_eq(ship.velocity, Vector2.ZERO, "a refused start must not write velocity")
	assert_false(ship._boosting, "a refused start must not enter the boosting state")
	assert_almost_eq(ship._boost_meter.charges, expected, 0.0001,
			"a refused start must not drain — the only change is the meter's own regen")


## The boost ends the instant the meter empties, mid-hold, even with the key still down — and
## holding straight through that frame must not restart it (only a fresh `pressed` edge can).
func test_boost_stops_exactly_when_the_meter_drains_to_zero_and_does_not_restart() -> void:
	var ship := _spawn_ship(0.0)
	ship._boost_meter.charges = ship._boost_meter.min_start_charge
	ship._step_boost(true, true, D)
	var guard: int = 0
	while ship._boosting and guard < 1000:
		ship._step_boost(false, true, D)
		guard += 1
	assert_almost_eq(ship._boost_meter.charges, 0.0, 0.0001, "the meter bottoms out exactly at zero")
	assert_false(ship._boosting, "the boost must have stopped on the frame the meter emptied")
	## Still holding the key, no new `pressed` edge — must not restart.
	ship._step_boost(false, true, D)
	assert_false(ship._boosting, "holding through an empty meter must not restart the boost")


## §6.6 — Shift held across the mission menu's freeze. `set_physics_process(false)` stops
## `_step_boost()` from being called at all, so the meter cannot drain behind the menu; on
## resume a still-held key produces no `just_pressed` edge, so a boost cannot auto-resume.
func test_shift_held_across_a_physics_freeze_does_not_auto_resume() -> void:
	var ship := _spawn_ship(0.0)
	var before: float = ship._boost_meter.charges
	## The freeze itself: no _step_boost() call happens while physics is off, which this test
	## represents by simply not calling it — the meter has no clock of its own (boost_meter.gd),
	## so "no call" IS the frozen behaviour.
	ship.set_physics_process(false)
	ship.set_physics_process(true)
	## Resuming with the key still down looks exactly like this to _step_boost(): `held` is
	## true but `pressed` (just_pressed) is false, because the press edge happened before the
	## freeze started.
	ship._step_boost(false, true, D)
	assert_false(ship._boosting, "a stale 'held' with no fresh press edge must not start a boost")
	assert_almost_eq(ship._boost_meter.charges, before, 0.0001, "no charge spent across the freeze")


## ── BST-3: Boost Drive re-partitions the bar and moves onto Shift ────────────────────────
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")

func test_engine_boost_equipped_partitions_the_bar_into_three_tanks() -> void:
	ShipProgressionState._boost_charge_count = ShipProgressionState.MIN_BOOST_CHARGES
	_equip_engine_boost()
	var ship := _spawn_ship(0.0)
	assert_eq(ship._boost_meter.tanks, 3,
			"Boost Drive equipped (below max boost_charge_count) partitions the bar into 3 tanks")


func test_engine_boost_at_max_capacity_partitions_the_bar_into_four_tanks() -> void:
	ShipProgressionState._boost_charge_count = ShipProgressionState.MAX_BOOST_CHARGES
	_equip_engine_boost()
	var ship := _spawn_ship(0.0)
	assert_eq(ship._boost_meter.tanks, 4,
			"a fully upgraded boost_charge_count gives Boost Drive its 4th tank")


func test_without_engine_boost_the_bar_stays_one_long_tank() -> void:
	var ship := _spawn_ship(0.0)
	assert_eq(ship._boost_meter.tanks, 1, "no Boost Drive equipped means one long bar")


## THE HEADLINE CASE for the tier switch: a press spends exactly one tank (not the whole
## bar) and activates the module rather than the default hold-to-boost redirect.
func test_engine_boost_press_spends_one_tank_and_activates_the_module() -> void:
	_equip_engine_boost()
	var ship := _spawn_ship(0.0)
	var meter := ship._boost_meter
	var before: float = meter.charges
	ship._step_boost(true, true, D)
	assert_almost_eq(meter.charges, before - meter.tank_size(), 0.0001,
			"one press must spend exactly one tank, not a continuous drain")
	assert_true(ship.engine_boost_active, "the module must have activated")


## BOUNDARY: short of a full tank, the press must refuse outright — no spend, no activation
## — the same "refuse, don't weaken" contract try_spend_tank() already uses.
func test_engine_boost_refuses_a_press_short_of_a_full_tank() -> void:
	_equip_engine_boost()
	var ship := _spawn_ship(0.0)
	var meter := ship._boost_meter
	meter.recharge_rate = 0.0
	meter.charges = meter.tank_size() * 0.5
	ship._step_boost(true, true, D)
	assert_almost_eq(meter.charges, meter.tank_size() * 0.5, 0.0001,
			"a press short of a full tank must not spend anything")
	assert_false(ship.engine_boost_active, "a refused press must not activate the module")


## BOUNDARY (review B3): the module's own 2.0 s cooldown is checked BEFORE the spend, so a
## press on a FULL meter during that cooldown costs nothing and activates nothing. This is
## the case that fails on a spend-first ordering — every press between boost_hold_sec (0.35 s)
## and the module's cooldown (2.0 s) would otherwise burn a whole tank for a try_activate()
## that was always going to refuse.
func test_engine_boost_press_during_cooldown_on_a_full_meter_costs_nothing() -> void:
	_equip_engine_boost()
	var ship := _spawn_ship(0.0)
	var meter := ship._boost_meter
	meter.recharge_rate = 0.0
	var mod: ShipModuleBase = ship._module_pool[&"engine_boost"]
	ship._step_boost(true, true, D)  ## first activation, starts the module's burst
	assert_true(ship.engine_boost_active, "precondition: the module activated")
	## Run the module's own burst out (0.55 s) so it ends and starts its 2.0 s cooldown —
	## _end_boost() is what actually sets _cooldown_left, not the passage of wall-clock time.
	var elapsed: float = 0.0
	while elapsed < 0.6:
		mod.tick(ship, D)
		elapsed += D
	assert_false(ship.engine_boost_active, "precondition: the burst has ended")
	## Well past boost_hold_sec (0.35 s) but well inside the module's 2.0 s cooldown.
	meter.charges = float(meter.max_charges)  ## refill to full, as if nothing had been spent
	var before: float = meter.charges
	ship._step_boost(true, true, D)
	assert_almost_eq(meter.charges, before, 0.0001,
			"a press refused by the module's cooldown must not spend a tank")
	assert_false(ship.engine_boost_active, "the module must not have activated a second time")


## Equipping the module while the ship already exists (mid-hold in spirit — the meter keeps
## whatever charge it had) must re-partition the bar without granting or losing any charge.
func test_equipping_engine_boost_mid_session_repartitions_without_losing_charge() -> void:
	ShipProgressionState._boost_charge_count = ShipProgressionState.MIN_BOOST_CHARGES
	var ship := _spawn_ship(0.0)
	var meter := ship._boost_meter
	assert_eq(meter.tanks, 1, "precondition: no module yet, one long bar")
	var before: float = meter.charges
	_equip_engine_boost()
	assert_eq(meter.tanks, 3, "equipping mid-session must re-partition to 3 tanks")
	assert_almost_eq(meter.charges, before, 0.0001,
			"re-partitioning must not change the charge already in the pool")
	_unequip_engine_boost()
	assert_eq(meter.tanks, 1, "unequipping must return the bar to one long tank")


## BOUNDARY: the free-activation hole this task closes. H (use_ability) must still fire Boost
## Drive in assault, where there is no Shift boost to conflict with, but must NOT fire it in
## open space, where Shift already spends the tank that pays for the same burst.
func test_engine_boost_fires_on_h_in_assault_but_not_in_open_space() -> void:
	_equip_engine_boost()
	var h_press := InputEventAction.new()
	h_press.action = &"use_ability"
	h_press.pressed = true

	var ship := _spawn_ship(0.0)
	ship._input(h_press)
	assert_false(ship.engine_boost_active,
			"H must be a no-op for Boost Drive in open space — Shift is the paid verb there")

	var fighter := FIGHTER_SCENE.instantiate() as AssaultPlayer
	add_child_autofree(fighter)
	fighter._input(h_press)
	assert_true(fighter.engine_boost_active,
			"H must still fire Boost Drive in assault — it has no Shift boost to conflict with")
