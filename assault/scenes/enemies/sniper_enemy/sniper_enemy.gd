# assault/scenes/enemies/sniper_enemy/sniper_enemy.gd
class_name SniperEnemy
extends BaseEnemy

## A stationary sniper that:
##   1. Flies into the viewport from above (FLY_IN)
##   2. Hovers near the top of the screen (AIM)
##      - Rotates to track the player
##      - Shows a SniperAimVisualizer cone that converges over 2 s
##   3. Locks on for 0.5 s — rotation freezes, lines fully converged (LOCK)
##   4. Fires one enemy_sniper_bullet in the aimed direction (FIRE)
##   5. Retreats upward off-screen (FLY_OUT)

enum Phase { FLY_IN, AIM, LOCK, FIRE, FLY_OUT }

const FLY_IN_SPEED  : float = 150.0
const AIM_DURATION  : float = 2.0
const LOCK_DURATION : float = 0.5
const FLY_OUT_SPEED : float = 220.0
## How quickly (lerp factor) the enemy rotates to track the player.
const ROTATION_LERP : float = 2.5
## Fraction of viewport height from the top at which the enemy hovers.
const HOVER_Y_FRAC  : float = 0.28

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn")

@onready var _muzzle: Marker2D = $Muzzle

var _phase      : Phase               = Phase.FLY_IN
var _timer      : float               = 0.0
var _hover_y    : float               = 0.0
var _visualizer : SniperAimVisualizer = null

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	score_value = 50
	rotation = PI  ## face downward toward the player from entry
	_compute_hover_y()

func _compute_hover_y() -> void:
	var cam := get_viewport().get_camera_2d()
	var vs  := get_viewport().get_visible_rect().size
	if cam:
		_hover_y = cam.global_position.y - vs.y * 0.5 + vs.y * HOVER_Y_FRAC
	else:
		_hover_y = global_position.y + 120.0

# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	match _phase:
		Phase.FLY_IN : _phase_fly_in(delta)
		Phase.AIM    : _phase_aim(delta)
		Phase.LOCK   : _phase_lock(delta)
		Phase.FIRE   : _phase_fire()
		Phase.FLY_OUT: _phase_fly_out(delta)

# ─── FLY_IN ──────────────────────────────────────────────────────────────────

func _phase_fly_in(_delta: float) -> void:
	if global_position.y < _hover_y:
		velocity = Vector2(0.0, FLY_IN_SPEED)
		move_and_slide()
	if global_position.y >= _hover_y:
		global_position.y = _hover_y
		velocity = Vector2.ZERO
		_begin_aim()

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
	## Connect expired → queue_free so the bullet self-destructs when it
	## hits the player or leaves the arena (no BulletPool needed for a
	## one-shot-per-cycle weapon).
	bullet.expired.connect(bullet.queue_free)
	bullet.set_direction(Vector2.UP.rotated(rotation))
	get_parent().add_child(bullet)
	bullet.global_position = _muzzle.global_position

	if is_instance_valid(_visualizer):
		_visualizer.queue_free()
	_visualizer = null

	_phase = Phase.FLY_OUT
	_timer = 0.0

# ─── FLY_OUT ──────────────────────────────────────────────────────────────────

func _phase_fly_out(_delta: float) -> void:
	velocity = Vector2(0.0, -FLY_OUT_SPEED)
	move_and_slide()
	_check_off_screen_top()

func _check_off_screen_top() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if global_position.y < cam.global_position.y - vs.y * 0.5 - 80.0:
		queue_free()

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
