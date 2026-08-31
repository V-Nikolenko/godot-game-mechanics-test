## PacerRunState — the benchmark rabbit: chase the nearest panel to keep top speed maxed, hold a
## fast clean line, never fight. → DODGE on a threat.
class_name PacerRunState
extends State

var host: RaceShip

@export var panel_reach: float = 700.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"PacerDodge"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)
	host.add_avoidance()
