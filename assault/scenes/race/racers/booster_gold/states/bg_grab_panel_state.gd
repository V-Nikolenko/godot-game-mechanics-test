## BgGrabPanelState — commit to the nearest reachable panel on both axes, then return to whatever
## mode invoked it (Frontrun or Reclaim).
class_name BgGrabPanelState
extends State

var host: RaceShip
var return_to: StringName = &"BgFrontrun"

@export var panel_reach: float = 1000.0
@export var cross_dist: float = 60.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	if panel == null:
		host.brain.transition_to(return_to); return
	host.set_forward_floor()
	host.steer_toward(panel.global_position.x)
	if host.global_position.distance_to(panel.global_position) < cross_dist:
		host.brain.transition_to(return_to)
