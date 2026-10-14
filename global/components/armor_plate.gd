## ArmorPlate — one breakable piece of armour on a full-size hull (the Ram Corvette's three).
##
## It sits under a `Plates` node, never as a direct child of the entity root, so the
## hurtbox-geometry gate's "exactly one direct-child HurtBox that covers the body" still holds
## (the space station's `Turrets` precedent). Armour is a *deflection rule*, not an absent
## hurtbox: player projectiles ask the owning entity `deflects_hit(hit_box)` through
## `ArmorQuery`; the entity forwards to the plate it overlaps.
##
## Children (built in `_ready()` when the scene does not author them): `HurtBox` (layer
## ENEMY_HURTBOX, mask PLAYER_ROCKETS | PLAYER_HITBOX, EMPTY `accepted_damage_types`), `Health`
## and a `Sprite2D` named `Sprite`.
##
## ONE CLASSIFIER, NOT `received_damage`. `HurtBox.received_damage` carries no damage type, so a
## plate cannot tell a bullet from a rocket through it. The plate instead classifies each HitBox
## in its HurtBox's `area_entered`: a ROCKET, or a projectile that answers `is_high_impact()`
## (the player's Sniper Shot), damages it; anything else is deflected (a flash, no damage). A
## direct `received_damage.emit(...)` on the plate's hurtbox (beam, nova, dash) therefore does
## nothing to it.
##
## IDEMPOTENT PER HITBOX. The projectile asks `deflects_hit()` in *its* `area_entered`, the plate
## classifies in *its own*, and Godot gives no order between the two. So both go through
## `_resolve(hit_box)`: the first caller decides (and applies the damage), later callers read the
## recorded answer. A rocket is consumed by the plate it breaks whichever callback runs first,
## and a plate already broken consumes nothing, so a volley's later rockets go on to the next plate.
class_name ArmorPlate
extends Node2D

## Emitted once when the plate's Health reaches 0, before the node frees itself.
signal broken(plate: ArmorPlate)
## Emitted once per HitBox the plate refused while alive (the deflect flash).
signal deflected(hit_box: HitBox)

@export var max_health: int = 50
## Used only when the scene does not author a `HurtBox` with its own shape.
@export var hurt_size: Vector2 = Vector2(24.0, 16.0)
@export var texture: Texture2D

const _GLOW_COLOR := Color(1.0, 0.85, 0.3)

var hurt_box: HurtBox
var health: Health
var sprite: Sprite2D

var _broken: bool = false
## HitBox instance id -> true when the plate took (and so consumed) that hit.
var _decisions: Dictionary = {}


func _ready() -> void:
	sprite = get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		add_child(sprite)

	health = get_node_or_null("Health") as Health
	if health == null:
		health = Health.new()
		health.name = "Health"
		health.max_health = max_health
		health.current_health = max_health
		add_child(health)

	hurt_box = get_node_or_null("HurtBox") as HurtBox
	if hurt_box == null:
		hurt_box = HurtBox.new()
		hurt_box.name = "HurtBox"
		hurt_box.collision_layer = CollisionLayers.ENEMY_HURTBOX
		hurt_box.collision_mask = CollisionLayers.PLAYER_ROCKETS | CollisionLayers.PLAYER_HITBOX
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = hurt_size
		shape.shape = rect
		hurt_box.add_child(shape)
		add_child(hurt_box)
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	hurt_box.area_exited.connect(_on_hurt_box_area_exited)


func is_alive() -> bool:
	return not _broken and (health == null or health.current_health > 0)


## True for a hit that damages a plate: any rocket, or a projectile that reports itself
## high-impact (duck-typed, the `is_armored()` precedent).
func breaks_on(hit_box: HitBox) -> bool:
	if hit_box.damage_type == HitBox.DamageType.ROCKET:
		return true
	var shooter := hit_box.get_parent()
	return shooter != null and shooter.has_method("is_high_impact") and shooter.is_high_impact()


## The ArmorQuery hook: true when this hit must NOT consume the projectile.
func deflects_hit(hit_box: HitBox) -> bool:
	if hit_box == null:
		return true
	return not _resolve(hit_box)


## 0..1 warm-yellow modulate on the plate's sprite only (never recolour the hull).
func set_glow(amount: float) -> void:
	if sprite != null:
		sprite.modulate = Color.WHITE.lerp(_GLOW_COLOR, clampf(amount, 0.0, 1.0))


func _on_hurt_box_area_entered(area: Area2D) -> void:
	var hit_box := area as HitBox
	if hit_box != null:
		_resolve(hit_box)


func _on_hurt_box_area_exited(area: Area2D) -> void:
	_decisions.erase(area.get_instance_id())


## Decides a HitBox once. Returns true when the plate took the hit (it is consumed).
func _resolve(hit_box: HitBox) -> bool:
	var id := hit_box.get_instance_id()
	if _decisions.has(id):
		return _decisions[id]
	for stale in _decisions.keys():
		if not is_instance_id_valid(stale):
			_decisions.erase(stale)

	if is_alive() and breaks_on(hit_box):
		_decisions[id] = true
		health.decrease(hit_box.damage)
		if health.current_health <= 0:
			_break()
		return true

	_decisions[id] = false
	if is_alive():
		deflected.emit(hit_box)
	return false


func _break() -> void:
	if _broken:
		return
	_broken = true
	hurt_box.set_deferred("monitoring", false)
	hurt_box.set_deferred("monitorable", false)
	sprite.hide()
	# The burst goes into the entity's parent (the plate and its entity may both be freed soon).
	var entity := get_parent().get_parent() if get_parent() != null else null
	var container: Node = entity.get_parent() if entity != null else get_parent()
	var effect := ExplosionEffect.new()
	add_child(effect)
	effect.explode(null, container)
	effect.queue_free()
	broken.emit(self)
	queue_free()
