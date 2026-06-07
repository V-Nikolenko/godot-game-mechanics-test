## IsacSprayState — hose the nearest ship in range continuously (lead it). Occupies space rather
## than chasing. → PROWL when the radius empties; → REPOSITION on a threat.
class_name IsacSprayState
extends State

var host: RaceShip

@export var spray_radius: float = 320.0
@export var fire_interval: float = 0.25
@export var bullet_damage: int = 4
@export var bullet_speed: float = 360.0
## px lateral tolerance — generous for an area suppressor but still requires a forward target
@export var aim_tol: float = 120.0

var _cd: float = 0.0

func process_physics(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"IsacReposition"); return
	var prey := _nearest_ship_within(spray_radius)
	if prey == null:
		host.brain.transition_to(&"IsacProwl"); return
	host.set_forward_coast(0.8)              ## slow turret; doesn't pursue hard
	host.steer_toward(host.global_position.x + signf(prey.global_position.x - host.global_position.x) * 40.0)
	if _cd <= 0.0:
		var prey_part := prey.get_node_or_null("RaceParticipant") as RaceParticipant
		if host.is_lined_up(prey_part, aim_tol):
			host.weapon.fire_at(host.muzzle(), prey, bullet_damage, bullet_speed)
			_cd = fire_interval

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
