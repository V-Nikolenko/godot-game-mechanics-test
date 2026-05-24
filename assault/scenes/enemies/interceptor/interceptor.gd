# assault/scenes/enemies/interceptor/interceptor.gd
class_name Interceptor
extends BaseEnemy

## Persistent pursuit unit that orbits the player, fires while circling,
## and periodically dashes toward the player's predicted position.
##
## State machine:
##   ENTER      — fly toward player until within orbit_radius.
##   ORBIT      — circle the player; fires via AttackController; counts down to DASH.
##   DASH       — burst at high speed toward the player's predicted position.
##   REACQUIRE  — fly back into orbit after the dash displacement.
##   RETREAT    — triggered after MAX_LIFETIME; fly off-screen top, then queue_free.
##
## Movement is fully self-managed (_physics_process). No EnemyPathMover is used.
## Spawn with b.interceptor().at(x, y) — no .move() needed.

@export var config: InterceptorConfig = preload(
		"res://assault/scenes/enemies/interceptor/interceptor_config.tres")

enum Phase { ENTER, ORBIT, DASH, REACQUIRE, RETREAT }

# ── Tuning — copied from config in _ready ─────────────────────────────────────
var _orbit_radius         : float = 200.0
var _orbit_speed          : float = 1.4
var _approach_speed       : float = 220.0
var _orbit_correct_speed  : float = 170.0
var _dash_speed           : float = 440.0
var _dash_duration        : float = 0.35
var _dash_interval        : float = 3.5
var _dash_prediction_time : float = 0.28

# ── Runtime state ─────────────────────────────────────────────────────────────
var _phase               : Phase   = Phase.ENTER
var _orbit_angle         : float   = 0.0
var _dash_timer          : float   = 0.0
var _dash_duration_timer : float   = 0.0
var _lifetime_timer      : float   = 0.0
var _dash_direction      : Vector2 = Vector2.ZERO

const MAX_LIFETIME  : float = 45.0
const ROTATION_LERP : float = 6.0

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _bullet_pool       : BulletPool
var _attack_controller : AttackController

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health        = config.max_health
		health.current_health    = config.max_health
		score_value              = config.score_value
		_orbit_radius            = config.orbit_radius
		_orbit_speed             = config.orbit_speed
		_approach_speed          = config.approach_speed
		_orbit_correct_speed     = config.orbit_correct_speed
		_dash_speed              = config.dash_speed
		_dash_duration           = config.dash_duration
		_dash_interval           = config.dash_interval
		_dash_prediction_time    = config.dash_prediction_time

	_bullet_pool = BulletPool.new()
	_bullet_pool.bullet_scene = _BULLET_SCENE
	## Arena diagonal ≈ 1047 px / 290 px/s / 0.55 s ≈ 6.5 → 14 is comfortable.
	_bullet_pool.pool_size = 14
	add_child(_bullet_pool)

	var pattern              := AimedAttackPattern.new()
	pattern.fire_interval    = config.fire_interval if config else 0.55
	pattern.bullet_damage    = config.bullet_damage if config else 10
	pattern.bullet_speed     = config.bullet_speed  if config else 290.0
	pattern.aim_at_player    = true
	pattern.spawn_offset     = Vector2(0.0, 10.0)
	pattern.start_delay      = 1.2  ## Don't fire until the enemy has entered orbit.

	_attack_controller             = AttackController.new()
	_attack_controller.pattern     = pattern
	_attack_controller.bullet_pool = _bullet_pool
	add_child(_attack_controller)

	## Stagger orbit starting angle and first dash so paired interceptors
	## don't behave identically.
	_orbit_angle = randf_range(0.0, TAU)
	_dash_timer  = randf_range(_dash_interval * 0.5, _dash_interval)

# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_lifetime_timer += delta
	if _lifetime_timer >= MAX_LIFETIME and _phase != Phase.RETREAT:
		_begin_retreat()

	var player := _get_player()

	match _phase:
		Phase.ENTER     : _phase_enter(delta, player)
		Phase.ORBIT     : _phase_orbit(delta, player)
		Phase.DASH      : _phase_dash(delta)
		Phase.REACQUIRE : _phase_reacquire(delta, player)
		Phase.RETREAT   : _phase_retreat(delta)

	# Rotation — each phase chooses what to face
	if player:
		match _phase:
			Phase.ENTER, Phase.ORBIT, Phase.REACQUIRE:
				_face_target(delta, player.global_position)
			Phase.DASH:
				_face_direction(delta, _dash_direction)
	if _phase == Phase.RETREAT:
		_face_direction(delta, Vector2.UP)

	move_and_slide()

# ─── ENTER ────────────────────────────────────────────────────────────────────

func _phase_enter(_delta: float, player: Node2D) -> void:
	if not player:
		velocity = Vector2.ZERO
		return
	var to_player := player.global_position - global_position
	if to_player.length() <= _orbit_radius:
		_phase = Phase.ORBIT
		return
	velocity = to_player.normalized() * _approach_speed

# ─── ORBIT ────────────────────────────────────────────────────────────────────

func _phase_orbit(delta: float, player: Node2D) -> void:
	_dash_timer -= delta
	if _dash_timer <= 0.0:
		_begin_dash(player)
		return

	if not player:
		velocity = Vector2.ZERO
		return

	## Advance the orbit anchor angle around the player.
	_orbit_angle += _orbit_speed * delta

	var orbit_target := player.global_position \
			+ Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
	var to_target    := orbit_target - global_position
	var dist         := to_target.length()

	## Proportional speed: fast correction when far off, gentle when close.
	var speed := clampf(dist * 4.0, 60.0, _orbit_correct_speed)
	velocity = to_target.normalized() * speed

# ─── DASH ─────────────────────────────────────────────────────────────────────

func _begin_dash(player: Node2D) -> void:
	_phase = Phase.DASH
	_dash_duration_timer = _dash_duration

	var predicted_pos: Vector2
	if player and player is CharacterBody2D:
		predicted_pos = player.global_position \
				+ (player as CharacterBody2D).velocity * _dash_prediction_time
	elif player:
		predicted_pos = player.global_position
	else:
		## No player available — dash downward as a fallback.
		predicted_pos = global_position + Vector2(0.0, 200.0)

	_dash_direction = (predicted_pos - global_position).normalized()

func _phase_dash(delta: float) -> void:
	_dash_duration_timer -= delta
	velocity = _dash_direction * _dash_speed
	if _dash_duration_timer <= 0.0:
		_phase = Phase.REACQUIRE

# ─── REACQUIRE ────────────────────────────────────────────────────────────────

func _phase_reacquire(_delta: float, player: Node2D) -> void:
	if not player:
		velocity = Vector2.ZERO
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > _orbit_radius * 1.5:
		## Still too far — steer back toward the orbit anchor.
		var orbit_target := player.global_position \
				+ Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
		velocity = (orbit_target - global_position).normalized() * _approach_speed
	else:
		## Close enough — re-enter orbit and reset the dash cooldown.
		_phase = Phase.ORBIT
		_dash_timer = _dash_interval

# ─── RETREAT ──────────────────────────────────────────────────────────────────

func _begin_retreat() -> void:
	_phase = Phase.RETREAT
	## Stop firing while retreating.
	if is_instance_valid(_attack_controller):
		_attack_controller.set_process(false)

func _phase_retreat(_delta: float) -> void:
	velocity = Vector2(0.0, -_approach_speed * 1.2)
	_check_off_screen_top()

func _check_off_screen_top() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var vs := get_viewport().get_visible_rect().size
	if global_position.y < cam.global_position.y - vs.y * 0.5 - 80.0:
		queue_free()

# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D

func _face_target(delta: float, target_pos: Vector2) -> void:
	var dir        := (target_pos - global_position).normalized()
	## atan2(dir.x, -dir.y) maps a world direction to the rotation that makes
	## Vector2.UP (the sprite's natural forward) point at the target.
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)

func _face_direction(delta: float, dir: Vector2) -> void:
	if dir.length_squared() < 0.001:
		return
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
