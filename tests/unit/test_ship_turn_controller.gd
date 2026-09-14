## Intent tests for ShipTurnController — the only writer of the open-space ship's
## rotation. These assert what the turn model MUST do, not what it happens to do:
## frame-rate independence, the hard turn-rate cap, no overshoot, and correct wrap
## behaviour across ±PI, plus the guarantee that the Classic scheme is still the
## pre-epic behaviour to the degree.
##
## The controller is kept OUT of the scene tree and `step()` is called by hand, so the
## time base is exact rather than dependent on real frame timing (tests/README.md house
## rule). It extends Node, so it MUST be freed in after_each: a `.new()` Node that is
## never freed prints `ObjectDB instances leaked` at process exit, after GUT has set the
## exit code and in words the gate's FATAL regex does not match — the gate would print
## GATE PASS on a leaking suite. See scripts/check-test-leaks.sh.
extends GutTest

const _SHIP := Vector2(400.0, 300.0)

var _turn: ShipTurnController


func before_each() -> void:
	_turn = ShipTurnController.new()


func after_each() -> void:
	_turn.free()


## Places the cursor so that the resulting TARGET angle is exactly `angle`.
## The sprite's nose is Vector2.UP, so the controller adds +90° to the cursor bearing.
func _aim_at(angle: float, distance: float = 200.0) -> void:
	_turn.set_aim_target(_SHIP, _SHIP + Vector2.from_angle(angle - PI * 0.5) * distance)


## Runs `count` steps of `delta` from `start` and returns the final rotation.
func _run(start: float, count: int, delta: float, turn_input: float = 0.0) -> float:
	var rot: float = start
	for i: int in count:
		rot = _turn.step(rot, turn_input, delta)
	return rot


func test_shipped_defaults() -> void:
	## Classic must be today's behaviour to the degree; the other three are the
	## fly-test dials and are pinned so a silent retune is a visible diff.
	assert_eq(_turn.scheme, &"mouse", "mouse aim is the default scheme")
	assert_eq(_turn.keyboard_turn_rate_deg, 220.0, "Classic is the pre-epic turn rate")
	assert_eq(_turn.mouse_max_turn_rate_deg, 150.0)
	assert_eq(_turn.mouse_turn_half_life, 0.14)
	assert_eq(_turn.mouse_dead_zone_px, 48.0)


## The whole reason the model uses `1 - exp(-lambda * delta)` instead of a bare
## `lerp(rotation, target, 0.1)`: the same wall-clock second must produce the same turn
## at 60 fps and at 30 fps. The target is deliberately SMALL (0.3 rad) so the rate cap
## never binds — with a target of PI the cap would bind for the whole second, the model
## would degrade to a constant-rate turn, and this case would pass for the wrong reason
## (it would be pinning the clamp, not the exponential).
func test_turn_is_frame_rate_independent() -> void:
	_aim_at(0.3)
	var at_60: float = _run(0.0, 60, 1.0 / 60.0)
	var at_30: float = _run(0.0, 30, 1.0 / 30.0)
	assert_almost_eq(at_60, at_30, 1e-3, "one second of turning must not depend on fps")
	assert_gt(at_60, 0.29, "and it must actually have travelled most of the way")


## The cap is the balance guarantee, not something the half-life happens to produce.
## Without the clamp the exponential term alone closes ~99.2% of PI in one second.
func test_turn_rate_cap_holds() -> void:
	_aim_at(PI)
	var rot: float = _turn.step(0.0, 0.0, 1.0)
	## absf(): the result is NEGATIVE, because angle_difference(0, PI) is -PI — the
	## documented 180° tie-break, pinned in its own case below.
	assert_almost_eq(absf(rot), deg_to_rad(150.0), 1e-6, "one second, one capped turn")


func test_never_overshoots_the_target() -> void:
	_aim_at(1.0)
	var rot: float = 0.0
	var sign_at_start: float = signf(angle_difference(rot, 1.0))
	for i: int in 240:
		rot = _turn.step(rot, 0.0, 1.0 / 60.0)
		var remaining: float = angle_difference(rot, 1.0)
		if not is_zero_approx(remaining):
			assert_eq(signf(remaining), sign_at_start,
					"step %d crossed the target (remaining %f)" % [i, remaining])
	assert_almost_eq(rot, 1.0, 1e-4, "and it converges on the target")


## BOUNDARY: 3.0 rad to -3.0 rad is 0.283 rad the short way and -5.98 the long way.
## `angle_difference` + `rotate_toward` are what make the short way automatic; a naive
## `target - current` takes the long way round and the ship spins almost all the way
## about for a 16° correction.
func test_wraps_the_short_way_across_pi() -> void:
	_aim_at(-3.0)
	var first: float = _turn.step(3.0, 0.0, 1.0 / 60.0)
	assert_gt(first, 3.0, "the first step must go the POSITIVE way across +PI")

	var rot: float = 3.0
	var travel: float = 0.0
	for i: int in 240:
		var next: float = _turn.step(rot, 0.0, 1.0 / 60.0)
		travel += absf(next - rot)
		rot = next
	assert_almost_eq(travel, 0.283, 0.01, "total travel is the short arc, not ~5.98")
	assert_almost_eq(angle_difference(rot, -3.0), 0.0, 1e-4, "and it arrives at the target")


