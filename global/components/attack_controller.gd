## AttackController — Node that drives an AttackPatternResource on a timer.
##
## Add as a child of any ship. Set `pattern` and `bullet_pool`.
## This node owns the timer state so multiple ships sharing the same pattern
## .tres don't share state (each gets its own AttackController instance).
class_name AttackController
extends Node

@export var pattern: AttackPatternResource
@export var bullet_pool: BulletPool
## Hold-fire switch. false keeps the fire-interval timer running and wrapping, but withholds
## the shot itself, so re-enabling mid-interval does not fire early or double up.
@export var enabled: bool = true
## true hands the timer to the owner: _process becomes a no-op and the owner must call tick(delta)
## itself (e.g. from a brain's own physics tick). Existing users leave this false and are unaffected.
@export var driven_by_brain: bool = false

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
	if driven_by_brain:
		return
	tick(delta)

## Advances the fire-interval timer by delta and fires when it wraps. Called automatically from
## _process unless driven_by_brain is true, in which case the owner (a brain) calls this directly.
func tick(delta: float) -> void:
	if not is_instance_valid(pattern) or not is_instance_valid(bullet_pool):
		return
	_timer += delta
	if _timer >= pattern.fire_interval:
		_timer -= pattern.fire_interval  # subtract (not reset to 0) to preserve overshoot accuracy
		if enabled:
			pattern.fire(_ship, bullet_pool)

## Fires immediately regardless of the timer's phase, for a telegraphed shot the owner triggers
## directly. Ignores enabled and does not touch the timer.
func fire_now() -> void:
	if is_instance_valid(pattern) and is_instance_valid(bullet_pool):
		pattern.fire(_ship, bullet_pool)
