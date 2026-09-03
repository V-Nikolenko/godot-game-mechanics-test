## TrackObstacle — a hand-placed hazard authored as a child of the Track node. Because Track
## scrolls, its global_position is always correct without per-object projection. Any ship that
## touches it takes damage (which also costs top speed via DamageReaction / the player's hurt
## handler), and it sits in group "asteroids" so racer Sensors / LateralMover already avoid it.
## Contact is polled (ships are positioned by direct assignment, so Area2D body_entered is
## unreliable). Place at Track local Y = -(distance), X = lane.
class_name TrackObstacle
extends Node2D

@export var damage: int = 18
@export var contact_radius: float = 42.0
@export var hit_cooldown: float = 1.0      ## per-ship re-hit guard
@export var cull_margin: float = 160.0

var _cooldowns: Dictionary = {}            ## ship Node2D -> seconds remaining

func _ready() -> void:
	add_to_group("asteroids")

func _physics_process(delta: float) -> void:
	# Cull once scrolled off the bottom of the screen.
	if global_position.y > get_viewport_rect().size.y + cull_margin:
		queue_free()
		return
	# Cheap guard: do nothing while still well above the screen (not yet reachable).
	if global_position.y < -cull_margin:
		return
	for k in _cooldowns.keys():
		_cooldowns[k] -= delta
	for k in _cooldowns.keys().filter(func(x): return _cooldowns[x] <= 0.0):
		_cooldowns.erase(k)
	for grp in ["player", "racers"]:
		for n in get_tree().get_nodes_in_group(grp):
			var s := n as Node2D
			if s == null or _cooldowns.has(s):
				continue
			if global_position.distance_to(s.global_position) <= contact_radius:
				var hb := s.get_node_or_null("HurtBox") as HurtBox
				if hb:
					hb.received_damage.emit(damage)
				_cooldowns[s] = hit_cooldown