## BOUNDARY: Vector2.ZERO.angle() is 0.0, so a cursor sitting exactly on the ship would
## otherwise snap the nose to world-right. The dead zone is what holds the target instead.
func test_cursor_exactly_on_the_ship_holds_the_target() -> void:
	_aim_at(-PI * 0.5)          ## far to port
	var held: float = _turn.get_target_angle()
	_turn.set_aim_target(_SHIP, _SHIP)
	assert_eq(_turn.get_target_angle(), held, "a zero-length aim vector changes nothing")


## BOUNDARY: pins the dead-zone RADIUS rather than assuming it. 48 px is the judgement
## call in the plan that most needs a human fly-test; this case is what makes changing
## it a deliberate act.
func test_dead_zone_edge() -> void:
	_aim_at(0.0, 400.0)
	var held: float = _turn.get_target_angle()

	_aim_at(1.2, 47.9)
	assert_eq(_turn.get_target_angle(), held, "47.9 px is inside the dead zone: held")

	_aim_at(1.2, 48.1)
	assert_almost_eq(_turn.get_target_angle(), 1.2, 1e-5, "48.1 px is outside it: updated")


## BOUNDARY: at exactly 180° the turn direction is a coin toss, and Godot documents the
## outcome — `angle_difference` "returns -PI if from is smaller than to". Pinned rather
## than overridden: at any real cursor position the case is measure-zero, and machinery
## to break the tie differently would be untestable in practice.
func test_exact_180_degree_tie_break_turns_negative() -> void:
	_aim_at(PI)
	assert_lt(_turn.step(0.0, 0.0, 1.0 / 60.0), 0.0, "the documented tie-break is negative")


## Classic is the pre-epic `_handle_rotation` exactly: `rotation += deg_to_rad(220) *
## turn * delta`, instantaneous, no smoothing. One step of one second, so the comparison
## is exact rather than sixty accumulated roundings.
func test_classic_scheme_is_still_220_deg_per_second() -> void:
	_turn.scheme = &"keys"
	assert_almost_eq(_turn.step(0.0, 1.0, 1.0), deg_to_rad(220.0), 1e-6)
	assert_almost_eq(_turn.step(0.0, -1.0, 1.0), -deg_to_rad(220.0), 1e-6)


## The "must not affect the legacy scheme" half of the ask: under Classic the cursor is
## not an input at all.
func test_classic_scheme_ignores_the_cursor() -> void:
	_turn.scheme = &"keys"
	_aim_at(PI * 0.5, 1000.0)
	assert_eq(_run(0.4, 120, 1.0 / 60.0, 0.0), 0.4, "no A/D held, no cursor steering")


## Under mouse aim A/D do nothing: an override that wins only while held is incoherent
## with a cursor-derived target — releasing the key would turn the ship straight back.
func test_mouse_scheme_ignores_the_ad_axis() -> void:
	_aim_at(0.8)
	assert_almost_eq(_run(0.8, 120, 1.0 / 60.0, 1.0), 0.8, 1e-6, "A/D contributes nothing")


## A mid-flight scheme flip must not teleport the nose.
##
## What this case catches: a `set_scheme` that writes rotation itself, which is the
## realistic bug. What it CANNOT do is distinguish the target re-seed from the rate cap —
## the cap alone already guarantees this bound, which is exactly why the plan says the
## cap, not the re-seed, is what prevents the jump. The re-seed's real job is the
## frozen-steering and dead-zone cases above.
func test_scheme_flip_mid_turn_does_not_jump() -> void:
	_aim_at(PI * 0.75)
	var rot: float = _run(0.0, 10, 1.0 / 60.0)

	_turn.set_scheme(&"keys", rot)
	assert_eq(_turn.step(rot, 0.0, 1.0 / 60.0), rot, "Classic with no key held holds still")

	_turn.set_scheme(&"mouse", rot)
	var cap: float = deg_to_rad(_turn.mouse_max_turn_rate_deg) * (1.0 / 60.0)
	assert_almost_eq(_turn.step(rot, 0.0, 1.0 / 60.0), rot, cap + 1e-6, "no jump on the flip")


## The AI-Targeting snap has to survive the very next frame, or it is undone before the
## player sees it. It is released by mouse MOTION, not by time.
func test_snap_holds_until_the_mouse_moves() -> void:
	_turn.face_instant(2.0)
	_aim_at(2.0 - PI * 0.5)     ## cursor 90° off the snapped facing
	assert_eq(_run(2.0, 60, 1.0 / 60.0), 2.0, "the cursor does not steal the snapped facing")

	_turn.notify_mouse_moved()
	_aim_at(2.0 - PI * 0.5)
	assert_lt(_turn.step(2.0, 0.0, 1.0 / 60.0), 2.0, "and the next mouse move releases it")


## Window focus loss: the ship holds its heading instead of chasing a cursor the player
## has alt-tabbed away from.
func test_disabled_steering_freezes_the_target() -> void:
	_turn.set_scheme(&"mouse", 0.5)
	_turn.set_steering_enabled(false)
	_aim_at(PI * 0.5, 1000.0)
	assert_eq(_run(0.5, 60, 1.0 / 60.0), 0.5, "a frozen target leaves the heading alone")

	_turn.set_steering_enabled(true)
	_aim_at(PI * 0.5, 1000.0)
	var resumed: float = _turn.step(0.5, 0.0, 1.0 / 60.0)
	assert_gt(resumed, 0.5, "re-enabling resumes the chase")
	assert_lt(resumed - 0.5, deg_to_rad(_turn.mouse_max_turn_rate_deg) * (1.0 / 60.0) + 1e-6,
			"and it resumes within one frame's cap — no discontinuity")
