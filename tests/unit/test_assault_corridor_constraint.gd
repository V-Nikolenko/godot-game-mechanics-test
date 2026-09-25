## Unit tests for AssaultCorridorConstraint (assault/scenes/systems/assault_corridor_constraint.gd).
## docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.5, §2.5a, P-7 / t11-corridor.
##
## `visible` is x -100..1380, y -380..1100 (ArenaCamera's own constants). Pure RefCounted math, no
## scene tree needed.
extends GutTest

const VIS_LO := Vector2(-100.0, -380.0)
const VIS_HI := Vector2(1380.0, 1100.0)
const EPS := 0.01


func _rig() -> AssaultCorridorConstraint:
	return AssaultCorridorConstraint.new()


## Enters the constraint (latches `_entered`) by filtering once from dead centre.
func _entered_rig() -> AssaultCorridorConstraint:
	var c := _rig()
	c.filter(Vector2(640.0, 360.0), Vector2.ZERO)
	return c


# ── Derived rect ─────────────────────────────────────────────────────────────

func test_visible_rect_equals_arena_camera_constants() -> void:
	var c := _rig()
	var rect: Rect2 = c._visible_rect()
	assert_eq(rect.position, VIS_LO)
	assert_eq(rect.end, VIS_HI)


# ── Inside visible: untouched ─────────────────────────────────────────────────

func test_inside_visible_is_a_pass_through() -> void:
	var c := _rig()
	var v := c.filter(Vector2(640.0, 360.0), Vector2(123.0, -45.0))
	assert_eq(v, Vector2(123.0, -45.0))


# ── Rule 1: not yet entered ────────────────────────────────────────────────────

func test_not_entered_keeps_only_inward_and_floors_at_entry_speed() -> void:
	var c := _rig()
	# y = -400 is 20 px past the -380 low edge; x = 500 is inside.
	var v := c.filter(Vector2(500.0, -400.0), Vector2(10.0, -30.0))
	assert_eq(v.x, 10.0, "tangential axis (x, already inside) is untouched")
	assert_eq(v.y, 60.0, "outward (-30) is discarded, then floored to entry_speed (60) inward (+y)")


func test_not_entered_keeps_an_inward_request_already_above_entry_speed() -> void:
	var c := _rig()
	var v := c.filter(Vector2(500.0, -400.0), Vector2(0.0, 200.0))
	assert_eq(v.y, 200.0, "already inward and faster than entry_speed: left alone")


func test_not_entered_ignores_the_hard_band_before_the_latch() -> void:
	var c := _rig()
	# y = -860: 480 px past the low edge, beyond hard_band (450), but never yet entered.
	var v := c.filter(Vector2(500.0, -860.0), Vector2(15.0, -999.0))
	assert_eq(v.x, 15.0, "x is inside: kept")
	assert_eq(v.y, 60.0, "still just the entry_speed floor, not the hard-band rule")


## Acceptance criterion: a spawn at y ≈ -860 with outward intent enters and the latch then holds.
func test_spawn_above_hard_band_enters_and_the_latch_holds() -> void:
	var c := _rig()
	var pos := Vector2(500.0, -860.0)
	var v := c.filter(pos, Vector2(15.0, -999.0))
	assert_almost_eq(v.y, 60.0, EPS, "moves inward at >= entry_speed")
	assert_true(v.y >= 60.0)
	assert_eq(v.x, 15.0, "x velocity kept")

	# Now put it exactly on the low edge (fully inside, d = 0 both axes) to latch `entered`, then
	# push it straight back out past the hard band: because the latch holds, band rules (not rule
	# 1) must govern from here on.
	pos = Vector2(500.0, -380.0)  # exactly on the low edge: inside (d = 0)
	var at_edge := c.filter(pos, Vector2(0.0, 0.0))
	assert_eq(at_edge, Vector2.ZERO, "sanity: at the edge, inside, untouched")

	pos = Vector2(500.0, -860.0)  # back out past the hard band
	var after_latch := c.filter(pos, Vector2(0.0, -999.0))
	assert_almost_eq(after_latch.y, 200.0, EPS,
		"latch held: this is the band-4 hard-band rule (inward >= edge_pressure, +y here), not rule 1's 60")


