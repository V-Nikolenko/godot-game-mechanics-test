## Bomb — dropped by the Bomber enemy.
##
## States:
##   FALLING   — falls downward; 5 s auto-fuse counts up.
##   TRIGGERED — player HurtBox entered proximity; 1 s colour-flash countdown.
##   EXPLODED  — HitBox activates briefly, then node is freed.
##
## The bomb continues to fall through all states until detonation or off-screen exit.
class_name Bomb
extends Area2D

enum State { FALLING, TRIGGERED, EXPLODED }

## Fall speed in world pixels per second.
@export var fall_speed: float = 120.0
## Seconds before the bomb auto-detonates regardless of player proximity.
@export var fuse_time: float = 5.0
## Seconds between player entering proximity and detonation.
@export var trigger_time: float = 1.0

const _OFF_SCREEN_MARGIN : float = 80.0

## Idle dark colour.
const _COLOR_IDLE    := Color(0.15, 0.15, 0.15, 1.0)
## Final detonation flash.
const _COLOR_EXPLODE := Color(1.0, 0.55, 0.0, 1.0)

var _state           := State.FALLING
var _fuse_elapsed    : float = 0.0
var _trigger_elapsed : float = 0.0

@onready var _visual    : ColorRect = $Visual
@onready var _hitbox    : HitBox    = $HitBox
@onready var _proximity : Area2D    = $ProximityDetector


func _ready() -> void:
	_hitbox.monitoring   = false
	_visual.color        = _COLOR_IDLE
	_proximity.area_entered.connect(_on_proximity_area_entered)


func _physics_process(delta: float) -> void:
	if _state == State.EXPLODED:
		return

	position.y += fall_speed * delta
	_check_off_screen()

	match _state:
		State.FALLING:
			_fuse_elapsed += delta
			if _fuse_elapsed >= fuse_time:
				_explode()

		State.TRIGGERED:
			_trigger_elapsed += delta
			var t: float = clampf(_trigger_elapsed / trigger_time, 0.0, 1.0)
			## Interpolate from dark grey toward bright orange-red as the countdown runs.
			_visual.color = Color(
				lerpf(0.15, 1.0,  t),
				lerpf(0.15, 0.15, t),
				lerpf(0.15, 0.0,  t),
				1.0
			)
			if _trigger_elapsed >= trigger_time:
				_explode()


## Fires when an Area2D enters the ProximityDetector zone.
## Only the player HurtBox (collision_layer 128) transitions the bomb to TRIGGERED.
func _on_proximity_area_entered(area: Area2D) -> void:
	if _state != State.FALLING:
		return
	if area.collision_layer & 128:
		_state = State.TRIGGERED


func _explode() -> void:
	if _state == State.EXPLODED:
		return
	_state = State.EXPLODED
	_proximity.monitoring = false
	_hitbox.monitoring    = true
	_visual.color         = _COLOR_EXPLODE
	await get_tree().create_timer(0.15).timeout
	if is_instance_valid(self):
		queue_free()


func _check_off_screen() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var vp := get_viewport().get_visible_rect().size
	if position.y > cam.global_position.y + vp.y * 0.5 + _OFF_SCREEN_MARGIN:
		queue_free()
