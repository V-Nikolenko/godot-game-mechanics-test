## A drifting piece of debris: a collision hazard, not cover (plan §2.8). An `Area2D`, not a body, so ships fly into
## it, sight lines pass it and shots pass it; its `ContactHitBox` (1024) hurts the ship whose hurtbox it touches,
## whatever its own speed (it has no body to stop the ship first). It is a hazard (`kind = &"debris"`) the AI keeps
## clear of.
##
## With a `source` (the Ram's broken plate, t15) the contact box stays disarmed until the fragment's centre is farther
## than `source_clear_radius` from that still-valid source, so it never hits the ship it broke off. It moves itself on
## accumulated `delta`; `ProjectileLifetime` (`lifetime`, plus the Assault world rect) ends it. One owner: `expired ->
## queue_free`.
class_name DebrisFragment
extends Area2D

## `ProjectileLifetime`'s host signal.
signal expired

@export var speed: float = 30.0
## px/s². The fragment slows to a stop and stays.
@export var deceleration: float = 0.0
## rad/s. Turns the sprite only; the travel direction is `direction`.
@export var spin: float = 0.0
## Seconds (0 = permanent).
@export var lifetime: float = 30.0
@export var direction: Vector2 = Vector2.DOWN
@export var contact_damage: int = 8
@export_range(0.0, 1.0) var avoid_weight: float = 0.4
## `configure(rng)` picks one of these and a speed in [speed_min, speed_max].
@export var textures: Array[Texture2D] = []
@export var speed_min: float = 20.0
@export var speed_max: float = 40.0

## The ship this broke off, or null. The contact box stays disarmed while it is valid and within the clear radius.
var source: Node = null
var source_clear_radius: float = 0.0

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _contact: HitBox = $ContactHitBox
@onready var _contact_shape: CollisionShape2D = $ContactHitBox/CollisionShape2D
@onready var _lifetime: ProjectileLifetime = $ProjectileLifetime

var _info := HazardInfo.new()
var _armed: bool = false
var _pending_transform: bool = false
var _at: Vector2 = Vector2.ZERO
var _rot: float = 0.0


## Same entry as `Wreck.spawn_into()` / `HazardField.spawn_into()`: deferred, frees itself if the container is gone.
func spawn_into(container: Node, at: Vector2, rot: float = 0.0) -> void:
	_at = at
	_rot = rot
	_pending_transform = true
	_attach.call_deferred(container)


## Untyped on purpose: a typed `Node` parameter makes the deferred call itself fail on a freed container.
func _attach(container) -> void:
	if is_instance_valid(container) and (container as Node).is_inside_tree():
		(container as Node).add_child(self)
	else:
		queue_free()


func _enter_tree() -> void:
	if _pending_transform:
		global_position = _at
		rotation = _rot
		_pending_transform = false
	Hazards.register(self)


func _exit_tree() -> void:
	Hazards.unregister(self)


func _ready() -> void:
	direction = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO
	_contact.damage = contact_damage
	_contact.damage_type = HitBox.DamageType.CONTACT
	# The one source of the life: 0 = no time rule (the Assault world rect still applies).
	_lifetime.max_time = lifetime
	expired.connect(queue_free)
	_refresh_info()


## Picks the sprite, the speed and the travel direction from [param rng] (the dying enemy's seeded `brain.rng`), so
## one seed gives one fragment. Call before adding it to the tree.
func configure(rng: RandomNumberGenerator) -> void:
	if rng == null:
		return
	if not textures.is_empty():
		var tex: Texture2D = textures[rng.randi_range(0, textures.size() - 1)]
		var sprite := get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			sprite.texture = tex
	speed = rng.randf_range(speed_min, speed_max)
	direction = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))


func _physics_process(delta: float) -> void:
	speed = maxf(0.0, speed - deceleration * delta)
	global_position += direction * speed * delta
	rotation += spin * delta
	if not _armed and _source_clear():
		_armed = true
		# The shape too, not just `monitorable` (see `Wreck._arm_contact()`): a pair built while unarmed never reports.
		_contact.set_deferred(&"monitorable", true)
		_contact_shape.set_deferred(&"disabled", false)
	_refresh_info()


func is_armed() -> bool:
	return _armed


func hazard_info() -> HazardInfo:
	_info.position = global_position if is_inside_tree() else position
	return _info


func contact_radius() -> float:
	# Also answers before `_ready()` (the Ram sizes its clear radius on a fresh instance), so no `@onready` here.
	var shape_node := get_node_or_null("ContactHitBox/CollisionShape2D") as CollisionShape2D
	var circle := shape_node.shape as CircleShape2D if shape_node != null else null
	return circle.radius * absf(shape_node.scale.x * scale.x) if circle != null else 0.0


func _source_clear() -> bool:
	if not is_instance_valid(source):
		return true
	var src := source as Node2D
	if src == null or not src.is_inside_tree():
		return true
	return global_position.distance_to(src.global_position) > source_clear_radius


func _refresh_info() -> void:
	_info.position = global_position if is_inside_tree() else position
	_info.kind = &"debris"
	_info.source = self
	_info.radius = contact_radius()
	_info.avoid_weight = avoid_weight
	_info.velocity = direction * speed
	_info.line_of_sight_blocker = false
