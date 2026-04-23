## FighterApproachState — moves the ship downward until it reaches the hold line,
## then transitions to FighterStrafeExitState.
##
## Firing is handled by the ship's AttackController (added in LightAssaultShip._ready()).
## This state previously fired bullets directly without the pool — that bug is now fixed.
class_name FighterApproachState
extends State

@export var actor: LightAssaultShip
@export var speed: float = 80.0
@export var hold_y_offset: float = 80.0
@export var strafe_state: State

var _hold_y: float = 0.0

func enter() -> void:
	var viewport_size := actor.get_viewport().get_visible_rect().size
	var cam := actor.get_viewport().get_camera_2d()
	if cam:
		_hold_y = cam.global_position.y - viewport_size.y * 0.5 + hold_y_offset

func process_physics(_delta: float) -> void:
	if actor.global_position.y < _hold_y:
		actor.velocity = Vector2(0, speed)
		actor.move_and_slide()
	else:
		state_transition.emit(strafe_state)
