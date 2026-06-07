## IsacProwlState — drift toward the densest part of the field, grabbing panels of convenience.
## → SPRAY when any ship is within spray_radius; → REPOSITION on a direct threat.
class_name IsacProwlState
extends State

var host: RaceShip

@export var spray_radius: float = 320.0
@export var panel_reach: float = 600.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"IsacReposition"); return
	if _nearest_ship_within(spray_radius) != null:
		host.brain.transition_to(&"IsacSpray"); return
	host.set_forward_floor()
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	host.steer_toward(panel.global_position.x if panel else host.global_position.x)

func _nearest_ship_within(r: float) -> Node2D:
	var best: Node2D = null
	var bd := r
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host:
				continue
			var d := host.global_position.distance_to(s.global_position)
			if d < bd:
				bd = d; best = s
	return best
