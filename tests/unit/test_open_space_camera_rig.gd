## INTENT tests for OpenSpaceCameraRig — the pure speed-zoom + camera-lead formula behind
## the ship's `speed_feel` camera effect
## (`docs/plans/open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy/3-plan.md` →
## Design → Thread 2).
##
## Tree-less `OpenSpaceCameraRig.new()`: step()/get_offset()/get_zoom() read no Input and
## touch no node other than themselves, so the rig is drivable by hand here with no ship,
## no camera and no CameraDirector.
##
## THE EPIC'S DEFINING CASE IS DELIBERATELY NOT HERE — step(velocity, delta) never receives
## `rotation`, so "lead follows velocity, not facing" is unobservable at this level; it is
## guaranteed by the signature for every conforming implementation, correct or not, and it
## cannot fail on today's build because on today's build this class does not exist.
## `tests/integration/test_open_space_camera_wiring.gd` is the file that drives a real ship
## with a real rotation and proves the sign end to end — read that file for the bug fix
## itself. This file only pins what a pure step() can actually discriminate: magnitude, the
## dead zone, frame-rate independence, and the accessibility scale.
extends GutTest

## One physics frame at the project's 60 Hz.
const D: float = 1.0 / 60.0

var _rig: OpenSpaceCameraRig = null


func before_each() -> void:
	_rig = OpenSpaceCameraRig.new()


func after_each() -> void:
	_rig.free()


## Settles the rig's smoothed lead against a constant velocity for `seconds`, in `D`-sized
## steps, so the exponential has converged well past its half-life.
func _settle(velocity: Vector2, seconds: float) -> void:
	var steps: int = int(seconds / D)
	for _i in range(steps):
		_rig.step(velocity, D)


func test_lead_magnitude_caps_at_lead_max_px() -> void:
	## raw = 420 * 0.30 = 126; minus the 32 px dead zone = 94; capped at lead_max_px = 90.
	_settle(Vector2(420.0, 0.0), 5.0)
	assert_almost_eq(_rig.get_offset().length(), 90.0, 0.5,
			"cruise-speed lead must settle at the 90 px cap, not the uncapped 94 px")


func test_lead_direction_tracks_velocity_up() -> void:
	_settle(Vector2(0.0, -400.0), 5.0)
	assert_lt(_rig.get_offset().y, 0.0,
			"a velocity of (0, -400) must lead upward (negative y)")


func test_lead_direction_tracks_velocity_down() -> void:
	_settle(Vector2(0.0, 400.0), 5.0)
	assert_gt(_rig.get_offset().y, 0.0,
			"a velocity of (0, +400) must lead downward (positive y)")


func test_dead_zone_settles_to_zero_lead() -> void:
	## The §4.4 ten-second coast tail: the ship never quite reaches zero velocity, so a
	## velocity lead must not hold a small permanent offset forever.
	_settle(Vector2(1.0, 0.0), 5.0)
	assert_eq(_rig.get_offset(), Vector2.ZERO,
			"a near-zero velocity must settle to exactly zero lead")


func test_zero_velocity_leads_zero() -> void:
	_rig.step(Vector2.ZERO, D)
	assert_eq(_rig.get_offset(), Vector2.ZERO)


func test_no_pop_at_the_dead_zone_edge() -> void:
	## Just under the edge (raw mag = 31.8 px < 32 px dead zone): a fresh rig, one step,
	## reads exactly zero.
	var under := OpenSpaceCameraRig.new()
	under.step(Vector2(0.0, 106.0), D)  ## 106 * 0.30 = 31.8
	var under_offset: Vector2 = under.get_offset()
	under.free()

	## Just over the edge (raw mag = 32.1 px): the RAW lead is only ~0.1 px, not a 32 px
	## pop — proving the subtract-don't-clip choice.
	var over := OpenSpaceCameraRig.new()
	over.step(Vector2(0.0, 107.0), D)  ## 107 * 0.30 = 32.1
	var over_offset: Vector2 = over.get_offset()
	over.free()

	assert_eq(under_offset, Vector2.ZERO)
	assert_lt(over_offset.length(), 1.0,
			"crossing the dead-zone edge must move the lead by a fraction of a pixel, not by lead_dead_zone_px")


func test_frame_rate_independence() -> void:
	var fast := OpenSpaceCameraRig.new()
	for _i in range(60):
		fast.step(Vector2(420.0, 0.0), 1.0 / 60.0)

	var slow := OpenSpaceCameraRig.new()
	for _i in range(6):
		slow.step(Vector2(420.0, 0.0), 1.0 / 6.0)

	assert_almost_eq(fast.get_offset(), slow.get_offset(), Vector2(1.0, 1.0),
			"the same one second of travel must settle to the same lead regardless of step size")
	fast.free()
	slow.free()


func test_motion_scale_zero_zeroes_offset_and_zoom() -> void:
	_rig.set_motion_scale(0.0)
	_settle(Vector2(420.0, 0.0), 5.0)
	assert_eq(_rig.get_offset(), Vector2.ZERO,
			"camera_motion = off must zero the lead entirely")
	assert_eq(_rig.get_zoom(Vector2(420.0, 0.0)), Vector2.ONE,
			"camera_motion = off must zero the speed-zoom entirely")


func test_boosting_lowers_the_zoom_target() -> void:
	var cruise_velocity := Vector2(420.0, 0.0)
	var zoom_normal: Vector2 = _rig.get_zoom(cruise_velocity)
	_rig.set_boosting(true)
	var zoom_boosting: Vector2 = _rig.get_zoom(cruise_velocity)
	assert_lt(zoom_boosting.x, zoom_normal.x,
			"boosting must pull the zoom out further than cruising at the same speed")
