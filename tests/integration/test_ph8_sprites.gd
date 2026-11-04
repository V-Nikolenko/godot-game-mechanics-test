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
const DRONE_SCENE: PackedScene = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn")
const TENDER_SCENE: PackedScene = preload("res://assault/scenes/enemies/laser_tender/laser_tender.tscn")

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
	"drone": ["Sprite2D", "twin_laser_drone.png", Vector2i(32, 32)],
	"tender": ["Sprite2D", "laser_tender.png", Vector2i(96, 96)],
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
		"drone":
			return DRONE_SCENE
		"tender":
			return TENDER_SCENE
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


# ── t16: the Twin-Laser Drone, the Laser Tender and its docked-drone cradle sprite ───────────────────────────────────────────────────────────────

const CRADLE_ART := "laser_tender_cradle_drone.png"
## The two lens pixels of `twin_laser_drone.png` the `StateLight` lights, as texture coordinates (a 2 x 2 block) and as an offset from the centre.
const LENS_PIXELS: Array[Vector2i] = [Vector2i(15, 25), Vector2i(16, 25), Vector2i(15, 26), Vector2i(16, 26)]


func test_the_drone_and_tender_art_is_at_least_as_big_as_its_body_circle() -> void:
	# The drone's art is a 22 px hull inside its r 13 circle (the wings are the width); the tender spans its r 40 body.
	for key in ["drone", "tender"]:
		var host := _host_scene(key).instantiate()
		var shape := (host.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
		var sprite := host.get_node("Sprite2D") as Sprite2D
		var used := _image(sprite.texture.resource_path).get_used_rect()
		assert_gte(float(used.size.x) * 0.5, shape.radius - 3.0, "%s: the art spans the %s px body" % [key, shape.radius])
		assert_lte(float(used.size.x) * 0.5, shape.radius + 10.0, "%s: and does not dwarf it" % key)
		host.free()


func test_the_drone_lens_is_baked_dark_and_the_state_light_sits_on_it() -> void:
	# State is a light, never a recoloured hull: the baked lens is unlit and the StateLight (red while the beam is up) is what lights it.
	var drone := DRONE_SCENE.instantiate()
	var img := _image(ART_DIR + "twin_laser_drone.png")
	var sum := Vector2.ZERO
	for p in LENS_PIXELS:
		var c := img.get_pixel(p.x, p.y)
		assert_gt(c.a, 0.99, "the lens pixel %s is part of the hull" % p)
		assert_lt(c.v, 0.3, "the lens pixel %s is dark in the texture" % p)
		sum += Vector2(p) + Vector2(0.5, 0.5)
	var lens := sum / float(LENS_PIXELS.size()) - Vector2(img.get_size()) * 0.5
	var light := drone.get_node("StateLight") as Node2D
	assert_almost_eq(light.position.x, lens.x, 1.0, "the StateLight is on the lens (x)")
	assert_almost_eq(light.position.y, lens.y, 1.0, "the StateLight is on the lens (y)")
	assert_eq((drone.get_node("Sprite2D") as Sprite2D).modulate, Color.WHITE, "no hull recolouring")
	drone.free()


func test_the_lens_lights_while_the_beam_is_up() -> void:
	var h = _world()
	var d := DRONE_SCENE.instantiate() as TwinLaserDrone
	d.set_physics_process(false)
	h.root.add_child(d)
	var brain := d.brain()
	brain.start_engaged = true
	assert_eq(d.state_light().get_state(), StateLight.State.OFF, "unlit before anything is shown")
	brain._set_light(StateLight.State.ARMED)
	assert_eq(d.state_light().get_state(), StateLight.State.ARMED, "the lens lights red (ARMED) through the StateLight")
	var lit := d.state_light().modulate
	assert_gt(lit.a, 0.2, "the lit lens is visible")
	assert_gt(lit.r, lit.b, "and red")


func test_the_cradle_sprite_is_the_docked_drone_and_card_free() -> void:
	var img := _image(ART_DIR + CRADLE_ART)
	assert_eq(img.get_size(), Vector2i(28, 28), "a 28 px docked drone")
	assert_gt(_alpha(img, 14, 14), 0.99, "opaque at the centre")
	_assert_card_free(img, "cradle drone")
	var h = _world()
	var tender := TENDER_SCENE.instantiate() as LaserTender
	tender.set_physics_process(false)
	h.root.add_child(tender)
	var bays := tender.cradles()
	assert_eq(bays.size(), 2)
	for c: Marker2D in bays:
		var docked := c.get_node_or_null("DockedDrone") as Sprite2D
		assert_not_null(docked, "%s holds a DockedDrone sprite" % c.name)
		if docked != null:
			assert_eq(docked.texture.resource_path, ART_DIR + CRADLE_ART, "%s: the docked-drone art" % c.name)
			assert_eq(docked.position, Vector2.ZERO, "%s: centred on its cradle" % c.name)
	assert_eq(bays[0].position, Vector2(-bays[1].position.x, bays[1].position.y), "the cradles mirror each other")


func test_the_cradles_sit_in_the_hull_bays() -> void:
	# The bays are the two round pits of laser_tender.png: dark floor, a ring around it. Each cradle marker lands on the dark floor, so a launched
	# (hidden) docked drone leaves a visibly empty bay.
	var img := _image(ART_DIR + "laser_tender.png")
	var h = _world()
	var tender := TENDER_SCENE.instantiate() as LaserTender
	tender.set_physics_process(false)
	h.root.add_child(tender)
	for c: Marker2D in tender.cradles():
		var p := Vector2i(c.position + Vector2(img.get_size()) * 0.5)
		assert_gt(img.get_pixelv(p).a, 0.99, "%s: on the hull" % c.name)
		var mean := 0.0
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				mean += img.get_pixel(p.x + dx, p.y + dy).v / 25.0
		assert_lt(mean, 0.3, "%s: on the dark floor of a bay (mean value %.2f)" % [c.name, mean])


func test_cradle_visibility_follows_launch_and_rearm(mode: String = use_parameters(["open_space", "assault"])) -> void:
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	var t := TENDER_SCENE.instantiate() as LaserTender
	t.set_physics_process(false)
	t.collision_mask = 0
	h.root.add_child(t)
	var l := t.get_node("CradleL/DockedDrone") as CanvasItem
	var r := t.get_node("CradleR/DockedDrone") as CanvasItem
	assert_true(l.visible and r.visible, "%s: both docked drones show on a fresh tender" % mode)
	var rig := t.launch_pair(PackedVector2Array([Vector2(-200, 300), Vector2(200, 300)]))
	assert_not_null(rig, "%s: the launch happened" % mode)
	assert_false(l.visible, "%s: the left cradle is empty after launch" % mode)
	assert_false(r.visible, "%s: the right cradle is empty after launch" % mode)
	t.rearm_cradles()
	assert_true(l.visible and r.visible, "%s: both cradles show a drone again after rearm" % mode)
	for d: Variant in [rig.drone_a, rig.drone_b]:
		if is_instance_valid(d):
			(d as Node).set_physics_process(false)
