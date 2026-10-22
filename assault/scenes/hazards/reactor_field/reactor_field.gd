## The Reactor Field: the brief reactor fire an explosive wreck leaves where it blew (plan §2.10). A `HazardField` with
## the numbers set in the scene (no pull, no slow; only hull stress) plus its presentation: a faint ring at the full
## `radius`, and the burning disc scaled to it that fades over the last `FADE_TIME` seconds. The stress itself is the
## base script's (`Hazards.pulse_damage` by centre distance); nothing here touches a ship.
class_name ReactorField
extends HazardField

const RING_COLOR := Color(1.0, 0.45, 0.15, 0.25)
const RING_WIDTH := 2.0
const RING_POINTS := 48
## The sprite fades to nothing over this many seconds before the field frees itself.
const FADE_TIME := 0.5

@onready var _sprite: AnimatedSprite2D = get_node_or_null("Sprite") as AnimatedSprite2D


func _ready() -> void:
	if _sprite != null:
		var frame := _sprite.sprite_frames.get_frame_texture(_sprite.animation, 0) if _sprite.sprite_frames != null else null
		if frame != null:
			_sprite.scale = Vector2.ONE * (radius * 2.0 / float(frame.get_width()))
		_sprite.play()


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
