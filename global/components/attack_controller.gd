## AttackController — Node that drives an AttackPatternResource on a timer.
##
## Add as a child of any ship. Set `pattern` and `bullet_pool`.
## This node owns the timer state so multiple ships sharing the same pattern
## .tres don't share state (each gets its own AttackController instance).
class_name AttackController
extends Node

@export var pattern: AttackPatternResource
@export var bullet_pool: BulletPool

var _timer: float = 0.0
var _ship: Node2D

func _ready() -> void:
	_ship = get_parent() as Node2D
	if not _ship:
		push_error("[AttackController] Parent must be a Node2D. Disabling.")
		set_process(false)
		return
	# Negative initial timer honours start_delay before the first shot.
	_timer = -(pattern.start_delay if is_instance_valid(pattern) else 0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(pattern) or not is_instance_valid(bullet_pool):
		return
	_timer += delta
	if _timer >= pattern.fire_interval:
		_timer -= pattern.fire_interval  # subtract (not reset to 0) to preserve overshoot accuracy
		pattern.fire(_ship, bullet_pool)