# ── Rule 2: soft band (0 < d <= 120) ──────────────────────────────────────────

func test_soft_band_keeps_outward_and_adds_ramped_inward_pressure() -> void:
	var c := _entered_rig()
	# x = 1440 is 60 px past the 1380 high edge: half of soft_band (120) -> half pressure (100).
	var v := c.filter(Vector2(1440.0, 360.0), Vector2(50.0, 0.0))
	assert_almost_eq(v.x, -50.0, EPS, "50 (kept, outward) - 100 (half pressure) = -50")


func test_soft_band_boundary_at_d_equals_0_is_untouched() -> void:
	var c := _entered_rig()
	var v := c.filter(Vector2(1380.0, 360.0), Vector2(77.0, 0.0))
	assert_eq(v.x, 77.0, "d = 0 exactly: inside, untouched")


## Boundary: d = 120 exactly is still the soft-band formula (full edge_pressure, outward kept).
func test_soft_band_boundary_at_d_equals_120() -> void:
	var c := _entered_rig()
	var v := c.filter(Vector2(1500.0, 360.0), Vector2(30.0, 0.0))  # d = 120
	assert_almost_eq(v.x, 30.0 - 200.0, EPS)


# ── Rule 3: outer band (120 < d < 450) ────────────────────────────────────────

func test_outer_band_scales_outward_and_adds_full_pressure() -> void:
	var c := _entered_rig()
	# d = 285 (halfway between soft=120 and hard=450) -> outward scaled by 0.5.
	var v := c.filter(Vector2(1665.0, 360.0), Vector2(100.0, 0.0))
	assert_almost_eq(v.x, 100.0 * 0.5 - 200.0, EPS)


func test_outer_band_keeps_an_inward_component_unscaled() -> void:
	var c := _entered_rig()
	var v := c.filter(Vector2(1665.0, 360.0), Vector2(-40.0, 0.0))  # already inward
	assert_almost_eq(v.x, -40.0 - 200.0, EPS, "inward part (-40, unscaled) - full pressure")


func test_outer_band_is_continuous_with_the_soft_band_at_d_equals_120() -> void:
	var soft := _entered_rig().filter(Vector2(1500.0, 360.0), Vector2(30.0, 0.0))  # d = 120 (soft branch)
	var outer := _entered_rig().filter(Vector2(1500.001, 360.0), Vector2(30.0, 0.0))  # d = 120.001 (outer branch)
	assert_almost_eq(soft.x, outer.x, EPS)


# ── Rule 4: hard band (d >= 450) ──────────────────────────────────────────────

## Boundary: d = 450 exactly already removes the outward component entirely.
func test_hard_band_boundary_at_d_equals_450() -> void:
	var c := _entered_rig()
	var v := c.filter(Vector2(1830.0, 360.0), Vector2(500.0, 0.0))  # d = 450, huge outward request
	assert_almost_eq(v.x, -200.0, EPS, "outward removed, only -edge_pressure remains")


func test_hard_band_forces_inward_at_least_edge_pressure_for_any_input() -> void:
	var c := _entered_rig()
	for desired_x in [500.0, 0.0, -500.0, -10000.0]:
		var cc := _entered_rig()
		var v := cc.filter(Vector2(2000.0, 360.0), Vector2(desired_x, 0.0))  # d = 620, well past hard
		assert_true(v.x <= -200.0, "desired %s -> net %s must be inward >= edge_pressure" % [desired_x, v.x])


func test_hard_band_keeps_the_tangential_axis() -> void:
	var c := _entered_rig()
	# x is way past the hard band; y is inside visible and must be untouched.
	var v := c.filter(Vector2(2000.0, 360.0), Vector2(999.0, -77.0))
	assert_eq(v.y, -77.0, "tangential (y) axis kept even while x is force-corrected")
	assert_true(v.x <= -200.0)


func test_hard_band_continuous_with_outer_band_at_d_equals_450() -> void:
	var outer := _entered_rig().filter(Vector2(1829.999, 360.0), Vector2(500.0, 0.0))  # d = 449.999 (outer branch)
	var hard := _entered_rig().filter(Vector2(1830.0, 360.0), Vector2(500.0, 0.0))  # d = 450 (hard branch)
	assert_almost_eq(outer.x, hard.x, EPS)
