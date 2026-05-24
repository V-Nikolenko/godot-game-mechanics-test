# assault/scenes/enemies/sniper_enemy/sniper_enemy.gd
class_name SniperEnemy
extends BaseEnemy

## A sniper that is carried in/out by EnemyPathMover (sequence movement) and
## fires a fixed number of shots while stationary:
##
##   sequence step 1 — straight(FLY_IN_SPEED, 0, FLY_IN_TIME) : descend into hover position
##   sequence step 2 — hold(HOLD_TIME)                         : stay put while shooting
##   sequence step 3 — straight(FLY_OUT_SPEED, PI)             : retreat off-screen top
##
## Internal state machine handles only the shoot cycle:
##   AIM  — rotates to track player; SniperAimVisualizer converges over AIM_DURATION
##   LOCK — rotation frozen; lines fully converged for LOCK_DURATION
##   FIRE — spawns one enemy_sniper_bullet; repeats up to MAX_SHOTS times
##   IDLE — all shots fired; EnemyPathMover's exit step takes over movement

enum Phase { AIM, LOCK, FIRE, IDLE }

const AIM_DURATION  : float = 2.0
const LOCK_DURATION : float = 0.5
## How quickly (lerp factor) the enemy rotates to track the player.
const ROTATION_LERP : float = 2.5
## Number of shots before the enemy goes idle and retreats.
const MAX_SHOTS     : int   = 2

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn")

@onready var _muzzle: Marker2D = $Muzzle

var _phase       : Phase               = Phase.AIM
var _timer       : float               = 0.0
var _shots_fired : int                 = 0
var _visualizer  : SniperAimVisualizer = null

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	score_value = 50
	rotation = PI  ## face downward toward the player on entry
	_begin_aim()

# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	match _phase:
		Phase.AIM  : _phase_aim(delta)
		Phase.LOCK : _phase_lock(delta)
		Phase.FIRE : _phase_fire()
		Phase.IDLE : pass  ## EnemyPathMover's fly-out step drives movement

# ─── AIM ─────────────────────────────────────────────────────────────────────

func _begin_aim() -> void:
	_phase = Phase.AIM
	_timer = 0.0

	var half_rad := deg_to_rad(25.0)
	var angles: Array[float] = [
		-half_rad,
		 half_rad,
		randf_range(-half_rad, half_rad),
		randf_range(-half_rad, half_rad),
		randf_range(-half_rad, half_rad),
	]
	_visualizer = SniperAimVisualizer.new()
	_visualizer.initial_angles = angles
	_muzzle.add_child(_visualizer)

func _phase_aim(delta: float) -> void:
	_timer += delta
	_track_player(delta)
	var t := clampf(_timer / AIM_DURATION, 0.0, 1.0)
	if is_instance_valid(_visualizer):
		_visualizer.update_charge(t)
	if _timer >= AIM_DURATION:
		_phase = Phase.LOCK
		_timer = 0.0

# ─── LOCK ─────────────────────────────────────────────────────────────────────

func _phase_lock(delta: float) -> void:
	_timer += delta
	if is_instance_valid(_visualizer):
		_visualizer.update_charge(1.0)
	if _timer >= LOCK_DURATION:
		_phase = Phase.FIRE

# ─── FIRE ─────────────────────────────────────────────────────────────────────

func _phase_fire() -> void:
	var bullet: EnemyBullet = _BULLET_SCENE.instantiate()
	bullet.expired.connect(bullet.queue_free)
	bullet.set_direction(Vector2.UP.rotated(rotation))
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position

	if is_instance_valid(_visualizer):
		_visualizer.queue_free()
	_visualizer = null

	_shots_fired += 1
	if _shots_fired < MAX_SHOTS:
		_begin_aim()   ## shoot again
	else:
		_phase = Phase.IDLE   ## done shooting — EnemyPathMover flies us out

# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _track_player(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player_pos := (players[0] as Node2D).global_position
	var dir := (player_pos - global_position).normalized()
	## atan2(dir.x, -dir.y) gives the rotation for Vector2.UP to face dir.
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
