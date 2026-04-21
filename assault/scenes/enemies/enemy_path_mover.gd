## EnemyPathMover — attach to any enemy to override its AI with a screen-relative path.
## Paths are defined in viewport space so they look identical regardless of scroll position.
## When the path ends (or the ship exits the screen) the node frees the parent enemy.
class_name EnemyPathMover
extends Node

enum PathType {
	STRAIGHT,   ## Straight line at path_angle radians from straight-down
	            ##   0       = straight down
	            ##   PI/4    = down-right  (old BACKSLASH)
	            ##  -PI/4    = down-left   (old SLASH)
	            ##   PI/2    = rightward   (old HORIZONTAL)
	            ##  -PI/2    = leftward    (old HORIZONTAL, negative speed)
	U_L,        ## Semicircle bowing left  — enters top, arcs down-left, exits top-left
	U_R,        ## Semicircle bowing right — enters top, arcs down-right, exits top-right
	SINE,       ## Sine-wave descent
}

## How the path should end once complete (only relevant for arc paths that return off-screen).
enum ExitMode {
	FREE_ON_SCREEN_EXIT, ## queue_free when enemy leaves viewport bounds
	FREE_ON_DURATION,    ## queue_free immediately when duration elapses (arc paths)
}

## Where shots are directed while on this path.
enum AimMode {
	PLAYER,  ## Track the player each shot (default)
	FORWARD, ## Fire in the current direction of travel
}

@export_group("Path")
@export var path_type: PathType = PathType.STRAIGHT
@export var path_angle: float = 0.0     ## Radians from straight-down for STRAIGHT paths (0 = down, PI/2 = right)
@export var speed: float = 120.0        ## Travel speed px/s along the path direction
@export var amplitude: float = 150.0   ## Semicircle radius for U paths; lateral swing for SINE
@export var duration: float = 4.0      ## Total seconds for timed arc paths (U_L, U_R)
@export var exit_mode: ExitMode = ExitMode.FREE_ON_SCREEN_EXIT
@export var rotate_actor: bool = true   ## When false the actor keeps its own rotation (use for allies whose sprite already faces the right way)

@export_group("Shooting")
@export var shoot_while_on_path: bool = true   ## Fire while following path
@export var path_fire_interval: float = 0.8    ## Seconds between shots
@export var aim_mode: AimMode = AimMode.PLAYER ## Where bullets are aimed
@export var bullet_damage: int = -1            ## HitBox damage on fired bullets (-1 = bullet default)

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _elapsed: float = 0.0
var _fire_timer: float = 0.0
var _actor: CharacterBody2D
var _state_machine: Node
var _initial_world_pos: Vector2
var _initial_cam_y: float

func _ready() -> void:
	_actor = get_parent() as CharacterBody2D
	if not _actor:
		queue_free()
		return

	_initial_world_pos = _actor.global_position

	var cam := _actor.get_viewport().get_camera_2d()
	_initial_cam_y = cam.global_position.y if cam else 0.0

	# Suspend the enemy's own movement so we own the position each frame.
	_actor.set_physics_process(false)
	_state_machine = _actor.get_node_or_null("AIStateMachine")
	if _state_machine:
		_state_machine.process_mode = Node.PROCESS_MODE_DISABLED

func _physics_process(delta: float) -> void:
	_elapsed += delta

	var cam := _actor.get_viewport().get_camera_2d()
	var cam_scroll_y: float = (cam.global_position.y - _initial_cam_y) if cam else 0.0

	var screen_offset := _get_screen_offset(_elapsed)
	_actor.global_position = _initial_world_pos + screen_offset + Vector2(0.0, cam_scroll_y)

	# Shooting: fire at player on a timer independent of physics_process state.
	if shoot_while_on_path:
		_fire_timer += delta
		if _fire_timer >= path_fire_interval:
			_fire_timer = 0.0
			_fire()

	# Rotate actor to face direction of travel.
	# Sprite forward in actor-local space is (0, 1) = down (sprite has 180° local rotation).
	# To face world direction (vx, vy): actor.rotation = atan2(-vx, vy).
	# rotate_actor = false leaves rotation alone (allies whose sprite already faces up).
	var prev_offset := _get_screen_offset(_elapsed - delta)
	var vel := screen_offset - prev_offset
	if rotate_actor and vel.length_squared() > 0.0001:
		_actor.rotation = atan2(-vel.x, vel.y)

	# Arc paths self-terminate on duration elapsed.
	if exit_mode == ExitMode.FREE_ON_DURATION and _elapsed >= duration:
		_actor.queue_free()
		return

	_check_off_screen(cam)

## Returns the displacement in SCREEN space at time t.
## +X = right, +Y = down (toward player).
func _get_screen_offset(t: float) -> Vector2:
	match path_type:
		PathType.STRAIGHT:
			# path_angle=0 → straight down; PI/2 → right; -PI/2 → left; ±PI/4 → diagonals
			return Vector2(sin(path_angle), cos(path_angle)) * speed * t

		PathType.U_L:
			# Semicircle: enter top, arc DOWN then LEFT, exit top-left.
			# amplitude = radius.  x drifts continuously left; y dips then returns.
			var p: float = clampf(t / duration, 0.0, 1.0)
			return Vector2(
				amplitude * (cos(p * PI) - 1.0),  # 0 → -amplitude → -2*amplitude
				amplitude * sin(p * PI)            # 0 → amplitude → 0
			)

		PathType.U_R:
			# Semicircle: enter top, arc DOWN then RIGHT, exit top-right.
			var p: float = clampf(t / duration, 0.0, 1.0)
			return Vector2(
				amplitude * (1.0 - cos(p * PI)),   # 0 → amplitude → 2*amplitude
				amplitude * sin(p * PI)             # 0 → amplitude → 0
			)

		PathType.SINE:
			return Vector2(amplitude * sin(t * 2.5), speed * t)

	return Vector2.ZERO

func _fire() -> void:
	var bullet: EnemyBullet = _BULLET_SCENE.instantiate() as EnemyBullet
	bullet.global_position = _actor.global_position

	if bullet_damage > 0:
		var hb := bullet.get_node_or_null("HitBox") as HitBox
		if hb:
			hb.damage = bullet_damage

	match aim_mode:
		AimMode.FORWARD:
			# actor.rotation = atan2(-vel.x, vel.y), so forward = Vector2.DOWN.rotated(rotation)
			bullet.set_direction(Vector2.DOWN.rotated(_actor.rotation))
		_: # AimMode.PLAYER
			var players := get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				var target := players[0] as Node2D
				bullet.set_direction((target.global_position - _actor.global_position).normalized())
			else:
				bullet.set_direction(Vector2.DOWN.rotated(_actor.rotation))

	_actor.get_parent().add_child(bullet)

func _check_off_screen(cam: Camera2D) -> void:
	if not cam:
		return
	var vp: Vector2 = _actor.get_viewport().get_visible_rect().size
	var margin: float = 80.0
	var cx: float = cam.global_position.x
	var cy: float = cam.global_position.y
	var ax: float = _actor.global_position.x
	var ay: float = _actor.global_position.y
	if ay > cy + vp.y * 0.5 + margin \
			or ay < cy - vp.y * 0.5 - margin \
			or ax > cx + vp.x * 0.5 + margin \
			or ax < cx - vp.x * 0.5 - margin:
		print("[Despawn] %s (on path) off-screen at (%.0f, %.0f)" % [_actor.name, ax, ay])
		_actor.queue_free()
