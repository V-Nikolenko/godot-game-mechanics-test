## BgReclaimState — active whenever Booster Gold is not 1st. Floor it, still grab panels greedily
## (GRAB_PANEL preempts), and USE THE DASH: ram the ship ahead if in range & off cooldown, or
## dash as a pure surge if far behind the leader. → FRONTRUN when back in 1st.
class_name BgReclaimState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var dash_range_min: float = 120.0
@export var dash_range_max: float = 1400.0   ## track_y gap to the ship ahead
@export var dash_aim_tol: float = 90.0
@export var lane_tol: float = 240.0
@export var desperation_gap: float = 2200.0  ## track_y behind leader → dash even with no clean target
@export var fire_cd: float = 1.0
@export var bullet_damage: int = 8
@export var bullet_speed: float = 320.0

var _fire: float = 0.0

func process_physics(delta: float) -> void:
	_fire = maxf(0.0, _fire - delta)
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var dir := host._director()
	if dir and dir.is_in_front(host.participant):
		host.brain.transition_to(&"BgFrontrun"); return

	host.set_forward_floor()

	# Panels still preempt (greedy): they restore the top speed needed to reclaim.
	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	var target := host.sensors.ship_ahead(dash_range_max, lane_tol)

	if host.brain.get_state(&"BgDash").get("dash_ready") and _should_dash(dir, target):
		host.brain.get_state(&"BgDash").set("target", target)
		host.brain.transition_to(&"BgDash"); return

	if panel != null:
		host.brain.get_state(&"BgGrabPanel").set("return_to", &"BgReclaim")
		host.brain.transition_to(&"BgGrabPanel"); return

	# Chase + suppress the ship ahead while the dash recharges.
	if target != null:
		host.steer_toward(target.global_x())
		if _fire <= 0.0 and host.is_lined_up(target, dash_aim_tol):
			host.weapon.fire_at(host.muzzle(), target.ship(), bullet_damage, bullet_speed)
			_fire = fire_cd
	else:
		host.steer_toward(host.global_position.x)

func _should_dash(dir: RaceDirector, target: RaceParticipant) -> bool:
	if target != null:
		var gap := host.sensors.gap_to(target)
		if gap >= dash_range_min and gap <= dash_range_max \
				and absf(host.global_position.x - target.global_x()) <= dash_aim_tol:
			return true
	# No clean target but far behind the leader → surge dash anyway.
	return dir != null and dir.gap_to_leader(host.participant) > desperation_gap
