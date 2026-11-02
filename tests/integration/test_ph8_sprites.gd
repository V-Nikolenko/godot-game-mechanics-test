## Phase 8 structure art (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.15; task t15): the turret base, the six turret heads, the heavy
## emplacement base, the shield generator, the power source and its glow, and the laser emitter post. INTENT tests.
##
## What a test can say about art: every sprite is wired into its scene, has an opaque pixel where its pivot / centre is and a transparent corner (no
## painted-in card), no two turret heads share a silhouette, a head sits on its mount so it turns with it (nose along the mount's +X), and state is
## shown by moving parts and lights only: an unpowered turret darkens the *mount* (head) and never the base, the power source's glow hides when its
## group goes dark and no hull `modulate` changes. Whether it *looks* right was checked by eye at 6x and in a composite (see DECISIONS.md, t15).
##
## `test_entity_sprite_transparency.gd` already sweeps every scene under `assault/scenes/enemies`, which holds all of these; no scene under
## `assault/scenes/structures` draws a texture (the turret group and the laser fence are coordinators over enemy members), so that sweep's roots are
## unchanged.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const ART_DIR := "res://assault/assets/sprites/enemies/"
const TURRET_SCENE: PackedScene = preload("res://assault/scenes/enemies/defense_turret/defense_turret.tscn")
const HEAVY_SCENE: PackedScene = preload("res://assault/scenes/enemies/heavy_emplacement/heavy_emplacement.tscn")
const POWER_SCENE: PackedScene = preload("res://assault/scenes/enemies/power_source/power_source.tscn")
const GENERATOR_SCENE: PackedScene = preload("res://assault/scenes/enemies/shield_generator/shield_generator.tscn")
const EMITTER_SCENE: PackedScene = preload("res://assault/scenes/enemies/laser_emitter/laser_emitter.tscn")

## Mount variant -> its head texture. One entry per `TurretMount.Variant`.
const HEADS := {
	TurretMount.Variant.BURST_CANNON: "turret_head_burst_cannon.png",
	TurretMount.Variant.SWEEP_BEAM: "turret_head_sweep_beam.png",
	TurretMount.Variant.ROCKET_BATTERY: "turret_head_rocket_battery.png",
	TurretMount.Variant.PULSE_RING: "turret_head_pulse_ring.png",
	TurretMount.Variant.LANCE: "turret_head_lance.png",
	TurretMount.Variant.BEAM_CANNON: "turret_head_beam_cannon.png",
}

## Host scene -> [the sprite node's name, its texture, the texture's size].
const HOSTS := {
	"turret": ["Base", "defense_turret_base.png", Vector2i(64, 64)],
	"heavy": ["Base", "heavy_emplacement_base.png", Vector2i(144, 144)],
	"generator": ["Sprite2D", "shield_generator.png", Vector2i(72, 72)],
	"power": ["Sprite2D", "power_source.png", Vector2i(80, 80)],
	"emitter": ["Sprite2D", "laser_emitter.png", Vector2i(40, 40)],
}

## Two heads differ when their alpha masks, laid on one canvas, disagree on at least this fraction of the pixels either covers.
const MIN_MASK_DIFF := 0.08


class FakeGroup:
	extends Node
	signal power_changed(powered: bool)
	var owner_group: StringName = &"fake_group"


func _host_scene(key: String) -> PackedScene:
	match key:
		"turret":
			return TURRET_SCENE
		"heavy":
			return HEAVY_SCENE
		"generator":
			return GENERATOR_SCENE
		"power":
			return POWER_SCENE
	return EMITTER_SCENE


func _image(path: String) -> Image:
	return (load(path) as Texture2D).get_image().duplicate()


func _alpha(img: Image, x: int, y: int) -> float:
	return img.get_pixel(x, y).a


func _assert_card_free(img: Image, label: String) -> void:
	var w := img.get_width() - 1
	var h := img.get_height() - 1
	for corner in [Vector2i(0, 0), Vector2i(w, 0), Vector2i(0, h), Vector2i(w, h)]:
		assert_eq(_alpha(img, corner.x, corner.y), 0.0, "%s: transparent corner %s" % [label, corner])


