## Shared behaviour for BigAsteroid and SmallAsteroid:
## random sprite region selection, contact damage, death handling.
class_name AsteroidBase
extends CharacterBody2D

signal died(world_position: Vector2)

@export var health_amount: int = 100
@export var contact_damage: int = 40
## When > 0, enables speed-scaled damage: returns 9999 (one-shot) at or above threshold.
@export var one_shot_speed_threshold: float = 0.0
@export var tileset_texture: Texture2D
@export var tile_size: Vector2i = Vector2i(64, 64)
@export var tile_columns: int = 3
@export var tile_rows: int = 2

@onready var health: Health = $Health
@onready var hurt_box: HurtBox = $HurtBox
@onready var sprite: Sprite2D = $Sprite2D
@onready var contact_hit_box: HitBox = $ContactHitBox

var _explosion: ExplosionEffect

func _ready() -> void:
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	_pick_random_sprite()
	health.set_health(health_amount)
	hurt_box.received_damage.connect(_on_received_damage)
	health.amount_changed.connect(_on_health_changed)
	contact_hit_box.damage = contact_damage
	contact_hit_box.damage_type = HitBox.DamageType.CONTACT

func _pick_random_sprite() -> void:
	if tileset_texture == null:
		return
	var total := tile_columns * tile_rows
	var idx := randi() % total
	var col := idx % tile_columns
	var row := idx / tile_columns
	var atlas := AtlasTexture.new()
	atlas.atlas = tileset_texture
	atlas.region = Rect2(col * tile_size.x, row * tile_size.y, tile_size.x, tile_size.y)
	sprite.texture = atlas

func _on_received_damage(amount: int) -> void:
	health.decrease(amount)

func _on_health_changed(current: int) -> void:
	if current <= 0:
		_explosion.explode()
		died.emit(global_position)
		_on_destroyed()
		queue_free()

## Override in subclasses to react to death (e.g. spawn fragments).
## MUST be synchronous — do NOT use await. Called immediately before queue_free().
func _on_destroyed() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if one_shot_speed_threshold > 0.0:
		contact_hit_box.damage = current_contact_damage()

func current_contact_damage() -> int:
	if one_shot_speed_threshold > 0.0 and velocity.length() >= one_shot_speed_threshold:
		return 9999
	return contact_damage
