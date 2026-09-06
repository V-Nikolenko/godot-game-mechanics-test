## Invariant test: every assault entity's `HurtBox` covers the body the player collides with.
## Armour is a *damage rule* on a full-size hurtbox, never an absent hurtbox.
##
## NOT characterization. A stretch of visibly solid hull that swallows shots and reports nothing
## is a defect, not a quirk to pin. This file is the companion to
## `test_contact_hitbox_geometry.gd`: that one polices the box an enemy hits the player *with*,
## this one polices the box the player hits the enemy *on*.
##
## ── Why this file exists ─────────────────────────────────────────────────────────────────────
##
## The backlog asked whether the space station's core `HurtBox` should shrink from the hull's
## 240x240 to an 88-wide central strip, so its x-extents stop overlapping the four turrets'. The
## answer is no, and the reasoning is in
## `docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/3-plan.md` and in
## `assault/scenes/enemies/space_station/ENEMY.md`. The short version: it would make 25 % of the
## boss's visible width dead in phase 1 and 66 % dead in phase 2 — where `station_turret.gd:73-77`
## closes each dead turret's hurtbox, so the strip is all that is left — on a hull that is
## *rotating* at that point. A decision that only lives in prose gets re-litigated; this file is
## the decision as a gate, and `test_the_88x240_proposal_fails_this_sweep` is the specific
## proposal, permanently red.
##
## ── What is actually enforced, precisely ─────────────────────────────────────────────────────
##
## `HurtBox ⊇ body CollisionShape2D`, **not** `HurtBox ⊇ sprite`. Those differ: the station's
## body collider is 240x240 under a 256x256 sprite, so 8 px per edge of visible hull is outside
## *both* boxes. That pre-existing lip is out of scope here — do not mistake this sweep for an
## art check.
##
## The assertion is one-sided (coverage, not equality) on purpose. The defect this file exists to
## catch is **undamageable visible hull**. An oversized hurtbox is the opposite defect, no
## decision has ruled on a tolerance for it, and asserting near-equality today would silently
## forbid a future deliberate widening nobody has considered.
##
## ── Harness notes ────────────────────────────────────────────────────────────────────────────
##
## Copied from `test_contact_hitbox_geometry.gd:84-107`, same three rules: a throwaway container
## `Node2D` per entity (effects and bullet pools scribble on `get_parent()`), each entity added to
## the tree so `_ready()` runs, and only DIRECT children searched for the `HurtBox` (the station's
## turrets carry their own, under `Turrets`).
##
## Geometry is compared as entity-local `Rect2`s via `cs.transform * cs.shape.get_rect()`, so the
## `CollisionShape2D.scale` that a `Shape2D` resource does not carry is included. Rects are AABBs:
## a *rotated* collision shape would compare as its bounding box rather than as itself. No roster
## entity rotates one, and the sweep instantiates everything at rest — before `station_laser_phase`
## can spin the hull.
extends GutTest

## Inward slack tolerated per edge before a hurtbox counts as failing to cover its body.
##
## Bounded by the smallest projectile *half-width* in the game, so a tolerated gap can never be
## one a projectile fits through: the enemy bullet capsule is `radius = 2.0`
## (`enemy_bullet.tscn`), and the player bullet is a default-radius-10 capsule under a root
## `scale.x = 0.236342` (`bullet.tscn:13-17`) — 4.73 px wide, 2.36 px half-width. The enemy figure
## is the conservative one even though enemy bullets are layer 256 / mask 128 and never test an
## enemy hurtbox at all.
##
## It is load-bearing from the first line, not a patch applied after a red run: three of the
## eleven entries fail a bare `Rect2.encloses()`, two of them by ~1e-5 px of float noise
## (gunship: body 83.079 px vs hurtbox 82.405 px is the only real one).
const _TOLERANCE_PX: float = 1.0

## The proposal this file exists to reject, verbatim from the backlog item.
const _PROPOSED_CORE_SIZE := Vector2(88.0, 240.0)

const _ENEMY_DIRS: Array[String] = [
	"res://assault/scenes/enemies",
	"res://assault/scenes/allies",
]

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


## Typed `Node2D`, not `BaseEnemy` — `AllyFighter` is `class_name AllyFighter extends
## CharacterBody2D` (`ally_fighter.gd:1-2`) and a `BaseEnemy`-typed harness would fail its row
## with "root is not a BaseEnemy", a failure that reads exactly like the bug under test.
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
func _hurt_box(entity: Node2D) -> HurtBox:
	for child in entity.get_children():
		var hb := child as HurtBox
		if hb != null:
			return hb
	return null


## The `CollisionShape2D` the scene author drew to describe the hull, by the exact name every
## contact-HitBox build site reads it under.
func _body_shape_node(entity: Node2D) -> CollisionShape2D:
	return entity.get_node_or_null("CollisionShape2D") as CollisionShape2D


func _sole_shape_node(parent: Node) -> CollisionShape2D:
	var found: Array[CollisionShape2D] = []
	for child in parent.get_children():
		var cs := child as CollisionShape2D
		if cs != null:
			found.append(cs)
	if found.size() != 1:
		return null
	return found[0]


