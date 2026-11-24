## Phase 11 art (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.9; task t9, task plan docs/plans/cmwt4y3hw00t8qs2yw6didjf1/3-plan.md): the Space
## Fortress hull, every part's intact / wreck art, the hangar's closed / open / wreck doors, the generators' shutter closed / open / wreck, the core's
## plated / open / wreck plating, the four thrusters and the critical overlay. INTENT tests.
##
## What a test can say about art: every texture is wired into the scene (replacing the station stand-ins), has the size of the hurtbox it stands for, is
## not a painted-in card (corners transparent, <= 90 % fully opaque), every destructible part swaps to a distinct wreck, the three door / shutter / plating
## states are distinct and shown at the right time, and no station PNG is left in the scene. Whether it *looks* right (strictly top-down, one palette,
## sockets where the parts sit) was checked by eye at 2-6x and in composites at in-game layout (see DECISIONS.md, Phase 11 t9).
##
## Geometry is frozen: no shape, part position or HomingPoint changes here; `test_space_fortress.gd` and the hurtbox / contact geometry gates read the same scene.
extends GutTest

const ART := "res://assault/assets/sprites/enemies/space_fortress/"
const SCENE_PATH := "res://assault/scenes/enemies/space_fortress/space_fortress.tscn"
const SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")

const MAX_OPAQUE := 0.90

## Every part: node -> [intact, wreck, flip_v]. The south generator mirrors the north art so its emitter fin faces outward.
const PARTS := {
	"BatterySpread": ["battery_spread.png", "battery_spread_wreck.png", false],
	"BatteryPulse": ["battery_pulse.png", "battery_pulse_wreck.png", false],
	"BatteryArtillery": ["battery_artillery.png", "battery_artillery_wreck.png", false],
	"BatteryMissiles": ["battery_missiles.png", "battery_missiles_wreck.png", false],
	"BatterySweep": ["battery_sweep.png", "battery_sweep_wreck.png", false],
	"Hangar": ["hangar_closed.png", "hangar_wreck.png", false],
	"ShieldNorth": ["generator_closed.png", "generator_wreck.png", false],
	"ShieldSouth": ["generator_closed.png", "generator_wreck.png", true],
	"Core": ["core_plated.png", "core_wreck.png", false],
}

## Every solid Phase 11 art file and its size (the hurtbox bounding boxes of §2.5.2; the hull is the 384 px canvas). The overlay has its own row.
const ALL_ART := {
	"fortress_hull.png": Vector2i(384, 384),
	"battery_spread.png": Vector2i(44, 44),
	"battery_spread_wreck.png": Vector2i(44, 44),
	"battery_pulse.png": Vector2i(44, 44),
	"battery_pulse_wreck.png": Vector2i(44, 44),
	"battery_artillery.png": Vector2i(44, 44),
	"battery_artillery_wreck.png": Vector2i(44, 44),
	"battery_missiles.png": Vector2i(44, 44),
	"battery_missiles_wreck.png": Vector2i(44, 44),
	"battery_sweep.png": Vector2i(44, 44),
	"battery_sweep_wreck.png": Vector2i(44, 44),
	"hangar_closed.png": Vector2i(36, 56),
	"hangar_open.png": Vector2i(36, 56),
	"hangar_wreck.png": Vector2i(36, 56),
	"generator_closed.png": Vector2i(52, 52),
	"generator_open.png": Vector2i(52, 52),
	"generator_wreck.png": Vector2i(52, 52),
	"core_plated.png": Vector2i(88, 88),
	"core_open.png": Vector2i(88, 88),
	"core_wreck.png": Vector2i(88, 88),
	"thruster.png": Vector2i(16, 24),
}

const OVERLAY := "critical_overlay.png"
const HULL_RADIUS := 176.0


func _image(rel: String) -> Image:
	var tex := load(ART + rel) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image().duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	return img


## [fully opaque fraction, visible (alpha > 0) fraction].
func _coverage(img: Image) -> Array[float]:
	var bytes := img.get_data()
	var n := bytes.size() / 4
	var opaque := 0
	var visible := 0
	for i in range(3, bytes.size(), 4):
		if bytes[i] == 255:
			opaque += 1
		if bytes[i] > 0:
			visible += 1
	return [float(opaque) / float(maxi(n, 1)), float(visible) / float(maxi(n, 1))]


