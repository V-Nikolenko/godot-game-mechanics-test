## Mine — dropped by Bogomol as a child of the Track node, so it scrolls with the world.
## After a short arm delay it damages the first ship that enters its radius, then frees itself.
## In group "mines" so every racer's Sensors.hazard_ahead() and LateralMover.avoidance_nudge()
## already steer around it.
class_name Mine
extends Node2D

@export var damage: int = 30
@export var arm_delay: float = 0.4
@export var trigger_radius: float = 46.0
@export var lifetime: float = 8.0

var _armed: float = 0.0
var _life: float = 0.0

func _ready() -> void:
	add_to_group("mines")
	_armed = arm_delay
	_life = lifetime

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if _armed > 0.0:
		_armed -= delta
		return
	# Cheap guard: skip the group scan while still well above the screen.
	if global_position.y < -200.0:
		return
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null:
				continue
			if global_position.distance_to(s.global_position) <= trigger_radius:
				var hb := s.get_node_or_null("HurtBox") as HurtBox
				if hb:
					hb.received_damage.emit(damage)
				queue_free()
				return