## Entity-local AABB of a `CollisionShape2D`, including every transform between it and the
## entity root. `cs.shape.get_rect()` is shape-local; `cs.transform` adds the scale a `Shape2D`
## resource does not carry; the `extra` transform adds the owning `Area2D`'s own placement.
func _local_rect(cs: CollisionShape2D, extra: Transform2D = Transform2D.IDENTITY) -> Rect2:
	return extra * (cs.transform * cs.shape.get_rect())


## The predicate, factored out so the negative case can call it directly instead of hand-editing
## a tracked scene. `hurt` must contain `body` once grown outward by `_TOLERANCE_PX` per edge.
func _covers(body_rect: Rect2, hurt_rect: Rect2) -> bool:
	return hurt_rect.grow(_TOLERANCE_PX).encloses(body_rect)


## Per-edge shortfall in pixels, for a failure message that says how far short and on which side
## rather than printing two rects and leaving the reader to subtract.
func _shortfall(body_rect: Rect2, hurt_rect: Rect2) -> String:
	var grown := hurt_rect.grow(_TOLERANCE_PX)
	var left := grown.position.x - body_rect.position.x
	var top := grown.position.y - body_rect.position.y
	var right := body_rect.end.x - grown.end.x
	var bottom := body_rect.end.y - grown.end.y
	return "left %.3f, top %.3f, right %.3f, bottom %.3f (positive = uncovered hull)" % [
		left, top, right, bottom
	]


## Returns `{"body": Rect2, "hurt": Rect2}`, or an empty dictionary if the entity is not shaped
## the way `test_every_roster_entry_has_exactly_one_hurtbox_with_one_shape` requires. Callers
## skip on empty; that test is what reports the structural failure.
func _rects(entity: Node2D) -> Dictionary:
	var body := _body_shape_node(entity)
	if body == null or body.shape == null:
		return {}
	var hb := _hurt_box(entity)
	if hb == null:
		return {}
	var hurt_cs := _sole_shape_node(hb)
	if hurt_cs == null or hurt_cs.shape == null:
		return {}
	return {
		"body": _local_rect(body),
		"hurt": _local_rect(hurt_cs, hb.transform),
	}


# ── The sweep ─────────────────────────────────────────────────────────────────

func test_every_hurtbox_covers_its_body_hull() -> void:
	for entry in ROSTER:
		var entity := _spawn(entry)
		var rects := _rects(entity)
		if rects.is_empty():
			continue
		assert_true(
			_covers(rects["body"], rects["hurt"]),
			(
				"%s: HurtBox does not cover the body collider — that much of the hull the player "
				+ "can see takes shots and reports nothing. Shortfall: %s"
			) % [entry["name"], _shortfall(rects["body"], rects["hurt"])]
		)


## The boundary case, and the reason this file is not just a formality: the actual 88x240
## proposal, applied to a live station, must fail the predicate above.
##
## Applied to the **instance's** `CollisionShape2D` with a **fresh** `RectangleShape2D` — never
## by mutating `cs.shape.size`. `space_station.tscn:22-23` shares one `RectangleShape2D_ss`
## sub-resource between the body collider and the core HurtBox and it is not
## `resource_local_to_scene`, so an in-place edit would resize the body too, would make this test
## vacuously pass, and would poison every other station instantiated in the same process.
func test_the_88x240_proposal_fails_this_sweep() -> void:
	var entity := _spawn({
		"name": "space_station",
		"scene": "res://assault/scenes/enemies/space_station/space_station.tscn",
	})
	var body := _body_shape_node(entity)
	var hb := _hurt_box(entity)
	assert_not_null(body, "station: has no body CollisionShape2D")
	assert_not_null(hb, "station: has no HurtBox as a direct child")
	if body == null or hb == null:
		return
	var hurt_cs := _sole_shape_node(hb)
	assert_not_null(hurt_cs, "station: HurtBox must have exactly one CollisionShape2D")
	if hurt_cs == null:
		return

	var narrowed := RectangleShape2D.new()
	narrowed.size = _PROPOSED_CORE_SIZE
	hurt_cs.shape = narrowed

	var body_rect := _local_rect(body)
	var hurt_rect := _local_rect(hurt_cs, hb.transform)
	assert_false(
		_covers(body_rect, hurt_rect),
		(
			"the 88x240 core proposal must FAIL this sweep. If it passes, the sweep has been "
			+ "loosened into a rubber stamp. Shortfall: %s"
		) % _shortfall(body_rect, hurt_rect)
	)
	## Names the number, so a sweep that starts failing it for some unrelated reason is visible.
	assert_almost_eq(
		body_rect.end.x - hurt_rect.end.x,
		(240.0 - _PROPOSED_CORE_SIZE.x) * 0.5,
		0.001,
		"the proposal leaves 76 px of hull uncovered on each side"
	)