func _assert_corners_clear(img: Image, rel: String) -> void:
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for corner in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		assert_eq(img.get_pixelv(corner).a, 0.0, "%s: transparent corner %s (no painted-in card)" % [rel, corner])


## One shared, never-mutated instance for the wiring rows; a fresh one for each row that changes state. Physics off: an idle brain would otherwise tick
## the reinforcements as inactive and close a door before the row reads it.
var _fortress: SpaceFortress


func before_all() -> void:
	_fortress = _fresh()


func after_all() -> void:
	_fortress.free()


func _fresh() -> SpaceFortress:
	var f := SCENE.instantiate() as SpaceFortress
	add_child(f)
	f.set_physics_process(false)
	return f


func _in_tree() -> SpaceFortress:
	var f := _fresh()
	autofree(f)
	return f


func _part(f: SpaceFortress, node: String) -> EnemyModule:
	return f.get_node("Modules/%s" % node) as EnemyModule


func _sprite(p: EnemyModule) -> Sprite2D:
	return p.get_node("Sprite") as Sprite2D


# ── 1. Every file ────────────────────────────────────────────────────────────────────────────────

func test_every_fortress_texture_exists_has_its_size_and_is_card_free(rel: String = use_parameters(ALL_ART.keys())) -> void:
	var img := _image(rel)
	assert_not_null(img, "%s must exist and import" % rel)
	if img == null:
		return
	assert_eq(img.get_size(), ALL_ART[rel], "%s: the size plan §2.9 / §2.5.2 gives" % rel)
	_assert_corners_clear(img, rel)
	var cover := _coverage(img)
	assert_lt(cover[0], MAX_OPAQUE, "%s: at most 90%% fully opaque" % rel)
	assert_gt(cover[0], 0.15, "%s: not an empty image" % rel)
	assert_gt(img.get_pixel(img.get_width() / 2, img.get_height() / 2).a, 0.0, "%s: something is drawn at its centre" % rel)


## 1b. The overlay sits over the hull in `critical`: a light layer of cracks, never a card that hides the hull.
func test_the_critical_overlay_is_a_light_overlay() -> void:
	var img := _image(OVERLAY)
	assert_not_null(img, "%s must exist and import" % OVERLAY)
	if img == null:
		return
	assert_eq(img.get_size(), Vector2i(384, 384), "the hull's canvas")
	_assert_corners_clear(img, OVERLAY)
	var cover := _coverage(img)
	assert_gt(cover[1], 0.01, "something is drawn")
	assert_lt(cover[1], 0.35, "at most 35% of the canvas is touched")
	assert_lt(cover[0], 0.20, "at most 20% fully opaque")


# ── 2-5. Wiring ──────────────────────────────────────────────────────────────────────────────────

