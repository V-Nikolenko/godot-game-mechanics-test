## Phase 9 art (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.14; task t12): the Hacker Frigate hull and dish, the Disruptor's accent fin, the three jamming
## towers and the EMP zone's beacon. INTENT tests.
##
## What a test can say about art: every sprite is wired into its scene (replacing the t7 / t8 / t11 placeholders), has the size the plan gives, an opaque pixel at its
## centre and a transparent corner (no painted-in card), covers the body it stands for, the Hacker's dish is a separate part whose scale moves between folded and
## unfolded, the Disruptor alone wears the accent fin, and state never recolours a hull. Whether it *looks* right (strictly top-down, nose-down, palette, a readable
## silhouette at in-game size) was checked by eye at 6x over a dark ground (see DECISIONS.md, t12).
##
## `test_entity_sprite_transparency.gd` already sweeps every scene under `assault/scenes/{enemies,hazards}`, which holds all of these.
extends GutTest

const ENEMY_ART := "res://assault/assets/sprites/enemies/"
const HAZARD_ART := "res://assault/assets/sprites/hazards/"
const HACKER: PackedScene = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn")
const DISRUPTOR: PackedScene = preload("res://assault/scenes/enemies/hacker_disruptor/hacker_disruptor.tscn")
const LOCAL_JAMMER: PackedScene = preload("res://assault/scenes/enemies/jamming_structure/jamming_structure.tscn")
const SECTOR_JAMMER: PackedScene = preload("res://assault/scenes/enemies/sector_jammer/sector_jammer.tscn")
const PULSED_JAMMER: PackedScene = preload("res://assault/scenes/enemies/pulsed_jammer/pulsed_jammer.tscn")
const EMP_ZONE: PackedScene = preload("res://assault/scenes/hazards/emp_zone/emp_zone.tscn")

## Scene key -> [scene, the sprite node's path, its texture, the texture's size]. Plan §2.14's table.
const HOSTS := {
	"hacker": ["hacker", "Hull", ENEMY_ART + "hacker_frigate.png", Vector2i(96, 96)],
	"hacker_dish": ["hacker", "Dish/Antenna", ENEMY_ART + "hacker_dish.png", Vector2i(32, 32)],
	"disruptor": ["disruptor", "Hull", ENEMY_ART + "hacker_frigate.png", Vector2i(96, 96)],
	"disruptor_dish": ["disruptor", "Dish/Antenna", ENEMY_ART + "hacker_dish.png", Vector2i(32, 32)],
	"disruptor_fin": ["disruptor", "Accent", ENEMY_ART + "hacker_disruptor_fin.png", Vector2i(32, 32)],
	"local": ["local", "Hull", ENEMY_ART + "jamming_structure.png", Vector2i(64, 64)],
	"pulsed": ["pulsed", "Hull", ENEMY_ART + "pulsed_jammer.png", Vector2i(64, 64)],
	"sector": ["sector", "Hull", ENEMY_ART + "sector_jammer.png", Vector2i(96, 96)],
	"beacon": ["zone", "Beacon", HAZARD_ART + "emp_zone_beacon.png", Vector2i(32, 32)],
}

## Scenes whose root has a body `CircleShape2D` the hull must cover (the zone and the dish parts have none).
const BODIES := ["hacker", "disruptor", "local", "pulsed", "sector"]


func _scene(key: String) -> PackedScene:
	match key:
		"hacker":
			return HACKER
		"disruptor":
			return DISRUPTOR
		"local":
			return LOCAL_JAMMER
		"pulsed":
			return PULSED_JAMMER
		"sector":
			return SECTOR_JAMMER
	return EMP_ZONE


## An instance in the tree (the `Dish` and `Brain` are `@onready`), physics off so nothing moves.
func _in_tree(key: String) -> Node:
	var host := _scene(key).instantiate()
	host.set_physics_process(false)
	add_child_autofree(host)
	return host


func _image(path: String) -> Image:
	return (load(path) as Texture2D).get_image().duplicate()


func _assert_card_free(img: Image, label: String) -> void:
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for corner in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		assert_eq(img.get_pixelv(corner).a, 0.0, "%s: transparent corner %s" % [label, corner])


func _row_width(img: Image, y: int) -> int:
	var n := 0
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.5:
			n += 1
	return n


func test_every_sprite_is_wired_sized_opaque_at_its_centre_and_card_free(key: String = use_parameters(HOSTS.keys())) -> void:
	var spec: Array = HOSTS[key]
	var host := _scene(spec[0]).instantiate()
	var sprite := host.get_node_or_null(NodePath(spec[1])) as Sprite2D
	assert_not_null(sprite, "%s: a Sprite2D at %s (the placeholder Polygon2D is gone)" % [key, spec[1]])
	if sprite == null:
		host.free()
		return
	assert_not_null(sprite.texture, "%s: it has a texture" % key)
	assert_eq(sprite.texture.resource_path, spec[2], "%s: its own art" % key)
	var img := _image(sprite.texture.resource_path)
	assert_eq(img.get_size(), spec[3], "%s: texture size (plan §2.14)" % key)
	assert_gt(img.get_pixel(img.get_width() / 2, img.get_height() / 2).a, 0.99, "%s: opaque at the centre" % key)
	_assert_card_free(img, key)
	host.free()


