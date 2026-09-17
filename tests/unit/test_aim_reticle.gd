## Unit tests for AimReticle — what set_aim() stores and the colour it maps state to.
## A _draw()-only node exposes nothing a headless test can assert on, so set_aim() stores
## what it will draw as members, the same shape OverheatBar's _percentage uses.
extends GutTest

var _reticle: AimReticle = null


func before_each() -> void:
	_reticle = AimReticle.new()
	add_child_autofree(_reticle)


func test_set_aim_stores_ring_radius_target_and_hull_angle() -> void:
	_reticle.set_aim(48.0, 0.3, 0.1, false, true)
	assert_eq(_reticle._ring_radius, 48.0)
	assert_eq(_reticle._target_angle, 0.3)
	assert_eq(_reticle._hull_angle, 0.1)


func test_normal_state_when_not_snapped_and_steering_enabled() -> void:
	_reticle.set_aim(48.0, 0.0, 0.0, false, true)
	assert_eq(_reticle._state, AimReticle.AimState.NORMAL)


func test_snap_held_changes_state_and_colour() -> void:
	_reticle.set_aim(48.0, 0.0, 0.0, false, true)
	var normal_color: Color = _reticle.ring_color()

	_reticle.set_aim(48.0, 0.0, 0.0, true, true)
	assert_eq(_reticle._state, AimReticle.AimState.SNAP)
	assert_ne(_reticle.ring_color(), normal_color,
			"an honoured snap must be visibly different from normal aim (finding 6)")


func test_steering_disabled_changes_state_and_colour() -> void:
	_reticle.set_aim(48.0, 0.0, 0.0, false, true)
	var normal_color: Color = _reticle.ring_color()

	_reticle.set_aim(48.0, 0.0, 0.0, false, false)
	assert_eq(_reticle._state, AimReticle.AimState.DISABLED)
	assert_ne(_reticle.ring_color(), normal_color,
			"steering frozen on focus loss must read differently from normal aim")


## BOUNDARY: steering disabled must win over a held snap — there is no state that reads as
## "disabled" less than "snap", since disabled means the whole ring is frozen regardless.
func test_steering_disabled_takes_priority_over_snap_held() -> void:
	_reticle.set_aim(48.0, 0.0, 0.0, true, false)
	assert_eq(_reticle._state, AimReticle.AimState.DISABLED)


## Off-tree (no parent at all), so _process()'s `parent == null` fallback is what is under
## test here, not whatever a real ship's physics-process state happens to be.
func test_scheme_hidden_reticle_is_not_visible_off_tree() -> void:
	var r: AimReticle = autofree(AimReticle.new())
	r.set_scheme_visible(false)
	r._process(0.0)
	assert_false(r.visible, "the &\"keys\" scheme must hide the ring")


func test_scheme_visible_reticle_is_visible_off_tree() -> void:
	var r: AimReticle = autofree(AimReticle.new())
	r.set_scheme_visible(true)
	r._process(0.0)
	assert_true(r.visible,
			"a reticle with no parent to freeze it must stay visible under &\"mouse\"")
