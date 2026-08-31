## ReacherAimState — brief telegraphed hold, then one heavy long-range shot leading the target.
## Returns to POSITION (which recharges).
class_name ReacherAimState
extends State

var host: RaceShip
var target: RaceParticipant = null

@export var telegraph: float = 0.35
@export var snipe_damage: int = 30
@export var snipe_speed: float = 700.0

var _t: float = 0.0

func enter() -> void:
	_t = telegraph

func process_physics(delta: float) -> void:
	_t -= delta
	host.set_forward_coast(0.7)
	if target and is_instance_valid(target.ship()):
		host.steer_toward(target.global_x())
	if _t <= 0.0:
		if target and is_instance_valid(target.ship()):
			host.weapon.fire_at(host.muzzle(), target.ship(), snipe_damage, snipe_speed)
		target = null
		host.brain.transition_to(&"ReacherPosition")