## Expressed relative to the scene rather than against a magic 239: epic task 4 adds station
## parts and task 1 re-derives the fight's numbers, and a legitimate hull resize should not
## redden this test with a message about a proposal nobody is making any more.
func test_the_station_core_hurtbox_spans_the_hull_not_just_the_core() -> void:
	var entity := _spawn({
		"name": "space_station",
		"scene": "res://assault/scenes/enemies/space_station/space_station.tscn",
	})
	var rects := _rects(entity)
	assert_false(rects.is_empty(), "station: not shaped as the sweep requires")
	if rects.is_empty():
		return
	assert_true(
		_covers(rects["body"], rects["hurt"]),
		"station: core HurtBox must cover the body collider — %s"
			% _shortfall(rects["body"], rects["hurt"])
	)

	## Derived from the turrets themselves, not hardcoded at 102: whatever ring they sit on, the
	## core hurtbox has to reach past it, or the shoulders go dead the moment the turret hurtboxes
	## close on death (`station_turret.gd:73-77`).
	var span: float = 0.0
	for turret in entity.get_node("Turrets").get_children():
		var t := turret as StationTurret
		var t_cs := _sole_shape_node(t.get_node("HurtBox"))
		assert_not_null(t_cs, "turret: HurtBox must have exactly one CollisionShape2D")
		if t_cs == null:
			continue
		var t_rect: Rect2 = t.transform * _local_rect(t_cs, (t.get_node("HurtBox") as Node2D).transform)
		span = maxf(span, maxf(absf(t_rect.position.x), absf(t_rect.end.x)))
	assert_gt(span, 0.0, "no turret contributed an x-extent — the derivation is vacuous")
	assert_gt(
		rects["hurt"].end.x,
		span,
		(
			"the core HurtBox must reach past the turret ring (x = %.1f). Narrower and the "
			+ "shoulders stop taking fire the moment the turrets die and close their own hurtboxes"
		) % span
	)


# ── Guards ────────────────────────────────────────────────────────────────────

## The roster is hand-maintained, so a new enemy would silently escape the sweep — the gap both
## `test_enemy_contact_damage.gd` and `test_contact_hitbox_geometry.gd` still have. `DirAccess`
## precedent: `test_suite_integrity.gd:51`, `test_project_load_integrity.gd:96`.
##
## Top-level directories only, deliberately: `assault/scenes/enemies/` also holds loose scripts
## (`base_enemy.gd`, `enemy_path_mover.gd`) and its subdirectories hold non-entity scenes
## (`light_assault_ship/states/`, `bomber/bomb.tscn`), all of which a recursive walk would raise
## as false failures.
func test_every_enemy_scene_is_in_the_roster() -> void:
	var rostered: Array[String] = []
	for entry in ROSTER:
		rostered.append(entry["scene"])
	for root in _ENEMY_DIRS:
		var dir := DirAccess.open(root)
		assert_not_null(dir, "cannot open %s" % root)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var scene_path := "%s/%s/%s.tscn" % [root, sub, sub]
			if not ResourceLoader.exists(scene_path):
				continue
			assert_true(
				rostered.has(scene_path),
				(
					"%s exists but is not in this file's ROSTER, so its HurtBox geometry is "
					+ "unchecked. Add it."
				) % scene_path
			)


func test_every_roster_entry_has_exactly_one_hurtbox_with_one_shape() -> void:
	for entry in ROSTER:
		var entity := _spawn(entry)
		var body := _body_shape_node(entity)
		assert_not_null(body, "%s: has no body CollisionShape2D" % entry["name"])
		var hb := _hurt_box(entity)
		assert_not_null(hb, "%s: has no HurtBox as a direct child" % entry["name"])
		if hb == null:
			continue
		assert_not_null(
			_sole_shape_node(hb),
			(
				"%s: HurtBox must have exactly one CollisionShape2D — a second one would be "
				+ "silently ignored by this sweep"
			) % entry["name"]
		)


## Guard against this file quietly becoming a test of nothing.
##
## The sweep compares two rects that are BOTH built by `_local_rect()`, so dropping the transform
## composition from it cancels out on almost every row and the sweep stays green while silently
## degrading to a raw `Shape2D` size comparison — measured, by stubbing `_local_rect()` to
## `return cs.shape.get_rect()` and watching all six tests pass. So this guard asserts the
## composition **changes the numbers**, not merely that some transform is non-identity: at least
## one roster entity's composed hurtbox rect must differ from its raw shape rect.
##
## Same intent as `test_contact_hitbox_geometry.gd:150-165`, but that file compares transforms
## directly and so cannot lose them this way.
func test_the_transform_composition_changes_at_least_one_rect_or_this_file_is_vacuous() -> void:
	var composed: Array[String] = []
	for entry in ROSTER:
		var entity := _spawn(entry)
		var hb := _hurt_box(entity)
		if hb == null:
			continue
		var cs := _sole_shape_node(hb)
		if cs == null or cs.shape == null:
			continue
		if _local_rect(cs, hb.transform) != cs.shape.get_rect():
			composed.append(entry["name"])
	assert_gt(
		composed.size(),
		0,
		"no roster entity's hurtbox rect is changed by the transform composition, so the sweep "
		+ "has degraded to comparing raw Shape2D sizes and would miss a hurtbox scaled down "
		+ "below its body"
	)
