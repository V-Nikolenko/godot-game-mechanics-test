## ReacherPositionState — keep a stand-off gap and a clear lane to a target; sidestep to open a
## shot. → AIM when lined up & charged; → CATCH_UP if dropping too far back; → EVADE on threat.
class_name ReacherPositionState
extends State

var host: RaceShip

@export var standoff_gap: float = 1200.0   ## track_y it likes to sit behind the target
@export var lane_tol: float = 90.0
@export var fall_behind_gap: float = 3000.0 ## track_y behind leader → CATCH_UP
@export var charge_time: float = 1.2

var _charge: float = 0.0

func enter() -> void:
	_charge = charge_time

func process_physics(delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"ReacherEvade"); return
	var dir := host._director()
	if dir and dir.gap_to_leader(host.participant) > fall_behind_gap:
		host.brain.transition_to(&"ReacherCatchup"); return

	var target := host.sensors.ship_ahead(8000.0, 9999.0)   ## any ship ahead, any lane
	host.set_forward_match(target, standoff_gap)
	if target:
		host.steer_toward(target.global_x())
	_charge = maxf(0.0, _charge - delta)
	if target and _charge <= 0.0 and absf(host.global_position.x - target.global_x()) < lane_tol:
		host.brain.get_state(&"ReacherAim").set("target", target)
		host.brain.transition_to(&"ReacherAim")
