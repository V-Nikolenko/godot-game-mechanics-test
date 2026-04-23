## EnemyPathMover — attaches to any ship and drives it along a MovementResource path.
## Responsibility: MOVEMENT ONLY. Shooting, health, and all other behaviour
## belong to the ship itself.
##
## Add as a child of any CharacterBody2D. Assign a MovementResource to `movement`.
## This node takes over physics_process and updates actor.global_position each frame
## using movement.sample(elapsed_time) + camera scroll offset.
class_name EnemyPathMover
extends Node

enum ExitMode {
	FREE_ON_SCREEN_EXIT, ## queue_free when ship leaves viewport (default)
	FREE_ON_DURATION,    ## queue_free when movement.total_duration() elapses
}

@export var movement: MovementResource
@export var exit_mode: ExitMode = ExitMode.FREE_ON_SCREEN_EXIT
@export var look_in_moving_direction: bool = true  ## Rotate actor to face direction of travel.

var _elapsed: float = 0.0
var _actor: CharacterBody2D
var _initial_world_pos: Vector2
var _initial_cam_y: float
var _cam: Camera2D

func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	if not _actor:
		push_error("[EnemyPathMover] Parent must be a CharacterBody2D. Freeing self.")
		queue_free()
		return

	_initial_world_pos = _actor.global_position

	_cam = _actor.get_viewport().get_camera_2d()
	if not _cam:
		push_warning("[EnemyPathMover] No active Camera2D found. Screen-exit culling will be skipped.")
	_initial_cam_y = _cam.global_position.y if _cam else 0.0

	# Suspend the ship's own movement AI — we own position each frame.
	# Timer-based shooting in the ship continues unaffected.
	_actor.set_physics_process(false)
	var state_machine: Node = _actor.get_node_or_null("AIStateMachine")
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(delta: float) -> void:
	if not is_instance_valid(movement):
		return

	_elapsed += delta

	var cam_scroll_y: float = (_cam.global_position.y - _initial_cam_y) if _cam else 0.0

	var pos_offset: Vector2 = movement.sample(_elapsed)
	_actor.global_position = _initial_world_pos + pos_offset + Vector2(0.0, cam_scroll_y)

	if look_in_moving_direction:
		var vel: Vector2 = pos_offset - movement.sample(_elapsed - delta)
		if vel.length_squared() > 0.0001:
			# Sprite's natural facing is +Y (down). atan2(-vel.x, vel.y) maps travel
			# direction to that convention.
			_actor.rotation = atan2(-vel.x, vel.y)

	if exit_mode == ExitMode.FREE_ON_DURATION:
		if _elapsed >= movement.total_duration():
			_actor.queue_free()
			set_physics_process(false)
		return  # duration-mode actors never use the off-screen check

	_check_off_screen(_cam)

func _check_off_screen(cam: Camera2D) -> void:
	if not cam:
		return
	var vp: Vector2 = _actor.get_viewport().get_visible_rect().size
	var margin: float = 80.0
	if _actor.global_position.y > cam.global_position.y + vp.y * 0.5 + margin \
			or _actor.global_position.y < cam.global_position.y - vp.y * 0.5 - margin \
			or _actor.global_position.x > cam.global_position.x + vp.x * 0.5 + margin \
			or _actor.global_position.x < cam.global_position.x - vp.x * 0.5 - margin:
		_actor.queue_free()
		set_physics_process(false)