func test_no_placeholder_polygons_are_left_in_the_scenes() -> void:
	for key in ["hacker", "disruptor", "local", "pulsed", "sector", "zone"]:
		var host := _scene(key).instantiate()
		var polygons := host.find_children("*", "Polygon2D", true, false)
		assert_eq(polygons.size(), 0, "%s: no placeholder Polygon2D" % key)
		host.free()


func test_the_hull_art_covers_its_body_circle(key: String = use_parameters(BODIES)) -> void:
	# The art must be at least as big as the body circle it stands for (hurtbox-geometry's visual twin), and not dwarf it. The Hacker's narrow hull is its
	# length; a tower's triangle / star is its width.
	var host := _scene(key).instantiate()
	var shape := (host.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	var used := _image((host.get_node("Hull") as Sprite2D).texture.resource_path).get_used_rect()
	var reach := float(maxi(used.size.x, used.size.y)) * 0.5
	# The sector jammer is a star: its arms reach 37 px of its r 42 body, the hub is smaller; 6 px of slack, not 3.
	assert_gte(reach, shape.radius - (6.0 if key == "sector" else 3.0), "%s: the art spans the %s px body" % [key, shape.radius])
	assert_lte(reach, shape.radius + 10.0, "%s: and does not dwarf it" % key)
	host.free()


func test_the_hacker_hull_is_a_nose_down_narrow_hull() -> void:
	# IDEAS §21 / plan §2.10: nose-down art (sprite_forward_angle PI/2) and a hull narrower than it is long.
	var img := _image(ENEMY_ART + "hacker_frigate.png")
	var used := img.get_used_rect()
	assert_gt(used.size.y, used.size.x, "longer than it is wide")
	var near_nose := _row_width(img, used.end.y - 6)
	var near_tail := _row_width(img, used.position.y + 6)
	var mid := _row_width(img, used.position.y + used.size.y / 2)
	assert_lt(near_nose, mid, "the bottom (the nose) tapers in")
	assert_lte(near_nose, near_tail + 4, "and is no broader than the engine block")
	var hacker := HACKER.instantiate() as HackerFrigate
	assert_almost_eq(EnemyMover.sprite_forward_angle_of(hacker), PI * 0.5, 0.001, "the mover turns nose-down art")
	hacker.free()


func test_the_dish_is_its_own_part_off_the_hull_centre_with_the_light_on_it() -> void:
	for key in ["hacker", "disruptor"]:
		var host := _in_tree(key) as HackerFrigate
		var dish := host.dish()
		assert_not_null(dish, "%s: a Dish part" % key)
		assert_ne(dish.position, Vector2.ZERO, "%s: the dish sits off the hull centre" % key)
		assert_not_null(dish.get_node_or_null("Antenna"), "%s: the dish part draws the antenna sprite" % key)
		assert_eq(host.state_light().get_parent(), dish, "%s: the StateLight is on the dish, not the hull" % key)
		var hull := host.get_node("Hull") as Sprite2D
		assert_ne(dish, hull, "%s: the dish is not the hull" % key)
		assert_false(dish.is_ancestor_of(hull), "%s: the hull is not part of the dish" % key)


func test_the_dish_moves_between_folded_and_unfolded() -> void:
	for key in ["hacker", "disruptor"]:
		var host := _in_tree(key) as HackerFrigate
		var dish := host.dish()
		var antenna := dish.get_node("Antenna") as Sprite2D
		var tex_w := float(antenna.texture.get_width())
		host.set_dish_open(0.0)
		var folded := dish.scale
		var folded_w := tex_w * folded.x
		host.set_dish_open(1.0)
		var open := dish.scale
		var open_w := tex_w * open.x
		assert_eq(folded, Vector2.ONE * HackerFrigate.DISH_FOLDED_SCALE, "%s: folded is the folded scale" % key)
		assert_eq(open, Vector2.ONE, "%s: unfolded is full size" % key)
		assert_lt(folded_w, open_w, "%s: the folded dish draws smaller than the open one" % key)
		assert_almost_eq(open_w, 32.0, 0.01, "%s: the open dish is the 32 px part" % key)
		host.set_dish_open(0.5)
		assert_between(dish.scale.x, folded.x, open.x, "%s: halfway is between the two" % key)
		assert_gt(dish.scale.x, folded.x, "%s: and past folded" % key)
		assert_lt(dish.scale.x, open.x, "%s: and short of open" % key)


func test_only_the_disruptor_wears_the_accent_fin() -> void:
	var base := HACKER.instantiate()
	var variant := DISRUPTOR.instantiate()
	assert_null(base.get_node_or_null("Accent"), "the base Hacker has no accent part")
	var fin := variant.get_node_or_null("Accent") as Sprite2D
	assert_not_null(fin, "the Disruptor has one")
	if fin != null:
		assert_eq(fin.texture.resource_path, ENEMY_ART + "hacker_disruptor_fin.png")
		assert_gt(fin.position.length(), 8.0, "the fin sits off the hull's centre line, so the variant's silhouette differs")
		var hull_used := _image(ENEMY_ART + "hacker_frigate.png").get_used_rect()
		var fin_used := _image(ENEMY_ART + "hacker_disruptor_fin.png").get_used_rect()
		assert_gt(float(fin_used.size.x) + fin.position.length(), float(hull_used.size.x) * 0.5, "it reaches past the hull's flank")
	base.free()
	variant.free()


func test_the_variants_share_the_hull_and_dish_but_the_towers_each_have_their_own_art() -> void:
	var seen := {}
	for key in ["local", "pulsed", "sector"]:
		var host := _scene(key).instantiate()
		var path := (host.get_node("Hull") as Sprite2D).texture.resource_path
		assert_false(seen.has(path), "%s: its own tower art" % key)
		seen[path] = true
		host.free()
	assert_eq(seen.size(), 3)
	# Three silhouettes that read apart at range: the masks laid on one canvas differ by a wide margin.
	var masks := {}
	for path: String in seen:
		var img := _image(path)
		var mask := {}
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					mask[Vector2i(x, y)] = true
		masks[path] = mask
	var paths := masks.keys()
	for i in paths.size():
		for j in range(i + 1, paths.size()):
			var a: Dictionary = masks[paths[i]]
			var b: Dictionary = masks[paths[j]]
			var union := a.size()
			var diff := 0
			for p: Vector2i in a:
				if not b.has(p):
					diff += 1
			for p: Vector2i in b:
				if not a.has(p):
					diff += 1
					union += 1
			assert_gte(float(diff) / float(maxi(union, 1)), 0.08, "%s and %s have distinct silhouettes" % [paths[i], paths[j]])


func test_the_jammer_lens_is_baked_amber_and_the_state_light_sits_on_the_centre() -> void:
	# State is a light, never a recoloured hull: the baked lens is amber (never cyan = shield, never violet = boost disruption) and the StateLight on the
	# centre is what blinks. The centre pixel of each tower reads warm.
	for key in ["local", "pulsed", "sector"]:
		var host := _scene(key).instantiate()
		var img := _image((host.get_node("Hull") as Sprite2D).texture.resource_path)
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		assert_gt(c.r, c.b + 0.1, "%s: a warm (amber) lens at the centre" % key)
		assert_eq((host.get_node("StateLight") as Node2D).position, Vector2.ZERO, "%s: the light is on the lens" % key)
		assert_eq((host.get_node("Hull") as Sprite2D).position, Vector2.ZERO, "%s: the hull is centred on the body" % key)
		host.free()


func test_the_beacon_is_neutral_not_faction_red() -> void:
	var img := _image(HAZARD_ART + "emp_zone_beacon.png")
	var red := 0
	var cool := 0
	var opaque := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			opaque += 1
			if c.r > c.b + 0.15 and c.r > c.g + 0.15:
				red += 1
			if c.b >= c.r:
				cool += 1
	assert_lt(float(red) / float(opaque), 0.05, "the zone is neutral: (almost) no red pixels")
	assert_gt(float(cool) / float(opaque), 0.6, "grey / blue-white: mostly cool")
	var zone := EMP_ZONE.instantiate() as EmpZone
	var beacon := zone.get_node("Beacon") as Sprite2D
	assert_eq(beacon.position, Vector2.ZERO, "centred on the zone")
	assert_eq(beacon.get_parent(), zone, "a child of the zone, not of its field (the field art is code-drawn)")
	zone.free()


func test_the_hit_flash_targets_a_node_that_exists_in_every_host() -> void:
	for key in ["hacker", "disruptor", "local", "pulsed", "sector"]:
		var host := _scene(key).instantiate()
		var player := host.get_node("HitFlashAnimationPlayer") as AnimationPlayer
		for anim_name in ["hit", "RESET"]:
			var anim := player.get_animation(anim_name)
			var path: NodePath = anim.track_get_path(0)
			var node := host.get_node_or_null(NodePath(path.get_concatenated_names()))
			assert_not_null(node, "%s/%s: the flash track (%s) names a real node" % [key, anim_name, path])
			assert_true(node is Sprite2D, "%s/%s: and it is the sprite" % [key, anim_name])
		host.free()


func test_state_never_recolours_a_hull() -> void:
	var hacker := HACKER.instantiate() as HackerFrigate
	add_child_autofree(hacker)
	hacker.set_dish_open(1.0)
	hacker.show_charge(0.5)
	var hull := hacker.get_node("Hull") as Sprite2D
	assert_eq(hull.modulate, Color.WHITE, "the hull is untinted while the dish opens and the ring closes")
	assert_eq(hull.self_modulate, Color.WHITE)
	assert_eq(hacker.modulate, Color.WHITE)
	var tower := LOCAL_JAMMER.instantiate() as JammingStructure
	tower.set_physics_process(false)
	add_child_autofree(tower)
	assert_eq((tower.get_node("Hull") as Sprite2D).modulate, Color.WHITE, "the tower hull is untinted; its light is the state")
	assert_eq(tower.modulate, Color.WHITE)