func test_every_host_sprite_is_wired_opaque_at_its_centre_and_card_free(key: String = use_parameters(HOSTS.keys())) -> void:
	var spec: Array = HOSTS[key]
	var host := _host_scene(key).instantiate()
	var sprite := host.get_node_or_null(spec[0]) as Sprite2D
	assert_not_null(sprite, "%s: a Sprite2D named %s" % [key, spec[0]])
	if sprite == null:
		host.free()
		return
	assert_eq(sprite.position, Vector2.ZERO, "%s: at the body's centre" % key)
	assert_not_null(sprite.texture, "%s: it has a texture" % key)
	assert_eq(sprite.texture.resource_path, ART_DIR + spec[1], "%s: its own art" % key)
	var img := _image(sprite.texture.resource_path)
	assert_eq(img.get_size(), spec[2], "%s: texture size" % key)
	assert_gt(_alpha(img, img.get_width() / 2, img.get_height() / 2), 0.99, "%s: opaque at the centre" % key)
	_assert_card_free(img, key)
	host.free()


func test_the_heavy_base_and_hulls_cover_their_bodies() -> void:
	# The sprite must be at least as big as the body circle it stands for (hurtbox-geometry's visual twin).
	for key in ["turret", "heavy", "generator", "power", "emitter"]:
		var host := _host_scene(key).instantiate()
		var shape := (host.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
		var sprite := host.get_node(HOSTS[key][0]) as Sprite2D
		var used := _image(sprite.texture.resource_path).get_used_rect()
		assert_gte(float(used.size.x) * 0.5, shape.radius - 1.0, "%s: the art spans the %s px body" % [key, shape.radius])
		host.free()


func test_the_glow_is_amber_additive_and_centred_on_the_core() -> void:
	var host := POWER_SCENE.instantiate()
	var glow := host.get_node("Glow") as Sprite2D
	assert_eq(glow.texture.resource_path, ART_DIR + "power_source_glow.png")
	assert_true(glow.material is CanvasItemMaterial, "additive, so it reads as light")
	assert_eq((glow.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	var img := _image(glow.texture.resource_path)
	_assert_card_free(img, "glow")
	# The orb sits on the sprite origin: the opaque rect (plus the node offset) is centred on it.
	var used := img.get_used_rect()
	var centre := Vector2(used.position) + Vector2(used.size) * 0.5
	var drawn := centre - Vector2(img.get_size()) * 0.5 + glow.offset
	assert_lt(drawn.length(), 1.0, "the orb's centre lands on the sprite origin")
	host.free()


func test_every_mount_variant_has_a_head_sprite_that_turns_with_it(variant: int = use_parameters(HEADS.keys())) -> void:
	var mount := TurretMountScenes.scene_for(variant).instantiate() as TurretMount
	var head := mount.get_node_or_null("Head") as Sprite2D
	assert_not_null(head, "variant %d: a Head sprite on the mount" % variant)
	if head == null:
		mount.free()
		return
	assert_eq(head.texture.resource_path, ART_DIR + HEADS[variant], "variant %d: its own head" % variant)
	assert_almost_eq(head.rotation, -PI * 0.5, 0.001, "variant %d: nose-down art points along the mount's +X" % variant)
	assert_true(head.show_behind_parent, "variant %d: muzzle lamps draw over the head" % variant)
	assert_false(head.centered, "variant %d: the pivot is the texture pixel the offset names" % variant)
	var img := _image(head.texture.resource_path)
	var pivot := Vector2i(-head.offset)
	assert_gt(_alpha(img, pivot.x, pivot.y), 0.99, "variant %d: opaque at the pivot the head turns on" % variant)
	_assert_card_free(img, "variant %d" % variant)
	# The art's far end is the muzzle (a ring coil has none): the barrel tip sits within 6 px of the Muzzle marker.
	var muzzle := mount.get_node_or_null("Muzzle") as Marker2D
	if muzzle != null:
		var used := img.get_used_rect()
		var tip := float(used.end.y) - float(pivot.y)
		assert_almost_eq(tip, muzzle.position.x, 6.0, "variant %d: the head's tip is at the muzzle" % variant)
	mount.free()


func test_no_two_heads_share_a_silhouette() -> void:
	var masks := {}
	for variant: int in HEADS:
		var img := _image(ART_DIR + HEADS[variant])
		var mask := {}
		# Laid on the heads' common pivot-free canvas: top-left aligned, which is how two files differ on disk.
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					mask[Vector2i(x, y)] = true
		masks[variant] = mask
	var keys := masks.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Dictionary = masks[keys[i]]
			var b: Dictionary = masks[keys[j]]
			var union := a.size()
			var diff := 0
			for p: Vector2i in a:
				if not b.has(p):
					diff += 1
			for p: Vector2i in b:
				if not a.has(p):
					diff += 1
					union += 1
			assert_gte(float(diff) / float(maxi(union, 1)), MIN_MASK_DIFF, "heads %d and %d have distinct silhouettes" % [keys[i], keys[j]])


func test_no_two_heads_share_a_texture() -> void:
	var seen := {}
	for variant: int in HEADS:
		assert_false(seen.has(HEADS[variant]), "%s is used once" % HEADS[variant])
		seen[HEADS[variant]] = true
	assert_eq(HEADS.size(), TurretMount.Variant.size(), "every mount variant has a head")


func test_the_hit_flash_targets_a_node_that_exists_in_every_host() -> void:
	for key in HOSTS:
		var host := _host_scene(key).instantiate()
		var player := host.get_node("HitFlashAnimationPlayer") as AnimationPlayer
		var anim := player.get_animation("hit")
		var path: NodePath = anim.track_get_path(0)
		assert_not_null(host.get_node_or_null(NodePath(path.get_concatenated_names())), "%s: the hit flash track (%s) names a real node" % [key, path])
		host.free()


func _world() -> Object:
	var h = HARNESS.open_space()
	add_child_autofree(h.root)
	return h


func test_unpowered_darkens_the_head_only_and_never_the_base() -> void:
	var h = _world()
	var t := TURRET_SCENE.instantiate() as DefenseTurret
	t.set_physics_process(false)
	h.root.add_child(t)
	var mount := t.mounts()[0]
	var head := mount.get_node("Head") as Sprite2D
	var base := t.get_node("Base") as Sprite2D
	assert_eq(mount.modulate, Color.WHITE, "lit: the head is untinted")
	t.set_powered(false)
	assert_lt(mount.modulate.r, 0.6, "unpowered: the head (the mount) is darkened")
	assert_eq(head.get_parent(), mount, "the head is on the mount, so it droops with it")
	assert_eq(base.modulate, Color.WHITE, "no hull is recoloured by state")
	assert_eq(base.self_modulate, Color.WHITE, "no hull is recoloured by state")
	assert_eq(t.modulate, Color.WHITE)


func test_the_heavy_emplacement_wears_two_heads_on_its_one_base() -> void:
	var h = _world()
	var t := HEAVY_SCENE.instantiate() as DefenseTurret
	t.set_physics_process(false)
	h.root.add_child(t)
	var mounts := t.mounts()
	assert_eq(mounts.size(), 2)
	var heads := []
	for m in mounts:
		var head := m.get_node("Head") as Sprite2D
		heads.append(head.texture.resource_path)
	assert_eq(heads[0], ART_DIR + HEADS[TurretMount.Variant.BEAM_CANNON], "the beam cannon's head")
	assert_eq(heads[1], ART_DIR + HEADS[TurretMount.Variant.BURST_CANNON], "the burst cannon's head")
	assert_eq(t.get_node_or_null("Base").get_child_count(), 0, "the base is one plain sprite; the heads sit on the mounts")
	t.set_powered(false)
	for m in mounts:
		assert_lt(m.modulate.r, 0.6, "both heads go dark")
	assert_eq((t.get_node("Base") as Sprite2D).modulate, Color.WHITE)


func test_the_power_source_glow_hides_when_its_group_goes_dark() -> void:
	var h = _world()
	var group := FakeGroup.new()
	h.root.add_child(group)
	var src := POWER_SCENE.instantiate() as PowerSource
	src.set_physics_process(false)
	src.set_turret_group(group)
	h.root.add_child(src)
	var glow := src.get_node("Glow") as Sprite2D
	var hull := src.get_node("Sprite2D") as Sprite2D
	assert_true(glow.visible, "lit while the group is powered")
	group.power_changed.emit(false)
	assert_false(glow.visible, "the glow hides when the group goes dark")
	assert_eq(hull.modulate, Color.WHITE, "the hull is not recoloured")
	assert_eq(hull.self_modulate, Color.WHITE)


func test_the_generator_and_emitter_hulls_are_never_tinted_by_state() -> void:
	var h = _world()
	var gen := GENERATOR_SCENE.instantiate() as ShieldGenerator
	gen.set_physics_process(false)
	h.root.add_child(gen)
	gen.set_powered(false)
	assert_eq((gen.get_node("Sprite2D") as Sprite2D).modulate, Color.WHITE)
	assert_eq(gen.modulate, Color.WHITE)
	var post := EMITTER_SCENE.instantiate() as LaserEmitter
	post.set_physics_process(false)
	h.root.add_child(post)
	assert_eq((post.get_node("Sprite2D") as Sprite2D).modulate, Color.WHITE)
