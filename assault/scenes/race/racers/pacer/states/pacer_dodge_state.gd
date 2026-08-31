## PacerDodgeState — brief sidestep, then back to RUN.
class_name PacerDodgeState
extends State

var host: RaceShip

@export var sidestep: float = 170.0

func process_physics(_delta: float) -> void:
	var threat := host.sensors.incoming_threat()
	if threat == null:
		host.brain.transition_to(&"PacerRun"); return
	var away := signf(host.global_position.x - threat.global_position.x)
	if away == 0.0:
		away = 1.0
	host.steer_toward(host.global_position.x + away * sidestep)
	host.set_forward_floor()
