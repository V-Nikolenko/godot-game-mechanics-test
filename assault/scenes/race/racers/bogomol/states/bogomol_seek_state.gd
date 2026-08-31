## BogomolSeekState — race for the nearest reachable panel on both axes (it benefits AND will
## deny it). → MINE_DROP on crossing; → CRUISE if no panel; → EVADE on threat.
class_name BogomolSeekState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var cross_dist: float = 60.0

var _target: Node2D = null

func enter() -> void:
	_target = null

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BogomolEvade"); return
	_target = host.sensors.nearest_panel_ahead(panel_reach)
	if _target == null:
		host.brain.transition_to(&"BogomolCruise"); return
	host.set_forward_floor()
	host.steer_toward(_target.global_position.x)
	if host.global_position.distance_to(_target.global_position) < cross_dist:
		host.brain.get_state(&"BogomolMine").set("drop_at", _target.global_position)
		host.brain.transition_to(&"BogomolMine")
