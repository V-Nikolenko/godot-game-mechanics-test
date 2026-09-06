## Invariant test: every code-built contact `HitBox` describes the same hull as the body it was
## built from — the same `Shape2D` resource AND the node transform that sizes and places it.
##
## NOT characterization. A contact box that is a different size from the ship the player can see
## is a defect, not a quirk to pin: the gunship's hull is 41.5 px wide and its ram box was built at
## 18 px, so 62 % of the heaviest ship in the roster passed through the player like a ghost.
##
## ── Why this file exists ─────────────────────────────────────────────────────────────────────
##
## A `Shape2D` is a resource; it carries the radius but NOT the `CollisionShape2D.scale` that
## multiplies it at runtime. Four places built a contact `HitBox` by copying `col.shape` alone
## (`base_enemy.gd`, `drone_interceptor.gd`, `kamikaze_drone.gd`, `ally_fighter.gd`), so every
## entity that sizes its body by scaling its collision shape — six of them — got a contact box at
## the *unscaled* radius. The fix is `HitBox.matching_shape()`, which copies the transform too;
## this file is what keeps a fifth call site from getting it wrong again.
##
## ── Harness notes ────────────────────────────────────────────────────────────────────────────
##
## The harness is `test_enemy_contact_damage.gd`'s, with one deliberate difference: `_spawn()` and
## `_contact_hitbox()` are typed **`Node2D`**, not `BaseEnemy`. `AllyFighter` is
## `class_name AllyFighter extends CharacterBody2D` (`ally_fighter.gd:1-2`) and is not a
## `BaseEnemy`, so the enemy-typed harness would fail its row with "root is not a BaseEnemy" — a
## failure that looks exactly like the bug under test but is not one. `ally_fighter` must stay in
## the roster regardless: it is the only coverage of the fourth call site.
##
## Otherwise the same three rules apply as in `test_enemy_contact_damage.gd`: each entity gets a
## throwaway container `Node2D` parent (effects and the bullet pool scribble on `get_parent()`),
## each is added to the tree so `_ready()` runs, and only DIRECT children are searched for the
## `HitBox` (bullets carry their own, under the pool; the station's turrets carry theirs, under
## `Turrets`).
extends GutTest

## `scene`: the entity to instantiate. `no_hitbox`: expected to carry no contact HitBox at all.
const ROSTER: Array[Dictionary] = [
	{
		"name": "ally_fighter",
		"scene": "res://assault/scenes/allies/ally_fighter/ally_fighter.tscn",
	},
	{
		"name": "bomber",
		"scene": "res://assault/scenes/enemies/bomber/bomber.tscn",
	},
	{
		"name": "bonus_drone",
		"scene": "res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn",
		"no_hitbox": true,
	},
	{
		"name": "drone_interceptor",
		"scene": "res://assault/scenes/enemies/drone_interceptor/drone_interceptor.tscn",
	},
	{
		"name": "gunship",
		"scene": "res://assault/scenes/enemies/gunship/gunship.tscn",
	},
	{
		"name": "interceptor",
		"scene": "res://assault/scenes/enemies/interceptor/interceptor.tscn",
	},
	{
		"name": "kamikaze_drone",
		"scene": "res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn",
	},
	{
		"name": "light_assault_ship",
		"scene": "res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn",
	},
	{
		"name": "ram_ship",
		"scene": "res://assault/scenes/enemies/ram_ship/ram_ship.tscn",
	},
	{
		"name": "space_station",
		"scene": "res://assault/scenes/enemies/space_station/space_station.tscn",
	},
	{
		"name": "sniper_enemy",
		"scene": "res://assault/scenes/enemies/sniper_enemy/sniper_enemy.tscn",
	},
]


## Typed `Node2D`, not `BaseEnemy` — see the harness note in the file header.
func _spawn(entry: Dictionary) -> Node2D:
	var container := Node2D.new()
	add_child_autofree(container)
	var scene: PackedScene = load(entry["scene"]) as PackedScene
	assert_not_null(scene, "%s: scene failed to load" % entry["name"])
	var entity := scene.instantiate() as Node2D
	assert_not_null(entity, "%s: root is not a Node2D" % entry["name"])
	container.add_child(entity)
	return entity


