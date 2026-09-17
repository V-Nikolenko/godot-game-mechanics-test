## Unit tests for AimCursor's pure image-building and the apply/restore pairing.
## Input's cursor state cannot be read back in a headless run, so these assert through the
## is_applied() seam rather than through Input/DisplayServer.
extends GutTest

const AimCursor := preload("res://global/systems/aim_cursor.gd")


func after_each() -> void:
	## AimCursor's applied flag is process-global (static) state — leaving it true would
	## leak a "cursor applied" reading into whichever test runs next.
	AimCursor.restore()


func test_build_image_is_the_requested_size() -> void:
	var img := AimCursor.build_image(32, Color.WHITE)
	assert_eq(img.get_width(), 32)
	assert_eq(img.get_height(), 32)


func test_centre_pixel_is_transparent() -> void:
	var img := AimCursor.build_image(32, Color.WHITE)
	assert_eq(img.get_pixel(16, 16).a, 0.0,
			"the centre must stay transparent so whatever is under the cursor is visible")


func test_all_four_ticks_are_opaque() -> void:
	var img := AimCursor.build_image(32, Color.WHITE)
	assert_eq(img.get_pixel(15, 5).a, 1.0, "top tick")
	assert_eq(img.get_pixel(15, 25).a, 1.0, "bottom tick")
	assert_eq(img.get_pixel(5, 15).a, 1.0, "left tick")
	assert_eq(img.get_pixel(25, 15).a, 1.0, "right tick")


func test_ticks_use_the_requested_color() -> void:
	var color := Color(0.35, 0.9, 1.0)
	var img := AimCursor.build_image(32, color)
	var top: Color = img.get_pixel(15, 5)
	## FORMAT_RGBA8 is 8 bits/channel, so a value can round-trip up to 1/255 ~= 0.0039 off.
	assert_almost_eq(top.r, color.r, 0.005)
	assert_almost_eq(top.g, color.g, 0.005)
	assert_almost_eq(top.b, color.b, 0.005)


func test_apply_then_restore_reports_not_applied() -> void:
	assert_false(AimCursor.is_applied(), "must start un-applied")
	AimCursor.apply()
	assert_true(AimCursor.is_applied())
	AimCursor.restore()
	assert_false(AimCursor.is_applied())


## BOUNDARY: restore() without a prior apply() must be a safe no-op, since ships flown under
## the &"keys" scheme call it unconditionally from _exit_tree() without ever having applied.
func test_restore_without_apply_is_a_safe_noop() -> void:
	assert_false(AimCursor.is_applied())
	AimCursor.restore()
	assert_false(AimCursor.is_applied())
