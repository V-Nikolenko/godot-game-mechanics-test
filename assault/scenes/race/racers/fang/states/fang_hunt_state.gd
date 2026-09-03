## FangHuntState — sit behind the ship in front (player or rival), match lane, suppress with
## forward fire. → LUNGE when lined up & close; → DODGE on a threat; chase panels only if there
## is nothing to hunt (Fang prioritises the kill over speed).
class_name FangHuntState
extends State

var host: RaceShip

@export var hunt_range: float = 2200.0   ## track_y units within which Fang engages
@export var lane_tol: float = 220.0
@export var follow_gap: float = 240.0    ## track_y to hold behind the prey
@export var lunge_range: float = 520.0   ## track_y gap at which Fang commits a lunge
@export var aim_tol: float = 70.0
@export var fire_cd: float = 1.4
@export var bullet_damage: int = 8
@export var bullet_speed: float = 300.0

var _cd: float = 0.0

func process_physics(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"FangDodge"); return

	var prey := host.sensors.ship_ahead(hunt_range, lane_tol)
	if prey == null:
		# Nothing to hunt → keep speed up by grabbing a panel, else hold centre.
		var panel := host.sensors.nearest_panel_ahead(600.0)
		host.steer_toward(panel.global_position.x if panel else 640.0)
		host.set_forward_floor()
		return

	host.set_forward_match(prey, follow_gap)
	host.steer_toward(prey.global_x())
	if _cd <= 0.0 and host.is_lined_up(prey, aim_tol):
		host.weapon.fire_at(host.muzzle(), prey.ship(), bullet_damage, bullet_speed)
		_cd = fire_cd

	var lunge_state := host.brain.get_state(&"FangLunge")
	if lunge_state != null and lunge_state.get("lunge_ready") \
			and host.sensors.gap_to(prey) < lunge_range \
			and host.is_lined_up(prey, aim_tol):
		host.brain.transition_to(&"FangLunge")
