# assault/scenes/enemies/drone_interceptor/drone_interceptor.gd
class_name DroneInterceptor
extends BaseEnemy

## Kamikaze pursuit unit. Orbits the player briefly, then locks direction and
## commits to a one-way dash — exploding on contact with the player.
##
## State machine:
##   ENTER — fly toward player until within orbit_radius.
##   ORBIT — circle the player for 1–2 seconds, then trigger DASH.
##   DASH  — lock direction to predicted player position, fly at dash_speed
##            indefinitely. Freed by off-screen check. Kamikaze on contact.
##
## No EnemyPathMover — movement is fully self-managed in _physics_process.
## Spawn with b.drone_interceptor().at(x, y) — no .move() needed.

@export var config: DroneInterceptorConfig = preload(
		"res://assault/scenes/enemies/drone_interceptor/drone_interceptor_config.tres")

enum Phase { ENTER, ORBIT, DASH }

# ── Tuning — copied from config in _ready ────────────────────────────────────
var _orbit_radius         : float = 130.0
var _orbit_speed          : float = 1.8
var _approach_speed       : float = 200.0
var _orbit_correct_speed  : float = 160.0
var _dash_speed           : float = 480.0
var _dash_prediction_time : float = 0.2

# ── Runtime state ─────────────────────────────────────────────────────────────
var _phase        : Phase   = Phase.ENTER
var _orbit_angle  : float   = 0.0
var _dash_timer   : float   = 0.0
var _dash_direction: Vector2 = Vector2.ZERO

const ROTATION_LERP : float = 7.0

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
		_dash_prediction_time    = config.dash_prediction_time

	## Stagger orbit angle and first dash timer so groups don't behave identically.
	_orbit_angle = randf_range(0.0, TAU)
	_dash_timer  = randf_range(1.0, 2.0)

# ─────────────────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	var player := _get_player()

	match _phase:
		Phase.ENTER : _phase_enter(delta, player)
		Phase.ORBIT : _phase_orbit(delta, player)
		Phase.DASH  : _phase_dash(delta)

	match _phase:
		Phase.ENTER, Phase.ORBIT:
			if player:
				_face_target(delta, player.global_position)
		Phase.DASH:
			_face_direction(delta, _dash_direction)

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
	_orbit_angle += _orbit_speed * delta
	var orbit_target := player.global_position \
			+ Vector2.RIGHT.rotated(_orbit_angle) * _orbit_radius
	var to_target    := orbit_target - global_position
	var dist         := to_target.length()
	var speed        := clampf(dist * 4.0, 60.0, _orbit_correct_speed)
	velocity = to_target.normalized() * speed

# ─── DASH ─────────────────────────────────────────────────────────────────────

func _begin_dash(player: Node2D) -> void:
	_phase = Phase.DASH
	var predicted_pos: Vector2
	if player and player is CharacterBody2D:
		predicted_pos = player.global_position \
				+ (player as CharacterBody2D).velocity * _dash_prediction_time
	elif player:
		predicted_pos = player.global_position
	else:
		predicted_pos = global_position + Vector2(0.0, 200.0)
	_dash_direction = (predicted_pos - global_position).normalized()

func _phase_dash(_delta: float) -> void:
	velocity = _dash_direction * _dash_speed
	_check_off_screen()

func _check_off_screen() -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var vp     := get_viewport().get_visible_rect().size
	var margin := 80.0
	var pos    := global_position
	if pos.y > cam.global_position.y + vp.y * 0.5 + margin \
			or pos.y < cam.global_position.y - vp.y * 0.5 - margin \
			or pos.x > cam.global_position.x + vp.x * 0.5 + margin \
			or pos.x < cam.global_position.x - vp.x * 0.5 - margin:
		queue_free()

# ─── CONTACT KILL ─────────────────────────────────────────────────────────────

## Override: collision_mask = 128 (player HurtBox) so we detect contact and kamikaze.
func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	var hb := HitBox.new()
	hb.collision_layer = 256
	hb.collision_mask  = 128   # player HurtBox — fires area_entered on contact
	hb.damage = config.collision_damage if config else 30
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	hb.area_entered.connect(_on_contact_hit)
	add_child(hb)

func _on_contact_hit(_area: Area2D) -> void:
	## Guard against double-firing before queue_free processes.
	if health.current_health > 0:
		health.set_health(0)

# ─── HELPERS ──────────────────────────────────────────────────────────────────

func _get_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D

func _face_target(delta: float, target_pos: Vector2) -> void:
	var dir        := (target_pos - global_position).normalized()
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)

func _face_direction(delta: float, dir: Vector2) -> void:
	if dir.length_squared() < 0.001:
		return
	var target_rot := atan2(dir.x, -dir.y)
	rotation = lerp_angle(rotation, target_rot, delta * ROTATION_LERP)
