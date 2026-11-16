## Phase 10 art (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.9 / §2.10; task t9): the Heavy Gunship and Carrier hulls and every part's intact / wreck art,
## the hangar's closed / open / wreck doors and the core's plated / exposed / wreck states. INTENT tests.
##
## What a test can say about art: every texture is wired into its scene (replacing the t4 / t6 stand-ins), has the size the plan gives, is not a painted-in card
## (corner transparent, <= 90% opaque), the hull covers the body it stands for, every destructible part has distinct intact and wreck art and swaps to the wreck on
## destruction, the hangar has three door textures and the core three plating states. Whether it *looks* right (strictly top-down, nose-down, faction palette, sockets
## where the parts sit) was checked by eye at 6x over a dark ground (see DECISIONS.md, t9).
##
## Geometry is frozen in t9: the flush-edge row of `test_heavy_gunship.gd` and the `module_x_extent` row of `test_carrier.gd` are the gates for it, and they pass unchanged.
extends GutTest

const ART := "res://assault/assets/sprites/enemies/"
const GUNSHIP: PackedScene = preload("res://assault/scenes/enemies/heavy_gunship/heavy_gunship.tscn")
const CARRIER: PackedScene = preload("res://assault/scenes/enemies/carrier/carrier.tscn")

const MAX_OPAQUE := 0.90

## Gunship hull and every part: module node (or "" = the hull) -> [intact, wreck ("" = none, the vent is never destroyed), size, mirrored on the starboard side].
const GUNSHIP_PARTS := {
	"BatteryPort": ["heavy_gunship/battery.png", "heavy_gunship/battery_wreck.png", Vector2i(32, 40), false],
	"BatteryStarboard": ["heavy_gunship/battery.png", "heavy_gunship/battery_wreck.png", Vector2i(32, 40), true],
	"Cannon": ["heavy_gunship/cannon.png", "heavy_gunship/cannon_wreck.png", Vector2i(32, 24), false],
	"Missiles": ["heavy_gunship/missiles.png", "heavy_gunship/missiles_wreck.png", Vector2i(40, 24), false],
	"VentPort": ["heavy_gunship/vent.png", "", Vector2i(16, 24), false],
	"VentStarboard": ["heavy_gunship/vent.png", "", Vector2i(16, 24), true],
}

const CARRIER_PARTS := {
	"EnginePort": ["carrier/engine.png", "carrier/engine_wreck.png", Vector2i(48, 48)],
	"EngineStarboard": ["carrier/engine.png", "carrier/engine_wreck.png", Vector2i(48, 48)],
	"GunPort": ["carrier/gun.png", "carrier/gun_wreck.png", Vector2i(48, 48)],
	"GunStarboard": ["carrier/gun.png", "carrier/gun_wreck.png", Vector2i(48, 48)],
	"HangarPort": ["carrier/hangar_closed.png", "carrier/hangar_wreck.png", Vector2i(64, 56)],
	"HangarStarboard": ["carrier/hangar_closed.png", "carrier/hangar_wreck.png", Vector2i(64, 56)],
	"Core": ["carrier/core_plated.png", "carrier/core_wreck.png", Vector2i(64, 64)],
}

## Every Phase 10 art file and its size (hull sizes are the plan's table).
const ALL_ART := {
	"heavy_gunship/hull.png": Vector2i(112, 144),
	"heavy_gunship/battery.png": Vector2i(32, 40),
	"heavy_gunship/battery_wreck.png": Vector2i(32, 40),
	"heavy_gunship/cannon.png": Vector2i(32, 24),
	"heavy_gunship/cannon_wreck.png": Vector2i(32, 24),
	"heavy_gunship/missiles.png": Vector2i(40, 24),
	"heavy_gunship/missiles_wreck.png": Vector2i(40, 24),
	"heavy_gunship/vent.png": Vector2i(16, 24),
	"carrier/hull.png": Vector2i(192, 288),
	"carrier/engine.png": Vector2i(48, 48),
	"carrier/engine_wreck.png": Vector2i(48, 48),
	"carrier/gun.png": Vector2i(48, 48),
	"carrier/gun_wreck.png": Vector2i(48, 48),
	"carrier/hangar_closed.png": Vector2i(64, 56),
	"carrier/hangar_open.png": Vector2i(64, 56),
	"carrier/hangar_wreck.png": Vector2i(64, 56),
	"carrier/core_plated.png": Vector2i(64, 64),
	"carrier/core_exposed.png": Vector2i(64, 64),
	"carrier/core_wreck.png": Vector2i(64, 64),
}

