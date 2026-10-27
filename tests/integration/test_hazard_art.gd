extends GutTest
## Gate over the Phase 6 hazard-field art (plan §2.17, t5): the four sprite sheets exist at their planned
## size, are transparent (the same 90 % bar as test_entity_sprite_transparency.gd, which only reaches
## them once t6/t7/t12/t17 put them in scenes), and the SpriteFrames built from them load with the
## expected animations. Intent test, not characterization.

const DIR := "res://assault/assets/sprites/hazards/"
const OPAQUE_LIMIT := 0.90

## name -> [frame width, frame height, frame count]
const SHEETS := {
	"gravity_well": [192, 192, 8],
	"energy_anomaly": [160, 160, 8],
	"gravity_field": [128, 128, 1],
	"reactor_field": [96, 96, 4],
}

## frames resource -> animation -> frame count
const FRAMES := {
	"gravity_well_frames": {"swirl": 8},
	"energy_anomaly_frames": {"dim": 4, "lit": 4},
	"reactor_field_frames": {"burn": 4},
}


func _image(name: String) -> Image:
	var tex := load(DIR + name + ".png") as Texture2D
	assert_not_null(tex, "%s.png loads" % name)
	return tex.get_image()


func test_sheet_sizes_match_the_plan(name: String = use_parameters(SHEETS.keys())) -> void:
	var spec: Array = SHEETS[name]
	var img := _image(name)
	assert_eq(img.get_size(), Vector2i(spec[0] * spec[2], spec[1]), "%s sheet size" % name)


func test_sheets_are_transparent(name: String = use_parameters(SHEETS.keys())) -> void:
	var img := _image(name)
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.99:
				opaque += 1
	var share := float(opaque) / float(img.get_width() * img.get_height())
	assert_lt(share, OPAQUE_LIMIT, "%s must not be a painted-in card" % name)
	assert_eq(img.get_pixel(0, 0).a, 0.0, "%s top-left corner is transparent" % name)


func test_every_frame_has_content(name: String = use_parameters(SHEETS.keys())) -> void:
	var spec: Array = SHEETS[name]
	var img := _image(name)
	for f in spec[2]:
		var seen := false
		for y in spec[1]:
			for x in spec[0]:
				if img.get_pixel(f * spec[0] + x, y).a > 0.0:
					seen = true
					break
			if seen:
				break
		assert_true(seen, "%s frame %d is not empty" % [name, f])


func test_sprite_frames_load(name: String = use_parameters(FRAMES.keys())) -> void:
	var sf := load(DIR + name + ".tres") as SpriteFrames
	assert_not_null(sf, "%s.tres loads" % name)
	if sf == null:
		return
	var want: Dictionary = FRAMES[name]
	assert_eq(sf.get_animation_names().size(), want.size(), "%s animation count" % name)
	for anim in want:
		assert_true(sf.has_animation(anim), "%s has %s" % [name, anim])
		assert_eq(sf.get_frame_count(anim), want[anim], "%s/%s frame count" % [name, anim])


func test_anomaly_is_violet_not_cyan() -> void:
	# IDEAS §21.1: cyan means shield. Every visible anomaly pixel must sit in the purple/magenta hue band.
	var img := _image("energy_anomaly")
	var bad := 0
	var seen := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5 or c.s < 0.25 or c.v < 0.2:
				continue
			seen += 1
			if c.h < 0.70 or c.h > 0.95:
				bad += 1
	assert_gt(seen, 1000, "anomaly has coloured pixels")
	assert_lt(float(bad) / float(seen), 0.02, "anomaly stays violet / magenta")


# ---------------------------------------------------------------------------------------------
# The minefield beacon (Phase 7, t9)
# ---------------------------------------------------------------------------------------------

const BEACON := "res://assault/assets/sprites/projectiles/mines/minefield_beacon.png"


func test_the_beacon_is_opaque_at_its_centre_and_transparent_at_its_corners() -> void:
	var tex := load(BEACON) as Texture2D
	assert_not_null(tex, "minefield_beacon.png loads")
	var img := tex.get_image()
	assert_eq(img.get_size(), Vector2i(32, 32), "a 32 x 32 buoy")
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.99:
				opaque += 1
	assert_lt(float(opaque) / float(img.get_width() * img.get_height()), OPAQUE_LIMIT, "the beacon is not a painted-in card")
	assert_gt(img.get_pixel(16, 16).a, 0.99, "opaque at the centre")
	for corner in [Vector2i(0, 0), Vector2i(31, 0), Vector2i(0, 31), Vector2i(31, 31)]:
		assert_eq(img.get_pixel(corner.x, corner.y).a, 0.0, "corner %s is transparent" % corner)


func test_the_minefield_beacon_uses_the_art_and_blinks_it() -> void:
	var field: Minefield = load("res://assault/scenes/hazards/minefield/minefield.tscn").instantiate()
	add_child_autofree(field)
	var beacon := field.get_node("Beacon") as MinefieldBeacon
	var sprite := beacon.get_node_or_null("Sprite") as Sprite2D
	assert_not_null(sprite, "the beacon has a Sprite")
	assert_eq(sprite.texture.resource_path, BEACON, "it wears minefield_beacon.png")
	beacon._process(0.1)
	assert_true(sprite.visible)
	assert_eq(sprite.modulate.a, 1.0, "bright half of the blink")
	beacon._process(0.5)
	assert_almost_eq(sprite.modulate.a, 0.35, 0.001, "dim half of the blink")
	beacon.lit = false
	assert_false(sprite.visible, "dark with the last mine")
