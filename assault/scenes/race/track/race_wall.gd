## RaceWall — a breakable, lethal, partial-width track wall placed as a child of Track
## (authored at negative Y; scrolls with the world). Contact one-shots any ship (handled
## centrally by HazardSystem). Player rockets (missiles, HitBox layer 32, damage_type 1)
## damage its HurtBox and break it — exactly like an asteroid. Always narrower than the
## 128–1152 lane, so a lateral gap always exists (dodgeable); rocketing it opens a cleaner
## line, except when authored right behind a dash panel (a "trap" — Phase 3).
class_name RaceWall
extends Node2D

## Lethal/visual footprint in px (matches wall_1.png: 256×65 — partial, keep < ~1024 lane).
@export var wall_size: Vector2 = Vector2(256, 65)
## Rocket hits needed to break it (warhead deals a large hit; ~1–2 rockets).
@export var health_amount: int = 60

@onready var _health: Health = $Health
@onready var _hurt_box: HurtBox = $HurtBox
@onready var _sprite: Sprite2D = $Sprite2D

var _explosion: ExplosionEffect
var _dead: bool = false

func _ready() -> void:
	add_to_group("race_hazards")
	_explosion = ExplosionEffect.new()
	add_child(_explosion)
	_health.set_health(health_amount)
	_hurt_box.received_damage.connect(_on_received_damage)
	_health.amount_changed.connect(_on_health_changed)

## Hazard contract — world-space lethal rect, centred on this node.
func danger_rect() -> Rect2:
	return Rect2(global_position - wall_size * 0.5, wall_size)

## Hazard contract — a wall is always lethal on contact until it breaks.
func is_lethal_now() -> bool:
	return not _dead

func _on_received_damage(amount: int) -> void:
	_health.decrease(amount)

func _on_health_changed(current: int) -> void:
	if current <= 0 and not _dead:
		_dead = true
		remove_from_group("race_hazards")
		_explosion.explode()
		_sprite.visible = false
		_hurt_box.set_deferred("monitoring", false)
		## Free after the explosion particles finish (matches asteroid death feel).
		await get_tree().create_timer(0.7).timeout
		queue_free()