var _old_art := [
	"heave_gunship.png", "heave_gunship.png.import", "heavy_gunship_non_shielded.png", "heavy_gunship_non_shielded.png.import", "heavy_gunship_non_shielded.pdn",
]


func _tex(rel: String) -> Texture2D:
	return load(ART + rel) as Texture2D


func _image(rel: String) -> Image:
	var tex := _tex(rel)
	if tex == null:
		return null
	var img := tex.get_image().duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	return img


func _opaque_fraction(img: Image) -> float:
	var bytes := img.get_data()
	var n := bytes.size() / 4
	var opaque := 0
	for i in range(3, bytes.size(), 4):
		if bytes[i] == 255:
			opaque += 1
	return float(opaque) / float(maxi(n, 1))


## One shared, never-mutated instance of each scene for the wiring rows (a scene instance costs more than a texture check), and a fresh one for each destruction row.
var _gunship: Node
var _carrier: Node


func before_all() -> void:
	_gunship = _fresh(GUNSHIP)
	_carrier = _fresh(CARRIER)


func after_all() -> void:
	_gunship.free()
	_carrier.free()


func _fresh(packed: PackedScene) -> Node:
	var host := packed.instantiate()
	host.set_physics_process(false)
	add_child(host)
	return host


func _in_tree(packed: PackedScene) -> Node:
	var host := _fresh(packed)
	autofree(host)
	return host


func test_every_phase10_texture_exists_has_its_size_and_is_card_free(rel: String = use_parameters(ALL_ART.keys())) -> void:
	var tex := _tex(rel)
	assert_not_null(tex, "%s must exist and import" % rel)
	if tex == null:
		return
	var size: Vector2i = ALL_ART[rel]
	assert_eq(Vector2i(tex.get_width(), tex.get_height()), size, "%s: the size plan §2.10 gives" % rel)
	var img := _image(rel)
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for corner in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		assert_eq(img.get_pixelv(corner).a, 0.0, "%s: transparent corner %s (no painted-in card)" % [rel, corner])
	assert_lt(_opaque_fraction(img), MAX_OPAQUE, "%s: at most 90%% fully opaque" % rel)
	assert_gt(_opaque_fraction(img), 0.15, "%s: not an empty image" % rel)
	var centre := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	assert_gt(centre.a, 0.0, "%s: something is drawn at its centre" % rel)


func test_the_old_gunship_art_is_gone() -> void:
	for f: String in _old_art:
		assert_false(FileAccess.file_exists(ART + f), "%s is deleted (plan §2.4.1)" % f)
	assert_false(ResourceLoader.exists(ART + "heave_gunship.png"), "the old hull does not import any more")


