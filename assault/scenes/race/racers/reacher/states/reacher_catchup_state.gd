## ReacherCatchupState — temporarily prioritise panels to recover lost top speed, then POSITION.
class_name ReacherCatchupState
extends State

var host: RaceShip

@export var recovered_gap: float = 1600.0   ## track_y behind leader to resume positioning

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"ReacherEvade"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(900.0)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)
	var dir := host._director()
	if dir and dir.gap_to_leader(host.participant) < recovered_gap:
		host.brain.transition_to(&"ReacherPosition")
