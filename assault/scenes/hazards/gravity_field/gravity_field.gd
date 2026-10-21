## The Gravity Field: the short-lived slow a Bomber's gravity bomb leaves where it bursts (plan §2.15).
## A `HazardField` with the numbers set in the scene (no pull, no stress, only `movement_penalty`) plus its
## presentation: a faint ring at the full `radius`, and the ripple sprite scaled to it that fades over the
## last `FADE_TIME` seconds. The slow itself is the base script's and is sampled by ships, never applied here.
class_name GravityField
extends HazardField

const RING_COLOR := Color(0.55, 0.9, 0.3, 0.22)
const RING_WIDTH := 2.0
const RING_POINTS := 64
## The sprite fades to nothing over this many seconds before the field frees itself.
const FADE_TIME := 0.5

@onready var _sprite: Sprite2D = get_node_or_null("Sprite") as Sprite2D


func _ready() -> void:
	if _sprite != null and _sprite.texture != null:
		_sprite.scale = Vector2.ONE * (radius * 2.0 / float(_sprite.texture.get_width()))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _sprite != null:
		_sprite.modulate.a = fade_alpha()


## 1.0 until `FADE_TIME` before the end of the field's life, then linear to 0. Always 1.0 for a permanent field.
func fade_alpha() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf((duration - _age) / FADE_TIME, 0.0, 1.0)


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINTS, RING_COLOR, RING_WIDTH, true)
