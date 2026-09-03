# assault/scenes/enemies/interceptor/interceptor.gd
class_name Interceptor
extends BaseEnemy

## Flying Gatling gunship. No self-managed movement AI.
## Movement is fully delegated to EnemyPathMover via WaveBuilder .move().
##
## Typical usages:
##   b.interceptor().at(x, y).move(b.straight(200))       — strafing run
##   b.interceptor().at(x, y).move(b.player_focus(240))   — locks on and flies through

@export var config: InterceptorConfig = preload(
		"res://assault/scenes/enemies/interceptor/interceptor_config.tres")

const _BULLET_SCENE: PackedScene = preload(
		"res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _bullet_pool       : BulletPool
var _attack_controller : AttackController

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health     = config.max_health
		health.current_health = config.max_health
		score_value           = config.score_value

	_bullet_pool            = BulletPool.new()
	_bullet_pool.bullet_scene = _BULLET_SCENE
	## pool_size: at 0.09 s interval and ~1.5 s effective range → ceil(1.5/0.09)+buffer = 20.
	_bullet_pool.pool_size  = 20
	add_child(_bullet_pool)

	var pattern              := GatlingAttackPattern.new()
	pattern.fire_interval    = config.fire_interval if config else 0.09
	pattern.bullet_damage    = config.bullet_damage if config else 4
	pattern.bullet_speed     = config.bullet_speed  if config else 220.0
	pattern.spread_angle     = config.spread_angle  if config else 0.08

	_attack_controller             = AttackController.new()
	_attack_controller.pattern     = pattern
	_attack_controller.bullet_pool = _bullet_pool
	add_child(_attack_controller)
