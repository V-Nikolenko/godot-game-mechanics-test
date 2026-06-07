## BogomolCruiseState — no panel reachable: hold a defensive fast line and occasionally lay a
## mine on its own lane. → SEEK when a panel appears; → EVADE on threat.
class_name BogomolCruiseState
extends State

var host: RaceShip

@export var lay_interval: float = 3.0
const _MINE: PackedScene = preload("res://assault/scenes/race/track/mine.tscn")
var _t: float = 0.0

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BogomolEvade"); return
	if host.sensors.nearest_panel_ahead(900.0) != null:
		host.brain.transition_to(&"BogomolSeek"); return
	host.set_forward_floor()
	host.add_avoidance()
	_t -= delta
	if _t <= 0.0:
		_t = lay_interval
		var mine := _MINE.instantiate() as Mine
		var drop_pos := host.global_position + Vector2(0.0, 40.0)   ## just behind on the lane
		var track := host.get_tree().get_first_node_in_group("race_track") as Node2D
		if track:
			mine.position = track.to_local(drop_pos)   ## scrolls with the world
			track.add_child(mine)
		else:
			mine.global_position = drop_pos
			host.get_parent().add_child(mine)