## Direct children only — see the harness note in the file header.
func _contact_hitbox(entity: Node2D) -> HitBox:
	for child in entity.get_children():
		var hb := child as HitBox
		if hb != null:
			return hb
	return null


## The `CollisionShape2D` the scene author drew to describe the hull. All four call sites read it
## by this exact name (`get_node_or_null("CollisionShape2D")`).
func _body_shape_node(entity: Node2D) -> CollisionShape2D:
	return entity.get_node_or_null("CollisionShape2D") as CollisionShape2D


func test_every_contact_hitbox_matches_its_body_shape() -> void:
	for entry in ROSTER:
		if entry.get("no_hitbox", false):
			continue
		var entity := _spawn(entry)
		var body := _body_shape_node(entity)
		assert_not_null(body, "%s: has no body CollisionShape2D" % entry["name"])
		var hb := _contact_hitbox(entity)
		assert_not_null(hb, "%s: has no contact HitBox as a direct child" % entry["name"])
		if body == null or hb == null:
			continue

		var shape_nodes: Array[CollisionShape2D] = []
		for child in hb.get_children():
			var cs := child as CollisionShape2D
			if cs != null:
				shape_nodes.append(cs)
		assert_eq(
			shape_nodes.size(),
			1,
			"%s: contact HitBox must have exactly one CollisionShape2D child" % entry["name"]
		)
		if shape_nodes.size() != 1:
			continue

		assert_eq(
			shape_nodes[0].shape,
			body.shape,
			"%s: contact HitBox must use the body's own Shape2D resource" % entry["name"]
		)
		assert_eq(
			shape_nodes[0].transform,
			body.transform,
			(
				"%s: contact HitBox must carry the body's transform — a Shape2D alone drops the "
				+ "scale that sizes it, making the ram box smaller than the visible hull"
			) % entry["name"]
		)


## Guard against this file quietly becoming a test of nothing. Four of the roster's entities
## author their body at `scale = 1`, where the assertion above passes even unfixed. If the scaled
## scenes were ever re-authored at true size the sweep would still be green while asserting
## nothing. Mirrors the vacuity guard in `test_enemy_contact_damage.gd`.
func test_the_roster_contains_a_scaled_body_or_this_file_is_vacuous() -> void:
	var scaled: Array[String] = []
	for entry in ROSTER:
		var entity := _spawn(entry)
		var body := _body_shape_node(entity)
		if body != null and body.transform != Transform2D.IDENTITY:
			scaled.append(entry["name"])
	assert_gt(
		scaled.size(),
		0,
		"no roster entity has a non-identity body transform, so the geometry sweep asserts nothing"
	)


## The one case the transform-copy design genuinely cannot represent: a non-uniform scale on a
## circle has no equivalent shape, so the physics server would silently produce a hull that is not
## the one the author drew. No scene uses one today; this makes that a gate failure rather than a
## mystery bug.
func test_no_body_collision_shape_uses_non_uniform_scale() -> void:
	for entry in ROSTER:
		var entity := _spawn(entry)
		var body := _body_shape_node(entity)
		if body == null:
			continue
		assert_almost_eq(
			body.scale.x,
			body.scale.y,
			0.0001,
			(
				"%s: body CollisionShape2D has a non-uniform scale, which a copied transform "
				+ "cannot faithfully reproduce on every Shape2D type"
			) % entry["name"]
		)


## The deliberate exception must survive the refactor: `bonus_drone` overrides the helper to add
## nothing at all, which is the correct realisation of its `collision_damage = 0`.
func test_bonus_drone_still_has_no_contact_hitbox() -> void:
	for entry in ROSTER:
		if not entry.get("no_hitbox", false):
			continue
		var entity := _spawn(entry)
		assert_null(
			_contact_hitbox(entity),
			"%s: is declared contact-harmless but carries a HitBox" % entry["name"]
		)