func test_the_hull_is_wired_and_covers_its_body() -> void:
	var sprite := _fortress.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture.resource_path, ART + "fortress_hull.png", "hull texture")
	assert_eq(sprite.scale, Vector2.ONE, "art is authored at its natural size")
	assert_almost_eq(sprite.rotation, 0.0, 1e-6, "the sprite is not turned")
	assert_not_null(sprite.material, "the hit-flash material stays on the hull")
	var body := (_fortress.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var shown := sprite.texture.get_size() * sprite.scale
	assert_gte(shown.x, body.radius * 2.0, "hull art at least as wide as the body")
	assert_gte(shown.y, body.radius * 2.0, "hull art at least as tall as the body")


func test_every_part_is_wired(node: String = use_parameters(PARTS.keys())) -> void:
	var row: Array = PARTS[node]
	var p := _part(_fortress, node)
	var sprite := _sprite(p)
	assert_eq(p.intact_texture.resource_path, ART + row[0], "%s intact_texture" % node)
	assert_not_null(p.wreck_texture, "%s has a wreck texture" % node)
	if p.wreck_texture == null:
		return
	assert_eq(p.wreck_texture.resource_path, ART + row[1], "%s wreck_texture" % node)
	assert_ne(p.wreck_texture, p.intact_texture, "%s: intact and wreck differ" % node)
	assert_eq(sprite.texture, p.intact_texture, "%s shows its intact art" % node)
	assert_eq(sprite.scale, Vector2.ONE, "%s: natural size" % node)
	assert_eq(sprite.flip_v, row[2], "%s: only the south generator mirrors (its fin faces outward)" % node)
	assert_false(sprite.flip_h, "%s: never mirrored sideways" % node)
	# The art is exactly as large as the hurtbox it stands for.
	var shape := (p.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape
	var box := Vector2i.ZERO
	if shape is CircleShape2D:
		var d := int((shape as CircleShape2D).radius * 2.0)
		box = Vector2i(d, d)
	elif shape is RectangleShape2D:
		box = Vector2i((shape as RectangleShape2D).size)
	assert_eq(Vector2i(p.intact_texture.get_size()), box, "%s: the art is its hurtbox's size" % node)
	assert_eq(Vector2i(p.wreck_texture.get_size()), box, "%s: the wreck too" % node)


func test_a_destroyed_part_swaps_to_its_wreck() -> void:
	var f := _in_tree()
	for node: String in PARTS.keys():
		var p := _part(f, node)
		p.destroy()
		assert_eq(_sprite(p).texture, p.wreck_texture, "%s shows its wreck" % node)
		assert_eq(p.visual_state(), EnemyModule.VisualState.WRECK, node)


func test_the_five_batteries_are_distinct() -> void:
	var intact := {}
	var wreck := {}
	for node: String in ["BatterySpread", "BatteryPulse", "BatteryArtillery", "BatteryMissiles", "BatterySweep"]:
		var p := _part(_fortress, node)
		intact[p.intact_texture] = true
		wreck[p.wreck_texture] = true
	assert_eq(intact.size(), 5, "each battery has its own base: the player reads which corner fires what")
	assert_eq(wreck.size(), 5, "and its own wreck")


# ── 6. The hangar doors ──────────────────────────────────────────────────────────────────────────

func test_the_hangar_has_three_door_states() -> void:
	var f := _in_tree()
	var hangar := _part(f, "Hangar")
	assert_not_null(f.hangar_open_texture, "the open-doors art")
	if f.hangar_open_texture == null:
		return
	assert_eq(f.hangar_open_texture.resource_path, ART + "hangar_open.png")
	assert_ne(hangar.intact_texture, f.hangar_open_texture, "closed and open differ")
	assert_ne(f.hangar_open_texture, hangar.wreck_texture, "open and wreck differ")
	var doors := f.reinforcements().door_changed
	doors.emit(&"hangar", true)
	assert_eq(_sprite(hangar).texture, f.hangar_open_texture, "open doors show the open art")
	doors.emit(&"north_defenders", false)
	assert_eq(_sprite(hangar).texture, f.hangar_open_texture, "another bay's doors change nothing")
	doors.emit(&"hangar", false)
	assert_eq(_sprite(hangar).texture, hangar.intact_texture, "shut doors show the closed art")
	# Boundary: a wreck keeps its wreck whatever the doors report.
	hangar.destroy()
	doors.emit(&"hangar", true)
	assert_eq(_sprite(hangar).texture, hangar.wreck_texture, "a wreck never shows the open doors")
	doors.emit(&"hangar", false)
	assert_eq(_sprite(hangar).texture, hangar.wreck_texture, "nor the closed ones")


## 6b. Through the real door cycle (no hand-emitted signal): catches a renamed bay id.
func test_the_hangar_shows_its_open_art_through_the_real_door_cycle() -> void:
	var f := _in_tree()
	var hangar := _part(f, "Hangar")
	var bays := f.reinforcements()
	assert_eq(bays.surge(&"hangar", 1), 1, "one launch queued")
	bays.tick(0.0, true)
	assert_true(bays.door_open(&"hangar"), "the doors are opening")
	assert_eq(_sprite(hangar).texture, f.hangar_open_texture, "the open art shows while the doors open")
	bays.tick(0.0, false)
	assert_false(bays.door_open(&"hangar"), "an inactive tick closes the doors without a launch")
	assert_eq(_sprite(hangar).texture, hangar.intact_texture, "and the closed art is back")


# ── 7. Shutters and plating ──────────────────────────────────────────────────────────────────────

func test_the_generators_and_core_have_three_states() -> void:
	var f := _in_tree()
	var north := _part(f, "ShieldNorth")
	var south := _part(f, "ShieldSouth")
	var core := _part(f, "Core")
	assert_eq(f.shutter_open_texture.resource_path, ART + "generator_open.png", "open shutter art")
	assert_eq(f.core_open_texture.resource_path, ART + "core_open.png", "open plating art")
	for states in [[north.intact_texture, f.shutter_open_texture, north.wreck_texture], [core.intact_texture, f.core_open_texture, core.wreck_texture]]:
		assert_ne(states[0], states[1], "closed and open differ")
		assert_ne(states[1], states[2], "open and wreck differ")
		assert_ne(states[0], states[2], "closed and wreck differ")
	f._open_shutters()
	assert_eq(_sprite(north).texture, f.shutter_open_texture, "the north shutter opens")
	assert_eq(_sprite(south).texture, f.shutter_open_texture, "the south shutter opens")
	assert_true(_sprite(south).flip_v, "still mirrored once open")
	f._open_core_plating()
	assert_eq(_sprite(core).texture, f.core_open_texture, "the plating opens on exposure")


func test_a_wrecked_core_keeps_its_wreck_when_the_plating_opens() -> void:
	var f := _in_tree()
	var core := _part(f, "Core")
	core.destroy()
	f._open_core_plating()
	assert_eq(_sprite(core).texture, core.wreck_texture, "boundary: never the open plating over a wreck")


# ── 8. Thrusters and overlay ─────────────────────────────────────────────────────────────────────

func test_thrusters_and_overlay_are_wired() -> void:
	var thrusters := _fortress.get_node("Thrusters") as Node2D
	var overlay_root := _fortress.get_node("CriticalOverlay") as Node2D
	assert_false(thrusters.visible, "thrusters start hidden (core_exposed shows them)")
	assert_false(overlay_root.visible, "the overlay starts hidden (critical shows it)")
	var sprites: Array[Sprite2D] = []
	for child in thrusters.get_children():
		if child is Sprite2D:
			sprites.append(child)
	assert_eq(sprites.size(), 4, "four exhaust sprites")
	for s in sprites:
		assert_eq(s.texture.resource_path, ART + "thruster.png", "%s texture" % s.name)
		assert_eq(s.scale, Vector2.ONE, "%s: natural size" % s.name)
		assert_gt(s.position.length(), HULL_RADIUS, "%s sits outside the hull circle" % s.name)
		var outward := s.position.normalized()
		assert_gt(s.transform.y.normalized().dot(outward), 0.99, "%s: the plume (sprite +y) points away from the centre" % s.name)
	var overlay := overlay_root.get_node("Overlay") as Sprite2D
	assert_not_null(overlay, "CriticalOverlay/Overlay")
	if overlay == null:
		return
	assert_eq(overlay.texture.resource_path, ART + OVERLAY, "overlay texture")
	assert_eq(overlay.scale, Vector2.ONE, "natural size")
	assert_eq(overlay.position, Vector2.ZERO, "centred on the hull")


# ── 9. No station art ────────────────────────────────────────────────────────────────────────────

## Reads the scene file's own `SceneState`, never a live instance: a live fortress holds its rocket pools' rounds and `StateLight`'s code-built glow.
func test_no_station_art_in_the_fortress_scene() -> void:
	var state := SCENE.get_state()
	var paths := {}
	for i in state.get_node_count():
		for j in state.get_node_property_count(i):
			var value: Variant = state.get_node_property_value(i, j)
			if value is Texture2D:
				paths[(value as Texture2D).resource_path] = String(state.get_node_path(i))
	for path: String in paths:
		assert_true(path.begins_with(ART), "%s (on %s) is fortress art" % [path, paths[path]])
		assert_false(path.get_file().begins_with("station_"), "%s: no station PNG" % path)
	# So an empty walk cannot pass: the hull and every part's art are among them.
	assert_true(paths.has(ART + "fortress_hull.png"), "the hull is found")
	for node: String in PARTS.keys():
		assert_true(paths.has(ART + PARTS[node][0]), "%s intact art is found" % node)
		assert_true(paths.has(ART + PARTS[node][1]), "%s wreck art is found" % node)
	assert_true(paths.has(ART + "hangar_open.png"), "the open hangar is found")
	assert_true(paths.has(ART + "thruster.png"), "the thrusters are found")
	assert_true(paths.has(ART + OVERLAY), "the overlay is found")
	assert_false(FileAccess.get_file_as_string(SCENE_PATH).contains("station_"), "the scene file names no station resource")
