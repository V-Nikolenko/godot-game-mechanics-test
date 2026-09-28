## Builds a `BaseEnemy` fixture with a `ContactHitBox` and, optionally, a scene-authored
## `ContactProfile`, for `test_contact_profile.gd` and `test_contact_blast_damage.gd`.
##
## Starts from `tests/helpers/fixture_enemy.tscn` (the minimum children `BaseEnemy._ready()` needs)
## and adds, BEFORE the enemy enters the tree, a code-built `ContactHitBox` shaped like every real
## enemy's: layer 256 (`enemy_hitbox`), mask 128 (`player_hurtbox`), CONTACT damage, a circle of
## `CONTACT_RADIUS`. Adding it before `add_child()` is what lets `BaseEnemy`'s `@onready`
## `get_node_or_null("ContactHitBox")` find it, exactly as it finds a scene-authored one.
##
## Also builds the player side: a real `HurtBox` (layer 128, mask 1281 — `player_fighter.tscn`'s
## values) whose `received_damage` drives a real `Health.decrease`, which is the
## `PlayerBase._apply_damage` path with no shield, no temp HP and no i-frames running.
##
## No `class_name`: test-only. `preload()` this script.
extends RefCounted

const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")

const CONTACT_RADIUS := 10.0
const CONTACT_DAMAGE := 30
const PLAYER_RADIUS := 12.0
const PLAYER_MAX_HEALTH := 100


## `profile` may be null: the enemy then resolves `BaseEnemy`'s default. The enemy is NOT added to
## the tree — the caller parents it (inside a container, so a blast has somewhere to land).
static func build_enemy(profile: ContactProfile, pos: Vector2) -> BaseEnemy:
	var enemy := FIXTURE_ENEMY.instantiate() as BaseEnemy
	enemy.position = pos
	var hit_box := HitBox.new()
	hit_box.name = "ContactHitBox"
	hit_box.collision_layer = CollisionLayers.ENEMY_HITBOX
	hit_box.collision_mask = CollisionLayers.PLAYER_HURTBOX
	hit_box.damage = CONTACT_DAMAGE
	hit_box.damage_type = HitBox.DamageType.CONTACT
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CONTACT_RADIUS
	shape.shape = circle
	hit_box.add_child(shape)
	enemy.add_child(hit_box)
	if profile != null:
		enemy.add_child(profile)
	return enemy


static func profile(mode: ContactProfile.Mode, blast_radius: float = 0.0, blast_damage: int = 0) -> ContactProfile:
	var p := ContactProfile.new()
	p.mode = mode
	p.blast_radius = blast_radius
	p.blast_damage = blast_damage
	return p


## A real player hurtbox + health pair, not in the tree. Returns the root `Node2D`; its children are
## `HurtBox` and `Health`, wired `received_damage -> decrease`.
static func build_player(pos: Vector2) -> Node2D:
	var root := Node2D.new()
	root.name = "PlayerFixture"
	root.position = pos
	var health := Health.new()
	health.name = "Health"
	health.max_health = PLAYER_MAX_HEALTH
	health.current_health = PLAYER_MAX_HEALTH
	root.add_child(health)
	var hurt_box := HurtBox.new()
	hurt_box.name = "HurtBox"
	hurt_box.collision_layer = CollisionLayers.PLAYER_HURTBOX
	hurt_box.collision_mask = 1281
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PLAYER_RADIUS
	shape.shape = circle
	hurt_box.add_child(shape)
	root.add_child(hurt_box)
	hurt_box.received_damage.connect(health.decrease)
	return root