func test_the_gunship_hull_is_wired_and_covers_its_body() -> void:
	var g := _gunship
	var sprite := g.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture.resource_path, ART + "heavy_gunship/hull.png", "hull texture")
	assert_eq(sprite.scale, Vector2.ONE, "art is authored at its natural size")
	assert_almost_eq(sprite.rotation, 0.0, 1e-6, "the art is drawn nose-down, so the sprite is not turned")
	var body := (g.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var shown := sprite.texture.get_size() * sprite.scale
	assert_almost_eq(shown.x, body.size.x, 0.01, "hull art as wide as the body")
	assert_almost_eq(shown.y, body.size.y, 0.01, "hull art as tall as the body")


func test_every_gunship_part_is_wired(key: String = use_parameters(GUNSHIP_PARTS.keys())) -> void:
	var g := _gunship
	var row: Array = GUNSHIP_PARTS[key]
	var part := g.get_node("Modules/%s" % key) as EnemyModule
	var sprite := part.get_node("Sprite") as Sprite2D
	assert_eq(part.intact_texture.resource_path, ART + row[0], "%s intact_texture" % key)
	assert_eq(sprite.texture, part.intact_texture, "%s shows its intact art" % key)
	assert_eq(sprite.scale, Vector2.ONE, "%s: natural size" % key)
	assert_eq(sprite.flip_h, row[3], "%s: the starboard side mirrors the port art" % key)
	var shape := (part.get_node("HurtBox/CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	assert_eq(Vector2i(part.intact_texture.get_size()), Vector2i(shape.size), "%s: the art is its hurtbox's size" % key)
	if row[1] == "":
		assert_eq(part.max_health, 0, "%s has no wreck because it is never destroyed" % key)
	else:
		assert_eq(part.wreck_texture.resource_path, ART + row[1], "%s wreck_texture" % key)
		assert_ne(part.wreck_texture, part.intact_texture, "%s: intact and wreck differ" % key)


func test_a_destroyed_gunship_part_swaps_to_its_wreck() -> void:
	var g := _in_tree(GUNSHIP)
	for key: String in ["BatteryPort", "BatteryStarboard", "Cannon", "Missiles"]:
		var part := g.get_node("Modules/%s" % key) as EnemyModule
		part.destroy()
		assert_eq((part.get_node("Sprite") as Sprite2D).texture, part.wreck_texture, "%s shows its wreck" % key)
		assert_eq(part.visual_state(), EnemyModule.VisualState.WRECK, key)


func test_the_carrier_hull_is_wired_and_covers_its_body() -> void:
	var c := _carrier
	var sprite := c.get_node("Sprite2D") as Sprite2D
	assert_eq(sprite.texture.resource_path, ART + "carrier/hull.png", "hull texture")
	assert_eq(sprite.scale, Vector2.ONE, "art is authored at its natural size")
	var body := (c.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var shown := sprite.texture.get_size() * sprite.scale
	assert_gte(shown.x, body.size.x, "hull art at least as wide as the body")
	assert_gte(shown.y, body.size.y, "hull art at least as tall as the body")


func test_every_carrier_part_is_wired(key: String = use_parameters(CARRIER_PARTS.keys())) -> void:
	var c := _carrier
	var row: Array = CARRIER_PARTS[key]
	var part := c.get_node("Modules/%s" % key) as EnemyModule
	var sprite := part.get_node("Sprite") as Sprite2D
	assert_eq(part.intact_texture.resource_path, ART + row[0], "%s intact_texture" % key)
	assert_eq(part.wreck_texture.resource_path, ART + row[1], "%s wreck_texture" % key)
	assert_ne(part.wreck_texture, part.intact_texture, "%s: intact and wreck differ" % key)
	assert_eq(sprite.texture, part.intact_texture, "%s shows its intact art" % key)
	assert_eq(sprite.scale, Vector2.ONE, "%s: natural size" % key)
	assert_eq(Vector2i(part.intact_texture.get_size()), row[2], "%s: the size plan §2.10 gives" % key)


func test_a_destroyed_carrier_part_swaps_to_its_wreck() -> void:
	var c := _in_tree(CARRIER)
	for key: String in CARRIER_PARTS.keys():
		var part := c.get_node("Modules/%s" % key) as EnemyModule
		part.destroy()
		assert_eq((part.get_node("Sprite") as Sprite2D).texture, part.wreck_texture, "%s shows its wreck" % key)
		assert_eq(part.visual_state(), EnemyModule.VisualState.WRECK, key)


func test_the_hangar_has_three_door_states(key: String = use_parameters(["HangarPort", "HangarStarboard"])) -> void:
	var c := _carrier
	var part := c.get_node("Modules/%s" % key) as EnemyModule
	var doors := part.get_node("Doors") as CarrierHangarDoors
	assert_not_null(doors.open_texture, "%s: the open-doors art" % key)
	assert_eq(doors.open_texture.resource_path, ART + "carrier/hangar_open.png")
	var states := [part.intact_texture, doors.open_texture, part.wreck_texture]
	assert_eq(states.size(), 3)
	assert_ne(states[0], states[1], "closed and open differ")
	assert_ne(states[1], states[2], "open and wreck differ")
	assert_ne(states[0], states[2], "closed and wreck differ")
	var mirrored: bool = key == "HangarStarboard"
	assert_eq((part.get_node("Sprite") as Sprite2D).flip_h, mirrored, "%s: the starboard hangar mirrors the port art (the bay opens to its own flank)" % key)
	assert_eq(doors.scale.x, -1.0 if mirrored else 1.0, "%s: the open art mirrors with the closed art" % key)


func test_the_hangar_doors_show_the_open_art_as_they_open() -> void:
	var doors := _carrier.get_node("Modules/HangarPort/Doors") as CarrierHangarDoors
	assert_false(doors.uses_art_open(), "shut doors show only the closed hangar art")
	doors.open_amount = 1.0
	assert_true(doors.uses_art_open(), "open doors show the open art")
	doors.broken = true
	assert_false(doors.uses_art_open(), "a wreck shows the wreck art, never the open doors")
	doors.broken = false
	doors.open_amount = 0.0


func test_the_core_has_three_plating_states() -> void:
	var c := _in_tree(CARRIER) as Carrier
	var core := c.get_node("Modules/Core") as EnemyModule
	assert_eq(c.core_open_texture.resource_path, ART + "carrier/core_exposed.png", "exposed art")
	assert_ne(c.core_open_texture, core.intact_texture)
	assert_ne(c.core_open_texture, core.wreck_texture)
	c._open_core_plating()
	assert_eq((core.get_node("Sprite") as Sprite2D).texture, c.core_open_texture, "the plating opens on exposure")
