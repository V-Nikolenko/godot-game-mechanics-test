## BgJukeState — brief sidestep to shake a chaser off the tail while leading, then FRONTRUN.
class_name BgJukeState
extends State

var host: RaceShip

@export var juke_distance: float = 320.0
@export var juke_time: float = 0.5

var _t: float = 0.0
var _side: int = 1

func enter() -> void:
	_t = juke_time
	_side = -_side if _side != 0 else 1

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	_t -= delta
	host.set_forward_floor()
	host.steer_toward(host.global_position.x + float(_side) * juke_distance)
	if _t <= 0.0:
		host.brain.transition_to(&"BgFrontrun")
