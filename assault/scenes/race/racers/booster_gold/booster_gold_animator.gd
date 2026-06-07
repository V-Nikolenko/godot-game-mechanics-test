## BoosterGoldAnimator — drives the AnimatedSprite2D on the Booster Gold racer.
## Reads the lateral gap between desired_x and actual position each physics frame and
## picks the matching animation:
##   |gap| > roll_threshold  → roll_to_the_left / roll_to_the_right  (hard dash / juke)
##   |gap| > tilt_threshold  → tilt_to_the_left / tilt_to_the_right  (normal steering)
##   otherwise               → idle
## All animation names match the five frames the user authored in the AnimatedSprite2D.
class_name BoosterGoldAnimator
extends Node

## |desired_x − current_x| above this plays the roll (hard bank) animations.
@export var roll_threshold: float = 80.0
## |desired_x − current_x| above this plays the tilt (gentle bank) animations.
@export var tilt_threshold: float = 15.0

var _host: RaceShip = null
var _sprite: AnimatedSprite2D = null

func _ready() -> void:
	_host = get_parent() as RaceShip
	## The animated sprite is the "Sprite2D" node (named for @onready compatibility
	## with race_ship.gd, but typed AnimatedSprite2D in the Booster Gold scene).
	_sprite = get_parent().get_node_or_null("Sprite2D") as AnimatedSprite2D
	if _sprite == null:
		push_warning("[BoosterGoldAnimator] Could not find AnimatedSprite2D at $Sprite2D")

func _physics_process(_delta: float) -> void:
	if _sprite == null or _host == null:
		return
	## Guard: SpriteFrames must be assigned (done in the editor, not in code).
	## Silently no-ops until the frames are present.
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(&"idle"):
		return
	var dx: float = _host.desired_x - _host.global_position.x
	var abs_dx: float = absf(dx)
	var next_anim: StringName
	if abs_dx > roll_threshold:
		next_anim = &"roll_to_the_right" if dx > 0.0 else &"roll_to_the_left"
	elif abs_dx > tilt_threshold:
		next_anim = &"tilt_to_the_right" if dx > 0.0 else &"tilt_to_the_left"
	else:
		next_anim = &"idle"
	## Only call play() when the animation actually changes (avoids restarting mid-loop).
	if _sprite.animation != next_anim:
		_sprite.play(next_anim)
