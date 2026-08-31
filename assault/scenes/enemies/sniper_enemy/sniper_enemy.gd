# assault/scenes/enemies/sniper_enemy/sniper_enemy.gd
class_name SniperEnemy
extends BaseEnemy

## Sniper that is carried in/out by EnemyPathMover (sequence movement) and
## fires shot_count times while hovering.  State machine:
##
##   APPROACH — descends into position; sprite faces down, no red line.
##              After FLY_IN_TIME seconds, transitions to AIM.
##   AIM      — rotates to track player; single red line converges over AIM_DURATION.
##   LOCK     — rotation frozen; line turns bright, held for LOCK_DURATION.
##   FIRE     — spawns one enemy_sniper_bullet, loops back to AIM until shot_count met.
##   IDLE     — all shots fired; EnemyPathMover's exit step flies the enemy out.
##
## NOTE: EnemyPathMover calls set_physics_process(false) on the actor to own
## position.  We therefore run our logic in _process(), which is never disabled
## and which executes AFTER _physics_process — so our rotation always wins.

enum Phase { APPROACH, AIM, LOCK, FIRE, IDLE }

const AIM_DURATION  : float = 2.0
const LOCK_DURATION : float = 0.5
## How quickly the enemy lerp-rotates to track the player.
const ROTATION_LERP : float = 4.0
## Must match the straight-movement step duration used in the wave sequence.
const FLY_IN_TIME   : float = 2.5

## How many shots to fire before going idle and retreating.
## Override per-spawn via b.sniper_enemy().prop("shot_count", N).
@export var shot_count: int = 5

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn")

@onready var _muzzle: Marker2D = $Muzzle

var _phase       : Phase               = Phase.APPROACH
var _timer       : float               = 0.0
var _shots_fired : int                 = 0
var _visualizer  : SniperAimVisualizer = null

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	score_value = 50
	rotation = PI  ## nose-down toward player; _process will hold this against EnemyPathMover

# ─────────────────────────────────────────────────────────────────────────────

## EnemyPathMover disables _physics_process on the actor — use _process instead.
func _process(delta: float) -> void:
	match _phase:
		Phase.APPROACH : _phase_approach(delta)
		Phase.AIM      : _phase_aim(delta)
		Phase.LOCK     : _phase_lock(delta)
		Phase.FIRE     : _phase_fire()
		Phase.IDLE     : pass  ## EnemyPathMover's exit step drives retreat

# ─── APPROACH ─────────────────────────────────────────────────────────────────

func _phase_approach(delta: float) -> void:
	## Keep sprite facing the player (nose-down) the whole way in.
	## EnemyPathMover sets rotation=0 in _physics_process (nose-up per its
	## sprite convention); we override it here since _process runs last.
	rotation = PI
	_timer += delta
	if _timer >= FLY_IN_TIME:
		_begin_aim()

# ─── AIM ─────────────────────────────────────────────────────────────────────

func _begin_aim() -> void:
	_phase = Phase.AIM
	_timer = 0.0
	## initial_angles left empty → SniperAimVisualizer uses single-line mode.
	_visualizer = SniperAimVisualizer.new()
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
	if _shots_fired < shot_count:
		_begin_aim()   ## fire again
	else:
		_phase = Phase.IDLE   ## done — let EnemyPathMover retreat us

# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _track_player(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player_pos := (players[0] as Node2D).global_position
	var dir := (player_pos - global_position).normalized()
	## atan2(dir.x, -dir.y) makes Vector2.UP.rotated(result) point at the target.
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
