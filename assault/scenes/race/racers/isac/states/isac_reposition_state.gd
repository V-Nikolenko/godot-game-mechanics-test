## IsacRepositionState — short slide off a threat, never fully fleeing. → PROWL when clear.
class_name IsacRepositionState
extends State

var host: RaceShip

@export var sidestep: float = 150.0
@export var slide_time: float = 0.4

var _t: float = 0.0

func enter() -> void:
	_t = slide_time

func process_physics(delta: float) -> void:
	_t -= delta
	var threat := host.sensors.incoming_threat()
	var away := 1.0
	if threat:
		away = signf(host.global_position.x - threat.global_position.x)
		if away == 0.0:
			away = 1.0
	host.set_forward_floor()
	host.steer_toward(host.global_position.x + away * sidestep)
	if _t <= 0.0:
		host.brain.transition_to(&"IsacProwl")
