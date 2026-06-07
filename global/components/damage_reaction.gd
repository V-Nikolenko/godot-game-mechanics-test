## DamageReaction — uniform "ship takes a hit" handling, composed onto any destructible ship.
## Wire it with setup(); it listens to a HurtBox and routes damage through an optional Shield
## to Health, flashes a sprite, runs an optional pre-damage hook, and explodes on death.
class_name DamageReaction
extends Node

signal died

@export var flash_color: Color = Color(1.0, 0.4, 0.4, 1.0)
@export var flash_time: float = 0.18
## Optional extra reaction on every hit (e.g. top-speed loss). Set by the host.
var on_hit: Callable = Callable()

var _health: Health = null
var _shield: Shield = null
var _sprite: CanvasItem = null
var _explosion: ExplosionEffect = null
var _flash_tween: Tween = null

func setup(health: Health, shield: Shield, hurt_box: HurtBox, sprite: CanvasItem) -> void:
	_health = health
	_shield = shield
	_sprite = sprite
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	if hurt_box and not hurt_box.received_damage.is_connected(_on_received_damage):
		hurt_box.received_damage.connect(_on_received_damage)
	if _health and not _health.amount_changed.is_connected(_on_health_changed):
		_health.amount_changed.connect(_on_health_changed)

func _on_received_damage(damage: int) -> void:
	if on_hit.is_valid():
		on_hit.call(damage)
	_flash()
	if _shield and _shield.consume_one():
		return
	if _health:
		_health.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current <= 0:
		died.emit()
		if _explosion:
			_explosion.explode()
		get_parent().queue_free()

func _flash() -> void:
	if _sprite == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_sprite.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_sprite, "modulate", Color.WHITE, flash_time)
