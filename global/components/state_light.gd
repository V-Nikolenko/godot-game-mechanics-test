## global/components/state_light.gd
## StateLight — the single small light an enemy shows to telegraph its attack intent.
##
## Red (ARMED) marks a threat that is live but not yet acting, yellow (CHARGING) marks a
## wind-up, white (COMMIT) marks the one moment worth reacting to — the real dash, the real
## ram — so it must read as rarer than either colour before it (docs/plans/
## cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.9, R2.11: "the real dash's cue is stronger than the
## fake's"). OFF is invisible. `blink_once()` flashes CHARGING for BLINK_SECONDS and restores
## whatever state was active before the call — used for NOTICING, which is a beat, not a
## threat level of its own.
##
## The texture is a radial GradientTexture2D built in code in _ready(), never scene-authored,
## so test_entity_sprite_transparency.gd's sweep of .tscn files never sees it (rev 2, N8). The
## state colour lives entirely in modulate; the hull sprite keeps the faction palette (IDEAS
## §21.1). modulate.a is capped below EnemyBullet's so a projectile stays the most vivid thing
## on screen (finding 9).
class_name StateLight
extends Node2D

enum State { OFF, ARMED, CHARGING, COMMIT }

const MAX_ALPHA := 0.85
const TEXTURE_SIZE := 8
const BLINK_SECONDS := 0.15

var _state: int = State.OFF
var _blink_seconds_left: float = 0.0
var _blink_return_state: int = State.OFF


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.name = "Light"
	sprite.texture = _build_texture()
	add_child(sprite)
	_apply(_state)


func get_state() -> int:
	return _state


func set_state(new_state: int) -> void:
	_blink_seconds_left = 0.0
	_state = new_state
	_apply(new_state)


## Used by NOTICING (§2.5, §2.8.4): flashes CHARGING (yellow) for BLINK_SECONDS, then restores
## whatever state was active before the call.
func blink_once() -> void:
	_blink_return_state = _state
	_blink_seconds_left = BLINK_SECONDS
	_apply(State.CHARGING)


func _process(delta: float) -> void:
	if _blink_seconds_left <= 0.0:
		return
	_blink_seconds_left -= delta
	if _blink_seconds_left <= 0.0:
		_blink_seconds_left = 0.0
		_state = _blink_return_state
		_apply(_state)


func _apply(s: int) -> void:
	match s:
		State.OFF:
			modulate = Color(1.0, 1.0, 1.0, 0.0)
		State.ARMED:
			modulate = Color(Color.RED, MAX_ALPHA)
		State.CHARGING:
			modulate = Color(Color.YELLOW, MAX_ALPHA)
		State.COMMIT:
			modulate = Color(Color.WHITE, MAX_ALPHA)


## TEXTURE_SIZE px, white at the centre fading to alpha 0 at the edge. One texture serves
## every state; the colour comes from modulate.
func _build_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	return texture
