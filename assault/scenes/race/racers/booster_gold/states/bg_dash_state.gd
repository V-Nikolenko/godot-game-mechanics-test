## BgDashState — invincible boosted lunge up the target's lane (or straight ahead), contact
## damage once per ship passed, then a cooldown before it can dash again. Used from RECLAIM.
## dash_ready starts false; the passive _physics_process counts down initial_delay before the
## first use is allowed, then cooldown between each subsequent use.
## BgReclaimState checks dash_ready before entering this state.
class_name BgDashState
extends State

var host: RaceShip
var target: RaceParticipant = null
var dash_ready: bool = false

@export var dash_time: float = 0.85
@export var dash_lunge: float = 950.0     ## track_y units fed to add_lunge() (time-based burst)
@export var dash_damage: int = 45
@export var dash_radius: float = 72.0
@export var initial_delay: float = 25.0   ## seconds before the first dash is allowed
@export var cooldown: float = 12.0        ## seconds between uses after the first

var _t: float = 0.0
var _cd: float = 0.0
var _hit: Array = []

func _ready() -> void:
	_cd = initial_delay

## Cooldown ticks while BG is in any other state (never overlaps with the active dash).
func _physics_process(delta: float) -> void:
	if host == null or host.brain.current == self:
		return
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
		if _cd <= 0.0:
			dash_ready = true

func enter() -> void:
	dash_ready = false
	_t = dash_time
	_hit.clear()
	host.hurt_box.monitoring = false              ## i-frames during the dash
	host.participant.set_cruise_factor(1.0)
	## add_lunge() feeds the shared _lunge_remaining bucket (consumed at 2600 units/sec),
	## giving a fast surge over ~0.37 s instead of an instant track_y jump (teleport).
	host.participant.add_lunge(dash_lunge)

func process_physics(delta: float) -> void:
	_t -= delta
	if target and is_instance_valid(target):
		host.steer_toward(target.global_x())
	_damage_scan()
	if _t <= 0.0:
		host.hurt_box.monitoring = true
		_cd = cooldown
		target = null
		host.brain.transition_to(&"BgReclaim")

func exit() -> void:
	host.hurt_box.monitoring = true

func _damage_scan() -> void:
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host or s in _hit:
				continue
			if host.global_position.distance_to(s.global_position) > dash_radius:
				continue
			var hb := s.get_node_or_null("HurtBox") as HurtBox
			if hb:
				hb.received_damage.emit(dash_damage)
			_hit.append(s)
