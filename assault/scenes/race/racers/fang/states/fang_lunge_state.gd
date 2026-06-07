## FangLungeState — a brief invincible over-speed straight up the prey's lane, dealing contact
## damage to any ship passed once. Then back to HUNT.
## lunge_ready starts false; the passive _physics_process counts down initial_delay before the
## first use is allowed, then lunge_cooldown between each subsequent use.
## FangHuntState checks lunge_ready before entering this state.
class_name FangLungeState
extends State

var host: RaceShip

@export var lunge_time: float = 0.7
@export var lunge_cruise: float = 1.0
@export var lunge_lunge: float = 500.0    ## track_y units fed to add_lunge() (time-based burst)
@export var contact_damage: int = 22
@export var contact_radius: float = 70.0
@export var initial_delay: float = 20.0   ## seconds before the first lunge is allowed
@export var lunge_cooldown: float = 10.0  ## seconds between uses after the first

var lunge_ready: bool = false
var _cd: float = 0.0
var _t: float = 0.0
var _hit: Array = []

func _ready() -> void:
	_cd = initial_delay

## Cooldown ticks while Fang is in any other state. Matches BgDashState's passive pattern.
func _physics_process(delta: float) -> void:
	if host == null or host.brain.current == self:
		return
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
		if _cd <= 0.0:
			lunge_ready = true

func enter() -> void:
	lunge_ready = false
	_t = lunge_time
	_hit.clear()
	host.hurt_box.monitoring = false              ## i-frames during the lunge
	host.participant.set_cruise_factor(lunge_cruise)
	## add_lunge() feeds the shared _lunge_remaining bucket (consumed at 2600 units/sec),
	## giving a fast surge over ~0.2 s instead of an instant track_y jump (teleport).
	host.participant.add_lunge(lunge_lunge)

func process_physics(delta: float) -> void:
	_t -= delta
	_damage_scan()
	if _t <= 0.0:
		host.hurt_box.monitoring = true
		_cd = lunge_cooldown
		host.brain.transition_to(&"FangHunt")

func exit() -> void:
	host.hurt_box.monitoring = true

func _damage_scan() -> void:
	for grp in ["player", "racers"]:
		for n in host.get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or s == host or s in _hit:
				continue
			if host.global_position.distance_to(s.global_position) > contact_radius:
				continue
			var hb := s.get_node_or_null("HurtBox") as HurtBox
			if hb:
				hb.received_damage.emit(contact_damage)
			_hit.append(s)
